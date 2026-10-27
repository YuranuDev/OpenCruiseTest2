// アプリのルート。メイン画面と設定画面を StackView で切り替える。
import QtQuick
import QtQuick.Controls
import OpenCruise

ApplicationWindow {
    id: window
    width: 1280
    height: 720
    visible: true
    // アプリのテーマ(昼夜・アクセント色)を Theme へ反映する。Theme 側で補間アニメーションされる
    // (切り替えは themeSnap が受け持つ: 切り替え前の画面を画像にして重ね、テーマを一度で変えてから画像を薄くする)
    readonly property bool wantNight: androidAuto.nightActive
    readonly property int wantAccent: androidAuto.accentIndex
    onWantNightChanged: themeSnap.request()
    onWantAccentChanged: themeSnap.request()
    // 画面サイズに応じた拡大率(1280x720 基準)。設定画面など、寸法を拡大率で決める部品が Theme.uiScale を参照する
    Binding { target: Theme; property: "uiScale"; value: Math.max(0.6, Math.min(rotor.width / 1280, rotor.height / 720)) }
    // 選択中のフォント。同梱フォントを読み込めず空のときは OS 既定のまま
    Binding { target: Theme; property: "fontFamily"; value: appSettings.fontFamily; when: appSettings.fontFamily !== "" }

    // 映像表示中かつ「接続後フルスクリーン」設定が有効で、メイン画面を見ているとき
    readonly property bool immersive: androidAuto.fullscreenOnStream && androidAuto.stateKey === "streaming"
                                      && showAa && stack.depth === 1
    // Android Auto 画面を表示中か。映像が出始めたら自動で切り替え、止まったら初期画面へ戻す
    property bool showAa: false
    readonly property bool streaming: androidAuto.stateKey === "streaming"
    onStreamingChanged: showAa = streaming
    visibility: (startFullscreen || immersive) ? Window.FullScreen : Window.Windowed
    title: "OpenCruise"

    // ---- 表示する画面(設定「表示 > 画面」)。選んだ画面が無ければメイン画面に出し、つながったら戻る ----
    function findScreen(name) {
        const list = Qt.application.screens
        for (let i = 0; i < list.length; ++i) {
            if (list[i].name === name) return list[i]
        }
        return list.length > 0 ? list[0] : null
    }
    // eglfs では、ウィンドウを作った後に別の画面へ移すと描画先が無くなり("Cannot sync before platform init!")
    // 何も表示されない。eglfs では操作する画面(DrmDisplay が起動前に決める)に任せ、画面は動かさない
    Component.onCompleted: {
        themeSnap.apply()   // 起動時はそのまま反映する
        if (!displaySettings.isEglfs)
            window.screen = Qt.binding(() => window.findScreen(displaySettings.targetScreenName))
        if (!splashExport) systemSound.play("start")   // 起動画面の書き出し(--export-splash)では鳴らさない
    }
    onScreenChanged: if (!displaySettings.isEglfs) Qt.callLater(window.placeOnScreen)
    // 画面を移ったとき: 全画面なら一度ウィンドウに戻して出し直し、ウィンドウ表示なら新しい画面の中央へ置く
    function placeOnScreen() {
        if (!window.screen) return
        if (window.visibility === Window.FullScreen) {
            window.visibility = Window.Windowed
            window.x = window.screen.virtualX
            window.y = window.screen.virtualY
            window.visibility = Qt.binding(() => (startFullscreen || window.immersive) ? Window.FullScreen : Window.Windowed)
        } else {
            window.x = window.screen.virtualX + Math.max(0, (window.screen.width - window.width) / 2)
            window.y = window.screen.virtualY + Math.max(0, (window.screen.height - window.height) / 2)
        }
    }
    color: Theme.background

    // 起動音(起動画面が出るタイミングで鳴らす。音量・出力先は設定の「システム」に従う)は上の Component.onCompleted で鳴らす

    // 下から出るメニュー(シート)を開閉する。設定画面などを開いているときは、メイン画面へ戻ってから開く
    function toggleMenu() {
        if (boot.active || exitConfirmation.opened) return
        if (stack.depth > 1) {
            stack.pop(null)
            if (stack.currentItem) stack.currentItem.menuOpen = true
            return
        }
        if (stack.currentItem) stack.currentItem.menuOpen = !stack.currentItem.menuOpen
    }

    // 起動画面中の Esc はスキップ。メニューが開いていれば閉じ、フルスクリーン中はメニューを開閉し、ホームでは終了確認を出す。
    Shortcut {
        sequence: "Esc"
        onActivated: {
            if (exitConfirmation.opened) {
                exitConfirmation.close()
            } else if (notifications.historyOpen) {
                notifications.historyOpen = false // 通知履歴を開いている間は、まずそれを閉じる
            } else if (boot.active) {
                boot.skip()
            } else if (stack.depth === 1 && stack.currentItem && stack.currentItem.menuOpen) {
                stack.currentItem.menuOpen = false
            } else if (window.immersive && stack.currentItem) {
                stack.currentItem.menuOpen = !stack.currentItem.menuOpen
            } else if (stack.depth > 1) {
                stack.pop()
            } else {
                exitConfirmation.open()
            }
        }
    }

    Shortcut {
        sequences: ["F10", "Menu"]
        onActivated: window.toggleMenu()
    }

    // ---- 音量・明るさのショートカット ----
    // 既存のキー(Esc / F10 / Menu / Meta・Super / Ctrl+Shift+D)や、OS・ブラウザが奪いやすい
    // メディアキー(Volume Up など。OS 側の音量とも二重になる)・Alt 系・Ctrl+Alt+矢印は使わない。
    // すべて Ctrl+Shift+文字。将来の物理ボタンも、同じキーイベントを送れば同じ動作になる。
    // どちらも「キーボードで左のキー = 下げる、右のキー = 上げる」にそろえる(隣り合う 2 つのキー)。
    //   Ctrl+Shift+V / B   マスター音量を下げる / 上げる(V = Volume。各系統の個別音量はそのまま。
    //                      Ctrl+Shift を押さえた左手の人差し指で届く)
    //   Ctrl+Shift+K / L   画面の明るさを下げる / 上げる(L = Light)
    // 押しっぱなしで連続して変わる。操作すると、対応する表示が出て、しばらくして自動で閉じる。
    readonly property int volumeStep: 5
    readonly property int brightnessStep: 10

    Shortcut {
        sequence: "Ctrl+Shift+V"
        onActivated: { audioSettings.adjustMasterVolume(-window.volumeStep); brightnessOsd.hide(); volumeOsd.show() }
    }
    Shortcut {
        sequence: "Ctrl+Shift+B"
        onActivated: { audioSettings.adjustMasterVolume(window.volumeStep); brightnessOsd.hide(); volumeOsd.show() }
    }
    Shortcut {
        sequence: "Ctrl+Shift+L"
        onActivated: { brightnessController.adjustBrightness(window.brightnessStep); volumeOsd.hide(); brightnessOsd.show() }
    }
    Shortcut {
        sequence: "Ctrl+Shift+K"
        onActivated: { brightnessController.adjustBrightness(-window.brightnessStep); volumeOsd.hide(); brightnessOsd.show() }
    }

    // ---- コンソールへ(eglfs のときだけ) ----
    // eglfs ではアプリが画面とキーボードを使っているので、Ctrl+Alt+F2 などで画面(VT)を切り替えられない。
    // 代わりに、これらのキーでアプリを終了する。自動起動のサービス(scripts/bootsplash)は、終了すると tty1 に
    // ログイン画面を出す(アプリに戻るときは sudo systemctl start opencruise)
    Shortcut {
        enabled: displaySettings.isEglfs
        context: Qt.ApplicationShortcut
        sequences: ["Ctrl+Alt+Backspace", "Ctrl+Alt+F1", "Ctrl+Alt+F2", "Ctrl+Alt+F3", "Ctrl+Alt+F4", "Ctrl+Alt+F5", "Ctrl+Alt+F6"]
        onActivated: {
            console.info("[app] コンソールへ切り替えるため終了します(Ctrl+Alt+F1〜F6 / Ctrl+Alt+Backspace)")
            Qt.quit()
        }
    }

    // ---- テーマ(昼夜・アクセント色)の切り替え ----
    // 色をアニメーションさせると、色を使うすべての部品(メーターの描画など)が毎フレーム計算し直しになり重い。
    // そこで、切り替え前の画面(rotor)を 1 枚の画像に写して上に重ね、その下でテーマを一度で切り替え、
    // 画像だけを薄くしていく(動かすのは画像 1 枚の不透明度だけ)。
    ShaderEffectSource {
        id: themeSnap
        z: 1000
        anchors.centerIn: parent
        width: rotor.width
        height: rotor.height
        rotation: rotor.rotation
        sourceItem: rotor
        live: false
        hideSource: false
        visible: false
        enabled: false   // タッチは下へ通す
        property bool pending: false
        // 写したフレームを確実に過ぎてから切り替えるため、2 フレーム待つ(描画が別スレッドのときの行き違い対策)
        property int waitFrames: 0

        function apply() {
            Theme.night = window.wantNight
            Theme.accentIndex = window.wantAccent
        }
        function request() {
            if (Theme.night === window.wantNight && Theme.accentIndex === window.wantAccent) return
            if (pending) return   // 写している最中。写し終えたときに今の値で切り替える
            if (!window.visible || rotor.width <= 0) { apply(); return }
            themeFade.stop()
            opacity = 1
            visible = true
            pending = true
            waitFrames = 2
            scheduleUpdate()   // 次のフレームで今の画面を写す
        }
        // 写し終えたフレームの後で切り替え、画像を薄くする
        Connections {
            target: window
            enabled: themeSnap.pending
            function onFrameSwapped() {
                if (--themeSnap.waitFrames > 0) { window.requestUpdate(); return }
                themeSnap.pending = false
                themeSnap.apply()
                themeFade.restart()
            }
        }
        NumberAnimation {
            id: themeFade
            target: themeSnap
            property: "opacity"
            from: 1
            to: 0
            duration: 500
            easing.type: Easing.InOutQuad
            onFinished: themeSnap.visible = false
        }
    }

    // ---- 画面の回転(設定「表示 > 画面」)。表示する部品はすべてこの中に置き、回転と縦横の入れ替えを受ける ----
    // 入力(タッチ・マウス)の座標も回転に合わせて変換される。
    Item {
        id: rotor
        readonly property bool quarter: displaySettings.rotation === 90 || displaySettings.rotation === 270
        anchors.centerIn: parent
        width: quarter ? parent.height : parent.width
        height: quarter ? parent.width : parent.height
        rotation: displaySettings.rotation

        // Windows キー(Meta / Super)で下から出るメニューを開閉する(どの画面でも。設定画面からはメイン画面へ戻って開く)
        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true
            Component.onCompleted: forceActiveFocus()
            Keys.onPressed: (event) => {
                if (!event.isAutoRepeat
                        && (event.key === Qt.Key_Meta || event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R)) {
                    window.toggleMenu()
                    event.accepted = true
                }
                // 昼夜モード切り替え（Ctrl+Shift+D）
                if (!event.isAutoRepeat && event.key === Qt.Key_D && event.modifiers & Qt.ControlModifier && event.modifiers & Qt.ShiftModifier) {
                    androidAuto.themeMode = androidAuto.nightActive ? 0 : 1
                    event.accepted = true
                }
            }
        }

        // 通知履歴パネル(ベルボタンで開く。ポップアップより下、各画面より上)
        NotificationHistoryPanel {
            anchors.fill: parent
            z: 90
        }

        // スマートフォン通知は、設定で許可したときだけ画面上部にポップアップする。
        Connections {
            target: phoneStatus
            function onNoticeReceived(notice) {
                if (!appSettings.phoneNoticePopupEnabled)
                    return
                const message = String(notice.text || "").trim()
                if (message === "")
                    return
                notifications.show("スマホ通知", message, 0, notice.icon || "notifications", 5000)
            }
        }

        // 警告音(メーターのしきい値超え)。鳴らす場所はここだけ。どのウィジェットが警告中かは WarningAlarm が管理する
        Connections {
            target: WarningAlarm
            function onBeep() { systemSound.play("alert") }
            function onCautionBeep() { systemSound.play("caution") }   // 注意音(注意値を超えたときに 1 回)
        }
        Binding { target: WarningAlarm; property: "interval"; value: systemSound.alertInterval }
        Binding { target: WarningAlarm; property: "continuous"; value: systemSound.alertContinuous }
        // 「ずっと鳴らす」のとき、鳴らしている警告がある間はループ再生する
        Binding { target: systemSound; property: "alertActive"; value: WarningAlarm.soundingCount > 0 }

        // グラフ用に、車両データ(メーターと同じ計測値。基本単位)を一定間隔で履歴へ入れる
        Timer {
            interval: VehicleHistory.sampleMs
            running: can.dataAvailable   // データ源が無い間は記録しない
            repeat: true
            onTriggered: VehicleHistory.push({
                boost: can.boostBar, rpm: can.rpm, speed: can.speedKmh, coolant: can.coolantTempC,
                fuel: can.fuelPercent, oilTemp: can.oilTempC, oilPressure: can.oilPressureBar, voltage: can.batteryVolts,
                throttle: can.throttlePercent, brake: can.brakePercent
            })
        }

        Connections {
            target: can
            function onDataAvailableChanged() { if (!can.dataAvailable) VehicleHistory.clear() }
        }

        // 画面上部のポップアップ通知（映像表示中も最前面）
        NotificationPopup {
            z: 100
            anchors.top: parent.top
            anchors.topMargin: Theme.margin
            anchors.horizontalCenter: parent.horizontalCenter
        }

        StackView {
            id: stack
            anchors.fill: parent

            // 新しい画面が入る：少し拡大した状態から通常サイズへ
            pushEnter: Transition {
                ParallelAnimation {
                    NumberAnimation {
                        property: "opacity"
                        from: 0.0
                        to: 1.0
                        duration: 220
                        easing.type: Easing.OutCubic
                    }

                    NumberAnimation {
                        property: "scale"
                        from: 1.035
                        to: 1.0
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }
            }

            // 現在の画面が後ろへ移動：控えめに縮小・フェード
            pushExit: Transition {
                ParallelAnimation {
                    NumberAnimation {
                        property: "opacity"
                        from: 1.0
                        to: 0.75
                        duration: 180
                        easing.type: Easing.OutCubic
                    }

                    NumberAnimation {
                        property: "scale"
                        from: 1.0
                        to: 0.985
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }
            }

            // 前の画面に戻る：通常サイズへ拡大・フェードイン
            popEnter: Transition {
                ParallelAnimation {
                    NumberAnimation {
                        property: "opacity"
                        from: 0.75
                        to: 1.0
                        duration: 220
                        easing.type: Easing.OutCubic
                    }

                    NumberAnimation {
                        property: "scale"
                        from: 0.985
                        to: 1.0
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }
            }

            // 現在の画面が消える：少し縮小しながらフェードアウト
            popExit: Transition {
                ParallelAnimation {
                    NumberAnimation {
                        property: "opacity"
                        from: 1.0
                        to: 0.0
                        duration: 180
                        easing.type: Easing.InCubic
                    }

                    NumberAnimation {
                        property: "scale"
                        from: 1.0
                        to: 0.965
                        duration: 180
                        easing.type: Easing.InCubic
                    }
                }
            }

            // メイン画面は、起動画面が 1 度描かれてから作る(作るのに時間がかかるので、先に起動画面を出す)。
            // 作るのも分けて少しずつ進め(非同期)、その間も起動画面のアニメーションが止まらないようにする
            Component.onCompleted: {
                if (splashExport) {
                    // 起動画面の書き出し(--export-splash): メイン画面は作らない(起動画面だけを描く)
                } else if (startOnSettings) {
                    stack.push(settingsComponent)
                    boot.report("home", 5, "設定画面から起動")       // 5 = Skipped
                    boot.report("widgets", 5, "設定画面から起動")
                } else {
                    homeLoader.waiting = true
                }
            }
        }
        QtObject {
            id: homeLoader
            property bool waiting: false   // 起動画面の最初の 1 枚を待っている
            property var incubator: null
            property bool ready: false     // メイン画面ができた(できるまで起動画面を消さない)
            property real startedAt: 0
            function create() {
                startedAt = Date.now()
                boot.report("home", 1, "作成中")                         // 1 = Running
                boot.report("widgets", 1, "メイン画面の作成を待っています")
                const inc = homeComponent.incubateObject(stack, {}, Qt.Asynchronous)
                const done = () => {
                    if (inc.status === Component.Ready) {
                        stack.push(inc.object, {}, StackView.Immediate)
                        homeLoader.ready = true
                        const ms = Date.now() - startedAt
                        boot.report("home", 2, ms + " ms")                // 2 = Ready
                        console.info("[boot] メイン画面を作りました (" + ms + " ms。起動画面を出したまま、少しずつ作成)")
                        widgetWatch.update()
                    } else if (inc.status === Component.Error) {
                        console.error("[boot] メイン画面を作れませんでした")
                        boot.report("home", 4, "作成に失敗しました")      // 4 = Failed
                        widgetWatch.finished = true
                        boot.report("widgets", 5, "メイン画面を作れなかったため中止")
                        homeLoader.ready = true   // 起動画面のまま固まらないようにする
                    }
                }
                if (inc.status !== Component.Loading) done()
                else inc.onStatusChanged = (status) => done()
                incubator = inc
            }
        }
        // 起動画面の「ウィジェット」の段階: 作っている途中の数を見て、すべて作り終えたら完了にする(起動時の 1 回だけ)
        QtObject {
            id: widgetWatch
            property bool finished: false
            property string lastText: ""
            function update() {
                if (finished || homeLoader.startedAt === 0) return
                const loading = WidgetRegistry.widgetsLoading, loaded = WidgetRegistry.widgetsLoaded
                // メイン画面を作っている間は、全部で何個になるかまだ分からないので、できた数だけ出す
                if (!homeLoader.ready || loading > 0) {
                    const text = homeLoader.ready ? "作成中 " + loaded + " / " + (loaded + loading) + " 個"
                                                  : "作成中 " + loaded + " 個できました"
                    if (text !== lastText) { lastText = text; boot.report("widgets", 1, text) }
                    return
                }
                finished = true
                boot.report("widgets", 2, loaded + " 個 (" + (Date.now() - homeLoader.startedAt) + " ms)")
            }
        }
        Connections {
            target: WidgetRegistry
            enabled: homeLoader.startedAt > 0 && !widgetWatch.finished
            function onWidgetsLoadingChanged() { Qt.callLater(widgetWatch.update) }
            function onWidgetsLoadedChanged() { Qt.callLater(widgetWatch.update) }
        }
        Connections {
            target: window
            enabled: homeLoader.waiting
            function onFrameSwapped() {
                homeLoader.waiting = false
                Qt.callLater(homeLoader.create)
            }
        }

        // 起動(オープニング)画面。外部機器などの待ちが終わるまで最前面に出し、終わったらフェードアウトする
        SplashScreen {
            id: splash
            objectName: "splash"   // --export-splash で C++ から探す
            anchors.fill: parent
            z: 50
            // 待ちが終わっても、メイン画面ができるまでは起動画面を出したままにする(空の画面を見せない)
            opacity: (boot.done && (homeLoader.ready || startOnSettings)) ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
        }

        // 画面の明るさ(ソフトウェア方式のときだけ不透明度が 0 より大きくなる黒い幕)。
        // 入力は受けない(MouseArea を持たない)。映像・起動画面を含む全体を暗くするため、最前面に近い位置に置く。
        Rectangle {
            anchors.fill: parent
            z: 1000
            color: "black"
            opacity: brightnessController.overlayOpacity
            visible: opacity > 0
        }

        // 音量・明るさの操作表示(幕より手前に置き、明るさを下げても読めるようにする)
        // 音量・明るさの表示は、どちらも画面の下の中央に小さく出す(同じ幅・同じ位置。片方を出すともう片方は閉じる)
        VolumeOsd {
            id: volumeOsd
            z: 1100
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40 * Theme.uiScale
        }
        BrightnessOsd {
            id: brightnessOsd
            z: 1100
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40 * Theme.uiScale
        }

        // ---- 終了確認(画面の回転に合わせて回るよう、Popup ではなく通常の部品で作る) ----
        Item {
            id: exitConfirmation
            property bool opened: false
            function open() { opened = true }
            function close() { opened = false }

            anchors.fill: parent
            z: 1200
            visible: scrim.opacity > 0

            Rectangle {
                id: scrim
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.55)
                opacity: exitConfirmation.opened ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
                MouseArea { anchors.fill: parent }   // 背後を操作させない
            }

            // Basic スタイルの既定(白背景・黒文字)だと夜間配色で文字が読めないため、テーマの色で描く
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(480, rotor.width - Theme.margin * 2)
                height: exitColumn.implicitHeight + Theme.margin * 3
                radius: Theme.radius + 8
                color: Theme.panel
                border.color: Theme.panelBorder
                scale: exitConfirmation.opened ? 1 : 0.94
                opacity: exitConfirmation.opened ? 1 : 0
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 160 } }

                Column {
                    id: exitColumn
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.margin * 1.5 }
                    spacing: Theme.margin
                    Text {
                        text: "終了確認"
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.bold: true
                        font.pixelSize: 24
                    }
                    Text {
                        width: parent.width
                        text: "アプリを終了しますか？"
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: 22
                        wrapMode: Text.WordWrap
                    }
                    Row {
                        width: parent.width
                        spacing: 12
                        layoutDirection: Qt.RightToLeft
                        ActionButton {
                            text: "終了"
                            onClicked: Qt.quit()
                        }
                        ActionButton {
                            text: "キャンセル"
                            onClicked: exitConfirmation.close()
                        }
                    }
                }
            }
        }
    }

    Component {
        id: homeComponent
        HomeScreen {
            immersive: window.immersive
            showAa: window.showAa
            onOpenSettings: stack.push(settingsComponent)
            onGoHome: window.showAa = false
            onOpenAndroidAuto: window.showAa = true
        }
    }

    Component {
        id: settingsComponent
        SettingsScreen {
            onBack: stack.pop()
        }
    }
}
