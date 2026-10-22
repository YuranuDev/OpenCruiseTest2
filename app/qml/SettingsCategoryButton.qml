// 設定画面の左側に並ぶジャンルボタン(アイコン + 名前)。選択中は塗りと左端のバーで示す。
import QtQuick

Rectangle {
    id: root
    property string icon: ""
    property string title: ""
    property bool selected: false
    signal clicked()

    readonly property real unit: Theme.uiScale

    implicitHeight: 84 * unit
    height: implicitHeight
    radius: Theme.radius + 2
    color: selected ? Theme.mix(Theme.panel, Theme.accent, 0.28)
                    : Theme.mix(Theme.panel, Theme.accent, mouse.pressed ? 0.18 : 0)
    border.width: selected ? 2 : 0
    border.color: Theme.accent
    scale: mouse.pressed ? 0.98 : 1.0
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 120 } }

    // 選択中を示す左端のバー
    Rectangle {
        visible: root.selected
        anchors { left: parent.left; leftMargin: 6 * root.unit; verticalCenter: parent.verticalCenter }
        width: 6 * root.unit
        height: parent.height * 0.5
        radius: width / 2
        color: Theme.accent
    }

    Row {
        anchors { left: parent.left; leftMargin: 26 * root.unit; right: parent.right; rightMargin: 12 * root.unit
                  verticalCenter: parent.verticalCenter }
        spacing: 16 * root.unit

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.icon
            size: 40 * root.unit
            color: root.selected ? Theme.accent : Theme.textSecondary
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 40 * root.unit - parent.spacing
            font.family: Theme.fontFamily
            text: root.title
            color: Theme.textPrimary
            font.pixelSize: 26 * root.unit
            font.bold: root.selected
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
