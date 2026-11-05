/**
 * @file AppInfo.cpp
 * @brief AppInfo の実装。
 */
#include "AppInfo.h"

#include "Log.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QFile>
#include <QGuiApplication>
#include <QLocale>
#include <QSysInfo>

#if defined(__GLIBC__)
#include <gnu/libc-version.h>
#endif

namespace opencruise {

namespace {
/// 秒数を「1日 2時間 3分」「4分 5秒」の形にする
QString formatDuration(qint64 sec) {
    if (sec < 0) {
        return QStringLiteral("--");
    }
    const qint64 d = sec / 86400;
    const qint64 h = (sec % 86400) / 3600;
    const qint64 m = (sec % 3600) / 60;
    const qint64 s = sec % 60;
    if (d > 0) {
        return QStringLiteral("%1日 %2時間 %3分").arg(d).arg(h).arg(m);
    }
    if (h > 0) {
        return QStringLiteral("%1時間 %2分").arg(h).arg(m);
    }
    return QStringLiteral("%1分 %2秒").arg(m).arg(s);
}

/// 空文字列なら "--"
QString orDash(const QString &text) { return text.isEmpty() ? QStringLiteral("--") : text; }
} // namespace

/**
 * @brief 起動時刻を記録し、稼働時間を 1 秒ごとに更新する。
 */
AppInfo::AppInfo(QObject *parent) : QObject(parent) {
    const QDateTime now = QDateTime::currentDateTime();
    startedMs_ = now.toMSecsSinceEpoch();
    startedAt_ = now.toString(QStringLiteral("yyyy-MM-dd HH:mm:ss"));
    timer_.setInterval(1000);
    connect(&timer_, &QTimer::timeout, this, &AppInfo::refreshUptime);
    refreshUptime();
    timer_.start();
}

QString AppInfo::appName() const { return QCoreApplication::applicationName(); }

QString AppInfo::appVersion() const { return orDash(QCoreApplication::applicationVersion()); }

QString AppInfo::qtVersion() const {
    return QStringLiteral("%1(ビルド %2)").arg(QString::fromLatin1(qVersion()), QString::fromLatin1(QT_VERSION_STR));
}

QString AppInfo::buildInfo() const {
#if defined(__clang__)
    const QString compiler = QStringLiteral("Clang %1.%2.%3").arg(__clang_major__).arg(__clang_minor__).arg(__clang_patchlevel__);
#elif defined(__GNUC__)
    const QString compiler = QStringLiteral("GCC %1.%2.%3").arg(__GNUC__).arg(__GNUC_MINOR__).arg(__GNUC_PATCHLEVEL__);
#else
    const QString compiler = QStringLiteral("不明なコンパイラ");
#endif
    return QStringLiteral("%1 / %2").arg(compiler, QSysInfo::buildAbi());
}

bool AppInfo::aasdkEnabled() const {
#ifdef OPENCRUISE_WITH_AASDK
    return true;
#else
    return false;
#endif
}

QString AppInfo::platformName() const { return orDash(QGuiApplication::platformName()); }

qint64 AppInfo::processId() const { return QCoreApplication::applicationPid(); }

bool AppInfo::fileLogging() const { return log::isFileLoggingActive(); }

QString AppInfo::logFile() const { return orDash(log::currentFilePath()); }

QString AppInfo::logDirectory() const { return orDash(log::directoryPath()); }

QString AppInfo::osName() const { return orDash(QSysInfo::prettyProductName()); }

QString AppInfo::kernel() const { return QSysInfo::kernelType() + QLatin1Char(' ') + QSysInfo::kernelVersion(); }

QString AppInfo::cpuArchitecture() const { return orDash(QSysInfo::currentCpuArchitecture()); }

QString AppInfo::hostName() const { return orDash(QSysInfo::machineHostName()); }

QString AppInfo::libcVersion() const {
#if defined(__GLIBC__)
    return QStringLiteral("glibc %1").arg(QString::fromLatin1(gnu_get_libc_version()));
#else
    return QStringLiteral("--");
#endif
}

QString AppInfo::session() const {
    const QString desktop = qEnvironmentVariable("XDG_CURRENT_DESKTOP");
    const QString type = qEnvironmentVariable("XDG_SESSION_TYPE");
    if (desktop.isEmpty() && type.isEmpty()) {
        return QStringLiteral("--");
    }
    if (desktop.isEmpty() || type.isEmpty()) {
        return desktop + type;
    }
    return QStringLiteral("%1(%2)").arg(desktop, type);
}

QString AppInfo::locale() const { return QLocale::system().name(); }

/**
 * @brief アプリの稼働時間は起動時刻から、OS の稼働時間は /proc/uptime から求める。
 */
void AppInfo::refreshUptime() {
    const qint64 appSec = (QDateTime::currentMSecsSinceEpoch() - startedMs_) / 1000;
    qint64 sysSec = -1;
    QFile file(QStringLiteral("/proc/uptime"));
    if (file.open(QIODevice::ReadOnly)) {
        bool ok = false;
        const double value = QString::fromLatin1(file.readLine()).section(QLatin1Char(' '), 0, 0).toDouble(&ok);
        if (ok) {
            sysSec = static_cast<qint64>(value);
        }
    }
    const QString app = formatDuration(appSec);
    const QString sys = formatDuration(sysSec);
    if (app != appUptime_ || sys != systemUptime_) {
        appUptime_ = app;
        systemUptime_ = sys;
        emit uptimeChanged();
    }
}

} // namespace opencruise
