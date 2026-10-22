/**
 * @file AppSettings.cpp
 * @brief AppSettings の実装。
 */
#include "AppSettings.h"

#include <QCoreApplication>
#include <QDir>
#include <QDirIterator>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QFont>
#include <QSet>
#include <QSettings>

#include "Log.h"

namespace opencruise {

namespace {

/// 選択肢として提示するフォント(表示順)。同梱ファイルから読み込めたものだけが実際の選択肢になる
const QStringList kFontCatalog = {
    QStringLiteral("Noto Sans JP"),
    QStringLiteral("Noto Sans CJK JP"),
    QStringLiteral("IBM Plex Sans JP"),
};

/// 初期のフォント(読み込めなかった場合は OS 既定のまま)
const QString kDefaultFont = QStringLiteral("Noto Sans JP");

QSettings openStore() {
    return QSettings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"),
                     QStringLiteral("OpenCruise"));
}

} // namespace

QStringList AppSettings::fontSearchDirs() {
    QStringList dirs;
    const QByteArray env = qgetenv("OPENCRUISE_FONT_DIR");
    if (!env.isEmpty()) {
        dirs << QString::fromLocal8Bit(env);
    }
    const QString appDir = QCoreApplication::applicationDirPath();
    dirs << appDir + QStringLiteral("/fonts");
    dirs << QDir::cleanPath(appDir + QStringLiteral("/../share/opencruise/fonts"));
    return dirs;
}

int AppSettings::loadBundledFonts() {
    int loadedFiles = 0;
    QSet<QString> families;
    for (const QString &dir : fontSearchDirs()) {
        if (!QDir(dir).exists()) {
            continue;
        }
        int loadedInDir = 0;
        QDirIterator it(dir, {QStringLiteral("*.otf"), QStringLiteral("*.ttf")}, QDir::Files,
                        QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QString path = it.next();
            const int id = QFontDatabase::addApplicationFont(path);
            if (id < 0) {
                log::warn("FONT", QStringLiteral("フォントを読み込めません: ") + path);
                continue;
            }
            ++loadedInDir;
            const QStringList names = QFontDatabase::applicationFontFamilies(id);
            for (const QString &name : names) {
                families.insert(name);
            }
        }
        loadedFiles += loadedInDir;
        log::info("FONT", QStringLiteral("%1 から %2 個のフォントを読み込みました").arg(dir).arg(loadedInDir));
        if (loadedInDir > 0) {
            break; // 最初に見つかった探索先だけを使う(同じフォントの二重登録を避ける)
        }
    }

    // 内部の細かいスタイル名(例: "IBM Plex Sans JP Text")は出さず、カタログのファミリだけを選択肢にする
    for (const QString &name : kFontCatalog) {
        if (families.contains(name)) {
            fontFamilies_ << name;
        } else if (loadedFiles > 0) {
            log::warn("FONT", QStringLiteral("同梱フォントが見つかりません: ") + name);
        }
    }
    if (loadedFiles == 0) {
        log::warn("FONT", QStringLiteral("同梱フォントを読み込めませんでした。OS 既定のフォントを使用します"));
    }
    return loadedFiles;
}

AppSettings::AppSettings(QObject *parent) : QObject(parent) {
    loadBundledFonts();

    const QSettings store = openStore();
    userName_ = store.value(QStringLiteral("user/name"), QString()).toString().trimmed();

    // 保存値が選択肢に無い(フォント未同梱・設定の破損など)場合は既定、既定も無ければ OS 既定
    QString family = store.value(QStringLiteral("ui/fontFamily"), kDefaultFont).toString();
    if (!fontFamilies_.contains(family)) {
        family = fontFamilies_.contains(kDefaultFont) ? kDefaultFont : QString();
    }
    fontFamily_ = family;
    if (!fontFamily_.isEmpty()) {
        QGuiApplication::setFont(QFont(fontFamily_));
    }
}

void AppSettings::setUserName(const QString &name) {
    const QString trimmed = name.trimmed();
    if (trimmed == userName_) {
        return;
    }
    userName_ = trimmed;
    openStore().setValue(QStringLiteral("user/name"), userName_);
    emit userNameChanged();
}

void AppSettings::setFontFamily(const QString &family) {
    if (family == fontFamily_ || !fontFamilies_.contains(family)) {
        return;
    }
    fontFamily_ = family;
    openStore().setValue(QStringLiteral("ui/fontFamily"), fontFamily_);
    QGuiApplication::setFont(QFont(fontFamily_));
    emit fontFamilyChanged();
}

} // namespace opencruise
