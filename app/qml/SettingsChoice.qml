// 横並びの大型選択ボタン(排他選択)。選択中はアクセント色の塗り + チェックマークで、色が分からなくても判別できる。
//   SettingsChoice { model: ["昼", "夜", "自動"]; currentIndex: androidAuto.themeMode; onPicked: (i) => androidAuto.themeMode = i }
// 押しても currentIndex は自動では変わらない。picked で受けた側が設定を書き換え、currentIndex の束縛で見た目へ反映する。
import QtQuick

Row {
    id: root
    property var model: []
    property int currentIndex: -1
    signal picked(int index)

    readonly property real unit: Theme.uiScale

    spacing: 10 * unit

    Repeater {
        model: root.model

        Rectangle {
            id: btn
            readonly property bool selected: index === root.currentIndex

            implicitWidth: Math.max(112 * root.unit, content.implicitWidth + 44 * root.unit)
            width: implicitWidth
            height: 64 * root.unit
            radius: Theme.radius
            color: selected ? Theme.accentFill
                            : Theme.mix(Theme.background, Theme.accentFill, mouse.pressed ? 0.45 : 0)
            border.width: selected || mouse.pressed ? 2 : 1
            border.color: selected || mouse.pressed ? Theme.accent : Theme.panelBorder
            scale: mouse.pressed ? 0.97 : 1.0
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

            Row {
                id: content
                anchors.centerIn: parent
                spacing: 8 * root.unit

                MaterialIcon {
                    visible: btn.selected
                    anchors.verticalCenter: parent.verticalCenter
                    name: "check"
                    size: 28 * root.unit
                    color: Theme.textOnAccent
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    text: modelData
                    color: btn.selected ? Theme.textOnAccent : Theme.textPrimary
                    font.pixelSize: 24 * root.unit
                    font.bold: btn.selected
                }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                onClicked: root.picked(index)
            }
        }
    }
}
