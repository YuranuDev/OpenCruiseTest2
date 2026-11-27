/**
 * @file BrightnessController.cpp
 * @brief BrightnessController の実装。
 */
#include "BrightnessController.h"

#include <algorithm>
#include <cmath>

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSettings>

#include "core/Log.h"

namespace opencruise {

namespace {

QSettings openStore() {
    return QSettings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"),
                     QStringLiteral("OpenCruise"));
}

/// sysfs の整数ファイルを読む。読めなければ -1。
int readIntFile(const QString &path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return -1;
    }
    bool ok = false;
    const int value = QString::fromLatin1(file.readAll()).trimmed().toInt(&ok);
    return ok ? value : -1;
}

#ifdef Q_OS_LINUX
/// バックライトの種類の優先度(小さいほど優先)。firmware > platform > raw
int typeRank(const QString &type) {
    if (type == QLatin1String("firmware")) return 0;
    if (type == QLatin1String("platform")) return 1;
    return 2;
}
#endif

} // namespace

BrightnessController::BrightnessController(QObject *parent) : QObject(parent) {
    detectBacklight();

    QSettings store = openStore();
    const QString legacyKey = QStringLiteral("display/brightness");
    int initial = store.contains(legacyKey) ? std::clamp(store.value(legacyKey).toInt(), kMinimum, kMaximum) : kMaximum;
    if (!store.contains(legacyKey) && hardwareControl()) {
        // 設定が無いときは、現在のバックライトの値を初期値にする(起動で明るさを勝手に変えない)
        const int now = readBacklightPercent();
        if (now >= 0) initial = std::clamp(now, kMinimum, kMaximum);
    }
    dayBrightness_ = std::clamp(store.value(QStringLiteral("display/dayBrightness"), initial).toInt(), kMinimum, kMaximum);
    nightBrightness_ = std::clamp(store.value(QStringLiteral("display/nightBrightness"), initial).toInt(), kMinimum, kMaximum);
    brightness_ = dayBrightness_;
    const bool hasSavedBrightness = store.contains(legacyKey) || store.contains(QStringLiteral("display/dayBrightness"))
                                    || store.contains(QStringLiteral("display/nightBrightness"));
    if (hasSavedBrightness) {
        // 旧版の単一値や片側だけを保存した状態から移行するときに、未設定側も現在値で確定する。
        store.setValue(QStringLiteral("display/dayBrightness"), dayBrightness_);
        store.setValue(QStringLiteral("display/nightBrightness"), nightBrightness_);
        applyToBacklight(); // 保存された設定があるときだけ、起動時にバックライトへ反映する
    }

    log::info("DISPLAY", QStringLiteral("brightness: day %1% / night %2% / %3")
                             .arg(dayBrightness_).arg(nightBrightness_)
                             .arg(hardwareControl() ? QStringLiteral("backlight (%1)").arg(backlightName_)
                                                    : QStringLiteral("software dimming")));
}

void BrightnessController::detectBacklight() {
#ifdef Q_OS_LINUX
    // 書き込める brightness ファイルを持つバックライトのうち、優先度が最も高いものを使う
    const QDir root(QStringLiteral("/sys/class/backlight"));
    int bestRank = 99;
    const QStringList names = root.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QString &name : names) {
        const QString dir = root.absoluteFilePath(name);
        const QString brightnessFile = dir + QStringLiteral("/brightness");
        const int max = readIntFile(dir + QStringLiteral("/max_brightness"));
        if (max <= 0 || !QFileInfo(brightnessFile).isWritable()) {
            continue; // 最大値が読めない、または書き込み権限が無い(その場合は暗幕を使う)
        }
        QFile typeFile(dir + QStringLiteral("/type"));
        QString typeName;
        if (typeFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            typeName = QString::fromLatin1(typeFile.readAll()).trimmed();
        }
        const int rank = typeRank(typeName);
        if (rank < bestRank) {
            bestRank = rank;
            backlightPath_ = brightnessFile;
            backlightName_ = name;
            backlightMax_ = max;
        }
    }
#endif
    // Windows など(および Linux でバックライトを制御できない場合)は、暗幕による調整だけを使う
}

int BrightnessController::readBacklightPercent() const {
    if (backlightPath_.isEmpty() || backlightMax_ <= 0) {
        return -1;
    }
    const int raw = readIntFile(backlightPath_);
    if (raw < 0) {
        return -1;
    }
    return static_cast<int>(std::lround(100.0 * raw / backlightMax_));
}

void BrightnessController::applyToBacklight() {
    if (backlightPath_.isEmpty()) {
        return;
    }
    // 1..max に収める(0 は機器によって消灯になるため使わない)
    const int raw = std::clamp(static_cast<int>(std::lround(static_cast<double>(backlightMax_) * brightness_ / 100.0)), 1,
                               backlightMax_);
    QFile file(backlightPath_);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)
        || file.write(QByteArray::number(raw)) < 0
        || !file.flush()) {
        fallBackToSoftware(file.errorString());
    }
}

void BrightnessController::fallBackToSoftware(const QString &reason) {
    log::warn("DISPLAY", QStringLiteral("cannot write to the backlight; switching to software dimming: %1").arg(reason));
    backlightPath_.clear();
    backlightName_.clear();
    backlightMax_ = 0;
    emit backendChanged();
    emit overlayOpacityChanged(); // 暗幕が必要になった
}

void BrightnessController::setBrightness(int percent) {
    setProfileBrightness(nightMode_, percent);
}

void BrightnessController::setDayBrightness(int percent) {
    setProfileBrightness(false, percent);
}

void BrightnessController::setNightBrightness(int percent) {
    setProfileBrightness(true, percent);
}

void BrightnessController::setProfileBrightness(bool night, int percent) {
    percent = std::clamp(percent, kMinimum, kMaximum);
    int &profileBrightness = night ? nightBrightness_ : dayBrightness_;
    if (percent == profileBrightness) return;
    profileBrightness = percent;
    QSettings store = openStore();
    store.setValue(QStringLiteral("display/dayBrightness"), dayBrightness_);
    store.setValue(QStringLiteral("display/nightBrightness"), nightBrightness_);
    if (night == nightMode_) {
        brightness_ = percent;
        store.setValue(QStringLiteral("display/brightness"), brightness_); // 旧版との設定互換
        applyToBacklight();
        emit overlayOpacityChanged();
    }
    emit brightnessChanged();
}

void BrightnessController::setNightMode(bool night) {
    if (night == nightMode_) return;
    nightMode_ = night;
    brightness_ = nightMode_ ? nightBrightness_ : dayBrightness_;
    QSettings store = openStore();
    store.setValue(QStringLiteral("display/dayBrightness"), dayBrightness_);
    store.setValue(QStringLiteral("display/nightBrightness"), nightBrightness_);
    store.setValue(QStringLiteral("display/brightness"), brightness_); // 旧版との設定互換
    applyToBacklight();
    emit brightnessChanged();
    emit overlayOpacityChanged();
}

void BrightnessController::adjustBrightness(int delta) {
    setBrightness(brightness_ + delta);
}

QString BrightnessController::methodText() const {
    if (hardwareControl()) {
        return QStringLiteral("バックライトを直接制御(%1)").arg(backlightName_);
    }
    return QStringLiteral("画面を暗くして調整(ソフトウェア)");
}

qreal BrightnessController::overlayOpacity() const {
    if (hardwareControl()) {
        return 0.0; // バックライトで暗くしているので、暗幕は重ねない(二重に暗くしない)
    }
    return 1.0 - static_cast<qreal>(brightness_) / 100.0;
}

} // namespace opencruise
