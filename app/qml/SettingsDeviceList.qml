// 縦に並べた大型の選択リスト(排他選択)。出力先デバイスのように、名前が長く数も変わる選択肢向け。
//   SettingsDeviceList { model: audioSettings.outputNames; currentIndex: audioSettings.mapDeviceIndex; onPicked: (i) => audioSettings.mapDeviceIndex = i }
// SettingsChoice と同じく、押しても currentIndex は自動では変わらない。picked で受けた側が設定を書き換える。
import QtQuick

Column {
    id: root
    property var model: []
    property int currentIndex: -1
    signal picked(int index)

    readonly property real unit: Theme.uiScale

    // SettingsRow の操作部品置き場(幅が子要素で決まる)の中に置くので、幅は固定にする
    width: 720 * unit
    spacing: 8 * unit

    Repeater {
        model: root.model

        Rectangle {
            id: item
            readonly property bool selected: index === root.currentIndex

            width: root.width
            height: 64 * root.unit
            radius: Theme.radius
            color: selected ? Theme.accentFill
                            : Theme.mix(Theme.background, Theme.accentFill, mouse.pressed ? 0.45 : 0)
            border.width: selected || mouse.pressed ? 2 : 1
            border.color: selected || mouse.pressed ? Theme.accent : Theme.panelBorder
            scale: mouse.pressed ? 0.99 : 1.0
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

            MaterialIcon {
                id: mark
                anchors { left: parent.left; leftMargin: 18 * root.unit; verticalCenter: parent.verticalCenter }
                name: item.selected ? "radio_button_checked" : "radio_button_unchecked"
                size: 30 * root.unit
                color: item.selected ? Theme.textOnAccent : Theme.textSecondary
            }
            Text {
                anchors {
                    left: mark.right; leftMargin: 14 * root.unit
                    right: parent.right; rightMargin: 18 * root.unit
                    verticalCenter: parent.verticalCenter
                }
                font.family: Theme.fontFamily
                text: modelData
                color: item.selected ? Theme.textOnAccent : Theme.textPrimary
                font.pixelSize: 24 * root.unit
                font.bold: item.selected
                elide: Text.ElideRight
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                onClicked: { root.picked(index) }
            }
        }
    }
}
