// 読み取り専用の情報 1 行(左: 項目名、右: 値)。接続状態などの診断表示に使う。
//   SettingsInfoRow { label: "状態"; value: androidAuto.stateText; valueColor: Theme.ok }
import QtQuick

Item {
    id: root
    property string label: ""
    property string value: ""
    property color valueColor: Theme.textPrimary

    readonly property real unit: Theme.uiScale

    width: parent ? parent.width : implicitWidth
    implicitHeight: Math.max(nameText.implicitHeight, valueText.implicitHeight) + 24 * unit
    height: Math.max(implicitHeight, 60 * unit)

    Text {
        id: nameText
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width * 0.34
        font.family: Theme.fontFamily
        text: root.label
        color: Theme.textSecondary
        font.pixelSize: 22 * root.unit
        wrapMode: Text.WordWrap
    }
    Text {
        id: valueText
        anchors.verticalCenter: parent.verticalCenter
        x: parent.width * 0.34 + 16 * root.unit
        width: parent.width - x
        font.family: Theme.fontFamily
        text: root.value
        color: root.valueColor
        font.pixelSize: 24 * root.unit
        wrapMode: Text.WordWrap
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: Theme.panelBorder
        opacity: 0.8
    }
}
