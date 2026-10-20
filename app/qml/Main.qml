// アプリのルート。メイン画面と設定画面を StackView で切り替える。
import QtQuick
import QtQuick.Controls

ApplicationWindow {
    id: window
    width: 1280
    height: 720
    visible: true
    visibility: startFullscreen ? Window.FullScreen : Window.Windowed
    title: "OpenCruise"
    color: Theme.background

    Shortcut {
        sequence: "Esc"
        onActivated: Qt.quit()
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
