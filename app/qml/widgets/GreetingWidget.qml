// あいさつウィジェット。時刻に応じて「おはようございます / こんにちは / こんばんは」を出し、
// ユーザー名(設定「一般」)があれば「〜、○○ さん」を付ける。
// 設定: 枠(カード/なし)・配置(左/中央)・名前を付けるか。
import QtQuick
import OpenCruise

WidgetBase {
    id: root

    readonly property string greeting: {
        const h = clock.hour
        return (h >= 4 && h < 11) ? "おはようございます" : (h >= 11 && h < 18) ? "こんにちは" : "こんばんは"
    }
    readonly property bool useName: config.showName !== false && appSettings.userName !== ""
    readonly property string greetingText: useName ? greeting + "、" + appSettings.userName + " さん" : greeting

    Row {
        id: header
        visible: root.titleVisible
        anchors { top: parent.top; left: parent.left; leftMargin: Math.max(10, Math.min(18, root.s * 0.2)); topMargin: root.titleVisible ? 6 : 0 }
        spacing: 8
        height: root.titleVisible ? root.titleBarHeight : 0
        MaterialIcon { anchors.verticalCenter: parent.verticalCenter; name: "waving_hand"; size: parent.height; color: Theme.accent }
        Text {
            width: Math.max(0, root.width - 2 * Math.max(10, Math.min(18, root.s * 0.2)) - parent.height - parent.spacing)
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily; font.pixelSize: root.headerFontSize
            color: Theme.textSecondary; text: root.titleText("あいさつ"); elide: Text.ElideRight
        }
    }

    Item {
        id: body
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        anchors.topMargin: root.titleVisible ? 4 : 0

        Text {
        readonly property real margin: Math.max(10, Math.min(18, root.s * 0.2))
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                  leftMargin: margin; rightMargin: margin }
        horizontalAlignment: root.config.align === "center" ? Text.AlignHCenter : Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
        font.family: Theme.fontFamily
        font.pixelSize: 100
        minimumPixelSize: 10
        fontSizeMode: Text.Fit
        // 1 行に収め、狭い場合は文字サイズを縮める
        height: Math.min(parent.height - 8, 36)
        elide: Text.ElideRight
        text: root.greetingText
        color: Theme.textSecondary
        }
    }
}
