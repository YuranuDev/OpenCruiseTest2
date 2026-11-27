/**
 * @file ImageImporter.cpp
 * @brief USB メモリなどの画像を、背景・飾りのフォルダへコピーする処理の実装。
 */
#include "ImageImporter.h"

#include "core/Log.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QMetaObject>
#include <QSize>
#include <QStorageInfo>
#include <QThread>

#include <unistd.h>

#include <utility>

namespace opencruise {

namespace {

const QString kBackground = QStringLiteral("background");
const QString kDecoration = QStringLiteral("decoration");

bool isImageName(const QString &name) {
    static const QStringList ext = {QStringLiteral("png"), QStringLiteral("jpg"), QStringLiteral("jpeg"),
                                    QStringLiteral("webp"), QStringLiteral("gif")};
    return ext.contains(QFileInfo(name).suffix().toLower());
}

// フォルダ名(デバイスの下の階層)から行き先の候補を決める。どちらでもなければ空
QString suggestedKind(const QStringList &folders) {
    for (const QString &f : folders) {
        const QString p = f.toLower();
        if (p == QLatin1String("backgrounds") || p == QLatin1String("background")) return kBackground;
        if (p == QLatin1String("decorations") || p == QLatin1String("decoration")) return kDecoration;
    }
    return QString();
}

// Windows が USB メモリに作る管理用のフォルダなどは探さない
bool skipDirName(const QString &n) {
    return n.startsWith(QLatin1Char('.')) || n.startsWith(QLatin1Char('$')) ||
           n == QLatin1String("System Volume Information") || n == QLatin1String("lost+found");
}

QString sizeText(qint64 n) {
    return n >= 1048576 ? QStringLiteral("%1 MB").arg(n / 1048576.0, 0, 'f', 1)
                        : QStringLiteral("%1 KB").arg(qMax<qint64>(1, n / 1024));
}

struct ScanResult {
    bool present = false;
    QVariantList list;
    int omitted = 0;
};

struct ScanState {
    QVariantList *list;
    int *omitted;
    int dirsLeft;   // 巡るフォルダ数の上限(巨大な USB メモリで時間がかかりすぎないように)
};

void scanDir(const QDir &dir, const QString &device, const QStringList &folders, int depth, ScanState &st,
             const std::atomic_bool &cancel) {
    if (cancel.load() || st.dirsLeft <= 0) return;
    --st.dirsLeft;
    // シンボリックリンクは辿らない(USB メモリの外のファイルを指させない)。隠しファイルも見ない
    const QFileInfoList entries = dir.entryInfoList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot | QDir::NoSymLinks,
                                                    QDir::DirsFirst | QDir::Name | QDir::IgnoreCase);
    for (const QFileInfo &fi : entries) {
        if (cancel.load()) return;
        if (fi.isDir()) {
            if (depth < ImageImporter::kMaxDepth && !skipDirName(fi.fileName()))
                scanDir(QDir(fi.absoluteFilePath()), device, folders + QStringList{fi.fileName()}, depth + 1, st, cancel);
            continue;
        }
        if (!isImageName(fi.fileName()) || fi.size() <= 0 || fi.size() > ImageImporter::kMaxFileBytes) continue;
        if (st.list->size() >= ImageImporter::kMaxCandidates) {
            ++*st.omitted;
            continue;
        }
        st.list->append(QVariantMap{{QStringLiteral("path"), fi.absoluteFilePath()},
                                    {QStringLiteral("file"), fi.fileName()},
                                    {QStringLiteral("device"), device},
                                    {QStringLiteral("folder"), folders.join(QLatin1Char('/'))},
                                    {QStringLiteral("size"), fi.size()},
                                    {QStringLiteral("suggested"), suggestedKind(folders)}});
    }
}

ScanResult scanUsbImages(const QString &usbDir, const std::atomic_bool &cancel) {
    ScanResult res;
    const QDir root(usbDir);
    ScanState st{&res.list, &res.omitted, 500};
    for (const QString &dev : root.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
        res.present = true;
        scanDir(QDir(root.filePath(dev)), dev, QStringList(), 0, st, cancel);
    }
    return res;
}

bool sameContent(const QString &a, const QString &b) {
    QFile fa(a), fb(b);
    if (fa.size() != fb.size()) return false;
    if (!fa.open(QIODevice::ReadOnly) || !fb.open(QIODevice::ReadOnly)) return false;
    while (!fa.atEnd()) {
        if (fa.read(65536) != fb.read(65536)) return false;
    }
    return true;
}

// 一時ファイルに書いて、書き終えてから名前を付ける(途中で止まっても中途半端な画像を残さない)。失敗したら理由を返す
QString copyFile(const QString &src, const QString &dest, const QString &tmp, const std::atomic_bool &cancel) {
    QFile in(src);
    if (!in.open(QIODevice::ReadOnly)) return QStringLiteral("読めません");
    QFile out(tmp);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) return QStringLiteral("書き込めません");
    QString error;
    while (!in.atEnd()) {
        if (cancel.load()) { error = QStringLiteral("中止しました"); break; }
        const QByteArray chunk = in.read(256 * 1024);
        if (chunk.isEmpty() && !in.atEnd()) { error = QStringLiteral("読み取りに失敗しました"); break; }
        if (out.write(chunk) != chunk.size()) { error = QStringLiteral("書き込みに失敗しました(空き容量?)"); break; }
    }
    if (error.isEmpty() && (!out.flush() || ::fsync(out.handle()) != 0)) error = QStringLiteral("書き込みを確定できません");
    out.close();
    if (error.isEmpty() && QFileInfo(tmp).size() != in.size()) error = QStringLiteral("コピーの大きさが合いません");
    if (error.isEmpty() && !QFile::rename(tmp, dest)) error = QStringLiteral("名前を付けられません");
    if (!error.isEmpty()) QFile::remove(tmp);
    return error;
}

struct ImportResult {
    int bg = 0, deco = 0, same = 0, skipped = 0, failed = 0;
    QString fatal;       // 取り込み自体をやめた理由(空き容量不足など)
    QStringList logs;    // ログはメインスレッドで出す
};

} // namespace

ImageImporter::ImageImporter(const QString &backgroundDir, const QString &decorationDir, QObject *parent)
    : QObject(parent), backgroundDir_(backgroundDir), decorationDir_(decorationDir) {
    // UpdateManager と同じ場所(USB メモリは opencruise-usb-mount が読み取り専用でつなぐ)
    usbDir_ = qEnvironmentVariable("OPENCRUISE_USB_DIR", QStringLiteral("/run/opencruise-usb"));
    cleanStaleParts();

    // USB のつなぐ場所のフォルダが増えた・減ったら、マウントが終わるのを少し待って探し直す(UpdateManager と同じ間合い)
    usbRescan_.setSingleShot(true);
    usbRescan_.setInterval(1500);
    connect(&usbRescan_, &QTimer::timeout, this, &ImageImporter::rescan);
    if (QFileInfo::exists(usbDir_)) usbWatcher_.addPath(usbDir_);
    connect(&usbWatcher_, &QFileSystemWatcher::directoryChanged, this, [this]() {
        usbRescan_.start();
        QTimer::singleShot(5000, this, &ImageImporter::rescan);
    });
}

ImageImporter::~ImageImporter() {
    cancel_.store(true);
    usbRescan_.stop();
    if (thread_) {
        thread_->wait();
        delete thread_;
        thread_ = nullptr;
    }
}

void ImageImporter::cleanStaleParts() const {
    // 再起動・電源断などで残った一時ファイルを消す
    for (const QString &d : {backgroundDir_, decorationDir_}) {
        const QDir dir(d);
        for (const QString &f : dir.entryList({QStringLiteral(".oc-import-*.part")}, QDir::Files | QDir::Hidden))
            QFile::remove(dir.filePath(f));
    }
}

void ImageImporter::setMessage(const QString &text) {
    if (text == message_) return;
    message_ = text;
    emit messageChanged();
}

void ImageImporter::setBusy(bool scanning, bool importing) {
    if (scanning == scanning_ && importing == importing_) return;
    scanning_ = scanning;
    importing_ = importing;
    emit busyChanged();
}

void ImageImporter::startWorker(std::function<void()> fn) {
    thread_ = QThread::create(std::move(fn));
    connect(thread_, &QThread::finished, this, [this, t = thread_]() {
        t->deleteLater();
        if (thread_ == t) thread_ = nullptr;
    });
    thread_->start();
}

void ImageImporter::rescan() {
    if (scanning_ || importing_) return;
    if (QFileInfo::exists(usbDir_) && !usbWatcher_.directories().contains(usbDir_)) usbWatcher_.addPath(usbDir_);
    setBusy(true, false);
    const QString usbDir = usbDir_;
    startWorker([this, usbDir]() {
        const ScanResult res = scanUsbImages(usbDir, cancel_);
        QMetaObject::invokeMethod(this, [this, res]() {
            if (res.list != candidates_ || res.present != usbPresent_ || res.omitted != omitted_) {
                candidates_ = res.list;
                usbPresent_ = res.present;
                omitted_ = res.omitted;
                emit candidatesChanged();
            }
            setBusy(false, false);
        }, Qt::QueuedConnection);
    });
}

void ImageImporter::importFiles(const QStringList &paths, const QString &kind) {
    if (scanning_ || importing_) return;
    if (kind != kBackground && kind != kDecoration && kind != QLatin1String("auto")) return;
    if (paths.isEmpty()) {
        setMessage(QStringLiteral("取り込む画像が選ばれていません"));
        return;
    }
    setBusy(false, true);
    setMessage(QStringLiteral("取り込んでいます…"));
    const QString usbDir = usbDir_, bgDir = backgroundDir_, decoDir = decorationDir_;
    startWorker([this, paths, kind, usbDir, bgDir, decoDir]() {
        ImportResult r;
        struct Job { QString src, name, kind; qint64 size; };
        QList<Job> jobs;
        qint64 total = 0;

        const QString root = QDir(usbDir).canonicalPath();
        for (const QString &path : paths) {
            // QML から来た名前は信用しない: USB のマウント先の中の、ふつうのファイルだけを受け付ける
            const QFileInfo fi(path);
            const QString canon = fi.canonicalFilePath();
            if (root.isEmpty() || canon.isEmpty() || fi.isSymLink() || !fi.isFile() || !canon.startsWith(root + QLatin1Char('/'))) {
                ++r.skipped;
                r.logs << QStringLiteral("skip (not a file on USB): %1").arg(path);
                continue;
            }
            QStringList parts = canon.mid(root.size() + 1).split(QLatin1Char('/'), Qt::SkipEmptyParts);
            if (parts.size() < 2) { ++r.skipped; continue; }
            parts.removeFirst();   // デバイス名
            const QString name = parts.takeLast();
            const QString k = kind == QLatin1String("auto") ? suggestedKind(parts) : kind;
            const qint64 size = fi.size();
            if (k.isEmpty() || !isImageName(name) || name.toUtf8().size() > 200 || size <= 0 || size > kMaxFileBytes) {
                ++r.skipped;
                r.logs << QStringLiteral("skip (not importable): %1").arg(canon);
                continue;
            }
            // 中身が本当に画像か・大きすぎないかを、ヘッダだけ読んで確かめる(全部は読み込まない)
            QImageReader reader(canon);
            const QSize px = reader.size();
            if (!reader.canRead() || (px.isValid() && (px.width() > kMaxPixels || px.height() > kMaxPixels))) {
                ++r.skipped;
                r.logs << QStringLiteral("skip (unreadable or too large image): %1").arg(canon);
                continue;
            }
            jobs.append({canon, name, k, size});
            total += size;
        }

        // 空きが少ないと、アプリの更新の展開が失敗するので、一定の空きを残す
        const qint64 avail = QStorageInfo(bgDir).bytesAvailable();
        if (!jobs.isEmpty() && avail >= 0 && avail - total < kMinFreeBytes)
            r.fatal = QStringLiteral("本体の空きが足りないので取り込みませんでした(空き %1、取り込み %2)").arg(sizeText(avail), sizeText(total));

        int counter = 0;
        if (r.fatal.isEmpty()) {
            for (const Job &j : std::as_const(jobs)) {
                if (cancel_.load()) break;
                const QString destDir = j.kind == kBackground ? bgDir : decoDir;
                QDir().mkpath(destDir);
                // 取り込み先の一覧(ThemeSettings)は拡張子を小文字か大文字で探すので、拡張子は小文字にそろえる
                const QFileInfo nf(j.name);
                const QString base = nf.completeBaseName(), ext = nf.suffix().toLower();
                QString dest = QStringLiteral("%1/%2.%3").arg(destDir, base, ext);
                bool same = false;
                // 同じ名前があるとき: 同じ中身なら飛ばし、別の画像なら _2, _3 … を付ける
                for (int n = 2; QFileInfo::exists(dest); ++n) {
                    if (sameContent(j.src, dest)) { same = true; break; }
                    if (n > 999) { dest.clear(); break; }
                    dest = QStringLiteral("%1/%2_%3.%4").arg(destDir, base).arg(n).arg(ext);
                }
                if (same) { ++r.same; continue; }
                if (dest.isEmpty()) { ++r.failed; continue; }
                const QString tmp = QStringLiteral("%1/.oc-import-%2-%3.part").arg(destDir).arg(QCoreApplication::applicationPid()).arg(++counter);
                const QString err = copyFile(j.src, dest, tmp, cancel_);
                if (err.isEmpty()) {
                    (j.kind == kBackground ? r.bg : r.deco)++;
                    r.logs << QStringLiteral("imported %1 -> %2").arg(j.src, dest);
                } else {
                    ++r.failed;
                    r.logs << QStringLiteral("failed %1: %2").arg(j.src, err);
                }
            }
        }

        QMetaObject::invokeMethod(this, [this, r]() {
            for (const QString &l : r.logs) log::info("IMPORT", l);
            if (!r.fatal.isEmpty()) log::warn("IMPORT", r.fatal);
            QStringList parts;
            if (r.bg > 0) parts << QStringLiteral("背景に %1 枚").arg(r.bg);
            if (r.deco > 0) parts << QStringLiteral("飾りに %1 枚").arg(r.deco);
            QString msg;
            if (!r.fatal.isEmpty()) {
                msg = r.fatal;
            } else {
                msg = parts.isEmpty() ? QStringLiteral("取り込んだ画像はありません") : parts.join(QStringLiteral("、")) + QStringLiteral(" 取り込みました");
                QStringList notes;
                if (r.same > 0) notes << QStringLiteral("%1 枚は同じ画像が入っているので飛ばしました").arg(r.same);
                if (r.skipped > 0) notes << QStringLiteral("%1 枚は取り込めない画像(行き先が決まらない・大きすぎる・読めない)なので飛ばしました").arg(r.skipped);
                if (r.failed > 0) notes << QStringLiteral("%1 枚は失敗しました").arg(r.failed);
                if (!notes.isEmpty()) msg += QStringLiteral("(") + notes.join(QStringLiteral(" / ")) + QStringLiteral(")");
            }
            setBusy(false, false);
            setMessage(msg);
            if (r.bg > 0) emit imported(kBackground, r.bg);
            if (r.deco > 0) emit imported(kDecoration, r.deco);
        }, Qt::QueuedConnection);
    });
}

} // namespace opencruise
