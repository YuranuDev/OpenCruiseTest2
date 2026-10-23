/**
 * @file PhoneStatus.cpp
 * @brief PhoneStatus の実装。
 */
#include "PhoneStatus.h"

#include <QDateTime>
#include <QStringList>

#include <algorithm>

namespace opencruise {

namespace {

constexpr int kMaxNotices = 20;
constexpr int kMockTickMs = 1000;

/// モック通知の文(順番に出す)。プロトコル上は送信元アプリ名・本文が無いので、短い 1 文だけにしている
const QStringList kMockTexts = {
    QStringLiteral("山田さんからメッセージ"),
    QStringLiteral("着信: 田中さん"),
    QStringLiteral("次の交差点を右折です"),
    QStringLiteral("カレンダー: 15:00 打ち合わせ"),
    QStringLiteral("新着メールがあります"),
};

} // namespace

QSettings PhoneStatus::openStore() const {
    return QSettings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"),
                     QStringLiteral("OpenCruise"));
}

PhoneStatus::PhoneStatus(QObject *parent) : QObject(parent) {
    mockEnabled_ = openStore().value(QStringLiteral("phone/mock"), true).toBool();
    mockTimer_.setInterval(kMockTickMs);
    connect(&mockTimer_, &QTimer::timeout, this, &PhoneStatus::tickMock);
    if (mockEnabled_) {
        mockTimer_.start();
    }
}

void PhoneStatus::setMockEnabled(bool enabled) {
    if (mockEnabled_ == enabled) {
        return;
    }
    mockEnabled_ = enabled;
    openStore().setValue(QStringLiteral("phone/mock"), enabled);
    if (enabled) {
        mockTimer_.start();
    } else {
        mockTimer_.stop();
    }
    emit mockEnabledChanged();
    emit changed();
}

void PhoneStatus::setConnected(bool connected) {
    if (connected_ == connected) {
        return;
    }
    connected_ = connected;
    if (!connected) {
        // 切断したら、前回のスマホの実データは捨てる(別のスマホにつながったとき古い値を出さない)
        hasRealBattery_ = false;
        hasRealSignal_ = false;
        realLevel_ = realRemainingSec_ = realSignal_ = -1;
        realCritical_ = false;
    }
    emit changed();
}

void PhoneStatus::setBattery(int level, int remainingSec, bool critical) {
    hasRealBattery_ = true;
    realLevel_ = std::clamp(level, 0, 100);
    realRemainingSec_ = remainingSec;
    realCritical_ = critical;
    emit changed();
}

void PhoneStatus::setSignal(int strength) {
    hasRealSignal_ = true;
    realSignal_ = std::clamp(strength, 0, 4);
    emit changed();
}

void PhoneStatus::ingestNotice(const QString &id, const QString &text, const QString &icon) {
    addNotice(id, text, icon, false);
}

void PhoneStatus::injectMockNotice() {
    const QString text = kMockTexts.at(mockNoticeIndex_ % kMockTexts.size());
    ++mockNoticeIndex_;
    addNotice(QStringLiteral("mock-%1").arg(mockNoticeIndex_), text, QString(), true);
}

QString PhoneStatus::classify(const QString &text) {
    // 送信元アプリが分からないため、文面の語から推定する(推定できなければ other)
    if (text.contains(QStringLiteral("着信")) || text.contains(QStringLiteral("通話")) ||
        text.contains(QStringLiteral("不在"))) {
        return QStringLiteral("call");
    }
    if (text.contains(QStringLiteral("メッセージ")) || text.contains(QStringLiteral("メール")) ||
        text.contains(QStringLiteral("LINE"), Qt::CaseInsensitive)) {
        return QStringLiteral("message");
    }
    if (text.contains(QStringLiteral("右折")) || text.contains(QStringLiteral("左折")) ||
        text.contains(QStringLiteral("直進")) || text.contains(QStringLiteral("交差点")) ||
        text.contains(QStringLiteral("到着"))) {
        return QStringLiteral("navigation");
    }
    return QStringLiteral("other");
}

QString PhoneStatus::defaultIcon(const QString &category) {
    if (category == QLatin1String("call")) return QStringLiteral("call");
    if (category == QLatin1String("message")) return QStringLiteral("chat");
    if (category == QLatin1String("navigation")) return QStringLiteral("navigation");
    return QStringLiteral("notifications");
}

void PhoneStatus::addNotice(const QString &id, const QString &text, const QString &icon, bool mock) {
    const QString category = classify(text);
    QVariantMap notice;
    notice.insert(QStringLiteral("id"), id);
    notice.insert(QStringLiteral("text"), text);
    notice.insert(QStringLiteral("icon"), icon.isEmpty() ? defaultIcon(category) : icon);
    notice.insert(QStringLiteral("category"), category);
    notice.insert(QStringLiteral("time"), QDateTime::currentMSecsSinceEpoch());
    notice.insert(QStringLiteral("mock"), mock);

    for (int i = 0; i < notices_.size(); ++i) { // 同じ ID は置き換える
        if (notices_.at(i).toMap().value(QStringLiteral("id")).toString() == id) {
            notices_.removeAt(i);
            break;
        }
    }
    notices_.prepend(notice);
    while (notices_.size() > kMaxNotices) {
        notices_.removeLast();
    }
    emit noticesChanged();
    emit noticeReceived(notice);
}

void PhoneStatus::tickMock() {
    ++mockTick_;
    bool dirty = false;
    if (!hasRealBattery_ && mockTick_ % 30 == 0) { // 30 秒ごとに 1% 減る(0 になったら 78% に戻す)
        mockLevel_ = mockLevel_ > 1 ? mockLevel_ - 1 : 78;
        dirty = true;
    }
    if (!hasRealSignal_ && mockTick_ % 7 == 0) { // 電波は 2〜4 を行き来する
        mockSignal_ = 2 + (mockTick_ / 7) % 3;
        dirty = true;
    }
    if (dirty) {
        emit changed();
    }
    if (mockTick_ % 25 == 0) { // 25 秒ごとにテスト通知
        injectMockNotice();
    }
}

} // namespace opencruise
