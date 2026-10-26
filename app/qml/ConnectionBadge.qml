// Android Auto の接続状態を、アイコンだけの丸いバッジで表示する(文字は出さない)。
//   映像受信中: 再生中のスマホ(緑) / 接続処理中: つながりかけのスマホ(アクセント色) /
//   接続待ち: 未接続のスマホ(橙) / エラーなど: × 付きのスマホ(赤)
// 右下の小さな点も同じ色。タップすると、今の状態を文字で知らせる(通知)。size でバッジの直径を指定する。
import QtQuick

Rectangle {
    id: root
    property real size: 52
    readonly property string key: androidAuto.stateKey
    readonly property color stateColor: Theme.stateColor(key)
    readonly property string icon: key === "streaming" ? "mdi:cellphone-play"
                                  : (key === "connected" || key === "connecting") ? "mdi:cellphone-link"
                                  : key === "waiting" ? "mdi:cellphone-link-off"
                                  : "mdi:cellphone-remove"

    width: size
    height: size
    radius: size / 2
    color: Theme.mix(Theme.panel, stateColor, mouse.pressed ? 0.35 : 0.12)
    border.color: Theme.mix(Theme.panelBorder, stateColor, 0.6)
    border.width: 1

    MaterialIcon {
        anchors.centerIn: parent
        name: root.icon
        size: Math.round(root.size * 0.56)
        color: root.stateColor
    }

    // 状態の点(円周の右下 45° の位置)
    Rectangle {
        readonly property real d: Math.round(root.size * 0.26)
        width: d
        height: d
        radius: d / 2
        x: root.size * 0.854 - d / 2
        y: root.size * 0.854 - d / 2
        color: root.stateColor
        border.width: 2
        border.color: Theme.background
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        onClicked: notifications.show("Android Auto: " + androidAuto.stateText, androidAuto.detailText, 0, root.icon, 4000)
    }
}
