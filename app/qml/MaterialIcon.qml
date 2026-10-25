// アイコンを表示する部品。name にアイコン名を渡す。
//   - "usb" や "directions_car" など: Google の Material Icons(app/fonts/MaterialIcons-Regular.ttf、Apache License 2.0)。
//     名前は https://fonts.google.com/icons で探せる(合字で表示する)。
//   - "mdi:oil-temperature" のように "mdi:" を付けると: Pictogrammers の Material Design Icons
//     (app/fonts/materialdesignicons-webfont.ttf、Apache License 2.0)。警告灯に近い車のアイコンが多い。
//     名前は https://pictogrammers.com/library/mdi/ で探せる(文字コードは MdiCodes.js で引く)。
import QtQuick
import "MdiCodes.js" as Mdi

Text {
    property string name: ""
    property int size: 24

    readonly property bool isMdi: name.startsWith("mdi:")

    FontLoader {
        id: iconFont
        source: isMdi ? "../fonts/materialdesignicons-webfont.ttf" : "../fonts/MaterialIcons-Regular.ttf"
    }

    text: isMdi ? Mdi.glyph(name.substring(4)) : name
    font.family: iconFont.name
    font.pixelSize: size
    color: Theme.textPrimary
    // 字形が読み込まれるまで、アイコン名の文字列がちらつかないようにする
    opacity: iconFont.status === FontLoader.Ready ? 1 : 0
}
