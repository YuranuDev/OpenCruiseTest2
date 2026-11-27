/**
 * @file ImageImporter.h
 * @brief USB メモリなどにある画像(PNG / JPEG / WebP / GIF)を、本体の背景・飾りのフォルダへ取り込む。
 *        QML へは context property `imageImporter` として公開する(設定 > テーマ・背景 の「USB メモリから画像を取り込む」)。
 *
 * 探す場所: UpdateManager と同じ /run/opencruise-usb/<デバイス>/(opencruise-usb-mount が読み取り専用でつなぐ。
 *   環境変数 OPENCRUISE_USB_DIR で変えられる)。直下から 3 階層目までの画像を候補にする(最大 kMaxCandidates 枚)。
 * 取り込み先: ThemeSettings の backgroundFolder / decorationFolder(~/.local/share/OpenCruise/backgrounds, decorations)。
 *   USB メモリは読み取り専用でつなぐ(更新ファイルを守るため)ので、元のファイルは消せない。「移動」ではなくコピーになる。
 * フォルダ名での振り分け: USB メモリの中のフォルダ名が backgrounds / background なら背景、decorations / decoration なら飾り
 *   (kind = "auto" のとき、この名前で振り分ける。どちらでもない画像は飛ばす)。
 *
 * アップデートとの関係(UpdateManager):
 *   - 取り込み先(~/.local/share/OpenCruise)は更新の置き場(/home/opencruise/app)と別なので、更新・ロールバックで画像は消えない
 *   - USB のマウント(opencruise-usb-mount)は読み取り専用のまま。更新ファイル(.ocapp)の探索・展開とは読み取り同士で競合しない
 *   - 更新の開始・再起動は、コピー中(importing)は QML 側で止める(SettingsPageUpdate)。再起動などで途中で止まっても、
 *     コピーは一時ファイル(.oc-import-*.part)に書いて最後に名前を付けるので、中途半端な画像は残らない(次の起動で一時ファイルを消す)
 *   - 本体の空きが少ないと更新の展開に失敗するので、取り込み後の空きが kMinFreeBytes を下回るときは取り込まない
 */
#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVariantList>

#include <atomic>
#include <functional>

class QThread;

namespace opencruise {

class ImageImporter : public QObject {
    Q_OBJECT
    /// USB メモリがつながっているか
    Q_PROPERTY(bool usbPresent READ usbPresent NOTIFY candidatesChanged)
    /// 見つかった画像: [{ path, file, device, folder, size, suggested("background" / "decoration" / "") }](フォルダ・ファイル名順)
    Q_PROPERTY(QVariantList candidates READ candidates NOTIFY candidatesChanged)
    /// 候補に入りきらなかった画像の数(0 なら全部入っている)
    Q_PROPERTY(int omitted READ omitted NOTIFY candidatesChanged)
    /// USB メモリを探している間
    Q_PROPERTY(bool scanning READ scanning NOTIFY busyChanged)
    /// コピーしている間(この間は更新の開始・再起動をしない)
    Q_PROPERTY(bool importing READ importing NOTIFY busyChanged)
    /// 直近の取り込みの結果の文
    Q_PROPERTY(QString message READ message NOTIFY messageChanged)

public:
    static constexpr int kMaxCandidates = 200;                    ///< 候補の最大数(多すぎると一覧が重い)
    static constexpr int kMaxDepth = 3;                           ///< 探すフォルダの深さ(デバイスの直下を 0 として)
    static constexpr qint64 kMaxFileBytes = 32LL * 1024 * 1024;   ///< 1 枚の最大サイズ
    static constexpr int kMaxPixels = 8192;                       ///< 縦横の最大(メモリを使いすぎないように)
    static constexpr qint64 kMinFreeBytes = 256LL * 1024 * 1024;  ///< 取り込んだあとに残す空き

    ImageImporter(const QString &backgroundDir, const QString &decorationDir, QObject *parent = nullptr);
    ~ImageImporter() override;

    bool usbPresent() const { return usbPresent_; }
    QVariantList candidates() const { return candidates_; }
    int omitted() const { return omitted_; }
    bool scanning() const { return scanning_; }
    bool importing() const { return importing_; }
    QString message() const { return message_; }

    /** @brief USB メモリの画像を探し直す(設定画面を開いたとき・「探し直す」ボタン)。コピー中は何もしない。 */
    Q_INVOKABLE void rescan();
    /**
     * @brief 候補の画像をコピーする。
     * @param paths 候補の path(USB のマウント先の中のファイルだけ受け付ける)
     * @param kind  "background"(背景へ)/ "decoration"(飾りへ)/ "auto"(フォルダ名で振り分け。振り分けられないものは飛ばす)
     */
    Q_INVOKABLE void importFiles(const QStringList &paths, const QString &kind);

signals:
    void candidatesChanged();
    void busyChanged();
    void messageChanged();
    /// 1 種類の取り込みが終わった(count 枚コピーした。kind は "background" / "decoration")。ThemeSettings の読み直しに使う
    void imported(const QString &kind, int count);

private:
    void startWorker(std::function<void()> fn);
    void setMessage(const QString &text);
    void setBusy(bool scanning, bool importing);
    void cleanStaleParts() const;

    QString usbDir_;
    QString backgroundDir_;
    QString decorationDir_;
    QFileSystemWatcher usbWatcher_;
    QTimer usbRescan_;
    QThread *thread_ = nullptr;
    std::atomic_bool cancel_{false};

    bool usbPresent_ = false;
    QVariantList candidates_;
    int omitted_ = 0;
    bool scanning_ = false;
    bool importing_ = false;
    QString message_;
};

} // namespace opencruise
