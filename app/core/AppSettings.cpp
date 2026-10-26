/**
 * @file AppSettings.cpp
 * @brief AppSettings の実装。
 */
#include "AppSettings.h"

#include <QCoreApplication>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QFont>
#include <QSet>
#include <QSettings>
#include <QProcess>
#include <QStandardPaths>
#include <QThread>

#include <memory>

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

/// カタログのフォントのファイル名の頭(ファイル名だけでファミリを見分け、使うときまで読み込まない)
QString familyOfFile(const QString &fileName) {
    if (fileName.startsWith(QStringLiteral("NotoSansCJKjp-"), Qt::CaseInsensitive)) return QStringLiteral("Noto Sans CJK JP");
    if (fileName.startsWith(QStringLiteral("NotoSansJP-"), Qt::CaseInsensitive)) return QStringLiteral("Noto Sans JP");
    if (fileName.startsWith(QStringLiteral("IBMPlexSansJP-"), Qt::CaseInsensitive)) return QStringLiteral("IBM Plex Sans JP");
    return {};
}

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
    int foundFiles = 0;
    for (const QString &dir : fontSearchDirs()) {
        if (!QDir(dir).exists()) {
            continue;
        }
        int foundInDir = 0;
        int loadedNow = 0;
        QDirIterator it(dir, {QStringLiteral("*.otf"), QStringLiteral("*.ttf")}, QDir::Files,
                        QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QString path = it.next();
            ++foundInDir;
            const QString family = familyOfFile(QFileInfo(path).fileName());
            if (!family.isEmpty()) {
                pendingFontFiles_[family] << path;   // カタログのフォントは、使うときに読み込む
                continue;
            }
            // カタログ外(アイコンなど小さいもの)は、今のうちに登録する
            if (QFontDatabase::addApplicationFont(path) < 0) {
                log::warn("FONT", QStringLiteral("フォントを読み込めません: ") + path);
            } else {
                ++loadedNow;
            }
        }
        foundFiles += foundInDir;
        log::info("FONT", QStringLiteral("%1 に %2 個のフォントがあります(すぐ登録: %3 個。ほかは使うときに登録)")
                              .arg(dir).arg(foundInDir).arg(loadedNow));
        if (foundInDir > 0) {
            break; // 最初に見つかった探索先だけを使う(同じフォントの二重登録を避ける)
        }
    }

    // 内部の細かいスタイル名(例: "IBM Plex Sans JP Text")は出さず、カタログのファミリだけを選択肢にする
    for (const QString &name : kFontCatalog) {
        if (pendingFontFiles_.contains(name)) {
            fontFamilies_ << name;
        } else if (foundFiles > 0) {
            log::warn("FONT", QStringLiteral("同梱フォントが見つかりません: ") + name);
        }
    }
    if (foundFiles == 0) {
        log::warn("FONT", QStringLiteral("同梱フォントが見つかりませんでした。OS 既定のフォントを使用します"));
    }
    return foundFiles;
}

namespace {
/// 起動時に先に読む太さ: 通常(Regular)だけ。太字・Light などは別スレッドで読み、届くまでは通常の字形から
/// 合成した太字で表示する(起動画面が出るまでの時間を短くするため)
bool isEssentialWeight(const QString &path) {
    return QFileInfo(path).completeBaseName().endsWith(QStringLiteral("-Regular"), Qt::CaseInsensitive);
}
/// 読んだフォントのデータを登録し、そのファミリが登録できたかを返す
bool registerFontData(const QString &family, const QString &path, const QByteArray &data) {
    if (data.isEmpty()) {
        log::warn("FONT", QStringLiteral("フォントを読み込めません: ") + path);
        return false;
    }
    const int id = QFontDatabase::addApplicationFontFromData(data);
    if (id < 0) {
        log::warn("FONT", QStringLiteral("フォントを登録できません: ") + path);
        return false;
    }
    return QFontDatabase::applicationFontFamilies(id).contains(family);
}
QByteArray readFontFile(const QString &path) {
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
}
} // namespace

bool AppSettings::loadFontNow(const QString &family, bool essentialOnly) {
    if (family.isEmpty()) {
        return false;
    }
    QStringList &pending = pendingFontFiles_[family];
    QStringList now;
    for (const QString &path : pending) {
        if (!essentialOnly || isEssentialWeight(path)) now << path;
    }
    if (now.isEmpty() && !pending.isEmpty()) {
        now << pending.first(); // 決まった名前の太さが無いときは、1 つだけでも先に読む
    }
    for (const QString &path : now) pending.removeAll(path);
    if (pending.isEmpty()) pendingFontFiles_.remove(family);

    const log::Stopwatch timer;
    bool registered = registeredFamilies_.contains(family);
    for (const QString &path : now) {
        if (registerFontData(family, path, readFontFile(path))) registered = true;
    }
    if (registered && !registeredFamilies_.contains(family)) registeredFamilies_ << family;
    log::info("FONT", QStringLiteral("%1 を登録しました(%2 ファイル、%3 ms)").arg(family).arg(now.size()).arg(timer.elapsedMs()));
    return registered;
}

void AppSettings::loadFontInBackground(const QString &family, std::function<void(bool)> then) {
    const QStringList files = pendingFontFiles_.take(family);
    if (files.isEmpty()) {
        if (then) then(registeredFamilies_.contains(family));
        return;
    }
    // ファイルの読み込み(時間がかかる)だけを別スレッドで行い、登録は UI スレッドで行う
    auto results = std::make_shared<QList<QByteArray>>();
    QThread *thread = QThread::create([files, results]() {
        for (const QString &path : files) results->append(readFontFile(path));
    });
    fontThreads_ << thread;
    loadingFamilies_ << family;
    const auto timer = std::make_shared<log::Stopwatch>();
    connect(thread, &QThread::finished, this, [this, thread, family, files, results, timer, then]() {
        fontThreads_.removeAll(thread);
        loadingFamilies_.removeOne(family);
        thread->deleteLater();
        bool registered = registeredFamilies_.contains(family);
        for (int i = 0; i < files.size() && i < results->size(); ++i) {
            if (registerFontData(family, files.at(i), results->at(i))) registered = true;
        }
        if (registered && !registeredFamilies_.contains(family)) registeredFamilies_ << family;
        log::info("FONT", QStringLiteral("%1 の残りを登録しました(%2 ファイル、%3 ms。画面は止めずに読み込み)")
                              .arg(family).arg(files.size()).arg(timer->elapsedMs()));
        emit fontLoadFinished(family, static_cast<int>(files.size()), timer->elapsedMs());
        if (then) then(registered);
    });
    thread->start(QThread::LowPriority);
}

void AppSettings::applyFontFamily(const QString &family) {
    if (family == fontFamily_) {
        return;
    }
    fontFamily_ = family;
    openStore().setValue(QStringLiteral("ui/fontFamily"), fontFamily_);
    QGuiApplication::setFont(QFont(fontFamily_));
    emit fontFamilyChanged();
}

AppSettings::AppSettings(QObject *parent) : QObject(parent) {
    loadBundledFonts();

    const QSettings store = openStore();
    userName_ = store.value(QStringLiteral("user/name"), QString()).toString().trimmed();
    powerMode_ = qBound(0, store.value(QStringLiteral("power/mode"), 0).toInt(), 2);
    phoneNoticePopupEnabled_ = store.value(QStringLiteral("notifications/phonePopups"), false).toBool();
    applyPowerMode();

    // 保存値が選択肢に無い(フォント未同梱・設定の破損など)場合は既定、既定も無ければ OS 既定。
    // 起動時に登録するのは、使うフォントの分だけ
    QString family = store.value(QStringLiteral("ui/fontFamily"), kDefaultFont).toString();
    if (!fontFamilies_.contains(family)) {
        family = fontFamilies_.contains(kDefaultFont) ? kDefaultFont : QString();
    }
    if (!family.isEmpty() && !loadFontNow(family, true)) {
        family = (family != kDefaultFont && loadFontNow(kDefaultFont, true)) ? kDefaultFont : QString();
    }
    fontFamily_ = family;
    if (!fontFamily_.isEmpty()) {
        QGuiApplication::setFont(QFont(fontFamily_));
        // 残りの太さは、画面を止めずに読む(読み終わったものから使える)
        loadFontInBackground(fontFamily_);
    }
}

AppSettings::~AppSettings() {
    // 読み込み中のフォントのスレッドは、終わるのを待ってから破棄する(ファイルを読んでいるだけなので、すぐ終わる)
    for (QThread *thread : fontThreads_) {
        thread->wait();
        delete thread;
    }
    restorePowerMode();
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
    if (registeredFamilies_.contains(family)) {
        requestedFamily_.clear();
        applyFontFamily(family);
        loadFontInBackground(family); // 残りの太さがあれば読む
        return;
    }
    // 初めて選ばれたフォント: 画面を止めないよう別スレッドで読み、読み終わったら切り替える
    // (読んでいる間にほかのフォントを選んだら、最後に選んだものにする)
    requestedFamily_ = family;
    if (loadingFamilies_.contains(family)) {
        return; // もう読んでいる: 読み終わったときに切り替える
    }
    loadFontInBackground(family, [this, family](bool ok) {
        if (requestedFamily_ != family) {
            return;
        }
        requestedFamily_.clear();
        if (ok) {
            applyFontFamily(family);
        } else {
            log::warn("FONT", QStringLiteral("フォントを登録できませんでした: ") + family);
        }
    });
}

void AppSettings::setPowerMode(int mode) {
    const int boundedMode = qBound(0, mode, 2);
    if (boundedMode == powerMode_) {
        return;
    }
    powerMode_ = boundedMode;
    openStore().setValue(QStringLiteral("power/mode"), powerMode_);
    applyPowerMode();
    emit powerModeChanged();
}

void AppSettings::setPhoneNoticePopupEnabled(bool enabled) {
    if (enabled == phoneNoticePopupEnabled_) {
        return;
    }
    phoneNoticePopupEnabled_ = enabled;
    openStore().setValue(QStringLiteral("notifications/phonePopups"), phoneNoticePopupEnabled_);
    emit phoneNoticePopupEnabledChanged();
}

void AppSettings::applyPowerMode() {
#ifdef Q_OS_LINUX
    if (QStandardPaths::findExecutable(QStringLiteral("powerprofilesctl")).isEmpty()) {
        powerModeStatus_ = QStringLiteral("power-profiles-daemon / powerprofilesctl が見つかりません");
        return;
    }
    if (powerProcess_) {
        powerReapply_ = true; // 適用中: 終わったら、今の設定でもう一度適用する
        return;
    }
    powerModeStatus_ = QStringLiteral("電源モードを適用しています");
    runPowerStep();
#else
    powerModeStatus_ = QStringLiteral("Linux 以外では利用できません");
#endif
}

void AppSettings::runPowerStep() {
#ifdef Q_OS_LINUX
    // 手順: (初回だけ)今のプロファイルを読む(終了時に戻すため) → 選んだプロファイルにする。
    // どちらも別プロセスの完了を待たず、終わったら finished で次へ進む(起動や画面を止めない)
    const QString executable = QStandardPaths::findExecutable(QStringLiteral("powerprofilesctl"));
    const bool reading = !powerOriginalTried_;
    powerOriginalTried_ = true;
    const QStringList profiles = {QStringLiteral("balanced"), QStringLiteral("power-saver"),
                                  QStringLiteral("performance")};
    const QString target = profiles.at(powerMode_);
    powerProcess_ = new QProcess(this);
    connect(powerProcess_, &QProcess::finished, this, [this, reading, target](int exitCode, QProcess::ExitStatus status) {
        QProcess *process = powerProcess_;
        powerProcess_ = nullptr;
        const bool ok = status == QProcess::NormalExit && exitCode == 0;
        if (reading) {
            // 読めなかったときは空のまま(終了時に戻さない)
            if (ok) originalPowerProfile_ = QString::fromLocal8Bit(process->readAllStandardOutput()).trimmed();
            process->deleteLater();
            runPowerStep(); // 続けて設定する
            return;
        }
        if (ok) {
            powerModeStatus_ = QStringLiteral("%1 を適用しました").arg(target);
        } else {
            const QString detail = QString::fromLocal8Bit(process->readAllStandardError()).trimmed();
            powerModeStatus_ = detail.isEmpty() ? QStringLiteral("電源モードを適用できませんでした") : detail;
        }
        process->deleteLater();
        emit powerModeChanged(); // 状態の文言を更新する
        if (powerReapply_) {
            powerReapply_ = false;
            applyPowerMode();
        }
    });
    connect(powerProcess_, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart || !powerProcess_) {
            return; // 実行中のエラーは finished で扱う
        }
        powerProcess_->deleteLater();
        powerProcess_ = nullptr;
        powerModeStatus_ = QStringLiteral("電源モードを適用できませんでした(powerprofilesctl を起動できません)");
        emit powerModeChanged();
    });
    if (reading) {
        powerProcess_->start(executable, {QStringLiteral("get")});
    } else {
        powerProcess_->start(executable, {QStringLiteral("set"), target});
    }
#endif
}

void AppSettings::restorePowerMode() {
#ifdef Q_OS_LINUX
    if (originalPowerProfile_.isEmpty()) {
        return;
    }
    const QString executable = QStandardPaths::findExecutable(QStringLiteral("powerprofilesctl"));
    if (executable.isEmpty()) {
        return;
    }
    QProcess process;
    process.start(executable, {QStringLiteral("set"), originalPowerProfile_});
    if (!process.waitForStarted(1000) || !process.waitForFinished(2000) ||
        process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        log::warn("POWER", QStringLiteral("以前の Linux 電源プロファイルを復元できませんでした: ") + originalPowerProfile_);
    }
#endif
}

} // namespace opencruise
