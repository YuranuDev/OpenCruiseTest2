/**
 * @file ClockModel.h
 * @brief 現在時刻を QML に提供するモデル。
 */
#pragma once

#include <QObject>
#include <QString>
#include <QTimer>

namespace opencruise {

/**
 * @brief 現在の時刻・日付を文字列で公開し、変化したときだけ通知する。
 */
class ClockModel : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString timeText READ timeText NOTIFY changed)
    Q_PROPERTY(QString dateText READ dateText NOTIFY changed)
    Q_PROPERTY(int hour READ hour NOTIFY changed)

public:
    /**
     * @brief タイマーを開始し、初期値を設定する。
     * @param parent 親オブジェクト
     */
    explicit ClockModel(QObject *parent = nullptr);

    /** @brief "HH:mm" 形式の時刻。 */
    QString timeText() const { return timeText_; }

    /** @brief "yyyy年M月d日 (曜日)" 形式の日付。 */
    QString dateText() const { return dateText_; }

    /** @brief 現在の時(0〜23)。挨拶の切り替えなどに使う。 */
    int hour() const { return hour_; }

signals:
    /** @brief 時刻または日付の表示が変わったとき。 */
    void changed();

private:
    /**
     * @brief 現在時刻から表示文字列を作り直し、変化があれば changed を発行する。
     */
    void refresh();

    QTimer timer_;
    QString timeText_;
    QString dateText_;
    int hour_ = 0;
};

} // namespace opencruise
