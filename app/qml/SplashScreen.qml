// 起動画面。完全な黒の背景に、ロゴ(YuranuDev)を画面の中央に出す(ロゴ以外は何も出さない)。
//  - ロゴは縦横比を保ったまま、画面の大きさに合わせて大きさを決める(横は画面の半分まで、縦は画面の 4 割まで)
//  - Linux の起動画面(Plymouth)は、この画面を --export-splash で書き出した画像(同じ黒の背景と同じ位置のロゴ)を最初から出す。
//    アプリはそれを消さずに引き継ぎ(handoff)、同じ位置に同じロゴを最初から出すので、動かず途切れずに切り替わる。
//    Plymouth を経由しないとき(開発中の起動など)だけ、最初の 1 枚を描いてからロゴをゆっくりフェードインする
// BootManager(context property `boot`)の待ち(ESP32 などの応答待ち)は、これまでどおり C++ 側にある。ここは表示だけで、
// 待ちの状況は画面に出さない(各ステップの詳細はログに残る。問題があれば注意事項の画面に出す)。
// メイン画面ができて起動の待ちが終わったら(ready)、注意事項の画面に切り替える。一定時間(または OK)で注意事項が終わったら、
// 起動画面を閉じてメイン画面へ移り(canClose)、メイン画面の動き(ゲージ・点滅・警告など)を始める(boot.release)。
import QtQuick

Rectangle {
    id: root
    color: Theme.bootBackground

    readonly property real unit: Math.max(0.6, Math.min(width / 1280, height / 720))
    // ---- 読み込み後の注意事項 ----
    // Main.qml が ready を渡す。注意事項を出して、OK を押すか noticeHoldMs が過ぎたら noticeDone になり、
    // canClose で起動画面ごと閉じてメイン画面へ移る。--skip-boot / --open-settings(skipNotice)のときは出さない。
    property bool ready: false              // メイン画面ができて、起動の待ちが終わった
    property bool skipNotice: false
    property int noticeHoldMs: 8000          // 自動でメイン画面へ移るまでの時間(ms)。OK で先に進める
    property bool noticeDone: false
    readonly property bool noticeShowing: ready && !skipNotice && !noticeDone && !exportMode
    // 注意事項が終わった(出さない場合は待ちが終わった)ら、起動画面を閉じてメイン画面へ移る。同時に動きを始める合図(boot.release)を出す
    readonly property bool canClose: ready && (skipNotice || noticeDone) && !exportMode
    onCanCloseChanged: if (canClose) boot.release()
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

    // 画面が実際に 1 枚描かれてから、ロゴを出し始める(起動の重い処理の間にフェードが進んでしまい、
    // 途中から急に出たように見えることがないように)
    property bool revealed: false
    Connections {
        target: root.Window.window
        enabled: !root.revealed
        function onFrameSwapped() { root.revealed = true }
    }
    Timer { interval: 400; running: !root.revealed; onTriggered: root.revealed = true }   // 念のため(描画の合図が来ないとき)

    // Linux の起動画面(Plymouth)との引き継ぎ:
    //  - handoff: Plymouth から引き継いだ。Plymouth は、この画面と同じ画像(黒の背景 + 中央のロゴ)を出していたので、
    //    ロゴはフェードせずに最初から出す(途切れて見えない。そのあとも動かさない)
    //  - exportMode(--export-splash): Plymouth 用の画像を作る(ロゴを最初から出す)
    readonly property bool handoff: typeof splashHandoff !== "undefined" && splashHandoff === true
    readonly property bool exportMode: typeof splashExport !== "undefined" && splashExport === true
    readonly property real logoOpacity: (handoff || exportMode || revealed) ? 1 : 0
    // --export-splash で C++ が呼ぶ: 進行バー(溝)の位置と大きさ(この画面の座標)と色
    function bootImageGeometry() {
        // Plymouth が、パスワードの入力欄やメッセージをロゴの下に出すための位置(ロゴの下端)と、その文字の色
        const p = logo.mapToItem(root, 0, logo.height)
        return { logoBottom: p.y, backgroundColor: Theme.bootBackground.toString(), textColor: Theme.bootTextSecondary.toString() }
    }

    // ---- 中央: ロゴ ----
    // 背景は root の color(完全な黒)。ロゴの画像は周りに透明の余白があるので、文字のある範囲(sourceClipRect)だけを使い、
    // 見た目の中央が画面の中央に合うようにする。縦横比は保つ
    Image {
        id: logo
        source: "../images/YuranuDev_Brush_Script_Logo.png"
        sourceClipRect: Qt.rect(132, 101, 1996, 577)   // 元の画像(2172 x 724)のうち、文字のある範囲(+ 少し余白)
        readonly property real aspect: 1996 / 577
        width: Math.round(Math.min(root.width * 0.5, root.height * 0.4 * aspect))
        height: Math.round(width / aspect)
        anchors.centerIn: parent
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true            // 縮小して使うので、ぎざぎざにならないように
        asynchronous: false     // 最初の 1 枚から出せるように、描く前に読み込んでおく
        opacity: root.logoOpacity
        // 引き継ぎ・書き出しのときは最初から出す(変化しない)。そうでないときだけ、ゆっくり浮かび上がらせる
        Behavior on opacity { NumberAnimation { duration: 900; easing.type: Easing.InOutQuad } }
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

        // 背景は、起動画面と同じ完全な黒(noticeLayer の color)

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

            // 起動の待ちで確認できなかった項目があれば知らせる(起動画面の一覧は、この画面に切り替わると見えないため)
            Text {
                visible: boot.hasProblem
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.fontFamily
                font.pixelSize: 20 * root.unit
                color: Theme.bootWarn
                wrapMode: Text.WordWrap
                text: boot.summaryText
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
