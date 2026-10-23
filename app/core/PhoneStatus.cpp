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
    mockStampMs_ = QDateTime::currentMSecsSinceEpoch();
    emit mockEnabledChanged();
    emit changed();
    emit callChanged();
    emit mediaChanged();
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
        // 通話・再生中の曲も同様に破棄する
        hasRealCall_ = false;
        realCallState_ = -1;
        realCallName_.clear();
        realCallNumber_.clear();
        realCallDurationSec_ = 0;
        hasRealTrack_ = false;
        hasRealPlayback_ = false;
        realSong_.clear();
        realArtist_.clear();
        realAlbum_.clear();
        realSource_.clear();
        realDurationSec_ = realPositionSec_ = 0;
        realPlaybackState_ = 1;
        emit callChanged();
        emit mediaChanged();
    }
    emit changed();
}

QString PhoneStatus::callState() const {
    if (hasRealCall_) {
        switch (realCallState_) {
        case 4: return QStringLiteral("incoming");
        case 1:
        case 5:
        case 6: return QStringLiteral("active");
        case 2: return QStringLiteral("hold");
        default: return QStringLiteral("none"); // 不明・待機・通話なし
        }
    }
    if (!mockEnabled_) {
        return QStringLiteral("none");
    }
    const int phase = mockCallPhase();
    return phase < 20 ? QStringLiteral("none") : (phase < 26 ? QStringLiteral("incoming") : QStringLiteral("active"));
}

int PhoneStatus::callDurationSec() const {
    if (hasRealCall_) {
        // スマホが通知した通話時間に、受け取ってからの経過を足す(通話中のみ)
        const qint64 extra = realCallState_ == 1 ? (QDateTime::currentMSecsSinceEpoch() - realCallStampMs_) / 1000 : 0;
        return realCallDurationSec_ + static_cast<int>(std::max<qint64>(0, extra));
    }
    return (mockEnabled_ && mockCallPhase() >= 26) ? mockCallPhase() - 26 : 0;
}

QString PhoneStatus::playbackState() const {
    if (hasRealPlayback_) {
        switch (realPlaybackState_) {
        case 2: return QStringLiteral("playing");
        case 3: return QStringLiteral("paused");
        default: return QStringLiteral("stopped");
        }
    }
    return mockEnabled_ ? QStringLiteral("playing") : QStringLiteral("stopped");
}

QString PhoneStatus::mockSong() const {
    static const QStringList kSongs = {QStringLiteral("Midnight Drive"), QStringLiteral("Coastal Road"),
                                       QStringLiteral("City Lights")};
    return kSongs.at(mockTrackIndex());
}
QString PhoneStatus::mockArtist() const {
    static const QStringList kArtists = {QStringLiteral("サンプル アーティスト"), QStringLiteral("テスト バンド"),
                                         QStringLiteral("デモ ユニット")};
    return kArtists.at(mockTrackIndex());
}
QString PhoneStatus::mockAlbum() const {
    static const QStringList kAlbums = {QStringLiteral("ドライブ ミックス"), QStringLiteral("ロード トリップ"),
                                        QStringLiteral("ナイト クルーズ")};
    return kAlbums.at(mockTrackIndex());
}

void PhoneStatus::setCall(int state, const QString &name, const QString &number, int durationSec) {
    hasRealCall_ = true; // 通話なし(state < 0)も「スマホから届いた実データ」として扱い、モックを出さない
    realCallState_ = state;
    realCallName_ = name;
    realCallNumber_ = number;
    realCallDurationSec_ = durationSec;
    realCallStampMs_ = QDateTime::currentMSecsSinceEpoch();
    emit callChanged();
}

void PhoneStatus::setTrack(const QString &song, const QString &artist, const QString &album, int durationSec) {
    hasRealTrack_ = true;
    realSong_ = song;
    realArtist_ = artist;
    realAlbum_ = album;
    realDurationSec_ = durationSec;
    emit mediaChanged();
}

void PhoneStatus::setPlayback(int state, const QString &source, int positionSec) {
    hasRealPlayback_ = true;
    realPlaybackState_ = state;
    realSource_ = source;
    realPositionSec_ = positionSec;
    realStampMs_ = QDateTime::currentMSecsSinceEpoch();
    emit mediaChanged();
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
    // モックの通話: 状態の切り替わり(着信 → 通話中 → 終了)と、通話中の秒数の更新で通知する
    if (mockEnabled_ && !hasRealCall_ && (mockCallPhase() == 0 || mockCallPhase() == 20 || mockCallPhase() >= 26)) {
        emit callChanged();
    }
    // モックの再生: 位置を 1 秒ずつ進め、曲の長さに達したら次の曲へ
    if (mockEnabled_ && !(hasRealTrack_ || hasRealPlayback_)) {
        if (++mockPositionSec_ >= kMockTrackSec) {
            mockPositionSec_ = 0;
            ++mockTrackCount_;
        }
        mockStampMs_ = QDateTime::currentMSecsSinceEpoch();
        emit mediaChanged();
    }
    if (mockTick_ % 25 == 0) { // 25 秒ごとにテスト通知
        injectMockNotice();
    }
}

} // namespace opencruise
