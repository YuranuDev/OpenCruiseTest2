/**
 * @file AasdkPhoneHandler.h
 * @brief スマートフォンの状態を受け取る 3 つのチャネル(PhoneStatus / GenericNotification / MediaPlaybackStatus)。
 *
 * いずれも「スマホ → 車載機」へ一方向に届く情報チャネルで、受け取った値を PhoneInfoCallbacks で上位へ流すだけ。
 * 映像・入力と違いセッションの成立には必須でないため、送信失敗や不正なメッセージはログに残すだけで、
 * セッションは終了しない(ウィジェットの情報が取れなくなるだけで、接続は維持する)。
 *
 *  - AasdkPhoneStatusHandler  : 通話状態(発信者・通話時間)と電波強度
 *  - AasdkNotificationHandler : スマホの汎用通知(id / text)。受信開始(Subscribe)を送り、届いた通知へ Ack を返す
 *  - AasdkPlaybackHandler     : 再生中の曲(曲名・アーティスト・アルバム・長さ)と再生状態・位置
 *
 * 3 つのクラスは同じ名前のコールバック(onChannelOpenRequest など)を別々のインターフェースから実装するため、
 * 1 つにまとめられず別クラスにしている。
 */
#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

#include <boost/asio.hpp>

#include <aasdk/Channel/GenericNotification/GenericNotificationService.hpp>
#include <aasdk/Channel/MediaPlaybackStatus/MediaPlaybackStatusService.hpp>
#include <aasdk/Channel/NavigationStatus/NavigationStatusService.hpp>
#include <aasdk/Channel/PhoneStatus/PhoneStatusService.hpp>
#include <aasdk/Channel/Promise.hpp>
#include <aasdk/Messenger/IMessenger.hpp>
#include <aap_protobuf/service/control/message/ChannelOpenRequest.pb.h>
#include <aap_protobuf/service/control/message/ServiceDiscoveryResponse.pb.h>

#include "PhoneInfo.h"

namespace opencruise::aa {

/// 3 チャネル共通の通知先とログ
struct PhoneInfoCallbacks {
    std::function<void(const std::string &)> onLog; ///< 診断ログ
    /// 電波強度(0〜4 に丸める前の値)
    std::function<void(int)> onSignal;
    /// 通話の一覧(通話が無ければ空)
    std::function<void(const std::vector<PhoneCallInfo> &)> onCalls;
    /// 汎用通知 1 件
    std::function<void(const PhoneNoticeInfo &)> onNotice;
    /// 再生中の曲の情報(曲が変わったとき)
    std::function<void(const MediaTrackInfo &)> onTrack;
    /// 再生状態・位置
    std::function<void(const MediaPlaybackInfo &)> onPlayback;
    std::function<void(const NavigationInfo &)> onNavigation;
};

/**
 * @brief PhoneStatus チャネル(通話状態・電波強度)。
 */
class AasdkPhoneStatusHandler : public aasdk::channel::phonestatus::IPhoneStatusServiceEventHandler,
                                public std::enable_shared_from_this<AasdkPhoneStatusHandler> {
public:
    AasdkPhoneStatusHandler(std::shared_ptr<boost::asio::io_service::strand> strand,
                            aasdk::messenger::IMessenger::Pointer messenger, PhoneInfoCallbacks callbacks);

    /** @brief 受信ループを開始する。 */
    void start();
    /** @brief ServiceDiscoveryResponse に PhoneStatus サービスを追記する。 */
    void fillFeatures(aap_protobuf::service::control::message::ServiceDiscoveryResponse &response);

    void onChannelOpenRequest(const aap_protobuf::service::control::message::ChannelOpenRequest &request) override;
    void onPhoneStatusUpdate(const aap_protobuf::service::phonestatus::message::PhoneStatus &status) override;
    void onChannelError(const aasdk::error::Error &e) override;

private:
    aasdk::channel::SendPromise::Pointer makeSendPromise(const char *what);
    void log(const std::string &message) const;

    std::shared_ptr<boost::asio::io_service::strand> strand_;
    std::shared_ptr<aasdk::channel::phonestatus::PhoneStatusService> channel_;
    PhoneInfoCallbacks callbacks_;
};

/**
 * @brief GenericNotification チャネル(スマホの通知)。
 *
 * チャネルを開いたあとに Subscribe を送ると、スマホが通知を送り始める想定。届いた通知には Ack を返す。
 * プロトコル上、通知に付くのは id / text / icon だけで、送信元アプリ名・本文・連絡先は無い。
 */
class AasdkNotificationHandler : public aasdk::channel::genericnotification::IGenericNotificationServiceEventHandler,
                                 public std::enable_shared_from_this<AasdkNotificationHandler> {
public:
    AasdkNotificationHandler(std::shared_ptr<boost::asio::io_service::strand> strand,
                             aasdk::messenger::IMessenger::Pointer messenger, PhoneInfoCallbacks callbacks);

    void start();
    void fillFeatures(aap_protobuf::service::control::message::ServiceDiscoveryResponse &response);

    void onChannelOpenRequest(const aap_protobuf::service::control::message::ChannelOpenRequest &request) override;
    void onNotification(
        const aap_protobuf::service::genericnotification::message::GenericNotificationMessage &notification) override;
    void onChannelError(const aasdk::error::Error &e) override;

private:
    aasdk::channel::SendPromise::Pointer makeSendPromise(const char *what);
    void log(const std::string &message) const;

    std::shared_ptr<boost::asio::io_service::strand> strand_;
    std::shared_ptr<aasdk::channel::genericnotification::GenericNotificationService> channel_;
    PhoneInfoCallbacks callbacks_;
};

/**
 * @brief MediaPlaybackStatus チャネル(再生中の曲・再生状態)。
 */
class AasdkPlaybackHandler : public aasdk::channel::mediaplaybackstatus::IMediaPlaybackStatusServiceEventHandler,
                             public std::enable_shared_from_this<AasdkPlaybackHandler> {
public:
    AasdkPlaybackHandler(std::shared_ptr<boost::asio::io_service::strand> strand,
                         aasdk::messenger::IMessenger::Pointer messenger, PhoneInfoCallbacks callbacks);

    void start();
    void fillFeatures(aap_protobuf::service::control::message::ServiceDiscoveryResponse &response);

    void onChannelOpenRequest(const aap_protobuf::service::control::message::ChannelOpenRequest &request) override;
    void onMetadataUpdate(const aap_protobuf::service::mediaplayback::message::MediaPlaybackMetadata &metadata) override;
    void onPlaybackUpdate(const aap_protobuf::service::mediaplayback::message::MediaPlaybackStatus &playback) override;
    void onChannelError(const aasdk::error::Error &e) override;

private:
    aasdk::channel::SendPromise::Pointer makeSendPromise(const char *what);
    void log(const std::string &message) const;

    std::shared_ptr<boost::asio::io_service::strand> strand_;
    std::shared_ptr<aasdk::channel::mediaplaybackstatus::MediaPlaybackStatusService> channel_;
    PhoneInfoCallbacks callbacks_;
};

/** @brief NavigationStatus チャネルの案内情報。 */
class AasdkNavigationHandler : public aasdk::channel::navigationstatus::INavigationStatusServiceEventHandler,
                              public std::enable_shared_from_this<AasdkNavigationHandler> {
public:
    AasdkNavigationHandler(std::shared_ptr<boost::asio::io_service::strand> strand,
                           aasdk::messenger::IMessenger::Pointer messenger, PhoneInfoCallbacks callbacks);
    void start();
    void fillFeatures(aap_protobuf::service::control::message::ServiceDiscoveryResponse &response);
    void onChannelOpenRequest(const aap_protobuf::service::control::message::ChannelOpenRequest &request) override;
    void onStatusUpdate(const aap_protobuf::service::navigationstatus::message::NavigationStatus &status) override;
    void onTurnEvent(const aap_protobuf::service::navigationstatus::message::NavigationNextTurnEvent &turn) override;
    void onDistanceEvent(const aap_protobuf::service::navigationstatus::message::NavigationNextTurnDistanceEvent &distance) override;
    void onStateUpdate(const aap_protobuf::service::navigationstatus::message::NavigationState &state) override;
    void onCurrentPosition(const aap_protobuf::service::navigationstatus::message::NavigationCurrentPosition &position) override;
    void onChannelError(const aasdk::error::Error &e) override;
private:
    void publish();
    void log(const std::string &message) const;
    std::shared_ptr<boost::asio::io_service::strand> strand_;
    std::shared_ptr<aasdk::channel::navigationstatus::NavigationStatusService> channel_;
    PhoneInfoCallbacks callbacks_;
    NavigationInfo info_;
    bool stateReceived_ = false; ///< NavigationState(steps)が届いている間は true。旧形式の通知で上書きしないために使う
};

} // namespace opencruise::aa
