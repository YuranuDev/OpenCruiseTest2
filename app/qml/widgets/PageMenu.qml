// ページの設定(ページのタブを長押し、または今のページのタブをタップで開く)。
// 名前の変更・左右への並び替え・削除(2 回押し。そのページのウィジェットも消える。最後の 1 ページは消せない)。
import QtQuick
import OpenCruise

Item {
    id: root
    property Item pages: null
    property int index: -1
    property bool open: false
    property bool confirmDelete: false

    readonly property real unit: Theme.uiScale
    readonly property string pageName: pages && index >= 0 && index < pages.names.length ? pages.names[index] : ""

    function show(i) { index = i; confirmDelete = false; open = true }
    function close() { nameField.commit(); open = false }

    visible: scrim.opacity > 0

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "black"
        opacity: root.open ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; enabled: root.open; onClicked: root.close() }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Theme.margin, 720 * root.unit)
        height: content.implicitHeight + 2 * Theme.margin * 1.5
        radius: Theme.radius + 8
        color: Theme.panel
        border.color: Theme.panelBorder
        scale: root.open ? 1 : 0.92
        opacity: root.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea { anchors.fill: parent }

        Column {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.margin * 1.5 }
            spacing: Theme.margin

            Text {
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: 30 * root.unit
                color: Theme.textPrimary
                text: "ページの設定"
            }

            Text {
                font.family: Theme.fontFamily
                font.pixelSize: 19 * root.unit
                color: Theme.textSecondary
                text: "名前"
            }
            WSTextField {
                id: nameField
                width: parent.width
                text: root.pageName
                placeholder: "ページ " + (root.index + 1)
                maxLength: 16
                onEdited: (t) => { if (root.pages && root.index >= 0) root.pages.renamePage(root.index, t) }
            }

            Text {
                font.family: Theme.fontFamily
                font.pixelSize: 19 * root.unit
                color: Theme.textSecondary
                text: "並び順"
            }
            Row {
                spacing: Theme.margin * 0.6
                ActionButton {
                    width: 200 * root.unit; height: 64 * root.unit
                    text: "◀ 左へ"
                    opacity: root.index > 0 ? 1 : 0.4
                    onClicked: if (root.index > 0) { root.pages.movePage(root.index, -1); root.index-- }
                }
                ActionButton {
                    width: 200 * root.unit; height: 64 * root.unit
                    text: "右へ ▶"
                    opacity: root.pages && root.index < root.pages.count - 1 ? 1 : 0.4
                    onClicked: if (root.pages && root.index < root.pages.count - 1) { root.pages.movePage(root.index, 1); root.index++ }
                }
            }

            Item { width: 1; height: Theme.margin * 0.5 }
            Item {
                width: parent.width
                height: 64 * root.unit
                Rectangle {
                    id: deleteButton
                    readonly property bool canDelete: root.pages && root.pages.count > 1
                    anchors.left: parent.left
                    height: parent.height
                    width: deleteText.implicitWidth + 48 * root.unit
                    radius: Theme.radius
                    opacity: canDelete ? 1 : 0.4
                    color: root.confirmDelete ? Theme.error : Theme.mix(Theme.panel, Theme.error, delMouse.pressed ? 0.3 : 0.1)
                    border.color: Theme.error
                    Text {
                        id: deleteText
                        anchors.centerIn: parent
                        font.family: Theme.fontFamily
                        font.bold: true
                        font.pixelSize: 22 * root.unit
                        color: root.confirmDelete ? Theme.textOnAccent : Theme.error
                        text: !deleteButton.canDelete ? "最後のページは削除できません"
                              : (root.confirmDelete ? "もう一度押すと、ウィジェットごと削除します" : "このページを削除")
                    }
                    MouseArea {
                        id: delMouse
                        anchors.fill: parent
                        enabled: deleteButton.canDelete
                        onClicked: {
                            if (!root.confirmDelete) {
                                root.confirmDelete = true
                                confirmTimer.restart()
                            } else {
                                root.confirmDelete = false
                                root.pages.removePage(root.index)
                                root.open = false
                            }
                        }
                    }
                    Timer { id: confirmTimer; interval: 4000; onTriggered: root.confirmDelete = false }
                }
                ActionButton {
                    anchors.right: parent.right
                    height: parent.height
                    selected: true
                    text: "閉じる"
                    onClicked: root.close()
                }
            }
        }
    }
}
