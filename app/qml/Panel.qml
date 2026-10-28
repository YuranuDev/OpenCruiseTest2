// テーマに合わせて描く面(カード・ボタン・ダイアログの土台)。Rectangle の代わりに使う。
//  - シンプル: 平らな panel 色(これまでと同じ)
//  - クラシック: 上から下へのゆるいグラデーションと、縁の内側の細いハイライト(控えめな立体感)
// tint / tintAmount で、押したとき・選んだときの色を混ぜられる(color の代わり。グラデーションを使うので color は効かない)。
//   Panel { radius: Theme.radius + 6; tint: Theme.accent; tintAmount: pressed ? 0.35 : 0 }
import QtQuick

Rectangle {
    id: root
    property color tint: Theme.accent
    property real tintAmount: 0
    property bool bevel: true   // 内側のハイライトを描くか(クラシックのみ)

    color: Theme.panel
    border.width: 1
    border.color: Theme.panelBorder
    gradient: Gradient {
        GradientStop { position: 0.0; color: Theme.mix(Theme.panelTop, root.tint, root.tintAmount) }
        GradientStop { position: 1.0; color: Theme.mix(Theme.panelBottom, root.tint, root.tintAmount) }
    }

    // 内側のハイライト(クラシック)。シンプルでは透明なので描かない
    Rectangle {
        visible: root.bevel && Theme.classic
        anchors.fill: parent
        anchors.margins: root.border.width
        radius: Math.max(0, root.radius - root.border.width)
        color: "transparent"
        border.width: 1
        border.color: Theme.bevelLight
    }
}
