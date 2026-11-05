// バックカメラの画面。バック信号が入ると(reverseCamera.shown)、ほかの画面の上に全面で出す。
//  - 映像(ReverseCameraVideo)の上に、距離の目安のガイド線(設定でオン/オフ)を重ねる
//  - 文字は 2 つだけ: 左上の「R」の札と「リアカメラ」、上の中央の警告マークつき「周囲の安全を直接確認してください」
//  - バック中は閉じるボタンを出さない(バック信号が切れたら戻る)。設定画面の「映像を確認」のときだけ、右上に「確認を終わる」を出す
//  - カメラが無い・準備中・エラーのときは、その旨を真ん中に出す
//  - 出すときはすぐ(短いフェード)、戻すときはゆっくり消す。出ている間は下の画面へタッチを通さない
//  - カメラの映像が実際に届き始める(reverseCamera.receiving)までは真っ黒にしておき、届いたら映像と表示をまとめて出す
//    (カメラが見つからない・エラーのときだけ、真ん中にその旨を出す)
import QtQuick
import OpenCruise

Item {
    id: root
    readonly property real unit: Theme.uiScale
    readonly property bool shown: reverseCamera.shown

    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: root.shown ? 120 : 260; easing.type: Easing.OutQuad } }

    Rectangle { anchors.fill: parent; color: "black" }
    MouseArea { anchors.fill: parent }   // 下の画面へタッチを通さない

    // 映像(カメラを動かしている間だけ、中身が出る)
    ReverseCameraVideo {
        anchors.fill: parent
        mirror: reverseCamera.mirror
        fill: reverseCamera.fill
        opacity: reverseCamera.receiving ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    // 映像の上の表示(ガイド線・左上・上の警告)。映像が届くまでは出さない(画面は黒のまま)
    readonly property real chromeOpacity: reverseCamera.receiving ? 1 : 0

    // ---- ガイド線(距離の目安。手前から 赤・黄・緑) ----
    Canvas {
        id: guides
        anchors.fill: parent
        visible: reverseCamera.guides && reverseCamera.receiving
        renderStrategy: Canvas.Cooperative
        readonly property string key: [width, height, visible].join("|")
        onKeyChanged: if (visible) requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const w = width, h = height
            if (w <= 0 || h <= 0) return
            // 左右の線(下の手前から奥へすぼまる)と、横の目盛り(距離の目安)
            const yNear = 0.97, yFar = 0.42
            const xAt = (y, side) => {   // 線の x(side: -1 = 左 / 1 = 右)
                const t = (yNear - y) / (yNear - yFar)
                const half = 0.33 - 0.17 * t
                return w * (0.5 + side * half)
            }
            const lw = Math.max(3, h * 0.008)
            const stroke = (pts, color) => {
                // 暗い縁を先に描いて、明るい映像の上でも見えるように
                for (const [c, k] of [["rgba(0,0,0,0.55)", 2.2], [color, 1]]) {
                    ctx.strokeStyle = c
                    ctx.lineWidth = lw * k
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    ctx.beginPath()
                    ctx.moveTo(pts[0][0], pts[0][1])
                    for (let i = 1; i < pts.length; ++i) ctx.lineTo(pts[i][0], pts[i][1])
                    ctx.stroke()
                }
            }
            const bands = [{ y0: yNear, y1: 0.8, color: "#ff3b30" },
                           { y0: 0.8, y1: 0.6, color: "#ffcc00" },
                           { y0: 0.6, y1: yFar, color: "#34c759" }]
            for (const b of bands) {
                for (const side of [-1, 1]) stroke([[xAt(b.y0, side), h * b.y0], [xAt(b.y1, side), h * b.y1]], b.color)
                // 奥側の端に、内向きの短い横線
                const y = h * b.y1, len = w * 0.05
                stroke([[xAt(b.y1, -1), y], [xAt(b.y1, -1) + len, y]], b.color)
                stroke([[xAt(b.y1, 1), y], [xAt(b.y1, 1) - len, y]], b.color)
            }
        }
    }

    // ---- カメラが映っていないとき ----
    Column {
        anchors.centerIn: parent
        width: parent.width * 0.8
        spacing: 14 * root.unit
        // 準備中は何も出さない(黒のまま)。見つからない・エラーのときだけ出す
        visible: !reverseCamera.receiving && (reverseCamera.cameraState === "none" || reverseCamera.cameraState === "error"
                                              || reverseCamera.missingDevice !== "")
        MaterialIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: reverseCamera.cameraState === "starting" ? "videocam" : "videocam_off"
            size: Math.round(72 * root.unit)
            color: "#ffffff"
            opacity: 0.85
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(30 * root.unit)
            font.bold: true
            color: "#ffffff"
            text: reverseCamera.cameraState === "starting" ? "カメラを準備中…"
                : reverseCamera.cameraState === "error" ? "カメラの映像を受け取れません"
                : reverseCamera.missingDevice !== "" ? "選んだカメラが見つかりません"
                : reverseCamera.cameraState === "none" ? "カメラが見つかりません"
                : "カメラを準備中…"
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(20 * root.unit)
            color: "#d0d0d0"
            visible: text !== ""
            text: reverseCamera.cameraState === "error" ? reverseCamera.cameraError
                : reverseCamera.missingDevice !== "" ? reverseCamera.missingDevice + "(設定 > カメラ で選び直せます)"
                : reverseCamera.cameraState === "none" ? "キャプチャーボード・USB カメラをつないでください" : ""
        }
    }

    // ---- 上の帯(映像の上で文字が読めるよう、上から下へ薄くなる暗い影) ----
    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        opacity: root.chromeOpacity
        Behavior on opacity { NumberAnimation { duration: 150 } }
        height: Math.round(130 * root.unit)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.6) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
        }
    }

    readonly property bool previewOnly: reverseCamera.previewing && !reverseCamera.reverse
    readonly property real barH: Math.round(60 * root.unit)

    // ---- 上の中央: 周囲の安全の確認(警告マークつき) ----
    Rectangle {
        id: safety
        opacity: root.chromeOpacity
        Behavior on opacity { NumberAnimation { duration: 150 } }
        // 左上の表示・右上のボタンと重ならない範囲で、なるべく画面の中央に置く。
        // 入りきらない(狭い画面)ときは、左上の表示の下の段に、画面の中央にそろえて置く
        readonly property real leftLimit: gearBadge.x + gearBadge.width + Theme.margin
        readonly property real rightLimit: endPreview.visible ? endPreview.x - Theme.margin : parent.width - Theme.margin * 1.5
        readonly property real wantW: safetyRow.implicitWidth + Math.round(40 * root.unit)
        readonly property bool fitsTop: wantW <= rightLimit - leftLimit
        y: fitsTop ? Theme.margin * 1.5 : gearBadge.y + gearBadge.height + Theme.margin * 0.6
        x: fitsTop ? Math.max(leftLimit, Math.min(rightLimit - width, (parent.width - width) / 2)) : (parent.width - width) / 2
        height: root.barH
        width: Math.min(wantW, parent.width - Theme.margin * 3)
        radius: height / 2
        color: Qt.rgba(0.07, 0.08, 0.1, 0.78)
        border.width: 1.5
        border.color: Qt.rgba(1.0, 0.8, 0.0, 0.7)
        clip: true
        Row {
            id: safetyRow
            anchors.centerIn: parent
            spacing: Math.round(10 * root.unit)
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "warning"
                size: Math.round(32 * root.unit)
                color: "#ffcc00"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.fontFamily
                font.pixelSize: Math.round(22 * root.unit)
                font.bold: true
                color: "#ffffff"
                text: "周囲の安全を直接確認してください"
            }
        }
    }

    // ---- 右上: 映像の確認(設定画面から)のときだけ、終わるボタン ----
    Rectangle {
        id: endPreview
        visible: reverseCamera.previewing
        anchors { right: parent.right; top: parent.top; margins: Theme.margin * 1.5 }
        height: root.barH
        width: endRow.implicitWidth + 32 * root.unit
        radius: height / 2
        color: endMouse.pressed ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(0.07, 0.08, 0.1, 0.78)
        border.width: 1.5
        border.color: Qt.rgba(1, 1, 1, 0.4)
        Row {
            id: endRow
            anchors.centerIn: parent
            spacing: 6 * root.unit
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "check"
                size: Math.round(26 * root.unit)
                color: "#ffffff"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.fontFamily
                font.pixelSize: Math.round(20 * root.unit)
                font.bold: true
                color: "#ffffff"
                text: "確認を終わる"
            }
        }
        MouseArea { id: endMouse; anchors.fill: parent; anchors.margins: -8; onClicked: reverseCamera.setPreview(false) }
    }
}
