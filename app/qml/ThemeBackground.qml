// アプリ全体の背景(Main.qml の画面の回転の中、いちばん奥に置く)。背景色の上に、模様か画像を重ねる。
//  kind(themeSettings.background):
//    "auto"   … テーマに合わせる(シンプルは無地、クラシックはカーボン)
//    "none"   … 無地
//    "carbon" … カーボン(細かい綾織り) / "brushed" … ヘアライン(横向きの細い筋) /
//    "dots"   … パンチング(小さな穴) / "stripes" … ストライプ(斜めの細い線)
//    "image"  … 画像(themeSettings.backgroundImageUrl。並べる / 画面を埋める / 引き伸ばす)
//  濃さは themeSettings.backgroundOpacity(0〜100 %)。
// 模様は Canvas に 1 回だけ描く(大きさ・テーマ・昼夜・模様が変わったときだけ描き直す。動かさないので軽い)。
import QtQuick

Rectangle {
    id: root
    color: Theme.background

    readonly property string kind: {
        const k = typeof themeSettings !== "undefined" ? themeSettings.background : "auto"
        if (k === "auto") return Theme.classic ? "carbon" : "none"
        return k
    }
    readonly property real strength: typeof themeSettings !== "undefined" ? themeSettings.backgroundOpacity / 100 : 0.6
    readonly property string imageUrl: typeof themeSettings !== "undefined" ? themeSettings.backgroundImageUrl : ""
    readonly property int fit: typeof themeSettings !== "undefined" ? themeSettings.backgroundFit : 1

    // ---- 模様 ----
    Canvas {
        id: pattern
        anchors.fill: parent
        visible: root.kind !== "none" && root.kind !== "image"
        opacity: root.strength
        renderStrategy: Canvas.Cooperative
        renderTarget: Canvas.Image
        readonly property string key: [width, height, root.kind, Theme.nightLevel, Theme.style].join("|")
        onKeyChanged: if (visible) requestPaint()
        onVisibleChanged: if (visible) requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const w = width, h = height
            if (w <= 0 || h <= 0) return
            // 夜は明るい線で、昼は暗い線で模様を描く(背景色より少しだけ違う色)
            const night = Theme.nightLevel > 0.5
            const light = (a) => night ? Qt.rgba(1, 1, 1, a) : Qt.rgba(1, 1, 1, a * 2.2)
            const dark = (a) => night ? Qt.rgba(0, 0, 0, a * 2.0) : Qt.rgba(0, 0, 0, a)
            // 繰り返しの模様は、1 枚(タイル)だけ描いて、それを並べる(全部を 1 つずつ描くより速い)
            const tiled = (size, drawTile) => {
                drawTile(Math.min(size, w), Math.min(size, h))
                const tile = ctx.getImageData(0, 0, size, size)
                ctx.fillStyle = ctx.createPattern(tile, "repeat")
                ctx.fillRect(0, 0, w, h)
            }
            switch (root.kind) {
            case "carbon": {
                // 綾織り: 4px のマスを 2 本ずつ、縦横に互い違い(16px で 1 周期)
                const c = 4
                tiled(16, (tw, th) => {
                for (let y = 0; y < th; y += c) {
                    for (let x = 0; x < tw; x += c) {
                        const ix = Math.floor(x / c), iy = Math.floor(y / c)
                        const horiz = ((ix >> 1) + (iy >> 1)) % 2 === 0
                        ctx.fillStyle = light(horiz ? 0.075 : 0.025)
                        ctx.fillRect(x, y, c, c)
                        ctx.fillStyle = dark(0.12)
                        if (horiz) ctx.fillRect(x, y + c - 1, c, 1)
                        else ctx.fillRect(x + c - 1, y, 1, c)
                    }
                }
                })
                break
            }
            case "brushed": {
                // ヘアライン: 横向きの細い筋。明るさを少しずつ変えて、金属をこすった跡のように
                let seed = 7
                const rnd = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647 }
                for (let y = 0; y < h; ++y) {
                    const v = rnd()
                    ctx.fillStyle = v > 0.5 ? light(0.02 + (v - 0.5) * 0.12) : dark(0.02 + (0.5 - v) * 0.1)
                    ctx.fillRect(0, y, w, 1)
                }
                break
            }
            case "dots": {
                // パンチング: 互い違いに並んだ小さな穴(穴の下側に明るい縁)。10px 間隔、2 段で 1 周期(20px)
                tiled(20, (tw, th) => {
                    for (const [x, y] of [[5, 5], [15, 15]]) {
                        ctx.fillStyle = dark(0.22)
                        ctx.beginPath(); ctx.arc(x, y, 1.8, 0, Math.PI * 2); ctx.fill()
                        ctx.fillStyle = light(0.06)
                        ctx.fillRect(x - 1, y + 1.6, 2, 1)
                    }
                })
                break
            }
            case "stripes": {
                // ストライプ: 斜め 45° の細い線
                ctx.lineWidth = 1
                ctx.strokeStyle = light(0.06)
                const step = 12
                ctx.beginPath()
                for (let d = -h; d < w; d += step) {
                    ctx.moveTo(d, h); ctx.lineTo(d + h, 0)
                }
                ctx.stroke()
                break
            }
            }
        }
    }

    // ---- 画像 ----
    Image {
        anchors.fill: parent
        visible: root.kind === "image" && root.imageUrl !== ""
        source: visible ? root.imageUrl : ""
        opacity: root.strength
        asynchronous: true
        cache: false
        fillMode: root.fit === 0 ? Image.Tile : (root.fit === 2 ? Image.Stretch : Image.PreserveAspectCrop)
        horizontalAlignment: Image.AlignHCenter
        verticalAlignment: Image.AlignVCenter
    }
}
