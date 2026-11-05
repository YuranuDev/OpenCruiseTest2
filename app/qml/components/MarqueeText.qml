// 表示幅を超えたテキストだけを、複製した文字列で途切れずループスクロールする。
import QtQuick
import OpenCruise

Item {
    id: root

    property string text: ""
    property string fontFamily: Theme.fontFamily
    property int pixelSize: 14
    property color color: Theme.textPrimary
    property bool bold: false
    property real gap: Math.max(28, root.pixelSize * 2)
    property bool paused: false
    /// 収まるときは中央そろえにする(スクロール中は左から流れる)
    property bool centered: false

    readonly property bool overflowing: sourceText.implicitWidth > width + 1
    readonly property real travel: sourceText.implicitWidth + ticker.spacing

    clip: true

    Text {
        id: staticText
        anchors.fill: parent
        visible: !root.overflowing
        text: root.text
        color: root.color
        font.family: root.fontFamily
        font.pixelSize: root.pixelSize
        font.bold: root.bold
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: root.centered ? Text.AlignHCenter : Text.AlignLeft
        elide: Text.ElideRight
    }

    Row {
        id: ticker
        visible: root.overflowing
        height: parent.height
        spacing: root.gap

        Text {
            id: sourceText
            text: root.text
            color: root.color
            font.family: root.fontFamily
            font.pixelSize: root.pixelSize
            font.bold: root.bold
            verticalAlignment: Text.AlignVCenter
            onImplicitWidthChanged: Qt.callLater(root.restartScroll)
        }
        Text {
            text: root.text
            color: root.color
            font.family: root.fontFamily
            font.pixelSize: root.pixelSize
            font.bold: root.bold
            verticalAlignment: Text.AlignVCenter
        }
    }

    SequentialAnimation {
        id: scrollAnimation
        running: root.overflowing && !root.paused && root.visible   // 見えていない間は流さない
        loops: Animation.Infinite

        PauseAnimation { duration: 800 }
        NumberAnimation {
            target: ticker
            property: "x"
            from: 0
            to: -root.travel
            duration: Math.max(2200, root.travel * 24)
            easing.type: Easing.Linear
        }
        PauseAnimation { duration: 400 }
    }

    onTextChanged: restartScroll()
    onWidthChanged: restartScroll()
    onPixelSizeChanged: restartScroll()

    function restartScroll() {
        ticker.x = 0
        if (root.overflowing && !root.paused)
            scrollAnimation.restart()
    }
}
