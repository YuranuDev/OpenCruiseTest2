#include "BootManager.h"

#include <QMetaObject>
#include <QThread>
#include <utility>

#include "core/Log.h"

namespace opencruise {

BootManager::BootManager(QObject *parent) : QAbstractListModel(parent) {
    tick_.setInterval(100);
    connect(&tick_, &QTimer::timeout, this, &BootManager::onTick);
}

void BootManager::addStep(const QString &id, const QString &title, bool required, int timeoutMs) {
    if (indexOf(id) >= 0) {
        return;
    }
    Step s;
    s.id = id;
    s.title = title;
    s.required = required;
    s.timeoutMs = timeoutMs;
    if (phase_ == Active) {
        s.state = Running;
        s.deadlineMs = timeoutMs > 0 ? elapsed() + timeoutMs : -1;
    }
    beginInsertRows(QModelIndex(), steps_.size(), steps_.size());
    steps_.append(s);
    endInsertRows();
    emit changed();
}

void BootManager::setTiming(int minDisplayMs, int problemHoldMs, int maxMs) {
    minDisplayMs_ = minDisplayMs;
    problemHoldMs_ = problemHoldMs;
    maxMs_ = maxMs;
}

void BootManager::start() {
    if (phase_ != Idle) {
        return;
    }
    phase_ = Active;
    clock_.start();
    for (int i = 0; i < steps_.size(); ++i) {
        Step &s = steps_[i];
        if (s.state == Pending) {
            s.state = Running;
        }
        // 開始前に確定済みのステップを除き、時間切れの期限を数え始める
        s.deadlineMs = (s.state == Running && s.timeoutMs > 0) ? s.timeoutMs : -1;
    }
    if (!steps_.isEmpty()) {
        emit dataChanged(index(0), index(steps_.size() - 1));
    }
    tick_.start();
    opencruise::log::info("BOOT", QStringLiteral("boot wait started (%1 steps)").arg(steps_.size()));
    emit phaseChanged();
    emit changed();
    evaluate();
}

void BootManager::report(const QString &id, int state, const QString &detail, const QString &logDetail) {
    // 機器との通信スレッドなど、別スレッドからの通知は本体のスレッドへ渡す
    if (QThread::currentThread() != thread()) {
        QMetaObject::invokeMethod(
            this, [this, id, state, detail, logDetail]() { report(id, state, detail, logDetail); }, Qt::QueuedConnection);
        return;
    }
    const int row = indexOf(id);
    if (row < 0) {
        opencruise::log::warn("BOOT", QStringLiteral("report for an unknown step: ") + id);
        return;
    }
    if (state < Pending || state > Skipped) {
        return;
    }
    Step &s = steps_[row];
    s.state = static_cast<StepState>(state);
    s.detail = detail;
    // 途中経過(Running)の通知は、応答があった印として期限を延ばす
    if (s.state == Running && s.timeoutMs > 0 && phase_ == Active) {
        s.deadlineMs = elapsed() + s.timeoutMs;
    }
    // ログは英語: logDetail を使う。無ければ、detail が英数字だけのときだけ出す(日本語の補足は画面だけ)
    bool asciiDetail = true;
    for (const QChar c : detail) {
        if (c.unicode() > 0x7e) { asciiDetail = false; break; }
    }
    const QString forLog = !logDetail.isEmpty() ? logDetail : (asciiDetail ? detail : QString());
    opencruise::log::info("BOOT", QStringLiteral("%1: %2 %3").arg(id, keyFor(s.state), forLog).trimmed());
    emit dataChanged(index(row), index(row));
    emit stepReported(id, state, detail);
    emit changed();
    evaluate();
}

void BootManager::skip() {
    if (phase_ == Active) {
        finish(true);
    }
}

void BootManager::release() {
    if (released_) {
        return;
    }
    released_ = true;
    opencruise::log::info("BOOT", QStringLiteral("splash and notice finished (starting the main screen)"));
    emit releasedChanged();
}

void BootManager::bypass() {
    if (phase_ == Done) {
        return;
    }
    phase_ = Done;
    tick_.stop();
    emit phaseChanged();
    emit changed();
    emit finished();
}

void BootManager::onTick() {
    const qint64 now = elapsed();
    for (int i = 0; i < steps_.size(); ++i) {
        Step &s = steps_[i];
        if (s.state == Running && s.deadlineMs >= 0 && now >= s.deadlineMs) {
            s.state = timeoutState(s);
            s.detail = QStringLiteral("応答がありません(時間切れ)");
            opencruise::log::warn("BOOT", QStringLiteral("%1: timed out").arg(s.id));
            emit dataChanged(index(i), index(i));
            emit stepReported(s.id, s.state, s.detail);
            emit changed();
        }
    }
    evaluate();
}

void BootManager::evaluate() {
    if (phase_ != Active) {
        return;
    }
    const qint64 now = elapsed();
    bool allSettled = true;
    for (const Step &s : std::as_const(steps_)) {
        if (!isSettled(s.state)) {
            allSettled = false;
            break;
        }
    }
    if (!allSettled) {
        settledAtMs_ = -1;
    } else if (settledAtMs_ < 0) {
        settledAtMs_ = now;
    }
    const bool timeUp = now >= maxMs_;
    const bool ready = allSettled && now >= minDisplayMs_ &&
                       now >= settledAtMs_ + (hasProblem() ? problemHoldMs_ : 0);
    if (ready || timeUp) {
        finish(false);
    }
}

void BootManager::finish(bool bySkip) {
    if (phase_ != Active) {
        return;
    }
    for (int i = 0; i < steps_.size(); ++i) {
        Step &s = steps_[i];
        if (isSettled(s.state)) {
            continue;
        }
        if (bySkip) {
            s.state = Skipped;
            s.detail = QStringLiteral("スキップしました");
        } else {
            s.state = timeoutState(s);
            s.detail = QStringLiteral("応答がありません(時間切れ)");
        }
        emit dataChanged(index(i), index(i));
        emit stepReported(s.id, s.state, s.detail);
    }
    phase_ = Done;
    tick_.stop();
    opencruise::log::info("BOOT", QStringLiteral("boot wait finished (%1 ms%2)")
                                      .arg(clock_.elapsed())
                                      .arg(bySkip ? QStringLiteral(", skipped") : QString()));
    emit phaseChanged();
    emit changed();
    emit finished();
}

qreal BootManager::progress() const {
    if (phase_ == Done || steps_.isEmpty()) {
        return 1.0;
    }
    int settled = 0;
    for (const Step &s : steps_) {
        if (isSettled(s.state)) {
            ++settled;
        }
    }
    return static_cast<qreal>(settled) / steps_.size();
}

bool BootManager::hasProblem() const {
    for (const Step &s : steps_) {
        if (s.state == Failed || s.state == Warning) {
            return true;
        }
    }
    return false;
}

QString BootManager::summaryText() const {
    if (phase_ == Done) {
        return hasProblem() ? QStringLiteral("一部の機器と接続できないまま起動します")
                            : QStringLiteral("準備が完了しました");
    }
    for (const Step &s : steps_) {
        if (s.state == Running) {
            // どの段階を読み込んでいるか(補足があれば添える)
            return s.detail.isEmpty() ? QStringLiteral("%1を準備しています…").arg(s.title)
                                      : QStringLiteral("%1を準備しています… %2").arg(s.title, s.detail);
        }
    }
    return QStringLiteral("起動しています…");
}

QString BootManager::keyFor(StepState s) {
    switch (s) {
    case Pending: return QStringLiteral("pending");
    case Running: return QStringLiteral("running");
    case Ready: return QStringLiteral("ready");
    case Warning: return QStringLiteral("warning");
    case Failed: return QStringLiteral("failed");
    case Skipped: return QStringLiteral("skipped");
    }
    return QStringLiteral("pending");
}

int BootManager::indexOf(const QString &id) const {
    for (int i = 0; i < steps_.size(); ++i) {
        if (steps_[i].id == id) {
            return i;
        }
    }
    return -1;
}

int BootManager::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : static_cast<int>(steps_.size());
}

QVariant BootManager::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= steps_.size()) {
        return {};
    }
    const Step &s = steps_[index.row()];
    switch (role) {
    case StepIdRole: return s.id;
    case TitleRole: return s.title;
    case DetailRole: return s.detail;
    case StateKeyRole: return keyFor(s.state);
    case RequiredRole: return s.required;
    default: return {};
    }
}

QHash<int, QByteArray> BootManager::roleNames() const {
    return {{StepIdRole, "stepId"},
            {TitleRole, "title"},
            {DetailRole, "detail"},
            {StateKeyRole, "stateKey"},
            {RequiredRole, "required"}};
}

} // namespace opencruise
