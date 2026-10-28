// 初期画面(ランチャー): 最上部にステータスバー(中央にウィジェットのページのタブ)、中央はウィジェット配置エリア
// (ページごと。時計・あいさつもウィジェット)、下部にナビバー(大型ボタン 6 つ。Android Auto 画面へ移るボタンもここ)。
// 運転中でも迷わないよう、操作は下部バーに集約する。未実装の機能は押すとモック通知を出す。
// 飾りの画像(キャラなど): ページごとに、画面のどこにでも置ける(ステータスバー・ナビバーの上も)。
//  奥(ウィジェット・バーの後ろ)・パネル(ウィジェットのパネルの上、中身の下)・手前(ウィジェットの前。タッチは下へ通す)の 3 層。
//  編集モードの「画像」で置き直す(DecorationEditor。選んだ画像の操作は下の DecorationPanel)。
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

    // ウィジェットの追加パネルを開く
    function openPicker() { picker.show() }
    // ウィジェットの編集モード(ナビバーの「編集」で入る・出る。上に編集用のバーが出る)
    readonly property bool editing: editingOn
    property bool editingOn: false
    // 編集モードのうち、飾りの画像を置き直している間(false ならウィジェットの編集)
    property bool decorEditing: false
    function setEditing(on) {
        editingOn = on
        if (!on) {
            decorEditing = false
            settingsDialog.close()
            decorPicker.close()
        }
    }
    function setDecorEditing(on) {
        decorEditing = on
        decorStore.selectedId = ""
        if (on) settingsDialog.close()
        else decorPicker.close()
    }
    onDecorEditingChanged: if (!decorEditing) decorStore.selectedId = ""

    // ---- 飾りの画像(今のページの分)と、奥の層(ほかの何よりも後ろ) ----
    DecorationStore {
        id: decorStore
        pages: widgetPages
        areaW: root.width
        areaH: root.height
    }
    DecorationLayer {
        anchors.fill: parent
        z: -1
        store: decorStore
        layerName: "back"
        editing: root.decorEditing
    }
    // ウィジェットのページ(Android Auto 画面の設定ダイアログの「一緒に変える」が、ここのウィジェットも探す)
    readonly property Item pages: widgetPages
    // Android Auto 画面のウィジェット(HomeScreen が渡す。「一緒に変える」の候補に入れる)
    property Item aaArea: null
    // 選んだウィジェット({ area, wid } の配列。ページをまたいでもよい)の設定を開く(1 つなら普通の設定、2 つ以上ならまとめて設定)
    function openSettingsFor(entries) {
        if (entries.length === 0) return
        settingsDialog.area = entries[0].area
        if (entries.length > 1) settingsDialog.showMulti(entries)
        else settingsDialog.show(entries[0].wid)
    }

    // ---- 下部: ナビバー(大型ボタン 6 つ。左端はホーム=この画面) ----
    Item {
        id: bar
        anchors {
            left: parent.left; right: parent.right; bottom: parent.bottom
            leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5; bottomMargin: Theme.margin * 1.5
        }
        height: Math.max(76, parent.height * 0.15)
        readonly property real cellW: (width - 5 * root.gap) / 6

        LauncherTile {
            x: 0; width: bar.cellW; height: bar.height; unit: root.unit ; selected: !root.editing
            icon: "home"; title: "ホーム"
            onClicked: root.setEditing(false)
        }
        // Android Auto 画面へ(映像が出ている間だけ。出ていないときは薄く表示し、押すと理由を知らせる)
        LauncherTile {
            x: 1 * (bar.cellW + root.gap); width: bar.cellW; height: bar.height; unit: root.unit
            icon: "mdi:android"; title: "Android Auto"
            dimmed: !root.aaAvailable
            onClicked: {
                if (!root.aaAvailable) {
                    notifications.show("Android Auto", "スマートフォンが接続されていません", 0, "mdi:android")
                    return
                }
                root.setEditing(false)
                root.openAndroidAuto()
            }
        }
        LauncherTile {
            x: 2 * (bar.cellW + root.gap); width: bar.cellW; height: bar.height; unit: root.unit
            icon: "graphic_eq"; title: "オーディオ"
            onClicked: root.showMock("オーディオ操作")
        }
        LauncherTile {
            x: 3 * (bar.cellW + root.gap); width: bar.cellW; height: bar.height; unit: root.unit
            // ウィジェットの編集モードに入る・出る(編集中は上に編集用のバー。追加もそこから)
            icon: "dashboard_customize"; title: root.editing ? "編集を終了" : "編集"
            selected: root.editing
            onClicked: root.setEditing(!root.editing)
        }
        LauncherTile {
            x: 4 * (bar.cellW + root.gap); width: bar.cellW; height: bar.height; unit: root.unit
            icon: "directions_car"; title: "車両連携"
            onClicked: root.showMock("車両連携")
        }
        LauncherTile {
            x: 5 * (bar.cellW + root.gap); width: bar.cellW; height: bar.height; unit: root.unit
            icon: "settings"; title: "設定"
            onClicked: { root.setEditing(false); root.openSettings() }
        }
    }

    // ---- 最上部: ステータスバー(左に接続状態のアイコン、中央にページのタブ、右に補助ボタン) ----
    Item {
        id: topBar
        anchors {
            top: parent.top; left: parent.left; right: parent.right
            topMargin: Theme.margin * 1.5; leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5
        }
        height: 52
        // 画像を置き直している間は、編集用のバーのボタンを画像の操作の層より上にする(ボタン以外はタッチを下へ通す)
        z: root.decorEditing ? 17 : 0

        // 編集モードの間は、ステータスバーの代わりに編集用のバーを出す
        WidgetEditBar {
            anchors.fill: parent
            z: 2
            opacity: root.editing ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            area: widgetPages.currentArea
            pages: widgetPages
            decorAvailable: true
            decorMode: root.decorEditing
            onDecorModeRequested: (on) => root.setDecorEditing(on)
            onAddDecorRequested: decorPicker.show()
            canUndo: decorStore.canUndo
            onUndoRequested: decorStore.undo()
            onAddRequested: root.openPicker()
            onSettingsRequested: (entries) => root.openSettingsFor(entries)
            onDoneRequested: root.setEditing(false)
        }

        // Android Auto の接続状態(アイコン)
        ConnectionBadge {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            size: parent.height
            visible: !root.editing
        }

        // ウィジェットのページのタブ(画面の中央。右のボタンと同じ幅を左にも空けて、中央にそろえる)
        PageBar {
            anchors { left: parent.left; right: rightButtons.left; verticalCenter: parent.verticalCenter
                      leftMargin: rightButtons.width + Theme.margin; rightMargin: Theme.margin }
            height: parent.height - 4
            pages: widgetPages
            visible: !root.editing
            onMenuRequested: (index) => pageMenu.show(index)
        }

        // 補助操作(通知・警告の解除)は控えめに右上へ(Android Auto 画面へは下のナビバーから)
        Row {
            id: rightButtons
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 12
            visible: !root.editing
            NotificationBell { }
            AlarmClearButton { }   // 鳴っている警告をまとめて解除(右端)
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
            editMode: root.editingOn && !root.decorEditing
            showEmptyState: !root.decorEditing
            decorSource: decorStore
            decorRoot: root
            // 画像を置き直している間は、ウィジェットを薄くして、後ろ(奥)の画像も見えるようにする
            opacity: root.decorEditing ? 0.55 : 1
            Behavior on opacity { NumberAnimation { duration: 180 } }
            onSettingsRequested: (area, wid) => { settingsDialog.area = area; settingsDialog.show(wid) }
            onPickerRequested: picker.show()
        }
    }

    // ---- 飾りの画像: 手前の層(ウィジェット・バーより前。タッチは受けない)と、置き直す操作 ----
    DecorationLayer {
        anchors.fill: parent
        z: 15
        store: decorStore
        layerName: "front"
        editing: root.decorEditing
    }
    DecorationEditor {
        anchors.fill: parent
        z: 16
        visible: root.decorEditing
        store: decorStore
        pages: widgetPages
        handleBottom: decorStore.selectedId !== "" ? bar.y - 6 : root.height
        tagTop: topBar.y + topBar.height
    }
    // 選んだ画像の操作(ナビバーの場所に重ねる)
    DecorationPanel {
        z: 18
        x: bar.x
        width: bar.width
        height: bar.height
        y: root.decorEditing && decorStore.selectedId !== "" ? bar.y : root.height + 10
        visible: y < root.height
        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        store: decorStore
    }

    // ---- 設定ダイアログ・追加パネル(画面全体に重ねる) ----
    WidgetSettingsDialog {
        id: settingsDialog
        anchors.fill: parent
        z: 20
        area: widgetPages.currentArea
        homePages: widgetPages
        aaArea: root.aaArea
    }
    WidgetPicker {
        id: picker
        anchors.fill: parent
        z: 21
        area: widgetPages.currentArea   // 追加するのは今のページ
    }
    DecorationPicker {
        id: decorPicker
        anchors.fill: parent
        z: 21
        store: decorStore
    }
    PageMenu {
        id: pageMenu
        anchors.fill: parent
        z: 22
        pages: widgetPages
    }
}
