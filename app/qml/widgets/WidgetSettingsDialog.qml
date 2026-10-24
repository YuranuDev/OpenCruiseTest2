// ウィジェットの設定ダイアログ。ウィジェットをダブルタップすると開く(設定画面を持つウィジェットだけ)。
// 中身は、種類ごとの設定画面(WidgetRegistry の settings)+ 全ウィジェット共通の「サイズ」「削除」。
// 設定は変更のたびに WidgetArea へ反映・保存される(「完了」で閉じるだけ)。
import QtQuick
import OpenCruise

Item {
    id: root

    property var area: null          // WidgetArea
    property string wid: ""
    property bool open: false

    readonly property real unit: Theme.uiScale
    readonly property var wtype: { if (area) area.revision; return area ? area.typeOf(wid) : "" }
    readonly property var def: WidgetRegistry.find(wtype)
    // 最新の設定・サイズ(area.revision が変わるたびに読み直す)
    readonly property var cfg: { if (area) area.revision; return area ? area.configOf(wid) : ({}) }
    readonly property var size: { if (area) area.revision; return area ? area.sizeOf(wid) : ({ w: 1, h: 1 }) }

    function show(id) { wid = id; open = true }
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
        width: Math.min(parent.width - 2 * Theme.margin, 820 * root.unit)
        height: Math.min(parent.height - 2 * Theme.margin, 700 * root.unit)
        radius: Theme.radius + 8
        color: Theme.panel
        border.color: Theme.panelBorder
        scale: root.open ? 1 : 0.92
        opacity: root.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea { anchors.fill: parent }   // パネル内のタップでスクリムが反応しないようにする

        // ---- 上段 ----
        Item {
            id: titleBar
            anchors { top: parent.top; left: parent.left; right: parent.right
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5 }
            height: 84 * root.unit
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14 * root.unit
                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.def ? root.def.icon : "widgets"
                    size: 40 * root.unit
                    color: Theme.accent
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.pixelSize: 30 * root.unit
                    color: Theme.textPrimary
                    text: root.def ? root.def.name + " の設定" : "ウィジェットの設定"
                }
            }
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color: Theme.panelBorder
            }
        }

        // ---- 設定の中身 ----
        Flickable {
            id: flick
            anchors { top: titleBar.bottom; bottom: footer.top; left: parent.left; right: parent.right
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5 }
            clip: true
            contentWidth: width
            contentHeight: col.height
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Column {
                id: col
                width: flick.width

                Loader {
                    id: settingsLoader
                    width: parent.width
                    sourceComponent: root.def ? root.def.settings : null
                }
                Binding { target: settingsLoader.item; property: "config"; value: root.cfg; when: settingsLoader.item !== null }
                Connections {
                    target: settingsLoader.item
                    function onEdit(key, value) { if (root.area) root.area.setConfigValue(root.wid, key, value) }
                }

                // ---- 全ウィジェット共通: タイトル ----
                SettingsRow {
                    label: "上部タイトルを表示"
                    SettingsSwitch {
                        checked: root.cfg.showTitle !== false
                        onToggled: (v) => { if (root.area) root.area.setConfigValue(root.wid, "showTitle", v) }
                    }
                }
                SettingsRow {
                    label: "タイトル文字"
                    description: "空欄ならウィジェット標準の名前を表示します"
                    stacked: true
                    WSTextField {
                        width: 520 * Theme.uiScale
                        text: root.cfg.titleText || ""
                        placeholder: root.def ? root.def.name : "タイトル"
                        maxLength: 32
                        onEdited: (t) => { if (root.area) root.area.setConfigValue(root.wid, "titleText", t) }
                    }
                }

                // ---- 共通: サイズ ----
                SettingsRow {
                    label: "サイズ(横)"
                    description: "グリッドのマス数です。隣のウィジェットと重なる大きさにはできません"
                    WSStepper {
                        value: root.size.w
                        from: root.def ? root.def.minSize.w : 1
                        to: root.def ? root.def.maxSize.w : 12
                        step: 1
                        suffix: " マス"
                        onMoved: (v) => { if (root.area) root.area.resizeWidget(root.wid, v, root.size.h) }
                    }
                }
                SettingsRow {
                    label: "サイズ(縦)"
                    WSStepper {
                        value: root.size.h
                        from: root.def ? root.def.minSize.h : 1
                        to: root.def ? root.def.maxSize.h : 6
                        step: 1
                        suffix: " マス"
                        onMoved: (v) => { if (root.area) root.area.resizeWidget(root.wid, root.size.w, v) }
                    }
                }
            }
        }

        // ---- 下段 ----
        Item {
            id: footer
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5 }
            height: 96 * root.unit
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 1
                color: Theme.panelBorder
            }
            Row {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                ActionButton {
                    text: "このウィジェットを削除"
                    onClicked: {
                        if (root.area) root.area.removeWidget(root.wid)
                        root.close()
                    }
                }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                ActionButton {
                    selected: true
                    text: "完了"
                    onClicked: root.close()
                }
            }
        }
    }
}
