/**
 * @file DrmDisplay.h
 * @brief eglfs(DRM/KMS)での外部モニター管理: 操作する画面の選択と、外部モニターへのミラー(複製表示)。
 *
 * 仕組み:
 *   1. 起動前(prepare): /sys/class/drm から画面(コネクタ)を調べ、操作する画面だけを Qt に使わせる
 *      KMS 設定ファイル(QT_QPA_EGLFS_KMS_CONFIG)を作る。ほかの画面は "mode": "off" にして、Qt に触らせない。
 *   2. 起動後: Qt が開いている DRM の fd(このプロセスの /dev/dri/cardN のうち DRM マスターのもの)を見つけ、
 *      Qt の描画が終わるたびに、操作する画面が今表示している画(フレームバッファ)を、外部モニターにも表示する。
 *        - 同じ解像度があれば、その解像度で表示し、新しい画をページフリップで切り替える(拡大縮小なし)
 *        - 無ければ、外部モニターの推奨解像度で表示し、画面いっぱいに縦横比を保って拡大縮小する(プレーンで表示)
 *   3. 画面の抜き差しは /sys/class/drm を見張り、外部モニターがつながったらすぐミラーを始める(再起動は不要)。
 *      操作する画面を変えたときだけ、再起動が必要(Qt が起動時に描画先を決めるため)。
 * Qt の描画には一切手を入れず、フレームバッファを外部モニター側でも読むだけなので、描画の負荷は増えない。
 * libdrm が無い環境でビルドしたとき、または eglfs 以外では何もしない(supported / active が false)。
 * QML へは context property `drmDisplay` として公開する。
 */
#pragma once

#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVariantList>

#include <memory>

class QQuickWindow;

namespace opencruise {

class DrmDisplay : public QObject {
    Q_OBJECT
    /// このビルドが DRM のミラーに対応しているか(libdrm ありでビルドされたか)
    Q_PROPERTY(bool supported READ supported CONSTANT)
    /// eglfs で動いていて、DRM を操作できるか
    Q_PROPERTY(bool active READ active NOTIFY changed)
    /// 状態の説明(設定画面に出す)
    Q_PROPERTY(QString statusText READ statusText NOTIFY changed)
    /// 画面(コネクタ)の一覧。{ name, connected, role, detail } の配列
    Q_PROPERTY(QVariantList outputs READ outputs NOTIFY changed)
    /// 操作する画面の選択肢。先頭は「自動(内蔵パネル)」
    Q_PROPERTY(QStringList mainChoices READ mainChoices NOTIFY changed)
    Q_PROPERTY(int mainChoiceIndex READ mainChoiceIndex WRITE setMainChoiceIndex NOTIFY changed)
    /// 今、操作する画面として使っている画面(起動時に決まる)
    Q_PROPERTY(QString mainOutput READ mainOutput CONSTANT)
    /// 外部モニターへミラーするか(すぐ反映)
    Q_PROPERTY(bool mirrorEnabled READ mirrorEnabled WRITE setMirrorEnabled NOTIFY changed)
    /// 0: 同じ解像度を優先(無ければ拡大縮小) / 1: 外部モニターの推奨解像度で拡大縮小
    Q_PROPERTY(int scaleMode READ scaleMode WRITE setScaleMode NOTIFY changed)
    /// 操作する画面の変更を反映するには再起動が必要か
    Q_PROPERTY(bool restartRequired READ restartRequired NOTIFY changed)

public:
    /**
     * @brief QGuiApplication を作る前に呼ぶ。eglfs で起動するときだけ、KMS 設定ファイルを作って環境変数に設定する。
     * ログ基盤はまだ無いので、結果は覚えておき、DrmDisplay を作ったときにログへ出す。
     */
    static void prepare(int argc, char *argv[]);

    explicit DrmDisplay(QObject *parent = nullptr);
    ~DrmDisplay() override;

    /** @brief 描画するウィンドウを渡す。描画が終わるたびにミラーを更新する。 */
    void attach(QQuickWindow *window);
    /** @brief ミラーをやめ、外部モニターの表示を消す(終了時に呼ぶ。Qt が DRM を閉じる前に)。 */
    Q_INVOKABLE void stop();

    bool supported() const;
    bool active() const { return active_; }
    QString statusText() const { return status_; }
    QVariantList outputs() const;
    QStringList mainChoices() const;
    int mainChoiceIndex() const;
    void setMainChoiceIndex(int index);
    QString mainOutput() const;
    bool mirrorEnabled() const { return mirrorEnabled_; }
    void setMirrorEnabled(bool on);
    int scaleMode() const { return scaleMode_; }
    void setScaleMode(int mode);
    bool restartRequired() const;

signals:
    void changed();

private:
    struct Private;

    void poll();        ///< 画面の抜き差しを調べ、ミラーを始める・やめる
    void onFrame();     ///< 描画が終わったとき: 外部モニターの画を更新する
    void setStatus(const QString &text);

    std::unique_ptr<Private> d_;
    QPointer<QQuickWindow> window_;
    QTimer pollTimer_;
    bool active_ = false;
    bool mirrorEnabled_ = true;
    int scaleMode_ = 0;
    QString savedMain_;   ///< 保存した「操作する画面」(空 = 自動)
    QString status_;
};

} // namespace opencruise
