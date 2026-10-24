// アプリのルート。メイン画面と設定画面を StackView で切り替える。
import QtQuick
import QtQuick.Controls
import QtQml.Models

ApplicationWindow {
    id: window
    width: 1280
    height: 720
    visible: true
    // アプリのテーマ(昼夜・アクセント色)を Theme へ反映する。Theme 側で補間アニメーションされる
    Binding { target: Theme; property: "night"; value: androidAuto.nightActive }
    Binding { target: Theme; property: "accentIndex"; value: androidAuto.accentIndex }
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
    screen: findScreen(displaySettings.targetScreenName)
    onScreenChanged: Qt.callLater(window.placeOnScreen)
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

    // 起動音(起動画面が出るタイミングで鳴らす。音量・出力先は設定の「システム」に従う)
    Component.onCompleted: systemSound.play("start")

    // 起動画面中の Esc はスキップ。フルスクリーン中はメニューを開閉し、ホームでは終了確認を出す。
    Shortcut {
        sequence: "Esc"
        onActivated: {
            if (exitConfirmation.opened) {
                exitConfirmation.close()
            } else if (notifications.historyOpen) {
                notifications.historyOpen = false // 通知履歴を開いている間は、まずそれを閉じる
            } else if (boot.active) {
                boot.skip()
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
        enabled: window.immersive
        onActivated: if (stack.currentItem) stack.currentItem.menuOpen = !stack.currentItem.menuOpen
    }

    // ---- 音量・明るさのショートカット ----
    // 既存のキー(Esc / F10 / Menu / Meta・Super / Ctrl+Shift+D)や、OS・ブラウザが奪いやすい
    // メディアキー(Volume Up など。OS 側の音量とも二重になる)・Alt 系・Ctrl+Alt+矢印は使わない。
    // すべて Ctrl+Shift+文字。将来の物理ボタンも、同じキーイベントを送れば同じ動作になる。
    //   Ctrl+Shift+V / B   マスター音量を上げる / 下げる(V = Volume。各系統の個別音量はそのまま)
    //   Ctrl+Shift+L / K   画面の明るさを上げる / 下げる(L = Light)
    // 押しっぱなしで連続して変わる。操作すると、対応する表示が出て、しばらくして自動で閉じる。
    readonly property int volumeStep: 5
    readonly property int brightnessStep: 10

    Shortcut {
        sequence: "Ctrl+Shift+V"
        onActivated: { audioSettings.adjustMasterVolume(window.volumeStep); volumeOsd.show() }
    }
    Shortcut {
        sequence: "Ctrl+Shift+B"
        onActivated: { audioSettings.adjustMasterVolume(-window.volumeStep); volumeOsd.show() }
    }
    Shortcut {
        sequence: "Ctrl+Shift+L"
        onActivated: { brightnessController.adjustBrightness(window.brightnessStep); brightnessOsd.show() }
    }
    Shortcut {
        sequence: "Ctrl+Shift+K"
        onActivated: { brightnessController.adjustBrightness(-window.brightnessStep); brightnessOsd.show() }
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

        // Windows キー(Meta / Super)でもメニューを開閉する（フルスクリーン中のみ）
        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true
            Component.onCompleted: forceActiveFocus()
            Keys.onPressed: (event) => {
                if (!event.isAutoRepeat && window.immersive && stack.currentItem
                        && (event.key === Qt.Key_Meta || event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R)) {
                    stack.currentItem.menuOpen = !stack.currentItem.menuOpen
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

            Component.onCompleted: {
                if (startOnSettings) {
                    stack.push(settingsComponent)
                } else {
                    stack.push(homeComponent)
                }
            }
        }

        // 起動(オープニング)画面。外部機器などの待ちが終わるまで最前面に出し、終わったらフェードアウトする
        SplashScreen {
            id: splash
            anchors.fill: parent
            z: 50
            opacity: boot.done ? 0 : 1
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
        VolumeOsd {
            id: volumeOsd
            z: 1100
            anchors.centerIn: parent
        }
        BrightnessOsd {
            id: brightnessOsd
            z: 1100
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 96 * Theme.uiScale
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

    // ---- 全部の画面に表示(ミラー。設定「表示 > 画面」) ----
    // 操作する画面(このウィンドウ)以外の、つながっているすべての画面に全画面のウィンドウを作り、
    // 表示全体(rotor。回転前の向き)を一定間隔で写して映す。ミラー側は見るだけで、操作は受けない。
    readonly property var mirrorScreens: {
        if (!displaySettings.appMirrorActive || !window.screen) return []   // OS のミラーを使うときは作らない
        const list = Qt.application.screens
        const out = []
        for (let i = 0; i < list.length; ++i) {
            if (list[i].name !== window.screen.name) out.push(list[i])
        }
        return out
    }
    property var mirrorFrame: null    // 最新の写し(grabToImage の結果。url が有効な間は持っておく)
    property bool mirrorBusy: false   // 写している途中(前の写しが終わるまで次を始めない)
    Timer {
        interval: Math.round(1000 / displaySettings.mirrorFps)
        repeat: true
        running: window.mirrorScreens.length > 0 && window.visible
        onTriggered: {
            if (window.mirrorBusy || rotor.width <= 0 || rotor.height <= 0) return
            window.mirrorBusy = true
            const started = rotor.grabToImage((result) => {
                window.mirrorFrame = result
                window.mirrorBusy = false
            })
            if (!started) window.mirrorBusy = false
        }
        onRunningChanged: if (!running) window.mirrorFrame = null
    }
    Instantiator {
        model: window.mirrorScreens
        delegate: Window {
            required property var modelData
            screen: modelData
            title: "OpenCruise(ミラー)"
            color: "black"
            flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
            Component.onCompleted: {
                x = modelData.virtualX
                y = modelData.virtualY
                width = modelData.width
                height = modelData.height
                showFullScreen()
            }
            Image {
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                cache: false
                smooth: true
                source: window.mirrorFrame ? window.mirrorFrame.url : ""
            }
            MouseArea { anchors.fill: parent }   // 見るだけ(操作は操作する画面で行う)
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
