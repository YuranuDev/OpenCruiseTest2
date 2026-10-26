// 再生中ウィジェット(Android Auto 連携)。スマートフォンで再生中の曲(曲名・アーティスト・アルバム)と、
// 再生位置のバー・経過/全体の時間・再生状態を表示する。
// 実データ: MediaPlaybackStatus チャネル(メタデータと再生状態)。スマホが送ってこない間は、モックが ON なら
// モックの曲(3 曲を順に再生)を表示する。モックの間は「モック」と表示する。表示専用(スマホの再生操作は送らない)。
// 再生位置はスマホが通知した値に、受け取ってからの経過時間を足して 1 秒ごとに進める(再生中のみ)。
//
// レイアウト(本体 = 見出しの下の領域):
//   - 横長・標準: 左にジャケット風のタイル、右に曲名/アーティスト/アルバム。再生位置のバーと時間は下段に横いっぱい
//   - 縦長(高さが幅の 0.85 倍以上で十分な高さ): タイルを上に、文字は中央そろえで下に並べる
//   - 低い(下段を置くと文字が入らない): 再生位置は文字列の下に細いバーだけ出す
// 文字の大きさは曲名(fontT)を基準に、アーティスト・アルバムをその比で決める。時間とバーは高さで決める(どのサイズでも同じ見た目の比率)。
// タイルはスマホからジャケット画像が届けばその画像、届かなければ曲(アルバム → アーティスト → 曲名)の
// 文字列から決まる色相のグラデーション。曲名・アーティスト・アルバムは幅に収まらないときだけ横スクロールする。
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
        running: root.playing && !root.lifting && root.onScreen   // 表示用の時刻だけ。見えたら読み直す
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }
    onOnScreenChanged: if (onScreen) nowMs = Date.now()

    // 表示する再生位置[秒]。再生中は、スマホが通知した位置に経過時間を足し、曲の長さを超えないようにする
    readonly property int position: {
        let pos = phoneStatus.playbackPositionSec
        if (root.playing) {
            pos += Math.max(0, Math.floor((root.nowMs - phoneStatus.playbackStampMs) / 1000))
        }
        return root.duration > 0 ? Math.min(pos, root.duration) : pos
    }
    readonly property real ratio: root.duration > 0 ? Math.max(0, Math.min(1, root.position / root.duration)) : 0

    function two(n) { return n < 10 ? "0" + n : "" + n }
    function timeText(sec) {
        sec = Math.max(0, Math.floor(sec))
        const h = Math.floor(sec / 3600)
        const mm = Math.floor((sec % 3600) / 60)
        return h > 0 ? h + ":" + two(mm) + ":" + two(sec % 60) : mm + ":" + two(sec % 60)
    }

    readonly property string songText: phoneStatus.trackSong !== "" ? phoneStatus.trackSong : "曲名不明"
    readonly property string artistText: phoneStatus.trackArtist
    readonly property string albumText: root.showAlbum ? phoneStatus.trackAlbum : ""

    // タイルの色相(0〜1)。同じアルバムなら同じ色になる
    readonly property real hue: {
        const key = phoneStatus.trackAlbum !== "" ? phoneStatus.trackAlbum
                  : (phoneStatus.trackArtist !== "" ? phoneStatus.trackArtist : phoneStatus.trackSong)
        let h = 7
        for (let i = 0; i < key.length; ++i) h = (h * 31 + key.charCodeAt(i)) % 1000003
        return (h * 0.6180339887) % 1
    }
    readonly property color stateColor: root.playing ? Theme.accent : Theme.textSecondary

    // ---- 上段: 名称・再生元・モック表示 ----
    Item {
        id: header
        visible: root.titleVisible
        anchors { top: parent.top; left: parent.left; right: parent.right
                  topMargin: root.titleVisible ? root.m * 0.8 : 0; leftMargin: root.m; rightMargin: root.m }
        height: root.titleVisible ? root.titleBarHeight : 0
        MaterialIcon {
            id: headIcon
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            name: root.playing ? "music_note" : "queue_music"
            size: parent.height
            color: Theme.accent
        }
        Text {
            anchors { left: headIcon.right; leftMargin: 8; right: tags.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            font.family: Theme.fontFamily
            text: root.titleText("再生中")
            elide: Text.ElideRight
            color: Theme.textSecondary
            font.pixelSize: root.headerFontSize
        }
        Row {
            id: tags
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 8
            Text {   // 再生元アプリ名(通知されたときだけ)
                visible: phoneStatus.hasTrack && phoneStatus.playbackSource !== "" && !phoneStatus.mediaIsMock
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.fontFamily
                text: phoneStatus.playbackSource
                color: Theme.textSecondary
                font.pixelSize: root.headerFontSize * 0.9
                elide: Text.ElideRight
                width: Math.min(implicitWidth, root.width * 0.4)
            }
            Rectangle {
                visible: phoneStatus.mediaIsMock
                width: mockTag.implicitWidth + 12
                height: Math.round(header.height * 0.9)
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
                    font.pixelSize: Math.round(root.headerFontSize * 0.8)
                }
            }
        }
    }

    // ---- 本体 ----
    Item {
        id: area
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right
                  margins: root.m; topMargin: root.titleVisible ? root.m * 0.6 : root.m }

        // 曲が無いとき
        Column {
            visible: !phoneStatus.hasTrack
            anchors.centerIn: parent
            width: parent.width
            spacing: Math.round(root.m * 0.4)
            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: !phoneStatus.connected ? "phonelink_off" : "album"
                size: Math.round(Math.max(24, Math.min(64, area.height * 0.32)))
                color: Theme.textSecondary
                opacity: 0.6
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.fontFamily
                text: !phoneStatus.connected ? "スマートフォンを接続してください" : "再生中の曲はありません"
                color: Theme.textSecondary
                font.pixelSize: root.bodyFontSize
                elide: Text.ElideRight
            }
        }

        // 曲の情報
        Item {
            id: card
            visible: phoneStatus.hasTrack
            anchors.fill: parent

            readonly property real gap: Math.round(Math.max(6, Math.min(14, root.m)))
            // 縦長なら上下に積む
            readonly property bool stacked: height >= width * 0.85 && height >= 220
            // 時間とバーは高さだけで決める(文字の大きさを決める前に、下段の高さが要るため)
            readonly property real fontTime: Math.round(Math.max(12, Math.min(18, height * 0.075)))
            readonly property real barH: Math.round(Math.max(4, Math.min(8, height * 0.025)))
            // 横長: 文字の段に使える高さと幅(タイルは段の高さの正方形、幅の 0.34 倍まで)
            readonly property real textWEst: width - Math.min(textH, width * 0.4) - gap
            // 基準の文字サイズ(曲名)。横長は 3 行(曲名・アーティスト・アルバム)が段に入る大きさ
            readonly property real fontT: Math.round(Math.max(15, stacked
                ? Math.min(40, width * 0.09, height * 0.08)
                : Math.min(44, textH / 3.0, textWEst * 0.13)))
            readonly property real fontA: Math.round(Math.max(12, fontT * 0.66))   // アーティスト
            readonly property real fontL: Math.round(Math.max(11, fontT * 0.56))   // アルバム

            readonly property real lineT: Math.ceil(fontT * 1.3)
            readonly property real titleH: lineT
            readonly property real blockW: stacked ? width : width - tile - gap
            readonly property real lineA: Math.ceil(fontA * 1.35)
            readonly property real lineL: Math.ceil(fontL * 1.35)

            // 再生位置の段(バー + 時間)の高さ
            readonly property real progH: root.showProgress ? barH + Math.round(gap * 0.5) + Math.ceil(fontTime * 1.3) : 0
            // 横長で下段を置くか(置くと文字が 2 行入らないときは、文字の下に細いバーだけ出す)
            readonly property bool progBottom: root.showProgress && (stacked || height - progH - gap >= 15 * 1.3 + 12 * 1.35)
            readonly property real textH: height - (progBottom ? progH + gap : 0)

            // 文字の行(高さに入る分だけ出す。アルバムは最後に省く)
            readonly property bool showArtist: root.artistText !== "" && (stacked || textH >= lineT + lineA)
            readonly property bool showAlbumLine: root.albumText !== "" && (stacked || textH >= titleH + lineA + lineL + 4)
            readonly property bool inlineBar: root.showProgress && !progBottom
            readonly property real blockH: titleH + (showArtist ? lineA : 0) + (showAlbumLine ? lineL : 0)
                                           + (inlineBar ? barH + Math.round(gap * 0.6) : 0)

            // タイル: 横長は文字の段の高さ、縦長は残りの高さと幅の小さいほう
            readonly property real tile: Math.round(stacked
                ? Math.max(48, Math.min(width * 0.62, height - blockH - progH - gap * 2))
                : Math.max(36, Math.min(textH, width * 0.4)))

            // ---- タイル ----
            Rectangle {
                id: art
                width: card.tile
                height: card.tile
                x: card.stacked ? Math.round((card.width - width) / 2) : 0
                y: card.stacked
                   ? Math.round((card.height - (card.tile + card.gap + card.blockH + (card.progBottom ? card.gap + card.progH : 0))) / 2)
                   : Math.round((card.textH - height) / 2)
                radius: Math.round(width * 0.14)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.hsla(root.hue, 0.55, Theme.night ? 0.42 : 0.55, 1) }
                    GradientStop { position: 1.0; color: Qt.hsla((root.hue + 0.09) % 1, 0.6, Theme.night ? 0.2 : 0.35, 1) }
                }
                MaterialIcon {
                    visible: cover.status !== Image.Ready
                    anchors.centerIn: parent
                    name: "music_note"
                    size: Math.round(parent.width * 0.5)
                    color: "#ffffff"
                    opacity: 0.5
                }
                // ジャケット画像(スマホが送ってきたときだけ)。角の丸めと切り抜きは画像プロバイダーがする
                Image {
                    id: cover
                    anchors.fill: parent
                    visible: status === Image.Ready
                    source: phoneStatus.trackArtUrl
                    sourceSize: Qt.size(Math.ceil(card.tile), Math.ceil(card.tile))
                    asynchronous: true
                    cache: false
                    smooth: true
                }
                // 再生状態の印(右下)。再生中はイコライザーが動く
                Rectangle {
                    id: badge
                    readonly property real d: Math.round(Math.max(18, parent.width * 0.3))
                    width: d; height: d; radius: d / 2
                    anchors { right: parent.right; bottom: parent.bottom; margins: Math.round(parent.width * 0.06) }
                    color: root.playing ? Theme.accent : Qt.rgba(0, 0, 0, 0.55)
                    MaterialIcon {
                        visible: !root.playing
                        anchors.centerIn: parent
                        name: root.paused ? "pause" : "stop"
                        size: Math.round(badge.d * 0.62)
                        color: "#ffffff"
                    }
                    Row {
                        visible: root.playing
                        anchors.centerIn: parent
                        height: Math.round(badge.d * 0.44)
                        spacing: Math.max(1, Math.round(badge.d * 0.07))
                        Repeater {
                            model: [0.55, 1.0, 0.7]
                            Rectangle {
                                id: eqBar
                                required property var modelData
                                required property int index
                                width: Math.max(2, Math.round(badge.d * 0.1))
                                height: parent.height * modelData
                                anchors.bottom: parent.bottom
                                radius: width / 2
                                color: Theme.textOnAccent
                                SequentialAnimation on height {
                                    running: root.playing && !root.lifting && root.onScreen
                                    loops: Animation.Infinite
                                    NumberAnimation { to: badge.height * 0.44 * (0.35 + 0.1 * eqBar.index); duration: 260 + 90 * eqBar.index; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: badge.height * 0.44; duration: 300 + 70 * eqBar.index; easing.type: Easing.InOutSine }
                                }
                            }
                        }
                    }
                }
            }

            // ---- 文字の段 ----
            Column {
                id: block
                x: card.stacked ? 0 : art.width + card.gap
                y: card.stacked ? art.y + art.height + card.gap : Math.round((card.textH - card.blockH) / 2)
                width: card.blockW
                spacing: 0

                MarqueeText {   // 曲名。幅に収まらないときだけ横スクロール
                    width: parent.width
                    height: card.lineT
                    text: root.songText
                    color: Theme.textPrimary
                    pixelSize: card.fontT
                    bold: true
                    centered: card.stacked
                    paused: root.lifting
                }
                MarqueeText {
                    visible: card.showArtist
                    width: parent.width
                    height: card.lineA
                    text: root.artistText
                    color: Theme.textPrimary
                    opacity: 0.78
                    pixelSize: card.fontA
                    centered: card.stacked
                    paused: root.lifting
                }
                MarqueeText {
                    visible: card.showAlbumLine
                    width: parent.width
                    height: card.lineL
                    text: root.albumText
                    color: Theme.textSecondary
                    pixelSize: card.fontL
                    centered: card.stacked
                    paused: root.lifting
                }
                // 低いとき: 文字の下に細いバーだけ
                Item {
                    visible: card.inlineBar
                    width: parent.width
                    height: card.barH + Math.round(card.gap * 0.6)
                    ProgressTrack {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: card.barH
                    }
                }
            }

            // ---- 下段: 再生位置のバーと時間 ----
            Column {
                visible: card.progBottom
                anchors { left: parent.left; right: parent.right }
                y: card.stacked ? block.y + card.blockH + card.gap : card.height - card.progH
                spacing: Math.round(card.gap * 0.5)
                ProgressTrack {
                    width: parent.width
                    height: card.barH
                }
                Item {
                    width: parent.width
                    height: Math.ceil(card.fontTime * 1.3)
                    Text {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        font.family: Theme.fontFamily
                        font.pixelSize: card.fontTime
                        color: Theme.textSecondary
                        text: root.timeText(root.position)
                    }
                    Text {
                        visible: root.paused
                        anchors.centerIn: parent
                        font.family: Theme.fontFamily
                        font.pixelSize: card.fontTime
                        color: Theme.textSecondary
                        text: "一時停止中"
                    }
                    Text {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        font.family: Theme.fontFamily
                        font.pixelSize: card.fontTime
                        color: Theme.textSecondary
                        text: "-" + root.timeText(root.duration - root.position)
                    }
                }
            }
        }
    }

    // 再生位置のバー
    component ProgressTrack: Item {
        Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.panelBorder }
        Rectangle {
            width: Math.max(parent.height, parent.width * root.ratio)
            height: parent.height
            radius: height / 2
            color: root.stateColor
            Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        }
    }
}
