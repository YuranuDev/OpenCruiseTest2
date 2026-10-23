// 初期画面(ランチャー): 最上部にステータスバー、中央に時計カードと広いウィジェット領域、下部にナビバー(大型ボタン 4 つ)。
// 運転中でも迷わないよう、操作は下部バーに集約する。未実装の機能は押すとモック通知を出す。
import QtQuick
import OpenCruise

Item {
    id: root

    // Android Auto の映像が出ている(=AA 画面へ戻れる)か
    property bool aaAvailable: false
    signal openSettings()
    signal openAndroidAuto()

    // 画面サイズに合わせた拡大率。1280x720 を基準に、800x480 でも収まるようにする
    readonly property real unit: Math.max(0.6, Math.min(width / 1280, height / 720))
    readonly property int gap: Theme.margin

    // 時刻に応じた挨拶と、ユーザー名つきの文
    readonly property string greeting: {
        const h = clock.hour
        return (h >= 4 && h < 11) ? "おはようございます" : (h >= 11 && h < 18) ? "こんにちは" : "こんばんは"
    }
    readonly property string greetingText: appSettings.userName === "" ? greeting
                                                                       : greeting + "、" + appSettings.userName + " さん"

    // 未実装機能の押下時: 既存のポップアップ通知でモックであることを伝える
    function showMock(name) {
        notifications.show(name, "この機能はモックです(未実装)", 0, "construction")
    }

    // ---- 下部: ナビバー(大型ボタン 5 つ。左端はホーム=この画面) ----
    Item {
        id: bar
        anchors {
            left: parent.left; right: parent.right; bottom: parent.bottom
            leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5; bottomMargin: Theme.margin * 1.5
        }
        height: Math.max(76, parent.height * 0.15)
        readonly property real cellW: (width - 4 * root.gap) / 5

        LauncherTile {
            x: 0; width: bar.cellW; height: bar.height; unit: root.unit ; selected: true
            icon: "home"; title: "ホーム"
            onClicked: {}
        }
        LauncherTile {
            x: 1 * (bar.cellW + root.gap); width: bar.cellW; height: bar.height; unit: root.unit
            icon: "graphic_eq"; title: "オーディオ"
            onClicked: root.showMock("オーディオ操作")
        }
        LauncherTile {
            x: 2 * (bar.cellW + root.gap); width: bar.cellW; height: bar.height; unit: root.unit
            icon: "widgets"; title: "ウィジェット"
            onClicked: root.showMock("ウィジェット設定")
        }
        LauncherTile {
            x: 3 * (bar.cellW + root.gap); width: bar.cellW; height: bar.height; unit: root.unit
            icon: "directions_car"; title: "車両連携"
            onClicked: root.showMock("車両連携")
        }
        LauncherTile {
            x: 4 * (bar.cellW + root.gap); width: bar.cellW; height: bar.height; unit: root.unit
            icon: "settings"; title: "設定"
            onClicked: root.openSettings()
        }
    }

    // ---- 最上部: ステータスバー(左に接続状態、右に補助ボタン) ----
    Item {
        id: topBar
        anchors {
            top: parent.top; left: parent.left; right: parent.right
            topMargin: Theme.margin * 1.5; leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5
        }
        height: 52

        Rectangle {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            height: parent.height
            width: badge.implicitWidth + 36
            radius: height / 2
            color: Theme.panel
            border.color: Theme.panelBorder
            ConnectionBadge { id: badge; anchors.centerIn: parent }
        }

        // 補助操作(Android Auto へ戻る・終了)は控えめに右上へ
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 12
            ActionButton {
                visible: root.aaAvailable
                selected: true
                text: "Android Auto を表示"
                onClicked: root.openAndroidAuto()
            }
            NotificationBell { }
            ActionButton {
                text: "終了"
                onClicked: Qt.quit()
            }
        }
    }

    // ---- 中央: 左に挨拶・時計のカード、右に広いウィジェット領域 ----
    Item {
        id: main
        anchors {
            top: topBar.bottom; left: parent.left; right: parent.right; bottom: bar.top
            leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5
            topMargin: Theme.margin; bottomMargin: Theme.margin
        }

        Rectangle {
            id: clockCard
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: parent.width * 0.32
            radius: Theme.radius + 6
            color: Theme.panel
            border.color: Theme.panelBorder

            Column {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                          leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5 }
                spacing: 2 * root.unit

                Text {
                    font.family: Theme.fontFamily
                    width: parent.width
                    text: root.greetingText
                    color: Theme.textSecondary
                    font.pixelSize: 26 * root.unit
                    elide: Text.ElideRight
                }
                Text {
                    font.family: Theme.fontFamily
                    text: clock.timeText
                    color: Theme.textPrimary
                    font.pixelSize: 96 * root.unit
                    font.bold: true
                }
                Text {
                    font.family: Theme.fontFamily
                    text: clock.dateText
                    color: Theme.textSecondary
                    font.pixelSize: 22 * root.unit
                }
            }
        }

        // ウィジェット領域(予定)。ここに今後ウィジェットを並べる
        Rectangle {
            id: widgetArea
            anchors {
                top: parent.top; bottom: parent.bottom; right: parent.right
                left: clockCard.right; leftMargin: root.gap
            }
            color: "transparent"
            radius: Theme.radius + 6
            border.width: 1
            border.color: Theme.panelBorder

            Column {
                anchors.centerIn: parent
                spacing: 6 * root.unit
                opacity: 0.5
                MaterialIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "widgets"
                    size: 44 * root.unit
                    color: Theme.textSecondary
                }
                Text {
                    font.family: Theme.fontFamily
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "ウィジェット表示エリア"
                    color: Theme.textSecondary
                    font.pixelSize: 20 * root.unit
                }
            }
        }
    }
}
