/**
 * @file AasdkInputHandler.h
 * @brief aasdk の入力(InputSource)チャネルを処理するクラス。
 *
 * Android Auto の入力サービスは、車載機側がタッチ/キー入力を受け付けることを
 * Service Discovery で宣言し、スマートフォンからの KeyBindingRequest に応答する。
 * チャネルを開いてキーバインドを受け付けるほか、UI 側から渡されたタッチ入力を
 * InputReport としてスマートフォンへ送る（sendTouch）。キー入力の送信は未実装。
 */
#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <string>

#include <boost/asio.hpp>

#include "TouchEvent.h"

// aasdk の同ヘッダは Error を自前で include していないため、先に読み込む
#include "StreamSettings.h"
#include <aasdk/Error/Error.hpp>
#include <aasdk/Channel/InputSource/IInputSourceServiceEventHandler.hpp>
#include <aasdk/Channel/InputSource/InputSourceService.hpp>
#include <aasdk/Channel/Promise.hpp>
#include <aasdk/Messenger/IMessenger.hpp>
#include <aap_protobuf/service/control/message/ChannelOpenRequest.pb.h>
#include <aap_protobuf/service/control/message/ServiceDiscoveryResponse.pb.h>
#include <aap_protobuf/service/media/sink/message/KeyBindingRequest.pb.h>

namespace opencruise::aa {

/**
 * @brief 入力チャネルのイベントハンドラ兼オーナー。
 */
class AasdkInputHandler : public aasdk::channel::inputsource::IInputSourceServiceEventHandler,
                          public std::enable_shared_from_this<AasdkInputHandler> {
public:
    /**
     * @brief 入力ハンドラから上位(セッション)への通知先。
     */
    struct Callbacks {
        std::function<void(const std::string &)> onFatalError; ///< セッションを終了すべきエラー
        std::function<void(const std::string &)> onLog;        ///< 診断ログ
    };

    /**
     * @brief 入力チャネルを生成する(受信ループはまだ開始しない)。
     */
    AasdkInputHandler(std::shared_ptr<boost::asio::io_service::strand> strand,
                      aasdk::messenger::IMessenger::Pointer messenger, Callbacks callbacks,
                      StreamSettings settings = {});

    /**
     * @brief 入力チャネルの受信ループを開始する。
     */
    void start();

    /**
     * @brief タッチ入力を InputReport としてスマートフォンへ送る。
     *
     * strand 上で呼ぶこと。KeyBindingRequest に応答する前（スマートフォンが入力を
     * 受け付ける準備をする前）に届いた入力は、送らずに捨てる。
     * 不正な入力（指が 0 本、actionIndex が範囲外）も捨てる。座標は申告したタッチ領域に収める。
     */
    void sendTouch(const TouchEvent &event);

    /**
     * @brief ServiceDiscoveryResponse に入力サービス(キー/タッチ)を追記する。
     */
    void fillFeatures(aap_protobuf::service::control::message::ServiceDiscoveryResponse &response);

    // ---- IInputSourceServiceEventHandler ----
    void onChannelOpenRequest(const aap_protobuf::service::control::message::ChannelOpenRequest &request) override;
    void onKeyBindingRequest(
        const aap_protobuf::service::media::sink::message::KeyBindingRequest &request) override;
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
    std::shared_ptr<aasdk::channel::inputsource::InputSourceService> channel_;
    Callbacks callbacks_;
    StreamSettings settings_;       ///< タッチ領域の大きさ(=映像解像度)の元
    bool ready_ = false;            ///< KeyBindingRequest に応答済み。以降は入力を送ってよい(strand 上でのみ触る)
    bool notReadyLogged_ = false;   ///< 準備前に入力を捨てたことを 1 回だけ記録するため
    bool firstTouchLogged_ = false; ///< 最初のタッチ送信を 1 回だけ記録するため
};

} // namespace opencruise::aa
