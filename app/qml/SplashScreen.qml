// 起動(ようこそ)画面。中央にタイトルを大きく出し、最下部に「実際の交通規制に従って走行する」旨の警告を細長い帯で出す。
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

    // ---- 中央: タイトル(強調)と、起動状況・進行バー ----
    Column {
        id: titleBlock
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
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

    // ---- 下部: 警告。下端に隙間なく、画面幅いっぱいの細長い帯で出す(文字は大きめ) ----
    Rectangle {
        id: warning
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: warningRow.implicitHeight + 2 * 16 * root.unit
        color: Theme.mix(Theme.panel, Theme.warn, 0.16)
        NumberAnimation on opacity { from: 0; to: 1; duration: 700; easing.type: Easing.OutCubic }

        // 上辺だけ警告色の線を引く
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 3
            color: Theme.warn
        }

        Row {
            id: warningRow
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                      leftMargin: 28 * root.unit; rightMargin: 28 * root.unit }
            spacing: 22 * root.unit

            MaterialIcon {
                id: warningIcon
                anchors.verticalCenter: parent.verticalCenter
                name: "warning"
                size: 72 * root.unit
                color: Theme.warn
            }

            Text {
                id: warningLabel
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.fontFamily
                text: "警告"
                color: Theme.warn
                font.pixelSize: 44 * root.unit
                font.bold: true
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.fontFamily
                width: parent.width - warningIcon.width - warningLabel.width - 2 * parent.spacing
                text: "必ず実際の交通規制(信号・標識・速度制限など)に従って走行してください。"
                color: Theme.textPrimary
                font.pixelSize: 40 * root.unit
                font.bold: true
                wrapMode: Text.WordWrap
            }
        }
    }

    ActionButton {
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: Theme.margin * 1.5; bottomMargin: warning.height + Theme.margin }
        visible: boot.active
        text: "スキップ"
        onClicked: boot.skip()
    }
}
