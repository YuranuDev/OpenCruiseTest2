// 時計ウィジェット(時刻と日付)。従来の初期画面の時計カードと同じ配色・文字の大きさの比率。
// 設定: 枠(カード/なし)・配置(左/中央)・日付の表示。
import QtQuick
import OpenCruise

WidgetBase {
    id: root
    framed: config.frame !== "plain"

    readonly property real m: Math.max(10, root.s * 0.07)
    readonly property int hAlign: config.align === "center" ? Text.AlignHCenter : Text.AlignLeft

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
