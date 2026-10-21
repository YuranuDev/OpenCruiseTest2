// 車載向けの大きめボタン（タッチしやすい高さ）。
import QtQuick

Rectangle {
    id: root
    property alias text: label.text
    property bool selected: false
    signal clicked()

    implicitWidth: label.implicitWidth + 40
    implicitHeight: 52
    radius: Theme.radius
    color: (mouse.pressed || selected) ? Theme.accent : Theme.panel
    border.color: Theme.panelBorder
    border.width: 1

    Text {
        id: label
        anchors.centerIn: parent
        color: Theme.textPrimary
        font.pixelSize: 22
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
