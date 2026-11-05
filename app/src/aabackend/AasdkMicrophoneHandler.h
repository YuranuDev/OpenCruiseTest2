/**
 * @file AasdkMicrophoneHandler.h
 * @brief aasdk のマイク(MediaSource)チャネルの最小実装。
 *
 * OpenAuto の ServiceFactory は常に Microphone を申告するため、同じ構成に合わせる。
 * スマートフォンからのマイク オープン/クローズ要求に応答し、開いている間だけ、車載機側で録音した
 * PCM(16kHz/16bit/1ch)を sendAudio() で送る。録音そのものは Qt 側(MicrophoneInput)が行う。
 */
#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>

#include <boost/asio.hpp>

#include <aasdk/Channel/MediaSource/Audio/MicrophoneAudioChannel.hpp>
#include <aasdk/Channel/MediaSource/IMediaSourceServiceEventHandler.hpp>
#include <aasdk/Channel/Promise.hpp>
#include <aasdk/Messenger/IMessenger.hpp>
#include <aap_protobuf/service/control/message/ServiceDiscoveryResponse.pb.h>

namespace opencruise::aa {

class AasdkMicrophoneHandler : public aasdk::channel::mediasource::IMediaSourceServiceEventHandler,
                               public std::enable_shared_from_this<AasdkMicrophoneHandler> {
public:
    struct Callbacks {
        std::function<void(const std::string &)> onFatalError; ///< セッションを終了すべきエラー
        std::function<void(const std::string &)> onLog;        ///< 診断ログ
        std::function<void(bool)> onMicrophoneRequest;         ///< スマートフォンがマイクを開いた(true)/閉じた(false)
    };

    AasdkMicrophoneHandler(std::shared_ptr<boost::asio::io_service::strand> strand,
                           aasdk::messenger::IMessenger::Pointer messenger, Callbacks callbacks);

    void start();
    void fillFeatures(aap_protobuf::service::control::message::ServiceDiscoveryResponse &response);

    /// スマートフォンがマイクを開いている間 true(strand 上でのみ呼ぶ)
    bool isOpen() const { return open_; }

    /**
     * @brief 録音した PCM を 1 チャンク送る(strand 上でのみ呼ぶ)。
     *
     * マイクが開いていない場合、または送信待ちが溜まりすぎている場合は、エラーにせず捨てる。
     */
    void sendAudio(const std::uint8_t *data, std::size_t size);

    // ---- IMediaSourceServiceEventHandler ----
    void onChannelOpenRequest(const aap_protobuf::service::control::message::ChannelOpenRequest &request) override;
    void onMediaChannelSetupRequest(const aap_protobuf::service::media::shared::message::Setup &request) override;
    void onMediaSourceOpenRequest(
        const aap_protobuf::service::media::source::message::MicrophoneRequest &request) override;
    void onMediaChannelAckIndication(const aap_protobuf::service::media::source::message::Ack &indication) override;
    void onChannelError(const aasdk::error::Error &e) override;

private:
    aasdk::channel::SendPromise::Pointer makeSendPromise(const char *what);
    void log(const std::string &message) const;

    std::shared_ptr<boost::asio::io_service::strand> strand_;
    std::shared_ptr<aasdk::channel::mediasource::audio::MicrophoneAudioChannel> channel_;
    Callbacks callbacks_;
    bool open_ = false;            ///< スマートフォンからオープン要求を受けている間 true(strand 上でのみ触る)
    std::size_t pendingSends_ = 0; ///< 送信完了待ちのチャンク数(strand 上でのみ触る)
    std::size_t droppedChunks_ = 0; ///< 送信待ち過多で捨てたチャンク数(ログ用)
};

} // namespace opencruise::aa
