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

/// 「次の操作」に紐づく詳細(ロータリー・車線・読み上げ文・所要時間)を消す
void clearStepDetail(NavigationInfo &info) {
    info.roundaboutExitNumber = 0;
    info.roundaboutExitAngle = 0;
    info.cue.clear();
    info.lanes.clear();
    info.timeToStepSeconds = -1;
}

/// 次の操作(steps[0])の詳細を NavigationInfo に写す
void fillStepDetail(const proto::service::navigationstatus::message::NavigationStep &step, NavigationInfo &info) {
    // 次の操作までの秒数は NavigationCurrentPosition で更新されるので、ここでは消さずに残す
    const long long timeToStep = info.timeToStepSeconds;
    clearStepDetail(info);
    info.timeToStepSeconds = timeToStep;
    if (step.has_maneuver()) {
        const auto &maneuver = step.maneuver();
        info.roundaboutExitNumber = maneuver.has_roundabout_exit_number() ? maneuver.roundabout_exit_number() : 0;
        info.roundaboutExitAngle = maneuver.has_roundabout_exit_angle() ? maneuver.roundabout_exit_angle() : 0;
    }
    for (const auto &text : step.cue().alternate_text()) {
        if (!text.empty()) {
            info.cue = text;
            break;
        }
    }
    info.lanes.reserve(static_cast<std::size_t>(step.lanes_size()));
    for (const auto &lane : step.lanes()) {
        NavigationLaneInfo laneInfo;
        laneInfo.directions.reserve(static_cast<std::size_t>(lane.lane_directions_size()));
        for (const auto &direction : lane.lane_directions()) {
            NavigationLaneDirectionInfo directionInfo;
            directionInfo.shape = direction.has_shape() ? static_cast<int>(direction.shape()) : 0;
            directionInfo.highlighted = direction.has_is_highlighted() && direction.is_highlighted();
            laneInfo.directions.push_back(directionInfo);
        }
        info.lanes.push_back(std::move(laneInfo));
    }
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
        info_.distanceUnit = 0;
        info_.road.clear();
        info_.currentRoad.clear();
        info_.nextRoad.clear();
        info_.maneuver = 0;
        info_.side = 0;
        info_.nextManeuver = 0;
        info_.nextSide = 0;
        clearStepDetail(info_);
        info_.destinations.clear();
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
    info_.distanceUnit = 0;
    info_.nextManeuver = 0;
    info_.nextSide = 0;
    info_.nextRoad.clear();
    clearStepDetail(info_);
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
        fillStepDetail(step, info_);
    } else {
        info_.road.clear();
        info_.maneuver = 0;
        info_.side = 0;
        clearStepDetail(info_);
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

    // 目的地の住所。距離・時刻は NavigationCurrentPosition 側の値を、同じ並び順のまま残す
    info_.destinations.resize(static_cast<std::size_t>(state.destinations_size()));
    for (int i = 0; i < state.destinations_size(); ++i) {
        const auto &destination = state.destinations(i);
        info_.destinations[static_cast<std::size_t>(i)].address =
            destination.has_address() ? destination.address() : std::string();
    }
    publish();
    channel_->receive(shared_from_this());
}

void AasdkNavigationHandler::onCurrentPosition(
    const proto::service::navigationstatus::message::NavigationCurrentPosition &position) {
    // 次の操作までの距離と時間
    if (position.has_step_distance()) {
        const auto &stepDistance = position.step_distance();
        info_.timeToStepSeconds = stepDistance.has_time_to_step_seconds() ? stepDistance.time_to_step_seconds() : -1;
        if (stepDistance.has_distance()) {
            const auto &distance = stepDistance.distance();
            info_.distanceMeters = distance.has_meters() ? distance.meters() : -1;
            info_.distanceLabel = distance.has_display_value() ? distance.display_value() : std::string();
            info_.distanceUnit = distance.has_display_units() ? static_cast<int>(distance.display_units()) : 0;
        } else {
            info_.distanceMeters = -1;
            info_.distanceLabel.clear();
            info_.distanceUnit = 0;
        }
    } else {
        info_.distanceMeters = -1;
        info_.distanceLabel.clear();
        info_.distanceUnit = 0;
        info_.timeToStepSeconds = -1;
    }

    // 目的地ごとの残り距離・到着予定時刻・到着までの秒数(住所は NavigationState で入れた並び順に合わせる)
    const auto count = static_cast<std::size_t>(position.destination_distances_size());
    if (info_.destinations.size() < count) info_.destinations.resize(count);
    else if (info_.destinations.size() > count) {
        // 距離が届かない目的地は、古い値を残さない(住所だけ残す)
        for (std::size_t i = count; i < info_.destinations.size(); ++i) {
            auto &d = info_.destinations[i];
            d.distanceMeters = -1;
            d.distanceLabel.clear();
            d.distanceUnit = 0;
            d.eta.clear();
            d.secondsToArrival = -1;
        }
    }
    for (std::size_t i = 0; i < count; ++i) {
        const auto &source = position.destination_distances(static_cast<int>(i));
        auto &d = info_.destinations[i];
        if (source.has_distance()) {
            const auto &distance = source.distance();
            d.distanceMeters = distance.has_meters() ? distance.meters() : -1;
            d.distanceLabel = distance.has_display_value() ? distance.display_value() : std::string();
            d.distanceUnit = distance.has_display_units() ? static_cast<int>(distance.display_units()) : 0;
        } else {
            d.distanceMeters = -1;
            d.distanceLabel.clear();
            d.distanceUnit = 0;
        }
        d.eta = source.has_estimated_time_at_arrival() ? source.estimated_time_at_arrival() : std::string();
        d.secondsToArrival = source.has_time_to_arrival_seconds() ? source.time_to_arrival_seconds() : -1;
    }

    // 現在走っている道路
    info_.currentRoad = position.has_current_road() && position.current_road().has_name()
                            ? position.current_road().name() : std::string();
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
