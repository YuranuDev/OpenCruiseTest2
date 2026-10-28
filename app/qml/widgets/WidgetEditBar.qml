// ウィジェットの編集モードで、画面の上(ステータスバーの場所)に出す編集用のバー。
//  左: 「編集中」と、ページの切り替え(pages があるとき)
//  右: 選んでいる数と、選んだものの操作(まとめて設定・削除・選択の解除)、すべて選択・追加・完了
// 削除は 2 回押し(1 回目で「もう一度押すと N 個を削除」に変わる。3 秒で元に戻る)。
import QtQuick
import OpenCruise

Item {
    id: root
    property Item area: null           // 今編集している WidgetArea
    property Item pages: null          // WidgetPages(初期画面のとき。Android Auto 画面では null)
    signal addRequested()
    signal settingsRequested(var wids)
    signal doneRequested()

    readonly property real unit: Theme.uiScale
    readonly property int selCount: area ? area.selection.length : 0
    readonly property int widgetCount: area ? area.count : 0
    // 横幅が足りないときは、補助のボタンの文字を省く(アイコンだけ)
    readonly property bool compact: width < 1100 * unit

    property bool confirmDelete: false
    property real confirmAt: 0
    onSelCountChanged: confirmDelete = false
    onVisibleChanged: confirmDelete = false
    Timer { id: confirmTimer; interval: 3000; onTriggered: root.confirmDelete = false }

    component BarButton: Rectangle {
        id: b
        property string icon: ""
        property string text: ""
        property bool showText: true
        property string tone: "normal"   // "normal" / "accent"(主な操作) / "danger"(削除) / "dangerSolid"(削除の確認中)
        signal clicked()
        readonly property bool solid: tone === "accent" || tone === "dangerSolid"
        readonly property color toneColor: tone === "danger" || tone === "dangerSolid" ? Theme.error : Theme.accent
        readonly property color onSolid: tone === "dangerSolid" ? "#ffffff" : Theme.textOnAccent
        height: root.height
        width: Math.max(height, bRow.implicitWidth + 28 * root.unit)
        radius: height / 2
        color: tone === "accent" ? Theme.mix(Theme.accentFill, "#000000", bMouse.pressed ? 0.2 : 0)
             : tone === "dangerSolid" ? Theme.mix(Theme.error, "#000000", bMouse.pressed ? 0.2 : 0)
             : Theme.mix(Theme.panel, toneColor, bMouse.pressed ? 0.35 : 0.08)
        border.width: solid ? 0 : 1.5
        border.color: tone === "normal" ? Theme.panelBorder : toneColor
        scale: bMouse.pressed ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: 80 } }
        Row {
            id: bRow
            anchors.centerIn: parent
            spacing: 6 * root.unit
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: b.icon
                size: Math.round(b.height * 0.5)
                color: b.solid ? b.onSolid : b.toneColor
            }
            Text {
                visible: b.showText && b.text !== ""
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.fontFamily
                font.pixelSize: Math.round(b.height * 0.38)
                font.bold: true
                color: b.solid ? b.onSolid : Theme.textPrimary
                text: b.text
            }
        }
        MouseArea { id: bMouse; anchors.fill: parent; onClicked: b.clicked() }
    }

    // 背景(ステータスバーの場所を覆う)
    Rectangle {
        anchors.fill: parent
        anchors.margins: -4 * root.unit
        radius: height / 2
        color: Theme.mix(Theme.panel, Theme.accent, 0.06)
        border.color: Theme.mix(Theme.panelBorder, Theme.accent, 0.5)
    }

    // ---- 左: 編集中・ページ ----
    Row {
        id: leftRow
        anchors { left: parent.left; leftMargin: 14 * root.unit; verticalCenter: parent.verticalCenter }
        spacing: 10 * root.unit
        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: "edit"
            size: Math.round(root.height * 0.55)
            color: Theme.accent
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(root.height * 0.42)
            font.bold: true
            color: Theme.textPrimary
            text: "編集中"
        }
        // ページの切り替え(編集中もページを移れる。ウィジェットの無い所の左右スワイプでも移れる)
        // 右の操作と重なるほど狭いときは出さない(スワイプで移れる)
        Row {
            id: pageSwitch
            visible: root.pages !== null && root.pages.count > 1
                     && root.width - rightRow.width - 240 * root.unit > implicitWidth
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4 * root.unit
            BarButton {
                icon: "chevron_left"
                height: root.height * 0.85
                anchors.verticalCenter: parent.verticalCenter
                opacity: root.pages && root.pages.current > 0 ? 1 : 0.35
                onClicked: if (root.pages) root.pages.setCurrent(root.pages.current - 1)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 200 * root.unit)
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Math.round(root.height * 0.36)
                color: Theme.textSecondary
                text: root.pages ? (root.pages.names[root.pages.current] || "") + "  " + (root.pages.current + 1) + " / " + root.pages.count : ""
            }
            BarButton {
                icon: "chevron_right"
                height: root.height * 0.85
                anchors.verticalCenter: parent.verticalCenter
                opacity: root.pages && root.pages.current < root.pages.count - 1 ? 1 : 0.35
                onClicked: if (root.pages) root.pages.setCurrent(root.pages.current + 1)
            }
        }
    }

    // ---- 右: 選択の操作・追加・完了 ----
    Row {
        id: rightRow
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 8 * root.unit

        // 何も選んでいないときの案内
        Text {
            visible: root.selCount === 0
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Math.max(0, root.width - leftRow.width - fixedButtons.width - 60 * root.unit))
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(root.height * 0.34)
            color: Theme.textSecondary
            text: "タップで選択 ・ ドラッグで移動"
        }

        // 選んだものの操作
        Text {
            visible: root.selCount > 0
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(root.height * 0.38)
            font.bold: true
            color: Theme.accent
            text: root.selCount + " 個選択中"
        }
        BarButton {
            visible: root.selCount > 0
            icon: "tune"
            text: "まとめて設定"
            showText: !root.compact
            onClicked: { root.confirmDelete = false; root.settingsRequested(root.area.selection.slice()) }
        }
        BarButton {
            visible: root.selCount > 0
            icon: "delete"
            tone: root.confirmDelete ? "dangerSolid" : "danger"
            text: root.confirmDelete ? "もう一度押すと " + root.selCount + " 個を削除" : "削除"
            showText: root.confirmDelete || !root.compact
            onClicked: {
                if (!root.confirmDelete) {
                    root.confirmDelete = true
                    root.confirmAt = Date.now()
                    confirmTimer.restart()
                    return
                }
                if (Date.now() - root.confirmAt < 400) return   // 2 度押しの勢いで消さない
                confirmTimer.stop()
                root.confirmDelete = false
                root.area.removeSelected()
            }
        }
        BarButton {
            visible: root.selCount > 0
            icon: "deselect"
            text: "選択を解除"
            showText: !root.compact
            onClicked: root.area.clearSelection()
        }

        Rectangle {   // 区切り
            visible: root.selCount > 0
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: root.height * 0.6
            color: Theme.panelBorder
        }

        Row {
            id: fixedButtons
            spacing: 8 * root.unit
            BarButton {
                visible: root.widgetCount > 0 && root.selCount < root.widgetCount
                icon: "select_all"
                text: "すべて選択"
                showText: !root.compact && root.selCount === 0
                onClicked: root.area.selectAll()
            }
            BarButton {
                icon: "add"
                text: "追加"
                onClicked: root.addRequested()
            }
            BarButton {
                tone: "accent"
                icon: "check"
                text: "完了"
                onClicked: root.doneRequested()
            }
        }
    }
}
