/**
 * @file PhoneStatus.h
 * @brief スマートフォン(Android Auto 経由)の状態と通知を保持するモデル。ウィジェットから読む。
 *
 * QML へは context property `phoneStatus` として公開する。
 *
 * 【実データで取れるもの(aasdk_phone_data.csv より)】
 *  - バッテリー残量・残り時間・危険フラグ: Control チャネルの BatteryStatusNotification。
 *    サービス宣言なしで届くため、AasdkSession が setBattery() へ渡す。
 *  - 電波強度(PhoneStatus.signal_strength)・汎用通知(GenericNotificationMessage の id/text/icon):
 *    いずれも現状は ServiceDiscovery で宣言しておらず届かない(not_declared)。→ モックで代替する。
 *    宣言したときは setSignal() / ingestNotice() を呼ぶだけでモックから実データへ切り替わる。
 *  - 取れないもの: 通知の送信元アプリ名・本文・連絡先(プロトコルに無い)。
 *    通知のカテゴリは text の内容から推定する(classify)。
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

    /** @brief モックの通知を 1 件出す(ウィジェット設定の「テスト通知」用)。 */
    Q_INVOKABLE void injectMockNotice();

    /** @brief 通知文からカテゴリ(call / message / navigation / other)を推定する。 */
    static QString classify(const QString &text);

signals:
    void mockEnabledChanged();
    void changed();
    void noticesChanged();
    /** @brief 通知が 1 件届いた(実・モックとも)。ウィジェットのポップアップ表示などに使う */
    void noticeReceived(const QVariantMap &notice);

private:
    void tickMock();
    int mockRemainingSec() const { return mockLevel_ * 60 * 4; }
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

    int mockLevel_ = 78;
    int mockSignal_ = 3;
    int mockTick_ = 0;
    int mockNoticeIndex_ = 0;
    QTimer mockTimer_;
    QVariantList notices_;
};

} // namespace opencruise
