// 通知履歴を開く丸いベルボタン。未読の通知があるときは、右上に赤丸を付ける。
// 押すと通知履歴パネル(NotificationHistoryPanel)を開閉する。size でボタンの直径を指定する。
import QtQuick

Rectangle {
    id: root
    property real size: 52
    readonly property bool active: mouse.pressed || notifications.historyOpen

    width: size
    height: size
    radius: size / 2
    color: active ? Theme.accent : Theme.panel
    border.color: Theme.panelBorder
    border.width: 1

    MaterialIcon {
        anchors.centerIn: parent
        name: "notifications"
        size: Math.round(root.size * 0.55)
        color: Theme.textPrimary
    }

    // 未読の赤丸(円周の右上 45° の位置)
    Rectangle {
        readonly property real d: Math.round(root.size * 0.3)
        visible: notifications.history.unreadCount > 0
        width: d
        height: d
        radius: d / 2
        x: root.size * 0.854 - d / 2
        y: root.size * 0.146 - d / 2
        color: Theme.error
        border.width: 2
        border.color: Theme.background
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        onClicked: notifications.historyOpen = !notifications.historyOpen
    }
}
