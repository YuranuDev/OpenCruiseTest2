// Google の Material Icons（app/fonts/MaterialIcons-Regular.ttf、Apache License 2.0）を表示する部品。
// name にアイコン名を渡す（例: "usb", "directions_car"）。名前は https://fonts.google.com/icons で探せる。
import QtQuick

Text {
    property string name: ""
    property int size: 24

    FontLoader { id: iconFont; source: "../fonts/MaterialIcons-Regular.ttf" }

    text: name
    font.family: iconFont.name
    font.pixelSize: size
    color: Theme.textPrimary
    // 字形が読み込まれるまで、アイコン名の文字列がちらつかないようにする
    opacity: iconFont.status === FontLoader.Ready ? 1 : 0
}
