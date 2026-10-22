// 大型のオン/オフスイッチ。「ON / OFF」の文字つきで、スイッチ + 文字のどこを押しても切り替わる。
//   SettingsSwitch { checked: androidAuto.fullscreenOnStream; onToggled: (value) => androidAuto.fullscreenOnStream = value }
// 押しても checked は自動では変わらない。toggled で受けた側が設定を書き換え、checked の束縛で見た目へ反映する。
import QtQuick

Item {
    id: root
    property bool checked: false
    signal toggled(bool value)

    readonly property real unit: Theme.uiScale

    implicitWidth: row.width
    implicitHeight: 64 * unit
    width: implicitWidth
    height: implicitHeight

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14 * root.unit

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 56 * root.unit
            horizontalAlignment: Text.AlignRight
            font.family: Theme.fontFamily
            text: root.checked ? "ON" : "OFF"
            color: root.checked ? Theme.accent : Theme.textSecondary
            font.pixelSize: 24 * root.unit
            font.bold: true
        }

        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: 112 * root.unit
            height: 60 * root.unit
            radius: height / 2
            color: root.checked ? Theme.accent : Theme.mix(Theme.background, Theme.textSecondary, 0.25)
            border.width: 1
            border.color: root.checked ? Theme.accent : Theme.panelBorder
            scale: mouse.pressed ? 0.96 : 1.0
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 140 } }

            Rectangle {
                width: 48 * root.unit
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                x: root.checked ? parent.width - width - 6 * root.unit : 6 * root.unit
                color: root.checked ? Theme.onAccent : Theme.textPrimary
                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        onClicked: root.toggled(!root.checked)
    }
}
