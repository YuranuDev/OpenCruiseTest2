// 画面全体で共有する色・サイズ（シングルトン）。昼夜 2 つの配色を nightLevel(0..1) で補間する。
// 切り替えは一度で行う(色をアニメーションさせると、色を使うすべての部品が毎フレーム計算し直し・描き直しになって重い)。
// 見た目の滑らかさは、Main.qml が切り替え前の画面を 1 枚の画像にして重ね、それを薄くしていくことで出す。
pragma Singleton
import QtQuick

QtObject {
    // ---- Main.qml から Binding で受け取る状態 ----
    property bool night: true
    property int accentIndex: 0
    // 表示フォントのファミリ名(AppSettings から Main.qml の Binding で受け取る)。通常のテキストは font.family にこれを指定する
    property string fontFamily: Qt.application.font.family
    // 画面サイズに応じた拡大率(Main.qml から Binding で受け取る。1280x720 で 1.0、小さい画面でも 0.6 まで)。設定画面などが寸法に掛ける
    property real uiScale: 1.0

    // アクセント色のプリセット（設定画面の選択肢）
    readonly property var accentPresets: ["#4da3ff", "#3ddc84", "#ffa040", "#ff6fa5", "#a78bfa", "#2dd4d4"]

    // 昼夜の補間係数(0 = 昼 / 1 = 夜)
    readonly property real nightLevel: night ? 1 : 0

    // アクセント色の元色
    readonly property color accentBase: accentPresets[Math.min(accentIndex, accentPresets.length - 1)]

    function mix(a, b, t) {
        var ca = Qt.color(a)
        var cb = Qt.color(b)
        return Qt.rgba(ca.r + (cb.r - ca.r) * t, ca.g + (cb.g - ca.g) * t,
                       ca.b + (cb.b - ca.b) * t, ca.a + (cb.a - ca.a) * t)
    }

    //                                   昼          夜
    readonly property color background:    mix("#eef1f6", "#0d1015", nightLevel)
    readonly property color panel:         mix("#ffffff", "#161b23", nightLevel)
    readonly property color panelBorder:   mix("#d3d9e2", "#252c37", nightLevel)
    readonly property color textPrimary:   mix("#1b2330", "#e8ebf0", nightLevel)
    readonly property color textSecondary: mix("#5d6878", "#8c95a3", nightLevel)
    // 昼は明るい背景で見やすいよう、アクセント色を少し暗くする
    readonly property color accent:        mix(mix(accentBase, "#000000", 0.25), accentBase, nightLevel)
    // ボタンの塗りなど面に使うアクセント色。accent(文字・アイコン用)と違い、昼は白寄りに明るく(30%)、夜は少し暗く(20%)する
    readonly property color accentFill:    mix(mix(accentBase, "#ffffff", 0.3), mix(accentBase, "#000000", 0.2), nightLevel)
    // accentFill の上に載せる文字・アイコンの色(昼夜とも中〜明るい塗りなので暗い色)
    readonly property color textOnAccent:      "#0d1015"
    readonly property color ok:            mix("#1fa95b", "#3ddc84", nightLevel)
    readonly property color warn:          mix("#d98200", "#ffb74d", nightLevel)
    readonly property color error:         mix("#d93636", "#ff5c5c", nightLevel)
    readonly property int radius: 14
    readonly property int margin: 16

    // 接続状態キーに対応する表示色
    function stateColor(key) {
        switch (key) {
        case "streaming": return ok
        case "connected": return accent
        case "connecting": return accent
        case "waiting": return warn
        default: return error
        }
    }
}
