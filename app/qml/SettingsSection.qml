// 設定ページ内のまとまり(カード)。タイトル(アイコン付き)の下に、子要素(SettingsRow など)を縦に並べる。
import QtQuick

Panel {   // テーマに合わせた面
    id: root
    property string title: ""
    property string icon: ""
    default property alias content: body.data

    readonly property real unit: Theme.uiScale
    readonly property real pad: 22 * unit

    width: parent ? parent.width : implicitWidth
    implicitHeight: inner.implicitHeight + 2 * pad
    height: implicitHeight
    radius: Theme.radius + 6

    Column {
        id: inner
        x: root.pad
        y: root.pad
        width: parent.width - 2 * root.pad
        spacing: 6 * root.unit

        Row {
            visible: root.title !== ""
            spacing: 12 * root.unit
            height: visible ? 44 * root.unit : 0

            MaterialIcon {
                visible: root.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                name: root.icon
                size: 34 * root.unit
                color: Theme.accent
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.fontFamily
                text: root.title
                color: Theme.textPrimary
                font.pixelSize: 30 * root.unit
                font.bold: true
            }
        }

        Column {
            id: body
            width: parent.width
            spacing: 0
        }
    }
}
