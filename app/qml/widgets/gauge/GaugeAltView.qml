// メーター(GaugeWidget)の、円形ではない見た目。GaugeWidget の本体の中に Loader で置かれ、gw(メーター本体)の
// 値・範囲・単位・警告の状態をそのまま使う(計測値・単位・最小/最大・警告ルール・データなし・モックの扱いはメーターと同じ)。
//   trend     数値+推移: 大きな数値の下に、直近の推移(VehicleHistory)を小さな折れ線で。config.trendSec(秒)・trendScale(auto / fixed)
//   center    センター基準: 基準値(config.centerRef。基本単位。未設定なら範囲が 0 をまたげば 0、それ以外は中央)から左右へ伸びるバー
//   shift     シフトライト: ランプの列。config.shiftStart から光り始め、config.shiftFull(変速の回転数)で全部が点滅する
//             (どちらも基本単位。未設定なら、警告の範囲の始まり(無ければ範囲の 85%)と、その 30% 手前)。
//             config.shiftMode: center(中央から外へ) / edges(外から中央へ) / left(左から右へ)。config.shiftLeds: 数(0 で幅から自動)
//   tank      タンク: 容器の中の液面。config.tankWave(液面の揺れ。既定オン)
//   histogram 分布: この走行(VehicleHistory.trip。1 秒に 1 件)で、どの値の帯にどれだけいたかの棒グラフ。config.histBins(区切りの数)。
//             右下の「↺」でこのメーターの数え直し(起動中だけ)
// 見えていない間(gw.onScreen が false)は、描き直し・揺れ・点滅を止める。
import QtQuick
import OpenCruise

Item {
    id: av
    required property var gw

    readonly property string look: gw.dialStyle
    readonly property var cfg: gw.config
    readonly property real span: Math.max(1e-9, gw.maxV - gw.minV)
    readonly property color dimColor: Theme.mix(Theme.panel, Theme.textSecondary, 0.22)
    readonly property string valueText: gw.hasData ? gw.fmt(gw.shown, gw.decimals) : "---"

    // ---------------------------------------------------------------- 名前(アイコン+名前。警告中は警告マークで点滅)
    Row {
        id: label
        visible: gw.labelVisible
        anchors { top: parent.top; left: parent.left }
        width: parent.width - 70
        height: visible ? Math.max(gw.titleBarHeight, Math.round(av.height * (gw.compact ? 0.16 : 0.12))) : 0
        spacing: 8
        MaterialIcon {
            visible: gw.showIcon
            anchors.verticalCenter: parent.verticalCenter
            name: gw.labelIcon
            size: label.height * 0.9
            color: gw.alerting ? gw.alertColor : Theme.accent
            opacity: gw.alerting ? gw.blink : 1
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, label.width - (gw.showIcon ? label.height + label.spacing : 0))
            font.family: Theme.fontFamily
            font.bold: true
            font.pixelSize: Math.max(11, label.height * 0.72)
            elide: Text.ElideRight
            color: gw.labelColor
            text: gw.labelText
        }
    }

    // 数値+単位(右寄せ)。各見た目で場所と高さを決めて使う
    component ValueBox: Item {
        id: vb
        property int align: Text.AlignRight
        property color textColor: gw.valueColor
        NumberText {
            id: vbNum
            anchors { left: parent.left; right: vbUnit.left; top: parent.top; bottom: parent.bottom; rightMargin: 4 }
            horizontalAlignment: vb.align
            verticalAlignment: Text.AlignVCenter
            bold: true
            italic: Theme.numberItalic
            pixelSize: 300
            minimumPixelSize: 12
            fit: true
            text: av.valueText
            color: vb.textColor
        }
        Text {
            id: vbUnit
            anchors { right: parent.right; baseline: vbNum.baseline }
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(11, Math.round(vb.height * 0.2))
            color: Theme.textSecondary
            text: gw.unitText
        }
    }

    // 下の小さな目盛りの文字
    component ScaleText: Text {
        font.family: Theme.numberFontFamily
        font.pixelSize: Math.max(10, Math.round(gw.titleFontSize * 0.8))
        color: Theme.textSecondary
    }

    Item {
        id: contentArea
        anchors { top: label.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; topMargin: gw.m * 0.4 }
    }

    // ================================================================ 数値+推移
    Item {
        visible: av.look === "trend"
        anchors.fill: contentArea
        readonly property int sec: [30, 60, 120, 300, 600].indexOf(Number(av.cfg.trendSec)) >= 0 ? Number(av.cfg.trendSec) : 60
        ValueBox {
            id: trendValue
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: parent.height * (gw.compact ? 0.5 : 0.42)
        }
        Canvas {
            id: trendCanvas
            anchors { top: trendValue.bottom; left: parent.left; right: parent.right; bottom: trendFoot.top; topMargin: 4 }
            renderStrategy: Canvas.Cooperative
            property int sec: parent.sec
            onSecChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const W = width, H = height
                if (W < 4 || H < 4) return
                const s = VehicleHistory.series(gw.metric)
                const now = Date.now(), from = now - sec * 1000
                const ts = [], vs = []
                for (let i = 0; i < s.t.length; ++i) {
                    if (s.t[i] < from) continue
                    ts.push(s.t[i]); vs.push(gw.toShown(s.v[i]))
                }
                // 縦軸: 固定 = メーターの最小〜最大 / 自動 = 表示中の値(幅が狭すぎないよう、範囲の 10% は取る)
                let lo = gw.minV, hi = gw.maxV
                if (av.cfg.trendScale !== "fixed" && vs.length > 0) {
                    lo = Math.min.apply(null, vs); hi = Math.max.apply(null, vs)
                    const need = av.span * 0.1
                    if (hi - lo < need) { const c = (hi + lo) / 2; lo = c - need / 2; hi = c + need / 2 }
                    const pad = (hi - lo) * 0.12; lo -= pad; hi += pad
                }
                const yOf = v => H - 2 - (v - lo) / Math.max(1e-9, hi - lo) * (H - 4)
                // 警告・注意の範囲をうっすら塗る
                const zone = (list, col) => {
                    for (const z of list) {
                        const a = Math.max(lo, z.lo), b = Math.min(hi, z.hi)
                        if (b <= a) continue
                        ctx.fillStyle = col
                        ctx.fillRect(0, yOf(b), W, yOf(a) - yOf(b))
                    }
                }
                zone(gw.warnZones, Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.12))
                zone(gw.cautionZones, Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.10))
                ctx.strokeStyle = av.dimColor
                ctx.lineWidth = 1
                ctx.beginPath(); ctx.moveTo(0, H - 0.5); ctx.lineTo(W, H - 0.5); ctx.stroke()
                if (ts.length < 2) return
                const col = gw.alerting ? gw.alertColor : Theme.accent
                ctx.beginPath()
                for (let i = 0; i < ts.length; ++i) {
                    const x = (ts[i] - from) / (sec * 1000) * W, y = yOf(vs[i])
                    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                }
                ctx.lineWidth = Math.max(2, Math.round(gw.s * 0.012))
                ctx.lineJoin = "round"
                ctx.strokeStyle = col
                ctx.stroke()
                // 塗り(下へ薄く)
                ctx.lineTo((ts[ts.length - 1] - from) / (sec * 1000) * W, H)
                ctx.lineTo((ts[0] - from) / (sec * 1000) * W, H)
                ctx.closePath()
                ctx.fillStyle = Qt.rgba(col.r, col.g, col.b, 0.14)
                ctx.fill()
            }
            // 値の履歴は 0.2 秒ごとに増える。描くのは 0.4 秒ごと(見えている間だけ)
            property int tick: 0
            Connections {
                target: VehicleHistory
                enabled: av.look === "trend" && gw.onScreen
                function onRevisionChanged() { if ((++trendCanvas.tick & 1) === 0) gw.paintCanvas(trendCanvas) }
            }
            Connections {
                target: gw
                function onOnScreenChanged() { if (gw.onScreen) gw.paintCanvas(trendCanvas) }
                function onZoneKeyChanged() { gw.paintCanvas(trendCanvas) }
            }
        }
        Item {
            id: trendFoot
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: gw.compact ? 0 : Math.round(gw.titleFontSize * 1.1)
            visible: !gw.compact
            ScaleText { anchors.left: parent.left; anchors.bottom: parent.bottom
                        text: parent.parent.sec >= 120 ? (parent.parent.sec / 60) + "分前" : parent.parent.sec + "秒前" }
            ScaleText { anchors.right: parent.right; anchors.bottom: parent.bottom; text: "今" }
        }
    }

    // ================================================================ センター基準
    Item {
        id: centerLook
        visible: av.look === "center"
        anchors.fill: contentArea
        readonly property real ref: {
            const r = av.cfg.centerRef !== undefined && av.cfg.centerRef !== null && av.cfg.centerRef !== ""
                      ? gw.toShown(Number(av.cfg.centerRef)) : (gw.minV < 0 && gw.maxV > 0 ? 0 : (gw.minV + gw.maxV) / 2)
            return Math.max(gw.minV, Math.min(gw.maxV, r))
        }
        ValueBox {
            id: centerValue
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: parent.height * (gw.compact ? 0.5 : 0.48)
        }
        Item {
            id: track
            anchors { left: parent.left; right: parent.right; top: centerValue.bottom; topMargin: parent.height * 0.08 }
            height: Math.max(10, Math.round(gw.s * 0.09))
            readonly property real cx: gw.frac(centerLook.ref) * width
            readonly property real vx: gw.frac(gw.hasData ? gw.shown : centerLook.ref) * width
            Rectangle { anchors.fill: parent; radius: height / 2; color: av.dimColor }
            // 警告・注意の範囲(帯の上下に細く)
            Repeater {
                model: gw.warnZones.concat(gw.cautionZones)
                Rectangle {
                    required property var modelData
                    x: gw.frac(modelData.lo) * track.width
                    width: Math.max(1, (gw.frac(modelData.hi) - gw.frac(modelData.lo)) * track.width)
                    y: -Math.max(3, track.height * 0.25) - 2
                    height: Math.max(3, track.height * 0.25)
                    radius: height / 2
                    color: gw.warnZones.indexOf(modelData) >= 0 ? Theme.error : Theme.warn
                    opacity: 0.8
                }
            }
            Rectangle {
                x: Math.min(track.cx, track.vx)
                width: Math.max(2, Math.abs(track.vx - track.cx))
                height: parent.height
                radius: Math.min(height / 2, width / 2)
                color: gw.zoneColorAt(gw.shown, Theme.accent)
                visible: gw.hasData
            }
            Rectangle {
                x: track.cx - width / 2
                y: -height * 0.3
                width: 2
                height: parent.height * 1.6
                color: Theme.textPrimary
            }
        }
        Item {
            visible: !gw.compact || parent.height > 80
            anchors { left: parent.left; right: parent.right; top: track.bottom; topMargin: 4 }
            height: Math.round(gw.titleFontSize * 1.2)
            ScaleText { anchors.left: parent.left; text: gw.fmt(gw.minV, gw.unitDef.stepDec) }
            ScaleText { x: Math.max(0, Math.min(parent.width - width, track.cx - width / 2)); text: gw.fmt(centerLook.ref, gw.unitDef.stepDec) }
            ScaleText { anchors.right: parent.right; text: gw.fmt(gw.maxV, gw.unitDef.stepDec) }
        }
    }

    // ================================================================ シフトライト
    Item {
        id: shiftLook
        visible: av.look === "shift"
        anchors.fill: contentArea
        readonly property real full: {
            if (av.cfg.shiftFull !== undefined && av.cfg.shiftFull !== null && av.cfg.shiftFull !== "")
                return gw.toShown(Number(av.cfg.shiftFull))
            const z = gw.warnZones.filter(z => z.lo > gw.minV + 1e-9)
            if (z.length > 0 && !gw.warnBelow) return z[0].lo
            return gw.minV + av.span * 0.85
        }
        readonly property real start: {
            const s = av.cfg.shiftStart !== undefined && av.cfg.shiftStart !== null && av.cfg.shiftStart !== ""
                      ? gw.toShown(Number(av.cfg.shiftStart)) : full - av.span * 0.3
            return Math.max(gw.minV, Math.min(full - av.span * 0.02, s))
        }
        readonly property string mode: ["center", "edges", "left"].indexOf(av.cfg.shiftMode) >= 0 ? av.cfg.shiftMode : "center"
        // 光の量(0〜1)。変速の回転数を超えたら全点滅
        readonly property real amount: gw.hasData ? Math.max(0, Math.min(1, (gw.shown - start) / Math.max(1e-9, full - start))) : 0
        readonly property bool flashing: gw.hasData && gw.shown >= full
        // ランプの数: 設定(0 で幅から自動。奇数にすると中央が 1 つ)
        readonly property int leds: {
            const n = Math.round(Number(av.cfg.shiftLeds) || 0)
            if (n >= 5) return Math.min(25, n)
            const auto = Math.max(5, Math.min(17, Math.floor(width / Math.max(18, height * 0.3))))
            return mode === "left" ? auto : (auto % 2 === 0 ? auto - 1 : auto)
        }
        readonly property bool showValue: height > 90
        property bool flashOn: true
        Timer {
            interval: 90; repeat: true
            running: shiftLook.flashing && av.look === "shift" && gw.onScreen
            onTriggered: shiftLook.flashOn = !shiftLook.flashOn
            onRunningChanged: if (!running) shiftLook.flashOn = true
        }
        // ランプ i の、光り始める順番(0〜1)
        function rank(i) {
            const n = leds
            if (mode === "left") return n <= 1 ? 0 : i / (n - 1)
            const half = (n - 1) / 2
            const d = Math.abs(i - half) / Math.max(0.5, half)   // 0 = 中央、1 = 端
            return mode === "center" ? d : 1 - d
        }
        Row {
            id: ledRow
            anchors.horizontalCenter: parent.horizontalCenter
            y: shiftLook.showValue ? parent.height * 0.06 : (parent.height - height) / 2
            readonly property real d: Math.min((shiftLook.width - (shiftLook.leds - 1) * spacing) / shiftLook.leds,
                                               shiftLook.showValue ? shiftLook.height * 0.32 : shiftLook.height * 0.8)
            spacing: Math.max(3, Math.round(shiftLook.width * 0.012))
            Repeater {
                model: shiftLook.leds
                Rectangle {
                    required property int index
                    readonly property real r: shiftLook.rank(index)
                    readonly property bool lit: shiftLook.flashing ? shiftLook.flashOn
                                                                   : (shiftLook.amount > 0 && r <= shiftLook.amount + 1e-6)
                    // 光る順の前半は緑、次に黄、最後は赤。全点滅のときは全部赤
                    readonly property color on: shiftLook.flashing ? Theme.error : (r < 0.45 ? Theme.ok : (r < 0.8 ? Theme.warn : Theme.error))
                    width: ledRow.d
                    height: ledRow.d
                    radius: width / 2
                    color: lit ? on : av.dimColor
                    border.width: lit ? 0 : 1
                    border.color: Theme.mix(Theme.panel, Theme.panelBorder, 0.9)
                    Rectangle {   // 光のにじみ
                        visible: parent.lit
                        anchors.centerIn: parent
                        width: parent.width * 1.3; height: width; radius: width / 2
                        color: parent.on
                        opacity: 0.15
                        z: -1
                    }
                }
            }
        }
        ValueBox {
            visible: shiftLook.showValue
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; top: ledRow.bottom; topMargin: parent.height * 0.08 }
            align: Text.AlignHCenter
            textColor: shiftLook.flashing ? Theme.error : gw.valueColor
        }
    }

    // ================================================================ タンク
    Item {
        id: tankLook
        visible: av.look === "tank"
        anchors.fill: contentArea
        readonly property real level: gw.hasData ? gw.frac(gw.shown) : 0
        readonly property color liquid: gw.hasData ? gw.zoneColorAt(gw.shown, Theme.accent) : av.dimColor
        Rectangle {
            id: tank
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: Math.min(parent.width * 0.42, parent.height * 0.8)
            radius: Math.round(width * 0.16)
            color: Theme.mix(Theme.background, Theme.panel, 0.4)
            border.width: 2
            border.color: Theme.panelBorder
            clip: true
            Item {
                id: liquidBox
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 3 }
                height: (tank.height - 6) * tankLook.level
                Rectangle { anchors.fill: parent; anchors.topMargin: wave.height * 0.5; color: tankLook.liquid; opacity: 0.85 }
                // 液面の波(1 回だけ描いた波を横に流す)
                Canvas {
                    id: wave
                    width: tank.width * 2
                    height: Math.max(6, tank.width * 0.12)
                    y: -height * 0.5
                    visible: liquidBox.height > 2
                    property color col: tankLook.liquid
                    onColChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const W = width, H = height, L = W / 2
                        ctx.beginPath()
                        ctx.moveTo(0, H)
                        for (let x = 0; x <= W; x += 2) ctx.lineTo(x, H * 0.5 + Math.sin(x / L * Math.PI * 2) * H * 0.35)
                        ctx.lineTo(W, H)
                        ctx.closePath()
                        ctx.fillStyle = Qt.rgba(col.r, col.g, col.b, 0.85)
                        ctx.fill()
                    }
                    NumberAnimation on x {
                        from: -tank.width; to: 0
                        duration: 2600
                        loops: Animation.Infinite
                        running: av.look === "tank" && gw.onScreen && av.cfg.tankWave !== false && wave.visible
                    }
                }
            }
            // 警告・注意の範囲の境目(容器の右の縁に印)
            Repeater {
                model: gw.warnZones.concat(gw.cautionZones)
                Rectangle {
                    required property var modelData
                    readonly property real v: gw.warnBelow ? modelData.hi : modelData.lo
                    visible: v > gw.minV && v < gw.maxV
                    x: tank.width - width - 2
                    y: 3 + (tank.height - 6) * (1 - gw.frac(v)) - height / 2
                    width: tank.width * 0.22
                    height: 3
                    color: gw.warnZones.indexOf(modelData) >= 0 ? Theme.error : Theme.warn
                }
            }
        }
        ValueBox {
            anchors { left: tank.right; right: parent.right; leftMargin: gw.m; verticalCenter: tank.verticalCenter }
            height: Math.min(tank.height * 0.5, parent.height)
        }
    }

    // ================================================================ 分布
    Item {
        id: histLook
        visible: av.look === "histogram"
        anchors.fill: contentArea
        readonly property int bins: Math.max(4, Math.min(24, Math.round(Number(av.cfg.histBins) || 10)))
        property double resetAt: 0
        property var counts: []
        property int total: 0
        readonly property int current: gw.hasData ? Math.min(bins - 1, Math.floor(gw.frac(gw.shown) * bins)) : -1
        readonly property int most: {
            let best = -1, n = 0
            for (let i = 0; i < counts.length; ++i) if (counts[i] > n) { n = counts[i]; best = i }
            return best
        }
        function edge(i) { return gw.minV + av.span * i / bins }
        function recount() {
            const s = VehicleHistory.tripSeries(gw.metric)
            const c = new Array(bins).fill(0)
            let t = 0
            for (let i = 0; i < s.t.length; ++i) {
                if (s.t[i] < resetAt) continue
                const f = gw.frac(gw.toShown(s.v[i]))
                c[Math.min(bins - 1, Math.floor(f * bins))]++
                t++
            }
            counts = c
            total = t
        }
        onBinsChanged: recount()
        Component.onCompleted: recount()
        Connections {
            target: VehicleHistory
            enabled: av.look === "histogram" && gw.onScreen
            function onTripRevisionChanged() { histLook.recount() }
        }
        Connections {
            target: gw
            function onOnScreenChanged() { if (gw.onScreen) histLook.recount() }
            function onUnitDefChanged() { histLook.recount() }
            function onMinVChanged() { histLook.recount() }
            function onMaxVChanged() { histLook.recount() }
        }
        Item {
            id: histHead
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: parent.height * (gw.compact ? 0.3 : 0.24)
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: parent.width * 0.55
                visible: !gw.compact
                font.family: Theme.fontFamily
                font.pixelSize: Math.max(11, Math.round(gw.titleFontSize * 0.85))
                color: Theme.textSecondary
                elide: Text.ElideRight
                text: histLook.most < 0 ? "この走行の記録はまだありません"
                      : "いちばん多い: " + gw.fmt(histLook.edge(histLook.most), gw.unitDef.stepDec) + "〜"
                        + gw.fmt(histLook.edge(histLook.most + 1), gw.unitDef.stepDec)
                        + "(" + Math.round(histLook.counts[histLook.most] / Math.max(1, histLook.total) * 100) + "%)"
            }
            ValueBox {
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: gw.compact ? parent.width : parent.width * 0.42
            }
        }
        Row {
            id: bars
            anchors { top: histHead.bottom; left: parent.left; right: parent.right; bottom: histFoot.top; topMargin: 6; bottomMargin: 3 }
            spacing: Math.max(2, Math.round(width * 0.012))
            readonly property int maxCount: Math.max(1, Math.max.apply(null, histLook.counts.length ? histLook.counts : [1]))
            Repeater {
                model: histLook.bins
                Item {
                    required property int index
                    width: (bars.width - (histLook.bins - 1) * bars.spacing) / histLook.bins
                    height: bars.height
                    readonly property real mid: histLook.edge(index + 0.5)
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Math.max(2, parent.height * (histLook.counts[index] || 0) / bars.maxCount)
                        radius: Math.min(4, width / 3)
                        color: index === histLook.current ? gw.zoneColorAt(gw.shown, Theme.accent)
                               : Theme.mix(av.dimColor, gw.zoneColorAt(parent.mid, Theme.textSecondary), 0.45)
                    }
                }
            }
        }
        Item {
            id: histFoot
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: Math.round(gw.titleFontSize * 1.2)
            ScaleText { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: gw.fmt(gw.minV, gw.unitDef.stepDec) }
            ScaleText { anchors.right: resetChip.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                        text: gw.fmt(gw.maxV, gw.unitDef.stepDec) }
            // 数え直し(このメーターだけ。走行の記録そのものは消さない)
            Rectangle {
                id: resetChip
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                height: parent.height
                width: height * 1.6
                radius: height / 2
                color: resetMouse.pressed ? Theme.accentFill : "transparent"
                border.width: 1
                border.color: Theme.panelBorder
                MaterialIcon { anchors.centerIn: parent; name: "restart_alt"; size: parent.height * 0.8; color: Theme.textSecondary }
                MouseArea {
                    id: resetMouse
                    anchors.fill: parent
                    anchors.margins: -6
                    onClicked: { histLook.resetAt = Date.now(); histLook.recount() }
                }
            }
        }
    }
}
