// アプリのルート。メイン画面と設定画面を StackView で切り替える。
import QtQuick
import QtQuick.Controls

ApplicationWindow {
    id: window
    width: 1280
    height: 720
    visible: true
    // アプリのテーマ(昼夜・アクセント色)を Theme へ反映する。Theme 側で補間アニメーションされる
    Binding { target: Theme; property: "night"; value: androidAuto.nightActive }
    Binding { target: Theme; property: "accentIndex"; value: androidAuto.accentIndex }
    // 画面サイズに応じた拡大率(1280x720 基準)。設定画面など、寸法を拡大率で決める部品が Theme.uiScale を参照する
    Binding { target: Theme; property: "uiScale"; value: Math.max(0.6, Math.min(window.width / 1280, window.height / 720)) }
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

    Dialog {
        id: exitConfirmation
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose
        title: "終了確認"
        width: Math.min(480, window.width - Theme.margin * 2)
        x: Math.round((window.width - width) / 2)
        y: Math.round((window.height - height) / 2)

        contentItem: Column {
            spacing: Theme.margin
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
