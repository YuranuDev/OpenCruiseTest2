// Android Auto の接続状態を「色つきの点 + 文字」で表示する。
import QtQuick

Row {
    spacing: 10

    Rectangle {
        width: 16
        height: 16
        radius: 8
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.stateColor(androidAuto.stateKey)
    }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Android Auto: " + androidAuto.stateText
        color: Theme.textPrimary
        font.pixelSize: 22
    }
}
