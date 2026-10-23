// OSD 用の横バー 1 本分(アイコン・ラベル・バー・数値)。VolumeOsd / BrightnessOsd が使う。表示専用で、操作は受けない。
//   OsdBar { width: parent.width; label: "マスター"; iconName: "volume_up"; value: audioSettings.masterVolume; emphasis: true }
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

    readonly property real unit: Theme.uiScale
    readonly property real fraction: Math.max(0, Math.min(1, root.value / 100))
    readonly property color barColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, root.fillOpacity)

    height: (emphasis ? 60 : 42) * unit

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
        height: (root.emphasis ? 16 : 10) * root.unit
        radius: height / 2
        color: Theme.panelBorder

        Rectangle {
            width: parent.width * root.fraction
            height: parent.height
            radius: height / 2
            color: root.barColor
            Behavior on width { NumberAnimation { duration: 80; easing.type: Easing.OutCubic } }
        }
    }
}
