// 飾りの画像(キャラなど)を置き直す操作の層。初期画面の編集モードで「画像」を選んでいる間だけ出す(画面全体に重ねる)。
//  - 置いた画像に枠を出す。タップで選択、ドラッグで移動(選んでいなくても、つかんだものが選ばれて動く)
//  - 選んだ画像の右下の丸いつまみ、または 2 本指でつまんで大きさを変える(縦横比はそのまま)
//  - 動かしているとき、画面の中央・端にそろうと吸い付き、そろった線を出す
//  - 選んだ画像は、ウィジェットに隠れている所も薄く出す(どこまで広がっているか分かるように)
//  - 何も無い所をタップで選択を解除。左右にスワイプでページを移る
//  - 手前 > パネル > 奥 の順に、先につかめる(見えている重なり順のとおり)
// 濃さ・反転・重ね方・複製・削除は、下の DecorationPanel で行う。
import QtQuick
import OpenCruise

Item {
    id: root
    property Item store: null
    property Item pages: null
    // つまみを出してよい下端(下の操作パネルに隠れないように。LauncherScreen が渡す)
    property real handleBottom: height
    // 目印(左上の「奥」など)を出してよい上端(上の編集用のバーに隠れないように)
    property real tagTop: 0
    readonly property real unit: Theme.uiScale
    // 吸い付き(中央・端にそろえる)。そろった線の位置(px。-1 なら出さない)
    readonly property real snapDist: 12 * unit
    property real guideX: -1
    property real guideY: -1
    function snap1(pos, size, total) {
        // 左端 / 中央 / 右端の順に、近ければそろえる。{ pos, guide }
        if (Math.abs(pos) < snapDist) return { pos: 0, guide: 0 }
        if (Math.abs(pos + size / 2 - total / 2) < snapDist) return { pos: total / 2 - size / 2, guide: total / 2 }
        if (Math.abs(pos + size - total) < snapDist) return { pos: total - size, guide: total }
        return { pos: pos, guide: -1 }
    }
    readonly property var layerNames: ({ back: "奥", panel: "パネル", front: "手前" })

    // 何も無い所: タップで選択解除、左右スワイプでページ切り替え
    MouseArea {
        anchors.fill: parent
        property real startX: 0
        property real startY: 0
        onPressed: (m) => { startX = m.x; startY = m.y }
        onReleased: (m) => {
            const dx = m.x - startX, dy = m.y - startY
            if (root.pages && Math.abs(dx) > Math.max(80, width * 0.08) && Math.abs(dx) > Math.abs(dy) * 1.5)
                root.pages.setCurrent(root.pages.current + (dx < 0 ? 1 : -1))
            else if (Math.hypot(dx, dy) < 20 && root.store)
                root.store.selectedId = ""
        }
    }

    Repeater {
        model: root.store ? root.store.model : null
        Item {
            id: frame
            required property int index
            required property string did
            required property real rx
            required property real ry
            required property real rw
            required property real ar
            required property string zone
            required property string file
            required property bool flip
            readonly property bool selected: root.store && root.store.selectedId === did
            x: root.width * rx
            y: root.height * ry
            width: root.width * rw
            height: width * ar
            // 見えている重なり順のとおりにつかめるよう、手前の画像を上にする。選んでいるものはさらに上
            z: (selected ? 3000 : 0) + (zone === "front" ? 2000 : zone === "panel" ? 1000 : 0) + index

            // 選んだ画像の全体(ウィジェットに隠れている所も薄く)
            Image {
                anchors.fill: parent
                visible: frame.selected && frame.zone !== "front"
                source: visible ? themeSettings.decorationUrl(frame.file) : ""
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                sourceSize.width: Math.min(2048, Math.ceil(frame.width * 1.25 / 64) * 64)
                opacity: 0.3
                transform: Scale { origin.x: frame.width / 2; xScale: frame.flip ? -1 : 1 }
            }

            // 2 本指でつまんで大きさを変える(中心はそのまま)
            PinchHandler {
                target: null
                property real startW: 0
                property real cx: 0
                property real cy: 0
                onActiveChanged: {
                    if (active) {
                        root.store.selectedId = frame.did
                        startW = frame.rw
                        cx = frame.rx + frame.rw / 2
                        cy = frame.ry + frame.width * frame.ar / 2 / root.height
                    } else {
                        root.store.save()
                    }
                }
                onActiveScaleChanged: if (active) root.store.scaleAround(frame.did, startW * activeScale, cx, cy)
            }

            // 枠(選んでいるものは太くアクセント色、ほかは細く)
            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                color: frame.selected ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.08) : "transparent"
                radius: 4
                border.width: frame.selected ? 3 : 1.5
                border.color: frame.selected ? Theme.accent : Qt.rgba(Theme.textPrimary.r, Theme.textPrimary.g, Theme.textPrimary.b, 0.45)
            }
            // 層の目印(左上): 奥 / パネル / 手前
            Rectangle {
                visible: frame.selected || frame.width > 90 * root.unit
                x: Math.max(4 * root.unit, -frame.x + 4 * root.unit)
                y: Math.max(4 * root.unit, root.tagTop - frame.y + 4 * root.unit)
                height: 26 * root.unit
                width: tag.implicitWidth + 16 * root.unit
                radius: height / 2
                color: frame.selected ? Theme.accentFill : Theme.mix(Theme.panel, Theme.background, 0.2)
                opacity: 0.92
                Text {
                    id: tag
                    anchors.centerIn: parent
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.round(15 * root.unit)
                    font.bold: true
                    color: frame.selected ? Theme.textOnAccent : Theme.textSecondary
                    text: root.layerNames[frame.zone] || ""
                }
            }

            // 移動
            MouseArea {
                anchors.fill: parent
                preventStealing: true
                property real startX: 0
                property real startY: 0
                property real baseX: 0
                property real baseY: 0
                property bool moving: false
                onPressed: (m) => {
                    const p = mapToItem(root, m.x, m.y)
                    startX = p.x; startY = p.y
                    baseX = frame.rx; baseY = frame.ry
                    moving = false
                }
                onPositionChanged: (m) => {
                    const p = mapToItem(root, m.x, m.y)
                    if (!moving && Math.hypot(p.x - startX, p.y - startY) > 10 * root.unit) {
                        moving = true
                        root.store.selectedId = frame.did
                    }
                    if (!moving) return
                    // 画面の中央・端に近ければ吸い付ける
                    const sx = root.snap1(baseX * root.width + p.x - startX, frame.width, root.width)
                    const sy = root.snap1(baseY * root.height + p.y - startY, frame.height, root.height)
                    root.guideX = sx.guide
                    root.guideY = sy.guide
                    root.store.setGeometry(frame.did, sx.pos / root.width, sy.pos / root.height, frame.rw)
                }
                function finish() {
                    if (moving) root.store.save()
                    moving = false
                    root.guideX = -1
                    root.guideY = -1
                }
                onReleased: {
                    if (!moving) root.store.selectedId = frame.selected ? "" : frame.did
                    finish()
                }
                onCanceled: finish()
            }

            // 大きさのつまみ(右下。縦横比はそのまま)
            Rectangle {
                id: handle
                visible: frame.selected
                readonly property real s: Math.round(48 * root.unit)
                width: s
                height: s
                radius: s / 2
                // ふつうは右下の角。画面の外や下の操作パネルに隠れるときは、見える所へ寄せる
                x: Math.max(0, Math.min(parent.width - s / 2, root.width - frame.x - s - 4))
                y: Math.max(0, Math.min(parent.height - s / 2, root.handleBottom - frame.y - s - 4))
                color: Theme.mix(Theme.panel, Theme.accent, resizeMouse.pressed ? 0.5 : 0.2)
                border.width: 2
                border.color: Theme.accent
                MaterialIcon {
                    anchors.centerIn: parent
                    name: "open_in_full"
                    size: Math.round(parent.width * 0.55)
                    color: Theme.accent
                    rotation: 90
                }
                MouseArea {
                    id: resizeMouse
                    anchors.fill: parent
                    anchors.margins: -10 * root.unit
                    preventStealing: true
                    property point start
                    property real startW: 0
                    onPressed: (m) => { start = mapToItem(root, m.x, m.y); startW = frame.rw }
                    onPositionChanged: (m) => {
                        if (!pressed) return
                        const p = mapToItem(root, m.x, m.y)
                        // 押した所からの動きで決める(横・縦のうち、大きく引っぱったほうに合わせる。左上は動かさない)
                        const byX = (p.x - start.x) / root.width
                        const byY = (p.y - start.y) / (root.width * frame.ar)
                        const w = Math.max(40 * root.unit / root.width, startW + (Math.abs(byX) > Math.abs(byY) ? byX : byY))
                        root.store.setGeometry(frame.did, frame.rx, frame.ry, w)
                    }
                    onReleased: root.store.save()
                    onCanceled: root.store.save()
                }
            }
        }
    }

    // そろった線(吸い付いたとき)
    Rectangle {
        visible: root.guideX >= 0
        x: Math.min(root.width - width, Math.max(0, root.guideX - width / 2))
        width: 2
        height: root.height
        color: Theme.accent
        z: 5000
    }
    Rectangle {
        visible: root.guideY >= 0
        y: Math.min(root.height - height, Math.max(0, root.guideY - height / 2))
        height: 2
        width: root.width
        color: Theme.accent
        z: 5000
    }

    // 1 つも無いときの案内
    Column {
        anchors.centerIn: parent
        spacing: 12 * root.unit
        visible: root.store && root.store.count === 0
        MaterialIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "add_photo_alternate"
            size: 56 * root.unit
            color: Theme.textSecondary
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            font.family: Theme.fontFamily
            font.pixelSize: 22 * root.unit
            color: Theme.textSecondary
            text: "このページには画像がありません。上の「画像を追加」から置けます"
        }
    }
}
