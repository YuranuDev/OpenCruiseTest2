// 終了の画面。終了の要求(ACC OFF。今は Ctrl+Shift+P)を受けたら、ほかの画面の上に全面で出す
// (shutdownManager.state が "idle" 以外の間)。
//  - 起動画面(SplashScreen)と同じ、完全な黒の背景の中央に YuranuDev のロゴだけを出す(同じ位置・同じ大きさ)
//  - その裏で終了処理(設定の保存・Android Auto の切断・ドアロックの解除など)を順に行う。今の処理の内容だけを、画面の下に
//    小さく控えめに出す(起動画面と同じ。結果の詳細はログに残る)
//  - 終了処理が全部済んだら(state が "ready")、ロゴと下の文字をゆっくりフェードアウトして真っ黒にし、それを描き終えてから
//    finish()(電源を切る / アプリを終了する)を呼ぶ
//  - 電源を切れなかったとき("failed")だけ、真ん中にその旨を出す(しばらくしてアプリが終了する)
// タッチは下の画面へ通さない。
import QtQuick
import OpenCruise

Rectangle {
    id: root
    color: Theme.bootBackground
    readonly property real unit: Math.max(0.6, Math.min(width / 1280, height / 720))
    readonly property string state_: shutdownManager.state
    readonly property bool active: state_ !== "idle"

    opacity: active ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }

    MouseArea { anchors.fill: parent; enabled: root.visible }   // 下の画面へタッチを通さない

    // ロゴと下の文字(終了処理が済んだら、まとめてフェードアウトする)
    Item {
        id: content
        anchors.fill: parent
        visible: root.state_ !== "failed"

        // ---- 中央: ロゴ(起動画面と同じ。SplashScreen.qml と合わせること) ----
        Image {
            id: logo
            source: "../../resources/images/YuranuDev_Brush_Script_Logo.png"
            sourceClipRect: Qt.rect(132, 101, 1996, 577)   // 元の画像(2172 x 724)のうち、文字のある範囲(+ 少し余白)
            readonly property real aspect: 1996 / 577
            width: Math.round(Math.min(root.width * 0.5, root.height * 0.4 * aspect))
            height: Math.round(width / aspect)
            anchors.centerIn: parent
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }

        // ---- 下: 今の処理の内容(控えめに。起動画面と同じ位置・大きさ) ----
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Math.round(28 * root.unit) }
            width: parent.width - Theme.margin * 4
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(15 * root.unit)
            color: Theme.bootTextSecondary
            opacity: 0.7
            text: root.currentText
        }
    }

    // 今の処理の内容: 実行中の処理の名前 +「中…」(名前は「設定の保存」のような形で登録する)。済んだら電源を切る旨。
    // 処理と処理の間(一瞬どれも実行中でない)は、直前の文字のままにする(ちらつかないように)
    property string runningText: ""
    Connections {
        target: shutdownManager
        function onTasksChanged() {
            const list = shutdownManager.tasks
            for (let i = 0; i < list.length; ++i)
                if (list[i].status === "running") { root.runningText = list[i].label + "中…"; return }
        }
    }
    readonly property string currentText: {
        if (state_ === "ready" || state_ === "stopping")
            return shutdownManager.afterAction === 0 ? "電源を切っています…" : "終了しています…"
        return runningText !== "" ? runningText : "終了の準備をしています…"
    }

    // ---- 終了処理が済んだら: ロゴをフェードアウトし、真っ黒を描き終えてから電源を切る ----
    property bool finishArmed: false
    SequentialAnimation {
        id: fadeOut
        NumberAnimation { target: content; property: "opacity"; to: 0; duration: 1200; easing.type: Easing.InOutQuad }
        ScriptAction { script: root.finishArmed = true }
    }
    Connections {
        target: shutdownManager
        function onStateChanged() {
            if (shutdownManager.state === "ready") fadeOut.start()
        }
    }
    Connections {
        target: root.Window.window
        enabled: root.finishArmed
        function onFrameSwapped() {
            root.finishArmed = false
            shutdownManager.finish()
        }
    }
    // 画面が変わらず描き直しが起きないときのため、1 枚描かせる
    onFinishArmedChanged: if (finishArmed && root.Window.window) root.Window.window.update()

    // ---- 電源を切れなかったとき ----
    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80 * root.unit, 760 * root.unit)
        spacing: 16 * root.unit
        visible: root.state_ === "failed"
        MaterialIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "error"
            size: Math.round(72 * root.unit)
            color: "#ff6b5e"
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(32 * root.unit)
            font.bold: true
            color: "#ffffff"
            text: "電源を切れませんでした"
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(20 * root.unit)
            color: "#b8bcc4"
            text: shutdownManager.errorText + "\nアプリを終了します"
        }
    }
}
