// 再生中ウィジェット(Android Auto 連携)。スマートフォンで再生中の曲(曲名・アーティスト・アルバム)と、
// 再生位置のバー・経過/全体の時間・再生状態を表示する。
// 実データ: MediaPlaybackStatus チャネル(メタデータと再生状態)。スマホが送ってこない間は、モックが ON なら
// モックの曲(3 曲を順に再生)を表示する。モックの間は「モック」と表示する。表示専用(スマホの再生操作は送らない)。
// 再生位置はスマホが通知した値に、受け取ってからの経過時間を足して 1 秒ごとに進める(再生中のみ)。
import QtQuick
import OpenCruise

WidgetBase {
    id: root

    readonly property bool playing: phoneStatus.playbackState === "playing"
    readonly property bool paused: phoneStatus.playbackState === "paused"
    readonly property real m: root.innerMargin
    readonly property int duration: phoneStatus.trackDurationSec
    readonly property bool showAlbum: config.showAlbum !== false
    readonly property bool showProgress: config.showProgress !== false && duration > 0

    // 位置を 1 秒ごとに読み直すための現在時刻
    property real nowMs: Date.now()
    Timer {
        interval: 1000
        running: root.playing && !root.lifting
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }

    // 表示する再生位置[秒]。再生中は、スマホが通知した位置に経過時間を足し、曲の長さを超えないようにする
    readonly property int position: {
        let pos = phoneStatus.playbackPositionSec
        if (root.playing) {
            pos += Math.max(0, Math.floor((root.nowMs - phoneStatus.playbackStampMs) / 1000))
        }
        return root.duration > 0 ? Math.min(pos, root.duration) : pos
    }

    function two(n) { return n < 10 ? "0" + n : "" + n }
    function timeText(sec) { return Math.floor(sec / 60) + ":" + two(sec % 60) }

    readonly property string subtitle: {
        const parts = []
        if (phoneStatus.trackArtist !== "") parts.push(phoneStatus.trackArtist)
        if (root.showAlbum && phoneStatus.trackAlbum !== "") parts.push(phoneStatus.trackAlbum)
        return parts.join("  ・  ")
    }

    // ---- 上段: 名称・再生元・モック表示 ----
    Row {
        id: header
        visible: root.titleVisible
        anchors { top: parent.top; left: parent.left; topMargin: root.titleVisible ? root.m * 0.8 : 0; leftMargin: root.m }
        width: root.width - root.m * 2
        spacing: 8
        height: root.titleVisible ? root.titleBarHeight : 0
        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.playing ? "music_note" : "queue_music"
            size: parent.height
            color: Theme.accent
        }
        Text {
            width: Math.max(0, parent.width - parent.height - parent.spacing)
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily
            text: root.titleText("再生中")
            elide: Text.ElideRight
            color: Theme.textSecondary
            font.pixelSize: root.headerFontSize
        }
    }
    Row {
        anchors { verticalCenter: header.verticalCenter; right: parent.right; rightMargin: root.m }
        spacing: 8
        Text {   // 再生元アプリ名(通知されたときだけ)
            visible: phoneStatus.hasTrack && phoneStatus.playbackSource !== "" && !phoneStatus.mediaIsMock
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily
            text: phoneStatus.playbackSource
            color: Theme.textSecondary
            font.pixelSize: root.detailFontSize
            elide: Text.ElideRight
            width: Math.min(implicitWidth, root.width * 0.4)
        }
        Rectangle {
            visible: phoneStatus.mediaIsMock
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
    }

    // ---- 本体 ----
    Item {
        id: bodyBox
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right
                  margins: root.m; topMargin: root.titleVisible ? root.m * 0.4 : 0 }

        // 曲が無いとき
        Column {
            visible: !phoneStatus.hasTrack
            anchors.centerIn: parent
            spacing: root.m * 0.3
            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "album"
                size: Math.max(28, root.s * 0.28)
                color: Theme.textSecondary
                opacity: 0.6
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                font.family: Theme.fontFamily
                text: !phoneStatus.connected ? "スマートフォンを接続してください" : "再生中の曲はありません"
                color: Theme.textSecondary
                font.pixelSize: root.bodyFontSize
            }
        }

        // 曲の情報
        Column {
            visible: phoneStatus.hasTrack
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: root.m * 0.35

            MarqueeText {   // 曲名。幅に収まらないときだけ横スクロール
                width: parent.width
                height: Math.max(26, root.height * 0.2)
                text: phoneStatus.trackSong !== "" ? phoneStatus.trackSong : "曲名不明"
                color: Theme.textPrimary
                pixelSize: Math.max(18, root.s * 0.13)
                bold: true
                paused: root.lifting
            }
            MarqueeText {
                visible: root.subtitle !== ""
                width: parent.width
                height: Math.max(18, root.s * 0.1)
                fontFamily: Theme.fontFamily
                pixelSize: root.bodyFontSize
                color: Theme.textSecondary
                text: root.subtitle
                paused: root.lifting
            }

            // 再生位置のバー(曲の長さが分かるときだけ)
            Item {
                visible: root.showProgress
                width: parent.width
                height: Math.max(10, root.s * 0.07)
                Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.panelBorder }
                Rectangle {
                    width: root.duration > 0 ? Math.max(parent.height, parent.width * root.position / root.duration) : 0
                    height: parent.height
                    radius: height / 2
                    color: root.paused ? Theme.textSecondary : Theme.accent
                    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                }
            }

            // 再生状態・経過/全体の時間
            Item {
                width: parent.width
                height: Math.max(18, root.s * 0.1)
                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.playing ? "play_arrow" : (root.paused ? "pause" : "stop")
                        size: Math.max(18, root.s * 0.1)
                        color: root.playing ? Theme.ok : Theme.textSecondary
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.fontFamily
                        font.pixelSize: root.detailFontSize
                        color: Theme.textSecondary
                        text: root.playing ? "再生中" : (root.paused ? "一時停止" : "停止")
                    }
                }
                Text {
                    visible: root.showProgress || root.position > 0
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    font.family: Theme.fontFamily
                    font.pixelSize: root.detailFontSize
                    color: Theme.textSecondary
                    text: root.timeText(root.position) + (root.duration > 0 ? " / " + root.timeText(root.duration) : "")
                }
            }
        }
    }
}
