// 画面上部のポップアップ通知。コード側は NotificationManager（context property: notifications）から出す。
import QtQuick

ListView {
    id: list

    model: notifications
    width: Math.min(parent.width - 2 * Theme.margin, 560)
    height: contentHeight
    spacing: 10
    interactive: false
    readonly property real titleFontSize: Math.max(16, Math.min(22, width * 0.04))
    readonly property real messageFontSize: Math.max(14, Math.min(18, width * 0.033))

    function levelColor(level) {
        switch (level) {
        case 1: return Theme.ok
        case 2: return Theme.warn
        case 3: return Theme.error
        default: return Theme.accent
        }
    }

    // 上からスライドしながら現れ、フェードして消える
    add: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 250 }
            NumberAnimation { property: "y"; from: -80; duration: 300; easing.type: Easing.OutCubic }
        }
    }
    remove: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: 250 }
    }
    displaced: Transition {
        NumberAnimation { property: "y"; duration: 250; easing.type: Easing.OutCubic }
    }

    delegate: Item {
        width: ListView.view.width
        height: card.height

        Rectangle {
            id: card
            width: parent.width
            height: contentRow.implicitHeight + 24
            radius: Theme.radius
            // エラー(メーターのしきい値超えなど)は、赤く塗って目立たせる
            color: level === 3 ? Theme.mix(Theme.panel, Theme.error, 0.28) : Theme.panel
            border.width: level === 3 ? 3 : 2
            border.color: list.levelColor(level)

            Row {
                id: contentRow
                x: 16; y: 12
                width: parent.width - 32
                spacing: 14

                MaterialIcon {
                    name: icon
                    size: 30
                    color: list.levelColor(level)
                    anchors.verticalCenter: parent.verticalCenter
                }
                Column {
                    width: parent.width - 30 - 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        font.family: Theme.fontFamily
                        width: parent.width
                        text: title
                        color: Theme.textPrimary
                        font.pixelSize: list.titleFontSize
                        font.bold: true
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    Text {
                        font.family: Theme.fontFamily
                        width: parent.width
                        visible: message.length > 0
                        text: message
                        color: Theme.textSecondary
                        font.pixelSize: list.messageFontSize
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                }
            }

            // タップで閉じる
            MouseArea {
                anchors.fill: parent
                onClicked: notifications.dismiss(notificationId)
            }
        }
    }
}
