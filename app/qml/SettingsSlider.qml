// 大型の音量スライダー(0..100)。つまみをドラッグ、またはバーのどこかをタッチして値を決める。
//   SettingsSlider { value: audioSettings.mapVolume; onMoved: (v) => audioSettings.mapVolume = v }
// from(最小値。既定 0)を指定すると、バーの左端がその値になる(明るさのように 0 にできない項目用)。
// iconName / iconMinName で左のアイコンを変えられる(既定は音量。値が from のとき iconMinName を灰色で出す)。
// 押しても value は自動では変わらない。moved で受けた側が設定を書き換え、value の束縛で見た目へ反映する。
// 指を離したときに released() が出る(音量の確認音を鳴らすのに使う)。
import QtQuick

Item {
    id: root
    property int value: 0
    property int from: 0
    property string iconName: "volume_up"
    property string iconMinName: "volume_off"
    signal moved(int value)
    signal released()

    readonly property real unit: Theme.uiScale

    implicitWidth: 460 * unit
    implicitHeight: 64 * unit
    width: implicitWidth
    height: implicitHeight

    MaterialIcon {
        id: icon
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        name: root.value <= root.from ? root.iconMinName : root.iconName
        size: 40 * root.unit
        color: root.value <= root.from ? Theme.textSecondary : Theme.accent
    }

    Text {
        id: valueText
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: 92 * root.unit
        horizontalAlignment: Text.AlignRight
        font.family: Theme.fontFamily
        text: root.value + " %"
        color: Theme.textPrimary
        font.pixelSize: 26 * root.unit
        font.bold: true
    }

    Item {
        id: bar
        anchors {
            left: icon.right; leftMargin: 16 * root.unit
            right: valueText.left; rightMargin: 16 * root.unit
            verticalCenter: parent.verticalCenter
        }
        height: parent.height

        Rectangle {
            id: groove
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            height: 14 * root.unit
            radius: height / 2
            color: Theme.panelBorder

            Rectangle {
                width: handle.x + handle.width / 2
                height: parent.height
                radius: height / 2
                color: Theme.accent
            }
        }

        Rectangle {
            id: handle
            width: 48 * root.unit
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: (bar.width - width) * (root.value - root.from) / Math.max(1, 100 - root.from)
            color: Theme.panel
            border.width: mouse.pressed ? 4 : 2
            border.color: Theme.accent
            scale: mouse.pressed ? 1.08 : 1.0
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            preventStealing: true // 縦に動く設定ページのスクロールにつまみ操作を奪われないようにする

            function setFromX(x) {
                const span = bar.width - handle.width
                const v = root.from + Math.round(Math.max(0, Math.min(1, (x - handle.width / 2) / span)) * (100 - root.from))
                if (v !== root.value) {
                    root.moved(v)
                }
            }
            onPressed: (m) => setFromX(m.x)
            onPositionChanged: (m) => { if (pressed) setFromX(m.x) }
            onReleased: root.released()
        }
    }
}
