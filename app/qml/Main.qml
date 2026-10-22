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

    // 起動画面中の Esc はスキップ。フルスクリーン中は Esc / F10 / Menu キーで下メニューを開閉する（Esc で即終了しない）
    Shortcut {
        sequence: "Esc"
        onActivated: {
            if (boot.active) {
                boot.skip()
            } else if (window.immersive && stack.currentItem) {
                stack.currentItem.menuOpen = !stack.currentItem.menuOpen
            } else {
                Qt.quit()
            }
        }
    }
    Shortcut {
        sequences: ["F10", "Menu"]
        enabled: window.immersive
        onActivated: if (stack.currentItem) stack.currentItem.menuOpen = !stack.currentItem.menuOpen
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
