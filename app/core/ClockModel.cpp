/**
 * @file ClockModel.cpp
 * @brief ClockModel の実装。
 */
#include "ClockModel.h"

#include <QDateTime>
#include <QLocale>

namespace opencruise {

/**
 * @brief 500ms 周期で更新する（1秒周期だと表示が最大1秒遅れることがあるため）。
 */
ClockModel::ClockModel(QObject *parent) : QObject(parent) {
    timer_.setInterval(500);
    timer_.setTimerType(Qt::PreciseTimer);
    connect(&timer_, &QTimer::timeout, this, &ClockModel::refresh);
    refresh();
    timer_.start();
}

/**
 * @brief 表示文字列を更新する。
 */
void ClockModel::refresh() {
    const QDateTime now = QDateTime::currentDateTime();
    const QString time = now.toString(QStringLiteral("HH:mm"));
    const QString date = QLocale(QLocale::Japanese).toString(now, QStringLiteral("yyyy年M月d日 (ddd)"));
    if (time == timeText_ && date == dateText_) {
        return;
    }
    timeText_ = time;
    dateText_ = date;
    emit changed();
}

} // namespace opencruise
