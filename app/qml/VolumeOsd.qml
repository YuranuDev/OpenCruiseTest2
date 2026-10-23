// 音量ショートカットの操作時に出す表示。マスター音量と、マップ音声・音楽音声・システムの各音量バーをまとめて出す。
// 各バーは audioSettings の現在値にバインドしているので、表示中に値が変われば追従する。
// すべてのバー(マスター・マップ音声・音楽音声・システム)は、タッチ/ドラッグで直接変更できる。
// show() を呼ぶたびに表示時間(holdMs)が延び、操作が止まってから holdMs 後に自動で閉じる。
// バーを押している間は閉じず、指を離してから holdMs 後に閉じる。パネル上のタッチは背面へ通さない。
// 位置は呼び出し側(Main.qml)で決める。
import QtQuick

Item {
    id: root
    property int holdMs: 2500
    property bool shown: false

    readonly property real unit: Theme.uiScale

    // いずれかのバーを指で押している間は閉じない
    readonly property bool touching: masterBar.pressed || mapBar.pressed || musicBar.pressed || systemBar.pressed
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

        // パネル上のタッチを受け止め、背面のウィジェットなどへ通さない
        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: column
            x: 28 * root.unit
            y: 24 * root.unit
            width: parent.width - 56 * root.unit
            spacing: 10 * root.unit

            // マスター音量(主役)
            OsdBar {
                id: masterBar
                width: parent.width
                emphasis: true
                interactive: true
                label: "マスター"
                iconName: audioSettings.masterVolume === 0 ? "volume_off" : "volume_up"
                value: audioSettings.masterVolume
                onMoved: (v) => audioSettings.masterVolume = v
                // 指を離したときに操作音を鳴らし、音量を確認できるようにする(設定画面のスライダーと同じ)
                onReleased: systemSound.play("click")
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.panelBorder
            }

            // 各系統の個別音量(マスターを掛ける前の設定値)
            OsdBar {
                id: mapBar
                width: parent.width
                interactive: true
                label: "マップ音声"
                iconName: "navigation"
                value: audioSettings.mapVolume
                fillOpacity: 0.7
                onMoved: (v) => audioSettings.mapVolume = v
            }
            OsdBar {
                id: musicBar
                width: parent.width
                interactive: true
                label: "音楽音声"
                iconName: "music_note"
                value: audioSettings.musicVolume
                fillOpacity: 0.7
                onMoved: (v) => audioSettings.musicVolume = v
            }
            OsdBar {
                id: systemBar
                width: parent.width
                interactive: true
                label: "システム"
                iconName: "settings"
                value: audioSettings.systemVolume
                fillOpacity: 0.7
                onMoved: (v) => audioSettings.systemVolume = v
                onReleased: systemSound.play("click")
            }
        }
    }
}
