// スマホ通知ウィジェット(通知連携)。phoneStatus.recentNotices(スマホから届いた通知)を表示する。
// 表示方法(config.mode): list=新しい順に最大 maxItems 件 / latest=最新 1 件を大きく / badge=件数だけ
// 通知文はカテゴリ(call / message / navigation / other)ごとのテンプレート(tplXxx、{text} が通知文)で整形する。
//
// 実際に取れる情報と制約: Android Auto の汎用通知(GenericNotificationMessage)は id・text・icon だけで、送信元アプリ名・
// 本文・連絡先は取れない。GenericNotification チャネルを宣言して実通知を受け取り(PhoneStatus::ingestNotice)、
// 届かない間はモックが ON なら PhoneStatus が出すモック通知で動く(カテゴリは文面から推定)。
import QtQuick
import OpenCruise

WidgetBase {
    id: root

    readonly property string mode: config.mode === "latest" || config.mode === "badge" ? config.mode : "list"
    readonly property int maxItems: Math.max(1, Math.min(5, config.maxItems || 3))
    readonly property real m: Math.max(10, root.s * 0.07)
    // 文字サイズは上限つき(ウィジェットを大きくしても通知文が巨大化してはみ出さない)
    readonly property real fsHead: Math.max(13, Math.min(root.s * 0.075, 18))
    readonly property real fsBody: Math.max(12, Math.min(root.s * 0.064, 17))
    readonly property real fsBig:  Math.max(14, Math.min(root.s * 0.078, 22))
    readonly property real fsSub:  Math.max(10, Math.min(root.s * 0.052, 13))
    property real nowMs: Date.now()

    Timer {   // 「n 分前」の表示を更新する
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }

    // 「その他」を隠す設定を反映した一覧
    readonly property var visibleNotices: {
        const all = phoneStatus.recentNotices
        return config.showOther === false ? all.filter(n => n.category !== "other") : all
    }

    function templateFor(category) {
        switch (category) {
        case "call": return config.tplCall
        case "message": return config.tplMessage
        case "navigation": return config.tplNavigation
        default: return config.tplOther
        }
    }
    function formatNotice(n) {
        const tpl = templateFor(n.category)
        return (tpl && tpl.length > 0 ? tpl : "{text}").split("{text}").join(n.text)
    }
    function ago(ms) {
        const sec = Math.max(0, Math.round((nowMs - ms) / 1000))
        return sec < 60 ? "たった今" : (sec < 3600 ? Math.floor(sec / 60) + " 分前" : Math.floor(sec / 3600) + " 時間前")
    }

    // ---- 上段: 名称・件数・モック表示 ----
    Row {
        id: header
        anchors { top: parent.top; left: parent.left; topMargin: root.m * 0.8; leftMargin: root.m }
        spacing: 8
        height: Math.max(20, root.s * 0.11)
        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.visibleNotices.length > 0 ? "notifications_active" : "notifications_none"
            size: parent.height
            color: Theme.accent
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily
            text: "スマホ通知"
            color: Theme.textSecondary
            font.pixelSize: root.fsHead
        }
    }
    Row {
        anchors { verticalCenter: header.verticalCenter; right: parent.right; rightMargin: root.m }
        spacing: 8
        Rectangle {
            visible: root.visibleNotices.length > 0 && root.visibleNotices[0].mock === true
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
                font.pixelSize: root.fsSub
            }
        }
    }

    // ---- 本体 ----
    Item {
        id: bodyBox
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right
                  margins: root.m; topMargin: root.m * 0.5 }
        clip: true

        Text {   // 通知が無いとき
            anchors.centerIn: parent
            visible: root.visibleNotices.length === 0
            font.family: Theme.fontFamily
            text: "通知はありません"
            color: Theme.textSecondary
            font.pixelSize: root.fsBody
        }

        // 件数だけ
        Column {
            visible: root.mode === "badge" && root.visibleNotices.length > 0
            anchors.centerIn: parent
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: Math.max(28, Math.min(root.s * 0.3, 64))
                color: Theme.textPrimary
                text: root.visibleNotices.length
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                font.family: Theme.fontFamily
                font.pixelSize: root.fsBody
                color: Theme.textSecondary
                text: "件の通知"
            }
        }

        // 最新 1 件 / 一覧(行の高さを揃えて、件数が変わっても崩れない)
        Column {
            visible: root.mode !== "badge"
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: root.m * 0.5

            Repeater {
                model: root.mode === "latest" ? Math.min(1, root.visibleNotices.length)
                                              : Math.min(root.maxItems, root.visibleNotices.length)
                Rectangle {
                    required property int index
                    readonly property var n: root.visibleNotices[index]
                    readonly property bool big: root.mode === "latest"
                    width: parent.width
                    height: big ? Math.max(60, bodyBox.height) : Math.max(52, Math.min(bodyBox.height / root.maxItems - root.m * 0.5, 80))
                    readonly property int lines: big ? 3 : (height >= 62 ? 2 : 1)
                    clip: true
                    radius: Theme.radius
                    color: Theme.mix(Theme.panel, Theme.accent, 0.08)
                    border.color: Theme.panelBorder

                    MaterialIcon {
                        id: ic
                        visible: root.config.showIcon !== false
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        name: n.icon
                        size: Math.min(parent.height * 0.45, 32)
                        color: Theme.accent
                    }
                    Column {
                        anchors { left: ic.visible ? ic.right : parent.left; leftMargin: 12
                                  right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Text {
                            width: parent.width
                            font.family: Theme.fontFamily
                            font.bold: true
                            font.pixelSize: big ? root.fsBig : root.fsBody
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            maximumLineCount: lines
                            elide: Text.ElideRight
                            color: Theme.textPrimary
                            text: root.formatNotice(n)
                        }
                        Text {
                            width: parent.width
                            font.family: Theme.fontFamily
                            font.pixelSize: root.fsSub
                            color: Theme.textSecondary
                            text: root.ago(n.time)
                        }
                    }
                }
            }
        }
    }
}
