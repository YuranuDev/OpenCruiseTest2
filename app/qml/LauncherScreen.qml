// 初期画面(ランチャー): 最上部にステータスバー(中央にウィジェットのページのタブ)、中央はウィジェット配置エリア
// (ページごと。時計・あいさつもウィジェット)、下部にナビバー(大型ボタン 5 つ)。
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

    // 未実装機能の押下時: 既存のポップアップ通知でモックであることを伝える
    function showMock(name) {
        notifications.show(name, "この機能はモックです(未実装)", 0, "construction")
    }

    // ウィジェットの追加パネルを開く(ナビバーのボタン、フルスクリーン中の下メニューから)
    function openPicker() { picker.show() }

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
            onClicked: root.openPicker()
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
            id: badgePill
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            height: parent.height
            width: badge.implicitWidth + 36
            radius: height / 2
            color: Theme.panel
            border.color: Theme.panelBorder
            ConnectionBadge { id: badge; anchors.centerIn: parent }
        }

        // ウィジェットのページのタブ(左右の間の空き)
        PageBar {
            anchors { left: badgePill.right; right: rightButtons.left; verticalCenter: parent.verticalCenter
                      leftMargin: Theme.margin; rightMargin: Theme.margin }
            height: parent.height - 4
            pages: widgetPages
            onMenuRequested: (index) => pageMenu.show(index)
        }

        // 補助操作(Android Auto へ戻る・通知)は控えめに右上へ
        Row {
            id: rightButtons
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 12
            ActionButton {
                visible: root.aaAvailable
                selected: true
                text: "Android Auto を表示"
                onClicked: root.openAndroidAuto()
            }
            NotificationBell { }
        }
    }

    // ---- 中央: ウィジェット配置エリア(この領域全体を使う。時計・あいさつも、ここに置くウィジェットの 1 つ) ----
    Item {
        id: main
        anchors {
            top: topBar.bottom; left: parent.left; right: parent.right; bottom: bar.top
            leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5
            topMargin: Theme.margin; bottomMargin: Theme.margin
        }

        WidgetPages {
            id: widgetPages
            anchors.fill: parent
            onSettingsRequested: (area, wid) => { settingsDialog.area = area; settingsDialog.show(wid) }
            onPickerRequested: picker.show()
        }
    }

    // ---- 設定ダイアログ・追加パネル(画面全体に重ねる) ----
    WidgetSettingsDialog {
        id: settingsDialog
        anchors.fill: parent
        z: 20
        area: widgetPages.currentArea
    }
    WidgetPicker {
        id: picker
        anchors.fill: parent
        z: 21
        area: widgetPages.currentArea   // 追加するのは今のページ
    }
    PageMenu {
        id: pageMenu
        anchors.fill: parent
        z: 22
        pages: widgetPages
    }
}
