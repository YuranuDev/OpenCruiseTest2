/**
 * @file Log.cpp
 * @brief Log.h の実装。Qt のメッセージハンドラを差し替え、既存の qDebug/qInfo/qWarning も
 *        同じ形式でファイルへ残す。
 *
 * 設計上の要点:
 *  - 書き込みはミューテックスで直列化する（映像スレッドからも呼ばれるため）。
 *  - WARN 以上と 500ms 経過時はフラッシュし、異常終了時にも直前までの内容が残るようにする。
 *  - ファイルサイズが上限を超えたら分割し、起動ごとのファイル名（日時 + PID）で識別できる。
 */
#include "Log.h"

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdio>
#include <mutex>

#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileInfoList>
#include <QStandardPaths>
#include <QSysInfo>
#include <QThread>

namespace opencruise::log {

const char *levelToString(Level level) {
    static const char *names[] = {"DEBUG", "INFO", "WARN", "ERROR", "FATAL"};
    const int index = static_cast<int>(level);
    if (index < 0 || index >= static_cast<int>(sizeof(names) / sizeof(names[0]))) {
        return "INFO";
    }
    return names[index];
}

Level parseLevel(const QString &text, bool *ok) {
    struct Entry {
        const char *name;
        Level level;
    };
    static const Entry table[] = {
        {"debug", Level::Debug}, {"info", Level::Info},  {"warn", Level::Warn},
        {"warning", Level::Warn}, {"error", Level::Error}, {"fatal", Level::Fatal},
    };

    const QString value = text.trimmed().toLower();
    for (const Entry &entry : table) {
        if (value == QLatin1String(entry.name)) {
            if (ok != nullptr) {
                *ok = true;
            }
            return entry.level;
        }
    }
    if (ok != nullptr) {
        *ok = false;
    }
    return Level::Info;
}

namespace {

/**
 * @brief ログ基盤の内部状態。
 */
struct State {
    std::mutex mutex;
    Options options;
    QFile file;
    QString directory;
    QString currentPath;
    QString basePath;
    quint64 partBytes = 0;
    int part = 1;
    bool fileActive = false;
    bool initialized = false;
    bool handlerInstalled = false;
    qint64 lastFlushMs = 0;
    bool writeFailureNotified = false;
};

State g_state;

/// メッセージハンドラの再入防止（ログ出力中に発生した Qt の警告で無限ループしないため）
thread_local bool t_inHandler = false;

QString threadIdText() {
    const auto id = QThread::currentThreadId();
    return QStringLiteral("0x") +
           QString::number(static_cast<qulonglong>(reinterpret_cast<quintptr>(id)), 16);
}

/**
 * @brief 古い実行のログを削除して、残す件数を保つ（ロック済みで呼ぶ）。
 */
void pruneOldRunsLocked(const QString &directory, int keep) {
    QDir dir(directory);
    const QFileInfoList files =
        dir.entryInfoList(QStringList() << QStringLiteral("opencruise_*.log"), QDir::Files, QDir::Time);
    // QDir::Time は新しい順。keep 件を残し、それより古いものを削除する
    for (int index = files.size() - 1; index >= keep; --index) {
        const QString path = files.at(index).absoluteFilePath();
        if (!QFile::remove(path)) {
            std::fprintf(stderr, "[LOG] 古いログを削除できません: %s\n", qPrintable(path));
            std::fflush(stderr);
        }
    }
}

/**
 * @brief 現在の分割番号のファイルを開く（ロック済みで呼ぶ）。
 */
bool openPartLocked() {
    const QString path = (g_state.part == 1)
                             ? g_state.basePath + QStringLiteral(".log")
                             : QStringLiteral("%1_part%2.log").arg(g_state.basePath).arg(g_state.part);
    g_state.file.setFileName(path);
    if (!g_state.file.open(QIODevice::WriteOnly | QIODevice::Append)) {
        return false;
    }
    g_state.currentPath = path;
    g_state.partBytes = static_cast<quint64>(g_state.file.size());
    g_state.lastFlushMs = QDateTime::currentMSecsSinceEpoch();
    return true;
}

/**
 * @brief サイズ上限に達したので次の分割ファイルへ移る（ロック済みで呼ぶ）。
 */
bool rotateLocked() {
    g_state.file.close();
    if (g_state.part >= std::max(1, g_state.options.maxFilesPerRun)) {
        g_state.fileActive = false;
        std::fprintf(stderr, "[LOG] ログファイルの分割上限に達したため、以降はコンソールのみに出力します\n");
        std::fflush(stderr);
        return false;
    }
    ++g_state.part;
    if (!openPartLocked()) {
        g_state.fileActive = false;
        return false;
    }
    g_state.fileActive = true;
    return true;
}

/**
 * @brief 書き込み失敗を 1 回だけ通知し、以降のファイル出力を止める（ロック済みで呼ぶ）。
 */
void reportWriteFailureLocked() {
    if (!g_state.writeFailureNotified) {
        g_state.writeFailureNotified = true;
        std::fprintf(stderr, "[LOG] ログファイルへの書き込みに失敗しました: %s (%s)\n",
                     qPrintable(g_state.currentPath), qPrintable(g_state.file.errorString()));
        std::fflush(stderr);
    }
    g_state.fileActive = false;
}

/**
 * @brief 1 行をコンソールとファイルへ出力する。
 */
void appendLine(Level level, const QString &line) {
    QByteArray bytes = line.toUtf8();
    bytes.append('\n');

    Options options;
    {
        std::lock_guard<std::mutex> lock(g_state.mutex);
        options = g_state.options;
    }
    if (options.mirrorToConsole) {
        std::fwrite(bytes.constData(), 1, static_cast<std::size_t>(bytes.size()), stderr);
        std::fflush(stderr);
    }

    std::lock_guard<std::mutex> lock(g_state.mutex);
    if (!g_state.fileActive) {
        return;
    }
    if (options.maxFileBytes > 0 &&
        (g_state.partBytes + static_cast<quint64>(bytes.size())) > static_cast<quint64>(options.maxFileBytes)) {
        if (!rotateLocked()) {
            return;
        }
    }
    const qint64 written = g_state.file.write(bytes);
    if (written != bytes.size()) {
        reportWriteFailureLocked();
        return;
    }
    g_state.partBytes += static_cast<quint64>(written);

    // 異常終了時にも調査材料を残すため、WARN 以上は即時、それ以外も 500ms ごとにフラッシュする
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const bool flushNow =
        (level == Level::Warn) || (level == Level::Error) || (level == Level::Fatal) || ((now - g_state.lastFlushMs) >= 500);
    if (flushNow) {
        g_state.file.flush();
        g_state.lastFlushMs = now;
    }
}

/**
 * @brief 1 行を整形して出力する。
 */
void emitLine(Level level, const QString &component, const QString &message, const QMessageLogContext *context) {
    Options options;
    {
        std::lock_guard<std::mutex> lock(g_state.mutex);
        options = g_state.options;
    }
    if (static_cast<int>(level) < static_cast<int>(options.minLevel)) {
        return;
    }

    QString line;
    line.reserve(message.size() + 128);
    line += QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH:mm:ss.zzz"));
    line += QStringLiteral(" [");
    line += QString::fromLatin1(levelToString(level));
    line += QStringLiteral("] [");
    line += component.isEmpty() ? QStringLiteral("APP") : component;
    line += QStringLiteral("] ");
    line += message;
    if (level == Level::Debug) {
        line += QStringLiteral(" (tid=%1)").arg(threadIdText());
    }
    if (context != nullptr && context->file != nullptr && context->line > 0) {
        line += QStringLiteral(" (%1:%2)").arg(QString::fromUtf8(context->file)).arg(context->line);
    }
    appendLine(level, line);
}

/**
 * @brief メッセージ先頭の [tag] をコンポーネント名として取り出す（最後のタグを採用）。
 */
QString takeComponent(const QMessageLogContext &context, QString &text) {
    QString component;
    for (;;) {
        if (!text.startsWith(QLatin1Char('['))) {
            break;
        }
        const int close = text.indexOf(QLatin1Char(']'));
        if (close <= 1 || close > 32) {
            break;
        }
        const QString tag = text.mid(1, close - 1).trimmed();
        if (tag.isEmpty() || tag.contains(QLatin1Char(' '))) {
            break;
        }
        component = tag;
        text = text.mid(close + 1);
        if (text.startsWith(QLatin1Char(' '))) {
            text.remove(0, 1);
        }
    }
    if (component.isEmpty()) {
        const QString category = (context.category != nullptr) ? QString::fromLatin1(context.category) : QString();
        component = (category.isEmpty() || category == QLatin1String("default")) ? QStringLiteral("QT") : category;
    }
    return component.toUpper();
}

/**
 * @brief Qt のメッセージハンドラ。Qt 内部（QML/描画を含む）の警告もここを通る。
 */
void messageHandler(QtMsgType type, const QMessageLogContext &context, const QString &message) {
    if (t_inHandler) {
        // 再入時は素の stderr へ（整形しない）
        const QByteArray raw = message.toUtf8();
        std::fprintf(stderr, "%s\n", raw.constData());
        return;
    }
    t_inHandler = true;

    Level level = Level::Info;
    switch (type) {
    case QtDebugMsg:
        level = Level::Debug;
        break;
    case QtInfoMsg:
        level = Level::Info;
        break;
    case QtWarningMsg:
        level = Level::Warn;
        break;
    case QtCriticalMsg:
        level = Level::Error;
        break;
    case QtFatalMsg:
        level = Level::Fatal;
        break;
    }

    QString text = message;
    const QString component = takeComponent(context, text);
    emitLine(level, component, text, &context);
    t_inHandler = false;
}

} // namespace

QString defaultDirectory() {
    QString base = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    if (base.isEmpty()) {
        base = QCoreApplication::applicationDirPath();
    }
    if (base.isEmpty()) {
        base = QDir::tempPath();
    }
    return base + QStringLiteral("/logs");
}

Options defaultOptions() {
    Options options;
    options.directory = defaultDirectory();

    const QByteArray directoryFromEnv = qgetenv("OPENCRUISE_LOG_DIR");
    if (!directoryFromEnv.isEmpty()) {
        options.directory = QString::fromLocal8Bit(directoryFromEnv);
    }

    bool levelOk = false;
    const Level levelFromEnv = parseLevel(QString::fromLocal8Bit(qgetenv("OPENCRUISE_LOG_LEVEL")), &levelOk);
    if (levelOk) {
        options.minLevel = levelFromEnv;
    }

    const QByteArray bytesFromEnv = qgetenv("OPENCRUISE_LOG_MAX_BYTES");
    if (!bytesFromEnv.isEmpty()) {
        bool sizeOk = false;
        const qlonglong value = bytesFromEnv.toLongLong(&sizeOk);
        if (sizeOk && value > 0) {
            options.maxFileBytes = value;
        }
    }
    return options;
}

bool initialize(const Options &requestedOptions, QString *errorMessage) {
    Options options = requestedOptions;
    if (options.directory.trimmed().isEmpty()) {
        options.directory = defaultDirectory();
    }
    if (options.maxFilesPerRun < 1) {
        options.maxFilesPerRun = 1;
    }
    if (options.maxRuns < 1) {
        options.maxRuns = 1;
    }

    {
        std::lock_guard<std::mutex> lock(g_state.mutex);
        if (g_state.initialized) {
            if (errorMessage != nullptr) {
                *errorMessage = QStringLiteral("ログ基盤は既に初期化されています");
            }
            return g_state.fileActive;
        }
        g_state.initialized = true;
        g_state.options = options;
        g_state.directory = options.directory;
        g_state.part = 1;
        g_state.partBytes = 0;
        g_state.writeFailureNotified = false;

        QString failure;
        QDir dir(options.directory);
        if (!dir.exists() && !QDir().mkpath(options.directory)) {
            failure = QStringLiteral("ログディレクトリを作成できません: ") + options.directory;
        } else {
            pruneOldRunsLocked(options.directory, options.maxRuns);
            const QString stamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss_zzz"));
            g_state.basePath = options.directory + QStringLiteral("/opencruise_") + stamp + QStringLiteral("_pid") +
                               QString::number(QCoreApplication::applicationPid());
            if (openPartLocked()) {
                g_state.fileActive = true;
            } else {
                failure = QStringLiteral("ログファイルを開けません: %1 (%2)")
                              .arg(g_state.file.fileName(), g_state.file.errorString());
            }
        }
        if (!g_state.fileActive && errorMessage != nullptr) {
            *errorMessage = failure;
        }
    }

    qInstallMessageHandler(&messageHandler);
    g_state.handlerInstalled = true;

    info("LOG", QStringLiteral("ログを開始しました (ファイル出力: %1)")
                    .arg(g_state.fileActive ? QStringLiteral("有効") : QStringLiteral("無効")));
    info("LOG", describeEnvironment());
    if (g_state.fileActive) {
        info("LOG", QStringLiteral("ログファイル: %1").arg(currentFilePath()));
        info("LOG", QStringLiteral("記録レベル: %1 以上 / サイズ上限: %2 バイト / 分割上限: %3")
                        .arg(QString::fromLatin1(levelToString(options.minLevel)))
                        .arg(options.maxFileBytes)
                        .arg(options.maxFilesPerRun));
    } else {
        warn("LOG", QStringLiteral("ファイルへのログ出力を開始できませんでした。コンソールのみ出力します"));
    }
    return g_state.fileActive;
}

void shutdown() {
    bool wasInitialized = false;
    {
        std::lock_guard<std::mutex> lock(g_state.mutex);
        wasInitialized = g_state.initialized;
    }
    if (!wasInitialized) {
        return;
    }

    info("LOG", QStringLiteral("ログを終了します"));

    {
        std::lock_guard<std::mutex> lock(g_state.mutex);
        if (g_state.file.isOpen()) {
            g_state.file.flush();
            g_state.file.close();
        }
        g_state.fileActive = false;
        g_state.initialized = false;
        g_state.currentPath.clear();
        g_state.basePath.clear();
        g_state.partBytes = 0;
        g_state.part = 1;
    }
    if (g_state.handlerInstalled) {
        qInstallMessageHandler(nullptr);
        g_state.handlerInstalled = false;
    }
}

bool isFileLoggingActive() {
    std::lock_guard<std::mutex> lock(g_state.mutex);
    return g_state.fileActive;
}

QString currentFilePath() {
    std::lock_guard<std::mutex> lock(g_state.mutex);
    return g_state.currentPath;
}

QString directoryPath() {
    std::lock_guard<std::mutex> lock(g_state.mutex);
    return g_state.directory;
}

void write(Level level, const char *component, const QString &message) {
    const QString name = (component != nullptr && *component != '\0') ? QString::fromLatin1(component).toUpper()
                                                                      : QStringLiteral("APP");
    emitLine(level, name, message, nullptr);
}

void debug(const char *component, const QString &message) { write(Level::Debug, component, message); }

void info(const char *component, const QString &message) { write(Level::Info, component, message); }

void warn(const char *component, const QString &message) { write(Level::Warn, component, message); }

void error(const char *component, const QString &message) { write(Level::Error, component, message); }

void fatal(const char *component, const QString &message) { write(Level::Fatal, component, message); }

QString describeEnvironment() {
    QString text = QStringLiteral("環境: OS=%1 / カーネル=%2 / CPU=%3 / Qt=%4 (ビルド %5) / アプリ=%6 %7")
                       .arg(QSysInfo::prettyProductName(), QSysInfo::kernelVersion(), QSysInfo::currentCpuArchitecture(),
                            QString::fromLatin1(qVersion()), QString::fromLatin1(QT_VERSION_STR),
                            QCoreApplication::applicationName(), QCoreApplication::applicationVersion());
#ifdef OPENCRUISE_WITH_AASDK
    text += QStringLiteral(" / aasdk=有効");
#else
    text += QStringLiteral(" / aasdk=無効");
#endif
    text += QStringLiteral(" / プロセスID=%1").arg(QCoreApplication::applicationPid());
    return text;
}

Stopwatch::Stopwatch()
    : startedMs_(std::chrono::duration_cast<std::chrono::milliseconds>(
                     std::chrono::steady_clock::now().time_since_epoch())
                     .count()) {}

qint64 Stopwatch::elapsedMs() const {
    const auto now = std::chrono::duration_cast<std::chrono::milliseconds>(
                         std::chrono::steady_clock::now().time_since_epoch())
                         .count();
    return static_cast<qint64>(now - startedMs_);
}

} // namespace opencruise::log
