// 初期画面(ランチャー): 上段に挨拶と時計、下段にナビ風の大型ボタン 2×2。
// 運転中でも迷わないよう、機能は 4 つの大型ボタンだけに絞る。未実装の機能は押すとモック通知を出す。
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

    // ---- 上段: 挨拶・時計 / 接続状態・操作 ----
    Item {
        id: top
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: Theme.margin * 1.5 }
        height: parent.height * 0.34

        Column {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: parent.width * 0.62
            spacing: 2 * root.unit

            Text {
                font.family: Theme.fontFamily
                width: parent.width
                text: root.greetingText
                color: Theme.textPrimary
                font.pixelSize: 36 * root.unit
                elide: Text.ElideRight
            }
            Text {
                font.family: Theme.fontFamily
                text: clock.timeText
                color: Theme.textPrimary
                font.pixelSize: 132 * root.unit
                font.bold: true
            }
            Text {
                font.family: Theme.fontFamily
                text: clock.dateText
                color: Theme.textSecondary
                font.pixelSize: 26 * root.unit
            }
        }

        // 補助情報は控えめに右上へ
        ConnectionBadge {
            id: badge
            anchors { right: parent.right; top: parent.top }
        }
        Row {
            anchors { right: parent.right; top: badge.bottom; topMargin: 12 }
            spacing: 10
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
    }

    // ---- 下段: 大型ボタン 2×2 ----
    Item {
        id: tiles
        anchors {
            top: top.bottom; bottom: parent.bottom; left: parent.left; right: parent.right
            leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5
            topMargin: Theme.margin; bottomMargin: Theme.margin * 1.5
        }
        readonly property real cellW: (width - root.gap) / 2
        readonly property real cellH: (height - root.gap) / 2

        LauncherTile {
            x: 0; y: 0; width: tiles.cellW; height: tiles.cellH; unit: root.unit
            icon: "graphic_eq"; title: "オーディオ"; subtitle: "再生・音量・音源の操作"
            onClicked: root.showMock("オーディオ操作")
        }
        LauncherTile {
            x: tiles.cellW + root.gap; y: 0; width: tiles.cellW; height: tiles.cellH; unit: root.unit
            icon: "widgets"; title: "ウィジェット"; subtitle: "表示する情報の設定"
            onClicked: root.showMock("ウィジェット設定")
        }
        LauncherTile {
            x: 0; y: tiles.cellH + root.gap; width: tiles.cellW; height: tiles.cellH; unit: root.unit
            icon: "directions_car"; title: "車両連携"; subtitle: "車両情報・車両との接続"
            onClicked: root.showMock("車両連携")
        }
        LauncherTile {
            x: tiles.cellW + root.gap; y: tiles.cellH + root.gap; width: tiles.cellW; height: tiles.cellH; unit: root.unit
            icon: "settings"; title: "設定"; subtitle: "表示・ユーザー・接続"
            onClicked: root.openSettings()
        }
    }
}
