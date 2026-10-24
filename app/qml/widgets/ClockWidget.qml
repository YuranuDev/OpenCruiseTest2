// 時計ウィジェット(時刻と日付)。従来の初期画面の時計カードと同じ配色・文字の大きさの比率。
// 設定: 枠(カード/なし)・配置(左/中央)・日付の表示。
import QtQuick
import OpenCruise

WidgetBase {
    id: root

    readonly property real m: root.innerMargin
    readonly property int hAlign: config.align === "center" ? Text.AlignHCenter : Text.AlignLeft

    Row {
        id: header
        visible: root.titleVisible
        anchors { top: parent.top; left: parent.left; leftMargin: root.m; topMargin: root.titleVisible ? root.m * 0.8 : 0 }
        spacing: 8
        height: root.titleVisible ? root.titleBarHeight : 0
        MaterialIcon { anchors.verticalCenter: parent.verticalCenter; name: "schedule"; size: parent.height; color: Theme.accent }
        Text {
            width: Math.max(0, root.width - root.m * 2 - parent.height - parent.spacing)
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily; font.pixelSize: root.headerFontSize
            color: Theme.textSecondary; text: root.titleText("時計"); elide: Text.ElideRight
        }
    }

    Item {
        id: body
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        anchors.topMargin: root.titleVisible ? root.m * 0.25 : 0

        Column {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                      leftMargin: root.m; rightMargin: root.m }
        spacing: 2

        Text {
            width: parent.width
            height: Math.min(root.height * 0.42, root.width * 0.32)
            horizontalAlignment: root.hAlign
            verticalAlignment: Text.AlignVCenter
            font.family: Theme.fontFamily
            font.bold: true
            font.pixelSize: 200
            minimumPixelSize: 12
            fontSizeMode: Text.Fit
            text: clock.timeText
            color: Theme.textPrimary
        }
        Text {
            width: parent.width
            height: Math.min(root.height * 0.14, root.width * 0.09)
            horizontalAlignment: root.hAlign
            verticalAlignment: Text.AlignVCenter
            font.family: Theme.fontFamily
            font.pixelSize: 100
            minimumPixelSize: 10
            fontSizeMode: Text.Fit
            text: clock.dateText
            color: Theme.textSecondary
            opacity: root.config.showDate === false ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }
        }
    }
}
