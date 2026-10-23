// 明るさのショートカットの操作時に出す表示(アイコン・バー・つまみ・数値)。brightnessController の現在値にバインドしている。
// 音量バー(VolumeOsd)と同じく、バーはタッチ/ドラッグで直接変更できる(つまみ付き)。
// show() を呼ぶたびに表示時間(holdMs)が延び、操作が止まってから holdMs 後に自動で閉じる。
// バーを押している間は閉じず、指を離してから holdMs 後に閉じる。パネル上のタッチは背面へ通さない。
// 位置は呼び出し側(Main.qml)で決める。
import QtQuick

Item {
    id: root
    property int holdMs: 2000
    property bool shown: false

    readonly property real unit: Theme.uiScale

    // バーを指で押している間は閉じない
    readonly property bool touching: bar.pressed
    onTouchingChanged: {
        if (touching) {
            hideTimer.stop()
        } else if (shown) {
            hideTimer.restart()
        }
    }

    function show() {
        shown = true
        if (!touching) {
            hideTimer.restart()
        }
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

        // パネル上のタッチを受け止め、背面のウィジェットなどへ通さない
        MouseArea {
            anchors.fill: parent
        }

        OsdBar {
            id: bar
            x: 28 * root.unit
            y: 20 * root.unit
            width: parent.width - 56 * root.unit
            emphasis: true
            interactive: true
            label: "明るさ"
            iconName: brightnessController.brightness >= 70 ? "brightness_high"
                      : brightnessController.brightness >= 35 ? "brightness_medium" : "brightness_low"
            value: brightnessController.brightness
            // setBrightness が最小値(10 %)未満を丸めるので、バーを左端へ動かしても真っ暗にはならない
            onMoved: (v) => brightnessController.brightness = v
            // 指を離したときに操作音を鳴らす(音量バーと同じ)
            onReleased: systemSound.play("click")
        }
    }
}
