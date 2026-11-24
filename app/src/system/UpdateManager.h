/**
 * @file UpdateManager.h
 * @brief アプリの更新(USB メモリ・ネット)。設定 > システム > アップデート が使う。
 *
 * 更新ファイル(.ocapp)は scripts/make-app-update.sh が作る。中身は tar で、manifest.json(ビルド番号・版・
 * payload の sha256・変更内容)と payload.tar.gz(usr/bin/opencruise と usr/share/opencruise)。
 *
 * 入れ方: payload の sha256 を確かめてから、アプリの更新の置き場所(既定 /home/opencruise/app)の
 * versions/<ビルド番号>/ に展開し、current のリンクをそこへ切り替える。反映はアプリの再起動(restartApp)で、
 * 起動するときに /usr/bin/opencruise-launch が current の版を選ぶ。新しい版が 30 秒動いたら good に書く
 * (good にならないまま 3 回起動したら、opencruise-launch が前の版へ戻して bad に書く)。
 * どの処理もアプリのユーザーの権限だけで行う(/home/opencruise/app はアプリのユーザーのもの)。
 *
 * 探す場所:
 *   USB  /run/opencruise-usb/<デバイス>/(opencruise-usb-mount が読み取り専用でつなぐ)の直下と opencruise-update/
 *   ネット kServerUrl/index.json(開発 PC の scripts/update-server.sh)。環境変数 OPENCRUISE_UPDATE_URL で変えられる
 * 置き場所は環境変数 OPENCRUISE_APP_DIR / OPENCRUISE_USB_DIR で変えられる(開発 PC での確認用)。
 */
#pragma once

#include <QByteArray>
#include <QFileSystemWatcher>
#include <QHash>
#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

#include <functional>

class QFile;
class QNetworkReply;

namespace opencruise {

class UpdateManager : public QObject {
    Q_OBJECT
    /// ネット経由の更新元(アプリの定数。環境変数 OPENCRUISE_UPDATE_URL があればそちら)
    Q_PROPERTY(QString serverUrl READ serverUrl CONSTANT)
    /// 今動いているアプリのビルド番号(YYYYMMDDhhmmss。分からなければ "dev")
    Q_PROPERTY(QString currentBuild READ currentBuild CONSTANT)
    /// OS に入っている版のビルド番号(/usr/share/opencruise/build-id)
    Q_PROPERTY(QString builtinBuild READ builtinBuild CONSTANT)
    /// 更新で入れた版で動いているか(false なら OS に入っている版)
    Q_PROPERTY(bool runningUpdate READ runningUpdate CONSTANT)
    /// 起動できずに戻された版(opencruise-launch が書く bad。無ければ空)
    Q_PROPERTY(QString rolledBackFrom READ rolledBackFrom NOTIFY stateChanged)
    /// "idle" / "checking" / "downloading" / "installing" / "ready"(入れ終わった。再起動で反映) / "error"
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    Q_PROPERTY(QString message READ message NOTIFY stateChanged)
    /// 入れ終わって再起動を待っている版(無ければ空)
    Q_PROPERTY(QString pendingBuild READ pendingBuild NOTIFY stateChanged)
    /// ダウンロード・展開の進み具合(0〜1。分からなければ -1)
    Q_PROPERTY(double progress READ progress NOTIFY progressChanged)
    /// USB メモリにある更新ファイル: [{ path, file, device, build, version, notes, size, newer }](新しい順)
    Q_PROPERTY(QVariantList usbUpdates READ usbUpdates NOTIFY usbUpdatesChanged)
    /// USB メモリがつながっているか
    Q_PROPERTY(bool usbPresent READ usbPresent NOTIFY usbUpdatesChanged)
    /// ネットで見つけた更新: { build, version, file, size, sha256, notes, newer }(未確認・見つからなければ空)
    Q_PROPERTY(QVariantMap netUpdate READ netUpdate NOTIFY netUpdateChanged)
    /// ネットの確認の結果の文(「確認していません」「最新です」など)
    Q_PROPERTY(QString netStatus READ netStatus NOTIFY netUpdateChanged)
    /// 前の版(good か OS の版)に戻せるか
    Q_PROPERTY(bool canRollback READ canRollback NOTIFY stateChanged)
    Q_PROPERTY(QString rollbackTarget READ rollbackTarget NOTIFY stateChanged)

public:
    /// 既定の更新元(開発 PC の scripts/update-server.sh)
    static constexpr const char *kServerUrl = "http://opencruise-dev.local:8765";

    explicit UpdateManager(QObject *parent = nullptr);

    QString serverUrl() const { return serverUrl_; }
    QString currentBuild() const { return currentBuild_; }
    QString builtinBuild() const { return builtinBuild_; }
    bool runningUpdate() const { return runningUpdate_; }
    QString rolledBackFrom() const;
    QString state() const { return state_; }
    QString message() const { return message_; }
    QString pendingBuild() const { return pendingBuild_; }
    double progress() const { return progress_; }
    QVariantList usbUpdates() const { return usbUpdates_; }
    bool usbPresent() const { return usbPresent_; }
    QVariantMap netUpdate() const { return netUpdate_; }
    QString netStatus() const { return netStatus_; }
    bool canRollback() const;
    QString rollbackTarget() const;

    /// USB メモリの中を探し直す(挿した・抜いたときは自動で探す)
    Q_INVOKABLE void scanUsb();
    /// ネットの更新元に新しい版があるか確かめる
    Q_INVOKABLE void checkNetwork();
    /// 更新ファイルを入れる(USB の path)
    Q_INVOKABLE void installFile(const QString &path);
    /// ネットで見つけた版をダウンロードして入れる
    Q_INVOKABLE void installNetwork();
    /// ダウンロード・展開をやめる
    Q_INVOKABLE void cancel();
    /// 前の版(good か OS の版)へ戻す(再起動で反映)
    Q_INVOKABLE void rollback();
    /// 「戻しました」の表示を消す
    Q_INVOKABLE void clearRolledBack();
    /// アプリを再起動して反映する(systemd が起動し直す。終了コード 75)
    Q_INVOKABLE void restartApp();

signals:
    void stateChanged();
    void progressChanged();
    void usbUpdatesChanged();
    void netUpdateChanged();

private:
    void setState(const QString &state, const QString &message = QString());
    void setProgress(double p);
    void fail(const QString &message);
    bool newer(const QString &build) const;
    QString appPath(const QString &rel) const;
    QString linkTarget(const QString &rel) const;
    bool pointCurrentTo(const QString &target);
    QVariantMap readManifest(const QString &ocapp) const;
    void runTar(const QStringList &args, std::function<void(bool, const QString &)> done);
    void hashFile(const QString &path, std::function<void(const QByteArray &)> done);
    void continueInstall(const QString &tmpDir);
    void finishInstall(const QString &build, const QString &newDir);
    void cleanupVersions();
    void markGood();
    void finishDownload();

    QString serverUrl_;
    QString appDir_;
    QString usbDir_;
    QString currentBuild_ = QStringLiteral("dev");
    QString builtinBuild_;
    bool runningUpdate_ = false;
    QString state_ = QStringLiteral("idle");
    QString message_;
    QString pendingBuild_;
    double progress_ = -1;
    QVariantList usbUpdates_;
    bool usbPresent_ = false;
    QVariantMap netUpdate_;
    QString netStatus_ = QStringLiteral("確認していません");
    QHash<QString, QVariantMap> manifestCache_;   // path + 更新時刻 → manifest

    QFileSystemWatcher usbWatcher_;
    QTimer usbRescan_;
    QTimer goodTimer_;
    QNetworkAccessManager net_;
    QPointer<QNetworkReply> reply_;
    QFile *download_ = nullptr;
    QString downloadPath_;
    QByteArray expectSha_;
    bool cancelled_ = false;
    int serial_ = 0;   // cancel() で、途中の処理の続きを捨てる
};

} // namespace opencruise
