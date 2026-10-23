// 通話ウィジェット(Android Auto 連携)。スマートフォンの通話状態を表示する。
// 状態: 通話なし / 着信中(点滅) / 通話中(経過時間) / 保留中。
// 実データ: PhoneStatus チャネルの calls(相手の名前・電話番号・通話時間)。スマホが送ってこない間は、
// モックが ON ならモックの通話(40 秒周期)を表示する。モックの間は「モック」と表示する。
import QtQuick
import OpenCruise

WidgetBase {
    id: root

    readonly property string callKind: phoneStatus.callState
    readonly property bool incoming: callKind === "incoming"
    readonly property bool active: callKind === "active"
    readonly property bool hold: callKind === "hold"
    readonly property bool idle: !incoming && !active && !hold
    readonly property real m: Math.max(10, root.s * 0.07)
    readonly property color stateColor: incoming ? Theme.warn : (active ? Theme.ok : (hold ? Theme.accent : Theme.textSecondary))

    // 通話時間を 1 秒ごとに読み直すための刻み
    property int tick: 0
    Timer {
        interval: 1000
        running: root.active && !root.lifting
        repeat: true
        onTriggered: root.tick++
    }

    // 着信中は点滅して目立たせる
    property real blink: 1
    SequentialAnimation on blink {
        running: root.incoming && root.config.blink !== false && !root.lifting
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 450; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 450; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.blink = 1
    }

    function two(n) { return n < 10 ? "0" + n : "" + n }
    function durationText(sec) {
        const h = Math.floor(sec / 3600)
        const mm = Math.floor((sec % 3600) / 60)
        const ss = sec % 60
        return h > 0 ? h + ":" + two(mm) + ":" + two(ss) : two(mm) + ":" + two(ss)
    }

    // 表示する相手: 名前 → 電話番号 → 「不明な番号」の順
    readonly property string partyName: {
        if (phoneStatus.callName !== "") return phoneStatus.callName
        if (phoneStatus.callNumber !== "") return phoneStatus.callNumber
        return "不明な番号"
    }
    readonly property bool showNumberLine: root.config.showNumber !== false && phoneStatus.callName !== ""
                                           && phoneStatus.callNumber !== ""

    // ---- 上段: 名称・モック表示 ----
    Row {
        id: header
        anchors { top: parent.top; left: parent.left; topMargin: root.m * 0.8; leftMargin: root.m }
        spacing: 8
        height: Math.max(20, root.s * 0.11)
        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.incoming ? "ring_volume" : (root.active ? "phone_in_talk" : (root.hold ? "phone_paused" : "call"))
            size: parent.height
            color: root.stateColor
            opacity: root.incoming ? root.blink : 1
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily
            text: "通話"
            color: Theme.textSecondary
            font.pixelSize: Math.max(13, root.s * 0.085)
        }
    }
    Rectangle {
        visible: phoneStatus.callIsMock
        anchors { verticalCenter: header.verticalCenter; right: parent.right; rightMargin: root.m }
        width: mockTag.implicitWidth + 14
        height: mockTag.implicitHeight + 6
        radius: height / 2
        color: "transparent"
        border.color: Theme.warn
        Text {
            id: mockTag
            anchors.centerIn: parent
            font.family: Theme.fontFamily
            text: "モック"
            color: Theme.warn
            font.pixelSize: Math.max(10, root.s * 0.06)
        }
    }

    // ---- 本体 ----
    Item {
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right
                  margins: root.m; topMargin: root.m * 0.4 }

        // 通話なし
        Column {
            visible: root.idle
            anchors.centerIn: parent
            spacing: root.m * 0.3
            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "phone_disabled"
                size: Math.max(28, root.s * 0.28)
                color: Theme.textSecondary
                opacity: 0.6
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                font.family: Theme.fontFamily
                text: !phoneStatus.connected && !phoneStatus.callIsMock ? "スマートフォンを接続してください"
                                                                        : "通話はありません"
                color: Theme.textSecondary
                font.pixelSize: Math.max(13, root.s * 0.085)
            }
        }

        // 着信中・通話中・保留中
        Column {
            visible: !root.idle
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: root.m * 0.3

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: Math.max(12, root.s * 0.08)
                color: root.stateColor
                opacity: root.incoming ? root.blink : 1
                text: root.incoming ? "着信中" : (root.hold ? "保留中" : "通話中")
            }
            Text {
                width: parent.width
                height: Math.max(26, root.height * 0.22)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: 200
                minimumPixelSize: 14
                fontSizeMode: Text.Fit
                elide: Text.ElideRight
                color: Theme.textPrimary
                text: root.partyName
            }
            Text {
                visible: root.showNumberLine
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.fontFamily
                font.pixelSize: Math.max(12, root.s * 0.07)
                elide: Text.ElideRight
                color: Theme.textSecondary
                text: phoneStatus.callNumber
            }
            Text {
                visible: root.active
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: Math.max(16, root.s * 0.13)
                color: Theme.ok
                // tick を読むことで、1 秒ごとに通話時間を読み直す
                text: { root.tick; return root.durationText(phoneStatus.callDurationSec) }
            }
        }
    }
}
