/**
 * @file AasdkSession.cpp
 * @brief 制御チャネルの進行（バージョン → SSL → 認証 → サービス探索）とセッションの終了処理。
 *
 * 確認できている根拠:
 *  - 送信/受信 API と暗号化種別: aasdk/src/Channel/Control/ControlServiceChannel.cpp
 *  - ハンドシェイクは Cryptor::doHandshake() が false の間 readHandshakeBuffer() を送り続け、
 *    true になったら AuthResponse を送る: aasdk/src/Messenger/Cryptor.cpp
 *  - Messenger::stop() は受信キューを空にするだけ。保留中の Promise は transport->stop() による
 *    USB 転送キャンセル経由で reject され、各チャネルの onChannelError に伝わる
 *
 * @note 実機(スマートフォン)では未検証。
 */
#include "AasdkSession.h"

#include <aasdk/Messenger/Cryptor.hpp>
#include <aasdk/Messenger/MessageInStream.hpp>
#include <aasdk/Messenger/MessageOutStream.hpp>
#include <aasdk/Messenger/Messenger.hpp>
#include <aasdk/Error/ErrorCode.hpp>
#include <aasdk/Transport/SSLWrapper.hpp>
#include <aasdk/Transport/USBTransport.hpp>

#include <aap_protobuf/service/control/message/AudioFocusNotification.pb.h>
#include <aap_protobuf/service/control/message/AudioFocusRequest.pb.h>
#include <aap_protobuf/service/control/message/AudioFocusRequestType.pb.h>
#include <aap_protobuf/service/control/message/AudioFocusStateType.pb.h>
#include <aap_protobuf/service/control/message/AuthResponse.pb.h>
#include <aap_protobuf/service/control/message/ByeByeResponse.pb.h>
#include <aap_protobuf/service/control/message/DriverPosition.pb.h>
#include <aap_protobuf/service/control/message/HeadUnitInfo.pb.h>
#include <aap_protobuf/service/control/message/NavFocusNotification.pb.h>
#include <aap_protobuf/service/control/message/NavFocusType.pb.h>
#include <aap_protobuf/service/control/message/PingResponse.pb.h>
#include <aap_protobuf/service/control/message/ServiceDiscoveryRequest.pb.h>
#include <aap_protobuf/service/control/message/ServiceDiscoveryResponse.pb.h>
#include <aap_protobuf/shared/MessageStatus.pb.h>

#include "AasdkConfig.h"

namespace opencruise::aa {

namespace proto = aap_protobuf;

namespace {

const char *aasdkErrorCodeName(aasdk::error::ErrorCode code) {
    using aasdk::error::ErrorCode;
    switch (code) {
    case ErrorCode::NONE: return "NONE";
    case ErrorCode::USB_CLAIM_INTERFACE: return "USB_CLAIM_INTERFACE";
    case ErrorCode::USB_INVALID_CONFIG_DESCRIPTOR: return "USB_INVALID_CONFIG_DESCRIPTOR";
    case ErrorCode::USB_OBTAIN_INTERFACE_DESCRIPTOR: return "USB_OBTAIN_INTERFACE_DESCRIPTOR";
    case ErrorCode::USB_EMPTY_INTERFACES: return "USB_EMPTY_INTERFACES";
    case ErrorCode::USB_INVALID_DEVICE_ENDPOINTS: return "USB_INVALID_DEVICE_ENDPOINTS";
    case ErrorCode::USB_INVALID_TRANSFER_METHOD: return "USB_INVALID_TRANSFER_METHOD";
    case ErrorCode::USB_TRANSFER_ALLOCATION: return "USB_TRANSFER_ALLOCATION";
    case ErrorCode::USB_LIST_DEVICES: return "USB_LIST_DEVICES";
    case ErrorCode::USB_OBTAIN_CONFIG_DESCRIPTOR: return "USB_OBTAIN_CONFIG_DESCRIPTOR";
    case ErrorCode::USB_TRANSFER: return "USB_TRANSFER";
    case ErrorCode::DATA_SINK_COMMIT_OVERFLOW: return "DATA_SINK_COMMIT_OVERFLOW";
    case ErrorCode::DATA_SINK_CONSUME_UNDERFLOW: return "DATA_SINK_CONSUME_UNDERFLOW";
    case ErrorCode::USB_AOAP_PROTOCOL_VERSION: return "USB_AOAP_PROTOCOL_VERSION";
    case ErrorCode::USB_AOAP_DEVICE_NOT_FOUND: return "USB_AOAP_DEVICE_NOT_FOUND";
    case ErrorCode::SSL_READ_CERTIFICATE: return "SSL_READ_CERTIFICATE";
    case ErrorCode::SSL_READ_PRIVATE_KEY: return "SSL_READ_PRIVATE_KEY";
    case ErrorCode::SSL_METHOD: return "SSL_METHOD";
    case ErrorCode::SSL_CONTEXT_CREATION: return "SSL_CONTEXT_CREATION";
    case ErrorCode::SSL_USE_CERTIFICATE: return "SSL_USE_CERTIFICATE";
    case ErrorCode::SSL_USE_PRIVATE_KEY: return "SSL_USE_PRIVATE_KEY";
    case ErrorCode::SSL_HANDLER_CREATION: return "SSL_HANDLER_CREATION";
    case ErrorCode::SSL_READ_BIO_CREATION: return "SSL_READ_BIO_CREATION";
    case ErrorCode::SSL_WRITE_BIO_CREATION: return "SSL_WRITE_BIO_CREATION";
    case ErrorCode::SSL_HANDSHAKE: return "SSL_HANDSHAKE";
    case ErrorCode::SSL_WRITE: return "SSL_WRITE";
    case ErrorCode::SSL_READ: return "SSL_READ";
    case ErrorCode::SSL_BIO_READ: return "SSL_BIO_READ";
    case ErrorCode::SSL_BIO_WRITE: return "SSL_BIO_WRITE";
    case ErrorCode::MESSENGER_INTERTWINED_CHANNELS: return "MESSENGER_INTERTWINED_CHANNELS";
    case ErrorCode::OPERATION_ABORTED: return "OPERATION_ABORTED";
    case ErrorCode::OPERATION_IN_PROGRESS: return "OPERATION_IN_PROGRESS";
    case ErrorCode::PARSE_PAYLOAD: return "PARSE_PAYLOAD";
    case ErrorCode::TCP_TRANSFER: return "TCP_TRANSFER";
    }
    return "UNKNOWN";
}

std::string describeAasdkError(const aasdk::error::Error &error) {
    return std::string(aasdkErrorCodeName(error.getCode())) + " (aasdk_code=" +
           std::to_string(static_cast<std::uint32_t>(error.getCode())) + ", native_code=" +
           std::to_string(error.getNativeCode()) + "): " + error.what();
}

} // namespace

/**
 * @brief USB 転送〜Messenger〜制御チャネルを組み立てる。
 */
AasdkSession::AasdkSession(boost::asio::io_service &ioService, aasdk::usb::IAOAPDevice::Pointer aoapDevice,
                           SessionCallbacks callbacks)
    : strand_(std::make_shared<boost::asio::io_service::strand>(ioService)), callbacks_(std::move(callbacks)) {
    transport_ = std::make_shared<aasdk::transport::USBTransport>(ioService, std::move(aoapDevice));

    // Cryptor::deinit() は SSL* を nullptr にするため、まだ encrypt()/decrypt() を呼ぶ者がいる間に
    // 呼ぶとクラッシュし得る。最後の参照者が消えるときに deinit する。
    cryptor_ = std::shared_ptr<aasdk::messenger::Cryptor>(
        new aasdk::messenger::Cryptor(std::make_shared<aasdk::transport::SSLWrapper>()),
        [](aasdk::messenger::Cryptor *cryptor) {
            try {
                cryptor->deinit();
            } catch (...) {
            }
            delete cryptor;
        });

    auto inStream = std::make_shared<aasdk::messenger::MessageInStream>(ioService, transport_, cryptor_);
    auto outStream = std::make_shared<aasdk::messenger::MessageOutStream>(ioService, transport_, cryptor_);
    messenger_ = std::make_shared<aasdk::messenger::Messenger>(ioService, std::move(inStream), std::move(outStream));
    controlChannel_ = std::make_shared<aasdk::channel::control::ControlServiceChannel>(*strand_, messenger_);
}

/**
 * @brief SSL を初期化し、映像チャネルと制御チャネルの受信を始めてバージョン要求を送る。
 */
void AasdkSession::start() {
    auto self = shared_from_this();
    strand_->dispatch([self]() {
        self->log("USB/AOAP セッション開始");
        try {
            self->cryptor_->init();
            self->log("TLS コンテキスト初期化完了");
        } catch (const aasdk::error::Error &e) {
            self->doTerminate(std::string("SSL 初期化に失敗: ") + e.what());
            return;
        }

        // 映像ハンドラからの通知は、セッション終了後に届いても無視する（弱参照 + finished_ 判定）
        std::weak_ptr<AasdkSession> weak = self;
        AasdkVideoHandler::Callbacks videoCallbacks;
        videoCallbacks.onVideoData = [weak](const std::uint8_t *data, std::size_t size) {
            if (auto s = weak.lock(); s && !s->finished_ && s->callbacks_.onVideoData) {
                s->callbacks_.onVideoData(data, size);
            }
        };
        videoCallbacks.onStateChanged = [weak](LinkState state, const std::string &detail) {
            if (auto s = weak.lock(); s && !s->finished_ && s->callbacks_.onStateChanged) {
                s->callbacks_.onStateChanged(state, detail);
            }
        };
        videoCallbacks.onFatalError = [weak](const std::string &reason) {
            if (auto s = weak.lock()) {
                s->terminate(reason);
            }
        };
        videoCallbacks.onLog = [weak](const std::string &message) {
            if (auto s = weak.lock()) {
                s->log(message);
            }
        };

        self->videoHandler_ =
            std::make_shared<AasdkVideoHandler>(self->strand_, self->messenger_, std::move(videoCallbacks));
        self->videoHandler_->start();

        // センサー/入力/System audio。スマートフォン(Android Auto)はこれらが Service Discovery に無いと
        // 接続を拒否することがある(「通信エラー: 2」)。いずれも致命的エラーはセッション終了として扱う。
        auto onFatal = [weak](const std::string &reason) {
            if (auto s = weak.lock()) {
                s->terminate(reason);
            }
        };
        auto onLog = [weak](const std::string &message) {
            if (auto s = weak.lock()) {
                s->log(message);
            }
        };

        AasdkSensorHandler::Callbacks sensorCallbacks;
        sensorCallbacks.onFatalError = onFatal;
        sensorCallbacks.onLog = onLog;
        self->sensorHandler_ =
            std::make_shared<AasdkSensorHandler>(self->strand_, self->messenger_, std::move(sensorCallbacks));
        self->sensorHandler_->start();

        AasdkInputHandler::Callbacks inputCallbacks;
        inputCallbacks.onFatalError = onFatal;
        inputCallbacks.onLog = onLog;
        self->inputHandler_ =
            std::make_shared<AasdkInputHandler>(self->strand_, self->messenger_, std::move(inputCallbacks));
        self->inputHandler_->start();

        AasdkSystemAudioHandler::Callbacks audioCallbacks;
        audioCallbacks.onFatalError = onFatal;
        audioCallbacks.onLog = onLog;
        self->systemAudioHandler_ = std::make_shared<AasdkSystemAudioHandler>(self->strand_, self->messenger_,
                                                                              std::move(audioCallbacks));
        self->systemAudioHandler_->start();

        self->controlChannel_->receive(self);
        self->log("VersionRequest 送信開始");
        self->controlChannel_->sendVersionRequest(self->makeSendPromise("VersionRequest"));
    });
}

/**
 * @brief アプリ側の都合でセッションを終了する。
 */
void AasdkSession::stop() { terminate("アプリが停止要求を出しました"); }

/**
 * @brief バージョン応答。問題なければ SSL ハンドシェイクの最初のデータ(ClientHello)を送る。
 *
 * aasdk は応答の status を MessageStatus へ単純キャストする(0xFFFF が -1 にならず 65535 になる)ため、
 * 「不一致」を特定の値で判定せず「STATUS_SUCCESS 以外は失敗」として扱う。
 * major/minor は aasdk がエンディアン変換せずに渡してくるため、ログには生値として出す。
 */
void AasdkSession::onVersionResponse(uint16_t majorCode, uint16_t minorCode, proto::shared::MessageStatus status) {
    log("バージョン応答 (経過 " + std::to_string(elapsedMs()) + " ms, 生値 major=" +
        std::to_string(majorCode) + ", minor=" + std::to_string(minorCode) +
        ", status=" + std::to_string(static_cast<int>(status)) + ")");

    if (status != proto::shared::MessageStatus::STATUS_SUCCESS) {
        terminate("プロトコルバージョンが一致しません (status=" + std::to_string(static_cast<int>(status)) + ")");
        return;
    }

    try {
        cryptor_->doHandshake(); // 初回は ClientHello を生成するだけで false が返る
        controlChannel_->sendHandshake(cryptor_->readHandshakeBuffer(), makeSendPromise("Handshake"));
        controlChannel_->receive(shared_from_this());
    } catch (const aasdk::error::Error &e) {
        terminate(std::string("SSL ハンドシェイク開始に失敗: ") + e.what());
    }
}

/**
 * @brief SSL ハンドシェイクの受信データを処理し、未完了なら続きを送り、完了なら認証完了を送る。
 */
void AasdkSession::onHandshake(const aasdk::common::DataConstBuffer &payload) {
    log("TLS ハンドシェイクデータ受信 (経過 " + std::to_string(elapsedMs()) + " ms)");
    try {
        cryptor_->writeHandshakeBuffer(payload);

        if (!cryptor_->doHandshake()) {
            log("TLS ハンドシェイク継続データを送信");
            controlChannel_->sendHandshake(cryptor_->readHandshakeBuffer(), makeSendPromise("Handshake"));
        } else {
            log("[session] SSL ハンドシェイク完了 (経過 " + std::to_string(elapsedMs()) +
                " ms) → 認証完了を送信します");
            proto::service::control::message::AuthResponse authResponse;
            authResponse.set_status(static_cast<std::int32_t>(proto::shared::MessageStatus::STATUS_SUCCESS));
            controlChannel_->sendAuthComplete(authResponse, makeSendPromise("AuthComplete"));
        }
        controlChannel_->receive(shared_from_this());
    } catch (const aasdk::error::Error &e) {
        terminate(std::string("SSL ハンドシェイクに失敗: ") + e.what());
    }
}

/**
 * @brief サービス探索要求に、車載機の情報と 映像/センサー/入力/System audio を載せた応答を返す。
 *
 * OpenAuto の ServiceFactory と同じ最小構成(Video + Sensor + Input + System audio)。
 * 映像だけを申告した場合、スマートフォンは ChannelOpenRequest を一切送らず
 * 「通信エラー: 2」で接続を打ち切った(実機ログで確認)。
 */
void AasdkSession::onServiceDiscoveryRequest(
    const proto::service::control::message::ServiceDiscoveryRequest &request) {
    log("[session] サービス探索要求を受信 (経過 " + std::to_string(elapsedMs()) + " ms)" +
        (request.has_device_name() ? " (端末名: " + request.device_name() + ")" : std::string()));

    proto::service::control::message::ServiceDiscoveryResponse response;
    response.set_display_name(config::kDisplayName);
    // サポートプローブは行わず、OpenAuto と同じ Ping の監視値を通知する。
    response.set_probe_for_support(false);
    auto *ping = response.mutable_connection_configuration()->mutable_ping_configuration();
    ping->set_tracked_ping_count(5);
    ping->set_timeout_ms(3000);
    ping->set_interval_ms(1000);
    ping->set_high_latency_threshold_ms(200);
    // 日本は右ハンドル
    response.set_driver_position(proto::service::control::message::DriverPosition::DRIVER_POSITION_RIGHT);

    auto *info = response.mutable_headunit_info();
    info->set_make(config::kHeadUnitMake);
    info->set_model(config::kHeadUnitModel);
    info->set_head_unit_make(config::kHeadUnitMake);
    info->set_head_unit_model(config::kHeadUnitModel);
    info->set_year(config::kVehicleYear);
    info->set_vehicle_id(config::kVehicleId);
    info->set_head_unit_software_build(config::kHeadUnitSoftwareBuild);
    info->set_head_unit_software_version(config::kHeadUnitSoftwareVersion);

    // チャネルの追加順は OpenAuto(ServiceFactory)に合わせる: 音声 → 映像 → センサー → 入力
    systemAudioHandler_->fillFeatures(response);
    videoHandler_->fillFeatures(response);
    sensorHandler_->fillFeatures(response);
    inputHandler_->fillFeatures(response);
    log("サービス探索応答を作成 (チャネル数=" + std::to_string(response.channels_size()) + ")");

    auto promise = aasdk::channel::SendPromise::defer(*strand_);
    promise->then(
        [self = shared_from_this()]() {
            self->log("サービス探索応答の送信完了");
            if (!self->finished_ && self->callbacks_.onStateChanged) {
                self->callbacks_.onStateChanged(LinkState::Connected, "接続済み（映像の開始を待っています）");
            }
        },
        [self = shared_from_this()](const aasdk::error::Error &e) {
            self->terminate(std::string("サービス探索応答の送信に失敗: ") + e.what());
        });
    controlChannel_->sendServiceDiscoveryResponse(response, std::move(promise));
    controlChannel_->receive(shared_from_this());
}

/**
 * @brief 音声フォーカス要求。OpenAuto と同じく、解放要求なら LOSS、それ以外は GAIN を返す。
 */
void AasdkSession::onAudioFocusRequest(const proto::service::control::message::AudioFocusRequest &request) {
    using proto::service::control::message::AudioFocusRequestType;
    using proto::service::control::message::AudioFocusStateType;

    proto::service::control::message::AudioFocusNotification response;
    response.set_focus_state(request.audio_focus_type() == AudioFocusRequestType::AUDIO_FOCUS_RELEASE
                                 ? AudioFocusStateType::AUDIO_FOCUS_STATE_LOSS
                                 : AudioFocusStateType::AUDIO_FOCUS_STATE_GAIN);
    controlChannel_->sendAudioFocusResponse(response, makeSendPromise("AudioFocusNotification"));
    controlChannel_->receive(shared_from_this());
}

/**
 * @brief スマートフォンからの切断要求。応答を返してからセッションを終了する。
 */
void AasdkSession::onByeByeRequest(const proto::service::control::message::ByeByeRequest &) {
    log("スマートフォンから切断要求を受信");
    auto promise = aasdk::channel::SendPromise::defer(*strand_);
    promise->then([self = shared_from_this()]() { self->terminate("スマートフォンからの切断要求"); },
                  [self = shared_from_this()](const aasdk::error::Error &) {
                      self->terminate("スマートフォンからの切断要求（応答送信は失敗）");
                  });
    controlChannel_->sendShutdownResponse(proto::service::control::message::ByeByeResponse(), std::move(promise));
}

/**
 * @brief 切断要求(こちらから送った場合)への応答。セッションを終了する。
 */
void AasdkSession::onByeByeResponse(const proto::service::control::message::ByeByeResponse &) {
    terminate("切断応答を受信");
}

/**
 * @brief バッテリー通知は使わないので読み捨てる。
 */
void AasdkSession::onBatteryStatusNotification(const proto::service::control::message::BatteryStatusNotification &) {
    controlChannel_->receive(shared_from_this());
}

/**
 * @brief ナビゲーションフォーカス要求。スマートフォン側(PROJECTED)にフォーカスを渡す（暫定）。
 */
void AasdkSession::onNavigationFocusRequest(const proto::service::control::message::NavFocusRequestNotification &) {
    proto::service::control::message::NavFocusNotification response;
    response.set_focus_type(proto::service::control::message::NavFocusType::NAV_FOCUS_PROJECTED);
    controlChannel_->sendNavigationFocusResponse(response, makeSendPromise("NavFocusNotification"));
    controlChannel_->receive(shared_from_this());
}

/**
 * @brief 音声セッション通知は未対応。aasdk 側の応答送信 API は実装が空のため、読み捨てる。
 */
void AasdkSession::onVoiceSessionRequest(const proto::service::control::message::VoiceSessionNotification &) {
    controlChannel_->receive(shared_from_this());
}

/**
 * @brief Ping 要求に、同じタイムスタンプで応答する。
 */
void AasdkSession::onPingRequest(const proto::service::control::message::PingRequest &request) {
    proto::service::control::message::PingResponse response;
    response.set_timestamp(request.timestamp());
    controlChannel_->sendPingResponse(response, makeSendPromise("PingResponse"));
    controlChannel_->receive(shared_from_this());
}

/**
 * @brief Ping 応答。車載機側から Ping を送っていないので読み捨てる。
 */
void AasdkSession::onPingResponse(const proto::service::control::message::PingResponse &) {
    controlChannel_->receive(shared_from_this());
}

/**
 * @brief 制御チャネルのエラー（受信失敗/パース失敗/USB切断など）でセッションを終了する。
 */
void AasdkSession::onChannelError(const aasdk::error::Error &e) {
    terminate("制御チャネルエラー: " + describeAasdkError(e));
}

/**
 * @brief 送信失敗でセッションを終了する Promise を作る。
 */
aasdk::channel::SendPromise::Pointer AasdkSession::makeSendPromise(const char *what) {
    auto promise = aasdk::channel::SendPromise::defer(*strand_);
    promise->then([self = shared_from_this(), what = std::string(what)]() {
                      self->log(what + " 送信完了");
                  },
                  [self = shared_from_this(), what = std::string(what)](const aasdk::error::Error &e) {
                      self->terminate("制御チャネル送信失敗(" + what + "): " + describeAasdkError(e));
                  });
    return promise;
}

/**
 * @brief strand 上で doTerminate を実行する（どのスレッドから呼んでもよい）。
 */
void AasdkSession::terminate(const std::string &reason) {
    strand_->dispatch([self = shared_from_this(), reason]() { self->doTerminate(reason); });
}

/**
 * @brief 転送を止めて保留中の Promise を失敗させ、終了を通知する。冪等。
 *
 * Cryptor はここでは解放しない（コンストラクタのカスタムデリータ参照）。
 */
void AasdkSession::doTerminate(const std::string &reason) {
    if (finished_) {
        return;
    }
    finished_ = true;
    log("セッション終了: " + reason);

    transport_->stop();
    messenger_->stop();

    if (callbacks_.onFinished) {
        callbacks_.onFinished(reason);
    }
}

/**
 * @brief 診断ログを上位へ流す。
 */
void AasdkSession::log(const std::string &message) const {
    if (callbacks_.onLog) {
        callbacks_.onLog("[session][+" + std::to_string(elapsedMs()) + "ms] " + message);
    }
}

} // namespace opencruise::aa
