/**
 * @file ThemeSettings.cpp
 * @brief アプリ全体の見た目(テーマ)と背景の設定の実装。
 */
#include "ThemeSettings.h"

#include "core/Log.h"

#include <QColor>
#include <QDir>
#include <QFileInfo>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>

#include <algorithm>

namespace opencruise {

namespace {
const QStringList kStyles = {QStringLiteral("simple"), QStringLiteral("classic")};
const QStringList kBackgrounds = {QStringLiteral("auto"),    QStringLiteral("none"), QStringLiteral("carbon"),
                                  QStringLiteral("brushed"), QStringLiteral("dots"), QStringLiteral("stripes"),
                                  QStringLiteral("image")};
const QStringList kProfileKeys = {QStringLiteral("style"), QStringLiteral("accentIndex"),
                                  QStringLiteral("accentCustom"), QStringLiteral("background"),
                                  QStringLiteral("backgroundImage"), QStringLiteral("backgroundFit"),
                                  QStringLiteral("backgroundOpacity")};
const QStringList kImageFilters = {QStringLiteral("*.png"),  QStringLiteral("*.jpg"),  QStringLiteral("*.jpeg"),
                                   QStringLiteral("*.webp"), QStringLiteral("*.gif"),  QStringLiteral("*.PNG"),
                                   QStringLiteral("*.JPG"),  QStringLiteral("*.JPEG"), QStringLiteral("*.WEBP"),
                                   QStringLiteral("*.GIF")};

QSettings openStore() {
    return QSettings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"),
                     QStringLiteral("OpenCruise"));
}

QString legacyKey(const QString &key) {
    if (key == QLatin1String("style")) return QStringLiteral("ui/style");
    if (key == QLatin1String("accentIndex")) return QStringLiteral("ui/accentIndex");
    if (key == QLatin1String("accentCustom")) return QStringLiteral("ui/accentCustom");
    if (key == QLatin1String("background")) return QStringLiteral("ui/background");
    if (key == QLatin1String("backgroundImage")) return QStringLiteral("ui/backgroundImage");
    if (key == QLatin1String("backgroundFit")) return QStringLiteral("ui/backgroundFit");
    return QStringLiteral("ui/backgroundOpacity");
}
} // namespace

ThemeSettings::ThemeSettings(QObject *parent) : QObject(parent) {
    QDir().mkpath(backgroundFolder());
    QDir().mkpath(decorationFolder());
    dayProfile_ = readStoredProfile(false);
    nightProfile_ = readStoredProfile(true);
    profilesLoaded_ = true;
    accentSaveTimer_.setSingleShot(true);
    accentSaveTimer_.setInterval(500);
    connect(&accentSaveTimer_, &QTimer::timeout, this, &ThemeSettings::savePendingAccentCustom);
    refreshBackgroundImages();
    refreshDecorationImages();
    log::info("THEME", QStringLiteral("day=%1 / night=%2 / background folders: %3, %4 (%5 images)")
                           .arg(dayProfile().value(QStringLiteral("style")).toString(),
                                nightProfile().value(QStringLiteral("style")).toString(),
                                backgroundFolder(), decorationFolder())
                           .arg(decorations_.size()));
}

QVariantMap ThemeSettings::readProfile(bool night) const {
    if (profilesLoaded_) return night ? nightProfile_ : dayProfile_;
    return readStoredProfile(night);
}

QVariantMap ThemeSettings::readStoredProfile(bool night) const {
    const QSettings store = openStore();
    const QString side = night ? QStringLiteral("night") : QStringLiteral("day");
    QVariantMap result;
    for (const QString &key : kProfileKeys) {
        const QString profileKey = QStringLiteral("ui/%1/%2").arg(side, key);
        const QVariant fallback = key == QLatin1String("style") ? QVariant(QStringLiteral("simple"))
            : key == QLatin1String("accentIndex") ? QVariant(0)
            : key == QLatin1String("accentCustom") ? QVariant(QString())
            : key == QLatin1String("background") ? QVariant(QStringLiteral("auto"))
            : key == QLatin1String("backgroundImage") ? QVariant(QString())
            : key == QLatin1String("backgroundFit") ? QVariant(1) : QVariant(60);
        const QVariant value = store.contains(profileKey) ? store.value(profileKey)
                                                          : store.value(legacyKey(key), fallback);
        result.insert(key, value);
    }

    const QString style = result.value(QStringLiteral("style")).toString();
    if (!kStyles.contains(style)) result.insert(QStringLiteral("style"), QStringLiteral("simple"));
    const QString background = result.value(QStringLiteral("background")).toString();
    if (!kBackgrounds.contains(background)) result.insert(QStringLiteral("background"), QStringLiteral("auto"));
    result.insert(QStringLiteral("accentIndex"), std::clamp(result.value(QStringLiteral("accentIndex")).toInt(), 0, 11));
    result.insert(QStringLiteral("backgroundFit"), std::clamp(result.value(QStringLiteral("backgroundFit")).toInt(), 0, 2));
    result.insert(QStringLiteral("backgroundOpacity"), std::clamp(result.value(QStringLiteral("backgroundOpacity")).toInt(), 0, 100));
    const QString image = result.value(QStringLiteral("backgroundImage")).toString();
    if (image.contains(QLatin1Char('/')) || image.contains(QLatin1Char('\\'))) {
        result.insert(QStringLiteral("backgroundImage"), QString());
    }
    const QString custom = result.value(QStringLiteral("accentCustom")).toString();
    const QColor customColor(custom);
    result.insert(QStringLiteral("accentCustom"), custom.isEmpty() || !customColor.isValid() ? QString() : customColor.name());
    return result;
}

void ThemeSettings::writeProfile(bool night, const QVariantMap &values) {
    const QVariantMap current = readProfile(night);
    QVariantMap next = current;
    for (const QString &key : kProfileKeys) {
        if (!values.contains(key)) continue;
        const QVariant value = values.value(key);
        if (key == QLatin1String("style")) {
            const QString style = value.toString();
            if (kStyles.contains(style)) next.insert(key, style);
        } else if (key == QLatin1String("background")) {
            const QString background = value.toString();
            if (kBackgrounds.contains(background)) next.insert(key, background);
        } else if (key == QLatin1String("accentCustom")) {
            const QString color = value.toString();
            const QColor parsed(color);
            if (color.isEmpty() || parsed.isValid()) next.insert(key, color.isEmpty() ? QString() : parsed.name());
        } else if (key == QLatin1String("backgroundImage")) {
            const QString fileName = value.toString();
            if (!fileName.contains(QLatin1Char('/')) && !fileName.contains(QLatin1Char('\\'))) next.insert(key, fileName);
        } else if (key == QLatin1String("accentIndex")) {
            next.insert(key, std::clamp(value.toInt(), 0, 11));
        } else if (key == QLatin1String("backgroundFit")) {
            next.insert(key, std::clamp(value.toInt(), 0, 2));
        } else if (key == QLatin1String("backgroundOpacity")) {
            next.insert(key, std::clamp(value.toInt(), 0, 100));
        }
    }
    if (next == current) return;

    if (night) nightProfile_ = next;
    else dayProfile_ = next;

    QSettings store = openStore();
    const QString side = night ? QStringLiteral("night") : QStringLiteral("day");
    for (const QString &key : kProfileKeys) {
        if (current.value(key) == next.value(key)) continue;
        if (key == QLatin1String("accentCustom")) {
            if (night) nightAccentPending_ = true;
            else dayAccentPending_ = true;
            continue; // 色相スライダーの連続更新は落ち着いてから保存する
        }
        store.setValue(QStringLiteral("ui/%1/%2").arg(side, key), next.value(key));
    }
    if (dayAccentPending_ || nightAccentPending_) accentSaveTimer_.start();
    emit changed();
}

void ThemeSettings::setNightMode(bool night) {
    if (night == nightMode_) return;
    nightMode_ = night;
    emit changed();
}

QVariantMap ThemeSettings::dayProfile() const { return readProfile(false); }
void ThemeSettings::setDayProfile(const QVariantMap &profile) { writeProfile(false, profile); }
QVariantMap ThemeSettings::nightProfile() const { return readProfile(true); }
void ThemeSettings::setNightProfile(const QVariantMap &profile) { writeProfile(true, profile); }

void ThemeSettings::savePendingAccentCustom() {
    QSettings store = openStore();
    if (dayAccentPending_) {
        store.setValue(QStringLiteral("ui/day/accentCustom"), dayProfile_.value(QStringLiteral("accentCustom")));
        dayAccentPending_ = false;
    }
    if (nightAccentPending_) {
        store.setValue(QStringLiteral("ui/night/accentCustom"), nightProfile_.value(QStringLiteral("accentCustom")));
        nightAccentPending_ = false;
    }
}

void ThemeSettings::setActiveValue(const QString &key, const QVariant &value) {
    QVariantMap values = readProfile(nightMode_);
    values.insert(key, value);
    writeProfile(nightMode_, values);
}

QString ThemeSettings::style() const { return readProfile(nightMode_).value(QStringLiteral("style")).toString(); }
void ThemeSettings::setStyle(const QString &style) { setActiveValue(QStringLiteral("style"), style); }
int ThemeSettings::accentIndex() const { return readProfile(nightMode_).value(QStringLiteral("accentIndex")).toInt(); }
void ThemeSettings::setAccentIndex(int index) { setActiveValue(QStringLiteral("accentIndex"), index); }
QString ThemeSettings::accentCustom() const { return readProfile(nightMode_).value(QStringLiteral("accentCustom")).toString(); }
void ThemeSettings::setAccentCustom(const QString &color) { setActiveValue(QStringLiteral("accentCustom"), color); }
QString ThemeSettings::background() const { return readProfile(nightMode_).value(QStringLiteral("background")).toString(); }
void ThemeSettings::setBackground(const QString &background) { setActiveValue(QStringLiteral("background"), background); }
QString ThemeSettings::backgroundImage() const { return readProfile(nightMode_).value(QStringLiteral("backgroundImage")).toString(); }
void ThemeSettings::setBackgroundImage(const QString &fileName) { setActiveValue(QStringLiteral("backgroundImage"), fileName); }
int ThemeSettings::backgroundFit() const { return readProfile(nightMode_).value(QStringLiteral("backgroundFit")).toInt(); }
void ThemeSettings::setBackgroundFit(int fit) { setActiveValue(QStringLiteral("backgroundFit"), fit); }
int ThemeSettings::backgroundOpacity() const { return readProfile(nightMode_).value(QStringLiteral("backgroundOpacity")).toInt(); }
void ThemeSettings::setBackgroundOpacity(int percent) { setActiveValue(QStringLiteral("backgroundOpacity"), percent); }

QString ThemeSettings::backgroundFolder() const {
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/OpenCruise/backgrounds");
}

QString ThemeSettings::decorationFolder() const {
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/OpenCruise/decorations");
}

QString ThemeSettings::decorationUrl(const QString &fileName) const {
    // フォルダの外を指すファイル名(../ など)は使わない
    if (fileName.isEmpty() || fileName.contains(QLatin1Char('/')) || fileName.contains(QLatin1Char('\\'))) return QString();
    const QString path = decorationFolder() + QLatin1Char('/') + fileName;
    return QFileInfo::exists(path) ? QUrl::fromLocalFile(path).toString() : QString();
}

void ThemeSettings::refreshDecorationImages() {
    const QStringList list = QDir(decorationFolder()).entryList(kImageFilters, QDir::Files, QDir::Name);
    if (list != decorations_) {
        decorations_ = list;
        log::info("THEME", QStringLiteral("decoration images: %1").arg(decorations_.size()));
        emit decorationImagesChanged();
    }
}

QString ThemeSettings::backgroundImageUrl() const {
    return backgroundUrl(backgroundImage());
}

QString ThemeSettings::backgroundUrl(const QString &fileName) const {
    // フォルダの外を指すファイル名(../ など)は使わない
    if (fileName.isEmpty() || fileName.contains(QLatin1Char('/')) || fileName.contains(QLatin1Char('\\'))) return QString();
    const QString path = backgroundFolder() + QLatin1Char('/') + fileName;
    return QFileInfo::exists(path) ? QUrl::fromLocalFile(path).toString() : QString();
}

void ThemeSettings::refreshBackgroundImages() {
    QDir dir(backgroundFolder());
    const QStringList list = dir.entryList(kImageFilters, QDir::Files, QDir::Name);
    if (list != images_) {
        images_ = list;
        emit imagesChanged();
        emit changed();   // 選んでいた画像が消えた・戻ったとき、backgroundImageUrl を読み直させる
    }
}

} // namespace opencruise
