/**
 * @file AasdkInputHandler.cpp
 * @brief 入力(InputSource)チャネルの最小実装。
 *
 * 映像解像度と同じタッチスクリーンを宣言し、スマートフォンからの
 * KeyBindingRequest に STATUS_SUCCESS を返す。入力イベントの送信は
 * 将来 Qt 側のタッチ/キー処理から行う。
 */
#include "AasdkInputHandler.h"

#include <aasdk/Error/Error.hpp>
#include <aap_protobuf/service/Service.pb.h>
#include <aap_protobuf/service/control/message/ChannelOpenResponse.pb.h>
#include <aap_protobuf/service/inputsource/InputSourceService.pb.h>
#include <aap_protobuf/service/media/sink/message/KeyCode.pb.h>
#include <aap_protobuf/service/media/sink/message/KeyBindingResponse.pb.h>
#include <aap_protobuf/shared/MessageStatus.pb.h>

namespace opencruise::aa {

namespace proto = aap_protobuf;

namespace {
// 映像サービス(VIDEO_800x480)とタッチ座標系を一致させる。
constexpr std::int32_t kTouchWidth = 800;
constexpr std::int32_t kTouchHeight = 480;
} // namespace

/**
 * @brief 入力チャネルを生成する。
 */
AasdkInputHandler::AasdkInputHandler(std::shared_ptr<boost::asio::io_service::strand> strand,
                                     aasdk::messenger::IMessenger::Pointer messenger, Callbacks callbacks)
    : strand_(std::move(strand)),
      channel_(std::make_shared<aasdk::channel::inputsource::InputSourceService>(*strand_,
                                                                                std::move(messenger))),
      callbacks_(std::move(callbacks)) {}

/**
 * @brief 入力チャネルの受信ループを開始する。
 */
void AasdkInputHandler::start() { channel_->receive(shared_from_this()); }

/**
 * @brief ServiceDiscoveryResponse に入力サービスを追記する。
 */
void AasdkInputHandler::fillFeatures(proto::service::control::message::ServiceDiscoveryResponse &response) {
    using proto::service::inputsource::InputSourceService;

    auto *service = response.add_channels();
    service->set_id(static_cast<std::int32_t>(channel_->getId()));

    auto *input = service->mutable_input_source_service();
    const std::int32_t keycodes[] = {
        proto::service::media::sink::message::KEYCODE_HOME,
        proto::service::media::sink::message::KEYCODE_BACK,
        proto::service::media::sink::message::KEYCODE_DPAD_UP,
        proto::service::media::sink::message::KEYCODE_DPAD_DOWN,
        proto::service::media::sink::message::KEYCODE_DPAD_LEFT,
        proto::service::media::sink::message::KEYCODE_DPAD_RIGHT,
        proto::service::media::sink::message::KEYCODE_DPAD_CENTER,
    };
    for (const auto keycode : keycodes) {
        input->add_keycodes_supported(keycode);
    }

    auto *touch = input->add_touchscreen();
    touch->set_width(kTouchWidth);
    touch->set_height(kTouchHeight);
}

/**
 * @brief チャネルオープン要求に成功を返す。
 */
void AasdkInputHandler::onChannelOpenRequest(
    const proto::service::control::message::ChannelOpenRequest &request) {
    log("[input] チャネルオープン要求を受信 (service_id=" + std::to_string(request.service_id()) +
        ") → STATUS_SUCCESS を返します");

    proto::service::control::message::ChannelOpenResponse response;
    response.set_status(proto::shared::MessageStatus::STATUS_SUCCESS);
    channel_->sendChannelOpenResponse(response, makeSendPromise("ChannelOpenResponse"));
    channel_->receive(shared_from_this());
}

/**
 * @brief スマートフォンが要求したキーバインドを受け付ける。
 */
void AasdkInputHandler::onKeyBindingRequest(
    const proto::service::media::sink::message::KeyBindingRequest &request) {
    log("[input] KeyBindingRequest を受信 (キー数=" + std::to_string(request.keycodes_size()) +
        ") → STATUS_SUCCESS を返します");

    proto::service::media::sink::message::KeyBindingResponse response;
    response.set_status(proto::shared::MessageStatus::STATUS_SUCCESS);
    channel_->sendKeyBindingResponse(response, makeSendPromise("KeyBindingResponse"));
    channel_->receive(shared_from_this());
}

/**
 * @brief チャネルエラー。中断は正常終了経路なので無視する。
 */
void AasdkInputHandler::onChannelError(const aasdk::error::Error &e) {
    if (e == aasdk::error::ErrorCode::OPERATION_ABORTED) {
        return;
    }
    if (callbacks_.onFatalError) {
        callbacks_.onFatalError(std::string("入力チャネルエラー: ") + e.what());
    }
}

/**
 * @brief 送信失敗をセッション終了エラーとして通知する Promise を作る。
 */
aasdk::channel::SendPromise::Pointer AasdkInputHandler::makeSendPromise(const char *what) {
    auto promise = aasdk::channel::SendPromise::defer(*strand_);
    promise->then([]() {},
                  [self = shared_from_this(), what = std::string(what)](const aasdk::error::Error &e) {
                      if (self->callbacks_.onFatalError) {
                          self->callbacks_.onFatalError("入力チャネル送信失敗(" + what + "): " + e.what());
                      }
                  });
    return promise;
}

/**
 * @brief 診断ログを上位へ流す。
 */
void AasdkInputHandler::log(const std::string &message) const {
    if (callbacks_.onLog) {
        callbacks_.onLog("[input] " + message);
    }
}

} // namespace opencruise::aa
