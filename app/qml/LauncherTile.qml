// ランチャー下部のナビバーのボタン。アイコンを上、ラベルを下に置く縦型。タップ領域は全面。
import QtQuick

Rectangle {
    id: root
    property string icon: ""
    property string title: ""
    // 画面サイズに応じた拡大率(LauncherScreen から渡す)。文字・アイコンの大きさに掛ける
    property real unit: 1.0
    // 現在表示中の画面を示す(ホームなど)。枠をアクセント色にする
    property bool selected: false
    // 今は使えない(押すと理由を知らせるなど)。薄く表示する
    property bool dimmed: false
    signal clicked()

    opacity: dimmed ? 0.45 : 1

    radius: Theme.radius + 6
    // 押している間はアクセント色をパネル色に混ぜて、押下を一目で分かるようにする(文字色はそのまま読める濃さに留める)
    color: Theme.mix(Theme.panel, Theme.accent, mouse.pressed ? 0.35 : (selected ? 0.12 : 0))
    border.width: (mouse.pressed || selected) ? 2 : 1
    border.color: (mouse.pressed || selected) ? Theme.accent : Theme.panelBorder
    scale: mouse.pressed ? 0.97 : 1.0
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

    Column {
        anchors.centerIn: parent
        width: parent.width - 16
        spacing: 2 * root.unit

        MaterialIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: root.icon
            size: 40 * root.unit
            color: Theme.accent
        }
        Text {
            font.family: Theme.fontFamily
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.title
            color: Theme.textPrimary
            font.pixelSize: 22 * root.unit
            font.bold: true
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        onClicked: { root.clicked() }
    }
}
