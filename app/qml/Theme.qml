// 画面全体で共有する色・サイズ（シングルトン）。昼夜 2 つの配色を nightLevel(0..1) で補間する。
// テーマ(style。設定「表示 > テーマ」。themeSettings から Main.qml が渡す)で配色と形が変わる:
//  - simple(シンプル): これまでの見た目。平らな面・大きめの角丸・青のアクセント
//  - classic(クラシック): 2000 年代ごろの車の内装に合わせた見た目。ガンメタ(夜)/シルバー(昼)の面に、上から下への
//    ゆるいグラデーションと内側の細いハイライト(控えめな立体感)、小さめの角丸、アンバー(オレンジ)の照明色。
//    アクセント色の選択肢も、当時のメーター照明の色(アンバー・赤・青・緑・アイボリー・シアン)になる
// 面は Panel.qml(グラデーションとハイライトを描く Rectangle)を使うと、テーマに合わせて描き分けられる。
// 切り替えは一度で行う(色をアニメーションさせると、色を使うすべての部品が毎フレーム計算し直し・描き直しになって重い)。
// 見た目の滑らかさは、Main.qml が切り替え前の画面を 1 枚の画像にして重ね、それを薄くしていくことで出す。
pragma Singleton
import QtQuick

QtObject {
    // ---- Main.qml から Binding で受け取る状態 ----
    property bool night: true
    property int accentIndex: 0
    // 自由に決めたアクセント色("#rrggbb")。空ならプリセット(accentIndex)を使う
    property string accentCustom: ""
    property string style: "simple"
    readonly property bool classic: style === "classic"
    // 表示フォントのファミリ名(AppSettings から Main.qml の Binding で受け取る)。通常のテキストは font.family にこれを指定する
    property string fontFamily: Qt.application.font.family
    // 数値(メーターの値・目盛り、グラフ、時計)に使うフォント。設定で「文章と同じ」なら fontFamily と同じ
    property string numberFontFamily: fontFamily
    // メーター・グラフの値を斜体にするか(設定の「数値を斜体にする」)
    property bool numberItalic: true
    // 画面サイズに応じた拡大率(Main.qml から Binding で受け取る。1280x720 で 1.0、小さい画面でも 0.6 まで)。設定画面などが寸法に掛ける
    property real uiScale: 1.0

    // アクセント色のプリセット（設定画面のパレットの選択肢）。保存するのは番号なので、先頭の 6 色の順番は変えない
    // (後ろへ足すだけ)。accentNames は同じ順の名前
    readonly property var accentPresets: classic
        ? ["#ff9a2e", "#ff5244", "#4fa8ff", "#78d35c", "#e9e2cf", "#35cfd6",
           "#f5cf47", "#b7dc4a", "#b48cff", "#ff7fa8", "#3fcf9b", "#f4f4f4"]
        : ["#4da3ff", "#3ddc84", "#ffa040", "#ff6fa5", "#a78bfa", "#2dd4d4",
           "#ff5a5f", "#ffd23f", "#a3e635", "#6c7bff", "#ff8a65", "#d5dae3"]
    readonly property var accentNames: classic
        ? ["アンバー", "レッド", "ブルー", "グリーン", "アイボリー", "シアン",
           "イエロー", "ライム", "パープル", "ピンク", "ミント", "ホワイト"]
        : ["ブルー", "グリーン", "オレンジ", "ピンク", "パープル", "ティール",
           "レッド", "イエロー", "ライム", "インディゴ", "コーラル", "シルバー"]

    // 昼夜の補間係数(0 = 昼 / 1 = 夜)
    readonly property real nightLevel: night ? 1 : 0

    // アクセント色の元色
    readonly property color accentBase: accentCustom !== "" ? accentCustom : accentPresets[Math.min(accentIndex, accentPresets.length - 1)]

    function mix(a, b, t) {
        var ca = Qt.color(a)
        var cb = Qt.color(b)
        return Qt.rgba(ca.r + (cb.r - ca.r) * t, ca.g + (cb.g - ca.g) * t,
                       ca.b + (cb.b - ca.b) * t, ca.a + (cb.a - ca.a) * t)
    }

    // テーマごとの配色(昼, 夜)。classic は少し暖かみのあるグレー(ガンメタ・シルバー)と、生成りの文字
    function pick(simpleDay, simpleNight, classicDay, classicNight) {
        return classic ? mix(classicDay, classicNight, nightLevel) : mix(simpleDay, simpleNight, nightLevel)
    }
    //                                         シンプル 昼  シンプル 夜  クラシック 昼  クラシック 夜
    readonly property color background:    pick("#eef1f6", "#0d1015", "#c6c9cd", "#0e0e0f")
    readonly property color panel:         pick("#ffffff", "#161b23", "#e7e9ec", "#1f2022")
    readonly property color panelBorder:   pick("#d3d9e2", "#252c37", "#a3a9b1", "#3a3c41")
    readonly property color textPrimary:   pick("#1b2330", "#e8ebf0", "#1b1d21", "#ede7db")
    readonly property color textSecondary: pick("#5d6878", "#8c95a3", "#525962", "#a49e93")
    // 面のグラデーション(上 → 下)と、内側のハイライト(縁の内側の細い明るい線)。シンプルは平ら(どちらも panel)
    readonly property color panelTop:      classic ? mix("#f6f7f8", "#2b2c30", nightLevel) : panel
    readonly property color panelBottom:   classic ? mix("#d6d9de", "#161719", nightLevel) : panel
    readonly property color bevelLight:    classic ? Qt.rgba(1, 1, 1, night ? 0.07 : 0.75) : "transparent"
    // 角の丸み(クラシックは控えめ)
    readonly property int radius: classic ? 6 : 14
    // 昼は明るい背景で見やすいよう、アクセント色を少し暗くする
    readonly property color accent:        mix(mix(accentBase, "#000000", 0.25), accentBase, nightLevel)
    // ボタンの塗りなど面に使うアクセント色。accent(文字・アイコン用)と違い、昼は白寄りに明るく(30%)、夜は少し暗く(20%)する
    readonly property color accentFill:    mix(mix(accentBase, "#ffffff", 0.3), mix(accentBase, "#000000", 0.2), nightLevel)
    // accentFill の上に載せる文字・アイコンの色(昼夜とも中〜明るい塗りなので暗い色)
    readonly property color textOnAccent:      "#0d1015"
    readonly property color ok:            mix("#1fa95b", "#3ddc84", nightLevel)
    readonly property color warn:          mix("#d98200", "#ffb74d", nightLevel)
    readonly property color error:         mix("#d93636", "#ff5c5c", nightLevel)
    // ---- 起動画面(SplashScreen)専用の固定配色 ----
    // Linux の起動画面(Plymouth)用の画像は、インストール時に 1 度だけ書き出す静止画。昼夜テーマ(時刻で自動切替)や
    // アクセント色に連動させると、書き出した時刻のテーマと起動した時刻のテーマが食い違い、色が合わなくなる。
    // そこで、起動画面は常にこの配色(夜の配色 + 既定のアクセント色)で描く。変える場合はここだけを直し、install.sh を再実行する。
    readonly property color bootBackground:    "#0d1015"
    readonly property color bootPanel:         "#161b23"
    readonly property color bootPanelBorder:   "#252c37"
    readonly property color bootTextPrimary:   "#e8ebf0"
    readonly property color bootTextSecondary: "#8c95a3"
    readonly property color bootAccent:        "#4da3ff"
    readonly property color bootTextOnAccent:  "#0d1015"
    readonly property color bootOk:            "#3ddc84"
    readonly property color bootWarn:          "#ffb74d"
    readonly property color bootError:         "#ff5c5c"
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
