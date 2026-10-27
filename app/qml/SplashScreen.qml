// 起動(ようこそ)画面。
//  - 中央: あいさつ(時刻に応じて。ユーザー名があれば「〜、○○ さん」)、タイトル「OpenCruise」、
//    サブタイトル「An Open-Source Car Integration System」、起動状況と進行バー
//  - 下部: 「実際の交通規制に従って走行する」旨の警告(角丸のカード。警告色のアイコンと見出しつき)
// BootManager(context property `boot`)の待ち(ESP32 などの応答待ち)が終わるまで表示を保つ。
// 読み込みが終わったら(ready)、注意事項の画面に切り替え、一定時間(または OK)でメイン画面へ移る(canClose)。
// 待ちの制御はすべて C++ 側(BootManager)にあり、ここは表示だけ。各ステップの詳細はログに残る。
import QtQuick

Rectangle {
    id: root
    color: Theme.bootBackground

    readonly property real unit: Math.max(0.6, Math.min(width / 1280, height / 720))
    // 進行バーはなめらかに追従させる
    property real shownProgress: boot.progress
    Behavior on shownProgress { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    // あいさつ(あいさつウィジェットと同じ区切り)
    readonly property string greeting: {
        const h = clock.hour
        return (h >= 4 && h < 11) ? "おはようございます" : (h >= 11 && h < 18) ? "こんにちは" : "こんばんは"
    }
    readonly property string greetingText: appSettings.userName !== "" ? greeting + "、" + appSettings.userName + " さん" : greeting

    // ---- 読み込み後の注意事項 ----
    // Main.qml が ready(読み込みが終わった)を渡す。注意事項を出して、OK を押すか noticeHoldMs が過ぎたら noticeDone になり、
    // canClose で起動画面ごと閉じてメイン画面へ移る。--skip-boot / --open-settings(skipNotice)のときは出さない。
    property bool ready: false
    property bool skipNotice: false
    property int noticeHoldMs: 8000          // 自動でメイン画面へ移るまでの時間(ms)。OK で先に進める
    property bool noticeDone: false
    readonly property bool noticeShowing: ready && !skipNotice && !noticeDone && !exportMode
    readonly property bool canClose: ready && (skipNotice || noticeDone)
    function dismissNotice() { noticeDone = true }
    // 注意事項の本文(アイコンは Material Icons の名前)
    readonly property var notices: [
        { icon: "traffic",      text: "必ず実際の交通規制(信号・標識・速度制限など)に従って走行してください。" },
        { icon: "touch_app",    text: "運転中は画面の操作や注視を避け、操作が必要なときは安全な場所に停車してから行ってください。" },
        { icon: "speed",        text: "本システムは試作の動作確認用です。表示される速度・回転数・警告などは参考値のため、車両本来のメーター・警告灯で確認してください。" },
        { icon: "phone_android", text: "Android Auto など、スマホ連携の映像・音声・通知は、通信状況により遅れたり途切れたりすることがあります。" }
    ]

    // 下へタッチを通さない
    MouseArea { anchors.fill: parent; enabled: root.visible }

    // ロゴ(タイトル)と警告はフェードインで出す。画面が実際に 1 枚描かれてから始めるので、
    // 起動の重い処理の間にフェードが進んでしまい、途中から急に出たように見えることがない
    property bool revealed: false
    Connections {
        target: root.Window.window
        enabled: !root.revealed
        function onFrameSwapped() { root.revealed = true }
    }
    Timer { interval: 400; running: !root.revealed; onTriggered: root.revealed = true }   // 念のため(描画の合図が来ないとき)

    // Linux の起動画面(Plymouth)との引き継ぎ:
    //  - handoff: Plymouth から引き継いだ。Plymouth は、この画面の変わらない部分(背景・タイトル・サブタイトル・
    //    進行バーの溝・警告)と同じ画像を出していたので、それらはフェードせずに最初から出す(途切れて見えない)。
    //    あいさつ・起動状況・段階の一覧・スキップだけをフェードインする
    //  - exportMode(--export-splash): Plymouth 用の画像を作る。変わる部分と進行バーの塗りは描かない
    readonly property bool handoff: typeof splashHandoff !== "undefined" && splashHandoff === true
    readonly property bool exportMode: typeof splashExport !== "undefined" && splashExport === true
    readonly property real fixedOpacity: (handoff || exportMode || revealed) ? 1 : 0   // 変わらない部分
    readonly property real liveOpacity: exportMode ? 0 : (revealed ? 1 : 0)            // 変わる部分
    // --export-splash で C++ が呼ぶ: 進行バー(溝)の位置と大きさ(この画面の座標)と色
    function bootImageGeometry() {
        const p = barTrack.mapToItem(root, 0, 0)
        return { barX: p.x, barY: p.y, barW: barTrack.width * titleBlock.scale, barH: barTrack.height * titleBlock.scale,
                 fillColor: Theme.bootAccent.toString(), backgroundColor: Theme.bootBackground.toString(),
                 textColor: Theme.bootTextSecondary.toString() }
    }

    // 背景: 上からアクセント色がうっすら差すグラデーション
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.mix(Theme.bootBackground, Theme.bootAccent, 0.10) }
            GradientStop { position: 0.6; color: Theme.bootBackground }
        }
    }

    // ---- 中央: あいさつ・タイトル・サブタイトル・起動状況 ----
    Column {
        id: titleBlock
        anchors.horizontalCenter: parent.horizontalCenter
        // 下の警告カードの分だけ上に寄せて、残りの高さの中央に置く
        // 入りきらない画面では、全体を少し縮める(上を基準に)
        readonly property real room: parent.height - warning.height - warning.anchors.bottomMargin - Theme.margin * 2
        scale: Math.min(1, room / Math.max(1, height))
        transformOrigin: Item.Top
        y: Math.max(Theme.margin, (parent.height - warning.height - warning.anchors.bottomMargin - height * scale) / 2)
        width: Math.min(parent.width - Theme.margin * 4, 900 * root.unit)
        spacing: 10 * root.unit

        Text {
            opacity: root.liveOpacity
        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.fontFamily
            font.pixelSize: 30 * root.unit
            color: Theme.bootTextSecondary
            elide: Text.ElideRight
            text: root.greetingText
        }

        // タイトル: 「Open」は細め、「Cruise」は太字のアクセント色
        Row {
            opacity: root.fixedOpacity
        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            anchors.horizontalCenter: parent.horizontalCenter
            Text {
                font.family: Theme.fontFamily
                font.pixelSize: 108 * root.unit
                font.weight: Font.Light
                color: Theme.bootTextPrimary
                text: "Open"
            }
            Text {
                font.family: Theme.fontFamily
                font.pixelSize: 108 * root.unit
                font.weight: Font.Bold
                color: Theme.bootAccent
                text: "Cruise"
            }
        }

        // サブタイトル(両側に細い線)
        Row {
            opacity: root.fixedOpacity
        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 18 * root.unit
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 56 * root.unit; height: Math.max(1, 2 * root.unit)
                color: Theme.bootPanelBorder
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.fontFamily
                font.pixelSize: 26 * root.unit
                font.letterSpacing: 1.5 * root.unit
                color: Theme.bootTextSecondary
                text: "An Open-Source Car Integration System"
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 56 * root.unit; height: Math.max(1, 2 * root.unit)
                color: Theme.bootPanelBorder
            }
        }

        Item { width: 1; height: 12 * root.unit }

        // 起動状況と進行バー
        Text {
            opacity: root.liveOpacity
        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.fontFamily
            font.pixelSize: 20 * root.unit
            color: boot.hasProblem && boot.done ? Theme.bootWarn : Theme.bootTextSecondary
            elide: Text.ElideRight
            text: boot.summaryText
        }
        Rectangle {
            id: barTrack
            opacity: root.fixedOpacity
        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width, 520 * root.unit)
            height: 6 * root.unit
            radius: height / 2
            color: Theme.bootPanelBorder
            Rectangle {
                visible: !root.exportMode   // 塗りは Plymouth が描く
                width: parent.width * root.shownProgress
                height: parent.height
                radius: height / 2
                color: Theme.bootAccent
            }
        }

        Item { width: 1; height: 4 * root.unit }

        // 起動の段階の一覧(どこまで読み込んだか)。状態のアイコン + 名前 + 補足(かかった時間など)
        Grid {
            id: stepGrid
            opacity: root.liveOpacity
            Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

            anchors.horizontalCenter: parent.horizontalCenter
            columns: 3
            columnSpacing: 18 * root.unit
            rowSpacing: 6 * root.unit
            readonly property real cellW: (parent.width - columnSpacing * (columns - 1)) / columns
            Repeater {
                model: boot
                Row {
                    id: stepRow
                    required property string title
                    required property string detail
                    required property string stateKey
                    width: stepGrid.cellW
                    height: 36 * root.unit
                    spacing: 8 * root.unit
                    readonly property color stateColor: stateKey === "ready" ? Theme.bootOk
                                                      : stateKey === "running" ? Theme.bootAccent
                                                      : stateKey === "warning" ? Theme.bootWarn
                                                      : stateKey === "failed" ? Theme.bootError : Theme.bootTextSecondary
                    MaterialIcon {
                        id: stepIcon
                        anchors.verticalCenter: parent.verticalCenter
                        size: 24 * root.unit
                        color: stepRow.stateColor
                        name: stepRow.stateKey === "ready" ? "check_circle"
                            : stepRow.stateKey === "running" ? "autorenew"
                            : stepRow.stateKey === "warning" ? "warning"
                            : stepRow.stateKey === "failed" ? "error"
                            : stepRow.stateKey === "skipped" ? "remove_circle_outline" : "radio_button_unchecked"
                        // 読み込み中は回す
                        RotationAnimation on rotation {
                            running: stepRow.stateKey === "running" && root.visible
                            from: 0; to: 360; duration: 1200; loops: Animation.Infinite
                        }
                        Binding on rotation { when: stepRow.stateKey !== "running"; value: 0 }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - stepIcon.width - parent.spacing
                        Text {
                            width: parent.width
                            font.family: Theme.fontFamily
                            font.pixelSize: 17 * root.unit
                            font.bold: stepRow.stateKey === "running"
                            color: stepRow.stateKey === "pending" ? Theme.bootTextSecondary : Theme.bootTextPrimary
                            elide: Text.ElideRight
                            text: stepRow.title
                        }
                        Text {
                            visible: text !== ""
                            width: parent.width
                            font.family: Theme.fontFamily
                            font.pixelSize: 13 * root.unit
                            color: stepRow.stateKey === "warning" || stepRow.stateKey === "failed" ? stepRow.stateColor
                                                                                                 : Theme.bootTextSecondary
                            elide: Text.ElideRight
                            text: stepRow.detail
                        }
                    }
                }
            }
        }
    }

    // ---- 下部: 警告(角丸のカード) ----
    Rectangle {
        id: warning
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 28 * root.unit }
        width: Math.min(parent.width - 2 * 28 * root.unit, 1160 * root.unit)
        height: warningRow.implicitHeight + 2 * 20 * root.unit
        radius: Theme.radius + 6
        color: Theme.mix(Theme.bootPanel, Theme.bootWarn, 0.12)
        border.width: 2
        border.color: Theme.bootWarn
        opacity: root.fixedOpacity
        Behavior on opacity { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }

        Row {
            id: warningRow
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                      leftMargin: 24 * root.unit; rightMargin: 24 * root.unit }
            spacing: 22 * root.unit

            // 警告色の丸に警告マーク
            Rectangle {
                id: warningBadge
                anchors.verticalCenter: parent.verticalCenter
                width: 76 * root.unit; height: width; radius: width / 2
                color: Theme.bootWarn
                MaterialIcon {
                    anchors.centerIn: parent
                    name: "warning"
                    size: Math.round(parent.width * 0.6)
                    color: Theme.bootTextOnAccent
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - warningBadge.width - parent.spacing
                spacing: 4 * root.unit
                Text {
                    font.family: Theme.fontFamily
                    font.pixelSize: 26 * root.unit
                    font.bold: true
                    font.letterSpacing: 2 * root.unit
                    color: Theme.bootWarn
                    text: "警告"
                }
                Text {
                    width: parent.width
                    font.family: Theme.fontFamily
                    font.pixelSize: 34 * root.unit
                    font.bold: true
                    color: Theme.bootTextPrimary
                    text: "必ず実際の交通規制(信号・標識・速度制限など)に従って走行してください。"
                    // 1 行に収める。収まらない幅では、収まる最大の大きさまで文字を縮める
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 12
                }
            }
        }
    }

    // スキップ(ActionButton は昼夜テーマに連動するため、起動画面の固定配色で作る)
    Rectangle {
        id: skipButton
        anchors { right: parent.right; top: parent.top; rightMargin: Theme.margin * 1.5; topMargin: Theme.margin * 1.5 }
        visible: boot.active && !root.exportMode
        opacity: root.liveOpacity
        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
        implicitWidth: skipLabel.implicitWidth + 40
        implicitHeight: 52
        width: implicitWidth
        height: implicitHeight
        radius: Theme.radius
        color: skipMouse.pressed ? Theme.bootAccent : Theme.bootPanel
        border.color: Theme.bootPanelBorder
        border.width: 1
        Text {
            id: skipLabel
            anchors.centerIn: parent
            font.family: Theme.fontFamily
            font.pixelSize: 22
            color: Theme.bootTextPrimary
            text: "スキップ"
        }
        MouseArea { id: skipMouse; anchors.fill: parent; onClicked: boot.skip() }
    }

    // ---- 注意事項(読み込みが終わったら、起動画面の上に出す) ----
    Rectangle {
        id: noticeLayer
        anchors.fill: parent
        z: 100
        color: Theme.bootBackground
        // 一度出したら出したままにする(閉じるときは起動画面ごとフェードアウトするので、下の起動画面を見せない)
        opacity: (root.noticeShowing || root.noticeDone) ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

        // 背景: 起動画面と同じ、上からアクセント色がうっすら差すグラデーション
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.mix(Theme.bootBackground, Theme.bootAccent, 0.10) }
                GradientStop { position: 0.6; color: Theme.bootBackground }
            }
        }

        // 入りきらない画面では、全体を少し縮める
        Column {
            id: noticeBlock
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property real room: parent.height - Theme.margin * 2
            scale: Math.min(1, room / Math.max(1, height))
            transformOrigin: Item.Top
            y: Math.max(Theme.margin, (parent.height - height * scale) / 2)
            width: Math.min(parent.width - Theme.margin * 4, 1040 * root.unit)
            spacing: 22 * root.unit

            // 見出し
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 20 * root.unit
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 64 * root.unit; height: width; radius: width / 2
                    color: Theme.bootWarn
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "warning"
                        size: Math.round(parent.width * 0.6)
                        color: Theme.bootTextOnAccent
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: 44 * root.unit
                    font.bold: true
                    color: Theme.bootTextPrimary
                    text: "ご利用にあたっての注意事項"
                }
            }

            // 本文のカード
            Rectangle {
                width: parent.width
                height: noticeList.implicitHeight + 2 * 24 * root.unit
                radius: Theme.radius + 6
                color: Theme.mix(Theme.bootPanel, Theme.bootWarn, 0.12)
                border.width: 2
                border.color: Theme.bootWarn

                Column {
                    id: noticeList
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: 28 * root.unit; rightMargin: 28 * root.unit }
                    spacing: 18 * root.unit
                    Repeater {
                        model: root.notices
                        Row {
                            id: noticeRow
                            required property var modelData
                            width: noticeList.width
                            spacing: 18 * root.unit
                            MaterialIcon {
                                id: noticeIcon
                                anchors.verticalCenter: parent.verticalCenter
                                size: 36 * root.unit
                                color: Theme.bootWarn
                                name: noticeRow.modelData.icon
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - noticeIcon.width - parent.spacing
                                font.family: Theme.fontFamily
                                font.pixelSize: 26 * root.unit
                                color: Theme.bootTextPrimary
                                wrapMode: Text.WordWrap
                                text: noticeRow.modelData.text
                            }
                        }
                    }
                }
            }

            // OK ボタンと、メイン画面へ移るまでの残り時間
            Rectangle {
                id: okButton
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(360 * root.unit, okLabel.implicitWidth + 80 * root.unit)
                height: 72 * root.unit
                radius: Theme.radius + 6
                color: okMouse.pressed ? Theme.mix(Theme.bootAccent, "#000000", 0.2) : Theme.bootAccent
                Text {
                    id: okLabel
                    anchors.centerIn: parent
                    font.family: Theme.fontFamily
                    font.pixelSize: 30 * root.unit
                    font.bold: true
                    color: Theme.bootTextOnAccent
                    text: "確認してメイン画面へ"
                }
                MouseArea { id: okMouse; anchors.fill: parent; onClicked: root.dismissNotice() }
            }
            Rectangle {
                id: noticeTrack
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, 520 * root.unit)
                height: 6 * root.unit
                radius: height / 2
                color: Theme.bootPanelBorder
                Rectangle {
                    // 残り時間(だんだん短くなる)
                    width: parent.width * root.noticeRemaining
                    height: parent.height
                    radius: height / 2
                    color: Theme.bootAccent
                }
            }
        }
    }
    // 注意事項を出している間だけ数える(OK で先に進めたときは止まる)
    property real noticeRemaining: 1
    NumberAnimation on noticeRemaining {
        running: root.noticeShowing
        from: 1; to: 0
        duration: root.noticeHoldMs
        onFinished: root.dismissNotice()
    }
}
