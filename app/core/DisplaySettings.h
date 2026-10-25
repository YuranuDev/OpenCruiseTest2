/**
 * @file DisplaySettings.h
 * @brief 画面の出力先と描画の設定。設定「表示」の「画面」「描画」が使う。
 *
 * すぐ反映される設定:
 *   - 表示する画面(eglfs 以外): 「自動(メイン画面)」「自動(外部画面があれば外部画面)」か、接続中の画面(QScreen)を選ぶ。
 *     画面は名前(HDMI-A-1 など)で保存し、その画面が外れている間はメイン画面に出し、再接続されたら戻す
 *     (Main.qml が screen を切り替える)。外部画面の判定: 内蔵パネルらしい接続名(eDP / LVDS / DSI / DPI)の画面が
 *     あればそれ以外の画面、無ければメイン画面以外の画面。
 *     eglfs(DRM/KMS)では、操作する画面と外部モニターへのミラーは DrmDisplay が受け持つ。
 *   - 画面の回転: 0 / 90 / 180 / 270°(Main.qml が表示全体を回す。タッチ座標も回転に合わせて変換される)
 * 再起動で反映される設定(ウィンドウを作る前にしか変えられないため。applyStartupSettings() で適用する):
 *   - 描画方式: 自動 / OpenGL / Vulkan / ソフトウェア(Vulkan が使えない環境では OpenGL にする)
 *   - 垂直同期: オン / オフ
 *   - フレームレート: 画面のリフレッシュレートどおり / 1/2 / 1/3(垂直同期の間隔を広げて間引く)
 * QML へは context property `displaySettings` として公開する。
 */
#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

namespace opencruise {

/**
 * @brief 画面の出力先と描画の設定(QSettings に保存)。UI スレッド専用。
 */
class DisplaySettings : public QObject {
    Q_OBJECT
    // ---- 表示する画面(eglfs 以外) ----
    /// 選択肢の表示名。先頭 2 つは「自動(メイン画面)」「自動(外部画面があれば外部画面)」、以降は接続中の画面
    Q_PROPERTY(QStringList screenNames READ screenNames NOTIFY screensChanged)
    Q_PROPERTY(int screenIndex READ screenIndex WRITE setScreenIndex NOTIFY screensChanged)
    /// 実際に出す画面の名前(QScreen::name)
    Q_PROPERTY(QString targetScreenName READ targetScreenName NOTIFY screensChanged)
    /// 選んだ画面が見つからず、メイン画面に出しているか
    Q_PROPERTY(bool usingFallback READ usingFallback NOTIFY screensChanged)
    /// 外部画面がつながっているか
    Q_PROPERTY(bool externalConnected READ externalConnected NOTIFY screensChanged)
    // ---- 回転(すぐ反映) ----
    Q_PROPERTY(int rotation READ rotation WRITE setRotation NOTIFY rotationChanged)
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
    /// eglfs(DRM/KMS で直接表示)で動いているか
    Q_PROPERTY(bool isEglfs READ isEglfs CONSTANT)

public:
    explicit DisplaySettings(QObject *parent = nullptr);

    /**
     * @brief 保存されている描画の設定を、ウィンドウを作る前に適用する。
     * QGuiApplication の生成後、QML(ウィンドウ)の読み込み前に 1 回だけ呼ぶこと。
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

    int graphicsApi() const { return graphicsApi_; }
    void setGraphicsApi(int api);
    bool vsync() const { return vsync_; }
    void setVsync(bool on);
    int frameDivider() const { return frameDivider_; }
    void setFrameDivider(int divider);
    bool restartRequired() const;
    QString activeGraphicsApi() const;
    QString graphicsNote() const;
    QString platformName() const;
    bool isEglfs() const;

    /** @brief 同じ引数でアプリを起動し直す(描画や画面の設定を反映するため)。 */
    Q_INVOKABLE void restartApp();

signals:
    void screensChanged();
    void rotationChanged();
    void renderingChanged();

private:
    /** @brief 接続中の画面から選択肢と、実際に出す画面を作り直す。 */
    void rebuildScreens();

    QString savedScreen_;          ///< 保存した画面の名前(空 = メイン画面、"@external" = 外部画面を優先)
    QStringList screenIds_;        ///< screenNames_ と同じ並びの画面名
    QStringList screenNames_;
    int screenIndex_ = 0;
    QString targetScreenName_;
    bool usingFallback_ = false;
    bool externalConnected_ = false;
    int rotation_ = 0;
    int graphicsApi_ = 0;
    bool vsync_ = true;
    int frameDivider_ = 1;
};

} // namespace opencruise
