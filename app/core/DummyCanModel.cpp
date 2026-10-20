/**
 * @file DummyCanModel.cpp
 * @brief DummyCanModel の実装。
 */
#include "DummyCanModel.h"

#include <algorithm>
#include <cmath>

namespace opencruise {

/**
 * @brief 100ms 周期で値を更新する。
 */
DummyCanModel::DummyCanModel(QObject *parent) : QObject(parent) {
    elapsed_.start();
    timer_.setInterval(100);
    connect(&timer_, &QTimer::timeout, this, &DummyCanModel::update);
    update();
    timer_.start();
}

/**
 * @brief ゆっくり変動する速度を作り、回転数は速度に比例させる。水温は上昇、燃料は緩やかに減少。
 */
void DummyCanModel::update() {
    constexpr double kPi = 3.14159265358979323846;
    const double t = static_cast<double>(elapsed_.elapsed()) / 1000.0;

    const double speed = 55.0 + 35.0 * std::sin(2.0 * kPi * t / 24.0) + 6.0 * std::sin(2.0 * kPi * t / 3.7);
    speedKmh_ = std::max(0, static_cast<int>(std::lround(speed)));
    rpm_ = 850 + speedKmh_ * 24 + static_cast<int>(std::lround(120.0 * std::sin(2.0 * kPi * t / 1.9)));
    coolantTempC_ = static_cast<int>(std::min(90.0, 60.0 + t * 0.5));
    fuelPercent_ = static_cast<int>(std::max(0.0, 68.0 - t * 0.01));
    emit changed();
}

} // namespace opencruise
