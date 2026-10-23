// 設定用の 1 行テキスト入力。入力の確定(Enter / フォーカス移動)で edited(text) を出す。
//   WSTextField { text: config.message; placeholder: "..."; maxLength: 24; onEdited: (t) => root.edit("message", t) }
import QtQuick
import OpenCruise
import QtQuick.Controls

TextField {
    id: root
    property string placeholder: ""
    property int maxLength: 30
    signal edited(string text)

    readonly property real unit: Theme.uiScale
    width: 420 * unit
    height: 64 * unit
    placeholderText: placeholder
    maximumLength: maxLength
    font.family: Theme.fontFamily
    font.pixelSize: 24 * unit
    color: Theme.textPrimary
    placeholderTextColor: Theme.textSecondary
    selectByMouse: true
    leftPadding: 18 * unit
    rightPadding: 18 * unit
    verticalAlignment: TextInput.AlignVCenter

    background: Rectangle {
        radius: Theme.radius
        color: Theme.panel
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? Theme.accent : Theme.panelBorder
    }

    onEditingFinished: root.edited(text)
}
