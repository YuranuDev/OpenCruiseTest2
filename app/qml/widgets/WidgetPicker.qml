// ウィジェットの追加パネル。ジャンルごとのタブに、追加できるウィジェットを並べる(WidgetRegistry の定義から自動生成)。
// 追加するとエリアの空いている最初の場所に置かれ、パネルが閉じる。「初期配置に戻す」は 2 回押しで実行する。
import QtQuick
import OpenCruise

Item {
    id: root

    property var area: null          // WidgetArea
    property bool open: false
    property string genre: WidgetRegistry.genres[0].id
    property bool confirmReset: false

    readonly property real unit: Theme.uiScale

    function show() { confirmReset = false; open = true }
    function close() { open = false }

    visible: scrim.opacity > 0

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "black"
        opacity: root.open ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; enabled: root.open; onClicked: root.close() }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Theme.margin, 980 * root.unit)
        height: Math.min(parent.height - 2 * Theme.margin, 700 * root.unit)
        radius: Theme.radius + 8
        color: Theme.panel
        border.color: Theme.panelBorder
        scale: root.open ? 1 : 0.92
        opacity: root.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea { anchors.fill: parent }

        // ---- 上段: タイトルとジャンルのタブ ----
        Item {
            id: head
            anchors { top: parent.top; left: parent.left; right: parent.right
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5 }
            height: 168 * root.unit

            Text {
                anchors { top: parent.top; topMargin: 18 * root.unit; left: parent.left }
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: 30 * root.unit
                color: Theme.textPrimary
                text: "ウィジェットを追加"
            }
            Row {
                id: tabs
                anchors { bottom: parent.bottom; bottomMargin: 14 * root.unit; left: parent.left; right: parent.right }
                spacing: Theme.margin * 0.6
                readonly property real cellW: (width - spacing * (WidgetRegistry.genres.length - 1)) / WidgetRegistry.genres.length

                Repeater {
                    model: WidgetRegistry.genres
                    Rectangle {
                        required property var modelData
                        readonly property bool on: root.genre === modelData.id
                        width: tabs.cellW
                        height: 76 * root.unit
                        radius: Theme.radius
                        color: Theme.mix(Theme.panel, Theme.accent, tabMouse.pressed ? 0.35 : (on ? 0.14 : 0))
                        border.width: on ? 2 : 1
                        border.color: on ? Theme.accent : Theme.panelBorder
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 8 * root.unit
                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: modelData.icon
                                size: 30 * root.unit
                                color: Theme.accent
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: Theme.fontFamily
                                font.bold: true
                                font.pixelSize: 19 * root.unit
                                color: Theme.textPrimary
                                text: modelData.name
                            }
                        }
                        MouseArea { id: tabMouse; anchors.fill: parent; onClicked: root.genre = modelData.id }
                    }
                }
            }
        }

        // ---- 中段: そのジャンルのウィジェット ----
        Flickable {
            id: flick
            anchors { top: head.bottom; bottom: foot.top; left: parent.left; right: parent.right
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5 }
            clip: true
            contentWidth: width
            contentHeight: list.height
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Column {
                id: list
                width: flick.width
                spacing: Theme.margin * 0.7

                Repeater {
                    model: WidgetRegistry.ofGenre(root.genre)
                    Rectangle {
                        required property var modelData
                        width: list.width
                        height: 112 * root.unit
                        radius: Theme.radius + 4
                        color: Theme.mix(Theme.panel, Theme.accent, cardMouse.pressed ? 0.3 : 0)
                        border.width: cardMouse.pressed ? 2 : 1
                        border.color: cardMouse.pressed ? Theme.accent : Theme.panelBorder
                        scale: cardMouse.pressed ? 0.985 : 1
                        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

                        MaterialIcon {
                            id: cardIcon
                            anchors { left: parent.left; leftMargin: 22 * root.unit; verticalCenter: parent.verticalCenter }
                            name: modelData.icon
                            size: 52 * root.unit
                            color: Theme.accent
                        }
                        Column {
                            anchors { left: cardIcon.right; leftMargin: 20 * root.unit; right: addLabel.left; rightMargin: 16 * root.unit
                                      verticalCenter: parent.verticalCenter }
                            spacing: 4 * root.unit
                            Row {
                                spacing: 10 * root.unit
                                Text {
                                    font.family: Theme.fontFamily
                                    font.bold: true
                                    font.pixelSize: 26 * root.unit
                                    color: Theme.textPrimary
                                    text: modelData.name
                                }
                                Rectangle {
                                    visible: modelData.mock
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: tag.implicitWidth + 14
                                    height: tag.implicitHeight + 6
                                    radius: height / 2
                                    color: "transparent"
                                    border.color: Theme.warn
                                    Text {
                                        id: tag
                                        anchors.centerIn: parent
                                        font.family: Theme.fontFamily
                                        text: "モックデータ"
                                        color: Theme.warn
                                        font.pixelSize: 13 * root.unit
                                    }
                                }
                            }
                            Text {
                                width: parent.width
                                font.family: Theme.fontFamily
                                font.pixelSize: 19 * root.unit
                                color: Theme.textSecondary
                                elide: Text.ElideRight
                                text: modelData.description
                            }
                        }
                        Rectangle {
                            id: addLabel
                            anchors { right: parent.right; rightMargin: 22 * root.unit; verticalCenter: parent.verticalCenter }
                            width: 112 * root.unit
                            height: 56 * root.unit
                            radius: Theme.radius
                            color: Theme.accentFill
                            Text {
                                anchors.centerIn: parent
                                font.family: Theme.fontFamily
                                font.bold: true
                                font.pixelSize: 22 * root.unit
                                color: Theme.textOnAccent
                                text: "追加"
                            }
                        }
                        MouseArea {
                            id: cardMouse
                            anchors.fill: parent
                            onClicked: {
                                if (root.area && root.area.addWidget(modelData.type)) root.close()
                            }
                        }
                    }
                }
            }
        }

        // ---- 下段 ----
        Item {
            id: foot
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5 }
            height: 96 * root.unit
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 1
                color: Theme.panelBorder
            }
            ActionButton {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: root.confirmReset ? "もう一度押すと初期配置に戻します" : "初期配置に戻す"
                onClicked: {
                    if (!root.confirmReset) {
                        root.confirmReset = true
                        resetTimer.restart()
                    } else {
                        root.confirmReset = false
                        if (root.area) root.area.resetLayout()
                        root.close()
                    }
                }
            }
            Timer { id: resetTimer; interval: 4000; onTriggered: root.confirmReset = false }
            ActionButton {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                selected: true
                text: "閉じる"
                onClicked: root.close()
            }
        }
    }
}
