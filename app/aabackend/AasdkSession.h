/**
 * @file AasdkSession.h
 * @brief スマートフォン1台ぶんの Android Auto セッション（制御チャネルを担当）。
 *
 * AOAP で確立した USB デバイスから、Transport → Cryptor → Messenger → 各チャネルを組み立て、
 * バージョン確認 → SSL ハンドシェイク → 認証完了 → サービス探索応答 までを進める。
 * 映像/センサー/入力/System audio の各チャネルはそれぞれのハンドラに委譲する。
 */
#pragma once

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>

#include <boost/asio.hpp>

#include <aasdk/Channel/Control/ControlServiceChannel.hpp>
#include <aasdk/Channel/Control/IControlServiceChannelEventHandler.hpp>
#include <aasdk/Messenger/ICryptor.hpp>
#include <aasdk/Messenger/IMessenger.hpp>
#include <aasdk/Transport/ITransport.hpp>
#include <aasdk/USB/IAOAPDevice.hpp>

#include "AasdkInputHandler.h"
#include "AasdkMicrophoneHandler.h"
#include "AasdkSensorHandler.h"
#include "AasdkSystemAudioHandler.h"
#include "AasdkVideoHandler.h"
#include "StreamSettings.h"
#include "LinkState.h"
#include "TouchEvent.h"

namespace opencruise::aa {

/**
 * @brief セッションから接続層(AasdkBackend)への通知先。
 */
struct SessionCallbacks {
    std::function<void(LinkState, const std::string &)> onStateChanged; ///< 状態変化
    std::function<void(const std::uint8_t *, std::size_t)> onVideoData;  ///< 映像データ受信
    std::function<void(const std::string &)> onLog;                      ///< 診断ログ
    std::function<void(const std::string &)> onFinished; ///< セッション終了（理由つき、1回だけ呼ばれる）
};

/**
 * @brief 1回の接続（切断まで）を表すオブジェクト。
 *
 * 使い捨て。終了したら onFinished が呼ばれるので、呼び出し側は破棄して新しく作り直す。
 */
class AasdkSession : public aasdk::channel::control::IControlServiceChannelEventHandler,
                     public std::enable_shared_from_this<AasdkSession> {
public:
    /**
     * @brief セッションを組み立てる（まだ通信は始めない）。
     * @param ioService aasdk 共通の io_service
     * @param aoapDevice AOAP 確立済みの USB デバイス
     * @param callbacks 通知先
     * @throws aasdk::error::Error / std::exception 下位オブジェクトの生成に失敗した場合
     */
    AasdkSession(boost::asio::io_service &ioService, aasdk::usb::IAOAPDevice::Pointer aoapDevice,
                 SessionCallbacks callbacks, StreamSettings settings = {});

    /**
     * @brief 通信を開始する（SSL 初期化 → 受信ループ開始 → バージョン要求送信）。
     * @note shared_ptr で管理されている必要がある（shared_from_this を使うため）。
     */
    void start();

    /**
     * @brief アプリ側の都合でセッションを終了する。何度呼んでもよい。
     */
    void stop();

    /**
     * @brief タッチ入力をスマートフォンへ送る。どのスレッドから呼んでもよい。
     *
     * 実際の送信は strand 上で行う。セッション終了後や入力チャネルの準備前に呼んだ場合は何もしない。
     */
    void sendTouch(const TouchEvent &event);

    // ---- IControlServiceChannelEventHandler ----
    void onVersionResponse(uint16_t majorCode, uint16_t minorCode, aap_protobuf::shared::MessageStatus status) override;
    void onHandshake(const aasdk::common::DataConstBuffer &payload) override;
    void onServiceDiscoveryRequest(
        const aap_protobuf::service::control::message::ServiceDiscoveryRequest &request) override;
    void onAudioFocusRequest(const aap_protobuf::service::control::message::AudioFocusRequest &request) override;
    void onByeByeRequest(const aap_protobuf::service::control::message::ByeByeRequest &request) override;
    void onByeByeResponse(const aap_protobuf::service::control::message::ByeByeResponse &response) override;
    void onBatteryStatusNotification(
        const aap_protobuf::service::control::message::BatteryStatusNotification &notification) override;
    void onNavigationFocusRequest(
        const aap_protobuf::service::control::message::NavFocusRequestNotification &request) override;
    void onVoiceSessionRequest(const aap_protobuf::service::control::message::VoiceSessionNotification &request) override;
    void onPingRequest(const aap_protobuf::service::control::message::PingRequest &request) override;
    void onPingResponse(const aap_protobuf::service::control::message::PingResponse &response) override;
    void onChannelError(const aasdk::error::Error &e) override;

private:
    /// 車載機側から定期的に PingRequest を送る(strand 上で実行)
    void schedulePing();

    /**
     * @brief 送信完了を待つ Promise を作る。失敗時はセッションを終了する。
     * @param what 失敗時ログ用の送信内容の説明
     */
    aasdk::channel::SendPromise::Pointer makeSendPromise(const char *what);

    /**
     * @brief セッション終了処理を strand 上で行う。冪等。
     * @param reason 終了理由（UI に表示される）
     */
    void terminate(const std::string &reason);

    /**
     * @brief terminate の本体（strand 上で実行される）。
     */
    void doTerminate(const std::string &reason);

    /**
     * @brief 診断ログを上位へ流す。
     */
    void log(const std::string &message) const;

    /**
     * @brief セッション開始からの経過ミリ秒（所要時間ログ用）。
     */
    long long elapsedMs() const {
        return static_cast<long long>(std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - startedAt_).count());
    }

    std::shared_ptr<boost::asio::io_service::strand> strand_; ///< 全チャネル共通。ハンドラ側と共有所有
    aasdk::transport::ITransport::Pointer transport_;
    aasdk::messenger::ICryptor::Pointer cryptor_;
    aasdk::messenger::IMessenger::Pointer messenger_;
    std::shared_ptr<aasdk::channel::control::ControlServiceChannel> controlChannel_;
    std::shared_ptr<AasdkVideoHandler> videoHandler_;
    std::shared_ptr<AasdkSensorHandler> sensorHandler_;
    std::shared_ptr<AasdkInputHandler> inputHandler_;
    std::shared_ptr<AasdkSystemAudioHandler> systemAudioHandler_;
    std::shared_ptr<AasdkSystemAudioHandler> mediaAudioHandler_;
    std::shared_ptr<AasdkSystemAudioHandler> guidanceAudioHandler_;
    std::shared_ptr<AasdkMicrophoneHandler> microphoneHandler_;
    std::shared_ptr<boost::asio::steady_timer> pingTimer_; ///< 車載機発の Ping 用
    std::uint64_t lastPingSentMs_ = 0;
    SessionCallbacks callbacks_;
    bool finished_ = false; ///< strand 上でのみ読み書きする
    bool stopRequested_ = false; ///< stop() による ByeBye 送信済み(strand 上でのみ触る)
    StreamSettings settings_;    ///< 映像設定
    std::shared_ptr<boost::asio::steady_timer> shutdownTimer_; ///< ByeBye 応答待ちの上限
    std::chrono::steady_clock::time_point startedAt_ = std::chrono::steady_clock::now(); ///< 接続開始時刻（所要時間ログ用）
};

} // namespace opencruise::aa
