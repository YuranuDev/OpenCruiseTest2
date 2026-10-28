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
#include <aap_protobuf/service/navigationstatus/message/NavigationNextTurnDistanceEvent.pb.h>
#include <aap_protobuf/service/navigationstatus/message/NavigationNextTurnEvent.pb.h>
#include <aap_protobuf/service/navigationstatus/message/NavigationStatus.pb.h>
#include <aap_protobuf/service/navigationstatus/message/NavigationState.pb.h>
#include <aap_protobuf/service/navigationstatus/message/NavigationCurrentPosition.pb.h>
#include <aap_protobuf/service/navigationstatus/message/NavigationManeuver.pb.h>
#include <aap_protobuf/service/navigationstatus/NavigationStatusService.pb.h>
#include <aap_protobuf/service/phonestatus/message/PhoneStatus.pb.h>
#include <aap_protobuf/shared/MessageStatus.pb.h>

namespace opencruise::aa {

namespace proto = aap_protobuf;

namespace {

void normalizeManeuver(int type, int &maneuver, int &side) {
    using Maneuver = proto::service::navigationstatus::message::NavigationManeuver;
    switch (type) {
    case Maneuver::KEEP_LEFT: case Maneuver::TURN_SLIGHT_LEFT: case Maneuver::TURN_NORMAL_LEFT:
    case Maneuver::TURN_SHARP_LEFT: case Maneuver::ON_RAMP_SLIGHT_LEFT: case Maneuver::ON_RAMP_NORMAL_LEFT:
    case Maneuver::ON_RAMP_SHARP_LEFT: case Maneuver::OFF_RAMP_SLIGHT_LEFT: case Maneuver::OFF_RAMP_NORMAL_LEFT:
    case Maneuver::FORK_LEFT: case Maneuver::MERGE_LEFT: case Maneuver::U_TURN_LEFT:
    case Maneuver::DESTINATION_LEFT: case Maneuver::ROUNDABOUT_ENTER_AND_EXIT_CCW:
    case Maneuver::ROUNDABOUT_ENTER_AND_EXIT_CCW_WITH_ANGLE:
        side = 1; break;
    case Maneuver::KEEP_RIGHT: case Maneuver::TURN_SLIGHT_RIGHT: case Maneuver::TURN_NORMAL_RIGHT:
    case Maneuver::TURN_SHARP_RIGHT: case Maneuver::ON_RAMP_SLIGHT_RIGHT: case Maneuver::ON_RAMP_NORMAL_RIGHT:
    case Maneuver::ON_RAMP_SHARP_RIGHT: case Maneuver::OFF_RAMP_SLIGHT_RIGHT: case Maneuver::OFF_RAMP_NORMAL_RIGHT:
    case Maneuver::FORK_RIGHT: case Maneuver::MERGE_RIGHT: case Maneuver::U_TURN_RIGHT:
    case Maneuver::DESTINATION_RIGHT: case Maneuver::ROUNDABOUT_ENTER_AND_EXIT_CW:
    case Maneuver::ROUNDABOUT_ENTER_AND_EXIT_CW_WITH_ANGLE:
        side = 2; break;
    default: side = 0; break;
    }
    if (type >= Maneuver::TURN_SLIGHT_LEFT && type <= Maneuver::TURN_SLIGHT_RIGHT) maneuver = 3;
    else if (type >= Maneuver::TURN_NORMAL_LEFT && type <= Maneuver::TURN_NORMAL_RIGHT) maneuver = 4;
    else if (type >= Maneuver::TURN_SHARP_LEFT && type <= Maneuver::TURN_SHARP_RIGHT) maneuver = 5;
    else if (type == Maneuver::U_TURN_LEFT || type == Maneuver::U_TURN_RIGHT) maneuver = 6;
    else if (type >= Maneuver::ON_RAMP_SLIGHT_LEFT && type <= Maneuver::ON_RAMP_U_TURN_RIGHT) maneuver = 7;
    else if (type >= Maneuver::OFF_RAMP_SLIGHT_LEFT && type <= Maneuver::OFF_RAMP_NORMAL_RIGHT) maneuver = 8;
    else if (type == Maneuver::FORK_LEFT || type == Maneuver::FORK_RIGHT) maneuver = 9;
    else if (type >= Maneuver::MERGE_LEFT && type <= Maneuver::MERGE_SIDE_UNSPECIFIED) maneuver = 10;
    else if (type >= Maneuver::ROUNDABOUT_ENTER && type <= Maneuver::ROUNDABOUT_ENTER_AND_EXIT_CCW_WITH_ANGLE) maneuver = 11;
    else if (type == Maneuver::STRAIGHT) maneuver = 14;
    else if (type == Maneuver::DESTINATION || type == Maneuver::DESTINATION_STRAIGHT ||
             type == Maneuver::DESTINATION_LEFT || type == Maneuver::DESTINATION_RIGHT) maneuver = 19;
    else maneuver = 0;
}

/// 送信完了を待つ Promise。失敗してもセッションは終了せず、ログに残すだけにする
aasdk::channel::SendPromise::Pointer makeLoggingPromise(boost::asio::io_service::strand &strand,
                                                        const PhoneInfoCallbacks &callbacks, const char *tag,
                                                        const char *what) {
    auto promise = aasdk::channel::SendPromise::defer(strand);
    promise->then([]() {},
                  [onLog = callbacks.onLog, tag = std::string(tag), what = std::string(what)](
                      const aasdk::error::Error &e) {
                      if (onLog) {
                          onLog("[" + tag + "] send failed (" + what + "): " + e.what());
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
    log("channel open request received (service_id=" + std::to_string(request.service_id()) + ") → STATUS_SUCCESS");
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
    log(std::string("channel error: ") + e.what());
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
    log("channel open request received (service_id=" + std::to_string(request.service_id()) + ") → STATUS_SUCCESS");
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
    log("notification received: id=" + info.id + " text=" + info.text);
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
    log(std::string("channel error: ") + e.what());
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
    log("channel open request received (service_id=" + std::to_string(request.service_id()) + ") → STATUS_SUCCESS");
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
        if (metadata.has_album_art()) {
            info.albumArt = metadata.album_art();
        }
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
    log(std::string("channel error: ") + e.what());
}

aasdk::channel::SendPromise::Pointer AasdkPlaybackHandler::makeSendPromise(const char *what) {
    return makeLoggingPromise(*strand_, callbacks_, "media", what);
}

void AasdkPlaybackHandler::log(const std::string &message) const {
    if (callbacks_.onLog) {
        callbacks_.onLog("[media] " + message);
    }
}

// ===========================================================================
// NavigationStatus
// ===========================================================================

AasdkNavigationHandler::AasdkNavigationHandler(std::shared_ptr<boost::asio::io_service::strand> strand,
                                               aasdk::messenger::IMessenger::Pointer messenger,
                                               PhoneInfoCallbacks callbacks)
    : strand_(std::move(strand)),
      channel_(std::make_shared<aasdk::channel::navigationstatus::NavigationStatusService>(*strand_, std::move(messenger))),
      callbacks_(std::move(callbacks)) {}

void AasdkNavigationHandler::start() { channel_->receive(shared_from_this()); }

void AasdkNavigationHandler::fillFeatures(proto::service::control::message::ServiceDiscoveryResponse &response) {
    auto *service = response.add_channels();
    service->set_id(static_cast<std::int32_t>(channel_->getId()));
    auto *navigation = service->mutable_navigation_status_service();
    navigation->set_minimum_interval_ms(500);
    navigation->set_type(proto::service::navigationstatus::NavigationStatusService::ENUM);
}

void AasdkNavigationHandler::onChannelOpenRequest(const proto::service::control::message::ChannelOpenRequest &request) {
    log("[navigation] channel open request received (service_id=" + std::to_string(request.service_id()) + ")");
    proto::service::control::message::ChannelOpenResponse response;
    response.set_status(proto::shared::MessageStatus::STATUS_SUCCESS);
    channel_->sendChannelOpenResponse(response, makeLoggingPromise(*strand_, callbacks_, "navigation", "ChannelOpenResponse"));
    channel_->receive(shared_from_this());
}

void AasdkNavigationHandler::onStatusUpdate(const proto::service::navigationstatus::message::NavigationStatus &status) {
    info_.status = static_cast<int>(status.status());
    if (info_.status != 1) {
        info_.distanceMeters = -1;
        info_.distanceLabel.clear();
        info_.road.clear();
        info_.nextRoad.clear();
        info_.maneuver = 0;
        info_.side = 0;
        info_.nextManeuver = 0;
        info_.nextSide = 0;
    }
    publish();
    channel_->receive(shared_from_this());
}

void AasdkNavigationHandler::onTurnEvent(const proto::service::navigationstatus::message::NavigationNextTurnEvent &turn) {
    info_.status = 1;
    info_.road = turn.road();
    info_.maneuver = turn.has_event() ? static_cast<int>(turn.event()) : 0;
    info_.side = turn.has_turn_side() ? static_cast<int>(turn.turn_side()) : 0;
    info_.distanceMeters = -1;
    info_.distanceLabel.clear();
    info_.nextManeuver = 0;
    info_.nextSide = 0;
    info_.nextRoad.clear();
    publish();
    channel_->receive(shared_from_this());
}

void AasdkNavigationHandler::onDistanceEvent(const proto::service::navigationstatus::message::NavigationNextTurnDistanceEvent &distance) {
    info_.status = 1;
    info_.distanceMeters = distance.distance_meters();
    info_.distanceLabel.clear();
    publish();
    channel_->receive(shared_from_this());
}

void AasdkNavigationHandler::onStateUpdate(const proto::service::navigationstatus::message::NavigationState &state) {
    info_.status = state.steps_size() > 0 ? 1 : 2;
    if (state.steps_size() > 0) {
        const auto &step = state.steps(0);
        info_.road = step.has_road() && step.road().has_name() ? step.road().name() : std::string();
        if (step.has_maneuver() && step.maneuver().has_type()) {
            normalizeManeuver(static_cast<int>(step.maneuver().type()), info_.maneuver, info_.side);
        } else {
            info_.maneuver = 0;
            info_.side = 0;
        }
    } else {
        info_.road.clear();
        info_.maneuver = 0;
        info_.side = 0;
    }
    if (state.steps_size() > 1) {
        const auto &step = state.steps(1);
        info_.nextRoad = step.has_road() && step.road().has_name() ? step.road().name() : std::string();
        if (step.has_maneuver() && step.maneuver().has_type()) {
            normalizeManeuver(static_cast<int>(step.maneuver().type()), info_.nextManeuver, info_.nextSide);
        } else {
            info_.nextManeuver = 0;
            info_.nextSide = 0;
        }
    } else {
        info_.nextRoad.clear();
        info_.nextManeuver = 0;
        info_.nextSide = 0;
    }
    publish();
    channel_->receive(shared_from_this());
}

void AasdkNavigationHandler::onCurrentPosition(
    const proto::service::navigationstatus::message::NavigationCurrentPosition &position) {
    if (position.has_step_distance() && position.step_distance().has_distance()) {
        const auto &distance = position.step_distance().distance();
        info_.distanceMeters = distance.has_meters() ? distance.meters() : -1;
        info_.distanceLabel = distance.has_display_value() ? distance.display_value() : std::string();
    } else {
        info_.distanceMeters = -1;
        info_.distanceLabel.clear();
    }
    publish();
    channel_->receive(shared_from_this());
}

void AasdkNavigationHandler::onChannelError(const aasdk::error::Error &error) {
    log(std::string("[navigation] channel error: ") + error.what());
}

void AasdkNavigationHandler::publish() {
    if (callbacks_.onNavigation) callbacks_.onNavigation(info_);
}

void AasdkNavigationHandler::log(const std::string &message) const {
    if (callbacks_.onLog) callbacks_.onLog(message);
}

} // namespace opencruise::aa
