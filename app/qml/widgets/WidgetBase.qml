// すべてのウィジェットの土台。ウィジェットは WidgetBase を継承し、中身(子要素)だけを書けばよい。
//   WidgetBase {
//       framed: true                       // カード背景を描くか
//       doubleTapAction: "settings"        // ダブルタップの動作: "settings"(設定画面) / "custom"(doubleTapped を使う) / "none"
//       Text { text: config.title }        // 子要素はこの中に置かれる(余白なし・全面)
//   }
// 値の受け渡し:
//   config   … 設定値(WidgetRegistry の defaultConfig に保存値を重ねたもの)。WidgetHost が注入する
//   lifting  … ドラッグで持ち上げ中か。WidgetHost が注入する(重い更新を止めたい場合などに使える)
//   gridW / gridH … グリッド上のマス数。WidgetHost(設定画面のプレビューでは WidgetSettingsDialog)が注入する
// 見出し(上部タイトル)は titleFontSize / titleBarHeight を使う。大きさはマス数で 3 段階に固定され、
// ウィジェットを大きくしても見出しだけが巨大化しない(短辺 1 マス=小 / 2 マス=中 / 3 マス以上=大)。
// 操作:
//   tapped()        … 1 回タップ(ウィジェット自身の操作を作りたいときに受ける)
//   doubleTapped()  … doubleTapAction が "custom" のときだけ呼ばれる
// ウィジェット内に独自の MouseArea を置くとドラッグ(長押し)より優先される。その範囲では移動を始められないので、
// 小さい操作部品だけに置くこと。
import QtQuick
import OpenCruise

Item {
    id: root

    // ---- WidgetHost が注入する ----
    property var config: ({})
    property bool lifting: false
    property int gridW: 3
    property int gridH: 3
    readonly property bool titleVisible: config.showTitle !== false

    function titleText(fallback) {
        const custom = String(config.titleText || "").trim()
        return custom !== "" ? custom : fallback
    }

    // ---- 継承側が決める ----
    property bool framed: true
    property string doubleTapAction: "settings"
    // ---- 見出し(上部タイトル)の大きさ。短辺のマス数で 3 段階(1 / 2 / 3 以上は同じ) ----
    readonly property int titleTier: Math.max(1, Math.min(3, Math.min(gridW, gridH)))
    readonly property real titleFontSize: Math.max(11, Math.round([15, 18, 21][titleTier - 1] * Theme.uiScale))
    readonly property real titleBarHeight: Math.round(titleFontSize * 1.35)
    // ウィジェット共通の文字階層。個別の値表示・大見出しは各ウィジェット側で調整する。
    // headerFontSize は見出し用(titleFontSize と同じ。既存ウィジェットとの互換のため残す)
    readonly property real headerFontSize: titleFontSize
    readonly property real bodyFontSize: Math.max(12, Math.min(s * 0.075, 22))
    readonly property real detailFontSize: Math.max(11, Math.min(s * 0.065, 18))
    signal tapped()
    signal doubleTapped()

    // 画面サイズに合わせた寸法の基準(短辺)
    readonly property real s: Math.min(width, height)

    default property alias content: slot.data

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius + 6
        color: Theme.panel
        border.color: Theme.panelBorder
        opacity: root.framed ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    Item {
        id: slot
        anchors.fill: parent
    }
}
