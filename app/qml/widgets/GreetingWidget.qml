// あいさつウィジェット。時刻に応じて「おはようございます / こんにちは / こんばんは」を出し、
// ユーザー名(設定「一般」)があれば「〜、○○ さん」を付ける。
// 設定: 枠(カード/なし)・配置(左/中央)・名前を付けるか。
import QtQuick
import OpenCruise

WidgetBase {
    id: root
    framed: config.frame !== "plain"

    readonly property string greeting: {
        const h = clock.hour
        return (h >= 4 && h < 11) ? "おはようございます" : (h >= 11 && h < 18) ? "こんにちは" : "こんばんは"
    }
    readonly property bool useName: config.showName !== false && appSettings.userName !== ""
    readonly property string greetingText: useName ? greeting + "、" + appSettings.userName + " さん" : greeting

    Text {
        readonly property real margin: Math.max(14, Math.min(28, root.s * 0.3))
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                  leftMargin: margin; rightMargin: margin }
        horizontalAlignment: root.config.align === "center" ? Text.AlignHCenter : Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
        font.family: Theme.fontFamily
        font.pixelSize: 100
        minimumPixelSize: 10
        fontSizeMode: Text.Fit
        // 高さに上限を付けて、1 行の見出しとして従来(26px 前後)と同程度の大きさに収める
        height: Math.min(parent.height - 8, 36)
        elide: Text.ElideRight
        text: root.greetingText
        color: Theme.textSecondary
    }
}
