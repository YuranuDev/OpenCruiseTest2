// バックカメラの画面。バック信号が入ると(reverseCamera.shown)、ほかの画面の上に全面で出す。
//  - 映像(ReverseCameraVideo)の上に、距離の目安のガイド線(設定でオン/オフ)と、「バック」の表示を重ねる
//  - 右上の「閉じる」で、今のバックの間だけ閉じられる(次にバックへ入れたらまた出る)。設定画面の「映像を確認」もこれで閉じる
//  - カメラが無い・準備中・エラーのときは、その旨を真ん中に出す
//  - 出すときはすぐ(短いフェード)、戻すときはゆっくり消す。出ている間は下の画面へタッチを通さない
import QtQuick

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
        opacity: reverseCamera.cameraState === "active" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    // ---- ガイド線(距離の目安。手前から 赤・黄・緑) ----
    Canvas {
        id: guides
        anchors.fill: parent
        visible: reverseCamera.guides && reverseCamera.cameraState === "active"
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
        visible: reverseCamera.cameraState !== "active"
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

    // ---- 左上: バックの表示(目視の注意) ----
    Row {
        anchors { left: parent.left; top: parent.top; margins: Theme.margin * 1.5 }
        spacing: 12 * root.unit
        Rectangle {
            height: Math.round(52 * root.unit)
            width: height
            radius: height / 2
            color: reverseCamera.previewing && !reverseCamera.reverse ? "#555555" : "#ff3b30"
            Text {
                anchors.centerIn: parent
                font.family: Theme.numberFontFamily
                font.pixelSize: Math.round(parent.height * 0.55)
                font.bold: true
                color: "#ffffff"
                text: "R"
            }
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            height: Math.round(40 * root.unit)
            width: noteText.implicitWidth + 28 * root.unit
            radius: height / 2
            color: Qt.rgba(0, 0, 0, 0.55)
            Text {
                id: noteText
                anchors.centerIn: parent
                font.family: Theme.fontFamily
                font.pixelSize: Math.round(19 * root.unit)
                color: "#ffffff"
                text: reverseCamera.previewing && !reverseCamera.reverse ? "映像の確認中" : "周囲の安全を直接確認してください"
            }
        }
    }

    // ---- 右上: 閉じる ----
    Rectangle {
        anchors { right: parent.right; top: parent.top; margins: Theme.margin * 1.5 }
        height: Math.round(52 * root.unit)
        width: closeRow.implicitWidth + 32 * root.unit
        radius: height / 2
        color: closeMouse.pressed ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(0, 0, 0, 0.55)
        border.width: 1.5
        border.color: Qt.rgba(1, 1, 1, 0.5)
        Row {
            id: closeRow
            anchors.centerIn: parent
            spacing: 6 * root.unit
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "close"
                size: Math.round(28 * root.unit)
                color: "#ffffff"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.fontFamily
                font.pixelSize: Math.round(20 * root.unit)
                font.bold: true
                color: "#ffffff"
                text: "閉じる"
            }
        }
        MouseArea { id: closeMouse; anchors.fill: parent; anchors.margins: -8; onClicked: reverseCamera.dismiss() }
    }
}
