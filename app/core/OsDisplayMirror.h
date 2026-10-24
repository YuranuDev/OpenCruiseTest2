/**
 * @file OsDisplayMirror.h
 * @brief OS の機能で画面を複製表示(ミラー)する。DisplaySettings が「ミラーの方式 = OS」のときに使う。
 *
 * アプリ内のミラー(表示を画像に写して別ウィンドウへ貼る)と違い、OS(ディスプレイサーバー / KMS)が同じ画を
 * 複数の画面へ出すので、アプリの描画負荷は増えない。対応する環境:
 *   - X11(xcb)          : xrandr --output <画面> --same-as <操作する画面> --scale-from <解像度>
 *                          (解像度が違う画面は、操作する画面の解像度に合わせて拡大・縮小する)
 *   - KDE Plasma(Wayland): kscreen-doctor output.<画面>.mirror.<操作する画面>(Plasma 6 以降)
 *   - eglfs(KMS)         : 起動前に QT_QPA_EGLFS_KMS_CONFIG の設定ファイル("clone")を作る。再起動で反映
 * それ以外(GNOME の Wayland など)は、外から設定を変える手段が無いので非対応(アプリ内のミラーを使う)。
 * X11 / KDE では、アプリの終了時に、このクラスがミラーにした画面を元の並び(横に拡張)へ戻す。
 */
#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

namespace opencruise {

/**
 * @brief OS の機能による画面の複製表示。UI スレッド専用。
 */
class OsDisplayMirror : public QObject {
    Q_OBJECT

public:
    enum class Backend { None, Xrandr, KScreen, Eglfs };

    explicit OsDisplayMirror(QObject *parent = nullptr);
    /** @brief ミラーにした画面を元に戻す(X11 / KDE)。 */
    ~OsDisplayMirror() override;

    /**
     * @brief eglfs で起動するときだけ、QGuiApplication を作る前に呼ぶ。
     *
     * 保存されている設定が「全部の画面に表示 + OS のミラー」で、QT_QPA_EGLFS_KMS_CONFIG が未設定なら、
     * 接続中の画面(/sys/class/drm)から複製の設定ファイルを作り、環境変数に設定する。
     * ログ基盤はまだ無いので、結果は startupNote() に残し、あとでログへ出す。
     */
    static void prepareEglfs(int argc, char *argv[]);
    /** @brief prepareEglfs() の結果(何もしなかったときは空)。 */
    static QString startupNote();

    Backend backend() const { return backend_; }
    /** @brief 使える方式の名前(xrandr / kscreen-doctor / eglfs(KMS))。非対応なら空。 */
    QString backendName() const;
    bool supported() const { return backend_ != Backend::None; }
    /** @brief 今の状態の説明(設定画面に出す)。 */
    QString status() const { return status_; }

    /**
     * @brief ミラーの有無と、操作する画面を指定する。前回と同じ指定なら何もしない(画面の抜き差しで呼ばれても安全)。
     * @param on true ならミラーにする。false なら、このクラスがミラーにした画面を元に戻す
     * @param target 操作する画面の名前(QScreen::name)
     * @param screens 接続中の画面の名前(QScreen::name)
     */
    void update(bool on, const QString &target, const QStringList &screens);

signals:
    void statusChanged();

private:
    void apply(const QString &target, const QStringList &screens);
    void restore();
    void setStatus(const QString &text);
    /** @brief コマンドを実行して終わるまで待つ(最大 5 秒)。失敗したら error に理由を入れて false。 */
    static bool run(const QString &program, const QStringList &args, QString *output, QString *error);

    Backend backend_ = Backend::None;
    QString program_;          ///< xrandr / kscreen-doctor の場所
    bool on_ = false;
    QString target_;
    QStringList mirrored_;     ///< このクラスがミラーにした画面(元に戻す対象)
    QString appliedKey_;       ///< 前回適用した指定(同じなら再適用しない)
    QString status_;
};

} // namespace opencruise
