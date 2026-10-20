/**
 * @file AasdkMicrophoneHandler.cpp
 * @brief マイク(MediaSource)チャネルの最小実装。録音データは送らない。
 */
#include "AasdkMicrophoneHandler.h"

#include <aasdk/Error/Error.hpp>
#include <aap_protobuf/service/Service.pb.h>
#include <aap_protobuf/service/control/message/ChannelOpenResponse.pb.h>
#include <aap_protobuf/service/media/shared/message/AudioConfiguration.pb.h>
#include <aap_protobuf/service/media/shared/message/Config.pb.h>
#include <aap_protobuf/service/media/shared/message/MediaCodecType.pb.h>
#include <aap_protobuf/service/media/source/MediaSourceService.pb.h>
#include <aap_protobuf/service/media/source/message/MicrophoneResponse.pb.h>
#include <aap_protobuf/shared/MessageStatus.pb.h>

namespace opencruise::aa {

namespace proto = aap_protobuf;

AasdkMicrophoneHandler::AasdkMicrophoneHandler(std::shared_ptr<boost::asio::io_service::strand> strand,
                                               aasdk::messenger::IMessenger::Pointer messenger, Callbacks callbacks)
    : strand_(std::move(strand)),
      channel_(std::make_shared<aasdk::channel::mediasource::audio::MicrophoneAudioChannel>(*strand_,
                                                                                            std::move(messenger))),
      callbacks_(std::move(callbacks)) {}

void AasdkMicrophoneHandler::start() { channel_->receive(shared_from_this()); }

/**
 * @brief 16kHz / 16bit / 1ch の PCM マイクを申告する(OpenAuto と同じ値)。
 */
void AasdkMicrophoneHandler::fillFeatures(proto::service::control::message::ServiceDiscoveryResponse &response) {
    auto *service = response.add_channels();
    service->set_id(static_cast<std::int32_t>(channel_->getId()));

    auto *source = service->mutable_media_source_service();
    source->set_available_type(proto::service::media::shared::message::MediaCodecType::MEDIA_CODEC_AUDIO_PCM);
    source->set_available_while_in_call(true);
    auto *audio = source->mutable_audio_config();
    audio->set_sampling_rate(16000);
    audio->set_number_of_bits(16);
    audio->set_number_of_channels(1);
}

void AasdkMicrophoneHandler::onChannelOpenRequest(
    const proto::service::control::message::ChannelOpenRequest &request) {
    log("[mic] チャネルオープン要求を受信 (service_id=" + std::to_string(request.service_id()) + ")");
    proto::service::control::message::ChannelOpenResponse response;
    response.set_status(proto::shared::MessageStatus::STATUS_SUCCESS);
    channel_->sendChannelOpenResponse(response, makeSendPromise("ChannelOpenResponse"));
    channel_->receive(shared_from_this());
}

void AasdkMicrophoneHandler::onMediaChannelSetupRequest(const proto::service::media::shared::message::Setup &) {
    log("[mic] メディアセットアップ要求を受信 → STATUS_READY");
    proto::service::media::shared::message::Config response;
    response.set_status(proto::service::media::shared::message::Config::STATUS_READY);
    response.set_max_unacked(1);
    response.add_configuration_indices(0);
    channel_->sendChannelSetupResponse(response, makeSendPromise("Config(setup response)"));
    channel_->receive(shared_from_this());
}

void AasdkMicrophoneHandler::onMediaSourceOpenRequest(
    const proto::service::media::source::message::MicrophoneRequest &request) {
    log(std::string("[mic] マイク ") + (request.open() ? "オープン" : "クローズ") + "要求を受信");
    proto::service::media::source::message::MicrophoneResponse response;
    response.set_status(0);
    response.set_session_id(0);
    channel_->sendMicrophoneOpenResponse(response, makeSendPromise("MicrophoneResponse"));
    channel_->receive(shared_from_this());
}

void AasdkMicrophoneHandler::onMediaChannelAckIndication(const proto::service::media::source::message::Ack &) {
    channel_->receive(shared_from_this());
}

void AasdkMicrophoneHandler::onChannelError(const aasdk::error::Error &e) {
    if (e == aasdk::error::ErrorCode::OPERATION_ABORTED) {
        return;
    }
    if (callbacks_.onFatalError) {
        callbacks_.onFatalError(std::string("マイクチャネルエラー: ") + e.what());
    }
}

aasdk::channel::SendPromise::Pointer AasdkMicrophoneHandler::makeSendPromise(const char *what) {
    auto promise = aasdk::channel::SendPromise::defer(*strand_);
    promise->then([]() {},
                  [self = shared_from_this(), what = std::string(what)](const aasdk::error::Error &e) {
                      if (self->callbacks_.onFatalError) {
                          self->callbacks_.onFatalError("マイクチャネル送信失敗(" + what + "): " + e.what());
                      }
                  });
    return promise;
}

void AasdkMicrophoneHandler::log(const std::string &message) const {
    if (callbacks_.onLog) {
        callbacks_.onLog(message);
    }
}

} // namespace opencruise::aa
