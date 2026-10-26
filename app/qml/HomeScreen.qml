// メイン画面。showAa が false の間は初期画面(LauncherScreen)、true の間は Android Auto 画面
// (ヘッダー(時計・接続状態・ボタン) + Android Auto 表示領域とウィジェット)を表示する。
// フルスクリーンでないときの本体は、初期画面と同じ 12 × 6 マスのウィジェット配置エリアで、Android Auto の映像は
// その角(設定「Android Auto」で角と幅・高さのマス数を選ぶ。widgetStore.aaCorner / aaCols / aaRows)に置き、
// 残りのマスにウィジェットを置ける(配置は初期画面とは別に widgetStore.aaLayoutJson へ保存)。
// 映像の描画アイテム(VideoSurfaceItem)は表示切替で破棄しないよう、常に生成しておく。
import QtQuick
import OpenCruise

Rectangle {
    id: root
    color: Theme.background
    signal openSettings()
    signal goHome()
    signal openAndroidAuto()

    // Android Auto 画面を表示中か(false なら初期画面)。Main.qml から渡される
    property bool showAa: false
    // 初期画面 ⇄ Android Auto 画面のフェード進行度(0=初期画面 / 1=Android Auto 画面)
    property real aaFade: showAa ? 1 : 0
    Behavior on aaFade { NumberAnimation { duration: 280; easing.type: Easing.InOutQuad } }

    // フルスクリーン表示(映像だけを全面表示)か。Main.qml から渡される
    property bool immersive: false
    // フルスクリーン中の下メニュー(シート)が開いているか
    property bool menuOpen: false
    onImmersiveChanged: if (!immersive) menuOpen = false

    // Android Auto の映像を置くマス(フルスクリーンでないとき)。0 = 左上 / 1 = 右上 / 2 = 左下 / 3 = 右下
    readonly property var aaRect: {
        const cols = widgetStore.aaCols, rows = widgetStore.aaRows, c = widgetStore.aaCorner
        return { col: (c === 1 || c === 3) ? aaWidgets.cols - cols : 0, row: c >= 2 ? aaWidgets.rows - rows : 0, w: cols, h: rows }
    }

    // Android Auto 画面のウィジェットの保存先(WidgetArea の pages の代わり。1 ページだけ)
    Item {
        id: aaStore
        // 初期配置: 映像(左上・幅 9 マス)の右側にメーターを 2 つ
        readonly property var defaultWidgets: [
            { type: "speedGauge", col: 9, row: 0, w: 3, h: 3 },
            { type: "turbo", col: 9, row: 3, w: 3, h: 3 }
        ]
        function pageWidgets(index) {
            try {
                const o = JSON.parse(widgetStore.aaLayoutJson)
                if (o && o.version === 1 && Array.isArray(o.widgets)) return o.widgets
            } catch (e) { /* 未保存・壊れている場合は初期配置 */ }
            return defaultWidgets
        }
        function savePage(index, list) { widgetStore.aaLayoutJson = JSON.stringify({ version: 1, widgets: list }) }
        function resetAll() {
            widgetStore.aaLayoutJson = ""
            aaWidgets.loadLayout()
            aaWidgets.revision++
        }
    }

    // 未実装機能の押下時: 既存のポップアップ通知でモックであることを伝える(初期画面と同じ)
    function showMock(name) {
        notifications.show(name, "この機能はモックです(未実装)", 0, "construction")
    }

    // ---- 初期画面 ----
    LauncherScreen {
        id: launcher
        anchors.fill: parent
        opacity: 1 - root.aaFade
        visible: opacity > 0
        enabled: !root.showAa
        aaAvailable: androidAuto.stateKey === "streaming"
        onOpenSettings: root.openSettings()
        onOpenAndroidAuto: root.openAndroidAuto()
    }

    // ---- ヘッダー ----
    Item {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        anchors.margins: Theme.margin
        height: 76
        opacity: root.aaFade
        visible: root.aaFade > 0 && !root.immersive

        Column {
            anchors.verticalCenter: parent.verticalCenter
            Text { font.family: Theme.fontFamily; text: clock.timeText; color: Theme.textPrimary; font.pixelSize: 46; font.bold: true }
            Text { font.family: Theme.fontFamily; text: clock.dateText; color: Theme.textSecondary; font.pixelSize: 18 }
        }

        ConnectionBadge {
            anchors.centerIn: parent
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            NotificationBell { }
            ActionButton {
                text: "ウィジェット"
                onClicked: aaPicker.show()
            }
            ActionButton {
                text: "ホーム"
                onClicked: root.goHome()
            }
            ActionButton {
                text: "設定"
                onClicked: root.openSettings()
            }
        }
    }

    // ---- 本体 ----
    Item {
        opacity: root.aaFade
        visible: root.aaFade > 0
        anchors {
            top: root.immersive ? parent.top : header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right
            margins: root.immersive ? 0 : Theme.margin
        }

        // ウィジェット(映像の場所以外のマス)。フルスクリーン中は隠す(動き続けるので、警告音などはそのまま)
        WidgetArea {
            id: aaWidgets
            anchors.fill: parent
            visible: !root.immersive
            enabled: !root.immersive
            pages: aaStore
            blocked: root.aaRect
            showEmptyState: false
            onSettingsRequested: (wid) => aaSettings.show(wid)
            onPickerRequested: aaPicker.show()
        }

        // Android Auto 表示領域(フルスクリーンでないときは、選んだ角のマスに置く)
        Rectangle {
            id: aaFrame
            z: 5
            x: root.immersive ? 0 : aaWidgets.cellW * root.aaRect.col + aaWidgets.pad
            y: root.immersive ? 0 : aaWidgets.cellH * root.aaRect.row + aaWidgets.pad
            width: root.immersive ? parent.width : aaWidgets.cellW * root.aaRect.w - 2 * aaWidgets.pad
            height: root.immersive ? parent.height : aaWidgets.cellH * root.aaRect.h - 2 * aaWidgets.pad
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
                    font.family: Theme.fontFamily
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "Android Auto"
                    color: Theme.textPrimary
                    font.pixelSize: 40
                }
                Text {
                    font.family: Theme.fontFamily
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: androidAuto.stateText
                    color: Theme.stateColor(androidAuto.stateKey)
                    font.pixelSize: 28
                }
                Text {
                    font.family: Theme.fontFamily
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: androidAuto.detailText
                    color: Theme.textSecondary
                    font.pixelSize: 18
                }
                Text {
                    font.family: Theme.fontFamily
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: androidAuto.stateKey === "waiting"
                    text: "スマートフォンを USB で接続してください"
                    color: Theme.textSecondary
                    font.pixelSize: 18
                }
                Text {
                    font.family: Theme.fontFamily
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

    }

    // ---- Android Auto 画面のウィジェットの設定ダイアログ・追加パネル ----
    WidgetSettingsDialog {
        id: aaSettings
        anchors.fill: parent
        z: 20
        area: aaWidgets
    }
    WidgetPicker {
        id: aaPicker
        anchors.fill: parent
        z: 21
        area: aaWidgets
    }

    // ---- フルスクリーン時のメニュー(下から出るシート) ----
    // 下端の細いつまみを上へスワイプ(またはタップ)、もしくは Esc / F10 / Menu キーで開く。
    // 閉じるのは、シートを下へスワイプ / 外側タップ / Esc / F10 / Menu キー。
    // つまみの高さの分だけ、映像の下端はタッチが届かない。
    readonly property bool sheetOpen: root.immersive && root.menuOpen
    readonly property real sheetUnit: Math.max(0.6, Math.min(width / 1280, height / 720))

    MouseArea {
        id: edgeHandle
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 28
        z: 10
        visible: root.immersive && !root.menuOpen
        onPositionChanged: (mouse) => { if (pressed && mouse.y < -30) root.menuOpen = true }
        onClicked: root.menuOpen = true

        Rectangle {
            anchors { bottom: parent.bottom; bottomMargin: 6; horizontalCenter: parent.horizontalCenter }
            width: 120; height: 6; radius: 3
            color: Theme.textSecondary
            opacity: 0.6
        }
    }

    // メニュー外(映像側)は暗くして、タップで閉じる
    Rectangle {
        anchors.fill: parent
        z: 11
        color: "black"
        opacity: root.sheetOpen ? 0.45 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        MouseArea {
            anchors.fill: parent
            enabled: root.sheetOpen
            onClicked: root.menuOpen = false
        }
    }

    Rectangle {
        id: sheet
        z: 12
        readonly property int cornerRadius: Theme.radius + 8
        width: parent.width
        // 下側の角丸を画面外へ逃がすため、角丸の分だけ高さを足して下へはみ出させる
        // システム情報の帯を出す分だけ高くする(下段のボタンの大きさは、帯の有無で変わらない)
        height: Math.max(190, root.height * 0.30) + (systemStats.showInMenu ? sheetStats.height + Theme.margin : 0) + cornerRadius
        y: root.sheetOpen ? parent.height - height + cornerRadius : parent.height
        visible: y < parent.height
        radius: cornerRadius
        color: Theme.panel
        border.color: Theme.panelBorder
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        // 下へスワイプで閉じる(ボタン以外の余白・つまみ部分で受ける)
        MouseArea {
            anchors.fill: parent
            onPositionChanged: (mouse) => { if (pressed && mouse.y > height * 0.5 + 40) root.menuOpen = false }
        }

        // つまみ(閉じられることを示す)
        Rectangle {
            anchors { top: parent.top; topMargin: 10; horizontalCenter: parent.horizontalCenter }
            width: 80; height: 6; radius: 3
            color: Theme.textSecondary
            opacity: 0.6
        }

        // 上段: 時計と接続状態(ステータスバー)
        Item {
            id: sheetInfo
            anchors { top: parent.top; topMargin: 28; left: parent.left; right: parent.right
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5 }
            height: 56 * root.sheetUnit

            Text {
                font.family: Theme.fontFamily
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: clock.timeText
                color: Theme.textPrimary
                font.pixelSize: 44 * root.sheetUnit
                font.bold: true
            }
            ConnectionBadge {
                anchors { right: alarmClear.left; rightMargin: Theme.margin; verticalCenter: parent.verticalCenter }
            }
            // 鳴っている警告をまとめて解除(右端)
            AlarmClearButton {
                id: alarmClear
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                size: Math.round(52 * root.sheetUnit)
            }
        }

        // 中段: システム情報(CPU / GPU / メモリ)。設定「システム」で非表示にできる
        SystemStatsStrip {
            id: sheetStats
            anchors { top: sheetInfo.bottom; topMargin: Theme.margin; left: parent.left; right: parent.right
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5 }
            unit: root.sheetUnit
            visible: systemStats.showInMenu
        }

        // 下段: 大型ボタン 5 つ(初期画面のナビバーと同じ内容・並び。終了ボタンは置かない)
        Item {
            id: sheetButtons
            anchors {
                top: systemStats.showInMenu ? sheetStats.bottom : sheetInfo.bottom; topMargin: Theme.margin
                left: parent.left; right: parent.right
                leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5
                bottom: parent.bottom; bottomMargin: Theme.margin * 1.5 + sheet.cornerRadius
            }
            readonly property real cellW: (width - 4 * Theme.margin) / 5

            LauncherTile {
                x: 0; width: sheetButtons.cellW; height: sheetButtons.height; unit: root.sheetUnit
                icon: "home"; title: "ホーム"
                onClicked: { root.menuOpen = false; root.goHome() }
            }
            LauncherTile {
                x: 1 * (sheetButtons.cellW + Theme.margin); width: sheetButtons.cellW; height: sheetButtons.height; unit: root.sheetUnit
                icon: "graphic_eq"; title: "オーディオ"
                onClicked: root.showMock("オーディオ操作")
            }
            LauncherTile {
                x: 2 * (sheetButtons.cellW + Theme.margin); width: sheetButtons.cellW; height: sheetButtons.height; unit: root.sheetUnit
                icon: "widgets"; title: "ウィジェット"
                onClicked: { root.menuOpen = false; root.goHome(); launcher.openPicker() }
            }
            LauncherTile {
                x: 3 * (sheetButtons.cellW + Theme.margin); width: sheetButtons.cellW; height: sheetButtons.height; unit: root.sheetUnit
                icon: "directions_car"; title: "車両連携"
                onClicked: root.showMock("車両連携")
            }
            LauncherTile {
                x: 4 * (sheetButtons.cellW + Theme.margin); width: sheetButtons.cellW; height: sheetButtons.height; unit: root.sheetUnit
                icon: "settings"; title: "設定"
                onClicked: { root.menuOpen = false; root.openSettings() }
            }
        }
    }
}
