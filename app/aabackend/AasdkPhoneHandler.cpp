/**
 * @file AasdkPhoneHandler.cpp
 * @brief PhoneStatus / GenericNotification / MediaPlaybackStatus チャネルの実装。
 */
#include "AasdkPhoneHandler.h"

#include <aasdk/Error/Error.hpp>
#include <aap_protobuf/service/Service.pb.h>
#include <aap_protobuf/service/control/message/ChannelOpenResponse.pb.h>
#include <aap_protobuf/service/genericnotification/message/GenericNotificationAck.pb.h>
#include <aap_protobuf/service/genericnotification/message/GenericNotificationMessage.pb.h>
#include <aap_protobuf/service/mediaplayback/message/MediaPlaybackMetadata.pb.h>
#include <aap_protobuf/service/mediaplayback/message/MediaPlaybackStatus.pb.h>
#include <aap_protobuf/service/phonestatus/message/PhoneStatus.pb.h>
#include <aap_protobuf/shared/MessageStatus.pb.h>

namespace opencruise::aa {

namespace proto = aap_protobuf;

namespace {

/// 送信完了を待つ Promise。失敗してもセッションは終了せず、ログに残すだけにする
aasdk::channel::SendPromise::Pointer makeLoggingPromise(boost::asio::io_service::strand &strand,
                                                        const PhoneInfoCallbacks &callbacks, const char *tag,
                                                        const char *what) {
    auto promise = aasdk::channel::SendPromise::defer(strand);
    promise->then([]() {},
                  [onLog = callbacks.onLog, tag = std::string(tag), what = std::string(what)](
                      const aasdk::error::Error &e) {
                      if (onLog) {
                          onLog("[" + tag + "] 送信に失敗(" + what + "): " + e.what());
                      }
                  });
    return promise;
}

} // namespace

// ===========================================================================
// PhoneStatus
// ===========================================================================

AasdkPhoneStatusHandler::AasdkPhoneStatusHandler(std::shared_ptr<boost::asio::io_service::strand> strand,
                                                 aasdk::messenger::IMessenger::Pointer messenger,
                                                 PhoneInfoCallbacks callbacks)
    : strand_(std::move(strand)),
      channel_(std::make_shared<aasdk::channel::phonestatus::PhoneStatusService>(*strand_, std::move(messenger))),
      callbacks_(std::move(callbacks)) {}

void AasdkPhoneStatusHandler::start() { channel_->receive(shared_from_this()); }

void AasdkPhoneStatusHandler::fillFeatures(proto::service::control::message::ServiceDiscoveryResponse &response) {
    auto *service = response.add_channels();
    service->set_id(static_cast<std::int32_t>(channel_->getId()));
    service->mutable_phone_status_service();
}

void AasdkPhoneStatusHandler::onChannelOpenRequest(const proto::service::control::message::ChannelOpenRequest &request) {
    log("チャネルオープン要求を受信 (service_id=" + std::to_string(request.service_id()) + ") → STATUS_SUCCESS");
    proto::service::control::message::ChannelOpenResponse response;
    response.set_status(proto::shared::MessageStatus::STATUS_SUCCESS);
    channel_->sendChannelOpenResponse(response, makeSendPromise("ChannelOpenResponse"));
    channel_->receive(shared_from_this());
}

void AasdkPhoneStatusHandler::onPhoneStatusUpdate(const proto::service::phonestatus::message::PhoneStatus &status) {
    if (status.has_signal_strength() && callbacks_.onSignal) {
        callbacks_.onSignal(static_cast<int>(status.signal_strength()));
    }
    if (callbacks_.onCalls) {
        std::vector<PhoneCallInfo> calls;
        for (const auto &c : status.calls()) {
            PhoneCallInfo info;
            info.state = static_cast<int>(c.phone_state());
            info.durationSec = static_cast<int>(c.call_duration_seconds());
            info.name = c.caller_id();
            info.number = c.caller_number();
            calls.push_back(std::move(info));
        }
        callbacks_.onCalls(calls);
    }
    channel_->receive(shared_from_this());
}

void AasdkPhoneStatusHandler::onChannelError(const aasdk::error::Error &e) {
    // 情報チャネルの切断は致命的ではない。セッション全体の終了は制御チャネル側の通知に任せる
    log(std::string("チャネルエラー: ") + e.what());
}

aasdk::channel::SendPromise::Pointer AasdkPhoneStatusHandler::makeSendPromise(const char *what) {
    return makeLoggingPromise(*strand_, callbacks_, "phone", what);
}

void AasdkPhoneStatusHandler::log(const std::string &message) const {
    if (callbacks_.onLog) {
        callbacks_.onLog("[phone] " + message);
    }
}

// ===========================================================================
// GenericNotification
// ===========================================================================

AasdkNotificationHandler::AasdkNotificationHandler(std::shared_ptr<boost::asio::io_service::strand> strand,
                                                   aasdk::messenger::IMessenger::Pointer messenger,
                                                   PhoneInfoCallbacks callbacks)
    : strand_(std::move(strand)),
      channel_(std::make_shared<aasdk::channel::genericnotification::GenericNotificationService>(
          *strand_, std::move(messenger))),
      callbacks_(std::move(callbacks)) {}

void AasdkNotificationHandler::start() { channel_->receive(shared_from_this()); }

void AasdkNotificationHandler::fillFeatures(proto::service::control::message::ServiceDiscoveryResponse &response) {
    auto *service = response.add_channels();
    service->set_id(static_cast<std::int32_t>(channel_->getId()));
    service->mutable_generic_notification_service();
}

void AasdkNotificationHandler::onChannelOpenRequest(
    const proto::service::control::message::ChannelOpenRequest &request) {
    log("チャネルオープン要求を受信 (service_id=" + std::to_string(request.service_id()) + ") → STATUS_SUCCESS");
    proto::service::control::message::ChannelOpenResponse response;
    response.set_status(proto::shared::MessageStatus::STATUS_SUCCESS);
    channel_->sendChannelOpenResponse(response, makeSendPromise("ChannelOpenResponse"));
    // 通知の受信を開始する(これを送らないと、スマホが通知を送ってこない可能性がある)
    channel_->sendSubscribe(makeSendPromise("Subscribe"));
    channel_->receive(shared_from_this());
}

void AasdkNotificationHandler::onNotification(
    const proto::service::genericnotification::message::GenericNotificationMessage &notification) {
    PhoneNoticeInfo info;
    info.id = notification.id();
    info.text = notification.text();
    log("通知を受信: id=" + info.id + " text=" + info.text);
    if (callbacks_.onNotice && !info.text.empty()) {
        callbacks_.onNotice(info);
    }

    proto::service::genericnotification::message::GenericNotificationAck ack;
    ack.set_id(notification.id());
    ack.set_handled(true);
    channel_->sendNotificationAck(ack, makeSendPromise("NotificationAck"));
    channel_->receive(shared_from_this());
}

void AasdkNotificationHandler::onChannelError(const aasdk::error::Error &e) {
    log(std::string("チャネルエラー: ") + e.what());
}

aasdk::channel::SendPromise::Pointer AasdkNotificationHandler::makeSendPromise(const char *what) {
    return makeLoggingPromise(*strand_, callbacks_, "notify", what);
}

void AasdkNotificationHandler::log(const std::string &message) const {
    if (callbacks_.onLog) {
        callbacks_.onLog("[notify] " + message);
    }
}

// ===========================================================================
// MediaPlaybackStatus
// ===========================================================================

AasdkPlaybackHandler::AasdkPlaybackHandler(std::shared_ptr<boost::asio::io_service::strand> strand,
                                           aasdk::messenger::IMessenger::Pointer messenger,
                                           PhoneInfoCallbacks callbacks)
    : strand_(std::move(strand)),
      channel_(std::make_shared<aasdk::channel::mediaplaybackstatus::MediaPlaybackStatusService>(
          *strand_, std::move(messenger))),
      callbacks_(std::move(callbacks)) {}

void AasdkPlaybackHandler::start() { channel_->receive(shared_from_this()); }

void AasdkPlaybackHandler::fillFeatures(proto::service::control::message::ServiceDiscoveryResponse &response) {
    auto *service = response.add_channels();
    service->set_id(static_cast<std::int32_t>(channel_->getId()));
    service->mutable_media_playback_service();
}

void AasdkPlaybackHandler::onChannelOpenRequest(const proto::service::control::message::ChannelOpenRequest &request) {
    log("チャネルオープン要求を受信 (service_id=" + std::to_string(request.service_id()) + ") → STATUS_SUCCESS");
    proto::service::control::message::ChannelOpenResponse response;
    response.set_status(proto::shared::MessageStatus::STATUS_SUCCESS);
    channel_->sendChannelOpenResponse(response, makeSendPromise("ChannelOpenResponse"));
    channel_->receive(shared_from_this());
}

void AasdkPlaybackHandler::onMetadataUpdate(const proto::service::mediaplayback::message::MediaPlaybackMetadata &metadata) {
    if (callbacks_.onTrack) {
        MediaTrackInfo info;
        info.song = metadata.song();
        info.artist = metadata.artist();
        info.album = metadata.album();
        info.durationSec = static_cast<int>(metadata.duration_seconds());
        callbacks_.onTrack(info);
    }
    channel_->receive(shared_from_this());
}

void AasdkPlaybackHandler::onPlaybackUpdate(const proto::service::mediaplayback::message::MediaPlaybackStatus &playback) {
    if (callbacks_.onPlayback) {
        MediaPlaybackInfo info;
        info.state = playback.has_state() ? static_cast<int>(playback.state()) : 1;
        info.source = playback.media_source();
        info.positionSec = static_cast<int>(playback.playback_seconds());
        callbacks_.onPlayback(info);
    }
    channel_->receive(shared_from_this());
}

void AasdkPlaybackHandler::onChannelError(const aasdk::error::Error &e) {
    log(std::string("チャネルエラー: ") + e.what());
}

aasdk::channel::SendPromise::Pointer AasdkPlaybackHandler::makeSendPromise(const char *what) {
    return makeLoggingPromise(*strand_, callbacks_, "media", what);
}

void AasdkPlaybackHandler::log(const std::string &message) const {
    if (callbacks_.onLog) {
        callbacks_.onLog("[media] " + message);
    }
}

} // namespace opencruise::aa
