// ウィジェットのページのタブ(初期画面の上部、接続状態と通知ボタンの間に置く)。
//  - タップでそのページへ。今のページをもう一度タップ(または長押し)すると、ページの設定(menuRequested)
//  - 警告音を鳴らしている(消音中も含む)ウィジェットがあるページのタブは、赤く点滅する
//  - 右端の「+」でページを足す(上限まで)
import QtQuick
import OpenCruise

Item {
    id: root
    property Item pages: null
    signal menuRequested(int index)

    readonly property real unit: Theme.uiScale
    readonly property real pillH: height

    // 警告中のタブの点滅
    property real blink: 1
    SequentialAnimation on blink {
        running: root.anyAlarm
        loops: Animation.Infinite
        NumberAnimation { to: 0.45; duration: 380; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 380; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.blink = 1
    }
    readonly property bool anyAlarm: {
        WarningAlarm.revision
        if (!pages) return false
        for (let i = 0; i < pages.count; ++i) {
            if (pages.pageAlarm(i)) return true
        }
        return false
    }

    ListView {
        id: tabs
        anchors.centerIn: parent
        height: parent.height
        width: Math.min(parent.width, contentWidth)
        orientation: ListView.Horizontal
        spacing: 8 * root.unit
        clip: true
        interactive: contentWidth > parent.width
        boundsBehavior: Flickable.StopAtBounds
        model: root.pages ? root.pages.names : []
        currentIndex: root.pages ? root.pages.current : 0
        highlightFollowsCurrentItem: false
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: Rectangle {
            id: pill
            required property var modelData
            required property int index
            readonly property bool selected: root.pages && root.pages.current === index
            readonly property bool alarm: { WarningAlarm.revision; return root.pages ? root.pages.pageAlarm(index) : false }
            height: root.pillH
            width: Math.max(96 * root.unit, pillRow.implicitWidth + 32 * root.unit)
            radius: height / 2
            color: alarm ? Theme.mix(Theme.panel, Theme.error, 0.35 + 0.4 * (1 - root.blink))
                         : (selected ? Theme.mix(Theme.panel, Theme.accent, pillMouse.pressed ? 0.45 : 0.22)
                                     : Theme.mix(Theme.panel, Theme.accent, pillMouse.pressed ? 0.25 : 0))
            border.width: selected || alarm ? 2 : 1
            border.color: alarm ? Theme.error : (selected ? Theme.accent : Theme.panelBorder)
            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: 6 * root.unit
                MaterialIcon {
                    visible: pill.alarm
                    anchors.verticalCenter: parent.verticalCenter
                    name: "warning"
                    size: Math.round(pill.height * 0.5)
                    color: Theme.error
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.bold: pill.selected
                    font.pixelSize: Math.round(pill.height * 0.4)
                    color: pill.selected || pill.alarm ? Theme.textPrimary : Theme.textSecondary
                    text: pill.modelData
                }
                MaterialIcon {   // 今のページは、もう一度タップで設定を開けることを示す
                    visible: pill.selected
                    anchors.verticalCenter: parent.verticalCenter
                    name: "more_horiz"
                    size: Math.round(pill.height * 0.45)
                    color: Theme.textSecondary
                }
            }
            MouseArea {
                id: pillMouse
                anchors.fill: parent
                pressAndHoldInterval: 450
                onClicked: {
                    if (pill.selected) root.menuRequested(pill.index)
                    else root.pages.setCurrent(pill.index)
                }
                onPressAndHold: root.menuRequested(pill.index)
            }
        }

        footer: Item {
            visible: root.pages && root.pages.count < root.pages.maxPages
            width: visible ? addPill.width + tabs.spacing : 0
            height: root.pillH
            Rectangle {
                id: addPill
                anchors.right: parent.right
                height: root.pillH
                width: height
                radius: height / 2
                color: Theme.mix(Theme.panel, Theme.accent, addMouse.pressed ? 0.3 : 0)
                border.color: Theme.panelBorder
                MaterialIcon {
                    anchors.centerIn: parent
                    name: "add"
                    size: Math.round(parent.height * 0.55)
                    color: Theme.accent
                }
                MouseArea { id: addMouse; anchors.fill: parent; onClicked: root.pages.addPage() }
            }
        }
    }
}
