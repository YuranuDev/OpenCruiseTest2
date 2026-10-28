/**
 * @file VehicleDataManager.cpp
 * @brief 車両データ管理クラスの実装
 */
#include "VehicleDataManager.h"

#include <QDebug>
#include <QSettings>
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

// ---- フリーホイール(惰性走行) ----
constexpr double kFreewheelMinKmh = 25.0;       ///< この速度以上でアクセルを離すと切り離す
constexpr double kFreewheelExitKmh = 18.0;      ///< 惰性走行中にこの速度まで下がったら、つなぎ直す
constexpr double kFreewheelDelayS = 0.6;        ///< アクセルを離してから切り離すまでの間
constexpr double kResyncTimeS = 0.3;            ///< つなぎ直すときに、回転を車速に合わせる時間(駆動力が抜ける)

// ---- 値の変わる速さの上限(エンジンやターボの重さで、一瞬では変わらないようにする) ----
constexpr double kRpmRiseRate = 4500.0;         ///< 回転が上がる速さの上限 [rpm/s](キックダウン・踏み込みでも 0.1 秒で 450rpm まで)
constexpr double kRpmFallRate = 3500.0;         ///< 回転が下がる速さの上限 [rpm/s](変速で約 1000rpm 落ちるのに 0.3 秒ほど)
constexpr double kBoostRiseRate = 2.5;          ///< ブーストが上がる速さの上限 [bar/s]
constexpr double kBoostFallRate = 3.0;          ///< ブーストが抜ける速さの上限 [bar/s](ブローオフでも 0.1 秒で 0.3bar まで)
constexpr double kCvtStepRate = 3.5;            ///< 疑似変速で段を切り替える速さ [変速比/s]

// ---- CVT(ベルト式。トルクコンバーター付き) ----
constexpr double kCvtMaxRatio = 2.631;          ///< いちばん低い変速比(発進側)
constexpr double kCvtMinRatio = 0.378;          ///< いちばん高い変速比(巡航側)
constexpr double kCvtFinalDrive = 4.4;          ///< CVT の最終減速比
constexpr double kCvtEff = 0.86;                ///< CVT の駆動系の効率(ベルト・油圧の分、AT より少し低い)
/// 大きく踏んだときの疑似変速(ステップ変速)の 7 段の変速比
constexpr std::array<double, 7> kCvtSteps = {2.40, 1.72, 1.30, 1.02, 0.82, 0.66, 0.53};
constexpr double kCvtStepUpRpm = 6100.0;        ///< 疑似変速で次の段へ上げる回転数
constexpr double kCvtStepEnter = 0.8;           ///< 疑似変速に入るアクセル開度
constexpr double kCvtStepLeave = 0.55;          ///< 疑似変速をやめるアクセル開度

QSettings openStore() {
    return QSettings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"),
                     QStringLiteral("OpenCruise"));
}

/// アクセル開度(0〜1)に対するトルクの割合。実際の車のように、踏み始めで大きく効き、奥ではゆるやかになる
/// (開度 20% で約 4 割、50% で約 2/3)。巡航に要るアクセルが浅くなり、CVT の目標回転数も上がりすぎない
double pedalTorqueFrac(double throttle) { return std::pow(std::clamp(throttle, 0.0, 1.0), 0.6); }
/// pedalTorqueFrac の逆(トルクの割合から開度)
double throttleForFrac(double frac) { return std::pow(std::clamp(frac, 0.0, 1.0), 1.0 / 0.6); }

/// a から b へ t(0〜1)で補間
double lerp(double a, double b, double t) { return a + (b - a) * t; }

/// 1 次遅れで target へ近づける(tau: 時定数 [s])
double approach(double value, double target, double tau, double dt) {
    return value + (target - value) * (1.0 - std::exp(-dt / std::max(1e-3, tau)));
}

/// 1 次遅れで近づけたうえで、1 秒あたりの変化を上限(上がる速さ rise・下がる速さ fall)までに抑える
double approachLimited(double value, double target, double tau, double dt, double rise, double fall) {
    const double next = approach(value, target, tau, dt);
    return std::clamp(next, value - fall * dt, value + rise * dt);
}
} // namespace

/**
 * @brief 100ms 周期で値を更新する。燃料は 4〜8 割、水温は外気温から始める(冷間始動)。
 */
VehicleDataManager::VehicleDataManager(QObject *parent)
    : QObject(parent)
    , headlightState_(HeadlightState::UNKNOWN)
    , rng_(std::random_device{}()) {
    {
        QSettings store = openStore();
        transmission_ = store.value(QStringLiteral("mock/transmission"), 0).toInt() == 1 ? Transmission::Cvt
                                                                                          : Transmission::At;
        style_ = static_cast<DriveStyle>(std::clamp(store.value(QStringLiteral("mock/driveStyle"), 1).toInt(), 0, 2));
        mockGauges_ = store.value(QStringLiteral("mock/gaugeData"), true).toBool();
        mockFreewheel_ = store.value(QStringLiteral("mock/freewheel"), true).toBool();
    }
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
 * @brief 変速機を切り替える。走行中でも回転数が飛ばないよう、今の総減速比に近い所から始める。
 */
void VehicleDataManager::setMockTransmission(int value) {
    const Transmission next = value == 1 ? Transmission::Cvt : Transmission::At;
    if (next == transmission_) return;
    const double overall = overallRatio();
    transmission_ = next;
    if (next == Transmission::Cvt) {
        cvtRatio_ = std::clamp(overall / kCvtFinalDrive, kCvtMinRatio, kCvtMaxRatio);
        cvtStepMode_ = false;
    } else {
        // いちばん近い総減速比のギア
        int best = 1;
        for (int g = 1; g <= static_cast<int>(kGearRatios.size()); ++g) {
            if (std::abs(kGearRatios[g - 1] * kFinalDrive - overall)
                < std::abs(kGearRatios[best - 1] * kFinalDrive - overall)) best = g;
        }
        gear_ = best;
        shiftLeftS_ = 0.0;
    }
    openStore().setValue(QStringLiteral("mock/transmission"), static_cast<int>(next));
    emit mockSettingsChanged();
}

void VehicleDataManager::setMockGauges(bool enabled) {
    if (enabled == mockGauges_) return;
    mockGauges_ = enabled;
    openStore().setValue(QStringLiteral("mock/gaugeData"), enabled);
    qInfo() << "[vehicle] メーター・グラフのダミーデータ:" << (enabled ? "使う" : "使わない(データなし)");
    emit dataAvailableChanged();
    emit engineStateChanged();   // warningsArmed も変わる
}

void VehicleDataManager::setMockFreewheel(bool enabled) {
    if (enabled == mockFreewheel_) return;
    mockFreewheel_ = enabled;
    openStore().setValue(QStringLiteral("mock/freewheel"), enabled);
    qInfo() << "[vehicle] フリーホイール(惰性走行):" << (enabled ? "使う" : "使わない");
    emit mockSettingsChanged();
}

void VehicleDataManager::setMockDriveStyle(int value) {
    const DriveStyle next = static_cast<DriveStyle>(std::clamp(value, 0, 2));
    if (next == style_) return;
    style_ = next;
    openStore().setValue(QStringLiteral("mock/driveStyle"), static_cast<int>(next));
    emit mockSettingsChanged();
}

/**
 * @brief 運転のしかたごとの値。
 *  穏やか: じわっと踏み、全開加速はほとんどしない。早めに変速(CVT は低い回転のまま)し、ブレーキも弱い
 *  普通  : これまでのモックと同じ
 *  アグレッシブ: 深く・速く踏み、全開加速が多い。高回転まで引っ張り、ブレーキも強い
 */
const VehicleDataManager::StyleParams &VehicleDataManager::paramsFor(DriveStyle style) {
    static const StyleParams kGentle = {0.15, 0.40, 0.04, 0.65, 25.0, 0.6, 1.5, 0.06, 0.7, 0.18, 1900.0, -150.0, 1.4};
    static const StyleParams kNormal = {0.30, 0.75, 0.18, 1.00, 50.0, 1.5, 3.0, 0.12, 1.0, 0.22, 2200.0, 0.0, 0.9};
    static const StyleParams kAggressive = {0.55, 1.00, 0.38, 1.00, 70.0, 3.5, 5.0, 0.25, 1.5, 0.26, 2700.0, 450.0, 0.45};
    switch (style) {
    case DriveStyle::Gentle: return kGentle;
    case DriveStyle::Aggressive: return kAggressive;
    default: return kNormal;
    }
}

double VehicleDataManager::rpmPerMs() {
    return 1.0 / kTireRadiusM * 60.0 / (2.0 * kPi);
}

double VehicleDataManager::transmissionRatio() const {
    if (transmission_ == Transmission::Cvt) return cvtRatio_;
    return kGearRatios[static_cast<std::size_t>(gear_ - 1)];
}

double VehicleDataManager::overallRatio() const {
    if (transmission_ == Transmission::Cvt) return cvtRatio_ * kCvtFinalDrive;
    return kGearRatios[static_cast<std::size_t>(gear_ - 1)] * kFinalDrive;
}

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
    const StyleParams &p = params();
    const double r = u(rng_);
    const double kmh = speedMs_ * 3.6;

    if (phase_ != Phase::Stop && kmh < 70.0 && r < p.stopChance) {
        // 信号待ち
        phase_ = Phase::Stop;
        targetMs_ = 0.0;
        phaseLeftS_ = lerp(5.0, 20.0, u(rng_));
        return;
    }
    if (r > 1.0 - p.pullChance) {
        // 全開加速(合流・追い越しなど)。穏やかな運転では踏み切らない
        phase_ = Phase::Pull;
        targetMs_ = (std::max(kmh, 40.0) + lerp(p.pullGainKmh * 0.5, p.pullGainKmh, u(rng_))) / 3.6;
        targetMs_ = std::min(targetMs_, 150.0 / 3.6);
        maxThrottle_ = p.pullThrottle;
        phaseLeftS_ = 20.0;
        return;
    }
    // 巡航(街中〜高速)。目標速度とアクセルの踏み方を毎回変える
    static constexpr std::array<double, 8> kTargets = {30, 40, 50, 60, 60, 80, 100, 110};
    std::uniform_int_distribution<std::size_t> pick(0, kTargets.size() - 1);
    phase_ = Phase::Cruise;
    targetMs_ = (kTargets[pick(rng_)] + lerp(-5.0, 5.0, u(rng_))) / 3.6;
    maxThrottle_ = lerp(p.cruiseThrottleMin, p.cruiseThrottleMax, u(rng_));
    phaseLeftS_ = lerp(12.0, 35.0, u(rng_));
}

/**
 * @brief 目標速度との差からアクセルとブレーキを決める(人の操作らしく、ペダルはゆっくり動かす)。
 */
void VehicleDataManager::driveControl(double dt, double &brakeDecel) {
    brakeDecel = 0.0;
    double wantThrottle = 0.0;
    const double err = targetMs_ - speedMs_;
    const StyleParams &p = params();

    if (launchHoldS_ > 0.0) {
        // 発進: ブレーキを離し、クリープで動き出してから(運転のしかたで変わる間をおいて)アクセルを踏む
        launchHoldS_ -= dt;
    } else if (phase_ == Phase::Stop) {
        // 止まるまではブレーキで減速し、止まったら(クリープで動かないよう)踏んだままにする
        brakeDecel = speedMs_ > 0.0 ? std::clamp((0.8 + speedMs_ * 0.12) * p.brakeScale, 0.6, 4.5) : 1.2;
    } else if (phase_ == Phase::Pull && err > 0.5) {
        wantThrottle = maxThrottle_;
    } else if (err < -1.5) {
        // 目標より速い: アクセルを離し、差が大きければブレーキ。
        // 惰性走行(フリーホイール)中は、少し速いくらいならブレーキを踏まずに惰性で落とす(約 15km/h 速いまで)
        const double coastMargin = freewheel_ ? 4.0 : 1.5;
        brakeDecel = std::clamp((-err - coastMargin) * 0.35 * p.brakeScale, 0.0, 2.5 * p.brakeScale);
    } else if (freewheel_ && err < 1.5) {
        // 惰性走行中: 目標より少し(約 5km/h)遅くなるまでは踏まずに惰性で走る(すぐ踏み直して行ったり来たりしない)
        wantThrottle = 0.0;
    } else {
        // 走行抵抗に釣り合う分 + 速度差に比例した分
        const double cruiseForce = kAeroCoef * speedMs_ * speedMs_ + kRollingN;
        const double eff = transmission_ == Transmission::Cvt ? kCvtEff : kDrivetrainEff;
        const double needNm = cruiseForce * kTireRadiusM / (overallRatio() * eff);
        const double feedForward = throttleForFrac(needNm / (baseTorqueNm(std::max(rpm_, kIdleRpm)) * 1.15));
        wantThrottle = std::clamp(feedForward + err * p.speedGain, 0.0, maxThrottle_);
    }

    // ペダルの動く速さ(運転のしかたで変わる。普通は踏むのが 1.5/s、離すのが 3/s)
    const double rate = wantThrottle > throttle_ ? p.pedalUpRate : p.pedalDownRate;
    throttle_ += std::clamp(wantThrottle - throttle_, -rate * dt, rate * dt);
}

/**
 * @brief 1 ステップ分、運転者・駆動系・エンジン・ターボ・水温・燃料を進める。
 */
void VehicleDataManager::update() {
    const qint64 nowMs = elapsed_.elapsed();
    const double dt = std::clamp(static_cast<double>(nowMs - lastMs_) / 1000.0, 0.02, 0.5);
    lastMs_ = nowMs;
    step(dt);
}

/**
 * @brief AT の変速。アクセルを踏むほど高回転まで引っ張る(運転のしかたで変速点が変わる)。踏み込むとキックダウン。
 */
void VehicleDataManager::updateAt(double /*dt*/) {
    if (shiftLeftS_ > 0.0) return;
    if (speedMs_ <= 0.5) {
        gear_ = 1;
        return;
    }
    const StyleParams &p = params();
    const double upAt = lerp(p.atUpshiftLow, 6300.0, std::pow(throttle_, 1.3));
    const double downAt = lerp(1150.0, 2600.0, throttle_) + (p.atUpshiftLow - 2200.0) * 0.3;
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
}

/**
 * @brief CVT の変速比。アクセル開度と車速から目標回転数を決め、変速比をその回転数になるよう連続的に動かす。
 *  - 軽く踏む: 目標回転数が低い(1200〜2000rpm 前後)ので、変速比が高い側へ動いて回転は低いまま速度だけ伸びる
 *  - 踏み増す: 目標回転数が上がる。低い側への変速は速く、高い側への変速はゆっくりなので、
 *              回転が先に上がって張り付き、そのまま速度が伸びる(ラバーバンド感)
 *  - 大きく踏む(kCvtStepEnter 以上): 7 段の疑似変速。段を固定して回転を上げ、kCvtStepUpRpm で次の段へ
 *  - アクセルを離す: 目標回転数が下がって高い側へ。止まるにつれて、いちばん低い側へ戻る
 */
void VehicleDataManager::updateCvt(double dt) {
    const StyleParams &p = params();
    const double kmh = speedMs_ * 3.6;
    const double perRatio = rpmPerMs() * std::max(speedMs_, 0.01) * kCvtFinalDrive;   // 変速比 1 あたりの回転数

    // 疑似変速に入る・やめる
    if (!cvtStepMode_ && throttle_ >= kCvtStepEnter && kmh > 8.0) {
        cvtStepMode_ = true;
        // 回転が上がりすぎない、いちばん低い段から
        cvtStep_ = static_cast<int>(kCvtSteps.size()) - 1;
        for (int s = 0; s < static_cast<int>(kCvtSteps.size()); ++s) {
            if (perRatio * kCvtSteps[s] < kCvtStepUpRpm - 700.0) { cvtStep_ = s; break; }
        }
    } else if (cvtStepMode_ && (throttle_ < kCvtStepLeave || kmh < 5.0)) {
        cvtStepMode_ = false;
    }

    double target = kCvtMaxRatio;
    double rate = 1.0;
    if (cvtStepMode_) {
        if (perRatio * kCvtSteps[cvtStep_] >= kCvtStepUpRpm && cvtStep_ < static_cast<int>(kCvtSteps.size()) - 1) {
            ++cvtStep_;   // 次の段へ(回転がすっと落ちる)
        }
        target = kCvtSteps[cvtStep_];
        rate = kCvtStepRate;   // 段の切り替えは素早く(ただし一瞬ではない)
    } else if (speedMs_ < 0.5) {
        target = kCvtMaxRatio;   // 停車中・発進はいちばん低い側
        rate = 3.0;
    } else {
        // 目標回転数: 車速が上がるほど少し高く、アクセル開度で大きく上がる
        const double base = lerp(1150.0, 1750.0, std::clamp(kmh / 110.0, 0.0, 1.0)) + p.cvtRpmOffset * 0.5;
        const double wantRpm = base + std::pow(throttle_, 1.6) * (5900.0 + p.cvtRpmOffset * 0.3 - base);
        target = wantRpm / perRatio;
        // 低い側へ(回転を上げる)は速く、高い側へ(回転を下げる)はゆっくり。踏んでいるほどゆっくり上げる
        rate = target > cvtRatio_ ? 1.2 + 2.0 * throttle_ : 0.35 + 0.6 * (1.0 - throttle_);
    }
    target = std::clamp(target, kCvtMinRatio, kCvtMaxRatio);
    cvtRatio_ += std::clamp(target - cvtRatio_, -rate * dt, rate * dt);
}

void VehicleDataManager::step(double dt) {
    std::normal_distribution<double> noise(0.0, 1.0);

    // ---- 運転者 ----
    const Phase phaseBefore = phase_;
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
    if (phaseBefore == Phase::Stop && phase_ != Phase::Stop && speedMs_ < 0.5) {
        launchHoldS_ = params().launchHoldS;   // 停車からの発進
    }
    double brakeDecel = 0.0;
    driveControl(dt, brakeDecel);
    // ブレーキの踏み込み量: 減速度 7 m/s²(約 0.7G)で 100%。停車中は止まっておくために軽く踏んだまま
    {
        double want = std::clamp(brakeDecel / 7.0, 0.0, 1.0);
        if (phase_ == Phase::Stop && speedMs_ < 0.15) want = std::max(want, 0.22);
        // 発進では、ブレーキをじわっと離す(離しきってからアクセル)
        const double releaseTau = launchHoldS_ > 0.0 ? params().launchHoldS * 0.25 : 0.08;
        brakePedal_ = approach(brakePedal_, want, want > brakePedal_ ? 0.12 : releaseTau, dt);
        if (brakePedal_ < 0.005) brakePedal_ = 0.0;
    }

    // ---- 変速(AT / CVT) ----
    if (shiftLeftS_ > 0.0) shiftLeftS_ -= dt;
    if (transmission_ == Transmission::Cvt) {
        shiftLeftS_ = 0.0;   // CVT は駆動力が抜けない
        updateCvt(dt);
    } else {
        updateAt(dt);
    }

    // ---- フリーホイール(惰性走行): アクセルを離して少したつと切り離し、アクセル・ブレーキ・低速でつなぎ直す ----
    {
        const double kmhNow = speedMs_ * 3.6;
        // 切り離すのはアクセルを離しきったとき、つなぎ直すのははっきり踏んだとき(行ったり来たりしないよう差をつける)
        const bool lifted = throttle_ < 0.01 && brakePedal_ < 0.02;
        const bool pressed = throttle_ > 0.06 || brakePedal_ >= 0.02;
        liftS_ = lifted ? liftS_ + dt : 0.0;
        // AT は 3 速以上(低いギアでは切り離さない)。変速中・つなぎ直し中は待つ
        const bool gearOk = transmission_ == Transmission::Cvt || gear_ >= 3;
        if (!freewheel_ && mockFreewheel_ && lifted && liftS_ >= kFreewheelDelayS && kmhNow >= kFreewheelMinKmh
            && gearOk && shiftLeftS_ <= 0.0 && resyncLeftS_ <= 0.0) {
            freewheel_ = true;
        } else if (freewheel_ && (pressed || kmhNow < kFreewheelExitKmh || !mockFreewheel_)) {
            freewheel_ = false;
            resyncLeftS_ = kResyncTimeS;   // 回転を車速に合わせてからつなぐ
        }
        if (resyncLeftS_ > 0.0) resyncLeftS_ -= dt;
    }

    // ---- エンジン回転数(トルクコンバーター) ----
    // 直結(ロックアップ)していない間は滑り、踏むとストール回転数(止まった状態で踏み込んだときの回転)近くまで回る。
    // 滑りの幅は、速度が上がるにつれて小さくなる。ロックアップは CVT が約 20km/h、AT が 2 速以上の約 30km/h から
    // (大きく踏み込んだときは外れる)
    const double kmh = speedMs_ * 3.6;
    const double coupled = rpmPerMs() * speedMs_ * overallRatio();
    const bool lockup = (transmission_ == Transmission::Cvt ? kmh > 20.0 : (gear_ >= 2 && kmh > 30.0)) && throttle_ < 0.85;
    const double stallRpm = kIdleRpm + std::pow(throttle_, 0.7) * (2600.0 - kIdleRpm);
    // D レンジで止まっている(クリープを抑えている)間は、負荷でアイドリングが少し下がる
    const double idleRpm = speedMs_ < 0.3 && throttle_ < 0.05 ? kIdleRpm - 40.0 : kIdleRpm;
    double targetRpm = coupled;
    if (!lockup) {
        const double band = lerp(2200.0, 300.0, std::clamp(kmh / 35.0, 0.0, 1.0));
        targetRpm = std::max(coupled, std::min(stallRpm, coupled + band));
    }
    targetRpm = std::max(targetRpm, idleRpm);
    // 変速中は、回転が新しいギアの回転へ変速時間をかけて移る(クラッチが滑りながらつながる)
    double rpmTau = shiftLeftS_ > 0.0 ? 0.16 : 0.08;
    if (freewheel_) {
        // 惰性走行: 駆動から切り離されているので、回転はアイドリングへゆっくり落ちる
        targetRpm = kIdleRpm;
        rpmTau = 0.45;
    } else if (resyncLeftS_ > 0.0) {
        // つなぎ直し: 回転を車速に合わせる(落ちていた回転を素早く上げる)
        rpmTau = 0.07;
    }
    // 回転は、エンジンの重さで一瞬には変わらない(変速・ロックアップの切り替わり・キックダウンでも急に飛ばない)
    rpm_ = approachLimited(rpm_, std::min(targetRpm, kRedlineRpm + 100.0), rpmTau, dt, kRpmRiseRate, kRpmFallRate);
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
    if (shiftLeftS_ > 0.0 || limiter || resyncLeftS_ > 0.0) {
        targetBoost = std::min(targetBoost, 0.1);   // 変速・リミッター・つなぎ直し中は抜ける(ブローオフ)
    }
    const bool rising = targetBoost > boostBar_;
    boostBar_ = approachLimited(boostBar_, targetBoost, rising ? lerp(0.9, 0.35, spool) : 0.18, dt,
                                kBoostRiseRate, kBoostFallRate);
    // 全開で立ち上がるときのオーバーシュート(ウェイストゲートが開くまでの山)
    if (rising && openness > 0.85 && spool > 0.9) {
        boostBar_ += 0.25 * dt * (kMaxBoostBar + 0.3 - boostBar_);
    }
    boostBar_ += noise(rng_) * 0.006;

    // ---- 駆動力と車速 ----
    double torqueNm = 0.0;
    if (shiftLeftS_ <= 0.0 && resyncLeftS_ <= 0.0 && !limiter) {
        const double boostGain = 1.0 + 0.8 * std::max(0.0, boostBar_) / kMaxBoostBar;
        torqueNm = pedalTorqueFrac(throttle_) * baseTorqueNm(rpm_) * boostGain;
        // トルクコンバーターのトルクの増幅(滑っているほど大きく、止まった状態で約 2 倍)
        if (!lockup) {
            const double speedRatio = std::clamp(coupled / std::max(rpm_, 1.0), 0.0, 1.0);
            torqueNm *= lerp(2.0, 1.0, std::clamp(speedRatio / 0.85, 0.0, 1.0));
        }
    }
    if (throttle_ < 0.05) {
        torqueNm = -(8.0 + rpm_ * 0.006);   // エンジンブレーキ
    }
    const double eff = transmission_ == Transmission::Cvt ? kCvtEff : kDrivetrainEff;
    double driveN = torqueNm * overallRatio() * eff / kTireRadiusM;
    if (freewheel_) {
        driveN = 0.0;   // 惰性走行: エンジンブレーキが掛からない(空気抵抗と転がり抵抗だけで減速)
    } else if (resyncLeftS_ > 0.0 && throttle_ < 0.05) {
        driveN *= 0.3;   // つなぎ直しの途中(ブレーキで抜けたとき): エンジンブレーキはじわっと戻る
    }
    if (throttle_ < 0.05 && speedMs_ < 2.4) {
        // クリープ: アクセルを離していても、アイドリングの力でゆっくり進む(時速 6km ほどで釣り合う)
        driveN = 520.0 * (1.0 - speedMs_ / 2.4);
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
