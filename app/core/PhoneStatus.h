/**
 * @file PhoneStatus.h
 * @brief スマートフォン(Android Auto 経由)の状態と通知を保持するモデル。ウィジェットから読む。
 *
 * QML へは context property `phoneStatus` として公開する。
 *
 * 【実データで取れるもの(aasdk_phone_data.csv より)】
 *  - バッテリー残量・残り時間・危険フラグ: Control チャネルの BatteryStatusNotification。
 *    サービス宣言なしで届くため、AasdkSession が setBattery() へ渡す。
 *  - 電波強度(PhoneStatus.signal_strength)・汎用通知(GenericNotificationMessage の id/text/icon)・通話状態・再生中の曲:
 *    ServiceDiscovery で宣言し(AasdkPhoneHandler)、届いた値を setSignal() / ingestNotice() / setCall() / setTrack() /
 *    setPlayback() で反映する。スマホが送ってこない間は、モックが ON ならモックの値を出す(*IsMock で区別できる)。
 *    ※ 実機での動作確認は未実施(スマホによっては、これらを送らない場合がある)。
 *  - 取れないもの: 通知の送信元アプリ名・本文・連絡先(プロトコルに無い)。
 *    通知のカテゴリは text の内容から推定する(classify)。
 *  - 通話状態(PhoneStatus.calls)・再生中の曲(MediaPlaybackStatus チャネル): setCall() / setTrack() / setPlayback() で反映する。
 *
 * モックは mockEnabled が ON の間だけ、実データが無い項目に対して動く。値には出所(*IsMock)が付く。
 */
#pragma once

#include <QObject>
#include <QSettings>
#include <QString>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

namespace opencruise {

class PhoneStatus : public QObject {
    Q_OBJECT
    /** モックデータの使用(実データが無い項目だけ。設定は保存される) */
    Q_PROPERTY(bool mockEnabled READ mockEnabled WRITE setMockEnabled NOTIFY mockEnabledChanged)
    /** Android Auto でスマートフォンと接続が確立しているか */
    Q_PROPERTY(bool connected READ connected NOTIFY changed)
    /** バッテリー残量[%]。-1 は不明 */
    Q_PROPERTY(int batteryLevel READ batteryLevel NOTIFY changed)
    /** バッテリー残り時間[秒]。-1 は不明 */
    Q_PROPERTY(int batteryRemainingSec READ batteryRemainingSec NOTIFY changed)
    Q_PROPERTY(bool batteryCritical READ batteryCritical NOTIFY changed)
    Q_PROPERTY(bool batteryIsMock READ batteryIsMock NOTIFY changed)
    /** 電波強度 0〜4。-1 は不明 */
    Q_PROPERTY(int signalStrength READ signalStrength NOTIFY changed)
    Q_PROPERTY(bool signalIsMock READ signalIsMock NOTIFY changed)
    /** 最近の通知(新しい順、最大 20 件)。各要素: {id,text,icon,category,time,mock} */
    Q_PROPERTY(QVariantList recentNotices READ recentNotices NOTIFY noticesChanged)
    /** 通話の状態: "none"(通話なし) / "incoming"(着信) / "active"(通話中) / "hold"(保留) */
    Q_PROPERTY(QString callState READ callState NOTIFY callChanged)
    /** 通話相手の名前(無ければ空)と電話番号(無ければ空)、通話時間[秒] */
    Q_PROPERTY(QString callName READ callName NOTIFY callChanged)
    Q_PROPERTY(QString callNumber READ callNumber NOTIFY callChanged)
    Q_PROPERTY(int callDurationSec READ callDurationSec NOTIFY callChanged)
    Q_PROPERTY(bool callIsMock READ callIsMock NOTIFY callChanged)
    /** 再生中の曲。曲が無い(不明)ときは hasTrack が false */
    Q_PROPERTY(bool hasTrack READ hasTrack NOTIFY mediaChanged)
    Q_PROPERTY(QString trackSong READ trackSong NOTIFY mediaChanged)
    Q_PROPERTY(QString trackArtist READ trackArtist NOTIFY mediaChanged)
    Q_PROPERTY(QString trackAlbum READ trackAlbum NOTIFY mediaChanged)
    /** 曲の長さ[秒]。不明なら 0 */
    Q_PROPERTY(int trackDurationSec READ trackDurationSec NOTIFY mediaChanged)
    /** 再生状態: "stopped" / "playing" / "paused" */
    Q_PROPERTY(QString playbackState READ playbackState NOTIFY mediaChanged)
    /** 再生元アプリ名(無ければ空) */
    Q_PROPERTY(QString playbackSource READ playbackSource NOTIFY mediaChanged)
    /** 再生位置[秒]と、その値を受け取った時刻(エポックミリ秒)。再生中は QML 側で経過時間を足して表示する */
    Q_PROPERTY(int playbackPositionSec READ playbackPositionSec NOTIFY mediaChanged)
    Q_PROPERTY(qint64 playbackStampMs READ playbackStampMs NOTIFY mediaChanged)
    Q_PROPERTY(bool mediaIsMock READ mediaIsMock NOTIFY mediaChanged)

public:
    explicit PhoneStatus(QObject *parent = nullptr);

    bool mockEnabled() const { return mockEnabled_; }
    void setMockEnabled(bool enabled);

    bool connected() const { return connected_; }
    int batteryLevel() const { return hasRealBattery_ ? realLevel_ : (mockEnabled_ ? mockLevel_ : -1); }
    int batteryRemainingSec() const { return hasRealBattery_ ? realRemainingSec_ : (mockEnabled_ ? mockRemainingSec() : -1); }
    bool batteryCritical() const { return hasRealBattery_ ? realCritical_ : (mockEnabled_ && mockLevel_ <= 5); }
    bool batteryIsMock() const { return !hasRealBattery_ && mockEnabled_; }
    int signalStrength() const { return hasRealSignal_ ? realSignal_ : (mockEnabled_ ? mockSignal_ : -1); }
    bool signalIsMock() const { return !hasRealSignal_ && mockEnabled_; }
    QVariantList recentNotices() const { return notices_; }

    QString callState() const;
    QString callName() const { return hasRealCall_ ? realCallName_ : (mockEnabled_ ? mockCallName() : QString()); }
    QString callNumber() const { return hasRealCall_ ? realCallNumber_ : QString(); }
    int callDurationSec() const;
    bool callIsMock() const { return !hasRealCall_ && mockEnabled_; }

    bool hasTrack() const { return hasRealTrack_ ? !realSong_.isEmpty() : mockEnabled_; }
    QString trackSong() const { return hasRealTrack_ ? realSong_ : (mockEnabled_ ? mockSong() : QString()); }
    QString trackArtist() const { return hasRealTrack_ ? realArtist_ : (mockEnabled_ ? mockArtist() : QString()); }
    QString trackAlbum() const { return hasRealTrack_ ? realAlbum_ : (mockEnabled_ ? mockAlbum() : QString()); }
    int trackDurationSec() const { return hasRealTrack_ ? realDurationSec_ : (mockEnabled_ ? kMockTrackSec : 0); }
    QString playbackState() const;
    QString playbackSource() const { return hasRealPlayback_ ? realSource_ : (mockEnabled_ ? QStringLiteral("モック再生") : QString()); }
    int playbackPositionSec() const { return hasRealPlayback_ ? realPositionSec_ : (mockEnabled_ ? mockPositionSec_ : 0); }
    qint64 playbackStampMs() const { return hasRealPlayback_ ? realStampMs_ : mockStampMs_; }
    bool mediaIsMock() const { return !(hasRealTrack_ || hasRealPlayback_) && mockEnabled_; }

    /** @brief 接続状態を更新する。切断(false)になったら実データ(バッテリー・電波)を破棄する。 */
    void setConnected(bool connected);
    /** @brief スマホのバッテリー通知を反映する(UI スレッドで呼ぶ)。残り時間が不明なら -1。 */
    void setBattery(int level, int remainingSec, bool critical);
    /** @brief スマホの電波強度を反映する(PhoneStatus サービスを宣言したときに使う。0〜4 に丸める)。 */
    void setSignal(int strength);
    /**
     * @brief スマホの汎用通知を取り込む(GenericNotification サービスを宣言したときに使う)。
     * @param id 通知 ID(同じ ID は上書き)
     * @param text 通知文(プロトコル上、送信元アプリ名・本文は無い)
     * @param icon Material Icons 名。空ならカテゴリ別の既定
     */
    void ingestNotice(const QString &id, const QString &text, const QString &icon = QString());

    /**
     * @brief スマホの通話状態を反映する(PhoneStatus サービスの calls。UI スレッドで呼ぶ)。
     * @param state PhoneStatus.State の値(0=不明 1=通話中 2=保留 3=待機 4=着信 5=会議 6=ミュート)。通話が無ければ -1
     */
    void setCall(int state, const QString &name, const QString &number, int durationSec);
    /** @brief 再生中の曲の情報を反映する(MediaPlaybackStatus チャネルのメタデータ)。 */
    void setTrack(const QString &song, const QString &artist, const QString &album, int durationSec);
    /** @brief 再生状態を反映する。state は 1=停止 2=再生中 3=一時停止、positionSec は再生位置[秒]。 */
    void setPlayback(int state, const QString &source, int positionSec);

    /** @brief モックの通知を 1 件出す(ウィジェット設定の「テスト通知」用)。 */
    Q_INVOKABLE void injectMockNotice();

    /** @brief 通知文からカテゴリ(call / message / navigation / other)を推定する。 */
    static QString classify(const QString &text);

signals:
    void mockEnabledChanged();
    void changed();
    void noticesChanged();
    /** @brief 通話状態(callXxx)が変わったとき */
    void callChanged();
    /** @brief 再生中の曲・再生状態(trackXxx / playbackXxx)が変わったとき */
    void mediaChanged();
    /** @brief 通知が 1 件届いた(実・モックとも)。ウィジェットのポップアップ表示などに使う */
    void noticeReceived(const QVariantMap &notice);

private:
    void tickMock();
    int mockRemainingSec() const { return mockLevel_ * 60 * 4; }
    // モックの通話は 40 秒周期(0〜19 秒: 通話なし / 20〜25: 着信 / 26〜39: 通話中)
    int mockCallPhase() const { return mockTick_ % kMockCallCycleSec; }
    QString mockCallName() const { return QStringLiteral("田中さん"); }
    // モックの曲は 3 曲を順に再生する(1 曲 kMockTrackSec 秒)
    int mockTrackIndex() const { return mockTrackCount_ % 3; }
    QString mockSong() const;
    QString mockArtist() const;
    QString mockAlbum() const;
    static constexpr int kMockCallCycleSec = 40;
    static constexpr int kMockTrackSec = 180;
    void addNotice(const QString &id, const QString &text, const QString &icon, bool mock);
    static QString defaultIcon(const QString &category);

    QSettings openStore() const;

    bool mockEnabled_ = true;
    bool connected_ = false;
    bool hasRealBattery_ = false;
    int realLevel_ = -1;
    int realRemainingSec_ = -1;
    bool realCritical_ = false;
    bool hasRealSignal_ = false;
    int realSignal_ = -1;

    bool hasRealCall_ = false;
    int realCallState_ = -1;
    QString realCallName_;
    QString realCallNumber_;
    int realCallDurationSec_ = 0;
    qint64 realCallStampMs_ = 0;

    bool hasRealTrack_ = false;
    QString realSong_;
    QString realArtist_;
    QString realAlbum_;
    int realDurationSec_ = 0;
    bool hasRealPlayback_ = false;
    int realPlaybackState_ = 1;
    QString realSource_;
    int realPositionSec_ = 0;
    qint64 realStampMs_ = 0;

    int mockPositionSec_ = 0;
    qint64 mockStampMs_ = 0;
    int mockTrackCount_ = 0;

    int mockLevel_ = 78;
    int mockSignal_ = 3;
    int mockTick_ = 0;
    int mockNoticeIndex_ = 0;
    QTimer mockTimer_;
    QVariantList notices_;
};

} // namespace opencruise
