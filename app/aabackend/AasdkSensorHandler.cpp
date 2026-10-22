/**
 * @file AasdkSensorHandler.cpp
 * @brief センサー(SensorSource)チャネルの最小実装。
 *
 * 走行状態は「制限なし」、夜間モードは「昼」を初期値として返す。
 * 実際の車両状態に応じた更新は、将来 CAN モデル等から送る。
 */
#include "AasdkSensorHandler.h"

#include <cmath>

#include <aasdk/Error/Error.hpp>
#include <aap_protobuf/service/Service.pb.h>
#include <aap_protobuf/service/control/message/ChannelOpenResponse.pb.h>
#include <aap_protobuf/service/sensorsource/SensorSourceService.pb.h>
#include <aap_protobuf/service/sensorsource/message/DrivingStatus.pb.h>
#include <aap_protobuf/service/sensorsource/message/FuelData.pb.h>
#include <aap_protobuf/service/sensorsource/message/Gear.pb.h>
#include <aap_protobuf/service/sensorsource/message/GearData.pb.h>
#include <aap_protobuf/service/sensorsource/message/LocationData.pb.h>
#include <aap_protobuf/service/sensorsource/message/ParkingBrakeData.pb.h>
#include <aap_protobuf/service/sensorsource/message/RpmData.pb.h>
#include <aap_protobuf/service/sensorsource/message/SpeedData.pb.h>
#include <aap_protobuf/service/sensorsource/message/NightModeData.pb.h>
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
    // OpenAuto の SensorService と同じ 3 種(走行状態 / 位置 / 夜間モード)に加え、
    // モックの車両データ送信用に 速度 / 回転数 / 燃料 / ギア / パーキングブレーキ も申告する。
    // 値を送るのは車両データ送信(sendVehicleData)が呼ばれたときだけで、呼ばれなければ何も送らない。
    using proto::service::sensorsource::message::SensorType;
    sensor->add_sensors()->set_sensor_type(SENSOR_DRIVING_STATUS_DATA);
    sensor->add_sensors()->set_sensor_type(proto::service::sensorsource::message::SENSOR_LOCATION);
    sensor->add_sensors()->set_sensor_type(SENSOR_NIGHT_MODE);
    for (const SensorType type : {proto::service::sensorsource::message::SENSOR_SPEED,
                                  proto::service::sensorsource::message::SENSOR_RPM,
                                  proto::service::sensorsource::message::SENSOR_FUEL,
                                  proto::service::sensorsource::message::SENSOR_GEAR,
                                  proto::service::sensorsource::message::SENSOR_PARKING_BRAKE}) {
        sensor->add_sensors()->set_sensor_type(type);
    }
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
 * @brief 昼夜モードを更新し、開始済みなら SensorBatch(night_mode_data) を送る。
 */
void AasdkSensorHandler::setNightMode(bool night) {
    auto self = shared_from_this();
    strand_->dispatch([self, night]() {
        if (self->nightMode_ == night) {
            return;
        }
        self->nightMode_ = night;
        if (!self->nightStarted_) {
            return; // 開始要求の応答時に最新値が送られる
        }
        proto::service::sensorsource::message::SensorBatch batch;
        batch.add_night_mode_data()->set_night_mode(night);
        self->channel_->sendSensorEventIndication(batch, self->makeSendPromise("SensorEvent(night)"));
        self->log(std::string("[sensor] 昼夜モードを送信しました: ") + (night ? "夜" : "昼"));
    });
}

/**
 * @brief 車両の状態を SensorBatch にして送る。開始要求のあったセンサーだけを詰める。
 *
 * 単位は次の想定(実機の Android Auto で挙動を確認して調整すること):
 *  速度 = m/s × 1000 / 回転数 = rpm × 1000 / 燃料 = % / 位置 = 度 × 1e7、方位 = 度 × 1e6、精度 = m × 1000
 */
void AasdkSensorHandler::sendVehicleData(const VehicleSnapshot &snapshot) {
    auto self = shared_from_this();
    strand_->dispatch([self, snapshot]() {
        namespace sm = proto::service::sensorsource::message;
        const auto started = [&self](int type) { return self->started_.count(type) > 0; };

        sm::SensorBatch batch;
        std::string sent;
        if (started(sm::SENSOR_SPEED)) {
            batch.add_speed_data()->set_speed_e3(static_cast<std::int32_t>(std::lround(snapshot.speedKmh / 3.6 * 1000.0)));
            sent += "速度 ";
        }
        if (started(sm::SENSOR_RPM)) {
            batch.add_rpm_data()->set_rpm_e3(snapshot.rpm * 1000);
            sent += "回転数 ";
        }
        if (started(sm::SENSOR_FUEL)) {
            auto *fuel = batch.add_fuel_data();
            fuel->set_fuel_level(snapshot.fuelPercent);
            fuel->set_low_fuel_warning(snapshot.lowFuel);
            sent += "燃料 ";
        }
        if (started(sm::SENSOR_GEAR)) {
            sm::Gear gear = sm::GEAR_PARK;
            switch (snapshot.gear) {
            case VehicleGear::Park: gear = sm::GEAR_PARK; break;
            case VehicleGear::Reverse: gear = sm::GEAR_REVERSE; break;
            case VehicleGear::Neutral: gear = sm::GEAR_NEUTRAL; break;
            case VehicleGear::Drive: gear = sm::GEAR_DRIVE; break;
            }
            batch.add_gear_data()->set_gear(gear);
            sent += "ギア ";
        }
        if (started(sm::SENSOR_PARKING_BRAKE)) {
            batch.add_parking_brake_data()->set_parking_brake(snapshot.parkingBrake);
            sent += "パーキングブレーキ ";
        }
        if (started(sm::SENSOR_LOCATION)) {
            auto *location = batch.add_location_data();
            location->set_latitude_e7(static_cast<std::int32_t>(std::lround(snapshot.latitude * 1e7)));
            location->set_longitude_e7(static_cast<std::int32_t>(std::lround(snapshot.longitude * 1e7)));
            location->set_accuracy_e3(5000);
            location->set_speed_e3(static_cast<std::int32_t>(std::lround(snapshot.speedKmh / 3.6 * 1000.0)));
            location->set_bearing_e6(static_cast<std::int32_t>(std::lround(snapshot.bearingDeg * 1e6)));
            sent += "位置 ";
        }
        if (sent.empty()) {
            return; // スマホがまだどのセンサーも開始していない
        }
        self->channel_->sendSensorEventIndication(batch, self->makeSendPromise("SensorEvent(vehicle)"));
        if (!self->loggedFirstVehicleSend_) {
            self->loggedFirstVehicleSend_ = true;
            self->log("車両データの送信を開始しました: " + sent);
        }
    });
}

/**
 * @brief センサー開始要求。応答送信後に初期値を1回送る。
 */
void AasdkSensorHandler::onSensorStartRequest(
    const proto::service::sensorsource::message::SensorRequest &request) {
    using proto::service::sensorsource::message::SENSOR_DRIVING_STATUS_DATA;
    using proto::service::sensorsource::message::SENSOR_NIGHT_MODE;

    const auto type = request.type();
    started_.insert(static_cast<int>(type));
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
        batch.add_night_mode_data()->set_night_mode(nightMode_);
        nightStarted_ = true;
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
