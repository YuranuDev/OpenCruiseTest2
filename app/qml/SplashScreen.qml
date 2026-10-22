// 起動(オープニング)画面。BootManager(context property `boot`)の各ステップの状態を一覧し、
// ESP32 などの応答待ちが終わるまで表示を保つ。待ちの制御はすべて C++ 側(BootManager)にあり、ここは表示だけ。
import QtQuick

Rectangle {
    id: root
    color: Theme.background

    readonly property real unit: Math.max(0.6, Math.min(width / 1280, height / 720))
    // 進行バーはなめらかに追従させる
    property real shownProgress: boot.progress
    Behavior on shownProgress { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    function iconFor(key) {
        switch (key) {
        case "ready": return "check_circle"
        case "warning": return "warning"
        case "failed": return "error"
        case "skipped": return "remove_circle_outline"
        default: return "radio_button_unchecked"
        }
    }
    function colorFor(key) {
        switch (key) {
        case "ready": return Theme.ok
        case "warning": return Theme.warn
        case "failed": return Theme.error
        case "running": return Theme.accent
        default: return Theme.textSecondary
        }
    }

    // 下の画面へタッチを通さない
    MouseArea { anchors.fill: parent; enabled: root.visible }

    Column {
        id: content
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.margin * 4, 620 * root.unit)
        spacing: 20 * root.unit
        NumberAnimation on opacity { from: 0; to: 1; duration: 500; easing.type: Easing.OutCubic }

        // ロゴ(ゆっくり脈打つ輪)
        Item {
            width: parent.width
            height: 132 * root.unit
            Rectangle {
                anchors.centerIn: parent
                width: 112 * root.unit; height: width; radius: width / 2
                color: "transparent"
                border.width: 3
                border.color: Theme.accent
                SequentialAnimation on scale {
                    loops: Animation.Infinite
                    running: boot.active
                    NumberAnimation { to: 1.08; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: "directions_car"
                    size: 60 * root.unit
                    color: Theme.accent
                }
            }
        }

        Text {
            font.family: Theme.fontFamily
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "OpenCruise"
            color: Theme.textPrimary
            font.pixelSize: 48 * root.unit
            font.bold: true
        }

        Text {
            font.family: Theme.fontFamily
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: boot.summaryText
            color: boot.hasProblem && boot.done ? Theme.warn : Theme.textSecondary
            font.pixelSize: 22 * root.unit
            elide: Text.ElideRight
        }

        // 進行バー
        Rectangle {
            width: parent.width
            height: 6 * root.unit
            radius: height / 2
            color: Theme.panelBorder
            Rectangle {
                width: parent.width * root.shownProgress
                height: parent.height
                radius: height / 2
                color: Theme.accent
            }
        }

        // ステップ一覧
        Rectangle {
            width: parent.width
            height: stepsColumn.height + 2 * Theme.margin
            radius: Theme.radius + 6
            color: Theme.panel
            border.color: Theme.panelBorder
            visible: stepRepeater.count > 0

            Column {
                id: stepsColumn
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                          leftMargin: Theme.margin * 1.25; rightMargin: Theme.margin * 1.25 }

                Repeater {
                    id: stepRepeater
                    model: boot
                    delegate: Item {
                        id: row
                        required property string title
                        required property string detail
                        required property string stateKey
                        width: stepsColumn.width
                        height: 46 * root.unit

                        Item {
                            id: iconBox
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: 30 * root.unit; height: width
                            // 応答待ちは回る「sync」、確定後は状態のアイコン
                            MaterialIcon {
                                anchors.centerIn: parent
                                visible: row.stateKey === "running"
                                name: "sync"
                                size: 30 * root.unit
                                color: Theme.accent
                                RotationAnimator on rotation { from: 0; to: 360; duration: 1100; loops: Animation.Infinite; running: parent.visible }
                            }
                            MaterialIcon {
                                anchors.centerIn: parent
                                visible: row.stateKey !== "running"
                                name: root.iconFor(row.stateKey)
                                size: 30 * root.unit
                                color: root.colorFor(row.stateKey)
                            }
                        }
                        Text {
                            font.family: Theme.fontFamily
                            anchors { left: iconBox.right; leftMargin: 14 * root.unit; verticalCenter: parent.verticalCenter }
                            text: row.title
                            color: Theme.textPrimary
                            font.pixelSize: 22 * root.unit
                        }
                        Text {
                            font.family: Theme.fontFamily
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: parent.width * 0.45
                            horizontalAlignment: Text.AlignRight
                            text: row.detail
                            color: (row.stateKey === "warning" || row.stateKey === "failed") ? root.colorFor(row.stateKey) : Theme.textSecondary
                            font.pixelSize: 18 * root.unit
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    ActionButton {
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: Theme.margin * 1.5; bottomMargin: Theme.margin * 1.5 }
        visible: boot.active
        text: "スキップ"
        onClicked: boot.skip()
    }
}
