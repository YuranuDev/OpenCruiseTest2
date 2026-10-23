// 明るさのショートカットの操作時に出す表示(アイコン・バー・数値)。brightnessController の現在値にバインドしている。
// show() を呼ぶたびに表示時間(holdMs)が延び、操作が止まってから holdMs 後に自動で閉じる。タップでも閉じる。
// 位置は呼び出し側(Main.qml)で決める。表示専用。
import QtQuick

Item {
    id: root
    property int holdMs: 2000
    property bool shown: false

    readonly property real unit: Theme.uiScale

    function show() {
        shown = true
        hideTimer.restart()
    }
    function hide() {
        shown = false
        hideTimer.stop()
    }

    width: 520 * unit
    height: panel.height
    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: root.shown ? 120 : 300; easing.type: Easing.OutCubic } }

    Timer {
        id: hideTimer
        interval: root.holdMs
        onTriggered: root.hide()
    }

    Rectangle {
        id: panel
        width: parent.width
        height: bar.height + 40 * root.unit
        radius: Theme.radius * root.unit
        color: Theme.panel
        border.width: 2
        border.color: Theme.panelBorder

        OsdBar {
            id: bar
            x: 28 * root.unit
            y: 20 * root.unit
            width: parent.width - 56 * root.unit
            emphasis: true
            label: "明るさ"
            iconName: brightnessController.brightness >= 70 ? "brightness_high"
                      : brightnessController.brightness >= 35 ? "brightness_medium" : "brightness_low"
            value: brightnessController.brightness
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.hide()
        }
    }
}
