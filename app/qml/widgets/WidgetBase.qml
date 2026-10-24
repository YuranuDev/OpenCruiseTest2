// すべてのウィジェットの土台。ウィジェットは WidgetBase を継承し、中身(子要素)だけを書けばよい。
//   WidgetBase {
//       framed: true                       // カード背景を描くか
//       doubleTapAction: "settings"        // ダブルタップの動作: "settings"(設定画面) / "custom"(doubleTapped を使う) / "none"
//       Text { text: config.title }        // 子要素はこの中に置かれる(余白なし・全面)
//   }
// 値の受け渡し:
//   config   … 設定値(WidgetRegistry の defaultConfig に保存値を重ねたもの)。WidgetHost が注入する
//   lifting  … ドラッグで持ち上げ中か。WidgetHost が注入する(重い更新を止めたい場合などに使える)
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

    // ---- 継承側が決める ----
    property bool framed: true
    property string doubleTapAction: "settings"
    // ウィジェット共通の文字階層。個別の値表示・大見出しは各ウィジェット側で調整する。
    readonly property real headerFontSize: Math.max(13, Math.min(s * 0.085, 26))
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
