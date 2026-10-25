// 設定 1 項目の行。左に項目名(と補足説明)、右に操作部品(選択ボタン・スイッチなど)を置く。
//   SettingsRow { label: "解像度"; description: "..."; SettingsChoice { ... } }
// 子要素が操作部品になる。stacked: true にすると、操作部品を項目名の下に置く(横幅が必要な部品向け)。
// controlMaxWidth は操作部品に使える幅の目安(SettingsChoice はこれを超えると折り返す)。
import QtQuick

Item {
    id: root
    property string label: ""
    property string description: ""
    property bool stacked: false
    default property alias control: slot.data

    readonly property real unit: Theme.uiScale
    readonly property real vpad: 12 * unit
    readonly property real gap: 24 * unit
    readonly property real controlMaxWidth: stacked ? width : Math.max(240 * unit, width * 0.62)

    width: parent ? parent.width : implicitWidth
    implicitHeight: stacked
                    ? textCol.implicitHeight + slot.height + 3 * vpad
                    : Math.max(textCol.implicitHeight, slot.height) + 2 * vpad + 12 * unit
    // 操作しやすいよう、1 行の最低の高さを確保する
    height: Math.max(implicitHeight, 80 * unit)

    Column {
        id: textCol
        x: 0
        y: root.stacked ? root.vpad : (root.height - height) / 2
        width: root.stacked ? root.width : Math.max(0, root.width - slot.width - root.gap)
        spacing: 2 * root.unit

        Text {
            width: parent.width
            font.family: Theme.fontFamily
            text: root.label
            color: Theme.textPrimary
            font.pixelSize: 26 * root.unit
            wrapMode: Text.WordWrap
        }
        Text {
            visible: root.description !== ""
            width: parent.width
            font.family: Theme.fontFamily
            text: root.description
            color: Theme.textSecondary
            font.pixelSize: 19 * root.unit
            wrapMode: Text.WordWrap
        }
    }

    Item {
        id: slot
        width: childrenRect.width
        height: childrenRect.height
        x: root.stacked ? 0 : root.width - width
        y: root.stacked ? root.vpad + textCol.implicitHeight + root.vpad : (root.height - height) / 2
    }

    // 行の区切り線
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: Theme.panelBorder
        opacity: 0.8
    }
}
