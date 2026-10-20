/**
 * @file AasdkVideoHandler.h
 * @brief aasdk の映像(MediaSink Video)チャネルを処理するクラス。
 *
 * aasdk が提供するのは「メッセージの送受信と protobuf へのデコード」まで。
 * チャネルを開く/セットアップに応答する/ACK を返す/フォーカスに応答する、といった
 * アプリ側の振る舞いは、このクラスで実装している。
 * H.264 のデコード自体は aasdk に含まれないため、受信した生データは onVideoData で
 * 外部（Qt 側の H264Decoder）へ渡す。
 */
#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>

#include <boost/asio.hpp>

#include <aasdk/Channel/MediaSink/Video/Channel/VideoChannel.hpp>
#include <aasdk/Channel/MediaSink/Video/IVideoMediaSinkServiceEventHandler.hpp>
#include <aasdk/Channel/Promise.hpp>
#include <aasdk/Messenger/IMessenger.hpp>
#include <aap_protobuf/service/control/message/ServiceDiscoveryResponse.pb.h>

#include "LinkState.h"

namespace opencruise::aa {

/**
 * @brief 映像チャネルのイベントハンドラ兼オーナー。
 *
 * aasdk のチャネルは「1メッセージ受信するたびにハンドラが receive() を呼び直す」方式のため、
 * 各 on* 関数は必ず最後に receive() を再度呼ぶ（呼び忘れると以降の受信が止まる）。
 */
class AasdkVideoHandler
    : public aasdk::channel::mediasink::video::IVideoMediaSinkServiceEventHandler,
      public std::enable_shared_from_this<AasdkVideoHandler> {
public:
    /**
     * @brief 映像ハンドラから上位（セッション）への通知先。
     */
    struct Callbacks {
        std::function<void(const std::uint8_t *, std::size_t)> onVideoData; ///< 映像データ受信
        std::function<void(LinkState, const std::string &)> onStateChanged;  ///< 状態変化
        std::function<void(const std::string &)> onFatalError;               ///< セッションを終了すべきエラー
        std::function<void(const std::string &)> onLog;                      ///< 診断ログ
    };

    /**
     * @brief 映像チャネルを生成する。
     * @param strand セッション共有の strand。ハンドラ生存中は有効であること(共有所有)
     * @param messenger セッションの Messenger
     * @param callbacks 通知先
     */
    AasdkVideoHandler(std::shared_ptr<boost::asio::io_service::strand> strand,
                      aasdk::messenger::IMessenger::Pointer messenger, Callbacks callbacks);

    /**
     * @brief 映像チャネルの受信ループを開始する。
     */
    void start();

    /**
     * @brief ServiceDiscoveryResponse に映像サービス(H.264/800x480/30fps)を追記する。
     * @param[in,out] response 追記先
     */
    void fillFeatures(aap_protobuf::service::control::message::ServiceDiscoveryResponse &response);

    // ---- IVideoMediaSinkServiceEventHandler ----
    void onChannelOpenRequest(const aap_protobuf::service::control::message::ChannelOpenRequest &request) override;
    void onMediaChannelSetupRequest(const aap_protobuf::service::media::shared::message::Setup &request) override;
    void onMediaChannelStartIndication(const aap_protobuf::service::media::shared::message::Start &indication) override;
    void onMediaChannelStopIndication(const aap_protobuf::service::media::shared::message::Stop &indication) override;
    void onMediaWithTimestampIndication(aasdk::messenger::Timestamp::ValueType timestamp,
                                        const aasdk::common::DataConstBuffer &buffer) override;
    void onMediaIndication(const aasdk::common::DataConstBuffer &buffer) override;
    void onVideoFocusRequest(
        const aap_protobuf::service::media::video::message::VideoFocusRequestNotification &request) override;
    void onChannelError(const aasdk::error::Error &e) override;

private:
    /**
     * @brief 送信完了を待つ Promise を作る。失敗時はセッション終了エラーとして通知する。
     * @param what 失敗時ログ用の送信内容の説明
     */
    aasdk::channel::SendPromise::Pointer makeSendPromise(const char *what);

    /**
     * @brief 映像データ（コーデック設定/フレーム）を上位へ渡し、ACK を返して受信を再開する。
     * @param isFrame タイムスタンプ付きの実フレームなら true、コーデック設定なら false
     */
    void handleMediaData(const aasdk::common::DataConstBuffer &buffer, bool isFrame);

    /**
     * @brief スマートフォン映像にフォーカスを移す通知を送る（VIDEO_FOCUS_PROJECTED）。
     */
    void sendVideoFocus();

    /**
     * @brief ログ出力のヘルパー。
     */
    void log(const std::string &message) const;

    std::shared_ptr<boost::asio::io_service::strand> strand_;
    std::shared_ptr<aasdk::channel::mediasink::video::channel::VideoChannel> channel_;
    Callbacks callbacks_;
    std::int32_t sessionId_ = 0; ///< Start 指示で通知されたセッションID（ACK に必要）
    bool streaming_ = false;     ///< 最初の映像データを受け取ったら true
};

} // namespace opencruise::aa
