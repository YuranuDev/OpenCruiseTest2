// 起動(ようこそ)画面。上部にタイトルを大きく出し、下部に「実際の交通規制に従って走行する」旨の警告を大きく出す。
// BootManager(context property `boot`)の待ち(ESP32 などの応答待ち)が終わるまで表示を保つ。
// 待ちの制御はすべて C++ 側(BootManager)にあり、ここは表示だけ。各ステップの詳細はログに残る。
import QtQuick

Rectangle {
    id: root
    color: Theme.background

    readonly property real unit: Math.max(0.6, Math.min(width / 1280, height / 720))
    // 進行バーはなめらかに追従させる
    property real shownProgress: boot.progress
    Behavior on shownProgress { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    // 下へタッチを通さない
    MouseArea { anchors.fill: parent; enabled: root.visible }

    // ---- 上部: タイトル(強調)と、起動状況・進行バー ----
    Column {
        id: titleBlock
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -parent.height * 0.15
        width: Math.min(parent.width - Theme.margin * 4, 760 * root.unit)
        spacing: 22 * root.unit
        NumberAnimation on opacity { from: 0; to: 1; duration: 500; easing.type: Easing.OutCubic }

        Text {
            font.family: Theme.fontFamily
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "OpenCruise"
            color: Theme.textPrimary
            font.pixelSize: 112 * root.unit
            font.bold: true
        }

        Text {
            font.family: Theme.fontFamily
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: boot.summaryText
            color: boot.hasProblem && boot.done ? Theme.warn : Theme.textSecondary
            font.pixelSize: 22 * root.unit
            elide: Text.ElideRight
        }

        // 進行バー
        Rectangle {
            width: parent.width
            height: 6 * root.unit
            radius: height / 2
            color: Theme.panelBorder
            Rectangle {
                width: parent.width * root.shownProgress
                height: parent.height
                radius: height / 2
                color: Theme.accent
            }
        }
    }

    // ---- 下部: 警告(大きく)。スキップボタンと重ならないよう、その分だけ上へ空ける ----
    Rectangle {
        id: warning
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.margin * 3 + 52
        width: Math.min(parent.width - Theme.margin * 4, 1100 * root.unit)
        height: warningRow.implicitHeight + 2 * 32 * root.unit
        radius: Theme.radius + 6
        color: Theme.mix(Theme.panel, Theme.warn, 0.16)
        border.width: 3
        border.color: Theme.warn
        NumberAnimation on opacity { from: 0; to: 1; duration: 700; easing.type: Easing.OutCubic }

        Row {
            id: warningRow
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                      leftMargin: 36 * root.unit; rightMargin: 36 * root.unit }
            spacing: 32 * root.unit

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "warning"
                size: 110 * root.unit
                color: Theme.warn
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 110 * root.unit - parent.spacing
                spacing: 10 * root.unit

                Text {
                    font.family: Theme.fontFamily
                    text: "警告"
                    color: Theme.warn
                    font.pixelSize: 44 * root.unit
                    font.bold: true
                }
                Text {
                    font.family: Theme.fontFamily
                    width: parent.width
                    text: "必ず実際の交通規制(信号・標識・速度制限など)に従って走行してください。"
                    color: Theme.textPrimary
                    font.pixelSize: 36 * root.unit
                    font.bold: true
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    ActionButton {
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: Theme.margin * 1.5; bottomMargin: Theme.margin * 1.5 }
        visible: boot.active
        text: "スキップ"
        onClicked: boot.skip()
    }
}
