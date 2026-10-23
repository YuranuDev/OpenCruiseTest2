// 数値の増減ボタン(−  値  ＋)。車載向けに大きなタッチ領域。
//   WSStepper { value: 1.5; from: 0; to: 3; step: 0.1; decimals: 1; suffix: " bar"; onMoved: (v) => ... }
// 押しても value は自動では変わらない。moved で受けた側が設定を書き換える(他の設定部品と同じ)。長押しで連続変化。
import QtQuick
import OpenCruise

Row {
    id: root
    property real value: 0
    property real from: 0
    property real to: 100
    property real step: 1
    property int decimals: 0
    property string suffix: ""
    signal moved(real value)

    readonly property real unit: Theme.uiScale
    spacing: 10 * unit

    function press(dir) { nudge(dir); repeat.dir = dir; hold.restart() }
    function release() { hold.stop(); repeat.stop() }

    function nudge(dir) {
        const next = Number((root.value + dir * root.step).toFixed(root.decimals + 1))
        const clamped = Math.max(root.from, Math.min(root.to, next))
        if (clamped !== root.value) root.moved(clamped)
    }

    // 押す/離すだけを通知する小さなボタン(インラインコンポーネントは外側の id を参照できないので、シグナルで知らせる)
    component Btn: Rectangle {
        id: btn
        property string glyph: ""
        property int dir: 1
        readonly property real unit: Theme.uiScale
        signal down(int dir)
        signal up()
        width: 64 * unit
        height: 64 * unit
        radius: Theme.radius
        color: Theme.mix(Theme.panel, Theme.accent, area.pressed ? 0.35 : 0)
        border.width: area.pressed ? 2 : 1
        border.color: area.pressed ? Theme.accent : Theme.panelBorder
        Text {
            anchors.centerIn: parent
            font.family: Theme.fontFamily
            text: btn.glyph
            color: Theme.textPrimary
            font.pixelSize: 34 * btn.unit
        }
        MouseArea {
            id: area
            anchors.fill: parent
            onPressed: btn.down(btn.dir)
            onReleased: btn.up()
            onCanceled: btn.up()
        }
    }

    Btn { glyph: "−"; dir: -1; onDown: (d) => root.press(d); onUp: root.release() }
    Text {
        width: 150 * root.unit
        height: 64 * root.unit
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.family: Theme.fontFamily
        text: root.value.toFixed(root.decimals) + root.suffix
        color: Theme.textPrimary
        font.pixelSize: 28 * root.unit
        font.bold: true
    }
    Btn { glyph: "＋"; dir: 1; onDown: (d) => root.press(d); onUp: root.release() }

    // 長押しで連続変化
    Timer { id: hold; interval: 400; onTriggered: repeat.start() }
    Timer {
        id: repeat
        property int dir: 1
        interval: 90
        repeat: true
        onTriggered: root.nudge(dir)
    }
}
