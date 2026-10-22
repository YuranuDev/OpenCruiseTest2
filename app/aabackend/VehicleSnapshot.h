/**
 * @file VehicleSnapshot.h
 * @brief 車両から取得した値を Android Auto へ送るための受け渡し用データ（Qt・aasdk のどちらにも依存しない）。
 *
 * UI 側(androidauto/)が値を詰め、接続層(aabackend/)がセンサーチャネルの SensorBatch に変換して送る。
 * 現状は動作確認用のモック値を詰めている。実車データ(CAN 等)へ差し替える場合も、この型のままでよい。
 */
#pragma once

namespace opencruise::aa {

/// ギアの状態
enum class VehicleGear { Park, Reverse, Neutral, Drive };

/**
 * @brief ある時点の車両の状態。
 */
struct VehicleSnapshot {
    int speedKmh = 0;       ///< 車速 [km/h]
    int rpm = 0;            ///< エンジン回転数 [rpm]
    int fuelPercent = 0;    ///< 燃料残量 [%]
    bool lowFuel = false;   ///< 低燃料警告
    VehicleGear gear = VehicleGear::Park;
    bool parkingBrake = true;
    double latitude = 0.0;  ///< 緯度 [度]
    double longitude = 0.0; ///< 経度 [度]
    double bearingDeg = 0.0; ///< 進行方位 [度。北=0、時計回り]
};

} // namespace opencruise::aa
