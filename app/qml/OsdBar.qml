// OSD 用の横バー 1 本分(アイコン・ラベル・バー・数値)。VolumeOsd / BrightnessOsd が使う。
//   OsdBar { width: parent.width; label: "マスター"; iconName: "volume_up"; value: audioSettings.masterVolume; emphasis: true }
// 既定は表示専用。interactive を true にすると、つまみが出て、バーのどこかをタッチ/ドラッグして値を決められる
// (押しても value は自動では変わらない。moved で受けた側が設定を書き換え、value の束縛で見た目へ反映する)。
// 指を離したときに released() が出る。押している間は pressed が true。
// バーは 0..100 % をそのまま表す。emphasis を true にすると大きく表示する(主役のバー用)。
// fillOpacity を下げると、従属する(主役ではない)バーとして控えめに見せられる。
// compact を true にすると、行の高さ・文字・つまみを小さくする(画面の下に出す小さめの表示用)。
import QtQuick

Item {
    id: root
    property string label: ""
    property string iconName: "volume_up"
    property int value: 0
    property bool emphasis: false
    property real fillOpacity: 1.0
    property bool interactive: false
    property bool compact: false
    signal moved(int value)
    signal released()
    readonly property bool pressed: interactive && touch.pressed

    readonly property real unit: Theme.uiScale
    readonly property real fraction: Math.max(0, Math.min(1, root.value / 100))
    readonly property color barColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, root.fillOpacity)
    /// 大きさ: 通常の値 n / 小さめの値 c(どちらも 1280x720 基準)
    function sz(n, c) { return (root.compact ? c : n) * root.unit }

    // タッチ操作できるときは、指で押しやすいよう行を高くする
    height: interactive ? (emphasis ? sz(72, 50) : sz(60, 40)) : (emphasis ? sz(60, 44) : sz(42, 32))

    MaterialIcon {
        id: icon
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        name: root.iconName
        size: root.emphasis ? root.sz(44, 30) : root.sz(30, 22)
        color: root.value === 0 ? Theme.textSecondary : root.barColor
    }

    Text {
        id: labelText
        anchors { left: icon.right; leftMargin: root.sz(14, 10); verticalCenter: parent.verticalCenter }
        width: root.label === "" ? 0 : (root.emphasis ? root.sz(130, 84) : root.sz(150, 84))
        visible: root.label !== ""
        font.family: Theme.fontFamily
        text: root.label
        color: root.emphasis ? Theme.textPrimary : Theme.textSecondary
        font.pixelSize: root.emphasis ? root.sz(26, 18) : root.sz(20, 15)
        font.bold: root.emphasis
        elide: Text.ElideRight
    }

    Text {
        id: valueText
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: root.emphasis ? root.sz(100, 64) : root.sz(76, 52)
        horizontalAlignment: Text.AlignRight
        font.family: Theme.fontFamily
        text: root.value + " %"
        color: Theme.textPrimary
        font.pixelSize: root.emphasis ? root.sz(30, 20) : root.sz(22, 15)
        font.bold: true
    }

    Rectangle {
        id: track
        anchors {
            left: labelText.right; leftMargin: root.sz(14, 10)
            right: valueText.left; rightMargin: root.sz(14, 10)
            verticalCenter: parent.verticalCenter
        }
        height: root.interactive ? (root.emphasis ? root.sz(18, 12) : root.sz(14, 9)) : (root.emphasis ? root.sz(16, 10) : root.sz(10, 7))
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
            width: root.emphasis ? root.sz(44, 30) : root.sz(38, 24)
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
