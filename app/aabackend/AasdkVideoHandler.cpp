/**
 * @file AasdkVideoHandler.cpp
 * @brief 映像チャネルの実装。プロトコル上の手順は aasdk のヘッダ/.proto から読み取ったもの。
 *
 * 確認できている根拠:
 *  - ControlMessageType/MediaMessageId と各メッセージ型: aasdk/protobuf/aap_protobuf/service/...
 *  - MEDIA_MESSAGE_CODEC_CONFIG は onMediaIndication、MEDIA_MESSAGE_DATA は
 *    onMediaWithTimestampIndication に振り分けられる: aasdk/src/Channel/MediaSink/Video/VideoMediaSinkService.cpp
 *  - receive() は 1 メッセージごとのワンショットで、ハンドラが再度呼ぶ必要がある
 *
 * @note 実機(スマートフォン)では未検証。特に max_unacked/ACK の運用、フォーカス応答の値は暫定。
 */
#include "AasdkVideoHandler.h"

#include <aap_protobuf/service/Service.pb.h>
#include <aap_protobuf/service/control/message/ChannelOpenResponse.pb.h>
#include <aap_protobuf/service/media/shared/message/Config.pb.h>
#include <aap_protobuf/service/media/shared/message/MediaCodecType.pb.h>
#include <aap_protobuf/service/media/sink/MediaSinkService.pb.h>
#include <aap_protobuf/service/media/sink/message/VideoCodecResolutionType.pb.h>
#include <aap_protobuf/service/media/sink/message/VideoConfiguration.pb.h>
#include <aap_protobuf/service/media/sink/message/VideoFrameRateType.pb.h>
#include <aap_protobuf/service/media/source/message/Ack.pb.h>
#include <aap_protobuf/service/media/video/message/VideoFocusMode.pb.h>
#include <aap_protobuf/service/media/video/message/VideoFocusNotification.pb.h>
#include <aap_protobuf/shared/MessageStatus.pb.h>

#include "AasdkConfig.h"

namespace opencruise::aa {

namespace proto = aap_protobuf;

/**
 * @brief 映像チャネルを生成する（受信ループはまだ開始しない）。
 */
AasdkVideoHandler::AasdkVideoHandler(std::shared_ptr<boost::asio::io_service::strand> strand,
                                     aasdk::messenger::IMessenger::Pointer messenger, Callbacks callbacks,
                                     StreamSettings settings)
    : strand_(std::move(strand)),
      settings_(settings.sanitized()),
      channel_(std::make_shared<aasdk::channel::mediasink::video::channel::VideoChannel>(*strand_,
                                                                                         std::move(messenger))),
      callbacks_(std::move(callbacks)) {}

/**
 * @brief 映像チャネルの受信ループを開始する。
 */
void AasdkVideoHandler::start() { channel_->receive(shared_from_this()); }

/**
 * @brief ServiceDiscoveryResponse に H.264 / 設定された解像度・fps の映像サービスを追記する。
 */
void AasdkVideoHandler::fillFeatures(proto::service::control::message::ServiceDiscoveryResponse &response) {
    using proto::service::media::shared::message::MediaCodecType;
    using proto::service::media::sink::message::VideoCodecResolutionType;
    using proto::service::media::sink::message::VideoFrameRateType;

    auto *service = response.add_channels();
    // ChannelId の数値がそのままフレームヘッダのチャネル番号(FrameHeader.cpp)なので、サービスIDにも使う
    service->set_id(static_cast<std::int32_t>(channel_->getId()));

    auto *sink = service->mutable_media_sink_service();
    sink->set_available_type(MediaCodecType::MEDIA_CODEC_VIDEO_H264_BP);
    sink->set_available_while_in_call(true);

    auto *video = sink->add_video_configs();
    switch (settings_.resolution) {
    case 1: video->set_codec_resolution(VideoCodecResolutionType::VIDEO_1280x720); break;
    case 2: video->set_codec_resolution(VideoCodecResolutionType::VIDEO_1920x1080); break;
    default: video->set_codec_resolution(VideoCodecResolutionType::VIDEO_800x480); break;
    }
    video->set_frame_rate(settings_.fps == 60 ? VideoFrameRateType::VIDEO_FPS_60 : VideoFrameRateType::VIDEO_FPS_30);
    video->set_width_margin(0);
    video->set_height_margin(0);
    video->set_density(settings_.densityDpi());
    video->set_video_codec_type(MediaCodecType::MEDIA_CODEC_VIDEO_H264_BP);
}

/**
 * @brief チャネルオープン要求に成功を返す。
 */
void AasdkVideoHandler::onChannelOpenRequest(const proto::service::control::message::ChannelOpenRequest &request) {
    log("[video] チャネルオープン要求を受信 (service_id=" + std::to_string(request.service_id()) +
        ") → STATUS_SUCCESS を返します");

    proto::service::control::message::ChannelOpenResponse response;
    response.set_status(proto::shared::MessageStatus::STATUS_SUCCESS);
    channel_->sendChannelOpenResponse(response, makeSendPromise("ChannelOpenResponse"));
    channel_->receive(shared_from_this());
}

/**
 * @brief メディアのセットアップ要求に「準備完了」を返す。
 */
void AasdkVideoHandler::onMediaChannelSetupRequest(const proto::service::media::shared::message::Setup &request) {
    log("[video] メディアセットアップ要求を受信 (codec type=" +
        std::to_string(static_cast<int>(request.type())) + ") → STATUS_READY / max_unacked=" +
        std::to_string(config::kVideoMaxUnacked) + " を返します");

    proto::service::media::shared::message::Config response;
    response.set_status(proto::service::media::shared::message::Config::STATUS_READY);
    response.set_max_unacked(config::kVideoMaxUnacked);
    response.add_configuration_indices(0);
    // OpenAuto と同様、Config の送信成功後に VIDEO_FOCUS_PROJECTED を通知する
    auto promise = aasdk::channel::SendPromise::defer(*strand_);
    promise->then([self = shared_from_this()]() { self->sendVideoFocus(); },
                  [self = shared_from_this()](const aasdk::error::Error &e) {
                      if (self->callbacks_.onFatalError) {
                          self->callbacks_.onFatalError(std::string("映像チャネル送信失敗(Config): ") + e.what());
                      }
                  });
    channel_->sendChannelSetupResponse(response, std::move(promise));
    channel_->receive(shared_from_this());
}

/**
 * @brief 映像ストリーム開始通知。以降の ACK に使うセッションIDを保存する。
 */
void AasdkVideoHandler::onMediaChannelStartIndication(const proto::service::media::shared::message::Start &indication) {
    sessionId_ = indication.session_id();
    log("映像ストリーム開始 (session_id=" + std::to_string(sessionId_) + ")");
    channel_->receive(shared_from_this());
}

/**
 * @brief 映像ストリーム停止通知。状態を「接続済み(映像待ち)」に戻す。
 */
void AasdkVideoHandler::onMediaChannelStopIndication(const proto::service::media::shared::message::Stop &) {
    log("映像ストリーム停止");
    streaming_ = false;
    if (callbacks_.onStateChanged) {
        callbacks_.onStateChanged(LinkState::Connected, "映像ストリームが停止しました");
    }
    channel_->receive(shared_from_this());
}

/**
 * @brief タイムスタンプ付き映像データ(MEDIA_MESSAGE_DATA)を処理する。
 */
void AasdkVideoHandler::onMediaWithTimestampIndication(aasdk::messenger::Timestamp::ValueType,
                                                       const aasdk::common::DataConstBuffer &buffer) {
    handleMediaData(buffer, true);
}

/**
 * @brief コーデック設定(SPS/PPS 等, MEDIA_MESSAGE_CODEC_CONFIG)を処理する。
 */
void AasdkVideoHandler::onMediaIndication(const aasdk::common::DataConstBuffer &buffer) { handleMediaData(buffer, false); }

/**
 * @brief 映像フォーカス要求に、要求されたモードをそのまま通知する。
 *
 * 要求にモードが無い場合は PROJECTED（スマートフォン映像を表示）とする。暫定の挙動。
 */
void AasdkVideoHandler::onVideoFocusRequest(
    const proto::service::media::video::message::VideoFocusRequestNotification &request) {
    using proto::service::media::video::message::VideoFocusMode;

    const VideoFocusMode mode = request.has_mode() ? request.mode() : VideoFocusMode::VIDEO_FOCUS_PROJECTED;
    log("映像フォーカス要求 (mode=" + std::to_string(static_cast<int>(mode)) + ")");

    proto::service::media::video::message::VideoFocusNotification indication;
    indication.set_focus(mode);
    indication.set_unsolicited(false);
    channel_->sendVideoFocusIndication(indication, makeSendPromise("VideoFocusNotification"));
    channel_->receive(shared_from_this());
}

/**
 * @brief チャネルエラー（受信失敗/パース失敗/USB切断など）をセッション終了として上位へ通知する。
 */
void AasdkVideoHandler::onChannelError(const aasdk::error::Error &e) {
    if (callbacks_.onFatalError) {
        callbacks_.onFatalError(std::string("映像チャネルエラー: ") + e.what());
    }
}

/**
 * @brief スマートフォン側の映像にフォーカスを移す通知（VIDEO_FOCUS_PROJECTED）を送る。
 *
 * セットアップ応答の後に明示的に送る使い方を想定している。現時点では呼び出し箇所が
 * 未確定のため、どこからも呼んでいない（実機での挙動確認後に接続する）。
 */
void AasdkVideoHandler::sendVideoFocus() {
    using proto::service::media::video::message::VideoFocusMode;

    proto::service::media::video::message::VideoFocusNotification indication;
    indication.set_focus(VideoFocusMode::VIDEO_FOCUS_PROJECTED);
    indication.set_unsolicited(false);
    channel_->sendVideoFocusIndication(indication, makeSendPromise("VideoFocusNotification"));
}

/**
 * @brief 送信失敗をセッション終了エラーとして通知する Promise を作る。
 */
aasdk::channel::SendPromise::Pointer AasdkVideoHandler::makeSendPromise(const char *what) {
    auto promise = aasdk::channel::SendPromise::defer(*strand_);
    promise->then([]() {},
                  [self = shared_from_this(), what = std::string(what)](const aasdk::error::Error &e) {
                      if (self->callbacks_.onFatalError) {
                          self->callbacks_.onFatalError("映像チャネル送信失敗(" + what + "): " + e.what());
                      }
                  });
    return promise;
}

/**
 * @brief 映像データを上位へ渡し、1件ごとに ACK を返して受信を再開する。
 *
 * ACK を返さないとスマートフォン側が max_unacked に達して送信を止めるため必須。
 */
void AasdkVideoHandler::handleMediaData(const aasdk::common::DataConstBuffer &buffer, bool isFrame) {
    // コーデック設定（SPS/PPS 等）では Streaming に遷移せず、実際の映像フレームを
    // 受信した時点で状態遷移する。
    if (isFrame && !streaming_) {
        streaming_ = true;
        if (callbacks_.onStateChanged) {
            callbacks_.onStateChanged(LinkState::Streaming, "映像を受信中");
        }
    }
    if (callbacks_.onVideoData) {
        callbacks_.onVideoData(buffer.cdata, buffer.size);
    }

    proto::service::media::source::message::Ack ack;
    ack.set_session_id(sessionId_);
    ack.set_ack(1);
    channel_->sendMediaAckIndication(ack, makeSendPromise("Media Ack"));
    channel_->receive(shared_from_this());
}

/**
 * @brief 診断ログを上位へ流す。
 */
void AasdkVideoHandler::log(const std::string &message) const {
    if (callbacks_.onLog) {
        callbacks_.onLog("[video] " + message);
    }
}

} // namespace opencruise::aa
