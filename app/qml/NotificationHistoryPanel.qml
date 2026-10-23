// 通知履歴パネル。ベルボタン(NotificationBell)で開閉する。Main.qml に 1 つだけ置く(全画面を覆い、外側タップで閉じる)。
// 履歴に載るのは、ポップアップが操作されずに消えた通知だけ(NotificationManager を参照)。新しい順。
import QtQuick

Item {
    id: root
    visible: opacity > 0
    opacity: notifications.historyOpen ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 180 } }

    function levelColor(level) {
        switch (level) {
        case 1: return Theme.ok
        case 2: return Theme.warn
        case 3: return Theme.error
        default: return Theme.accent
        }
    }

    // 外側は暗くして、タップで閉じる
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.45
        MouseArea {
            anchors.fill: parent
            onClicked: notifications.historyOpen = false
        }
    }

    Rectangle {
        id: card
        anchors { right: parent.right; rightMargin: Theme.margin; top: parent.top; topMargin: 96 }
        width: Math.min(parent.width - 2 * Theme.margin, 540)
        height: Math.min(parent.height - 96 - Theme.margin, 580)
        radius: Theme.radius
        color: Theme.panel
        border.width: 1
        border.color: Theme.panelBorder

        // カード内のタップは外側へ伝えない(閉じてしまわないように)
        MouseArea { anchors.fill: parent }

        Item {
            id: head
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
            height: 52

            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                font.family: Theme.fontFamily
                text: "通知履歴"
                color: Theme.textPrimary
                font.pixelSize: 26
                font.bold: true
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 10
                ActionButton {
                    visible: notifications.history.count > 0
                    text: "すべて削除"
                    onClicked: notifications.history.clear()
                }
                ActionButton {
                    text: "閉じる"
                    onClicked: notifications.historyOpen = false
                }
            }
        }

        ListView {
            id: list
            anchors { top: head.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: parent.bottom
                      leftMargin: 16; rightMargin: 16; bottomMargin: 16 }
            model: notifications.history
            spacing: 10
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                width: ListView.view.width
                height: row.implicitHeight + 24
                radius: Theme.radius
                color: Theme.background
                border.width: 1
                border.color: root.levelColor(level)

                Row {
                    id: row
                    x: 14; y: 12
                    width: parent.width - 28
                    spacing: 12

                    MaterialIcon {
                        name: icon
                        size: 32
                        color: root.levelColor(level)
                    }
                    Column {
                        width: parent.width - 32 - 12
                        spacing: 2
                        Row {
                            width: parent.width
                            Text {
                                font.family: Theme.fontFamily
                                width: parent.width - timeLabel.implicitWidth - 10
                                text: title
                                color: Theme.textPrimary
                                font.pixelSize: 20
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Item { width: 10; height: 1 }
                            Text {
                                id: timeLabel
                                font.family: Theme.fontFamily
                                text: timeText
                                color: Theme.textSecondary
                                font.pixelSize: 15
                            }
                        }
                        Text {
                            font.family: Theme.fontFamily
                            width: parent.width
                            visible: message.length > 0
                            text: message
                            color: Theme.textSecondary
                            font.pixelSize: 16
                            wrapMode: Text.WordWrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        Text {
            anchors.centerIn: list
            visible: notifications.history.count === 0
            font.family: Theme.fontFamily
            text: "通知はありません"
            color: Theme.textSecondary
            font.pixelSize: 20
        }
    }
}
