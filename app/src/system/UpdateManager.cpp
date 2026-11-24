/**
 * @file UpdateManager.cpp
 * @brief アプリの更新(USB メモリ・ネット)の実装。流れは UpdateManager.h を参照。
 */
#include "UpdateManager.h"

#include "core/Log.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QUrl>

#include <algorithm>
#include <cstdio>
#include <memory>
#include <unistd.h>

namespace opencruise {

namespace {
QString readTrimmed(const QString &path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) return QString();
    return QString::fromUtf8(f.readAll()).trimmed();
}
bool writeText(const QString &path, const QString &text) {
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) return false;
    f.write(text.toUtf8());
    f.write("\n");
    return true;
}
bool validBuild(const QString &b) {
    static const QRegularExpression re(QStringLiteral("^[0-9]{8,20}$"));
    return re.match(b).hasMatch();
}
// ビルド番号を人が読める形に(20261124120000 → 2026-11-24 12:00)
QString prettyBuild(const QString &b) {
    if (b.size() < 12 || !validBuild(b)) return b;
    return QStringLiteral("%1-%2-%3 %4:%5").arg(b.mid(0, 4), b.mid(4, 2), b.mid(6, 2), b.mid(8, 2), b.mid(10, 2));
}
} // namespace

UpdateManager::UpdateManager(QObject *parent) : QObject(parent) {
    serverUrl_ = qEnvironmentVariable("OPENCRUISE_UPDATE_URL", QString::fromLatin1(kServerUrl));
    while (serverUrl_.endsWith(QLatin1Char('/'))) serverUrl_.chop(1);

    // 置き場所: 車では /home/opencruise/app(tmpfiles.d が作る)。無くて作れなければ(開発 PC など)、ユーザーのデータの場所
    appDir_ = qEnvironmentVariable("OPENCRUISE_APP_DIR", QStringLiteral("/home/opencruise/app"));
    if (!QDir().mkpath(appDir_) || !QFileInfo(appDir_).isWritable())
        appDir_ = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation) + QStringLiteral("/app");
    QDir().mkpath(appDir_ + QStringLiteral("/versions"));
    usbDir_ = qEnvironmentVariable("OPENCRUISE_USB_DIR", QStringLiteral("/run/opencruise-usb"));

    // 今動いている版: 実行ファイルの隣の ../share/opencruise/build-id(make-app-update.sh と opencruise のレシピが書く)
    const QString exeDir = QCoreApplication::applicationDirPath();
    const QString b = readTrimmed(exeDir + QStringLiteral("/../share/opencruise/build-id"));
    if (validBuild(b)) currentBuild_ = b;
    builtinBuild_ = readTrimmed(QStringLiteral("/usr/share/opencruise/build-id"));
    const QString versions = QDir(appDir_ + QStringLiteral("/versions")).canonicalPath();
    runningUpdate_ = !versions.isEmpty() && QDir(exeDir).canonicalPath().startsWith(versions + QLatin1Char('/'));
    log::info("UPDATE", QStringLiteral("running build %1 (%2), app dir %3, server %4")
                            .arg(currentBuild_, runningUpdate_ ? QStringLiteral("update") : QStringLiteral("builtin"),
                                 appDir_, serverUrl_));
    const QString bad = rolledBackFrom();
    if (!bad.isEmpty()) log::warn("UPDATE", QStringLiteral("%1 was rolled back by opencruise-launch").arg(bad));

    // USB: つなぐ場所のフォルダが増えた・減ったら(マウントが終わるのを少し待って)探し直す
    usbRescan_.setSingleShot(true);
    usbRescan_.setInterval(1500);
    connect(&usbRescan_, &QTimer::timeout, this, &UpdateManager::scanUsb);
    if (QFileInfo::exists(usbDir_)) usbWatcher_.addPath(usbDir_);
    connect(&usbWatcher_, &QFileSystemWatcher::directoryChanged, this, [this]() {
        usbRescan_.start();
        QTimer::singleShot(5000, this, &UpdateManager::scanUsb);   // マウントが遅い USB メモリ向けにもう一度
    });
    QTimer::singleShot(0, this, &UpdateManager::scanUsb);

    // 更新で入れた版が 30 秒動いたら「起動できた」印を付ける(opencruise-launch が前の版へ戻さないように)
    goodTimer_.setSingleShot(true);
    goodTimer_.setInterval(30000);
    connect(&goodTimer_, &QTimer::timeout, this, &UpdateManager::markGood);
    if (runningUpdate_) goodTimer_.start();
}

QString UpdateManager::appPath(const QString &rel) const { return appDir_ + QLatin1Char('/') + rel; }

QString UpdateManager::linkTarget(const QString &rel) const {
    char buf[1024];
    const QByteArray p = QFile::encodeName(appPath(rel));
    const ssize_t n = ::readlink(p.constData(), buf, sizeof(buf) - 1);
    if (n <= 0) return QString();
    return QFile::decodeName(QByteArray(buf, int(n)));
}

// current を target(versions/<ビルド番号>)へ向け直す。作ってから名前を変えるので、途中で電源が切れても壊れない
bool UpdateManager::pointCurrentTo(const QString &target) {
    const QByteArray tmp = QFile::encodeName(appPath(QStringLiteral("current.new")));
    const QByteArray cur = QFile::encodeName(appPath(QStringLiteral("current")));
    ::unlink(tmp.constData());
    if (::symlink(QFile::encodeName(target).constData(), tmp.constData()) != 0) return false;
    if (::rename(tmp.constData(), cur.constData()) != 0) return false;
    ::sync();
    return true;
}

QString UpdateManager::rolledBackFrom() const {
    const QString bad = readTrimmed(appPath(QStringLiteral("bad")));
    return bad.section(QLatin1Char('/'), -1);
}

void UpdateManager::clearRolledBack() {
    QFile::remove(appPath(QStringLiteral("bad")));
    emit stateChanged();
}

bool UpdateManager::canRollback() const {
    return !linkTarget(QStringLiteral("current")).isEmpty();
}

QString UpdateManager::rollbackTarget() const {
    const QString cur = linkTarget(QStringLiteral("current"));
    const QString good = readTrimmed(appPath(QStringLiteral("good")));
    if (!good.isEmpty() && good != cur && QFileInfo(appPath(good) + QStringLiteral("/usr/bin/opencruise")).isExecutable())
        return prettyBuild(good.section(QLatin1Char('/'), -1));
    return QStringLiteral("OS に入っている版");
}

void UpdateManager::setState(const QString &state, const QString &message) {
    state_ = state;
    message_ = message;
    emit stateChanged();
}

void UpdateManager::setProgress(double p) {
    if (qFuzzyCompare(p + 2, progress_ + 2)) return;
    progress_ = p;
    emit progressChanged();
}

void UpdateManager::fail(const QString &message) {
    log::warn("UPDATE", message);
    setProgress(-1);
    QDir(appPath(QStringLiteral("tmp"))).removeRecursively();
    setState(QStringLiteral("error"), message);
}

bool UpdateManager::newer(const QString &build) const {
    if (!validBuild(build)) return false;
    if (!validBuild(currentBuild_)) return true;
    if (build.size() != currentBuild_.size()) return build.size() > currentBuild_.size();
    return build > currentBuild_;
}

// ---------------------------------------------------------------- USB
QVariantMap UpdateManager::readManifest(const QString &ocapp) const {
    const QFileInfo fi(ocapp);
    const QString key = ocapp + QLatin1Char('@') + QString::number(fi.lastModified().toMSecsSinceEpoch());
    auto it = manifestCache_.constFind(key);
    if (it != manifestCache_.constEnd()) return it.value();
    QProcess p;
    p.start(QStringLiteral("tar"), { QStringLiteral("-xOf"), ocapp, QStringLiteral("manifest.json") });
    QVariantMap m;
    if (p.waitForFinished(5000) && p.exitStatus() == QProcess::NormalExit && p.exitCode() == 0) {
        const QJsonDocument doc = QJsonDocument::fromJson(p.readAllStandardOutput());
        if (doc.isObject()) m = doc.object().toVariantMap();
    }
    const_cast<UpdateManager *>(this)->manifestCache_.insert(key, m);
    return m;
}

void UpdateManager::scanUsb() {
    if (QFileInfo::exists(usbDir_) && !usbWatcher_.directories().contains(usbDir_)) usbWatcher_.addPath(usbDir_);
    QVariantList list;
    bool present = false;
    const QDir root(usbDir_);
    for (const QString &dev : root.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        present = true;
        for (const QString &sub : { QString(), QStringLiteral("/opencruise-update") }) {
            const QDir d(root.filePath(dev) + sub);
            for (const QFileInfo &f : d.entryInfoList({ QStringLiteral("*.ocapp") }, QDir::Files)) {
                const QVariantMap m = readManifest(f.absoluteFilePath());
                const QString build = m.value(QStringLiteral("build")).toString();
                if (!validBuild(build)) continue;
                list.append(QVariantMap{
                    { QStringLiteral("path"), f.absoluteFilePath() }, { QStringLiteral("file"), f.fileName() },
                    { QStringLiteral("device"), dev }, { QStringLiteral("build"), build },
                    { QStringLiteral("buildText"), prettyBuild(build) },
                    { QStringLiteral("version"), m.value(QStringLiteral("version")).toString() },
                    { QStringLiteral("notes"), m.value(QStringLiteral("notes")).toString() },
                    { QStringLiteral("size"), f.size() }, { QStringLiteral("newer"), newer(build) },
                    { QStringLiteral("current"), build == currentBuild_ } });
            }
        }
    }
    std::sort(list.begin(), list.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("build")).toString() > b.toMap().value(QStringLiteral("build")).toString();
    });
    if (list != usbUpdates_ || present != usbPresent_) {
        usbUpdates_ = list;
        usbPresent_ = present;
        if (!list.isEmpty()) log::info("UPDATE", QStringLiteral("found %1 update file(s) on USB").arg(list.size()));
        emit usbUpdatesChanged();
    }
}

// ---------------------------------------------------------------- ネット
void UpdateManager::checkNetwork() {
    if (reply_) return;
    netStatus_ = QStringLiteral("確認しています…");
    emit netUpdateChanged();
    QNetworkRequest req(QUrl(serverUrl_ + QStringLiteral("/index.json")));
    req.setTransferTimeout(8000);
    req.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::AlwaysNetwork);
    reply_ = net_.get(req);
    QNetworkReply *r = reply_;
    connect(r, &QNetworkReply::finished, this, [this, r]() {
        r->deleteLater();
        reply_ = nullptr;
        netUpdate_.clear();
        if (r->error() != QNetworkReply::NoError) {
            netStatus_ = QStringLiteral("更新元に届きません(%1)").arg(r->errorString());
            log::info("UPDATE", QStringLiteral("check %1 failed: %2").arg(serverUrl_, r->errorString()));
            emit netUpdateChanged();
            return;
        }
        const QJsonObject app = QJsonDocument::fromJson(r->readAll()).object().value(QStringLiteral("app")).toObject();
        const QString build = app.value(QStringLiteral("build")).toString();
        const QString file = app.value(QStringLiteral("file")).toString();
        if (!validBuild(build) || file.isEmpty() || file.contains(QLatin1Char('/'))) {
            netStatus_ = QStringLiteral("更新元に更新ファイルがありません");
            emit netUpdateChanged();
            return;
        }
        netUpdate_ = app.toVariantMap();
        netUpdate_.insert(QStringLiteral("buildText"), prettyBuild(build));
        netUpdate_.insert(QStringLiteral("newer"), newer(build));
        netUpdate_.insert(QStringLiteral("current"), build == currentBuild_);
        netStatus_ = newer(build) ? QStringLiteral("新しい版があります") : QStringLiteral("最新です");
        log::info("UPDATE", QStringLiteral("server has build %1 (%2)").arg(build, netStatus_));
        emit netUpdateChanged();
    });
}

void UpdateManager::installNetwork() {
    if (state_ == QStringLiteral("downloading") || state_ == QStringLiteral("installing") || reply_) return;
    const QString file = netUpdate_.value(QStringLiteral("file")).toString();
    if (file.isEmpty()) return;
    cancelled_ = false;
    ++serial_;
    QDir().mkpath(appPath(QStringLiteral("download")));
    downloadPath_ = appPath(QStringLiteral("download/") + file);
    expectSha_ = netUpdate_.value(QStringLiteral("sha256")).toString().toLatin1().toLower();
    delete download_;
    download_ = new QFile(downloadPath_ + QStringLiteral(".part"), this);
    if (!download_->open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        fail(QStringLiteral("ダウンロード先に書けません: %1").arg(download_->fileName()));
        return;
    }
    setProgress(0);
    setState(QStringLiteral("downloading"), QStringLiteral("ダウンロードしています"));
    QNetworkRequest req(QUrl(serverUrl_ + QLatin1Char('/') + QString::fromUtf8(QUrl::toPercentEncoding(file))));
    req.setTransferTimeout(30000);
    reply_ = net_.get(req);
    QNetworkReply *r = reply_;
    connect(r, &QNetworkReply::readyRead, this, [this, r]() { if (download_) download_->write(r->readAll()); });
    connect(r, &QNetworkReply::downloadProgress, this, [this](qint64 got, qint64 total) {
        if (total > 0) setProgress(double(got) / double(total));
    });
    connect(r, &QNetworkReply::finished, this, &UpdateManager::finishDownload);
}

void UpdateManager::finishDownload() {
    QNetworkReply *r = reply_;
    reply_ = nullptr;
    if (!r) return;
    r->deleteLater();
    if (download_) download_->write(r->readAll());
    const QString part = downloadPath_ + QStringLiteral(".part");
    if (download_) { download_->close(); download_->deleteLater(); download_ = nullptr; }
    if (cancelled_) { QFile::remove(part); return; }
    if (r->error() != QNetworkReply::NoError) {
        QFile::remove(part);
        fail(QStringLiteral("ダウンロードできませんでした(%1)").arg(r->errorString()));
        return;
    }
    setState(QStringLiteral("downloading"), QStringLiteral("ダウンロードしたファイルを確かめています"));
    const int serial = serial_;
    hashFile(part, [this, part, serial](const QByteArray &sha) {
        if (serial != serial_) return;
        if (!expectSha_.isEmpty() && sha != expectSha_) {
            QFile::remove(part);
            fail(QStringLiteral("ダウンロードしたファイルが壊れています(sha256 が合いません)"));
            return;
        }
        QFile::remove(downloadPath_);
        QFile::rename(part, downloadPath_);
        setState(QStringLiteral("idle"));
        installFile(downloadPath_);
    });
}

void UpdateManager::cancel() {
    cancelled_ = true;
    ++serial_;
    if (reply_) reply_->abort();
    QDir(appPath(QStringLiteral("tmp"))).removeRecursively();
    setProgress(-1);
    setState(QStringLiteral("idle"), QStringLiteral("やめました"));
}

// ---------------------------------------------------------------- 入れる
void UpdateManager::runTar(const QStringList &args, std::function<void(bool, const QString &)> done) {
    auto *p = new QProcess(this);
    const int serial = serial_;
    connect(p, &QProcess::finished, this, [this, p, done, serial](int code, QProcess::ExitStatus st) {
        const QString err = QString::fromUtf8(p->readAllStandardError()).trimmed();
        p->deleteLater();
        if (serial != serial_) return;   // やめた
        done(st == QProcess::NormalExit && code == 0, err);
    });
    connect(p, &QProcess::errorOccurred, this, [this, p, done, serial](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart) return;
        p->deleteLater();
        if (serial != serial_) return;
        done(false, QStringLiteral("tar を起動できません"));
    });
    p->start(QStringLiteral("tar"), args);
}

// 大きなファイルの sha256 を、画面を止めないよう少しずつ求める
void UpdateManager::hashFile(const QString &path, std::function<void(const QByteArray &)> done) {
    auto file = std::make_shared<QFile>(path);
    if (!file->open(QIODevice::ReadOnly)) { done(QByteArray()); return; }
    auto hash = std::make_shared<QCryptographicHash>(QCryptographicHash::Sha256);
    const qint64 total = std::max<qint64>(1, file->size());
    auto step = std::make_shared<std::function<void()>>();
    *step = [this, file, hash, total, done, step]() {
        for (int i = 0; i < 4 && !file->atEnd(); ++i) hash->addData(file->read(4 << 20));
        setProgress(double(file->pos()) / double(total));
        if (!file->atEnd()) { QTimer::singleShot(0, this, *step); return; }
        file->close();
        const QByteArray r = hash->result().toHex();
        *step = nullptr;   // 自分への参照を切る
        done(r);
    };
    QTimer::singleShot(0, this, *step);
}

void UpdateManager::installFile(const QString &path) {
    if (state_ == QStringLiteral("downloading") || state_ == QStringLiteral("installing")) return;
    if (!QFileInfo(path).isReadable()) { fail(QStringLiteral("更新ファイルが読めません: %1").arg(path)); return; }
    cancelled_ = false;
    ++serial_;
    log::info("UPDATE", QStringLiteral("installing %1").arg(path));
    const QString tmp = appPath(QStringLiteral("tmp"));
    QDir(tmp).removeRecursively();
    QDir().mkpath(tmp);
    setProgress(-1);
    setState(QStringLiteral("installing"), QStringLiteral("更新ファイルを開いています"));
    runTar({ QStringLiteral("-xf"), path, QStringLiteral("-C"), tmp, QStringLiteral("manifest.json"), QStringLiteral("payload.tar.gz") },
           [this, tmp](bool ok, const QString &err) {
               if (!ok) { fail(QStringLiteral("更新ファイルを開けません(%1)").arg(err)); return; }
               continueInstall(tmp);
           });
}

void UpdateManager::continueInstall(const QString &tmpDir) {
    QFile mf(tmpDir + QStringLiteral("/manifest.json"));
    if (!mf.open(QIODevice::ReadOnly)) { fail(QStringLiteral("更新ファイルに manifest.json がありません")); return; }
    const QJsonObject m = QJsonDocument::fromJson(mf.readAll()).object();
    const QString build = m.value(QStringLiteral("build")).toString();
    if (m.value(QStringLiteral("format")).toInt() != 1 || !validBuild(build)) {
        fail(QStringLiteral("この更新ファイルの形式には対応していません"));
        return;
    }
    const QByteArray want = m.value(QStringLiteral("payloadSha256")).toString().toLatin1().toLower();
    setState(QStringLiteral("installing"), QStringLiteral("壊れていないか確かめています"));
    const int serial = serial_;
    hashFile(tmpDir + QStringLiteral("/payload.tar.gz"), [this, tmpDir, build, want, serial](const QByteArray &sha) {
        if (serial != serial_) return;
        if (sha.isEmpty() || sha != want) { fail(QStringLiteral("更新ファイルが壊れています(sha256 が合いません)")); return; }
        const QString newDir = appPath(QStringLiteral("versions/") + build + QStringLiteral(".new"));
        QDir(newDir).removeRecursively();
        QDir().mkpath(newDir);
        setProgress(-1);
        setState(QStringLiteral("installing"), QStringLiteral("展開しています"));
        runTar({ QStringLiteral("-xzf"), tmpDir + QStringLiteral("/payload.tar.gz"), QStringLiteral("-C"), newDir },
               [this, build, newDir](bool ok, const QString &err) {
                   if (!ok) { QDir(newDir).removeRecursively(); fail(QStringLiteral("展開できませんでした(%1)").arg(err)); return; }
                   finishInstall(build, newDir);
               });
    });
}

void UpdateManager::finishInstall(const QString &build, const QString &newDir) {
    if (!QFileInfo(newDir + QStringLiteral("/usr/bin/opencruise")).isExecutable()) {
        QDir(newDir).removeRecursively();
        fail(QStringLiteral("更新ファイルにアプリが入っていません"));
        return;
    }
    const QString rel = QStringLiteral("versions/") + build;
    const QString finalDir = appPath(rel);
    // 同じ版を入れ直すとき: 前のものは名前を変えてから消す(動いている版でも、開いているファイルは消えない)
    if (QFileInfo::exists(finalDir)) {
        const QString old = finalDir + QStringLiteral(".old");
        QDir(old).removeRecursively();
        QDir().rename(finalDir, old);
    }
    if (!QDir().rename(newDir, finalDir)) { fail(QStringLiteral("展開した版を置けませんでした")); return; }
    if (!pointCurrentTo(rel)) { fail(QStringLiteral("起動する版を切り替えられませんでした")); return; }
    QFile::remove(appPath(QStringLiteral("tries")));
    QFile::remove(appPath(QStringLiteral("bad")));
    QDir(appPath(QStringLiteral("tmp"))).removeRecursively();
    cleanupVersions();
    pendingBuild_ = build;
    setProgress(-1);
    log::info("UPDATE", QStringLiteral("installed build %1; restart to apply").arg(build));
    setState(QStringLiteral("ready"), QStringLiteral("%1 の版を入れました。再起動すると反映されます").arg(prettyBuild(build)));
    scanUsb();   // 「今の版」の印を付け直す(再起動まではまだ前の版)
}

// 残す版: current・good・今動いている版。それ以外(古い版・途中で止まった .new / .old)は消す
void UpdateManager::cleanupVersions() {
    QStringList keep = { linkTarget(QStringLiteral("current")), readTrimmed(appPath(QStringLiteral("good"))) };
    const QString exeVer = QDir(QCoreApplication::applicationDirPath() + QStringLiteral("/../..")).canonicalPath();
    if (runningUpdate_) keep << QStringLiteral("versions/") + QFileInfo(exeVer).fileName();
    const QDir vdir(appPath(QStringLiteral("versions")));
    for (const QString &d : vdir.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        if (keep.contains(QStringLiteral("versions/") + d)) continue;
        QDir(vdir.filePath(d)).removeRecursively();
    }
    QDir(appPath(QStringLiteral("download"))).removeRecursively();
}

void UpdateManager::rollback() {
    if (state_ == QStringLiteral("downloading") || state_ == QStringLiteral("installing")) return;
    const QString cur = linkTarget(QStringLiteral("current"));
    const QString good = readTrimmed(appPath(QStringLiteral("good")));
    QString to;
    if (!good.isEmpty() && good != cur && QFileInfo(appPath(good) + QStringLiteral("/usr/bin/opencruise")).isExecutable()) {
        if (!pointCurrentTo(good)) { fail(QStringLiteral("前の版に切り替えられませんでした")); return; }
        to = good.section(QLatin1Char('/'), -1);
    } else {
        QFile::remove(appPath(QStringLiteral("current")));
        to = builtinBuild_;
    }
    QFile::remove(appPath(QStringLiteral("tries")));
    pendingBuild_ = to;
    log::info("UPDATE", QStringLiteral("rolled back to %1; restart to apply").arg(to.isEmpty() ? QStringLiteral("builtin") : to));
    setState(QStringLiteral("ready"), QStringLiteral("前の版(%1)に戻しました。再起動すると反映されます")
                                          .arg(to.isEmpty() ? QStringLiteral("OS に入っている版") : prettyBuild(to)));
}

void UpdateManager::markGood() {
    const QString cur = linkTarget(QStringLiteral("current"));
    const QString exeVer = QDir(QCoreApplication::applicationDirPath() + QStringLiteral("/../..")).canonicalPath();
    if (cur.isEmpty() || cur != QStringLiteral("versions/") + QFileInfo(exeVer).fileName()) return;   // 切り替え済み・戻した後
    if (readTrimmed(appPath(QStringLiteral("good"))) == cur) return;
    writeText(appPath(QStringLiteral("good")), cur);
    QFile::remove(appPath(QStringLiteral("tries")));
    log::info("UPDATE", QStringLiteral("build %1 marked as good").arg(currentBuild_));
    cleanupVersions();
}

void UpdateManager::restartApp() {
    log::info("UPDATE", QStringLiteral("restarting the app to apply build %1").arg(pendingBuild_));
    // systemd(opencruise.service の Restart=on-failure)が起動し直す。opencruise-launch が current の版を選ぶ
    QTimer::singleShot(300, qApp, []() { QCoreApplication::exit(75); });
}

} // namespace opencruise
