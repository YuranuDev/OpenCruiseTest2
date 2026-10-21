// メイン画面: ヘッダー(時計・接続状態・設定ボタン) + Android Auto 表示領域 + CAN パネル。
import QtQuick
import OpenCruise

Rectangle {
    id: root
    color: Theme.background
    signal openSettings()

    // フルスクリーン表示(映像だけを全面表示)か。Main.qml から渡される
    property bool immersive: false
    // フルスクリーン中のスライドメニューが開いているか
    property bool menuOpen: false
    onImmersiveChanged: if (!immersive) menuOpen = false

    // ---- ヘッダー ----
    Item {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        anchors.margins: Theme.margin
        height: 76
        visible: !root.immersive

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
            top: root.immersive ? parent.top : header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right
            margins: root.immersive ? 0 : Theme.margin
        }

        // Android Auto 表示領域
        Rectangle {
            id: aaFrame
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left; right: root.immersive ? parent.right : canPanel.left; rightMargin: root.immersive ? 0 : Theme.margin }
            color: "black"
            radius: root.immersive ? 0 : Theme.radius
            border.color: root.immersive ? "transparent" : Theme.panelBorder
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
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: androidAuto.stateKey === "waiting" || androidAuto.stateKey === "connecting"
                    text: "接続試行 " + androidAuto.attemptCount + " 回 / 受信映像 "
                          + androidAuto.videoPacketCount + " 通"
                    color: Theme.textSecondary
                    font.pixelSize: 16
                }
            }
        }

        CanPanel {
            id: canPanel
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
            width: 320
            visible: !root.immersive
        }
    }

    // ---- フルスクリーン時のメニュー ----
    // 右端の細いつまみを左へスワイプ(またはタップ)、もしくは Esc / F10 / Menu キーで開く。
    // つまみの幅の分だけ、映像の右端はタッチが届かない。
    MouseArea {
        id: edgeHandle
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        width: 28
        z: 10
        visible: root.immersive && !root.menuOpen
        onPositionChanged: (mouse) => { if (pressed && mouse.x < -30) root.menuOpen = true }
        onClicked: root.menuOpen = true

        Rectangle {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: 6; height: 90; radius: 3
            color: Theme.textSecondary
            opacity: 0.6
        }
    }

    // メニュー外タップで閉じる
    MouseArea {
        anchors.fill: parent
        z: 11
        visible: root.immersive && root.menuOpen
        onClicked: root.menuOpen = false
    }

    Rectangle {
        id: slideMenu
        z: 12
        width: 300
        height: parent.height
        x: (root.immersive && root.menuOpen) ? parent.width - width : parent.width
        visible: x < parent.width
        color: Theme.panel
        border.color: Theme.panelBorder
        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Column {
            anchors { fill: parent; margins: Theme.margin }
            spacing: 14
            Text { text: clock.timeText; color: Theme.textPrimary; font.pixelSize: 40; font.bold: true }
            ConnectionBadge {}
            ActionButton {
                width: parent.width
                text: "設定"
                onClicked: { root.menuOpen = false; root.openSettings() }
            }
            ActionButton {
                width: parent.width
                text: "メニューを閉じる"
                onClicked: root.menuOpen = false
            }
            ActionButton {
                width: parent.width
                text: "終了"
                onClicked: Qt.quit()
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Esc / F10 / Menu キーでも開閉できます"
                color: Theme.textSecondary
                font.pixelSize: 15
            }
        }
    }
}
