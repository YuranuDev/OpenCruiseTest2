// スマホ状態ウィジェット(Android Auto 連携)。スマートフォンのバッテリー残量・残り時間・電波・接続状態を表示する。
// 実データ: バッテリー(Control チャネルの BatteryStatusNotification)と電波(PhoneStatus チャネルの signal_strength)。
// スマホが送ってこない間(未接続・非対応)は、モックが ON ならモックの値を出す。出所は phoneStatus.*IsMock で分かり、
// モックの項目には「モック」と出す。
// 残量がしきい値以下(またはスマホが「危険」と通知)で、色・アイコン・メッセージで警告する。
import QtQuick
import OpenCruise

WidgetBase {
    id: root

    readonly property int level: phoneStatus.batteryLevel            // -1 = 不明
    readonly property bool known: level >= 0
    readonly property bool low: known && (level <= (config.lowThreshold || 20) || phoneStatus.batteryCritical)
    readonly property color batteryColor: !known ? Theme.textSecondary : (low ? Theme.error : (level <= 40 ? Theme.warn : Theme.ok))
    readonly property bool anyMock: phoneStatus.batteryIsMock || (config.showSignal !== false && phoneStatus.signalIsMock)
    readonly property real m: root.innerMargin

    property real blink: 1
    SequentialAnimation on blink {
        running: root.low && !root.lifting && root.onScreen
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 450; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 450; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.blink = 1
    }

    function remainingText() {
        const sec = phoneStatus.batteryRemainingSec
        if (sec < 0) return ""
        const min = Math.round(sec / 60)
        return min >= 60 ? "残り 約 " + Math.floor(min / 60) + " 時間 " + (min % 60) + " 分" : "残り 約 " + min + " 分"
    }

    // ---- 上段: 名称・接続状態 ----
    Row {
        id: header
        visible: root.titleVisible
        anchors { top: parent.top; left: parent.left; topMargin: root.titleVisible ? root.m * 0.8 : 0; leftMargin: root.m }
        spacing: 8
        height: root.titleVisible ? root.titleBarHeight : 0
        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.low ? "battery_alert" : "smartphone"
            size: parent.height
            color: root.low ? Theme.error : Theme.accent
            opacity: root.low ? root.blink : 1
        }
        Text {
            width: Math.max(0, root.width - root.m * 2 - parent.height - parent.spacing - root.s * 0.3)
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily
            text: root.titleText("スマートフォン")
            color: Theme.textSecondary
            font.pixelSize: root.headerFontSize
            elide: Text.ElideRight
        }
    }
    Row {
        anchors { verticalCenter: header.verticalCenter; right: parent.right; rightMargin: root.m }
        spacing: 8
        Rectangle {
            visible: root.anyMock
            width: mockTag.implicitWidth + 14
            height: mockTag.implicitHeight + 6
            radius: height / 2
            color: "transparent"
            border.color: Theme.warn
            anchors.verticalCenter: parent.verticalCenter
            Text {
                id: mockTag
                anchors.centerIn: parent
                font.family: Theme.fontFamily
                text: "モック"
                color: Theme.warn
                font.pixelSize: root.detailFontSize
            }
        }
        Rectangle {   // 接続状態
            width: 14; height: 14; radius: 7
            anchors.verticalCenter: parent.verticalCenter
            color: phoneStatus.connected ? Theme.ok : Theme.textSecondary
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily
            text: phoneStatus.connected ? "接続中" : "未接続"
            color: Theme.textSecondary
            font.pixelSize: root.bodyFontSize
        }
    }

    // ---- 下段: 警告メッセージ ----
    Text {
        id: lowText
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                  leftMargin: root.m; rightMargin: root.m; bottomMargin: root.m * 0.7 }
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontFamily
        font.bold: true
        font.pixelSize: root.bodyFontSize
        elide: Text.ElideRight
        color: Theme.error
        text: root.config.lowMessage || "バッテリー残量が少なくなっています"
        // 「警告メッセージを表示」がオフなら場所も取らない(色・アイコンだけで知らせる)
        height: root.config.showLowMessage !== false ? implicitHeight : 0
        opacity: root.low && root.config.showLowMessage !== false ? root.blink : 0
        visible: opacity > 0
    }

    // ---- 本体: 左にバッテリー(残量バー+数字)、右に電波 ----
    Item {
        id: bodyBox
        anchors { top: header.bottom; bottom: lowText.top; left: parent.left; right: parent.right
                  leftMargin: root.m; rightMargin: root.m; topMargin: root.titleVisible ? root.m * 0.4 : 0 }

        Column {
            id: batteryCol
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: parent.width - (signalCol.visible ? signalCol.width + root.m : 0)
            spacing: root.m * 0.3

            Text {
                width: parent.width
                height: Math.max(26, bodyBox.height * 0.5)
                verticalAlignment: Text.AlignVCenter
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: 200
                minimumPixelSize: 14
                fontSizeMode: Text.Fit
                text: root.known ? root.level + " %" : "-- %"
                color: root.low ? Theme.error : Theme.textPrimary
            }
            // 残量バー
            Item {
                width: parent.width
                height: Math.max(12, root.s * 0.09)
                Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.panelBorder }
                Rectangle {
                    width: root.known ? Math.max(parent.height, parent.width * root.level / 100) : 0
                    height: parent.height
                    radius: height / 2
                    color: root.batteryColor
                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                }
            }
            Text {
                width: parent.width
                visible: root.config.showRemaining !== false
                font.family: Theme.fontFamily
                font.pixelSize: root.bodyFontSize
                elide: Text.ElideRight
                color: Theme.textSecondary
                text: !phoneStatus.connected && !phoneStatus.batteryIsMock ? "スマートフォンを接続してください"
                      : (root.remainingText() !== "" ? root.remainingText() : "残り時間は通知されていません")
            }
        }

        // 電波(4 本のバー)
        Column {
            id: signalCol
            visible: root.config.showSignal !== false && phoneStatus.signalStrength >= 0
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: Math.max(36, root.s * 0.28)
            spacing: 4
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Math.max(3, root.s * 0.02)
                height: Math.max(30, root.s * 0.24)
                Repeater {
                    model: 4
                    Rectangle {
                        required property int index
                        width: Math.max(6, root.s * 0.045)
                        height: parent.height * (index + 1) / 4
                        anchors.bottom: parent.bottom
                        radius: 2
                        color: index < phoneStatus.signalStrength ? Theme.accent : Theme.panelBorder
                        Behavior on color { ColorAnimation { duration: 300 } }
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                font.family: Theme.fontFamily
                text: "電波"
                color: Theme.textSecondary
                font.pixelSize: root.detailFontSize
            }
        }
    }
}
