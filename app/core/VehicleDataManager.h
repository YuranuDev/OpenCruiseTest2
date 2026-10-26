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
 *  - 駆動系: 変速機は設定で選ぶ(mockTransmission)。車速と回転数は、変速比・最終減速比・タイヤ半径で一致させる
 *      AT : 6 速。アクセルを踏むほど高回転まで引っ張って変速(変速中は駆動力が抜ける)。踏み込むとキックダウン
 *      CVT: 変速比を連続的に変え、アクセル開度と車速で決まる目標回転数に回転を合わせる。
 *           軽く踏むと低い回転のまま速度だけ伸び、踏み増すと回転が先に上がって張り付く(ラバーバンド感)。
 *           大きく踏むと 7 段の疑似変速(ステップ変速)で、段ごとに回転が上がっては下がる。
 *           発進は変速比いちばん低い所から、減速すると低い側へ戻る。低速ではトルクコンバーターが滑る
 *  - 運転のしかた: 設定で選ぶ(mockDriveStyle。穏やか / 普通 / アグレッシブ)。アクセルの踏み方・踏む速さ、
 *      全開加速の頻度、ブレーキの強さ、変速(AT の変速点・CVT の目標回転数)が変わる
 *  - エンジン: 回転数ごとのトルク特性 + ターボ(回転数とアクセル開度で決まる目標ブーストへ遅れて追従)
 *  - 水温: 燃焼の発熱で暖機し、サーモスタット(約 86℃)が開くとラジエーターで 86〜90℃前後に保つ
 *  - 燃料: 出力から燃料消費を求め、タンク容量に対する残量を減らす
 *  - 油温: 水温より遅れて暖まり、負荷が高いほど水温より高くなる
 *  - 油圧: 回転数に比例して上がり(リリーフ弁で頭打ち)、油温が低いほど(粘度が高いほど)高い
 *  - 電圧: 発電機(オルタネーター)が約 14V に保つ。負荷が高いときや低回転では少し下がる
 *
 * エンジン始動の判定(メーターの警告を有効にするタイミング。回転数だけで決める。実 CAN でも同じ):
 *  - 始動: 回転数が kEngineStartRpm 以上の状態が kEngineConfirmSec 続いたら、始動したとみなす
 *          (スターターで回しているだけ・一瞬の吹け上がりは数えない)
 *  - 警告を有効にする: 始動とみなしてから kWarnSettleSec 経ったとき(油圧・電圧が落ち着くまで待つ)
 * 停止(エンジン OFF)はここでは判定しない。一度始動とみなしたら、アプリが終わるまでそのまま。
 * (エンジン OFF はキー位置で判断し、そのときに自動でシャットダウンする機能を後から足す予定のため)
 * QML では can.engineRunning / can.warningsArmed として読む。
 *
 * データ源: 今は実 CAN 通信が無いので、ダミーデータ(上のシミュレーション)だけ。
 * メーター・グラフにダミーデータを使うか(mockGauges)は、Android Auto へ送るか(AndroidAutoController の
 * mockVehicleData)とは別に切り替えられる。mockGauges が false なら dataAvailable が false になり、
 * メーター・グラフは「データなし」の表示になる(警告も出さない)。シミュレーション自体は、Android Auto へ送る分のために動かし続ける。
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
    /// ギア(AT: 1〜6。CVT は段が無いので、疑似変速中はその段、それ以外は 0)
    Q_PROPERTY(int gear READ gear NOTIFY changed)
    /// 今の総減速比(変速比 × 最終減速比)
    Q_PROPERTY(double gearRatio READ gearRatio NOTIFY changed)
    /// 今の変速比(最終減速比を掛ける前。AT はそのギアの比、CVT はプーリー比)
    Q_PROPERTY(double transmissionRatio READ transmissionRatio NOTIFY changed)
    /// モックの変速機(0 = AT / 1 = CVT)。保存される
    Q_PROPERTY(int mockTransmission READ mockTransmission WRITE setMockTransmission NOTIFY mockSettingsChanged)
    /// モックの運転のしかた(0 = 穏やか / 1 = 普通 / 2 = アグレッシブ)。保存される
    Q_PROPERTY(int mockDriveStyle READ mockDriveStyle WRITE setMockDriveStyle NOTIFY mockSettingsChanged)
    Q_PROPERTY(double throttlePercent READ throttlePercent NOTIFY changed)
    Q_PROPERTY(QString sourceText READ sourceText NOTIFY dataAvailableChanged)
    /// メーター・グラフに出すデータがあるか(今はダミーデータを使う設定のときだけ true)
    Q_PROPERTY(bool dataAvailable READ dataAvailable NOTIFY dataAvailableChanged)
    /// メーター・グラフにダミーデータを使うか。保存される
    Q_PROPERTY(bool mockGauges READ mockGauges WRITE setMockGauges NOTIFY dataAvailableChanged)
    /// エンジンが始動しているとみなすか
    Q_PROPERTY(bool engineRunning READ engineRunning NOTIFY engineStateChanged)
    /// メーターの警告を有効にするか(始動とみなして少し経ってから true。一度 true になったらそのまま)
    Q_PROPERTY(bool warningsArmed READ warningsArmed NOTIFY engineStateChanged)

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
    /** @brief 現在のギア(AT: 1〜6。停車中は 1。CVT: 疑似変速中はその段、それ以外は 0)。 */
    int gear() const { return transmission_ == Transmission::Cvt ? (cvtStepMode_ ? cvtStep_ + 1 : 0) : gear_; }
    /** @brief 今の総減速比。 */
    double gearRatio() const { return overallRatio(); }
    /** @brief 今の変速比(最終減速比を掛ける前)。 */
    double transmissionRatio() const;
    int mockTransmission() const { return static_cast<int>(transmission_); }
    void setMockTransmission(int value);
    int mockDriveStyle() const { return static_cast<int>(style_); }
    void setMockDriveStyle(int value);
    /** @brief アクセル開度 [%]。 */
    double throttlePercent() const { return throttle_ * 100.0; }
    /** @brief データの出所を示す表示用文字列(「ダミーデータ」/「なし」)。 */
    QString sourceText() const { return dataAvailable() ? QStringLiteral("ダミーデータ") : QStringLiteral("なし"); }
    bool dataAvailable() const { return mockGauges_; }
    bool mockGauges() const { return mockGauges_; }
    void setMockGauges(bool enabled);
    bool engineRunning() const { return engineRunning_; }
    /** @brief 警告を有効にするか。データが無いときは出さない。 */
    bool warningsArmed() const { return warningsArmed_ && dataAvailable(); }

    static constexpr double kEngineStartRpm = 400.0;  ///< これ以上で回っていれば始動(を数え始める)
    static constexpr double kEngineConfirmSec = 2.0;  ///< 始動とみなすまで続く時間 [s]
    static constexpr double kWarnSettleSec = 3.0;     ///< 始動とみなしてから警告を有効にするまで [s]

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

    /** @brief エンジン始動の判定(engineRunning / warningsArmed)が変わったとき。 */
    void engineStateChanged();

    /** @brief モックの設定(変速機・運転のしかた)が変わったとき。 */
    void mockSettingsChanged();

    /** @brief メーター・グラフに出すデータの有無(dataAvailable / mockGauges / sourceText)が変わったとき。 */
    void dataAvailableChanged();

private:
    /// 運転者の行動(走行パターンの 1 区間)
    enum class Phase {
        Stop,   ///< 停車(信号待ちなど)
        Cruise, ///< 目標速度まで加速(または減速)して巡航
        Pull    ///< アクセル全開で目標速度まで加速
    };

    /// 変速機の種類
    enum class Transmission { At = 0, Cvt = 1 };
    /// 運転のしかた
    enum class DriveStyle { Gentle = 0, Normal = 1, Aggressive = 2 };
    /// 運転のしかたごとの値
    struct StyleParams {
        double cruiseThrottleMin;  ///< 巡航で踏み込む上限の下限
        double cruiseThrottleMax;  ///< 巡航で踏み込む上限の上限
        double pullChance;         ///< 次の区間が全開加速になる割合
        double pullThrottle;       ///< 全開加速で踏む量
        double pullGainKmh;        ///< 全開加速で上げる速度の幅(最大)
        double pedalUpRate;        ///< アクセルを踏む速さ [/s]
        double pedalDownRate;      ///< アクセルを離す速さ [/s]
        double speedGain;          ///< 目標速度との差への反応の強さ
        double brakeScale;         ///< ブレーキの強さの倍率
        double stopChance;         ///< 信号待ちになる割合
        double atUpshiftLow;       ///< AT: 軽く踏んだときの変速点 [rpm]
        double cvtRpmOffset;       ///< CVT: 目標回転数の上乗せ [rpm]
    };
    static const StyleParams &paramsFor(DriveStyle style);
    const StyleParams &params() const { return paramsFor(style_); }

    /**
     * @brief 経過時間から 1 ステップ分のシミュレーションを進めて値を更新する。
     */
    void update();
    /** @brief dt 秒だけシミュレーションを進める(update から呼ぶ。試験でも直接呼べる)。 */
    void step(double dt);
    /** @brief AT の変速を進める。 */
    void updateAt(double dt);
    /** @brief CVT の変速比を進める。 */
    void updateCvt(double dt);
    /** @brief 今の総減速比(変速比 × 最終減速比)。 */
    double overallRatio() const;
    /** @brief 車速 1 m/s あたりの、総減速比 1 のときのエンジン回転数 [rpm]。 */
    static double rpmPerMs();

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

    // ---- エンジン始動の判定 ----
    /** @brief 回転数から始動の判定を進める(回転数を更新するたびに呼ぶ)。 */
    void updateEngineState(double dt);
    bool engineRunning_ = false;
    bool warningsArmed_ = false;
    double aboveStartS_ = 0.0;   ///< 始動の回転数以上が続いている時間 [s]
    double runningS_ = 0.0;      ///< 始動とみなしてからの時間 [s]

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

    // ---- モックの設定 ----
    bool mockGauges_ = true;     ///< メーター・グラフにダミーデータを使う
    Transmission transmission_ = Transmission::At;
    DriveStyle style_ = DriveStyle::Normal;

    // ---- CVT の状態 ----
    double cvtRatio_ = 2.631;    ///< 変速比(プーリー比)
    bool cvtStepMode_ = false;   ///< 疑似変速(ステップ変速)中か
    int cvtStep_ = 0;            ///< 疑似変速の段(0 始まり)
};

} // namespace opencruise
