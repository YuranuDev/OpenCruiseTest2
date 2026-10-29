// 色を決めるためのグラデーション付きスライダー(色相・鮮やかさ・明るさ用)。
//   SettingsColorBar { label: "色相"; stops: [...色の文字列...]; value: h; onMoved: (v) => h = v }
// value は from..to の実数(既定 0..1)。バーの色(stops)は左端から右端への色の並び。
// SettingsSlider と同じく、押しても value は自動では変わらない(moved を受けた側が書き換える)。
import QtQuick
import OpenCruise

Item {
    id: root
    property string label: ""
    property real value: 0
    property real from: 0
    property real to: 1
    property var stops: []              // バーの色(左 → 右)
    property color handleColor: Theme.accent   // つまみの中の色(今の色)
    signal moved(real value)
    signal released()

    readonly property real unit: Theme.uiScale
    implicitWidth: 460 * unit
    implicitHeight: 64 * unit
    width: implicitWidth
    height: implicitHeight

    Text {
        id: labelText
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: 120 * root.unit
        font.family: Theme.fontFamily
        font.pixelSize: 22 * root.unit
        color: Theme.textSecondary
        text: root.label
        elide: Text.ElideRight
    }

    Item {
        id: bar
        anchors { left: labelText.right; right: parent.right; verticalCenter: parent.verticalCenter }
        height: parent.height

        // グラデーションの溝
        Canvas {
            id: groove
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            height: 24 * root.unit
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Connections { target: root; function onStopsChanged() { groove.requestPaint() } }
            onPaint: {
                const c = getContext("2d")
                c.clearRect(0, 0, width, height)
                const n = root.stops.length
                if (n === 0 || width <= 0) return
                const g = c.createLinearGradient(0, 0, width, 0)
                for (let i = 0; i < n; ++i) g.addColorStop(n === 1 ? 0 : i / (n - 1), String(root.stops[i]))
                const r = height / 2
                c.beginPath()
                c.moveTo(r, 0)
                c.arcTo(width, 0, width, height, r)
                c.arcTo(width, height, 0, height, r)
                c.arcTo(0, height, 0, 0, r)
                c.arcTo(0, 0, width, 0, r)
                c.closePath()
                c.fillStyle = g
                c.fill()
            }
            // 縁(明るい色・暗い色の端が背景に溶けないように)
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: Theme.panelBorder
            }
        }

        Rectangle {
            id: handle
            width: 48 * root.unit
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: (bar.width - width) * (root.value - root.from) / Math.max(0.0001, root.to - root.from)
            color: root.handleColor
            border.width: mouse.pressed ? 5 : 4
            border.color: Theme.textPrimary
            scale: mouse.pressed ? 1.08 : 1.0
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            preventStealing: true   // 縦に動く設定ページのスクロールにつまみ操作を奪われないようにする

            function setFromX(x) {
                const span = Math.max(1, bar.width - handle.width)
                const t = Math.max(0, Math.min(1, (x - handle.width / 2) / span))
                root.moved(root.from + t * (root.to - root.from))
            }
            onPressed: (m) => setFromX(m.x)
            onPositionChanged: (m) => { if (pressed) setFromX(m.x) }
            onReleased: root.released()
        }
    }
}
