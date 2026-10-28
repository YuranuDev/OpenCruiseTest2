/**
 * @file ThemeSettings.cpp
 * @brief アプリ全体の見た目(テーマ)と背景の設定の実装。
 */
#include "ThemeSettings.h"

#include "Log.h"

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

const QStringList kImageFilters = {QStringLiteral("*.png"),  QStringLiteral("*.jpg"),  QStringLiteral("*.jpeg"),
                                   QStringLiteral("*.webp"), QStringLiteral("*.gif"),  QStringLiteral("*.PNG"),
                                   QStringLiteral("*.JPG"),  QStringLiteral("*.JPEG"), QStringLiteral("*.WEBP"),
                                   QStringLiteral("*.GIF")};

QSettings openStore() {
    return QSettings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"),
                     QStringLiteral("OpenCruise"));
}
} // namespace

ThemeSettings::ThemeSettings(QObject *parent) : QObject(parent) {
    const QSettings store = openStore();
    const QString style = store.value(QStringLiteral("ui/style"), style_).toString();
    style_ = kStyles.contains(style) ? style : QStringLiteral("simple");
    const QString background = store.value(QStringLiteral("ui/background"), background_).toString();
    background_ = kBackgrounds.contains(background) ? background : QStringLiteral("auto");
    backgroundImage_ = store.value(QStringLiteral("ui/backgroundImage")).toString();
    backgroundFit_ = std::clamp(store.value(QStringLiteral("ui/backgroundFit"), backgroundFit_).toInt(), 0, 2);
    backgroundOpacity_ = std::clamp(store.value(QStringLiteral("ui/backgroundOpacity"), backgroundOpacity_).toInt(), 0, 100);
    QDir().mkpath(backgroundFolder());   // 画像を置く場所を作っておく
    QDir().mkpath(decorationFolder());
    refreshBackgroundImages();
    refreshDecorationImages();
    log::info("THEME", QStringLiteral("style=%1 / background=%2%3 / image folder: %4 / decoration folder: %5 (%6 images)")
                           .arg(style_, background_,
                                background_ == QStringLiteral("image") ? QStringLiteral(" (%1)").arg(backgroundImage_) : QString(),
                                backgroundFolder(), decorationFolder())
                           .arg(decorations_.size()));
}

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

void ThemeSettings::save(const QString &key, const QVariant &value) {
    openStore().setValue(key, value);
    emit changed();
}

void ThemeSettings::setStyle(const QString &style) {
    if (style == style_ || !kStyles.contains(style)) return;
    style_ = style;
    log::info("THEME", QStringLiteral("style: %1").arg(style_));
    save(QStringLiteral("ui/style"), style_);
}

void ThemeSettings::setBackground(const QString &background) {
    if (background == background_ || !kBackgrounds.contains(background)) return;
    background_ = background;
    log::info("THEME", QStringLiteral("background: %1").arg(background_));
    save(QStringLiteral("ui/background"), background_);
}

void ThemeSettings::setBackgroundImage(const QString &fileName) {
    if (fileName == backgroundImage_) return;
    backgroundImage_ = fileName;
    log::info("THEME", QStringLiteral("background image: %1").arg(fileName));
    save(QStringLiteral("ui/backgroundImage"), backgroundImage_);
}

QString ThemeSettings::backgroundImageUrl() const {
    if (backgroundImage_.isEmpty()) return QString();
    const QString path = backgroundFolder() + QLatin1Char('/') + backgroundImage_;
    return QFileInfo::exists(path) ? QUrl::fromLocalFile(path).toString() : QString();
}

void ThemeSettings::setBackgroundFit(int fit) {
    fit = std::clamp(fit, 0, 2);
    if (fit == backgroundFit_) return;
    backgroundFit_ = fit;
    save(QStringLiteral("ui/backgroundFit"), backgroundFit_);
}

void ThemeSettings::setBackgroundOpacity(int percent) {
    percent = std::clamp(percent, 0, 100);
    if (percent == backgroundOpacity_) return;
    backgroundOpacity_ = percent;
    save(QStringLiteral("ui/backgroundOpacity"), backgroundOpacity_);
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
