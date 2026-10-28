/**
 * @file DisplaySettings.cpp
 * @brief DisplaySettings の実装。
 */
#include "DisplaySettings.h"

#include "Log.h"

#include <algorithm>

#include <QCoreApplication>
#include <QGuiApplication>
#include <QProcess>
#include <QQuickWindow>
#include <QScreen>
#include <QSettings>
#include <QSGRendererInterface>
#include <QSurfaceFormat>
#include <QtGui/qtguiglobal.h>
#if QT_CONFIG(vulkan)
#include <QVulkanInstance>
#endif

namespace opencruise {

namespace {
QSettings openStore() {
    return QSettings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"),
                     QStringLiteral("OpenCruise"));
}

const QString kScreenKey = QStringLiteral("display/screen");
const QString kRotationKey = QStringLiteral("display/rotation");
const QString kApiKey = QStringLiteral("display/graphicsApi");
const QString kVsyncKey = QStringLiteral("display/vsync");
const QString kDividerKey = QStringLiteral("display/frameDivider");
/// 保存値の特別な値: 外部画面があれば外部画面、無ければメイン画面(起動時・抜き差し時に自動で切り替える)
const QString kAutoExternal = QStringLiteral("@external");

/// 本体の内蔵パネルらしい接続名か(ノート PC・車載機の eDP / LVDS / DSI など)
bool isInternalName(const QString &name) {
    for (const char *prefix : {"eDP", "LVDS", "DSI", "DPI"}) {
        if (name.startsWith(QLatin1String(prefix), Qt::CaseInsensitive)) {
            return true;
        }
    }
    return false;
}

/// 外部画面を選ぶ。内蔵パネルらしい名前の画面があればそれ以外、無ければメイン画面以外。見つからなければ nullptr
const QScreen *findExternalScreen() {
    const QList<QScreen *> screens = QGuiApplication::screens();
    if (screens.size() < 2) {
        return nullptr;
    }
    bool anyInternal = false;
    for (const QScreen *screen : screens) {
        anyInternal = anyInternal || isInternalName(screen->name());
    }
    for (const QScreen *screen : screens) {
        if (anyInternal ? !isInternalName(screen->name()) : screen != QGuiApplication::primaryScreen()) {
            return screen;
        }
    }
    return nullptr;
}

/// 起動時に適用した描画の設定(再起動が必要かの判定に使う)
struct StartupValues {
    bool applied = false;
    int graphicsApi = 0;
    bool vsync = true;
    int frameDivider = 1;
};
StartupValues g_startup;
QString g_graphicsNote;   ///< 選んだ描画方式を使えず、別の方式にしたときの説明

/// Vulkan で描画できるか。eglfs は OpenGL(ES)専用で、Vulkan を選ぶと描画の初期化で異常終了するので使わない
bool vulkanUsable() {
#if QT_CONFIG(vulkan)
    if (QGuiApplication::platformName().startsWith(QLatin1String("eglfs"))) {
        return false;
    }
    QVulkanInstance instance;   // 実際に作れるか試す(ドライバや Qt のプラットフォームが対応していなければ失敗する)
    return instance.create();
#else
    return false;   // Qt が Vulkan なしでビルドされている
#endif
}

int clampApi(int api) { return (api >= 0 && api <= 3) ? api : 0; }
int clampDivider(int divider) { return (divider >= 1 && divider <= 3) ? divider : 1; }
int normalizeRotation(int degrees) {
    const int r = ((degrees % 360) + 360) % 360;
    return (r == 90 || r == 180 || r == 270) ? r : 0;
}

/// 選択肢に出す画面の説明(例: "HDMI-A-1 — DELL U2419H 1920×1080 60Hz")
QString describe(const QScreen *screen) {
    const QString model = (screen->manufacturer() + QLatin1Char(' ') + screen->model()).trimmed();
    const QSize size = screen->size() * screen->devicePixelRatio();
    QString text = screen->name();
    if (!model.isEmpty()) {
        text += QStringLiteral(" — ") + model;
    }
    text += QStringLiteral(" %1×%2 %3Hz").arg(size.width()).arg(size.height()).arg(qRound(screen->refreshRate()));
    if (screen == QGuiApplication::primaryScreen()) {
        text += QStringLiteral("(メイン)");
    }
    return text;
}
} // namespace

void DisplaySettings::applyStartupSettings() {
    const QSettings store = openStore();
    g_startup.graphicsApi = clampApi(store.value(kApiKey, 0).toInt());
    g_startup.vsync = store.value(kVsyncKey, true).toBool();
    g_startup.frameDivider = clampDivider(store.value(kDividerKey, 1).toInt());
    g_startup.applied = true;

    int api = g_startup.graphicsApi;
    if (api == 2 && !vulkanUsable()) {
        api = 1;
        g_graphicsNote = QStringLiteral("Vulkan はこの環境(%1)で使えないため、OpenGL で描画しています")
                             .arg(QGuiApplication::platformName());
        log::warn("DISPLAY", QStringLiteral("Vulkan is not usable on this platform (%1); rendering with OpenGL")
                                 .arg(QGuiApplication::platformName()));
    }
    switch (api) {
    case 1: QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL); break;
    case 2: QQuickWindow::setGraphicsApi(QSGRendererInterface::Vulkan); break;
    case 3: QQuickWindow::setGraphicsApi(QSGRendererInterface::Software); break;
    default: break;   // 自動(Qt の既定。Linux では通常 OpenGL)
    }

    // 垂直同期: swapInterval 0 で無効、2・3 でリフレッシュレートの 1/2・1/3 に間引く
    QSurfaceFormat format = QSurfaceFormat::defaultFormat();
    format.setSwapInterval(g_startup.vsync ? g_startup.frameDivider : 0);
    QSurfaceFormat::setDefaultFormat(format);

    static const char *const kApiNames[] = {"auto", "OpenGL", "Vulkan", "software"};
    log::info("DISPLAY", QStringLiteral("graphics API=%1 / vsync=%2 / divider=1/%3")
                             .arg(QString::fromUtf8(kApiNames[g_startup.graphicsApi]),
                                  g_startup.vsync ? QStringLiteral("on") : QStringLiteral("off"))
                             .arg(g_startup.frameDivider));
}

DisplaySettings::DisplaySettings(QObject *parent) : QObject(parent) {
    const QSettings store = openStore();
    // 既定は「外部画面を優先」(起動時に外部画面がつながっていれば、自動でそちらに出す)
    savedScreen_ = store.value(kScreenKey, kAutoExternal).toString();
    rotation_ = normalizeRotation(store.value(kRotationKey, 0).toInt());
    graphicsApi_ = clampApi(store.value(kApiKey, 0).toInt());
    vsync_ = store.value(kVsyncKey, true).toBool();
    frameDivider_ = clampDivider(store.value(kDividerKey, 1).toInt());

    // 画面の抜き差し・メイン画面の変更で、選択肢と出す画面を作り直す
    auto *app = qobject_cast<QGuiApplication *>(QCoreApplication::instance());
    if (app) {
        // 通知の時点では画面一覧の更新が終わっていないことがあるので、イベントループに戻ってから作り直す
        const auto later = [this]() { rebuildScreens(); };
        connect(app, &QGuiApplication::screenAdded, this, later, Qt::QueuedConnection);
        connect(app, &QGuiApplication::screenRemoved, this, later, Qt::QueuedConnection);
        connect(app, &QGuiApplication::primaryScreenChanged, this, later, Qt::QueuedConnection);
    }
    rebuildScreens();
}

void DisplaySettings::rebuildScreens() {
    screenIds_ = {QString(), kAutoExternal};
    screenNames_ = {QStringLiteral("自動(メイン画面)"),
                    QStringLiteral("自動(外部画面があれば外部画面)")};
    const bool autoMode = savedScreen_.isEmpty() || savedScreen_ == kAutoExternal;
    bool savedFound = autoMode;
    for (const QScreen *screen : QGuiApplication::screens()) {
        screenIds_ << screen->name();
        screenNames_ << describe(screen);
        if (screen->name() == savedScreen_) {
            savedFound = true;
        }
    }
    if (!savedFound) {
        // 外れている画面も選択中のまま見えるように残す
        screenIds_ << savedScreen_;
        screenNames_ << savedScreen_ + QStringLiteral("(未接続)");
    }
    screenIndex_ = std::max(0, static_cast<int>(screenIds_.indexOf(savedScreen_)));

    const QScreen *primary = QGuiApplication::primaryScreen();
    const QString primaryName = primary ? primary->name() : QString();
    const QScreen *external = findExternalScreen();
    const QString previous = targetScreenName_;
    usingFallback_ = !autoMode && !savedFound;
    externalConnected_ = external != nullptr;
    if (savedScreen_ == kAutoExternal) {
        targetScreenName_ = external ? external->name() : primaryName;
    } else if (autoMode || !savedFound) {
        targetScreenName_ = primaryName;
    } else {
        targetScreenName_ = savedScreen_;
    }
    if (previous != targetScreenName_) {
        QString reason;
        if (usingFallback_) {
            reason = QStringLiteral(" (selected screen %1 is not connected; using the primary screen)").arg(savedScreen_);
        } else if (savedScreen_ == kAutoExternal) {
            reason = external ? QStringLiteral(" (external screen chosen automatically)")
                              : QStringLiteral(" (no external screen; using the primary screen)");
        }
        log::info("DISPLAY", QStringLiteral("target screen: %1%2")
                                 .arg(targetScreenName_.isEmpty() ? QStringLiteral("(unknown)") : targetScreenName_, reason));
    }
    emit screensChanged();
}

bool DisplaySettings::isEglfs() const { return QGuiApplication::platformName().startsWith(QLatin1String("eglfs")); }

void DisplaySettings::setScreenIndex(int index) {
    if (index < 0 || index >= screenIds_.size()) {
        return;
    }
    const QString name = screenIds_.at(index);
    if (name == savedScreen_) {
        return;
    }
    savedScreen_ = name;
    openStore().setValue(kScreenKey, savedScreen_);
    rebuildScreens();
}

void DisplaySettings::setRotation(int degrees) {
    const int r = normalizeRotation(degrees);
    if (r == rotation_) {
        return;
    }
    rotation_ = r;
    openStore().setValue(kRotationKey, rotation_);
    emit rotationChanged();
}

void DisplaySettings::setGraphicsApi(int api) {
    api = clampApi(api);
    if (api == graphicsApi_) {
        return;
    }
    graphicsApi_ = api;
    openStore().setValue(kApiKey, graphicsApi_);
    emit renderingChanged();
}

void DisplaySettings::setVsync(bool on) {
    if (on == vsync_) {
        return;
    }
    vsync_ = on;
    openStore().setValue(kVsyncKey, vsync_);
    emit renderingChanged();
}

void DisplaySettings::setFrameDivider(int divider) {
    divider = clampDivider(divider);
    if (divider == frameDivider_) {
        return;
    }
    frameDivider_ = divider;
    openStore().setValue(kDividerKey, frameDivider_);
    emit renderingChanged();
}

bool DisplaySettings::restartRequired() const {
    if (!g_startup.applied) {
        return false;
    }
    return graphicsApi_ != g_startup.graphicsApi || vsync_ != g_startup.vsync ||
           (vsync_ && frameDivider_ != g_startup.frameDivider);
}

QString DisplaySettings::activeGraphicsApi() const {
    switch (QQuickWindow::graphicsApi()) {
    case QSGRendererInterface::OpenGL: return QStringLiteral("OpenGL");
    case QSGRendererInterface::Vulkan: return QStringLiteral("Vulkan");
    case QSGRendererInterface::Software: return QStringLiteral("ソフトウェア");
    case QSGRendererInterface::Direct3D11: return QStringLiteral("Direct3D 11");
    case QSGRendererInterface::Metal: return QStringLiteral("Metal");
    default: return QStringLiteral("不明");
    }
}

QString DisplaySettings::graphicsNote() const { return g_graphicsNote; }

QString DisplaySettings::platformName() const { return QGuiApplication::platformName(); }

void DisplaySettings::restartApp() {
    QStringList args = QCoreApplication::arguments();
    if (!args.isEmpty()) {
        args.removeFirst();   // 先頭は実行ファイル自身
    }
    log::info("DISPLAY", QStringLiteral("restarting to apply the settings"));
    if (QProcess::startDetached(QCoreApplication::applicationFilePath(), args)) {
        QCoreApplication::quit();
    } else {
        log::warn("DISPLAY", QStringLiteral("could not restart (cannot start a new process)"));
    }
}

} // namespace opencruise
