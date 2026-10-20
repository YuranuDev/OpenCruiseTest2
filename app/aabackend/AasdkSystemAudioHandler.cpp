/**
 * @file AasdkSystemAudioHandler.cpp
 * @brief System audio チャネルの最小実装(受信して ACK のみ)。
 */
#include "AasdkSystemAudioHandler.h"

#include <aasdk/Error/Error.hpp>
#include <aap_protobuf/service/Service.pb.h>
#include <aap_protobuf/service/control/message/ChannelOpenResponse.pb.h>
#include <aap_protobuf/service/media/shared/message/Config.pb.h>
#include <aap_protobuf/service/media/shared/message/MediaCodecType.pb.h>
#include <aap_protobuf/service/media/sink/MediaSinkService.pb.h>
#include <aap_protobuf/service/media/shared/message/AudioConfiguration.pb.h>
#include <aap_protobuf/service/media/sink/message/AudioStreamType.pb.h>
#include <aap_protobuf/service/media/source/message/Ack.pb.h>
#include <aap_protobuf/shared/MessageStatus.pb.h>

namespace opencruise::aa {

namespace proto = aap_protobuf;

namespace {
constexpr std::int32_t kAudioBitDepth = 16;
constexpr std::int32_t kAudioMaxUnacked = 1;

struct AudioParams {
    std::int32_t sampleRate;
    std::int32_t channelCount;
};

// OpenAuto の ServiceFactory と同じ値: Media 48kHz/2ch、Guidance/System 16kHz/1ch
AudioParams paramsFor(AasdkSystemAudioHandler::Kind kind) {
    return kind == AasdkSystemAudioHandler::Kind::Media ? AudioParams{48000, 2} : AudioParams{16000, 1};
}

std::shared_ptr<aasdk::channel::mediasink::audio::AudioMediaSinkService>
makeChannel(AasdkSystemAudioHandler::Kind kind, boost::asio::io_service::strand &strand,
            aasdk::messenger::IMessenger::Pointer messenger) {
    using namespace aasdk::channel::mediasink::audio::channel;
    switch (kind) {
    case AasdkSystemAudioHandler::Kind::Media:
        return std::make_shared<MediaAudioChannel>(strand, std::move(messenger));
    case AasdkSystemAudioHandler::Kind::Guidance:
        return std::make_shared<GuidanceAudioChannel>(strand, std::move(messenger));
    case AasdkSystemAudioHandler::Kind::System:
        break;
    }
    return std::make_shared<SystemAudioChannel>(strand, std::move(messenger));
}
} // namespace

/**
 * @brief 音声チャネルを生成する。
 */
AasdkSystemAudioHandler::AasdkSystemAudioHandler(std::shared_ptr<boost::asio::io_service::strand> strand,
                                                 aasdk::messenger::IMessenger::Pointer messenger,
                                                 Callbacks callbacks, Kind kind)
    : strand_(std::move(strand)), channel_(makeChannel(kind, *strand_, std::move(messenger))),
      callbacks_(std::move(callbacks)), kind_(kind) {}

/**
 * @brief 音声チャネルの受信ループを開始する。
 */
void AasdkSystemAudioHandler::start() { channel_->receive(shared_from_this()); }

/**
 * @brief ServiceDiscoveryResponse に System audio サービスを追記する。
 */
void AasdkSystemAudioHandler::fillFeatures(
    proto::service::control::message::ServiceDiscoveryResponse &response) {
    using proto::service::media::shared::message::MediaCodecType;
    using proto::service::media::sink::message::AUDIO_STREAM_SYSTEM_AUDIO;

    auto *service = response.add_channels();
    service->set_id(static_cast<std::int32_t>(channel_->getId()));

    auto *sink = service->mutable_media_sink_service();
    sink->set_available_type(MediaCodecType::MEDIA_CODEC_AUDIO_PCM);
    using proto::service::media::sink::message::AUDIO_STREAM_GUIDANCE;
    using proto::service::media::sink::message::AUDIO_STREAM_MEDIA;
    sink->set_audio_type(kind_ == Kind::Media      ? AUDIO_STREAM_MEDIA
                         : kind_ == Kind::Guidance ? AUDIO_STREAM_GUIDANCE
                                                   : AUDIO_STREAM_SYSTEM_AUDIO);
    sink->set_available_while_in_call(true);

    auto *audio = sink->add_audio_configs();
    audio->set_sampling_rate(paramsFor(kind_).sampleRate);
    audio->set_number_of_bits(kAudioBitDepth);
    audio->set_number_of_channels(paramsFor(kind_).channelCount);
}

/**
 * @brief チャネルオープン要求に成功を返す。
 */
void AasdkSystemAudioHandler::onChannelOpenRequest(
    const proto::service::control::message::ChannelOpenRequest &request) {
    log("[audio] チャネルオープン要求を受信 (service_id=" + std::to_string(request.service_id()) +
        ") → STATUS_SUCCESS を返します");

    proto::service::control::message::ChannelOpenResponse response;
    response.set_status(proto::shared::MessageStatus::STATUS_SUCCESS);
    channel_->sendChannelOpenResponse(response, makeSendPromise("ChannelOpenResponse"));
    channel_->receive(shared_from_this());
}

/**
 * @brief メディアセットアップ要求に「準備完了」を返す。
 */
void AasdkSystemAudioHandler::onMediaChannelSetupRequest(
    const proto::service::media::shared::message::Setup &request) {
    log("[audio] メディアセットアップ要求を受信 (codec type=" +
        std::to_string(static_cast<int>(request.type())) + ") → STATUS_READY を返します");

    proto::service::media::shared::message::Config response;
    response.set_status(proto::service::media::shared::message::Config::STATUS_READY);
    response.set_max_unacked(kAudioMaxUnacked);
    response.add_configuration_indices(0);
    channel_->sendChannelSetupResponse(response, makeSendPromise("Config(setup response)"));
    channel_->receive(shared_from_this());
}

/**
 * @brief 音声ストリーム開始通知。ACK に使うセッションIDを保存する。
 */
void AasdkSystemAudioHandler::onMediaChannelStartIndication(
    const proto::service::media::shared::message::Start &indication) {
    sessionId_ = indication.session_id();
    log("[audio] System audio ストリーム開始 (session_id=" + std::to_string(sessionId_) + ")");
    channel_->receive(shared_from_this());
}

/**
 * @brief 音声ストリーム停止通知。
 */
void AasdkSystemAudioHandler::onMediaChannelStopIndication(
    const proto::service::media::shared::message::Stop &) {
    log("[audio] System audio ストリーム停止");
    sessionId_ = 0;
    channel_->receive(shared_from_this());
}

/**
 * @brief タイムスタンプ付き音声データ。
 */
void AasdkSystemAudioHandler::onMediaWithTimestampIndication(
    aasdk::messenger::Timestamp::ValueType, const aasdk::common::DataConstBuffer &buffer) {
    handleMediaData(buffer);
}

/**
 * @brief コーデック設定/タイムスタンプなし音声データ。
 */
void AasdkSystemAudioHandler::onMediaIndication(const aasdk::common::DataConstBuffer &buffer) {
    handleMediaData(buffer);
}

/**
 * @brief 音声データを捨てて ACK を返す。ACK を返さないと max_unacked で送信が止まる。
 */
void AasdkSystemAudioHandler::handleMediaData(const aasdk::common::DataConstBuffer &) {
    proto::service::media::source::message::Ack ack;
    ack.set_session_id(sessionId_);
    ack.set_ack(1);
    channel_->sendMediaAckIndication(ack, makeSendPromise("Media Ack"));
    channel_->receive(shared_from_this());
}

/**
 * @brief チャネルエラー。中断は正常終了経路なので無視する。
 */
void AasdkSystemAudioHandler::onChannelError(const aasdk::error::Error &e) {
    if (e == aasdk::error::ErrorCode::OPERATION_ABORTED) {
        return;
    }
    if (callbacks_.onFatalError) {
        callbacks_.onFatalError(std::string("音声チャネルエラー: ") + e.what());
    }
}

/**
 * @brief 送信失敗をセッション終了エラーとして通知する Promise を作る。
 */
aasdk::channel::SendPromise::Pointer AasdkSystemAudioHandler::makeSendPromise(const char *what) {
    auto promise = aasdk::channel::SendPromise::defer(*strand_);
    promise->then([]() {},
                  [self = shared_from_this(), what = std::string(what)](const aasdk::error::Error &e) {
                      if (self->callbacks_.onFatalError) {
                          self->callbacks_.onFatalError("音声チャネル送信失敗(" + what + "): " + e.what());
                      }
                  });
    return promise;
}

/**
 * @brief 診断ログを上位へ流す。
 */
void AasdkSystemAudioHandler::log(const std::string &message) const {
    if (callbacks_.onLog) {
        callbacks_.onLog(std::string("[audio:") + (kind_ == Kind::Media ? "media" : kind_ == Kind::Guidance ? "guidance" : "system") + "] " + message);
    }
}

} // namespace opencruise::aa
