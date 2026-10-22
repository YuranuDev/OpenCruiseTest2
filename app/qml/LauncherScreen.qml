// 初期画面(ランチャー): 上部に挨拶・時計と、将来ウィジェットを置く領域、下部にナビバー(大型ボタン 4 つ)。
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

    // ---- 下部: ナビバー(大型ボタン 4 つ) ----
    Item {
        id: bar
        anchors {
            left: parent.left; right: parent.right; bottom: parent.bottom
            leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5; bottomMargin: Theme.margin * 1.5
        }
        height: Math.max(76, parent.height * 0.15)
        readonly property real cellW: (width - 3 * root.gap) / 4

        LauncherTile {
            x: 0; width: bar.cellW; height: bar.height; unit: root.unit
            icon: "graphic_eq"; title: "オーディオ"
            onClicked: root.showMock("オーディオ操作")
        }
        LauncherTile {
            x: (bar.cellW + root.gap); width: bar.cellW; height: bar.height; unit: root.unit
            icon: "widgets"; title: "ウィジェット"
            onClicked: root.showMock("ウィジェット設定")
        }
        LauncherTile {
            x: 2 * (bar.cellW + root.gap); width: bar.cellW; height: bar.height; unit: root.unit
            icon: "directions_car"; title: "車両連携"
            onClicked: root.showMock("車両連携")
        }
        LauncherTile {
            x: 3 * (bar.cellW + root.gap); width: bar.cellW; height: bar.height; unit: root.unit
            icon: "settings"; title: "設定"
            onClicked: root.openSettings()
        }
    }

    // ---- 上部: 挨拶・時計 / 接続状態 + ウィジェット領域 ----
    Item {
        id: main
        anchors {
            top: parent.top; left: parent.left; right: parent.right; bottom: bar.top
            leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5
            topMargin: Theme.margin * 1.5; bottomMargin: Theme.margin
        }

        Column {
            id: clockBlock
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: parent.width * 0.32
            spacing: 2 * root.unit

            Text {
                font.family: Theme.fontFamily
                width: parent.width
                text: root.greetingText
                color: Theme.textPrimary
                font.pixelSize: 30 * root.unit
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

        // 補助情報(接続状態・Android Auto へ戻る・終了)は控えめに右上へ
        Row {
            id: statusRow
            anchors { right: parent.right; top: parent.top }
            spacing: 16
            ConnectionBadge { anchors.verticalCenter: parent.verticalCenter }
            ActionButton {
                visible: root.aaAvailable
                selected: true
                text: "Android Auto を表示"
                onClicked: root.openAndroidAuto()
            }
            ActionButton {
                text: "終了"
                onClicked: Qt.quit()
            }
        }

        // ウィジェット領域(予定)。ここに今後ウィジェットを並べる
        Rectangle {
            id: widgetArea
            anchors {
                top: statusRow.bottom; topMargin: Theme.margin
                bottom: parent.bottom; right: parent.right
                left: clockBlock.right; leftMargin: Theme.margin
            }
            color: "transparent"
            radius: Theme.radius + 6
            border.width: 1
            border.color: Theme.panelBorder

            Text {
                font.family: Theme.fontFamily
                anchors.centerIn: parent
                text: "ウィジェット表示エリア"
                color: Theme.textSecondary
                font.pixelSize: 20 * root.unit
                opacity: 0.6
            }
        }
    }
}
