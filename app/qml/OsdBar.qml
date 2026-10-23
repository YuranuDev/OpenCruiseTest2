// OSD 用の横バー 1 本分(アイコン・ラベル・バー・数値)。VolumeOsd / BrightnessOsd が使う。
//   OsdBar { width: parent.width; label: "マスター"; iconName: "volume_up"; value: audioSettings.masterVolume; emphasis: true }
// 既定は表示専用。interactive を true にすると、つまみが出て、バーのどこかをタッチ/ドラッグして値を決められる
// (押しても value は自動では変わらない。moved で受けた側が設定を書き換え、value の束縛で見た目へ反映する)。
// 指を離したときに released() が出る。押している間は pressed が true。
// バーは 0..100 % をそのまま表す。emphasis を true にすると大きく表示する(主役のバー用)。
// fillOpacity を下げると、従属する(主役ではない)バーとして控えめに見せられる。
import QtQuick

Item {
    id: root
    property string label: ""
    property string iconName: "volume_up"
    property int value: 0
    property bool emphasis: false
    property real fillOpacity: 1.0
    property bool interactive: false
    signal moved(int value)
    signal released()
    readonly property bool pressed: interactive && touch.pressed

    readonly property real unit: Theme.uiScale
    readonly property real fraction: Math.max(0, Math.min(1, root.value / 100))
    readonly property color barColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, root.fillOpacity)

    // タッチ操作できるときは、指で押しやすいよう行を高くする
    height: (interactive ? (emphasis ? 72 : 60) : (emphasis ? 60 : 42)) * unit

    MaterialIcon {
        id: icon
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        name: root.iconName
        size: (root.emphasis ? 44 : 30) * root.unit
        color: root.value === 0 ? Theme.textSecondary : root.barColor
    }

    Text {
        id: labelText
        anchors { left: icon.right; leftMargin: 14 * root.unit; verticalCenter: parent.verticalCenter }
        width: root.label === "" ? 0 : (root.emphasis ? 130 : 150) * root.unit
        visible: root.label !== ""
        font.family: Theme.fontFamily
        text: root.label
        color: root.emphasis ? Theme.textPrimary : Theme.textSecondary
        font.pixelSize: (root.emphasis ? 26 : 20) * root.unit
        font.bold: root.emphasis
        elide: Text.ElideRight
    }

    Text {
        id: valueText
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: (root.emphasis ? 100 : 76) * root.unit
        horizontalAlignment: Text.AlignRight
        font.family: Theme.fontFamily
        text: root.value + " %"
        color: Theme.textPrimary
        font.pixelSize: (root.emphasis ? 30 : 22) * root.unit
        font.bold: true
    }

    Rectangle {
        id: track
        anchors {
            left: labelText.right; leftMargin: 14 * root.unit
            right: valueText.left; rightMargin: 14 * root.unit
            verticalCenter: parent.verticalCenter
        }
        height: (root.interactive ? (root.emphasis ? 18 : 14) : (root.emphasis ? 16 : 10)) * root.unit
        radius: height / 2
        color: Theme.panelBorder

        Rectangle {
            width: root.interactive ? knob.x + knob.width / 2 : parent.width * root.fraction
            height: parent.height
            radius: height / 2
            color: root.barColor
            Behavior on width { enabled: !root.interactive; NumberAnimation { duration: 80; easing.type: Easing.OutCubic } }
        }

        // つまみ(タッチ操作できるときだけ)
        Rectangle {
            id: knob
            visible: root.interactive
            width: (root.emphasis ? 44 : 38) * root.unit
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: (track.width - width) * root.fraction
            color: Theme.panel
            border.width: touch.pressed ? 4 : 2
            border.color: root.barColor
            scale: touch.pressed ? 1.08 : 1.0
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
        }
    }

    // タッチ操作の受け口。バーの左右へつまみの半径ぶん広げ、端でも押しやすくする。縦は行全体
    MouseArea {
        id: touch
        enabled: root.interactive
        readonly property real pad: knob.width / 2
        anchors {
            left: track.left; leftMargin: -pad
            right: track.right; rightMargin: -pad
            top: parent.top
            bottom: parent.bottom
        }
        preventStealing: true

        function setFromX(x) {
            const span = track.width - knob.width
            const ratio = span > 0 ? (x - pad - knob.width / 2) / span : 0
            const v = Math.round(Math.max(0, Math.min(1, ratio)) * 100)
            if (v !== root.value) {
                root.moved(v)
            }
        }
        onPressed: (m) => setFromX(m.x)
        onPositionChanged: (m) => { if (pressed) setFromX(m.x) }
        onReleased: root.released()
        onCanceled: root.released()
    }
}
