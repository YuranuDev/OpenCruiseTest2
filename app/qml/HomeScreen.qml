// メイン画面: ヘッダー(時計・接続状態・設定ボタン) + Android Auto 表示領域 + CAN パネル。
import QtQuick
import OpenCruise

Rectangle {
    id: root
    color: Theme.background
    signal openSettings()

    // ---- ヘッダー ----
    Item {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        anchors.margins: Theme.margin
        height: 76

        Column {
            anchors.verticalCenter: parent.verticalCenter
            Text { text: clock.timeText; color: Theme.textPrimary; font.pixelSize: 46; font.bold: true }
            Text { text: clock.dateText; color: Theme.textSecondary; font.pixelSize: 18 }
        }

        ConnectionBadge {
            anchors.centerIn: parent
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            ActionButton {
                text: "終了"
                onClicked: Qt.quit()
            }
            ActionButton {
                text: "設定"
                onClicked: root.openSettings()
            }
        }
    }

    // ---- 本体 ----
    Item {
        anchors {
            top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right
            margins: Theme.margin
        }

        // Android Auto 表示領域
        Rectangle {
            id: aaFrame
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left; right: canPanel.left; rightMargin: Theme.margin }
            color: "black"
            radius: Theme.radius
            border.color: Theme.panelBorder
            clip: true

            VideoSurfaceItem {
                id: surface
                anchors.fill: parent
                Component.onCompleted: androidAuto.attachSurface(surface)
            }

            // 映像が出ていない間の案内表示
            Column {
                anchors.centerIn: parent
                spacing: 10
                visible: androidAuto.stateKey !== "streaming"
                width: parent.width - 80

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "Android Auto"
                    color: Theme.textPrimary
                    font.pixelSize: 40
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: androidAuto.stateText
                    color: Theme.stateColor(androidAuto.stateKey)
                    font.pixelSize: 28
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: androidAuto.detailText
                    color: Theme.textSecondary
                    font.pixelSize: 18
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: androidAuto.stateKey === "waiting"
                    text: "スマートフォンを USB で接続してください"
                    color: Theme.textSecondary
                    font.pixelSize: 18
                }
            }
        }

        CanPanel {
            id: canPanel
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
            width: 320
        }
    }
}
