// ランチャー画面の大型ボタン。アイコン + タイトル + 補足の 1 行。タップ領域は全面。
import QtQuick

Rectangle {
    id: root
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    // 画面サイズに応じた拡大率(LauncherScreen から渡す)。文字・アイコンの大きさに掛ける
    property real unit: 1.0
    signal clicked()

    radius: Theme.radius + 6
    // 押している間はアクセント色をパネル色に混ぜて、押下を一目で分かるようにする(文字色はそのまま読める濃さに留める)
    color: Theme.mix(Theme.panel, Theme.accent, mouse.pressed ? 0.35 : 0)
    border.width: mouse.pressed ? 2 : 1
    border.color: mouse.pressed ? Theme.accent : Theme.panelBorder
    scale: mouse.pressed ? 0.98 : 1.0
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

    // アイコンは円形の下地に載せ、主要な操作対象として視線を集める
    Rectangle {
        id: badge
        width: 96 * root.unit
        height: width
        radius: width / 2
        anchors { left: parent.left; leftMargin: 28 * root.unit; verticalCenter: parent.verticalCenter }
        color: Theme.mix(Theme.panel, Theme.accent, 0.2)
        border.width: 2
        border.color: Theme.accent

        MaterialIcon {
            anchors.centerIn: parent
            name: root.icon
            size: 56 * root.unit
            color: Theme.accent
        }
    }

    Column {
        anchors {
            left: badge.right; leftMargin: 24 * root.unit
            right: parent.right; rightMargin: 20 * root.unit
            verticalCenter: parent.verticalCenter
        }
        spacing: 4 * root.unit

        Text {
            font.family: Theme.fontFamily
            width: parent.width
            text: root.title
            color: Theme.textPrimary
            font.pixelSize: 34 * root.unit
            font.bold: true
            elide: Text.ElideRight
        }
        Text {
            font.family: Theme.fontFamily
            width: parent.width
            visible: root.subtitle !== ""
            text: root.subtitle
            color: Theme.textSecondary
            font.pixelSize: 20 * root.unit
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
