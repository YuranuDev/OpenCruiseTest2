// ウィジェットで鳴っている警告(警告音)を、まとめて解除(消音)する丸いボタン。
// 鳴っている警告があるときだけ赤く点滅して押せるようになり、無いときはグレーアウトして押せない。
// 押すと、鳴っているすべての警告を確認済みにする(各警告は、値が警告値の内側へ戻るまで鳴らない。
// メーターのタップで 1 つずつ止めるのと同じ)。右上の数字は、鳴っている警告の数。size でボタンの直径を指定する。
import QtQuick
import OpenCruise

Rectangle {
    id: root
    property real size: 52
    readonly property bool active: WarningAlarm.soundingCount > 0

    width: size
    height: size
    radius: size / 2
    color: active ? Theme.mix(Theme.panel, Theme.error, mouse.pressed ? 1.0 : 0.55 + 0.45 * (1 - blink)) : Theme.panel
    border.color: active ? Theme.error : Theme.panelBorder
    border.width: active ? 2 : 1
    opacity: active ? 1 : 0.4

    // 鳴っている間の点滅
    property real blink: 1
    SequentialAnimation on blink {
        running: root.active
        loops: Animation.Infinite
        NumberAnimation { to: 0.3; duration: 380; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 380; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.blink = 1
    }

    MaterialIcon {
        anchors.centerIn: parent
        name: root.active ? "notifications_off" : "notifications_paused"
        size: Math.round(root.size * 0.55)
        color: root.active ? "#ffffff" : Theme.textSecondary
    }

    // 鳴っている警告の数(円周の右上 45° の位置)
    Rectangle {
        readonly property real d: Math.round(root.size * 0.38)
        visible: root.active
        width: Math.max(d, countText.implicitWidth + 8)
        height: d
        radius: d / 2
        x: root.size * 0.854 - width / 2
        y: root.size * 0.146 - d / 2
        color: Theme.textPrimary
        border.width: 2
        border.color: Theme.background
        Text {
            id: countText
            anchors.centerIn: parent
            font.family: Theme.fontFamily
            font.bold: true
            font.pixelSize: Math.round(parent.height * 0.62)
            color: Theme.error
            text: WarningAlarm.soundingCount
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.active
        onClicked: WarningAlarm.acknowledgeAll()
    }
}
