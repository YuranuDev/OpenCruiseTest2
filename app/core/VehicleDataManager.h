/**
 * @file VehicleDataManager.h
 * @brief 車両データを管理するクラス
 *
 * このクラスは車両の各種状態データを管理し、更新や通知を行う。
 * 将来的にESP32から取得する車両データを扱えるように設計されている。
 * DummyCanModelの機能を統合した実装。
 */
#pragma once

#include <QObject>
#include <QTimer>
#include <QElapsedTimer>
#include <memory>

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
    // CANデータ用プロパティ（QMLで使用される）
    Q_PROPERTY(int speedKmh READ speedKmh NOTIFY changed)
    Q_PROPERTY(int rpm READ rpm NOTIFY changed)
    Q_PROPERTY(int coolantTempC READ coolantTempC NOTIFY changed)
    Q_PROPERTY(int fuelPercent READ fuelPercent NOTIFY changed)
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
    int speedKmh() const { return speedKmh_; }
    /** @brief エンジン回転数 [rpm]。 */
    int rpm() const { return rpm_; }
    /** @brief 冷却水温 [℃]。 */
    int coolantTempC() const { return coolantTempC_; }
    /** @brief 燃料残量 [%]。 */
    int fuelPercent() const { return fuelPercent_; }
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
    /**
     * @brief 経過時間から疑似的な走行パターンを計算して値を更新する。
     */
    void update();

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

    /**
     * @brief 車速 [km/h]
     */
    int speedKmh_ = 0;

    /**
     * @brief エンジン回転数 [rpm]
     */
    int rpm_ = 0;

    /**
     * @brief 冷却水温 [℃]
     */
    int coolantTempC_ = 0;

    /**
     * @brief 燃料残量 [%]
     */
    int fuelPercent_ = 0;
};
