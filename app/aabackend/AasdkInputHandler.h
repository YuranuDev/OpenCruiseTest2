/**
 * @file AasdkInputHandler.h
 * @brief aasdk の入力(InputSource)チャネルを処理するクラス。
 *
 * Android Auto の入力サービスは、車載機側がタッチ/キー入力を受け付けることを
 * Service Discovery で宣言し、スマートフォンからの KeyBindingRequest に応答する。
 * 実際の入力イベント送信は Qt 側から行う想定だが、最小構成では
 * 「チャネルを開いてキーバインドを受け付ける」ところまでを担当する。
 */
#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <string>

#include <boost/asio.hpp>

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
                      aasdk::messenger::IMessenger::Pointer messenger, Callbacks callbacks);

    /**
     * @brief 入力チャネルの受信ループを開始する。
     */
    void start();

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
};

} // namespace opencruise::aa
