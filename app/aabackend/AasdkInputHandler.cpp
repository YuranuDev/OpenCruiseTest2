/**
 * @file AasdkInputHandler.cpp
 * @brief 入力(InputSource)チャネルの最小実装。
 *
 * 映像解像度と同じタッチスクリーンを宣言し、スマートフォンからの
 * KeyBindingRequest に STATUS_SUCCESS を返す。UI 側から渡されたタッチ入力は
 * InputReport(touch_event) として送る。キー入力の送信は未実装。
 */
#include "AasdkInputHandler.h"

#include <algorithm>
#include <chrono>

#include <aasdk/Error/Error.hpp>
#include <aap_protobuf/service/Service.pb.h>
#include <aap_protobuf/service/control/message/ChannelOpenResponse.pb.h>
#include <aap_protobuf/service/inputsource/InputSourceService.pb.h>
#include <aap_protobuf/service/inputsource/message/InputReport.pb.h>
#include <aap_protobuf/service/inputsource/message/PointerAction.pb.h>
#include <aap_protobuf/service/inputsource/message/TouchEvent.pb.h>
#include <aap_protobuf/service/media/sink/message/KeyCode.pb.h>
#include <aap_protobuf/service/media/sink/message/KeyBindingResponse.pb.h>
#include <aap_protobuf/shared/MessageStatus.pb.h>

namespace opencruise::aa {

namespace proto = aap_protobuf;

/**
 * @brief 入力チャネルを生成する。
 */
AasdkInputHandler::AasdkInputHandler(std::shared_ptr<boost::asio::io_service::strand> strand,
                                     aasdk::messenger::IMessenger::Pointer messenger, Callbacks callbacks,
                                     StreamSettings settings)
    : strand_(std::move(strand)),
      channel_(std::make_shared<aasdk::channel::inputsource::InputSourceService>(*strand_,
                                                                                std::move(messenger))),
      callbacks_(std::move(callbacks)),
      settings_(settings.sanitized()) {}

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

    // タッチ領域は映像解像度(VIDEO_800x480)と一致させる。値は TouchEvent.h で共有している。
    auto *touch = input->add_touchscreen();
    touch->set_width(settings_.width());
    touch->set_height(settings_.height());
}

/**
 * @brief タッチ入力を InputReport(touch_event) にして送る。
 */
void AasdkInputHandler::sendTouch(const TouchEvent &event) {
    using proto::service::inputsource::message::InputReport;
    using proto::service::inputsource::message::PointerAction;

    if (!ready_) {
        if (!notReadyLogged_) {
            notReadyLogged_ = true;
            log("[input] KeyBindingRequest への応答前なので、タッチ入力を送らずに捨てます");
        }
        return;
    }
    if (event.points.empty() || event.actionIndex >= event.points.size()) {
        log("[input] 不正なタッチ入力を破棄しました (指=" + std::to_string(event.points.size()) +
            ", action_index=" + std::to_string(event.actionIndex) + ")");
        return;
    }

    PointerAction action = PointerAction::ACTION_MOVED;
    switch (event.action) {
    case TouchAction::Down: action = PointerAction::ACTION_DOWN; break;
    case TouchAction::Up: action = PointerAction::ACTION_UP; break;
    case TouchAction::Move: action = PointerAction::ACTION_MOVED; break;
    case TouchAction::PointerDown: action = PointerAction::ACTION_POINTER_DOWN; break;
    case TouchAction::PointerUp: action = PointerAction::ACTION_POINTER_UP; break;
    }

    InputReport report;
    // 単位は µs(openauto と同じ。プロジェクトの資料に従う)。実機での確認は未実施。
    report.set_timestamp(static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::steady_clock::now().time_since_epoch()).count()));
    auto *touch = report.mutable_touch_event();
    for (const TouchPoint &point : event.points) {
        auto *data = touch->add_pointer_data();
        data->set_x(static_cast<std::uint32_t>(std::clamp<std::int32_t>(point.x, 0, settings_.width() - 1)));
        data->set_y(static_cast<std::uint32_t>(std::clamp<std::int32_t>(point.y, 0, settings_.height() - 1)));
        data->set_pointer_id(point.id);
    }
    touch->set_action_index(event.actionIndex);
    touch->set_action(action);

    if (!firstTouchLogged_) {
        firstTouchLogged_ = true;
        log("[input] 最初のタッチ入力を送信します (action=" + std::to_string(static_cast<int>(event.action)) +
            ", 指=" + std::to_string(event.points.size()) + ")");
    }
    channel_->sendInputReport(report, makeSendPromise("InputReport"));
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
    ready_ = true; // 以降はタッチ入力を送ってよい
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
