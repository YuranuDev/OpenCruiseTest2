/**
 * @file AasdkSystemAudioHandler.h
 * @brief aasdk の System audio(MediaSink Audio)チャネルを処理するクラス。
 *
 * Android Auto はナビ音声などを System audio として送ってくる。
 * 本アプリではまず「チャネルを正しく開き、PCM を受け取って ACK する」
 * 最小構成を実装する。実際の再生は将来のオーディオ出力実装で行う。
 */
#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <string>

#include <boost/asio.hpp>

#include <aasdk/Channel/MediaSink/Audio/AudioMediaSinkService.hpp>
#include <aasdk/Channel/MediaSink/Audio/Channel/GuidanceAudioChannel.hpp>
#include <aasdk/Channel/MediaSink/Audio/Channel/MediaAudioChannel.hpp>
#include <aasdk/Channel/MediaSink/Audio/Channel/SystemAudioChannel.hpp>
#include <aasdk/Channel/MediaSink/Audio/IAudioMediaSinkServiceEventHandler.hpp>
#include <aasdk/Channel/Promise.hpp>
#include <aasdk/Messenger/IMessenger.hpp>
#include <aap_protobuf/service/control/message/ChannelOpenRequest.pb.h>
#include <aap_protobuf/service/control/message/ServiceDiscoveryResponse.pb.h>
#include <aap_protobuf/service/media/shared/message/Setup.pb.h>

namespace opencruise::aa {

/**
 * @brief System audio チャネルのイベントハンドラ兼オーナー。
 */
class AasdkSystemAudioHandler : public aasdk::channel::mediasink::audio::IAudioMediaSinkServiceEventHandler,
                                public std::enable_shared_from_this<AasdkSystemAudioHandler> {
public:
    /**
     * @brief 音声ハンドラから上位(セッション)への通知先。
     */
    struct Callbacks {
        std::function<void(const std::string &)> onFatalError; ///< セッションを終了すべきエラー
        std::function<void(const std::string &)> onLog;        ///< 診断ログ
        std::function<void(const std::uint8_t *, std::size_t)> onAudioData; ///< PCM データ受信
        std::function<void()> onAudioStop;                                  ///< ストリーム停止通知
    };

    /**
     * @brief System audio チャネルを生成する(受信ループはまだ開始しない)。
     */
    /// 音声チャネルの種類(OpenAuto の ServiceFactory と同じ 3 種)
    enum class Kind { System, Media, Guidance };

    AasdkSystemAudioHandler(std::shared_ptr<boost::asio::io_service::strand> strand,
                            aasdk::messenger::IMessenger::Pointer messenger, Callbacks callbacks,
                            Kind kind = Kind::System);

    /**
     * @brief 音声チャネルの受信ループを開始する。
     */
    void start();

    /**
     * @brief ServiceDiscoveryResponse に System audio サービスを追記する。
     */
    void fillFeatures(aap_protobuf::service::control::message::ServiceDiscoveryResponse &response);

    // ---- IAudioMediaSinkServiceEventHandler ----
    void onChannelOpenRequest(const aap_protobuf::service::control::message::ChannelOpenRequest &request) override;
    void onMediaChannelSetupRequest(const aap_protobuf::service::media::shared::message::Setup &request) override;
    void onMediaChannelStartIndication(const aap_protobuf::service::media::shared::message::Start &indication) override;
    void onMediaChannelStopIndication(const aap_protobuf::service::media::shared::message::Stop &indication) override;
    void onMediaWithTimestampIndication(aasdk::messenger::Timestamp::ValueType timestamp,
                                        const aasdk::common::DataConstBuffer &buffer) override;
    void onMediaIndication(const aasdk::common::DataConstBuffer &buffer) override;
    void onChannelError(const aasdk::error::Error &e) override;

private:
    /**
     * @brief 送信完了を待つ Promise を作る。失敗時はセッション終了エラーとして通知する。
     */
    aasdk::channel::SendPromise::Pointer makeSendPromise(const char *what);

    /**
     * @brief 受信データを捨てて ACK を返し、受信を再開する。
     */
    void handleMediaData(const aasdk::common::DataConstBuffer &buffer);

    /**
     * @brief 診断ログを上位へ流す。
     */
    void log(const std::string &message) const;

    std::shared_ptr<boost::asio::io_service::strand> strand_;
    std::shared_ptr<aasdk::channel::mediasink::audio::AudioMediaSinkService> channel_;
    Kind kind_;
    Callbacks callbacks_;
    std::int32_t sessionId_ = 0; ///< Start 指示で通知されたセッションID(ACK に必要)
};

} // namespace opencruise::aa
