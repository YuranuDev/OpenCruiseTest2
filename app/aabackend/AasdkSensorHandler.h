/**
 * @file AasdkSensorHandler.h
 * @brief aasdk のセンサー(SensorSource)チャネルを処理するクラス。
 *
 * Android Auto では車載機が車両センサー(走行状態/夜間モード)を提供する。
 * 最小構成として、対応センサーを Service Discovery で宣言し、
 * SensorStartRequest に初期値を返す。
 */
#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <string>

#include <boost/asio.hpp>

#include <aasdk/Channel/Promise.hpp>
#include <aasdk/Channel/SensorSource/ISensorSourceServiceEventHandler.hpp>
#include <aasdk/Channel/SensorSource/SensorSourceService.hpp>
#include <aasdk/Messenger/IMessenger.hpp>
#include <aap_protobuf/service/control/message/ChannelOpenRequest.pb.h>
#include <aap_protobuf/service/control/message/ServiceDiscoveryResponse.pb.h>
#include <aap_protobuf/service/sensorsource/message/SensorRequest.pb.h>

namespace opencruise::aa {

/**
 * @brief センサーチャネルのイベントハンドラ兼オーナー。
 */
class AasdkSensorHandler : public aasdk::channel::sensorsource::ISensorSourceServiceEventHandler,
                           public std::enable_shared_from_this<AasdkSensorHandler> {
public:
    /**
     * @brief センサーハンドラから上位(セッション)への通知先。
     */
    struct Callbacks {
        std::function<void(const std::string &)> onFatalError; ///< セッションを終了すべきエラー
        std::function<void(const std::string &)> onLog;        ///< 診断ログ
    };

    /**
     * @brief センサーチャネルを生成する(受信ループはまだ開始しない)。
     */
    AasdkSensorHandler(std::shared_ptr<boost::asio::io_service::strand> strand,
                       aasdk::messenger::IMessenger::Pointer messenger, Callbacks callbacks);

    /**
     * @brief センサーチャネルの受信ループを開始する。
     */
    void start();

    /**
     * @brief 昼夜モードを設定する。センサー開始済みなら Android Auto へ即時に送信する（どのスレッドからでも可）。
     */
    void setNightMode(bool night);

    /**
     * @brief ServiceDiscoveryResponse にセンサーサービスを追記する。
     */
    void fillFeatures(aap_protobuf::service::control::message::ServiceDiscoveryResponse &response);

    // ---- ISensorSourceServiceEventHandler ----
    void onChannelOpenRequest(const aap_protobuf::service::control::message::ChannelOpenRequest &request) override;
    void onSensorStartRequest(
        const aap_protobuf::service::sensorsource::message::SensorRequest &request) override;
    void onChannelError(const aasdk::error::Error &e) override;

private:
    /**
     * @brief 送信完了を待つ Promise を作る。失敗時はセッション終了エラーとして通知する。
     */
    aasdk::channel::SendPromise::Pointer makeSendPromise(const char *what);

    /**
     * @brief 診断ログを上位へ流す。
     */
    void log(const std::string &message) const;

    std::shared_ptr<boost::asio::io_service::strand> strand_;
    std::shared_ptr<aasdk::channel::sensorsource::SensorSourceService> channel_;
    Callbacks callbacks_;
    bool nightMode_ = false;    ///< 現在の昼夜モード(strand 上でのみ触る)
    bool nightStarted_ = false; ///< スマホが NIGHT_MODE センサーを開始済みか
};

} // namespace opencruise::aa
