/**
 * @file OsDisplayMirror.cpp
 * @brief OsDisplayMirror の実装。
 */
#include "OsDisplayMirror.h"

#include "Log.h"

#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>

#include <cstdlib>
#include <cstring>

namespace opencruise {

namespace {
QString g_startupNote;

/// 内蔵パネルらしい接続名か(DisplaySettings の外部画面の判定と同じ)
bool isInternalName(const QString &name) {
    for (const char *prefix : {"eDP", "LVDS", "DSI", "DPI"}) {
        if (name.startsWith(QLatin1String(prefix), Qt::CaseInsensitive)) {
            return true;
        }
    }
    return false;
}

/// /sys/class/drm の接続名(例: HDMI-A-1)を、eglfs(KMS)の出力名(例: HDMI1)にする
QString kmsName(const QString &sysfsName) {
    const int dash = sysfsName.lastIndexOf(QLatin1Char('-'));
    if (dash <= 0) {
        return sysfsName;
    }
    const QString type = sysfsName.left(dash);
    const QString index = sysfsName.mid(dash + 1);
    static const QList<QPair<QString, QString>> kTypes = {
        {QStringLiteral("HDMI-A"), QStringLiteral("HDMI")}, {QStringLiteral("HDMI-B"), QStringLiteral("HDMI")},
        {QStringLiteral("DVI-I"), QStringLiteral("DVI")},   {QStringLiteral("DVI-D"), QStringLiteral("DVI")},
        {QStringLiteral("DVI-A"), QStringLiteral("DVI")},   {QStringLiteral("DP"), QStringLiteral("DP")},
        {QStringLiteral("eDP"), QStringLiteral("eDP")},     {QStringLiteral("LVDS"), QStringLiteral("LVDS")},
        {QStringLiteral("DSI"), QStringLiteral("DSI")},     {QStringLiteral("DPI"), QStringLiteral("DPI")},
        {QStringLiteral("VGA"), QStringLiteral("VGA")},     {QStringLiteral("Virtual"), QStringLiteral("Virtual")}};
    for (const auto &t : kTypes) {
        if (type == t.first) {
            return t.second + index;
        }
    }
    return type + index;
}

/// 起動引数・環境変数から、eglfs で起動するかを判定する
bool wantsEglfs(int argc, char *argv[]) {
    for (int i = 1; i + 1 < argc; ++i) {
        if (std::strcmp(argv[i], "-platform") == 0 || std::strcmp(argv[i], "--platform") == 0) {
            return QString::fromLocal8Bit(argv[i + 1]).startsWith(QLatin1String("eglfs"));
        }
    }
    return qEnvironmentVariable("QT_QPA_PLATFORM").startsWith(QLatin1String("eglfs"));
}

/// DRM の接続中の出力(/sys/class/drm/card*-*)
struct DrmOutput {
    QString card;        ///< "card0"
    QString kms;         ///< eglfs の出力名("HDMI1" など)
    QStringList modes;   ///< 対応する解像度("1920x1080" など。先頭が推奨)
};

QList<DrmOutput> scanDrm() {
    QList<DrmOutput> list;
    const QDir drm(QStringLiteral("/sys/class/drm"));
    for (const QString &entry : drm.entryList({QStringLiteral("card*-*")}, QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
        QFile status(drm.filePath(entry + QStringLiteral("/status")));
        if (!status.open(QIODevice::ReadOnly) || status.readAll().trimmed() != "connected") {
            continue;
        }
        DrmOutput out;
        out.card = entry.section(QLatin1Char('-'), 0, 0);              // "card0-HDMI-A-1" → "card0"
        out.kms = kmsName(entry.section(QLatin1Char('-'), 1));       //                 → "HDMI1"
        QFile modes(drm.filePath(entry + QStringLiteral("/modes")));
        if (modes.open(QIODevice::ReadOnly)) {
            for (const QByteArray &line : modes.readAll().split('\n')) {
                const QString mode = QString::fromLatin1(line.trimmed());
                if (!mode.isEmpty() && !out.modes.contains(mode)) out.modes << mode;
            }
        }
        list << out;
    }
    return list;
}

/// 接続中の出力の組み合わせ(抜き差しの検出に使う)
QString outputsKey(const QList<DrmOutput> &outputs) {
    QStringList keys;
    for (const DrmOutput &o : outputs) keys << o.card + QLatin1Char(':') + o.kms;
    keys.sort();
    return keys.join(QLatin1Char(','));
}

QString g_startupOutputs;   ///< 起動時の接続中の出力(eglfs の自動ミラーのときだけ記録する)
bool g_eglfsAuto = false;   ///< eglfs の自動ミラーを使っている(抜き差しを見張る)
} // namespace

void OsDisplayMirror::prepareEglfs(int argc, char *argv[]) {
    if (!wantsEglfs(argc, argv)) {
        return;
    }
    if (qEnvironmentVariableIsSet("QT_QPA_EGLFS_KMS_CONFIG")) {
        g_startupNote = QStringLiteral("QT_QPA_EGLFS_KMS_CONFIG が設定済みのため、自動のミラーは使いません");
        return;
    }
    const QSettings store(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"),
                          QStringLiteral("OpenCruise"));
    // 「全部の画面に表示」がオフなら何もしない。方式の既定は eglfs では OS(KMS の複製)
    if (!store.value(QStringLiteral("display/mirrorAll"), true).toBool()) {
        return;
    }
    const bool useClone = store.value(QStringLiteral("display/mirrorMethod"), 1).toInt() == 1;

    const QList<DrmOutput> connected = scanDrm();
    g_startupOutputs = outputsKey(connected);
    g_eglfsAuto = true;   // どちらの方式でも、eglfs は起動後に画面を足し引きできないので抜き差しを見張る
    if (!useClone) {
        // アプリ内の方式: 画面ごとに別々の出力として使い、Main.qml が 2 枚目以降の画面へ表示を写す
        g_startupNote = QStringLiteral("eglfs: アプリ内の方式でミラーします(画面 %1 枚)").arg(connected.size());
        return;
    }
    if (connected.size() < 2) {
        g_startupNote = QStringLiteral("eglfs: つながっている画面が 1 つのため、ミラーはしません(画面をつなぐと自動で切り替えます)");
        return;
    }

    // 複製元(= アプリのウィンドウを出し、タッチを受ける画面): 画面を名前で指定していればその画面、
    // それ以外は内蔵パネル(タッチパネルが付いているのは普通こちら) → 先頭の順。
    // 外部画面を複製元にすると、内蔵パネルのタッチが外部画面の座標として扱われ、操作できなくなる
    const QString saved = store.value(QStringLiteral("display/screen")).toString();
    int targetIndex = -1;
    for (int i = 0; i < connected.size() && targetIndex < 0; ++i) {
        if (connected[i].kms == saved) targetIndex = i;
    }
    for (int i = 0; i < connected.size() && targetIndex < 0; ++i) {
        if (isInternalName(connected[i].kms)) targetIndex = i;
    }
    if (targetIndex < 0) targetIndex = 0;
    const DrmOutput &target = connected[targetIndex];
    const QString targetMode = target.modes.isEmpty() ? QString() : target.modes.first();

    // 同じ GPU(カード)の出力だけ複製できる。複製先は、複製元と同じ解像度があればそれを使う
    QJsonArray outputs;
    // 複製元をメイン画面にする(アプリのウィンドウはメイン画面に出る)
    QJsonObject targetEntry{{QStringLiteral("name"), target.kms}, {QStringLiteral("primary"), true}};
    // タッチパネルを複製元の画面に結び付ける(QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS の /dev/input/... を使う)
    for (const QString &part : qEnvironmentVariable("QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS").split(QLatin1Char(':'))) {
        if (part.startsWith(QLatin1String("/dev/input/"))) {
            targetEntry.insert(QStringLiteral("touchDevice"), part);
            break;
        }
    }
    if (!targetMode.isEmpty()) targetEntry.insert(QStringLiteral("mode"), targetMode);
    outputs.append(targetEntry);
    QStringList clones;
    QStringList mismatched;
    for (const DrmOutput &o : connected) {
        if (o.kms == target.kms || o.card != target.card) continue;
        QJsonObject entry{{QStringLiteral("name"), o.kms}, {QStringLiteral("clone"), target.kms}};
        if (!targetMode.isEmpty() && o.modes.contains(targetMode)) {
            entry.insert(QStringLiteral("mode"), targetMode);
        } else {
            mismatched << o.kms;
        }
        outputs.append(entry);
        clones << o.kms;
    }
    if (clones.isEmpty()) {
        g_startupNote = QStringLiteral("eglfs: 複製元 %1 と同じ GPU の画面が無いため、ミラーはしません").arg(target.kms);
        return;
    }

    const QJsonObject config{{QStringLiteral("device"), QStringLiteral("/dev/dri/") + target.card},
                             {QStringLiteral("outputs"), outputs}};
    const QString path = QDir::tempPath() + QStringLiteral("/opencruise-eglfs-kms.json");
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        g_startupNote = QStringLiteral("eglfs: ミラーの設定ファイルを作れません: ") + path;
        return;
    }
    const QByteArray json = QJsonDocument(config).toJson(QJsonDocument::Compact);
    file.write(json);
    file.close();
    qputenv("QT_QPA_EGLFS_KMS_CONFIG", path.toLocal8Bit());
    g_startupNote = QStringLiteral("eglfs: %1(%2)の表示を %3 に複製します")
                        .arg(target.kms, targetMode.isEmpty() ? QStringLiteral("解像度不明") : targetMode,
                             clones.join(QStringLiteral(", ")));
    if (!mismatched.isEmpty()) {
        g_startupNote += QStringLiteral("。%1 は同じ解像度に対応していないため、表示されないことがあります")
                             .arg(mismatched.join(QStringLiteral(", ")));
    }
    // うまく複製されないときの調査用に、作った設定をそのまま残す
    g_startupNote += QStringLiteral(" / 設定 %1: %2").arg(path, QString::fromUtf8(json));
}

QString OsDisplayMirror::startupNote() { return g_startupNote; }

OsDisplayMirror::OsDisplayMirror(QObject *parent) : QObject(parent) {
    const QString platform = QGuiApplication::platformName();
    if (platform == QLatin1String("xcb")) {
        program_ = QStandardPaths::findExecutable(QStringLiteral("xrandr"));
        backend_ = program_.isEmpty() ? Backend::None : Backend::Xrandr;
        status_ = program_.isEmpty() ? QStringLiteral("xrandr が見つからないため使えません") : QStringLiteral("使えます(xrandr)");
    } else if (platform.startsWith(QLatin1String("wayland"))) {
        program_ = QStandardPaths::findExecutable(QStringLiteral("kscreen-doctor"));
        const bool kde = qEnvironmentVariable("XDG_CURRENT_DESKTOP").contains(QLatin1String("KDE"), Qt::CaseInsensitive);
        backend_ = (kde && !program_.isEmpty()) ? Backend::KScreen : Backend::None;
        status_ = backend_ == Backend::KScreen
                      ? QStringLiteral("使えます(kscreen-doctor)")
                      : QStringLiteral("この Wayland 環境では、外からミラーを設定できません(KDE Plasma のみ対応)");
    } else if (platform.startsWith(QLatin1String("eglfs"))) {
        backend_ = Backend::Eglfs;
        status_ = g_startupNote.isEmpty() ? QStringLiteral("再起動すると反映されます(KMS の複製表示)") : g_startupNote;
        if (g_eglfsAuto) {
            // eglfs は起動後に画面を足し引きできないので、抜き差しを見張り、変わったら再起動を促す
            connect(&watch_, &QTimer::timeout, this, [this]() {
                if (!displaysChanged_ && outputsKey(scanDrm()) != g_startupOutputs) {
                    displaysChanged_ = true;
                    log::info("DISPLAY", QStringLiteral("eglfs: 画面の接続が変わりました(再起動で反映)"));
                    setStatus(QStringLiteral("画面の接続が変わりました。再起動すると反映されます"));
                }
            });
            watch_.start(2000);
        }
    } else {
        status_ = QStringLiteral("このプラットフォーム(%1)では使えません").arg(platform);
    }
    if (!g_startupNote.isEmpty()) {
        log::info("DISPLAY", g_startupNote);
    }
}

OsDisplayMirror::~OsDisplayMirror() { restore(); }

QString OsDisplayMirror::backendName() const {
    switch (backend_) {
    case Backend::Xrandr: return QStringLiteral("xrandr");
    case Backend::KScreen: return QStringLiteral("kscreen-doctor");
    case Backend::Eglfs: return QStringLiteral("eglfs(KMS)");
    default: return {};
    }
}

void OsDisplayMirror::setStatus(const QString &text) {
    if (status_ != text) {
        status_ = text;
        emit statusChanged();
    }
}

bool OsDisplayMirror::run(const QString &program, const QStringList &args, QString *output, QString *error) {
    QProcess process;
    process.start(program, args);
    if (!process.waitForFinished(5000)) {
        process.kill();
        *error = QStringLiteral("%1 が応答しません").arg(program);
        return false;
    }
    if (output) {
        *output = QString::fromLocal8Bit(process.readAllStandardOutput());
    }
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        *error = QString::fromLocal8Bit(process.readAllStandardError()).trimmed();
        if (error->isEmpty()) {
            *error = QStringLiteral("終了コード %1").arg(process.exitCode());
        }
        return false;
    }
    return true;
}

void OsDisplayMirror::update(bool on, const QString &target, const QStringList &screens) {
    if (backend_ == Backend::Eglfs) {
        return;   // 起動時に決まる(prepareEglfs)。変更は再起動で反映
    }
    if (backend_ == Backend::None) {
        return;
    }
    QStringList sorted = screens;
    sorted.sort();
    const QString key = on ? target + QLatin1Char('|') + sorted.join(QLatin1Char(',')) : QString();
    if (key == appliedKey_) {
        return;
    }
    appliedKey_ = key;
    if (on && !target.isEmpty()) {
        apply(target, screens);
    } else {
        restore();
        setStatus(QStringLiteral("使えます(%1)").arg(backendName()));
    }
}

void OsDisplayMirror::apply(const QString &target, const QStringList &screens) {
    QString error;
    if (backend_ == Backend::Xrandr) {
        // 接続中の出力と、操作する画面の解像度を調べる
        QString text;
        if (!run(program_, {QStringLiteral("--query")}, &text, &error)) {
            setStatus(QStringLiteral("ミラーにできません: ") + error);
            return;
        }
        static const QRegularExpression kLine(QStringLiteral("^(\\S+) connected(?: primary)?(?: (\\d+)x(\\d+)\\+\\d+\\+\\d+)?"),
                                              QRegularExpression::MultilineOption);
        QStringList outputs;
        QString targetSize;
        for (auto it = kLine.globalMatch(text); it.hasNext();) {
            const auto m = it.next();
            outputs << m.captured(1);
            if (m.captured(1) == target && !m.captured(2).isEmpty()) {
                targetSize = m.captured(2) + QLatin1Char('x') + m.captured(3);
            }
        }
        if (!outputs.contains(target) || targetSize.isEmpty()) {
            setStatus(QStringLiteral("ミラーにできません: 操作する画面 %1 が xrandr で見つかりません").arg(target));
            return;
        }
        QStringList args;
        QStringList mirrored;
        for (const QString &name : outputs) {
            if (name == target) continue;
            args << QStringLiteral("--output") << name << QStringLiteral("--auto")
                 << QStringLiteral("--scale-from") << targetSize << QStringLiteral("--same-as") << target;
            mirrored << name;
        }
        if (mirrored.isEmpty()) {
            setStatus(QStringLiteral("ミラーにする画面がありません(xrandr)"));
            return;
        }
        if (!run(program_, args, nullptr, &error)) {
            setStatus(QStringLiteral("ミラーにできません: ") + error);
            log::warn("DISPLAY", QStringLiteral("xrandr でミラーにできません: ") + error);
            return;
        }
        for (const QString &name : mirrored) {
            if (!mirrored_.contains(name)) mirrored_ << name;
        }
        target_ = target;
        setStatus(QStringLiteral("%1 の表示を %2 に複製中(xrandr)").arg(target, mirrored.join(QStringLiteral(", "))));
        log::info("DISPLAY", status_);
    } else if (backend_ == Backend::KScreen) {
        QStringList args;
        QStringList mirrored;
        for (const QString &name : screens) {
            if (name == target) continue;
            args << QStringLiteral("output.%1.mirror.%2").arg(name, target);
            mirrored << name;
        }
        if (mirrored.isEmpty()) {
            setStatus(QStringLiteral("ミラーにする画面がありません(kscreen-doctor)"));
            return;
        }
        if (!run(program_, args, nullptr, &error)) {
            setStatus(QStringLiteral("ミラーにできません(Plasma 6 以降が必要です): ") + error);
            log::warn("DISPLAY", QStringLiteral("kscreen-doctor でミラーにできません: ") + error);
            return;
        }
        for (const QString &name : mirrored) {
            if (!mirrored_.contains(name)) mirrored_ << name;
        }
        target_ = target;
        setStatus(QStringLiteral("%1 の表示を %2 に複製中(kscreen-doctor)").arg(target, mirrored.join(QStringLiteral(", "))));
        log::info("DISPLAY", status_);
    }
}

void OsDisplayMirror::restore() {
    if (mirrored_.isEmpty() || target_.isEmpty()) {
        mirrored_.clear();
        return;
    }
    QString error;
    QStringList args;
    if (backend_ == Backend::Xrandr) {
        // 操作する画面の右へ、順に横へ並べ直す(拡張表示)
        QString left = target_;
        for (const QString &name : mirrored_) {
            args << QStringLiteral("--output") << name << QStringLiteral("--auto") << QStringLiteral("--scale")
                 << QStringLiteral("1x1") << QStringLiteral("--right-of") << left;
            left = name;
        }
    } else if (backend_ == Backend::KScreen) {
        for (const QString &name : mirrored_) {
            args << QStringLiteral("output.%1.mirror.none").arg(name);
        }
    }
    if (!args.isEmpty()) {
        if (run(program_, args, nullptr, &error)) {
            log::info("DISPLAY", QStringLiteral("ミラーを解除しました: ") + mirrored_.join(QStringLiteral(", ")));
        } else {
            log::warn("DISPLAY", QStringLiteral("ミラーを解除できません: ") + error);
        }
    }
    mirrored_.clear();
}

} // namespace opencruise
