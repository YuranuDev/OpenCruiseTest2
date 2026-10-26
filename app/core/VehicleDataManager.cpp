/**
 * @file VehicleDataManager.cpp
 * @brief 車両データ管理クラスの実装
 */
#include "VehicleDataManager.h"

#include <QDebug>
#include <algorithm>
#include <array>
#include <cmath>

namespace opencruise {

namespace {
constexpr double kPi = 3.14159265358979323846;

// ---- 車両の諸元(1.6L ターボのコンパクトカーを想定) ----
constexpr double kMassKg = 1300.0;              ///< 車両重量(乗員込み)
constexpr double kTireRadiusM = 0.316;          ///< タイヤ半径(205/55R16 相当)
constexpr double kFinalDrive = 4.105;           ///< 最終減速比
constexpr double kDrivetrainEff = 0.9;          ///< 駆動系の効率
constexpr std::array<double, 6> kGearRatios = {3.538, 2.060, 1.404, 1.000, 0.713, 0.582};
constexpr double kIdleRpm = 780.0;
constexpr double kRedlineRpm = 6800.0;          ///< レブリミット
constexpr double kAeroCoef = 0.42;              ///< 空気抵抗 0.5 × ρ × Cd × A [N/(m/s)²]
constexpr double kRollingN = 150.0;             ///< 転がり抵抗 [N]
constexpr double kMaxBoostBar = 1.35;           ///< ブーストの最大目標値(ゲージ圧)
constexpr double kVacuumBar = -0.68;            ///< アクセルを閉じたときの負圧
constexpr double kTankLiters = 45.0;            ///< 燃料タンク容量
constexpr double kAmbientC = 22.0;              ///< 外気温
constexpr double kThermostatC = 86.0;           ///< サーモスタットの開弁温度(全開は +10℃)
constexpr double kShiftTimeS = 0.35;            ///< 変速にかかる時間(駆動力が抜ける)

/// a から b へ t(0〜1)で補間
double lerp(double a, double b, double t) { return a + (b - a) * t; }

/// 1 次遅れで target へ近づける(tau: 時定数 [s])
double approach(double value, double target, double tau, double dt) {
    return value + (target - value) * (1.0 - std::exp(-dt / std::max(1e-3, tau)));
}
} // namespace

/**
 * @brief 100ms 周期で値を更新する。燃料は 4〜8 割、水温は外気温から始める(冷間始動)。
 */
VehicleDataManager::VehicleDataManager(QObject *parent)
    : QObject(parent)
    , headlightState_(HeadlightState::UNKNOWN)
    , rng_(std::random_device{}()) {
    std::uniform_real_distribution<double> fuel(0.4, 0.8);
    fuelLiters_ = kTankLiters * fuel(rng_);
    coolantTempC_ = kAmbientC;
    oilTempC_ = kAmbientC;
    batteryVolts_ = 12.6;
    rpm_ = kIdleRpm;
    boostBar_ = kVacuumBar + 0.08;
    phase_ = Phase::Stop;
    phaseLeftS_ = 3.0;

    elapsed_.start();
    updateTimer_.setInterval(100);
    connect(&updateTimer_, &QTimer::timeout, this, &VehicleDataManager::update);
    update();
    updateTimer_.start();
}

/**
 * @brief デストラクタ
 */
VehicleDataManager::~VehicleDataManager() = default;

/**
 * @brief ヘッドライト状態を取得する
 * @return ヘッドライト状態
 */
HeadlightState VehicleDataManager::getHeadlightState() const {
    return headlightState_;
}

/**
 * @brief ヘッドライト状態を設定する
 * @param state ヘッドライト状態
 */
void VehicleDataManager::setHeadlightState(HeadlightState state) {
    if (headlightState_ != state) {
        headlightState_ = state;
        emit headlightStateChanged(state);
        emit nightModeChanged(isNightMode());
    }
}

/**
 * @brief 昼夜モードを取得する（ヘッドライト状態に基づく）
 * @return true: 夜モード, false: 昼モード
 */
bool VehicleDataManager::isNightMode() const {
    return (headlightState_ == HeadlightState::ON);
}

/**
 * @brief 回転数ごとの自然吸気分のトルク(全開時)。低回転は細く、3000〜5000rpm が山、高回転で落ちる。
 */
double VehicleDataManager::baseTorqueNm(double rpm) {
    static constexpr std::array<double, 7> kRpm = {800, 1500, 2500, 3500, 4500, 5800, 7000};
    static constexpr std::array<double, 7> kNm = {70, 92, 110, 120, 122, 112, 90};
    if (rpm <= kRpm.front()) return kNm.front();
    for (std::size_t i = 1; i < kRpm.size(); ++i) {
        if (rpm <= kRpm[i]) {
            return lerp(kNm[i - 1], kNm[i], (rpm - kRpm[i - 1]) / (kRpm[i] - kRpm[i - 1]));
        }
    }
    return kNm.back();
}

double VehicleDataManager::rpmFromSpeed(double speedMs, int gear) const {
    const double wheelRpm = speedMs / kTireRadiusM * 60.0 / (2.0 * kPi);
    return wheelRpm * kGearRatios[static_cast<std::size_t>(gear - 1)] * kFinalDrive;
}

/**
 * @brief 走行パターンの次の区間を選ぶ。停車の後は必ず発進し、ときどき全開加速を混ぜる。
 */
void VehicleDataManager::nextPhase() {
    std::uniform_real_distribution<double> u(0.0, 1.0);
    const double r = u(rng_);
    const double kmh = speedMs_ * 3.6;

    if (phase_ != Phase::Stop && kmh < 70.0 && r < 0.22) {
        // 信号待ち
        phase_ = Phase::Stop;
        targetMs_ = 0.0;
        phaseLeftS_ = lerp(5.0, 20.0, u(rng_));
        return;
    }
    if (r > 0.82) {
        // 全開加速(合流・追い越しなど)
        phase_ = Phase::Pull;
        targetMs_ = (std::max(kmh, 40.0) + lerp(35.0, 70.0, u(rng_))) / 3.6;
        targetMs_ = std::min(targetMs_, 150.0 / 3.6);
        maxThrottle_ = 1.0;
        phaseLeftS_ = 20.0;
        return;
    }
    // 巡航(街中〜高速)。目標速度とアクセルの踏み方を毎回変える
    static constexpr std::array<double, 8> kTargets = {30, 40, 50, 60, 60, 80, 100, 110};
    std::uniform_int_distribution<std::size_t> pick(0, kTargets.size() - 1);
    phase_ = Phase::Cruise;
    targetMs_ = (kTargets[pick(rng_)] + lerp(-5.0, 5.0, u(rng_))) / 3.6;
    maxThrottle_ = lerp(0.3, 0.75, u(rng_));
    phaseLeftS_ = lerp(12.0, 35.0, u(rng_));
}

/**
 * @brief 目標速度との差からアクセルとブレーキを決める(人の操作らしく、ペダルはゆっくり動かす)。
 */
void VehicleDataManager::driveControl(double dt, double &brakeDecel) {
    brakeDecel = 0.0;
    double wantThrottle = 0.0;
    const double err = targetMs_ - speedMs_;

    if (phase_ == Phase::Stop) {
        brakeDecel = speedMs_ > 0.0 ? std::clamp(0.8 + speedMs_ * 0.12, 0.8, 3.2) : 0.0;
    } else if (phase_ == Phase::Pull && err > 0.5) {
        wantThrottle = 1.0;
    } else if (err < -1.5) {
        // 目標より速い: アクセルを離し、差が大きければブレーキ
        brakeDecel = std::clamp((-err - 1.5) * 0.35, 0.0, 2.5);
    } else {
        // 走行抵抗に釣り合う分 + 速度差に比例した分
        const double cruiseForce = kAeroCoef * speedMs_ * speedMs_ + kRollingN;
        const double ratio = kGearRatios[static_cast<std::size_t>(gear_ - 1)] * kFinalDrive;
        const double needNm = cruiseForce * kTireRadiusM / (ratio * kDrivetrainEff);
        const double feedForward = needNm / (baseTorqueNm(std::max(rpm_, kIdleRpm)) * 1.15);
        wantThrottle = std::clamp(feedForward + err * 0.12, 0.0, maxThrottle_);
    }

    // ペダルの動く速さ(踏むのは 1.5/s、離すのは 3/s)
    const double rate = wantThrottle > throttle_ ? 1.5 : 3.0;
    throttle_ += std::clamp(wantThrottle - throttle_, -rate * dt, rate * dt);
}

/**
 * @brief 1 ステップ分、運転者・駆動系・エンジン・ターボ・水温・燃料を進める。
 */
void VehicleDataManager::update() {
    const qint64 nowMs = elapsed_.elapsed();
    const double dt = std::clamp(static_cast<double>(nowMs - lastMs_) / 1000.0, 0.02, 0.5);
    lastMs_ = nowMs;
    std::normal_distribution<double> noise(0.0, 1.0);

    // ---- 運転者 ----
    phaseLeftS_ -= dt;
    const bool reached = phase_ == Phase::Pull && speedMs_ >= targetMs_ - 0.5;
    if (phaseLeftS_ <= 0.0 || reached) {
        if (reached) {
            // 全開加速のあとは、その速度で少し巡航する
            phase_ = Phase::Cruise;
            maxThrottle_ = 0.5;
            phaseLeftS_ = 10.0;
        } else {
            nextPhase();
        }
    }
    double brakeDecel = 0.0;
    driveControl(dt, brakeDecel);

    // ---- 変速(AT 相当。アクセルを踏むほど高回転まで引っ張る。踏み込むとキックダウン) ----
    if (shiftLeftS_ > 0.0) {
        shiftLeftS_ -= dt;
    } else if (speedMs_ > 0.5) {
        const double upAt = lerp(2200.0, 6300.0, std::pow(throttle_, 1.3));
        const double downAt = lerp(1150.0, 2600.0, throttle_);
        const double rpmNow = rpmFromSpeed(speedMs_, gear_);
        if (gear_ < static_cast<int>(kGearRatios.size()) && rpmNow > upAt) {
            ++gear_;
            shiftLeftS_ = kShiftTimeS;
        } else if (gear_ > 1 && rpmNow < downAt) {
            --gear_;
            shiftLeftS_ = kShiftTimeS * 0.7;
        } else if (gear_ > 1 && throttle_ > 0.85 && rpmFromSpeed(speedMs_, gear_ - 1) < 5600.0) {
            --gear_;   // キックダウン
            shiftLeftS_ = kShiftTimeS * 0.7;
        }
    } else {
        gear_ = 1;
    }

    // ---- エンジン回転数(低速ではトルコンが滑る) ----
    const double coupled = rpmFromSpeed(speedMs_, gear_);
    const double slipRpm = kIdleRpm + throttle_ * 2200.0;   // 発進時はアクセル開度なりに回転が上がる
    double targetRpm = std::max(coupled, speedMs_ < 0.3 ? kIdleRpm + throttle_ * 1800.0 : std::min(slipRpm, coupled + 900.0));
    targetRpm = std::max(targetRpm, kIdleRpm);
    rpm_ = approach(rpm_, std::min(targetRpm, kRedlineRpm + 100.0), shiftLeftS_ > 0.0 ? 0.12 : 0.08, dt);
    const bool limiter = rpm_ >= kRedlineRpm;

    // ---- ターボ(回転数で過給が立ち上がり、アクセル開度で目標が決まる。上がるときは遅れ = ターボラグ) ----
    const double spool = std::clamp((rpm_ - 1600.0) / 1800.0, 0.0, 1.0);
    const double openness = std::pow(throttle_, 1.4);
    double targetBoost = lerp(kVacuumBar, kMaxBoostBar * spool, openness);
    if (throttle_ < 0.05) {
        targetBoost = kVacuumBar - std::min(0.12, (rpm_ - kIdleRpm) / 30000.0);   // 高回転でアクセルを離すと負圧が深い
    } else if (rpm_ < 1200.0) {
        targetBoost = std::min(targetBoost, -0.35);
    }
    if (shiftLeftS_ > 0.0 || limiter) {
        targetBoost = std::min(targetBoost, 0.1);   // 変速・リミッター中は抜ける(ブローオフ)
    }
    const bool rising = targetBoost > boostBar_;
    boostBar_ = approach(boostBar_, targetBoost, rising ? lerp(0.9, 0.35, spool) : 0.18, dt);
    // 全開で立ち上がるときのオーバーシュート(ウェイストゲートが開くまでの山)
    if (rising && openness > 0.85 && spool > 0.9) {
        boostBar_ += 0.25 * dt * (kMaxBoostBar + 0.3 - boostBar_);
    }
    boostBar_ += noise(rng_) * 0.006;

    // ---- 駆動力と車速 ----
    double torqueNm = 0.0;
    if (shiftLeftS_ <= 0.0 && !limiter) {
        const double boostGain = 1.0 + 0.8 * std::max(0.0, boostBar_) / kMaxBoostBar;
        torqueNm = throttle_ * baseTorqueNm(rpm_) * boostGain;
    }
    if (throttle_ < 0.05) {
        torqueNm = -(8.0 + rpm_ * 0.006);   // エンジンブレーキ
    }
    const double ratio = kGearRatios[static_cast<std::size_t>(gear_ - 1)] * kFinalDrive;
    double driveN = torqueNm * ratio * kDrivetrainEff / kTireRadiusM;
    if (speedMs_ < 0.3 && torqueNm < 0.0) {
        driveN = 0.0;
    }
    const double resistN = speedMs_ > 0.05 ? kAeroCoef * speedMs_ * speedMs_ + kRollingN : 0.0;
    const double accel = (driveN - resistN) / kMassKg - brakeDecel;
    speedMs_ = std::max(0.0, speedMs_ + accel * dt);
    if (phase_ == Phase::Stop && speedMs_ < 0.15) {
        speedMs_ = 0.0;
    }

    // ---- 燃料(出力から消費量を出す。アイドリングでも少し減る) ----
    const double omega = rpm_ * 2.0 * kPi / 60.0;
    const double powerKw = std::max(0.0, torqueNm) * omega / 1000.0;
    const double litersPerHour = 0.7 * (rpm_ / kIdleRpm) * 0.6 + powerKw * 0.34;   // 燃料消費率 約 250g/kWh
    fuelLiters_ = std::max(0.0, fuelLiters_ - litersPerHour * dt / 3600.0);

    // ---- 水温(発熱で暖まり、サーモスタットが開くとラジエーターで冷える。走行風で冷えやすい) ----
    const double heatInKw = 4.0 * (rpm_ / kIdleRpm) * 0.5 + powerKw * 0.9;
    const double openFrac = std::clamp((coolantTempC_ - kThermostatC) / 10.0, 0.0, 1.0);
    const double radiatorKw = openFrac * (coolantTempC_ - kAmbientC) * (0.55 + speedMs_ * 0.035);
    const double lossKw = (coolantTempC_ - kAmbientC) * 0.06;
    const double heatCapacityKjPerC = 45.0;   // 冷却水 + エンジン本体の熱容量(暖機に数分かかる程度)
    coolantTempC_ += (heatInKw - radiatorKw - lossKw) * dt / heatCapacityKjPerC;

    // ---- 油温(水温より遅れて暖まる。負荷が高いと水温より高くなる) ----
    const double oilTarget = coolantTempC_ + 3.0 + std::min(28.0, powerKw * 0.35);
    oilTempC_ = approach(oilTempC_, oilTarget, 150.0, dt);

    // ---- 油圧(回転数に比例。冷えて粘度が高いほど高く、リリーフ弁で約 5.5bar に頭打ち) ----
    const double viscosity = std::clamp(1.0 + (90.0 - oilTempC_) / 60.0, 0.8, 2.0);
    const double oilTarget2 = std::min(5.5, 0.25 + rpm_ / 1000.0 * 1.1 * viscosity);
    oilPressureBar_ = approach(oilPressureBar_, oilTarget2, 0.25, dt) + noise(rng_) * 0.015;

    // ---- 電圧(発電機が約 14.2V に保つ。低回転・高負荷では少し下がる) ----
    const double voltTarget = 14.25 - (rpm_ < 1000.0 ? 0.3 : 0.0) - std::min(0.25, powerKw * 0.004);
    batteryVolts_ = approach(batteryVolts_, voltTarget, 1.5, dt) + noise(rng_) * 0.01;

    // ---- 公開値(センサーらしく少し揺らす) ----
    speedKmh_ = speedMs_ * 3.6;
    const double rpmShown = rpm_ + noise(rng_) * (speedMs_ < 0.3 ? 12.0 : 6.0);
    rpm_ = std::max(kIdleRpm * 0.9, rpmShown);
    fuelPercent_ = fuelLiters_ / kTankLiters * 100.0;
    updateEngineState(dt);
    emit changed();
}

void VehicleDataManager::updateEngineState(double dt) {
    if (!engineRunning_) {
        aboveStartS_ = rpm_ >= kEngineStartRpm ? aboveStartS_ + dt : 0.0;
        if (aboveStartS_ >= kEngineConfirmSec) {
            engineRunning_ = true;
            runningS_ = 0.0;
            qInfo() << "[vehicle] エンジン始動とみなしました(" << rpm_ << "rpm)";
            emit engineStateChanged();
        }
        return;
    }
    // 停止(エンジン OFF)は判定しない(キー位置で判断する予定)。始動後は警告を有効にするまで数えるだけ
    if (warningsArmed_) {
        return;
    }
    runningS_ += dt;
    if (runningS_ >= kWarnSettleSec) {
        warningsArmed_ = true;
        qInfo() << "[vehicle] メーターの警告を有効にしました";
        emit engineStateChanged();
    }
}

} // namespace opencruise
