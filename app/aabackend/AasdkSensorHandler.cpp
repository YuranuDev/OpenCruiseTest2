/**
 * @file AasdkSensorHandler.cpp
 * @brief センサー(SensorSource)チャネルの最小実装。
 *
 * 走行状態は「制限なし」、夜間モードは「昼」を初期値として返す。
 * 実際の車両状態に応じた更新は、将来 CAN モデル等から送る。
 */
#include "AasdkSensorHandler.h"

#include <aasdk/Error/Error.hpp>
#include <aap_protobuf/service/Service.pb.h>
#include <aap_protobuf/service/control/message/ChannelOpenResponse.pb.h>
#include <aap_protobuf/service/sensorsource/SensorSourceService.pb.h>
#include <aap_protobuf/service/sensorsource/message/DrivingStatus.pb.h>
#include <aap_protobuf/service/sensorsource/message/NightMode.pb.h>
#include <aap_protobuf/service/sensorsource/message/Sensor.pb.h>
#include <aap_protobuf/service/sensorsource/message/SensorBatch.pb.h>
#include <aap_protobuf/service/sensorsource/message/SensorStartResponseMessage.pb.h>
#include <aap_protobuf/service/sensorsource/message/SensorType.pb.h>
#include <aap_protobuf/shared/MessageStatus.pb.h>

namespace opencruise::aa {

namespace proto = aap_protobuf;

/**
 * @brief センサーチャネルを生成する。
 */
AasdkSensorHandler::AasdkSensorHandler(std::shared_ptr<boost::asio::io_service::strand> strand,
                                       aasdk::messenger::IMessenger::Pointer messenger, Callbacks callbacks)
    : strand_(std::move(strand)),
      channel_(std::make_shared<aasdk::channel::sensorsource::SensorSourceService>(*strand_,
                                                                                   std::move(messenger))),
      callbacks_(std::move(callbacks)) {}

/**
 * @brief センサーチャネルの受信ループを開始する。
 */
void AasdkSensorHandler::start() { channel_->receive(shared_from_this()); }

/**
 * @brief ServiceDiscoveryResponse にセンサーサービスを追記する。
 */
void AasdkSensorHandler::fillFeatures(proto::service::control::message::ServiceDiscoveryResponse &response) {
    using proto::service::sensorsource::message::SENSOR_DRIVING_STATUS_DATA;
    using proto::service::sensorsource::message::SENSOR_NIGHT_MODE;

    auto *service = response.add_channels();
    service->set_id(static_cast<std::int32_t>(channel_->getId()));

    auto *sensor = service->mutable_sensor_source_service();
    sensor->add_sensors()->set_type(SENSOR_DRIVING_STATUS_DATA);
    sensor->add_sensors()->set_type(SENSOR_NIGHT_MODE);
}

/**
 * @brief チャネルオープン要求に成功を返す。
 */
void AasdkSensorHandler::onChannelOpenRequest(
    const proto::service::control::message::ChannelOpenRequest &request) {
    log("[sensor] チャネルオープン要求を受信 (service_id=" + std::to_string(request.service_id()) +
        ") → STATUS_SUCCESS を返します");

    proto::service::control::message::ChannelOpenResponse response;
    response.set_status(proto::shared::MessageStatus::STATUS_SUCCESS);
    channel_->sendChannelOpenResponse(response, makeSendPromise("ChannelOpenResponse"));
    channel_->receive(shared_from_this());
}

/**
 * @brief センサー開始要求。応答送信後に初期値を1回送る。
 */
void AasdkSensorHandler::onSensorStartRequest(
    const proto::service::sensorsource::message::SensorRequest &request) {
    using proto::service::sensorsource::message::SENSOR_DRIVING_STATUS_DATA;
    using proto::service::sensorsource::message::SENSOR_NIGHT_MODE;

    const auto type = request.type();
    log("[sensor] SensorStartRequest を受信 (type=" + std::to_string(static_cast<int>(type)) + ")");

    proto::service::sensorsource::message::SensorStartResponseMessage response;
    response.set_status(proto::shared::MessageStatus::STATUS_SUCCESS);

    proto::service::sensorsource::message::SensorBatch batch;
    bool hasInitialValue = false;
    if (type == SENSOR_DRIVING_STATUS_DATA) {
        batch.add_driving_status_data()->set_status(
            proto::service::sensorsource::message::DRIVE_STATUS_UNRESTRICTED);
        hasInitialValue = true;
    } else if (type == SENSOR_NIGHT_MODE) {
        batch.add_night_mode_data()->set_night_mode(false);
        hasInitialValue = true;
    }

    auto promise = aasdk::channel::SendPromise::defer(*strand_);
    promise->then(
        [self = shared_from_this(), batch = std::move(batch), hasInitialValue]() {
            if (hasInitialValue) {
                self->channel_->sendSensorEventIndication(batch, self->makeSendPromise("SensorEvent"));
            }
        },
        [self = shared_from_this()](const aasdk::error::Error &e) {
            if (self->callbacks_.onFatalError) {
                self->callbacks_.onFatalError(std::string("センサーチャネル送信失敗: ") + e.what());
            }
        });
    channel_->sendSensorStartResponse(response, std::move(promise));
    channel_->receive(shared_from_this());
}

/**
 * @brief チャネルエラー。中断は正常終了経路なので無視する。
 */
void AasdkSensorHandler::onChannelError(const aasdk::error::Error &e) {
    if (e == aasdk::error::ErrorCode::OPERATION_ABORTED) {
        return;
    }
    if (callbacks_.onFatalError) {
        callbacks_.onFatalError(std::string("センサーチャネルエラー: ") + e.what());
    }
}

/**
 * @brief 送信失敗をセッション終了エラーとして通知する Promise を作る。
 */
aasdk::channel::SendPromise::Pointer AasdkSensorHandler::makeSendPromise(const char *what) {
    auto promise = aasdk::channel::SendPromise::defer(*strand_);
    promise->then([]() {},
                  [self = shared_from_this(), what = std::string(what)](const aasdk::error::Error &e) {
                      if (self->callbacks_.onFatalError) {
                          self->callbacks_.onFatalError("センサーチャネル送信失敗(" + what + "): " + e.what());
                      }
                  });
    return promise;
}

/**
 * @brief 診断ログを上位へ流す。
 */
void AasdkSensorHandler::log(const std::string &message) const {
    if (callbacks_.onLog) {
        callbacks_.onLog("[sensor] " + message);
    }
}

} // namespace opencruise::aa
