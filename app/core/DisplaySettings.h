/**
 * @file DisplaySettings.h
 * @brief 画面の出力先(外部画面)と描画の設定。設定「表示」の「画面」「描画」が使う。
 *
 * すぐ反映される設定:
 *   - 表示する画面: 「自動(メイン画面)」「自動(外部画面があれば外部画面)」か、接続されている画面(QScreen)から選ぶ。
 *     画面は名前(HDMI-A-1 など)で保存し、その画面が外れている間はメイン画面に出し、再接続されたら戻す
 *     (Main.qml が screen を切り替える)。既定は「外部画面があれば外部画面」で、起動時に外部画面が
 *     つながっていれば自動でそちらに出し、途中で抜き差ししても追従する。
 *     外部画面の判定: 内蔵パネルらしい接続名(eDP / LVDS / DSI など)の画面があればそれ以外の画面、
 *     無ければメイン画面以外の画面
 *   - 画面の回転: 0 / 90 / 180 / 270°(Main.qml が表示全体を回す。タッチ座標も回転に合わせて変換される)
 *   - 全部の画面に表示(ミラー): 操作する画面(上の「表示する画面」)以外の、つながっているすべての画面にも
 *     同じ表示を映す。Main.qml が画面ごとに全画面のウィンドウを作り、表示内容を mirrorFps 回/秒で写す。
 *     ミラー側は見るだけ(タッチ・マウスは受けない)。方式を「OS」にすると、OS の複製表示(xrandr など。
 *     OsDisplayMirror)を使い、アプリの描画負荷は増えない(使えない環境ではアプリ内の方式で映す)
 * 再起動で反映される設定(ウィンドウを作る前にしか変えられないため。applyStartupSettings() で適用する):
 *   - 描画方式: 自動 / OpenGL / Vulkan / ソフトウェア
 *   - 垂直同期: オン / オフ
 *   - フレームレート: 画面のリフレッシュレートどおり / 1/2 / 1/3(垂直同期の間隔を広げて間引く)
 * QML へは context property `displaySettings` として公開する。
 */
#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

#include "OsDisplayMirror.h"

namespace opencruise {

/**
 * @brief 画面の出力先と描画の設定(QSettings に保存)。UI スレッド専用。
 */
class DisplaySettings : public QObject {
    Q_OBJECT
    // ---- 表示する画面 ----
    /// 選択肢の表示名。先頭 2 つは「自動(メイン画面)」「自動(外部画面があれば外部画面)」、以降は接続中の画面
    /// (保存した画面が外れていれば末尾に「未接続」で残す)
    Q_PROPERTY(QStringList screenNames READ screenNames NOTIFY screensChanged)
    /// screenNames の中の選択位置
    Q_PROPERTY(int screenIndex READ screenIndex WRITE setScreenIndex NOTIFY screensChanged)
    /// 実際に出す画面の名前(QScreen::name)。保存した画面が無ければメイン画面
    Q_PROPERTY(QString targetScreenName READ targetScreenName NOTIFY screensChanged)
    /// 保存した画面が見つからず、メイン画面に出しているか
    Q_PROPERTY(bool usingFallback READ usingFallback NOTIFY screensChanged)
    /// 外部画面がつながっているか(「外部画面があれば外部画面」の判定と同じ)
    Q_PROPERTY(bool externalConnected READ externalConnected NOTIFY screensChanged)
    // ---- 回転(すぐ反映) ----
    Q_PROPERTY(int rotation READ rotation WRITE setRotation NOTIFY rotationChanged)
    // ---- ミラー(すぐ反映) ----
    Q_PROPERTY(bool mirrorAll READ mirrorAll WRITE setMirrorAll NOTIFY mirrorChanged)
    /// ミラーの更新回数 [回/秒](15 / 30 / 60)。アプリ内のミラーのときだけ使う
    Q_PROPERTY(int mirrorFps READ mirrorFps WRITE setMirrorFps NOTIFY mirrorChanged)
    /// ミラーの方式。0: アプリ内(表示を写して貼る) / 1: OS の複製表示(OsDisplayMirror)
    Q_PROPERTY(int mirrorMethod READ mirrorMethod WRITE setMirrorMethod NOTIFY mirrorChanged)
    /// アプリ内のミラーを動かすか(全部の画面に表示 かつ 方式がアプリ内、または OS の方式が使えないとき)
    Q_PROPERTY(bool appMirrorActive READ appMirrorActive NOTIFY mirrorChanged)
    Q_PROPERTY(bool osMirrorSupported READ osMirrorSupported CONSTANT)
    Q_PROPERTY(QString osMirrorBackend READ osMirrorBackend CONSTANT)
    Q_PROPERTY(QString osMirrorStatus READ osMirrorStatus NOTIFY mirrorChanged)
    /// eglfs で動いているか(画面を自動でミラーし、接続が変わると再起動する)
    Q_PROPERTY(bool isEglfs READ isEglfs CONSTANT)
    /// eglfs で画面の接続が変わったら、自動で再起動して反映するか
    Q_PROPERTY(bool autoRestartOnDisplayChange READ autoRestartOnDisplayChange WRITE setAutoRestartOnDisplayChange NOTIFY mirrorChanged)
    /// 画面の接続が変わったので再起動したい(eglfs の自動ミラー中で、自動再起動がオン)。Main.qml が見て再起動する
    Q_PROPERTY(bool displaysChangedRestart READ displaysChangedRestart NOTIFY mirrorChanged)
    // ---- 描画(再起動で反映) ----
    /// 0: 自動 / 1: OpenGL / 2: Vulkan / 3: ソフトウェア
    Q_PROPERTY(int graphicsApi READ graphicsApi WRITE setGraphicsApi NOTIFY renderingChanged)
    Q_PROPERTY(bool vsync READ vsync WRITE setVsync NOTIFY renderingChanged)
    /// 1: リフレッシュレートどおり / 2: 1/2 / 3: 1/3(垂直同期がオンのときだけ効く)
    Q_PROPERTY(int frameDivider READ frameDivider WRITE setFrameDivider NOTIFY renderingChanged)
    /// 描画の設定を変えて、まだ再起動していない
    Q_PROPERTY(bool restartRequired READ restartRequired NOTIFY renderingChanged)
    /// 今使っている描画方式(起動時に決まる)
    Q_PROPERTY(QString activeGraphicsApi READ activeGraphicsApi CONSTANT)
    /// 選んだ描画方式を使えず、別の方式にしたときの説明(問題が無ければ空)
    Q_PROPERTY(QString graphicsNote READ graphicsNote CONSTANT)
    /// Qt のプラットフォーム(xcb / wayland / eglfs など)
    Q_PROPERTY(QString platformName READ platformName CONSTANT)

public:
    explicit DisplaySettings(QObject *parent = nullptr);

    /**
     * @brief 保存されている描画の設定を、ウィンドウを作る前に適用する。
     *
     * QGuiApplication の生成後、QML(ウィンドウ)の読み込み前に 1 回だけ呼ぶこと。
     * 適用した内容は起動時の値として覚え、再起動が必要かの判定に使う。
     */
    static void applyStartupSettings();

    QStringList screenNames() const { return screenNames_; }
    int screenIndex() const { return screenIndex_; }
    void setScreenIndex(int index);
    QString targetScreenName() const { return targetScreenName_; }
    bool usingFallback() const { return usingFallback_; }
    bool externalConnected() const { return externalConnected_; }

    int rotation() const { return rotation_; }
    void setRotation(int degrees);
    bool mirrorAll() const { return mirrorAll_; }
    void setMirrorAll(bool on);
    int mirrorFps() const { return mirrorFps_; }
    void setMirrorFps(int fps);
    int mirrorMethod() const { return mirrorMethod_; }
    void setMirrorMethod(int method);
    bool appMirrorActive() const;
    bool osMirrorSupported() const { return osMirror_.supported(); }
    QString osMirrorBackend() const { return osMirror_.backendName(); }
    QString osMirrorStatus() const { return osMirror_.status(); }
    bool isEglfs() const;
    bool autoRestartOnDisplayChange() const { return autoRestart_; }
    void setAutoRestartOnDisplayChange(bool on);
    bool displaysChangedRestart() const;

    int graphicsApi() const { return graphicsApi_; }
    void setGraphicsApi(int api);
    bool vsync() const { return vsync_; }
    void setVsync(bool on);
    int frameDivider() const { return frameDivider_; }
    void setFrameDivider(int divider);
    bool restartRequired() const;
    QString activeGraphicsApi() const;
    QString platformName() const;
    QString graphicsNote() const;

    /** @brief 同じ引数でアプリを起動し直す(描画の設定を反映するため)。 */
    Q_INVOKABLE void restartApp();

signals:
    void screensChanged();
    void rotationChanged();
    void mirrorChanged();
    void renderingChanged();

private:
    /** @brief 接続中の画面から選択肢と、実際に出す画面を作り直す。 */
    void rebuildScreens();
    /** @brief OS のミラーへ、今の設定と画面を伝える(変わっていなければ何もしない)。 */
    void updateOsMirror();

    QString savedScreen_;          ///< 保存した画面の名前(空 = メイン画面、"@external" = 外部画面を優先)
    QStringList screenIds_;        ///< screenNames_ と同じ並びの画面名(先頭は空 = 自動)
    QStringList screenNames_;
    int screenIndex_ = 0;
    QString targetScreenName_;
    bool usingFallback_ = false;
    bool externalConnected_ = false;
    int rotation_ = 0;
    bool mirrorAll_ = true;
    int mirrorFps_ = 30;
    int mirrorMethod_ = 0;
    bool autoRestart_ = true;
    OsDisplayMirror osMirror_;   ///< OS の複製表示(ミラーを解除するため、DisplaySettings と同じ寿命)
    int graphicsApi_ = 0;
    bool vsync_ = true;
    int frameDivider_ = 1;
};

} // namespace opencruise
