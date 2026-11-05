// 自由に色を決める部品: 今の色の見本と 16 進入力、色相・鮮やかさ・明るさのスライダー。
//   SettingsColorPicker { color: androidAuto.accentCustom; onPicked: (c) => androidAuto.accentCustom = c }
// color は "#rrggbb"。操作のたびに picked(color) を出す(色をなぞっている間も続けて出る)。
// 暗すぎる色は文字・アイコンが読めなくなるので、明るさは minValue 以上にする。
import QtQuick
import OpenCruise

Item {
    id: root
    property string color: "#4da3ff"
    property real minValue: 0.55        // 明るさ(HSV の V)の下限
    signal picked(string color)

    readonly property real unit: Theme.uiScale
    implicitWidth: 560 * unit
    implicitHeight: col.implicitHeight
    width: implicitWidth
    height: implicitHeight

    // 操作中の値(0..1)。16 進に丸めると誤差が出るので、スライダーはこちらを元にする
    property real h: 0
    property real s: 0
    property real v: 1
    readonly property color current: Qt.hsva(h, s, v, 1)

    function hex(c) { return String(c).toLowerCase() }
    function syncFrom(text) {
        const c = Qt.color(text)
        if (hex(Qt.hsva(h, s, v, 1)) === hex(c)) return   // 自分が出した色の戻り(丸めの誤差で動かさない)
        if (c.hsvHue >= 0) h = c.hsvHue                   // 無彩色の色相は -1(今の色相を保つ)
        s = c.hsvSaturation
        v = Math.max(minValue, c.hsvValue)
    }
    onColorChanged: syncFrom(color)
    Component.onCompleted: syncFrom(color)
    function commit() { root.picked(hex(Qt.hsva(h, s, v, 1))) }

    Column {
        id: col
        width: parent.width
        spacing: 8 * root.unit

        // 今の色の見本と 16 進入力
        Row {
            spacing: 16 * root.unit
            Rectangle {
                width: 96 * root.unit
                height: 64 * root.unit
                radius: Theme.radius
                color: root.current
                border.width: 1
                border.color: Theme.panelBorder
            }
            WSTextField {
                id: hexField
                anchors.verticalCenter: parent.verticalCenter
                width: 200 * root.unit
                maxLength: 7
                placeholder: "#rrggbb"
                text: root.hex(root.current)
                onEdited: (t) => {
                    const m = /^#?([0-9a-fA-F]{6})$/.exec(t.trim())
                    if (m) {
                        root.syncFrom("#" + m[1])
                        root.commit()
                    }
                    // 6 桁そろった(確定した)ときと、入力を終えて不正だったときだけ、今の色の表記に戻す
                    // (入力の途中で少し止まっただけでは、打っている文字を消さない)
                    if (m || !hexField.activeFocus) text = Qt.binding(() => root.hex(root.current))
                }
            }
        }

        SettingsColorBar {
            width: parent.width
            label: "色相"
            value: root.h
            handleColor: root.current
            stops: [Qt.hsva(0, root.s, root.v, 1), Qt.hsva(1 / 6, root.s, root.v, 1), Qt.hsva(2 / 6, root.s, root.v, 1),
                    Qt.hsva(3 / 6, root.s, root.v, 1), Qt.hsva(4 / 6, root.s, root.v, 1), Qt.hsva(5 / 6, root.s, root.v, 1),
                    Qt.hsva(1, root.s, root.v, 1)]
            onMoved: (x) => { root.h = Math.min(0.9999, x); root.commit() }
        }
        SettingsColorBar {
            width: parent.width
            label: "鮮やかさ"
            value: root.s
            handleColor: root.current
            stops: [Qt.hsva(root.h, 0, root.v, 1), Qt.hsva(root.h, 1, root.v, 1)]
            onMoved: (x) => { root.s = x; root.commit() }
        }
        SettingsColorBar {
            width: parent.width
            label: "明るさ"
            from: root.minValue
            value: root.v
            handleColor: root.current
            stops: [Qt.hsva(root.h, root.s, root.minValue, 1), Qt.hsva(root.h, root.s, 1, 1)]
            onMoved: (x) => { root.v = x; root.commit() }
        }
    }
}
