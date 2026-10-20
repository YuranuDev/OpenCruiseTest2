/**
 * @file AasdkMicrophoneHandler.h
 * @brief aasdk のマイク(MediaSource)チャネルの最小実装。
 *
 * OpenAuto の ServiceFactory は常に Microphone を申告するため、同じ構成に合わせる。
 * 実際の録音データは送らず、チャネルを開いて Setup/Open 要求に応答するだけ。
 */
#pragma once

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
    };

    AasdkMicrophoneHandler(std::shared_ptr<boost::asio::io_service::strand> strand,
                           aasdk::messenger::IMessenger::Pointer messenger, Callbacks callbacks);

    void start();
    void fillFeatures(aap_protobuf::service::control::message::ServiceDiscoveryResponse &response);

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
};

} // namespace opencruise::aa
