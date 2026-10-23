// 音量ショートカットの操作時に出す表示。マスター音量と、マップ音声・音楽音声・システムの各音量バーをまとめて出す。
// 各バーは audioSettings の現在値にバインドしているので、表示中に値が変われば追従する。
// show() を呼ぶたびに表示時間(holdMs)が延び、操作が止まってから holdMs 後に自動で閉じる。タップでも閉じる。
// 位置は呼び出し側(Main.qml)で決める。表示専用で、バーを直接操作することはできない。
import QtQuick

Item {
    id: root
    property int holdMs: 2500
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

    width: 640 * unit
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
        height: column.implicitHeight + 48 * root.unit
        radius: Theme.radius * root.unit
        color: Theme.panel
        border.width: 2
        border.color: Theme.panelBorder

        Column {
            id: column
            x: 28 * root.unit
            y: 24 * root.unit
            width: parent.width - 56 * root.unit
            spacing: 10 * root.unit

            // マスター音量(主役)
            OsdBar {
                width: parent.width
                emphasis: true
                label: "マスター"
                iconName: audioSettings.masterVolume === 0 ? "volume_off" : "volume_up"
                value: audioSettings.masterVolume
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.panelBorder
            }

            // 各系統の個別音量(マスターを掛ける前の設定値)
            OsdBar {
                width: parent.width
                label: "マップ音声"
                iconName: "navigation"
                value: audioSettings.mapVolume
                fillOpacity: 0.7
            }
            OsdBar {
                width: parent.width
                label: "音楽音声"
                iconName: "music_note"
                value: audioSettings.musicVolume
                fillOpacity: 0.7
            }
            OsdBar {
                width: parent.width
                label: "システム"
                iconName: "settings"
                value: audioSettings.systemVolume
                fillOpacity: 0.7
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.hide()
        }
    }
}
