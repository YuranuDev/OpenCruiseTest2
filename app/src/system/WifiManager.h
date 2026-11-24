/**
 * @file WifiManager.h
 * @brief Wi-Fi の接続(設定 > システム > ネットワーク)。NetworkManager の nmcli を使う。
 *
 * アプリのユーザーが Wi-Fi を操作できるのは、polkit のルール(50-opencruise.rules)で許可しているため。
 * 一覧の更新は、設定画面を開いている間だけ(active)8 秒ごとに行う(電波の強さ・接続の状態)。
 * nmcli が無い(NetworkManager の無い開発 PC など)ときは available が false になり、画面は「使えません」と出す。
 * パスワードはログに出さない。
 */
#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVariantList>

#include <functional>

namespace opencruise {

class WifiManager : public QObject {
    Q_OBJECT
    /// Wi-Fi を操作できるか(nmcli があり、Wi-Fi の機器がある)
    Q_PROPERTY(bool available READ available NOTIFY changed)
    /// Wi-Fi がオンか
    Q_PROPERTY(bool enabled READ enabled NOTIFY changed)
    /// 操作中(接続・切断・探している)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    /// 最後の操作の結果の文(エラーなど)
    Q_PROPERTY(QString message READ message NOTIFY changed)
    /// つながっている Wi-Fi の名前(無ければ空)と、IP アドレス
    Q_PROPERTY(QString connectedSsid READ connectedSsid NOTIFY changed)
    Q_PROPERTY(QString ipAddress READ ipAddress NOTIFY changed)
    /// 見えている Wi-Fi: [{ ssid, signal(0〜100), secure, active, saved }](つながっているもの → 保存済み → 強い順)
    Q_PROPERTY(QVariantList networks READ networks NOTIFY changed)
    /// 設定画面を開いている間 true にする(定期的に一覧を更新する)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)

public:
    explicit WifiManager(QObject *parent = nullptr);

    bool available() const { return available_; }
    bool enabled() const { return enabled_; }
    bool busy() const { return busy_; }
    QString message() const { return message_; }
    QString connectedSsid() const { return connectedSsid_; }
    QString ipAddress() const { return ipAddress_; }
    QVariantList networks() const { return networks_; }
    bool active() const { return active_; }
    void setActive(bool on);

    /// 一覧を更新する(rescan: 周りを探し直す)
    Q_INVOKABLE void refresh(bool rescan = false);
    /// つなぐ。保存済みならパスワードは要らない。パスワードの要らない Wi-Fi は空でよい
    Q_INVOKABLE void connectTo(const QString &ssid, const QString &password = QString());
    Q_INVOKABLE void disconnectWifi();
    /// 保存したパスワードを消す
    Q_INVOKABLE void forget(const QString &ssid);
    Q_INVOKABLE void setEnabled(bool on);

    /// nmcli -t の 1 行を、エスケープ(\: と \\)を考えて区切る
    static QStringList splitTerse(const QString &line);

signals:
    void changed();
    void activeChanged();

private:
    using Done = std::function<void(bool ok, const QString &out, const QString &err)>;
    void nmcli(const QStringList &args, Done done, int timeoutMs = 15000);
    void finishAction(bool ok, const QString &okMessage, const QString &err);

    bool available_ = false;
    bool enabled_ = false;
    bool busy_ = false;
    bool refreshing_ = false;
    QString message_;
    QString device_;
    QString connectedSsid_;
    QString ipAddress_;
    QVariantList networks_;
    bool active_ = false;
    QTimer poll_;
};

} // namespace opencruise
