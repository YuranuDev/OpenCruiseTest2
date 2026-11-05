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
    readonly property real m: root.innerMargin
    readonly property color stateColor: incoming ? Theme.warn : (active ? Theme.ok : (hold ? Theme.accent : Theme.textSecondary))

    // 通話時間を 1 秒ごとに読み直すための刻み
    property int tick: 0
    Timer {
        interval: 1000
        running: root.active && !root.lifting && root.onScreen   // 通話時間の表示だけ。見えたら読み直す
        repeat: true
        onTriggered: root.tick++
    }
    onOnScreenChanged: if (onScreen) tick++

    // 着信中は点滅して目立たせる
    property real blink: 1
    SequentialAnimation on blink {
        running: root.incoming && root.config.blink !== false && !root.lifting && root.onScreen
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
        visible: root.titleVisible
        anchors { top: parent.top; left: parent.left; topMargin: root.titleVisible ? root.m * 0.8 : 0; leftMargin: root.m }
        width: Math.max(0, root.width - root.m * 2 - (mockBadge.visible ? mockBadge.width + root.m : 0))
        spacing: 8
        height: root.titleVisible ? root.titleBarHeight : 0
        clip: true
        MaterialIcon {
            id: headerIcon
            anchors.verticalCenter: parent.verticalCenter
            name: root.incoming ? "ring_volume" : (root.active ? "phone_in_talk" : (root.hold ? "phone_paused" : "call"))
            size: parent.height
            color: Theme.accent   // 見出しのアイコンは他のウィジェットと同じ色(状態の色は本文側で示す)
            opacity: root.incoming ? root.blink : 1
        }
        Text {
            width: Math.max(0, header.width - headerIcon.width - header.spacing)
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily
            text: root.titleText("通話")
            color: Theme.textSecondary
            font.pixelSize: root.headerFontSize
            elide: Text.ElideRight
        }
    }
    Rectangle {
        id: mockBadge
        visible: phoneStatus.callIsMock
        anchors { verticalCenter: header.verticalCenter; right: parent.right; rightMargin: root.m }
        width: Math.min(mockTag.implicitWidth + 14, root.width * 0.35)
        height: mockTag.implicitHeight + 6
        radius: height / 2
        color: "transparent"
        border.color: Theme.warn
        Text {
            id: mockTag
            anchors.centerIn: parent
            width: Math.max(0, parent.width - 8)
            font.family: Theme.fontFamily
            text: "モック"
            color: Theme.warn
            font.pixelSize: root.detailFontSize
            minimumPixelSize: 8
            fontSizeMode: Text.Fit
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    // ---- 本体 ----
    Item {
        id: callDetails
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right
                  margins: root.m; topMargin: root.titleVisible ? root.m * 0.4 : 0 }
        clip: true

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
                width: callDetails.width
                height: Math.max(18, callDetails.height * 0.22)
                anchors.horizontalCenter: parent.horizontalCenter
                font.family: Theme.fontFamily
                text: !phoneStatus.connected && !phoneStatus.callIsMock ? "スマートフォンを接続してください"
                                                                        : "通話はありません"
                color: Theme.textSecondary
                font.pixelSize: Math.max(10, Math.min(root.bodyFontSize, height * 0.8))
                minimumPixelSize: 9
                fontSizeMode: Text.Fit
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // 着信中・通話中・保留中
        Column {
            visible: !root.idle
            anchors.fill: parent
            spacing: root.m * 0.12
            clip: true

            Text {
                width: parent.width
                height: parent.height * 0.18
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: Math.max(10, Math.min(root.bodyFontSize, height * 0.72))
                minimumPixelSize: 9
                fontSizeMode: Text.Fit
                color: root.stateColor
                opacity: root.incoming ? root.blink : 1
                text: root.incoming ? "着信中" : (root.hold ? "保留中" : "通話中")
            }
            Text {
                width: parent.width
                height: parent.height * 0.34
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: Math.min(root.s * 0.24, height * 0.72)
                minimumPixelSize: 11
                fontSizeMode: Text.Fit
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                color: Theme.textPrimary
                text: root.partyName
            }
            Text {
                visible: root.showNumberLine
                width: parent.width
                height: visible ? parent.height * 0.16 : 0
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.family: Theme.fontFamily
                font.pixelSize: Math.min(root.detailFontSize, height * 0.72)
                minimumPixelSize: 9
                fontSizeMode: Text.Fit
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                color: Theme.textSecondary
                text: phoneStatus.callNumber
            }
            Text {
                visible: root.active
                width: parent.width
                height: visible ? parent.height * 0.20 : 0
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: Math.max(10, Math.min(root.s * 0.13, height * 0.72))
                minimumPixelSize: 9
                fontSizeMode: Text.Fit
                wrapMode: Text.NoWrap
                color: Theme.ok
                // tick を読むことで、1 秒ごとに通話時間を読み直す
                text: { root.tick; return root.durationText(phoneStatus.callDurationSec) }
            }
        }
    }
}
