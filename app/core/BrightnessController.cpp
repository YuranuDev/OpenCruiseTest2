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

#include "Log.h"

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

    const QSettings store = openStore();
    const QString key = QStringLiteral("display/brightness");
    if (store.contains(key)) {
        brightness_ = std::clamp(store.value(key, kMaximum).toInt(), kMinimum, kMaximum);
        applyToBacklight(); // 保存された設定があるときだけ、起動時にバックライトへ反映する
    } else if (hardwareControl()) {
        // 設定が無いときは、現在のバックライトの値を初期値にする(起動で明るさを勝手に変えない)
        const int now = readBacklightPercent();
        if (now >= 0) {
            brightness_ = std::clamp(now, kMinimum, kMaximum);
        }
    }

    log::info("DISPLAY", QStringLiteral("明るさ: ") + QString::number(brightness_) + QStringLiteral("% / ") + methodText());
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
    log::warn("DISPLAY", QStringLiteral("バックライトへ書き込めないため、画面を暗幕で暗くする方式へ切り替えます: %1").arg(reason));
    backlightPath_.clear();
    backlightName_.clear();
    backlightMax_ = 0;
    emit backendChanged();
    emit overlayOpacityChanged(); // 暗幕が必要になった
}

void BrightnessController::setBrightness(int percent) {
    percent = std::clamp(percent, kMinimum, kMaximum);
    if (percent == brightness_) {
        return;
    }
    brightness_ = percent;
    openStore().setValue(QStringLiteral("display/brightness"), brightness_);
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
