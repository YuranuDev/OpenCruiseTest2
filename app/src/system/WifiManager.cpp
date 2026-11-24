/**
 * @file WifiManager.cpp
 * @brief Wi-Fi の接続(nmcli)の実装。
 */
#include "WifiManager.h"

#include "core/Log.h"

#include <QHash>
#include <QProcess>
#include <QSet>
#include <QStandardPaths>
#include <QVariantMap>

#include <algorithm>

namespace opencruise {

WifiManager::WifiManager(QObject *parent) : QObject(parent) {
    poll_.setInterval(8000);
    connect(&poll_, &QTimer::timeout, this, [this]() { refresh(false); });
    // 起動時に一度だけ状態を読む(画面の「Wi-Fi: 〇〇」の表示用)
    QTimer::singleShot(3000, this, [this]() { refresh(false); });
}

void WifiManager::setActive(bool on) {
    if (active_ == on) return;
    active_ = on;
    if (on) { refresh(true); poll_.start(); } else { poll_.stop(); }
    emit activeChanged();
}

QStringList WifiManager::splitTerse(const QString &line) {
    QStringList out;
    QString cur;
    for (int i = 0; i < line.size(); ++i) {
        const QChar c = line.at(i);
        if (c == QLatin1Char('\\') && i + 1 < line.size()) { cur += line.at(++i); continue; }
        if (c == QLatin1Char(':')) { out << cur; cur.clear(); continue; }
        cur += c;
    }
    out << cur;
    return out;
}

void WifiManager::nmcli(const QStringList &args, Done done, int timeoutMs) {
    auto *p = new QProcess(this);
    auto *timer = new QTimer(p);
    timer->setSingleShot(true);
    connect(timer, &QTimer::timeout, p, [p]() { p->kill(); });
    connect(p, &QProcess::finished, this, [p, done](int code, QProcess::ExitStatus st) {
        const QString out = QString::fromUtf8(p->readAllStandardOutput());
        const QString err = QString::fromUtf8(p->readAllStandardError()).trimmed();
        p->deleteLater();
        done(st == QProcess::NormalExit && code == 0, out, err);
    });
    connect(p, &QProcess::errorOccurred, this, [p, done](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart) return;
        p->deleteLater();
        done(false, QString(), QStringLiteral("nmcli を起動できません"));
    });
    // 文言を英語にそろえる(結果の読み取りのため)
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));
    p->setProcessEnvironment(env);
    p->start(QStringLiteral("nmcli"), args);
    timer->start(timeoutMs);
}

void WifiManager::refresh(bool rescan) {
    if (refreshing_) return;
    if (QStandardPaths::findExecutable(QStringLiteral("nmcli")).isEmpty()) {
        if (available_ || message_.isEmpty()) {
            available_ = false;
            message_ = QStringLiteral("NetworkManager(nmcli)がありません");
            emit changed();
        }
        return;
    }
    refreshing_ = true;
    // 1. Wi-Fi の機器と状態
    nmcli({ QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("DEVICE,TYPE,STATE,CONNECTION"), QStringLiteral("device") },
          [this, rescan](bool ok, const QString &out, const QString &) {
        QString dev, conn;
        bool connected = false;
        if (ok) {
            for (const QString &line : out.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                const QStringList f = splitTerse(line);
                if (f.size() < 4 || f.at(1) != QStringLiteral("wifi")) continue;
                dev = f.at(0);
                connected = f.at(2).startsWith(QStringLiteral("connected"));
                conn = connected ? f.at(3) : QString();
                break;
            }
        }
        if (dev.isEmpty()) {
            refreshing_ = false;
            available_ = false;
            networks_.clear();
            message_ = ok ? QStringLiteral("Wi-Fi の機器が見つかりません") : QStringLiteral("NetworkManager に接続できません");
            emit changed();
            return;
        }
        device_ = dev;
        available_ = true;
        // 2. オン/オフ
        nmcli({ QStringLiteral("-t"), QStringLiteral("radio"), QStringLiteral("wifi") },
              [this, rescan, connected, dev](bool, const QString &radio, const QString &) {
            enabled_ = radio.trimmed() == QStringLiteral("enabled");
            // 3. 保存済みの Wi-Fi
            nmcli({ QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("NAME,TYPE"), QStringLiteral("connection"), QStringLiteral("show") },
                  [this, rescan, connected, dev](bool, const QString &cons, const QString &) {
                QSet<QString> saved;
                for (const QString &line : cons.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                    const QStringList f = splitTerse(line);
                    if (f.size() >= 2 && f.at(1).contains(QStringLiteral("wireless"))) saved.insert(f.at(0));
                }
                // 4. 見えている Wi-Fi
                nmcli({ QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("IN-USE,SSID,SIGNAL,SECURITY"),
                        QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("list"),
                        QStringLiteral("--rescan"), rescan ? QStringLiteral("yes") : QStringLiteral("no") },
                      [this, saved, connected, dev](bool, const QString &list, const QString &) {
                    QHash<QString, QVariantMap> bySsid;   // 同じ名前(複数のアクセスポイント)は強いものだけ
                    QString activeSsid;
                    for (const QString &line : list.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                        const QStringList f = splitTerse(line);
                        if (f.size() < 4 || f.at(1).isEmpty()) continue;
                        const bool inUse = f.at(0).trimmed() == QStringLiteral("*");
                        const int signal = f.at(2).toInt();
                        const QString sec = f.at(3).trimmed();
                        if (inUse) activeSsid = f.at(1);
                        QVariantMap &n = bySsid[f.at(1)];
                        if (n.isEmpty() || inUse || signal > n.value(QStringLiteral("signal")).toInt()) {
                            n = { { QStringLiteral("ssid"), f.at(1) }, { QStringLiteral("signal"), signal },
                                  { QStringLiteral("secure"), !sec.isEmpty() && sec != QStringLiteral("--") },
                                  { QStringLiteral("active"), inUse || n.value(QStringLiteral("active")).toBool() },
                                  { QStringLiteral("saved"), saved.contains(f.at(1)) } };
                        }
                    }
                    QVariantList nets;
                    for (const QVariantMap &n : std::as_const(bySsid)) nets << n;
                    std::sort(nets.begin(), nets.end(), [](const QVariant &a, const QVariant &b) {
                        const QVariantMap x = a.toMap(), y = b.toMap();
                        const int rx = x.value(QStringLiteral("active")).toBool() ? 2 : x.value(QStringLiteral("saved")).toBool() ? 1 : 0;
                        const int ry = y.value(QStringLiteral("active")).toBool() ? 2 : y.value(QStringLiteral("saved")).toBool() ? 1 : 0;
                        if (rx != ry) return rx > ry;
                        return x.value(QStringLiteral("signal")).toInt() > y.value(QStringLiteral("signal")).toInt();
                    });
                    networks_ = nets;
                    connectedSsid_ = connected ? activeSsid : QString();
                    if (!connected) {
                        ipAddress_.clear();
                        refreshing_ = false;
                        emit changed();
                        return;
                    }
                    // 5. IP アドレス
                    nmcli({ QStringLiteral("-g"), QStringLiteral("IP4.ADDRESS"), QStringLiteral("device"), QStringLiteral("show"), dev },
                          [this](bool, const QString &ip, const QString &) {
                        ipAddress_ = ip.split(QLatin1Char('\n'), Qt::SkipEmptyParts).value(0).section(QLatin1Char('|'), 0, 0).trimmed();
                        refreshing_ = false;
                        emit changed();
                    });
                });
            });
        });
    });
}

void WifiManager::finishAction(bool ok, const QString &okMessage, const QString &err) {
    busy_ = false;
    if (ok) {
        message_ = okMessage;
    } else {
        // よくある失敗を分かりやすく
        if (err.contains(QStringLiteral("Secrets were required")) || err.contains(QStringLiteral("802-11-wireless-security.psk")))
            message_ = QStringLiteral("パスワードが違うか、足りません");
        else if (err.contains(QStringLiteral("No network with SSID")))
            message_ = QStringLiteral("その Wi-Fi が見つかりません");
        else
            message_ = QStringLiteral("失敗しました: ") + err.left(160);
        log::warn("WIFI", err);
    }
    emit changed();
    refresh(false);
}

void WifiManager::connectTo(const QString &ssid, const QString &password) {
    if (busy_ || device_.isEmpty() || ssid.isEmpty()) return;
    busy_ = true;
    message_ = QStringLiteral("「%1」につないでいます…").arg(ssid);
    emit changed();
    log::info("WIFI", QStringLiteral("connecting to \"%1\"").arg(ssid));   // パスワードは出さない
    bool saved = false;
    for (const QVariant &v : std::as_const(networks_)) {
        const QVariantMap n = v.toMap();
        if (n.value(QStringLiteral("ssid")).toString() == ssid) saved = n.value(QStringLiteral("saved")).toBool();
    }
    const QString okText = QStringLiteral("「%1」につなぎました").arg(ssid);
    if (saved && password.isEmpty()) {
        nmcli({ QStringLiteral("connection"), QStringLiteral("up"), QStringLiteral("id"), ssid },
              [this, okText](bool ok, const QString &, const QString &err) { finishAction(ok, okText, err); }, 45000);
        return;
    }
    // パスワードを入れ直すときは、保存済みの設定を消してから(古いパスワードが残らないように)
    auto doConnect = [this, ssid, password, okText]() {
        QStringList args = { QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("connect"), ssid,
                             QStringLiteral("ifname"), device_ };
        if (!password.isEmpty()) args << QStringLiteral("password") << password;
        nmcli(args, [this, okText](bool ok, const QString &, const QString &err) { finishAction(ok, okText, err); }, 45000);
    };
    if (saved) {
        nmcli({ QStringLiteral("connection"), QStringLiteral("delete"), QStringLiteral("id"), ssid },
              [doConnect](bool, const QString &, const QString &) { doConnect(); });
    } else {
        doConnect();
    }
}

void WifiManager::disconnectWifi() {
    if (busy_ || device_.isEmpty()) return;
    busy_ = true;
    emit changed();
    nmcli({ QStringLiteral("device"), QStringLiteral("disconnect"), device_ },
          [this](bool ok, const QString &, const QString &err) { finishAction(ok, QStringLiteral("切断しました"), err); });
}

void WifiManager::forget(const QString &ssid) {
    if (busy_ || ssid.isEmpty()) return;
    busy_ = true;
    emit changed();
    nmcli({ QStringLiteral("connection"), QStringLiteral("delete"), QStringLiteral("id"), ssid },
          [this, ssid](bool ok, const QString &, const QString &err) {
              finishAction(ok, QStringLiteral("「%1」のパスワードを消しました").arg(ssid), err);
          });
}

void WifiManager::setEnabled(bool on) {
    if (busy_) return;
    busy_ = true;
    emit changed();
    nmcli({ QStringLiteral("radio"), QStringLiteral("wifi"), on ? QStringLiteral("on") : QStringLiteral("off") },
          [this, on](bool ok, const QString &, const QString &err) {
              finishAction(ok, on ? QStringLiteral("Wi-Fi をオンにしました") : QStringLiteral("Wi-Fi をオフにしました"), err);
          });
}

} // namespace opencruise
