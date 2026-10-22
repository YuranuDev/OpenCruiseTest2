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

    // 映像表示中かつ「接続後フルスクリーン」設定が有効で、メイン画面を見ているとき
    readonly property bool immersive: androidAuto.fullscreenOnStream && androidAuto.stateKey === "streaming"
                                      && stack.depth === 1
    visibility: (startFullscreen || immersive) ? Window.FullScreen : Window.Windowed
    title: "OpenCruise"
    color: Theme.background

    // フルスクリーン中は Esc / F10 / Menu キーでスライドメニューを開閉する（Esc で即終了しない）
    Shortcut {
        sequence: "Esc"
        onActivated: {
            if (window.immersive && stack.currentItem) {
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

    StackView {
        id: stack
        anchors.fill: parent
        Component.onCompleted: {
            if (startOnSettings) {
                stack.push(settingsComponent)
            } else {
                stack.push(homeComponent)
            }
        }
    }

    Component {
        id: homeComponent
        HomeScreen {
            immersive: window.immersive
            onOpenSettings: stack.push(settingsComponent)
        }
    }

    Component {
        id: settingsComponent
        SettingsScreen {
            onBack: stack.pop()
        }
    }
}
