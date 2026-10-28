// メイン画面。showAa が false の間は初期画面(LauncherScreen)、true の間は Android Auto 画面
// (初期画面と同じステータスバー + Android Auto 表示領域とウィジェット)を表示する。
// 画面を切り替えるボタン類(ホーム・ウィジェット・設定など)は、下から出るメニュー(シート)にまとめる。
// メニューはステータスバーの「メニュー」ボタン・Windows キー・Esc / F10 / Menu キーで開閉する(どの画面でも)。
// フルスクリーンでないときの本体は、初期画面と同じ 12 × 6 マスのウィジェット配置エリアで、Android Auto の映像は
// その角(設定「Android Auto」で角と幅・高さのマス数を選ぶ。widgetStore.aaCorner / aaCols / aaRows)に置き、
// 残りのマスにウィジェットを置ける(配置は初期画面とは別に widgetStore.aaLayoutJson へ保存)。
// 映像の描画アイテム(VideoSurfaceItem)は表示切替で破棄しないよう、常に生成しておく。
// ウィジェットの編集モード(メニューの「編集」): Android Auto 画面では、そこのウィジェットと映像の場所を編集する。
// 映像は、内側の角のつまみをドラッグで大きさ(マス数)、映像そのものをドラッグで置く角を変えられる(離したときに決まる)。
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
    // 下から出るメニュー(シート)が開いているか。フルスクリーンの切り替わりや画面の切り替えでは閉じる
    property bool menuOpen: false
    onImmersiveChanged: { menuOpen = false; aaEditing = false }
    onShowAaChanged: { menuOpen = false; aaEditing = false }
    // Android Auto 画面のウィジェットの編集モード
    property bool aaEditing: false
    function openAaSettingsFor(entries) {
        if (entries.length === 0) return
        aaSettings.area = aaWidgets
        if (entries.length > 1) aaSettings.showMulti(entries)
        else aaSettings.show(entries[0].wid)
    }

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

    // ---- ステータスバー(初期画面と同じ形: 左に接続状態のアイコン、中央に時刻、右にメニュー・通知・警告の解除) ----
    Item {
        id: header
        anchors {
            top: parent.top; left: parent.left; right: parent.right
            topMargin: Theme.margin * 1.5; leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5
        }
        height: 52
        opacity: root.aaFade
        visible: root.aaFade > 0 && !root.immersive

        // 編集モードの間は、ステータスバーの代わりに編集用のバーを出す
        WidgetEditBar {
            anchors.fill: parent
            z: 2
            opacity: root.aaEditing ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            area: aaWidgets
            onAddRequested: aaPicker.show()
            onSettingsRequested: (entries) => root.openAaSettingsFor(entries)
            onDoneRequested: root.aaEditing = false
        }

        ConnectionBadge {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            size: parent.height
            visible: !root.aaEditing
        }

        // 時刻(初期画面のページのタブの位置)
        Rectangle {
            visible: !root.aaEditing
            anchors.centerIn: parent
            height: parent.height - 4
            width: timeText.implicitWidth + 40
            radius: height / 2
            color: Theme.panel
            border.color: Theme.panelBorder
            Text {
                id: timeText
                anchors.centerIn: parent
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: Math.round(parent.height * 0.5)
                color: Theme.textPrimary
                text: clock.timeText
            }
        }

        Row {
            visible: !root.aaEditing
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 12
            ActionButton {
                selected: root.menuOpen
                text: "メニュー"
                onClicked: root.menuOpen = !root.menuOpen
            }
            NotificationBell { }
            AlarmClearButton { }   // 鳴っている警告をまとめて解除(右端。初期画面と同じ)
        }
    }

    // ---- 本体 ----
    Item {
        opacity: root.aaFade
        visible: root.aaFade > 0
        anchors {
            top: root.immersive ? parent.top : header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right
            // 余白は初期画面のウィジェット配置エリアと同じ
            topMargin: root.immersive ? 0 : Theme.margin
            leftMargin: root.immersive ? 0 : Theme.margin * 1.5
            rightMargin: root.immersive ? 0 : Theme.margin * 1.5
            // 下端はメニューのつまみ(edgeHandle)の分だけ空ける
            bottomMargin: root.immersive ? 0 : edgeHandle.height + 4
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
            editMode: root.aaEditing
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

            // ---- 編集モード: 映像の大きさ・置く角を変える(映像へのタッチは送らない) ----
            Item {
                id: aaEdit
                anchors.fill: parent
                visible: root.aaEditing && !root.immersive
                readonly property real u: Theme.uiScale
                readonly property int corner: widgetStore.aaCorner
                readonly property bool atRight: corner === 1 || corner === 3
                readonly property bool atBottom: corner >= 2

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.45)
                    border.width: 2
                    border.color: Theme.accent
                    radius: aaFrame.radius
                }
                // 映像そのものをドラッグ: 離した位置に近い角へ移す
                MouseArea {
                    id: aaMove
                    anchors.fill: parent
                    preventStealing: true
                    property point start
                    property bool active: false
                    onPressed: (m) => { start = Qt.point(m.x, m.y); active = false }
                    onPositionChanged: (m) => {
                        if (!active && Math.hypot(m.x - start.x, m.y - start.y) > 12 * aaEdit.u) active = true
                        if (!active) return
                        const p = aaFrame.mapToItem(aaWidgets, m.x - start.x + aaFrame.width / 2, m.y - start.y + aaFrame.height / 2)
                        aaGhost.show(widgetStore.aaCols, widgetStore.aaRows,
                                     (p.x > aaWidgets.width / 2 ? 1 : 0) + (p.y > aaWidgets.height / 2 ? 2 : 0))
                    }
                    onReleased: { if (active) aaGhost.apply(); active = false }
                    onCanceled: { aaGhost.hide(); active = false }
                }
                // 真ん中の表示: 「Android Auto」と大きさ
                Column {
                    anchors.centerIn: parent
                    spacing: 6 * aaEdit.u
                    MaterialIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: "open_with"
                        size: Math.round(44 * aaEdit.u)
                        color: Theme.accent
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(26 * aaEdit.u)
                        font.bold: true
                        color: Theme.textPrimary
                        text: "Android Auto  " + (aaGhost.visible ? aaGhost.cols + " x " + aaGhost.rows
                                                                    : widgetStore.aaCols + " x " + widgetStore.aaRows)
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(18 * aaEdit.u)
                        color: Theme.textSecondary
                        text: "ドラッグで角を移動 ・ 角のつまみで大きさを変更"
                    }
                }
                // 大きさのつまみ(映像の内側の角。画面の角と反対側)
                Rectangle {
                    id: aaHandle
                    readonly property real s: Math.round(56 * aaEdit.u)
                    width: s
                    height: s
                    radius: s / 2
                    x: aaEdit.atRight ? 6 * aaEdit.u : parent.width - s - 6 * aaEdit.u
                    y: aaEdit.atBottom ? 6 * aaEdit.u : parent.height - s - 6 * aaEdit.u
                    color: Theme.mix(Theme.panel, Theme.accent, aaResize.pressed ? 0.5 : 0.2)
                    border.width: 2
                    border.color: Theme.accent
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "open_in_full"
                        size: Math.round(parent.width * 0.55)
                        color: Theme.accent
                        // 引っぱる向き(内側の角の向き)に合わせて回す。アイコンは右上・左下向き
                        rotation: (aaEdit.atRight === aaEdit.atBottom) ? 90 : 0
                    }
                    MouseArea {
                        id: aaResize
                        anchors.fill: parent
                        anchors.margins: -8 * aaEdit.u   // 少し広めに受ける
                        preventStealing: true
                        onPositionChanged: (m) => {
                            if (!pressed) return
                            const p = aaResize.mapToItem(aaWidgets, m.x, m.y)
                            const c = Math.round((aaEdit.atRight ? aaWidgets.width - p.x : p.x) / aaWidgets.cellW)
                            const r = Math.round((aaEdit.atBottom ? aaWidgets.height - p.y : p.y) / aaWidgets.cellH)
                            aaGhost.show(c, r, aaEdit.corner)
                        }
                        onReleased: aaGhost.apply()
                        onCanceled: aaGhost.hide()
                    }
                }
            }
        }

        // 編集中に、離したときの映像の場所(大きさ・角)を示す枠
        Rectangle {
            id: aaGhost
            z: 6
            visible: false
            property int cols: 9
            property int rows: 6
            property int corner: 0
            // 映像の大きさの範囲(WidgetStore と同じ)
            readonly property int minCols: 4
            readonly property int minRows: 2
            function show(c, r, k) {
                cols = Math.max(minCols, Math.min(aaWidgets.cols, c))
                rows = Math.max(minRows, Math.min(aaWidgets.rows, r))
                corner = k
                visible = true
            }
            function hide() { visible = false }
            function apply() {
                if (!visible) return
                visible = false
                widgetStore.aaCorner = corner
                widgetStore.aaCols = cols
                widgetStore.aaRows = rows
            }
            readonly property int col: (corner === 1 || corner === 3) ? aaWidgets.cols - cols : 0
            readonly property int row: corner >= 2 ? aaWidgets.rows - rows : 0
            x: aaWidgets.cellW * col + aaWidgets.pad
            y: aaWidgets.cellH * row + aaWidgets.pad
            width: aaWidgets.cellW * cols - 2 * aaWidgets.pad
            height: aaWidgets.cellH * rows - 2 * aaWidgets.pad
            radius: Theme.radius
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
            border.width: 3
            border.color: Theme.accent
            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
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

    // ---- 下から出るメニュー(シート)。初期画面・Android Auto 画面・フルスクリーンのどれでも使う ----
    // 開く: Windows キー / Esc(フルスクリーン中) / F10 / Menu キー、Android Auto 画面のステータスバーの「メニュー」、
    //       Android Auto 画面(フルスクリーンも)では下端の細いつまみを上へスワイプ(またはタップ)
    // 閉じる: シートを下へスワイプ / 外側タップ / 同じキー
    // フルスクリーン中は、つまみの高さの分だけ映像の下端はタッチが届かない。
    readonly property bool sheetOpen: root.menuOpen
    readonly property real sheetUnit: Math.max(0.6, Math.min(width / 1280, height / 720))

    // 下端のつまみ(上へスワイプ・タップでメニューを開く)。Android Auto 画面では、フルスクリーンでなくても出す
    MouseArea {
        id: edgeHandle
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 28
        z: 10
        visible: (root.immersive || root.showAa) && !root.menuOpen
        opacity: root.immersive ? 1 : root.aaFade
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

        // 上段: 時計と接続状態(アイコン)・警告の解除
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
                size: Math.round(52 * root.sheetUnit)
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

        // 下段: 大型ボタン 6 つ(初期画面のナビバーと同じ内容・並び。終了ボタンは置かない)
        Item {
            id: sheetButtons
            anchors {
                top: systemStats.showInMenu ? sheetStats.bottom : sheetInfo.bottom; topMargin: Theme.margin
                left: parent.left; right: parent.right
                leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5
                bottom: parent.bottom; bottomMargin: Theme.margin * 1.5 + sheet.cornerRadius
            }
            readonly property real cellW: (width - 5 * Theme.margin) / 6

            LauncherTile {
                x: 0; width: sheetButtons.cellW; height: sheetButtons.height; unit: root.sheetUnit
                icon: "home"; title: "ホーム"
                selected: !root.showAa
                onClicked: { root.menuOpen = false; root.goHome() }
            }
            LauncherTile {
                x: 1 * (sheetButtons.cellW + Theme.margin); width: sheetButtons.cellW; height: sheetButtons.height; unit: root.sheetUnit
                icon: "mdi:android"; title: "Android Auto"
                selected: root.showAa
                dimmed: androidAuto.stateKey !== "streaming"
                onClicked: {
                    if (androidAuto.stateKey !== "streaming") {
                        notifications.show("Android Auto", "スマートフォンが接続されていません", 0, "mdi:android")
                        return
                    }
                    root.menuOpen = false
                    root.openAndroidAuto()
                }
            }
            LauncherTile {
                x: 2 * (sheetButtons.cellW + Theme.margin); width: sheetButtons.cellW; height: sheetButtons.height; unit: root.sheetUnit
                icon: "graphic_eq"; title: "オーディオ"
                onClicked: root.showMock("オーディオ操作")
            }
            LauncherTile {
                x: 3 * (sheetButtons.cellW + Theme.margin); width: sheetButtons.cellW; height: sheetButtons.height; unit: root.sheetUnit
                icon: "dashboard_customize"; title: "編集"
                selected: root.showAa ? root.aaEditing : launcher.editing
                // フルスクリーンでない Android Auto 画面なら、その画面のウィジェットと映像の場所を編集する。それ以外は初期画面で編集
                onClicked: {
                    root.menuOpen = false
                    if (root.showAa && !root.immersive) root.aaEditing = !root.aaEditing
                    else { root.goHome(); launcher.setEditing(true) }
                }
            }
            LauncherTile {
                x: 4 * (sheetButtons.cellW + Theme.margin); width: sheetButtons.cellW; height: sheetButtons.height; unit: root.sheetUnit
                icon: "directions_car"; title: "車両連携"
                onClicked: root.showMock("車両連携")
            }
            LauncherTile {
                x: 5 * (sheetButtons.cellW + Theme.margin); width: sheetButtons.cellW; height: sheetButtons.height; unit: root.sheetUnit
                icon: "settings"; title: "設定"
                onClicked: { root.menuOpen = false; root.openSettings() }
            }
        }
    }
}
