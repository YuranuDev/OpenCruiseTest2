// 時計ウィジェット(時刻と日付)。従来の初期画面の時計カードと同じ配色・文字の大きさの比率。
// 設定: 枠(カード/なし)・配置(左/中央)・日付の表示。
import QtQuick
import OpenCruise

WidgetBase {
    id: root

    // 時計は文字を大きく見せたいので、共通の余白よりさらに詰める
    readonly property real m: Math.max(5, root.innerMargin * 0.6)
    readonly property bool dateShown: root.config.showDate !== false
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
        anchors.topMargin: root.titleVisible ? root.m * 0.25 : root.m
        anchors.bottomMargin: root.m

        Column {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                      leftMargin: root.m; rightMargin: root.m }
        spacing: 0

        // 本体の高さいっぱいを使う(横幅で決まる大きさを超える分は取らない)
        Text {
            width: parent.width
            height: Math.min(body.height * (root.dateShown ? 0.72 : 0.95), parent.width * 0.48)
            horizontalAlignment: root.hAlign
            verticalAlignment: Text.AlignVCenter
            font.family: Theme.numberFontFamily
            font.bold: true
            font.pixelSize: 200
            minimumPixelSize: 12
            fontSizeMode: Text.Fit
            text: clock.timeText
            color: Theme.textPrimary
        }
        Text {
            width: parent.width
            height: root.dateShown ? Math.min(body.height * 0.24, parent.width * 0.13) : 0
            horizontalAlignment: root.hAlign
            verticalAlignment: Text.AlignVCenter
            font.family: Theme.fontFamily
            font.pixelSize: 100
            minimumPixelSize: 10
            fontSizeMode: Text.Fit
            text: clock.dateText
            color: Theme.textSecondary
            opacity: root.dateShown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }
        }
    }
}
