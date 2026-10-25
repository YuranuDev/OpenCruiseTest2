/**
 * @file VehicleDataManager.h
 * @brief 車両データを管理するクラス
 *
 * このクラスは車両の各種状態データを管理し、更新や通知を行う。
 * 将来的にESP32から取得する車両データを扱えるように設計されている。
 * DummyCanModelの機能を統合した実装。
 *
 * 実 CAN 通信が入るまでは、簡易的な車両シミュレーション(モック)で値を作る:
 *  - 運転者: 停止・発進・巡航・全開加速・減速を組み合わせた走行パターンを、ランダムに選んで繰り返す
 *  - 駆動系: 6 速 AT 相当のギア比・最終減速比・タイヤ半径から、車速と回転数を一致させる(変速あり)
 *  - エンジン: 回転数ごとのトルク特性 + ターボ(回転数とアクセル開度で決まる目標ブーストへ遅れて追従)
 *  - 水温: 燃焼の発熱で暖機し、サーモスタット(約 86℃)が開くとラジエーターで 86〜90℃前後に保つ
 *  - 燃料: 出力から燃料消費を求め、タンク容量に対する残量を減らす
 *  - 油温: 水温より遅れて暖まり、負荷が高いほど水温より高くなる
 *  - 油圧: 回転数に比例して上がり(リリーフ弁で頭打ち)、油温が低いほど(粘度が高いほど)高い
 *  - 電圧: 発電機(オルタネーター)が約 14V に保つ。負荷が高いときや低回転では少し下がる
 */
#pragma once

#include <QObject>
#include <QTimer>
#include <QElapsedTimer>
#include <memory>
#include <random>

namespace opencruise {

/**
 * @brief ヘッドライト状態の列挙型
 */
enum class HeadlightState {
    OFF,    ///< ヘッドライトオフ
    ON,     ///< ヘッドライトオン
    UNKNOWN ///< 不明（状態未確定）
};

/**
 * @brief 車両データ管理クラス
 *
 * このクラスは車両の各種状態を管理し、変更時にシグナルを発行する。
 * DummyCanModelの機能を統合し、将来的にESP32通信からデータを取得できるように設計されている。
 */
class VehicleDataManager : public QObject {
    Q_OBJECT
    // CANデータ用プロパティ（QMLで使用される）。値はすべて小数を含む(表示側で丸める)
    Q_PROPERTY(double speedKmh READ speedKmh NOTIFY changed)
    Q_PROPERTY(double rpm READ rpm NOTIFY changed)
    Q_PROPERTY(double coolantTempC READ coolantTempC NOTIFY changed)
    Q_PROPERTY(double fuelPercent READ fuelPercent NOTIFY changed)
    Q_PROPERTY(double boostBar READ boostBar NOTIFY changed)
    Q_PROPERTY(double oilTempC READ oilTempC NOTIFY changed)
    Q_PROPERTY(double oilPressureBar READ oilPressureBar NOTIFY changed)
    Q_PROPERTY(double batteryVolts READ batteryVolts NOTIFY changed)
    Q_PROPERTY(int gear READ gear NOTIFY changed)
    Q_PROPERTY(double throttlePercent READ throttlePercent NOTIFY changed)
    Q_PROPERTY(QString sourceText READ sourceText CONSTANT)

public:
    /**
     * @brief コンストラクタ
     * @param parent 親オブジェクト
     */
    explicit VehicleDataManager(QObject *parent = nullptr);

    /**
     * @brief デストラクタ
     */
    ~VehicleDataManager() override;

    /**
     * @brief ヘッドライト状態を取得する
     * @return ヘッドライト状態
     */
    HeadlightState getHeadlightState() const;

    /**
     * @brief ヘッドライト状態を設定する
     * @param state ヘッドライト状態
     */
    void setHeadlightState(HeadlightState state);

    /**
     * @brief 昼夜モードを取得する（ヘッドライト状態に基づく）
     * @return true: 夜モード, false: 昼モード
     */
    bool isNightMode() const;

    /** @brief 車速 [km/h]。 */
    double speedKmh() const { return speedKmh_; }
    /** @brief エンジン回転数 [rpm]。 */
    double rpm() const { return rpm_; }
    /** @brief 冷却水温 [℃]。 */
    double coolantTempC() const { return coolantTempC_; }
    /** @brief 燃料残量 [%]。 */
    double fuelPercent() const { return fuelPercent_; }
    /** @brief 油温 [℃]。 */
    double oilTempC() const { return oilTempC_; }
    /** @brief 油圧(ゲージ圧) [bar]。 */
    double oilPressureBar() const { return oilPressureBar_; }
    /** @brief 電圧(バッテリー・電装系) [V]。 */
    double batteryVolts() const { return batteryVolts_; }
    /** @brief ブースト圧(ゲージ圧) [bar]。負の値は負圧。 */
    double boostBar() const { return boostBar_; }
    /** @brief 現在のギア(1〜6)。停車中は 1。 */
    int gear() const { return gear_; }
    /** @brief アクセル開度 [%]。 */
    double throttlePercent() const { return throttle_ * 100.0; }
    /** @brief データの出所を示す表示用文字列（常に「ダミーデータ」）。 */
    QString sourceText() const { return QStringLiteral("ダミーデータ"); }

signals:
    /**
     * @brief ヘッドライト状態が変更されたシグナル
     * @param state 変更されたヘッドライト状態
     */
    void headlightStateChanged(HeadlightState state);

    /**
     * @brief 昼夜モードが変更されたシグナル
     * @param isNightMode 夜モードかどうか
     */
    void nightModeChanged(bool isNightMode);

    /**
     * @brief いずれかの車両データが更新されたとき。
     */
    void changed();

private:
    /// 運転者の行動(走行パターンの 1 区間)
    enum class Phase {
        Stop,   ///< 停車(信号待ちなど)
        Cruise, ///< 目標速度まで加速(または減速)して巡航
        Pull    ///< アクセル全開で目標速度まで加速
    };

    /**
     * @brief 経過時間から 1 ステップ分のシミュレーションを進めて値を更新する。
     */
    void update();

    /**
     * @brief 次の走行区間をランダムに選ぶ。
     */
    void nextPhase();

    /**
     * @brief 運転者のアクセル・ブレーキ操作を決める。
     * @param dt 経過時間 [s]
     * @param brakeDecel ブレーキによる減速度 [m/s²](出力)
     */
    void driveControl(double dt, double &brakeDecel);

    /**
     * @brief 回転数とアクセル開度から、自然吸気分のエンジントルク [Nm] を求める。
     * @param rpm エンジン回転数
     */
    static double baseTorqueNm(double rpm);

    /**
     * @brief 車速とギアから、エンジン回転数 [rpm] を求める(クラッチ・トルコンの滑りは別途)。
     */
    double rpmFromSpeed(double speedMs, int gear) const;

    /**
     * @brief ヘッドライト状態
     */
    HeadlightState headlightState_;

    /**
     * @brief 車両データの更新タイマー
     */
    QTimer updateTimer_;

    /**
     * @brief 経過時間計測用タイマー
     */
    QElapsedTimer elapsed_;

    /// 前回の更新時刻 [ms](elapsed_ 基準)
    qint64 lastMs_ = 0;

    // ---- 公開する値 ----
    double speedKmh_ = 0.0;      ///< 車速 [km/h]
    double rpm_ = 0.0;           ///< エンジン回転数 [rpm]
    double coolantTempC_ = 0.0;  ///< 冷却水温 [℃]
    double fuelPercent_ = 0.0;   ///< 燃料残量 [%]
    double oilTempC_ = 0.0;      ///< 油温 [℃]
    double oilPressureBar_ = 0.0;///< 油圧 [bar]
    double batteryVolts_ = 12.6; ///< 電圧 [V]
    double boostBar_ = 0.0;      ///< ブースト圧(ゲージ圧) [bar]

    // ---- シミュレーションの状態 ----
    std::mt19937 rng_;
    Phase phase_ = Phase::Stop;
    double phaseLeftS_ = 0.0;    ///< 今の区間の残り時間 [s]
    double targetMs_ = 0.0;      ///< 目標速度 [m/s]
    double maxThrottle_ = 0.6;   ///< この区間で踏み込む上限(運転のおとなしさ)
    double speedMs_ = 0.0;       ///< 車速 [m/s]
    double throttle_ = 0.0;      ///< アクセル開度 0〜1
    int gear_ = 1;               ///< ギア(1〜6)
    double shiftLeftS_ = 0.0;    ///< 変速中の残り時間 [s](この間は駆動力が抜ける)
    double fuelLiters_ = 0.0;    ///< 燃料 [L]
};

} // namespace opencruise
