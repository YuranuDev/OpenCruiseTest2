// グラフ(車載連携)。メーターと同じ計測値(config.metric。定義は WidgetRegistry.gaugeSpecs)の直近の変化を、
// 折れ線グラフで表示する。履歴は VehicleHistory(シングルトン)が持つので、置いた直後から過去の分も描ける。
//  - 上段: アイコン・名前(左)と今の値(右。警告値を超えていれば赤)
//  - 中段: グラフ。縦軸の目盛り(左)、警告線(赤い破線と、超えた側の薄い赤)、線の下の塗りつぶし
//  - 下段: 表示している時間の中の最大・最小・平均(高さに余裕があるとき)
// 設定: 単位 / 表示する時間(windowSec) / 縦軸(固定 = min〜max、自動 = 表示中の値に合わせる) / 警告線 / 塗りつぶし / 統計
// 値は基本単位で保存し、表示のときだけ選んだ単位に換算する(メーターと同じ)。
import QtQuick
import OpenCruise

WidgetBase {
    id: root

    // ---------------------------------------------------------------- 計測値と単位
    readonly property string metric: WidgetRegistry.gaugeSpecs[config.metric] ? config.metric : "boost"
    // データ源があるか(無いときは「データなし」。履歴は Main.qml が捨てるので、線は描かれない)
    readonly property bool hasData: can.dataAvailable
    readonly property var gauge: WidgetRegistry.gaugeSpecs[metric]
    readonly property var unitDef: {
        const list = gauge.units
        for (let i = 0; i < list.length; ++i) {
            if (list[i].id === config.unit) return list[i]
        }
        return list[0]
    }
    readonly property string unitText: unitDef.label
    readonly property int decimals: unitDef.dec
    // 作っている途中(非同期作成中)は unitDef がまだ決まっていないことがあるので、そのときは換算しない
    function toShown(base) { return unitDef ? Number(base) * unitDef.scale + (unitDef.offset || 0) : Number(base) }
    function fmt(v, dec) {
        const half = 0.5 * Math.pow(10, -dec)
        return (Math.abs(v) < half ? 0 : v).toFixed(dec)
    }

    readonly property int windowSec: [30, 60, 300, 600].indexOf(Number(config.windowSec)) >= 0 ? Number(config.windowSec) : 60
    readonly property bool autoScale: config.autoScale === true
    readonly property bool fillOn: config.fill !== false
    readonly property bool statsOn: config.showStats !== false
    readonly property bool warnOn: config.warnEnabled === true && config.warn !== undefined
    readonly property bool warnBelow: gauge.warnBelow === true
    readonly property real warnV: toShown(config.warn)
    readonly property real fixedMin: toShown(config.min !== undefined ? config.min : gauge.limitMin)
    readonly property real fixedMax: Math.max(toShown(config.max !== undefined ? config.max : gauge.limitMax), fixedMin + 0.1)

    // ---------------------------------------------------------------- データ(表示単位に直した、表示する時間の分)
    property var points: []          // [{ t, v }]
    property real current: NaN
    property real statMin: NaN
    property real statMax: NaN
    property real statAvg: NaN
    // 作り終わったか。少しずつ作っている途中にも履歴の更新は届くので、作り終わるまでは読み直さない
    property bool built: false
    function collect() {
        if (!built) return
        if (!hasData) {
            points = []
            current = NaN
            statMin = NaN
            statMax = NaN
            statAvg = NaN
            root.paintCanvas(chart)
            return
        }
        const s = VehicleHistory.series(metric)
        const from = Date.now() - windowSec * 1000
        const list = []
        let mn = Infinity, mx = -Infinity, sum = 0
        // 古い方は二分探索で飛ばす
        let lo = 0, hi = s.t.length
        while (lo < hi) { const mid = (lo + hi) >> 1; if (s.t[mid] < from) lo = mid + 1; else hi = mid }
        for (let i = Math.max(0, lo - 1); i < s.t.length; ++i) {
            const v = toShown(s.v[i])
            list.push({ t: s.t[i], v: v })
            if (s.t[i] >= from) { mn = Math.min(mn, v); mx = Math.max(mx, v); sum += v }
        }
        points = list
        const n = s.t.length - lo
        current = list.length > 0 ? list[list.length - 1].v : NaN
        statMin = n > 0 ? mn : NaN
        statMax = n > 0 ? mx : NaN
        statAvg = n > 0 ? sum / n : NaN
        root.paintCanvas(chart)
    }
    Connections {
        target: VehicleHistory
        enabled: root.built && root.onScreen && !root.lifting
        function onRevisionChanged() { root.collect() }
    }
    onMetricChanged: collect()
    onHasDataChanged: collect()
    // 見えていない間は履歴を読み直さない(履歴そのものは VehicleHistory が記録し続ける)。見えたら今の分で描き直す
    onOnScreenChanged: if (onScreen) collect()
    onUnitDefChanged: collect()
    onWindowSecChanged: collect()
    Component.onCompleted: { built = true; collect() }

    readonly property bool inZone: warnOn && !isNaN(current) && (warnBelow ? current <= warnV : current >= warnV)

    // 縦軸の範囲
    readonly property var range: {
        if (!autoScale || isNaN(statMin)) return { lo: fixedMin, hi: fixedMax }
        let lo = statMin, hi = statMax
        if (warnOn) { lo = Math.min(lo, warnV); hi = Math.max(hi, warnV) }
        const span = Math.max(hi - lo, (toShown(gauge.minSpan) - toShown(0)) * 0.25, Math.pow(10, -decimals) * 4)
        const mid = (lo + hi) / 2
        return { lo: mid - span * 0.6, hi: mid + span * 0.6 }
    }
    // 目盛り: 1, 2, 5 × 10^n のきりのよい刻みで 3〜5 本
    readonly property var ticks: {
        const span = range.hi - range.lo
        const raw = span / 4
        const p = Math.pow(10, Math.floor(Math.log(raw) / Math.LN10))
        const step = [1, 2, 5, 10].map(k => k * p).find(st => st >= raw) || p * 10
        const list = []
        for (let v = Math.ceil(range.lo / step) * step; v <= range.hi + 1e-9; v += step) list.push(v)
        return { step: step, values: list }
    }
    readonly property int tickDec: Math.max(0, Math.min(3, -Math.floor(Math.log(ticks.step) / Math.LN10 + 1e-9)))

    readonly property real m: root.innerMargin
    readonly property bool compact: Math.min(gridW, gridH) <= 2

    // ---------------------------------------------------------------- 上段: 名前と今の値
    Item {
        id: head
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: root.m }
        height: Math.max(root.titleBarHeight, valueText.implicitHeight)
        Row {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            visible: root.titleVisible
            spacing: 8
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.inZone ? "warning" : root.gauge.icon
                size: root.titleBarHeight
                color: root.inZone ? Theme.error : Theme.accent
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.fontFamily
                font.pixelSize: root.titleFontSize
                color: root.inZone ? Theme.error : Theme.textSecondary
                text: root.titleText(root.gauge.title)
            }
            Rectangle {   // データの状態の表示(ダミーデータ中は「モック」、データ源が無いときは「データなし」)
                anchors.verticalCenter: parent.verticalCenter
                width: mockText.implicitWidth + 12
                height: mockText.implicitHeight + 4
                radius: height / 2
                color: "transparent"
                border.color: root.hasData ? Theme.warn : Theme.textSecondary
                Text {
                    id: mockText
                    anchors.centerIn: parent
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.round(root.titleFontSize * 0.7)
                    text: root.hasData ? "モック" : "データなし"
                    color: root.hasData ? Theme.warn : Theme.textSecondary
                }
            }
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 4
            NumberText {
                id: valueText
                bold: true
                italic: Theme.numberItalic
                pixelSize: Math.round(Math.max(18, Math.min(root.height * 0.16, 44)))
                color: root.inZone ? Theme.error : Theme.textPrimary
                text: isNaN(root.current) || !root.hasData ? "--" : root.fmt(root.current, root.decimals)
            }
            Text {
                anchors.baseline: valueText.baseline
                font.family: Theme.fontFamily
                font.pixelSize: Math.round(valueText.effectivePixelSize * 0.45)
                color: Theme.textSecondary
                text: root.unitText
            }
        }
    }

    // ---------------------------------------------------------------- 下段: 最大・最小・平均
    Row {
        id: stats
        visible: root.statsOn && root.height >= 150
        anchors { bottom: parent.bottom; right: parent.right; bottomMargin: root.m * 0.8; rightMargin: root.m }
        spacing: Math.round(root.m * 1.2)
        height: visible ? implicitHeight : 0
        Repeater {
            model: [{ k: "MAX", v: root.statMax }, { k: "MIN", v: root.statMin }, { k: "平均", v: root.statAvg }]
            Row {
                required property var modelData
                spacing: 4
                Text {
                    anchors.baseline: statVal.baseline
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.pixelSize: Math.round(statVal.effectivePixelSize * 0.7)
                    color: Theme.textSecondary
                    text: modelData.k
                }
                NumberText {
                    id: statVal
                    bold: true
                    italic: Theme.numberItalic
                    pixelSize: Math.round(Math.max(12, Math.min(root.titleFontSize, 18)))
                    color: root.warnOn && !isNaN(modelData.v) && (root.warnBelow ? modelData.v <= root.warnV : modelData.v >= root.warnV)
                           ? Theme.error : Theme.textPrimary
                    text: isNaN(modelData.v) ? "--" : root.fmt(modelData.v, root.decimals)
                }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(Math.max(11, Math.min(root.titleFontSize, 18) * 0.75))
            color: Theme.textSecondary
            text: root.unitText
        }
    }

    // ---------------------------------------------------------------- 中段: グラフ
    // データ源が無いときの案内(グラフの真ん中)
    Text {
        z: 1
        visible: !root.hasData
        anchors.centerIn: chart
        font.family: Theme.fontFamily
        font.pixelSize: Math.round(Math.max(12, Math.min(root.titleFontSize * 1.1, 20)))
        color: Theme.textSecondary
        text: "データがありません"
    }
    Canvas {
        id: chart
        anchors { top: head.bottom; bottom: stats.visible ? stats.top : parent.bottom; left: parent.left; right: parent.right
                  topMargin: root.m * 0.6; bottomMargin: root.m * 0.6; leftMargin: root.m; rightMargin: root.m }
        renderTarget: Canvas.Image
        onWidthChanged: if (visible) root.paintCanvas(chart)
        onHeightChanged: if (visible) root.paintCanvas(chart)
        readonly property color lineColor: root.inZone ? Theme.error : Theme.accent
        readonly property string key: [Theme.accent, Theme.error, Theme.panelBorder, Theme.textSecondary, root.fillOn,
                                       root.warnOn, root.warnV, root.range.lo, root.range.hi, Theme.numberFontFamily].join("|")
        onKeyChanged: if (visible) root.paintCanvas(chart)

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const fontPx = Math.round(Math.max(10, Math.min(root.titleFontSize * 0.75, 14)))
            ctx.font = fontPx + "px \"" + Theme.numberFontFamily + "\""
            const lo = root.range.lo, hi = root.range.hi
            // 左の目盛りの幅
            let labelW = 0
            for (let i = 0; i < root.ticks.values.length; ++i)
                labelW = Math.max(labelW, ctx.measureText(root.fmt(root.ticks.values[i], root.tickDec)).width)
            // 上下は、端の目盛りの数字と時間の目盛りが切れないだけあける
            const left = Math.ceil(labelW + 6), topPad = Math.ceil(fontPx * 0.6), bottomH = fontPx + 6
            const W = width - left, H = height - bottomH
            if (W < 10 || H - topPad < 10) return
            const yOf = v => H - (Math.max(lo, Math.min(hi, v)) - lo) / (hi - lo) * (H - topPad)
            const now = Date.now(), from = now - root.windowSec * 1000
            const xOf = t => left + (t - from) / (root.windowSec * 1000) * W

            // 目盛りの線と数字
            ctx.lineWidth = 1
            ctx.strokeStyle = Theme.panelBorder
            ctx.fillStyle = Theme.textSecondary
            ctx.textAlign = "right"
            ctx.textBaseline = "middle"
            for (let i = 0; i < root.ticks.values.length; ++i) {
                const v = root.ticks.values[i], y = Math.round(yOf(v)) + 0.5
                ctx.beginPath(); ctx.moveTo(left, y); ctx.lineTo(width, y); ctx.stroke()
                ctx.fillText(root.fmt(v, root.tickDec), left - 6, y)
            }
            // 時間の目盛り(左端と右端)
            ctx.textBaseline = "top"
            ctx.textAlign = "left"
            const span = root.windowSec >= 120 ? (root.windowSec / 60) + "分前" : root.windowSec + "秒前"
            ctx.fillText(span, left, H + 3)
            ctx.textAlign = "right"
            ctx.fillText("今", width, H + 3)

            // 警告線と、超えた側の薄い赤
            if (root.warnOn && root.warnV > lo && root.warnV < hi) {
                const wy = yOf(root.warnV)
                ctx.fillStyle = Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.1)
                if (root.warnBelow) ctx.fillRect(left, wy, W, H - wy)
                else ctx.fillRect(left, topPad, W, wy - topPad)
                ctx.strokeStyle = Theme.error
                ctx.lineWidth = 1.5
                ctx.setLineDash([6, 4])
                ctx.beginPath(); ctx.moveTo(left, wy); ctx.lineTo(width, wy); ctx.stroke()
                ctx.setLineDash([])
            }

            // 折れ線(横 1 px に何点も入るときは間引く)
            const pts = root.points
            if (pts.length < 2) return
            const stepN = Math.max(1, Math.floor(pts.length / W))
            ctx.save()
            ctx.beginPath()
            ctx.rect(left, topPad - 2, W, H - topPad + 4)
            ctx.clip()
            ctx.beginPath()
            let first = true, lastX = left
            for (let i = 0; i < pts.length; i += stepN) {
                const x = xOf(pts[i].t), y = yOf(pts[i].v)
                if (first) { ctx.moveTo(x, y); first = false } else ctx.lineTo(x, y)
                lastX = x
            }
            const lp = pts[pts.length - 1]
            ctx.lineTo(xOf(lp.t), yOf(lp.v))
            lastX = xOf(lp.t)
            if (root.fillOn) {
                ctx.save()
                ctx.lineTo(lastX, H)
                ctx.lineTo(Math.max(left, xOf(pts[0].t)), H)
                ctx.closePath()
                const g = ctx.createLinearGradient(0, 0, 0, H)
                g.addColorStop(0, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.32))
                g.addColorStop(1, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.02))
                ctx.fillStyle = g
                ctx.fill()
                ctx.restore()
                // 塗りの輪郭で線を引き直すため、線だけのパスを作り直す
                ctx.beginPath()
                first = true
                for (let i = 0; i < pts.length; i += stepN) {
                    const x = xOf(pts[i].t), y = yOf(pts[i].v)
                    if (first) { ctx.moveTo(x, y); first = false } else ctx.lineTo(x, y)
                }
                ctx.lineTo(xOf(lp.t), yOf(lp.v))
            }
            ctx.strokeStyle = lineColor
            ctx.lineWidth = Math.max(2, Math.min(3, root.s * 0.012))
            ctx.lineJoin = "round"
            ctx.stroke()
            // 今の値の点
            ctx.fillStyle = lineColor
            ctx.beginPath()
            ctx.arc(xOf(lp.t), yOf(lp.v), ctx.lineWidth * 1.8, 0, Math.PI * 2)
            ctx.fill()
            ctx.restore()
        }
    }
}
