/**
 * @file DummyCanModel.h
 * @brief CAN 情報の「ダミー」モデル。実際の CAN 通信は行わない。
 */
#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QString>
#include <QTimer>

namespace opencruise {

/**
 * @brief 速度・回転数などを疑似的に変化させて QML に提供する。
 *
 * 将来、実 CAN 受信に置き換える際は、同じプロパティ名を持つ別クラスに差し替えればよい。
 */
class DummyCanModel : public QObject {
    Q_OBJECT
    Q_PROPERTY(int speedKmh READ speedKmh NOTIFY changed)
    Q_PROPERTY(int rpm READ rpm NOTIFY changed)
    Q_PROPERTY(int coolantTempC READ coolantTempC NOTIFY changed)
    Q_PROPERTY(int fuelPercent READ fuelPercent NOTIFY changed)
    Q_PROPERTY(QString sourceText READ sourceText CONSTANT)

public:
    /**
     * @brief 更新タイマーを開始する。
     * @param parent 親オブジェクト
     */
    explicit DummyCanModel(QObject *parent = nullptr);

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
    /** @brief いずれかの値が更新されたとき。 */
    void changed();

private:
    /**
     * @brief 経過時間から疑似的な走行パターンを計算して値を更新する。
     */
    void update();

    QTimer timer_;
    QElapsedTimer elapsed_;
    int speedKmh_ = 0;
    int rpm_ = 0;
    int coolantTempC_ = 0;
    int fuelPercent_ = 0;
};

} // namespace opencruise
