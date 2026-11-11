/**
 * @file ShutdownManager.cpp
 * @brief 車両の終了(ACC OFF)に合わせた、アプリ主導のシャットダウンの実装。
 */
#include "ShutdownManager.h"

#include "core/Log.h"

#include <QCoreApplication>
#include <QFile>
#include <QPointer>
#include <QProcess>
#include <QSettings>
#include <QUrl>
#include <QVariantMap>

#include <algorithm>

namespace opencruise {

namespace {
QSettings openStore() {
    return QSettings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"), QStringLiteral("OpenCruise"));
}
// Plymouth のテーマの画像(scripts/bootsplash/install.sh が入れる。main.cpp の終了画面と同じ)
const char *kPlymouthImage = "/usr/share/plymouth/themes/opencruise/background.png";
} // namespace

ShutdownManager::ShutdownManager(QObject *parent) : QObject(parent) {
    const QSettings store = openStore();
    afterAction_ = std::clamp(store.value(QStringLiteral("power/afterShutdown"), 0).toInt(), 0, 1);
    timeoutSec_ = std::clamp(store.value(QStringLiteral("power/shutdownTimeoutSec"), 20).toInt(), 5, 60);

    taskTimer_.setSingleShot(true);
    connect(&taskTimer_, &QTimer::timeout, this, [this]() { completeCurrent(serial_, false, QString(), true); });
    overallTimer_.setSingleShot(true);
    connect(&overallTimer_, &QTimer::timeout, this, [this]() {
        if (state_ != QStringLiteral("preparing")) return;
        log::warn("SHUTDOWN", QStringLiteral("overall time limit (%1 s) reached; skipping the remaining tasks").arg(timeoutSec_));
        taskTimer_.stop();
        ++serial_;   // 今の処理の完了の知らせは、もう受け付けない
        for (Entry &e : entries_) {
            if (e.status == QStringLiteral("running")) e.status = QStringLiteral("timeout");
            else if (e.status == QStringLiteral("waiting")) e.status = QStringLiteral("skipped");
        }
        emit tasksChanged();
        allDone();
    });
}

void ShutdownManager::addTask(const QString &id, const QString &label, Task task, int timeoutMs) {
    Entry e;
    e.id = id;
    e.label = label;
    e.task = std::move(task);
    e.timeoutMs = std::max(100, timeoutMs);
    entries_.append(e);
    emit tasksChanged();
}

QVariantList ShutdownManager::tasks() const {
    QVariantList list;
    for (const Entry &e : entries_) {
        list.append(QVariantMap{{QStringLiteral("id"), e.id}, {QStringLiteral("label"), e.label},
                                {QStringLiteral("status"), e.status}, {QStringLiteral("detail"), e.detail}});
    }
    return list;
}

void ShutdownManager::setAfterAction(int action) {
    action = std::clamp(action, 0, 1);
    if (action == afterAction_) return;
    afterAction_ = action;
    openStore().setValue(QStringLiteral("power/afterShutdown"), afterAction_);
    log::info("SHUTDOWN", QStringLiteral("after the tasks: %1").arg(action == 0 ? QStringLiteral("power off the PC") : QStringLiteral("quit the app only")));
    emit settingsChanged();
}

void ShutdownManager::setTimeoutSec(int seconds) {
    seconds = std::clamp(seconds, 5, 60);
    if (seconds == timeoutSec_) return;
    timeoutSec_ = seconds;
    openStore().setValue(QStringLiteral("power/shutdownTimeoutSec"), timeoutSec_);
    emit settingsChanged();
}

QString ShutdownManager::screenImageUrl() const {
    const QString path = QString::fromLatin1(kPlymouthImage);
    return QFile::exists(path) ? QUrl::fromLocalFile(path).toString() : QString();
}

void ShutdownManager::setState(const QString &state) {
    if (state == state_) return;
    state_ = state;
    emit stateChanged();
}

void ShutdownManager::requestShutdown(const QString &reason) {
    if (state_ != QStringLiteral("idle")) {
        log::info("SHUTDOWN", QStringLiteral("shutdown already in progress (%1); request ignored: %2").arg(state_, reason));
        return;
    }
    reason_ = reason;
    errorText_.clear();
    for (Entry &e : entries_) {
        e.status = QStringLiteral("waiting");
        e.detail.clear();
    }
    log::info("SHUTDOWN", QStringLiteral("shutdown requested (%1); running %2 tasks (limit %3 s, then %4)")
                              .arg(reason).arg(entries_.size()).arg(timeoutSec_)
                              .arg(afterAction_ == 0 ? QStringLiteral("power off") : QStringLiteral("quit the app")));
    elapsed_.start();
    setState(QStringLiteral("preparing"));
    emit tasksChanged();
    overallTimer_.start(timeoutSec_ * 1000);
    current_ = -1;
    // 画面の切り替え(終了の準備の画面)を先に描かせてから、処理を始める
    QTimer::singleShot(150, this, [this]() { runNext(); });
}

void ShutdownManager::runNext() {
    if (state_ != QStringLiteral("preparing")) return;
    ++current_;
    if (current_ >= entries_.size()) {
        allDone();
        return;
    }
    Entry &e = entries_[current_];
    e.status = QStringLiteral("running");
    emit tasksChanged();
    log::info("SHUTDOWN", QStringLiteral("task started: %1").arg(e.id));
    const int serial = ++serial_;
    taskTimer_.start(e.timeoutMs);
    QPointer<ShutdownManager> self(this);
    // 完了の知らせは、どのスレッドから来てもこのスレッドで受ける
    Done done = [self, serial](bool ok, const QString &detail) {
        if (!self) return;
        QMetaObject::invokeMethod(self.data(), [self, serial, ok, detail]() {
            if (self) self->completeCurrent(serial, ok, detail, false);
        }, Qt::QueuedConnection);
    };
    try {
        e.task(done);
    } catch (...) {
        done(false, QStringLiteral("exception"));
    }
}

void ShutdownManager::completeCurrent(int serial, bool ok, const QString &detail, bool timedOut) {
    if (serial != serial_ || current_ < 0 || current_ >= entries_.size() || state_ != QStringLiteral("preparing")) return;
    taskTimer_.stop();
    ++serial_;
    Entry &e = entries_[current_];
    if (timedOut) {
        e.status = QStringLiteral("timeout");
        log::warn("SHUTDOWN", QStringLiteral("task timed out after %1 ms: %2").arg(e.timeoutMs).arg(e.id));
    } else if (ok) {
        // 「やることが無かった」ときは、detail を "skip:<理由>" にすると「スキップ」として出す
        if (detail.startsWith(QStringLiteral("skip:"))) {
            e.status = QStringLiteral("skipped");
            e.detail = detail.mid(5);
        } else {
            e.status = QStringLiteral("done");
            e.detail = detail;
        }
        log::info("SHUTDOWN", QStringLiteral("task %1: %2%3").arg(e.status, e.id, e.detail.isEmpty() ? QString() : QStringLiteral(" (") + e.detail + QLatin1Char(')')));
    } else {
        e.status = QStringLiteral("failed");
        e.detail = detail;
        log::warn("SHUTDOWN", QStringLiteral("task failed: %1 (%2)").arg(e.id, detail));
    }
    emit tasksChanged();
    QTimer::singleShot(0, this, [this]() { runNext(); });
}

void ShutdownManager::allDone() {
    overallTimer_.stop();
    log::info("SHUTDOWN", QStringLiteral("all tasks finished in %1 ms; fading out the shutdown screen").arg(elapsed_.elapsed()));
    setState(QStringLiteral("ready"));   // QML が終了の画面をフェードアウトし、描き終えたら finish() を呼ぶ
}

void ShutdownManager::finish() {
    if (state_ != QStringLiteral("ready") || finished_) return;
    finished_ = true;
    if (afterAction_ == 1) {
        log::info("SHUTDOWN", QStringLiteral("quitting the app (power off is disabled in the settings)"));
        setState(QStringLiteral("stopping"));
        QCoreApplication::quit();
        return;
    }
    // PC の電源を切る。自動起動のサービスはログインのセッション(PAMName=login)として動くので、root でなくても
    // logind が許可する。systemd がアプリへ SIGTERM を送り、アプリは(もう出している)終了画面のまま終わる
    log::info("SHUTDOWN", QStringLiteral("powering off: systemctl poweroff"));
    setState(QStringLiteral("stopping"));
    auto *p = new QProcess(this);
    connect(p, &QProcess::finished, this, [this, p](int code, QProcess::ExitStatus status) {
        const QString err = QString::fromLocal8Bit(p->readAllStandardError()).trimmed();
        p->deleteLater();
        if (status == QProcess::NormalExit && code == 0) return;   // あとは SIGTERM で終わる
        errorText_ = err.isEmpty() ? QStringLiteral("systemctl poweroff exited with code %1").arg(code) : err;
        log::error("SHUTDOWN", QStringLiteral("could not power off: %1; quitting the app instead").arg(errorText_));
        setState(QStringLiteral("failed"));
        QTimer::singleShot(8000, qApp, []() { QCoreApplication::quit(); });
    });
    connect(p, &QProcess::errorOccurred, this, [this, p](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart) return;
        errorText_ = QStringLiteral("cannot run systemctl");
        log::error("SHUTDOWN", QStringLiteral("could not power off: %1; quitting the app instead").arg(errorText_));
        p->deleteLater();
        setState(QStringLiteral("failed"));
        QTimer::singleShot(8000, qApp, []() { QCoreApplication::quit(); });
    });
    p->start(QStringLiteral("systemctl"), {QStringLiteral("poweroff")});
}

} // namespace opencruise
