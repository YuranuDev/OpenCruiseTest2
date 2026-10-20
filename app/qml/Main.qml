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

    StackView {
        id: stack
        anchors.fill: parent
        initialItem: homeComponent
        Component.onCompleted: if (startOnSettings) push(settingsComponent)
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
