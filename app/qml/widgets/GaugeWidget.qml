// 汎用のメーター(ターボ圧計・タコメーター・スピードメーター・水温計・燃料計で共通)。
// 何を測るかは config.metric(WidgetRegistry の defaultConfig で種類ごとに固定)で決まり、計測値の定義
// (データ元・単位・換算・設定できる範囲・既定の見出し)は WidgetRegistry.gaugeSpecs にまとめてある。
// 設定値(最小・最大・警告値)は基本単位(bar / rpm / km/h / ℃ / %)で保存し、表示と編集のときだけ選んだ単位に換算する。
//  - 表示方式: アナログ+デジタル / アナログ / デジタル
//  - メーターの種類: クラシック(細い外周+目盛り+警告帯) / シンプル(細い進捗リング) / スポーツ(セグメント式のバー)
//    どの種類も、数字の内側に細い円を引き、数値は太字の斜体で表示する
//  - 最小値・最大値・単位・開始/終了角度・数値の配置・針の出っ張り・中心円の大きさと色・針の色
//  - アイコン表示・警告値・警告メッセージ(燃料計のように「この値以下で警告」の計測値もある)
//  - 2×2 などの小さいサイズ(短辺 2 マス以下)は小型表示(compact)。目盛りの数字を間引いて大きめにし、小目盛りを省く
// 警告になると、針と数値が赤になり、名前の横のアイコンが警告マークになって点滅し、警告メッセージの帯がメーターに重なる
// (解除は警告値から少し戻ったとき)。
//
// レイアウトの考え方:
//  1. 上部の見出し・下の警告欄は持たず、名前と警告メッセージはメーターの中(中心円の上)に出す
//  2. アナログは「半径 1 の円」で、弧・中心円・数値表示が実際に占める範囲(外接矩形)を求め、
//     その矩形が本体に最大で収まる半径を決める(弧の欠けている側の余白を無駄にしない)
//  3. 目盛り(静的)・進捗(値に追従)・針は別々に描き、値が変わっても目盛りは描き直さない
import QtQuick
import OpenCruise

WidgetBase {
    id: root

    // ---------------------------------------------------------------- 計測値の定義と単位
    readonly property string metric: WidgetRegistry.gaugeSpecs[config.metric] ? config.metric : "boost"
    readonly property var gauge: WidgetRegistry.gaugeSpecs[metric]
    readonly property var unitDef: {
        const list = gauge.units
        for (let i = 0; i < list.length; ++i) {
            if (list[i].id === config.unit) return list[i]
        }
        return list[0]
    }
    function toShown(base) { return Number(base) * unitDef.scale + (unitDef.offset || 0) }
    readonly property string unitText: unitDef.label
    readonly property int decimals: unitDef.dec
    readonly property real labelDiv: unitDef.labelDiv || 1        // 目盛りの数字を割る値(回転数の ×1000 など)
    readonly property bool warnBelow: gauge.warnBelow === true    // true なら「警告値以下」で警告

    // ---------------------------------------------------------------- 設定(表示単位に換算済み)
    readonly property string style: config.style === "analog" || config.style === "digital" ? config.style : "both"
    readonly property string dialStyle: config.dialStyle === "minimal" || config.dialStyle === "sport" ? config.dialStyle : "classic"
    readonly property real minV: toShown(config.min)
    readonly property real maxV: Math.max(toShown(config.max), minV + 0.1)
    readonly property real warnV: toShown(config.warn)
    readonly property bool warnOn: config.warnEnabled === true
    readonly property bool showIcon: config.showIcon !== false
    readonly property real startAngle: Math.max(-180, Math.min(-90, config.startAngle === undefined ? -135 : Number(config.startAngle)))
    readonly property real endAngle: Math.max(90, Math.min(180, config.endAngle === undefined ? 135 : Number(config.endAngle)))
    readonly property real sweepAngle: endAngle - startAngle
    readonly property bool autoLabelPosition: config.autoLabelPosition !== false
    readonly property bool needleTail: config.needleTail !== false
    readonly property real hubSize: Math.max(0.08, Math.min(0.5, (config.hubSize || 16) / 100))   // 直径 / 半径
    readonly property color needleColor: configuredColor("needleColor", Theme.accent)
    readonly property color hubColor: configuredColor("hubColor", Theme.panel)

    function configuredColor(key, fallback) {
        const value = String(config[key] || "")
        if (value === "theme") return Theme.accent
        if (value === "panel") return Theme.panel
        return /^#[0-9a-f]{6}$/i.test(value) ? Qt.color(value) : fallback
    }

    // ---------------------------------------------------------------- 値
    // データ元(現状は VehicleDataManager のモック)。束縛の依存を確実に取るため、プロパティを直接読む
    readonly property real sourceValue: {
        switch (metric) {
        case "rpm": return can.rpm
        case "speed": return can.speedKmh
        case "coolant": return can.coolantTempC
        case "fuel": return can.fuelPercent
        default: return can.boostBar
        }
    }
    readonly property real rawValue: toShown(sourceValue)
    // 針・数値は滑らかに追従させる(データは約 10Hz)
    property real shown: rawValue
    Behavior on shown { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

    function frac(v) { return Math.max(0, Math.min(1, (v - minV) / (maxV - minV))) }
    // 進捗の起点(0。範囲外なら近い端。ブーストの負圧は 0 から左へ伸びる)
    readonly property real originV: Math.max(minV, Math.min(maxV, 0))
    // 警告ゾーン(表示単位)。上側警告なら [警告値, 最大]、下側警告なら [最小, 警告値]
    readonly property bool hasWarnZone: warnOn && (warnBelow ? warnV > minV : warnV < maxV)
    readonly property real zoneLo: warnBelow ? minV : Math.max(warnV, minV)
    readonly property real zoneHi: warnBelow ? Math.min(warnV, maxV) : maxV
    function inZone(v) { return hasWarnZone && (warnBelow ? v <= warnV + 1e-9 : v >= warnV - 1e-9) }
    // 「-0.00」を出さない数値整形
    function fmt(v, dec) {
        const half = 0.5 * Math.pow(10, -dec)
        return (Math.abs(v) < half ? 0 : v).toFixed(dec)
    }

    // ---------------------------------------------------------------- 警告(ヒステリシスつき)
    property bool warning: false
    function updateWarning() {
        const hysteresis = (maxV - minV) * 0.03
        if (!warnOn) warning = false
        else if (warnBelow) {
            if (!warning && rawValue <= warnV) warning = true
            else if (warning && rawValue > warnV + hysteresis) warning = false
        } else {
            if (!warning && rawValue >= warnV) warning = true
            else if (warning && rawValue < warnV - hysteresis) warning = false
        }
    }
    onRawValueChanged: updateWarning()
    onWarnOnChanged: updateWarning()
    onWarnVChanged: updateWarning()
    onWarnBelowChanged: updateWarning()
    Component.onCompleted: updateWarning()

    readonly property color valueColor: warning ? Theme.error : Theme.textPrimary

    // 点滅(警告中だけ動かす)
    property real blink: 1
    SequentialAnimation on blink {
        running: root.warning && !root.lifting
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 380; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 380; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.blink = 1
    }

    // ---------------------------------------------------------------- 寸法
    readonly property real m: root.innerMargin
    // 小型表示(短辺 2 マス以下、2×2 など)。名前・目盛りの数字は残し、目盛りの数字を間引いて大きめにする。
    // 小目盛りとデジタルの両端の値は省く
    readonly property bool compact: Math.min(gridW, gridH) <= 2

    // ---------------------------------------------------------------- メーター内の名前(上部の見出しの代わり)
    // アイコン+名前。警告中はアイコンが警告マークになり点滅する。警告メッセージは下の帯をメーターに重ねて出す
    readonly property bool labelVisible: titleVisible
    readonly property string labelIcon: warning ? "warning" : gauge.icon
    readonly property string labelText: titleText(gauge.title)
    readonly property color labelColor: warning ? Theme.error : Theme.textSecondary
    readonly property real labelOpacity: 1

    // モックデータ中の表示(右上)
    Rectangle {
        id: mockTag
        z: 2
        anchors { top: parent.top; right: parent.right; topMargin: root.m * 0.7; rightMargin: root.m }
        width: mockText.implicitWidth + 14
        height: mockText.implicitHeight + 4
        radius: height / 2
        color: "transparent"
        border.color: Theme.warn
        Text {
            id: mockText
            anchors.centerIn: parent
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(root.titleFontSize * (root.compact ? 0.65 : 0.75))
            text: "モック"
            color: Theme.warn
        }
    }

    // ================================================================ 本体
    Item {
        id: body
        anchors { fill: parent; margins: root.m }

        // ============================================================ アナログ
        Item {
            id: dial
            visible: root.style !== "digital"

            // ---- 半径 1 の円で考えた配置(中心が原点、0° が真上・時計回り) ----
            // 数値表示の枠。auto のときは弧の空き(開始と終了の間)の方向へ置き、中心円とは重ならないようにする
            readonly property var readout: {
                // 数値を大きく見せるため広めに取る(小型表示は少し縦に広げる)
                const w = 0.72, h = root.compact ? 0.56 : 0.5
                const hubClear = root.hubSize / 2 + 0.05
                let cx = 0, cy = 0.52
                if (root.autoLabelPosition) {
                    const g = ((root.startAngle + root.endAngle) / 2 + 180) * Math.PI / 180
                    const rr = (360 - root.sweepAngle) >= 60 ? 0.56 : 0.5
                    cx = Math.sin(g) * rr
                    cy = -Math.cos(g) * rr
                }
                if (cy - h / 2 < hubClear) cy = hubClear + h / 2
                return { x: cx - w / 2, y: cy - h / 2, w: w, h: h }
            }
            // アナログのみのときの単位表示(中心円の下)
            readonly property real unitY: root.hubSize / 2 + 0.16
            readonly property string scaleUnitText: root.labelDiv > 1 ? "×" + root.labelDiv + " " + root.unitText : root.unitText

            // 弧・中心円・数値表示が占める範囲
            readonly property var bounds: {
                const xs = [], ys = []
                const add = (deg, r) => {
                    const a = deg * Math.PI / 180
                    xs.push(Math.sin(a) * r); ys.push(-Math.cos(a) * r)
                }
                add(root.startAngle, 1)
                add(root.endAngle, 1)
                for (let d = -180; d <= 180; d += 90) {
                    if (d >= root.startAngle && d <= root.endAngle) add(d, 1)
                }
                const hr = root.hubSize / 2
                xs.push(-hr, hr); ys.push(-hr, hr)
                if (root.style === "both") {
                    xs.push(readout.x, readout.x + readout.w)
                    ys.push(readout.y, readout.y + readout.h)
                } else {
                    ys.push(unitY + 0.07)
                }
                const pad = 0.02
                return { minX: Math.min(...xs) - pad, maxX: Math.max(...xs) + pad,
                         minY: Math.min(...ys) - pad, maxY: Math.max(...ys) + pad }
            }

            // ---- 実寸(px) ----
            // 半径(px)。QML のプロパティ名は小文字始まりが必須なので rpx とする
            readonly property real rpx: Math.max(1, Math.min(body.width / (bounds.maxX - bounds.minX),
                                                             body.height / (bounds.maxY - bounds.minY)))
            readonly property real cx: -bounds.minX * rpx
            readonly property real cy: -bounds.minY * rpx
            width: (bounds.maxX - bounds.minX) * rpx
            height: (bounds.maxY - bounds.minY) * rpx
            anchors.centerIn: parent

            // メーターの種類ごとの寸法(半径に対する比)
            // どの種類も、数字は内側の細い円(ringR)の外側、目盛りはさらに外側に置く
            readonly property var dims: root.dialStyle === "sport"
                ? { trackR: 0.92, trackW: 0.12, majorIn: 0.78, minorIn: 0.80, tickOut: 0.835, labelR: 0.69,
                    majorW: 0.03, minorW: 0.012, sub: 2, labelPx: 0.12, needleTip: 0.8, ringR: 0.6 }
                : (root.dialStyle === "minimal"
                   ? { trackR: 0.95, trackW: 0.03, majorIn: 0.83, minorIn: 0.86, tickOut: 0.89, labelR: 0.71,
                       majorW: 0.02, minorW: 0.01, sub: 2, labelPx: 0.11, needleTip: 0.86, ringR: 0.6 }
                   : { trackR: 0.96, trackW: 0.025, majorIn: 0.77, minorIn: 0.82, tickOut: 0.87, labelR: 0.685,
                       majorW: 0.026, minorW: 0.011, sub: 5, labelPx: 0.105, needleTip: 0.88, ringR: 0.6 })

            // スポーツのセグメント(数と 1 つあたりの角度。セグメントの間は少し空ける)
            readonly property int segCount: Math.max(16, Math.round(root.sweepAngle / 6))
            readonly property real segDeg: root.sweepAngle / segCount
            readonly property real segGap: Math.min(1.8, segDeg * 0.3)

            // 点灯するセグメントの範囲(中央の値が 0〜現在値の間にあるもの)。変わったときだけ描き直す
            readonly property int litFrom: {
                const lo = Math.min(root.originV, root.shown)
                return Math.max(0, Math.ceil((lo - root.minV) / (root.maxV - root.minV) * segCount - 0.5 - 1e-9))
            }
            readonly property int litTo: {
                const hi = Math.max(root.originV, root.shown)
                return Math.min(segCount - 1, Math.floor((hi - root.minV) / (root.maxV - root.minV) * segCount - 0.5 + 1e-9))
            }

            // 角度(度、0° が真上)→ Canvas の角度(ラジアン、0 が右)
            function rad(deg) { return (deg - 90) * Math.PI / 180 }
            function angOf(v) { return root.startAngle + root.frac(v) * root.sweepAngle }
            // セグメント i の中央の値
            function segValue(i) { return root.minV + (root.maxV - root.minV) * (i + 0.5) / segCount }
            // セグメント i を描く(角度は弧の上の位置)
            function drawSeg(ctx, i, R, color) {
                const d0 = root.startAngle + i * segDeg + segGap / 2
                const d1 = root.startAngle + (i + 1) * segDeg - segGap / 2
                ctx.strokeStyle = color
                ctx.beginPath()
                ctx.arc(cx, cy, R * dims.trackR, rad(d0), rad(d1))
                ctx.stroke()
            }

            // ---- 目盛り・警告帯(設定・大きさ・配色が変わったときだけ描き直す) ----
            Canvas {
                id: face
                anchors.fill: parent
                renderStrategy: Canvas.Cooperative
                readonly property string key: [width, height, dial.cx, dial.cy, dial.rpx, root.minV, root.maxV, root.warnV,
                                               root.warnOn, root.warnBelow, root.labelDiv, root.dialStyle, root.startAngle,
                                               root.endAngle, root.compact, Theme.panel, Theme.panelBorder, Theme.textSecondary,
                                               Theme.textPrimary, Theme.error, Theme.accent, Theme.fontFamily].join("|")
                onKeyChanged: requestPaint()

                // 大目盛りの間隔。1 / 2 / 5 × 10^n(と 0.25)から、数字が詰まりすぎない最小のものを選ぶ
                function niceStep(range, maxMajors) {
                    const c = []
                    for (let e = -2; e <= 5; ++e) {
                        const p = Math.pow(10, e)
                        c.push(p, 2 * p)
                        if (e === -1) c.push(0.25)
                        c.push(5 * p)
                    }
                    c.sort((a, b) => a - b)
                    for (let i = 0; i < c.length; ++i) {
                        if (range / c[i] <= maxMajors) return c[i]
                    }
                    return c[c.length - 1]
                }

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const R = dial.rpx, cx = dial.cx, cy = dial.cy, dm = dial.dims
                    if (R <= 1) return
                    const a0 = dial.rad(root.startAngle), a1 = dial.rad(root.endAngle)
                    const angV = (v) => dial.rad(dial.angOf(v))
                    const zoneColor = Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.35)

                    if (root.dialStyle === "classic") {
                        // 外周の細い線
                        ctx.lineCap = "butt"
                        ctx.lineWidth = R * dm.trackW
                        ctx.strokeStyle = Theme.panelBorder
                        ctx.beginPath()
                        ctx.arc(cx, cy, R * dm.trackR, a0, a1)
                        ctx.stroke()
                        // 警告ゾーン: 目盛りの外側に赤い帯
                        if (root.hasWarnZone) {
                            ctx.lineWidth = R * 0.04
                            ctx.strokeStyle = Theme.error
                            ctx.beginPath()
                            ctx.arc(cx, cy, R * 0.905, angV(root.zoneLo), angV(root.zoneHi))
                            ctx.stroke()
                        }
                    } else if (root.dialStyle === "minimal") {
                        ctx.lineCap = "round"
                        ctx.lineWidth = R * dm.trackW
                        ctx.strokeStyle = Theme.panelBorder
                        ctx.beginPath()
                        ctx.arc(cx, cy, R * dm.trackR, a0, a1)
                        ctx.stroke()
                        if (root.hasWarnZone) {
                            ctx.lineCap = "butt"
                            ctx.strokeStyle = zoneColor
                            ctx.beginPath()
                            ctx.arc(cx, cy, R * dm.trackR, angV(root.zoneLo), angV(root.zoneHi))
                            ctx.stroke()
                        }
                    } else {
                        // スポーツ: 消灯したセグメント(警告ゾーンは赤みを帯びる)
                        ctx.lineCap = "butt"
                        ctx.lineWidth = R * dm.trackW
                        for (let i = 0; i < dial.segCount; ++i) {
                            dial.drawSeg(ctx, i, R, root.inZone(dial.segValue(i)) ? zoneColor
                                                                                  : Theme.mix(Theme.panel, Theme.panelBorder, 0.9))
                        }
                    }

                    // 内側の細い円(全種類共通。数字の内側の区切り)
                    ctx.lineCap = "butt"
                    ctx.lineWidth = Math.max(1, R * 0.008)
                    ctx.strokeStyle = Theme.panelBorder
                    ctx.beginPath()
                    ctx.arc(cx, cy, R * dm.ringR, a0, a1)
                    ctx.stroke()

                    // 目盛り(大目盛りに数字。0 は強調)
                    const range = root.maxV - root.minV
                    // 小型表示は数字が大きいぶん間引く
                    const maxMajors = root.compact ? Math.max(3, Math.round(root.sweepAngle / 55))
                                                   : Math.max(4, Math.round(root.sweepAngle / 30))
                    const step = niceStep(range / root.labelDiv, maxMajors) * root.labelDiv
                    const stepShown = step / root.labelDiv
                    const dec = stepShown >= 1 ? 0 : (Math.abs(stepShown * 10 - Math.round(stepShown * 10)) < 1e-6 ? 1 : 2)
                    const minor = root.compact ? step : step / dm.sub   // 小型表示は大目盛りだけ
                    const first = Math.ceil(root.minV / minor - 1e-9)
                    ctx.lineCap = "butt"
                    ctx.textAlign = "center"
                    ctx.textBaseline = "middle"
                    const px = Math.max(9, Math.round(R * dm.labelPx * (root.compact ? 1.25 : 1)))
                    ctx.font = "bold " + px + "px '" + Theme.fontFamily + "'"
                    for (let n = first; n * minor <= root.maxV + 1e-9; ++n) {
                        const v = n * minor
                        const isMajor = Math.abs(v / step - Math.round(v / step)) < 1e-6
                        const isZero = Math.abs(v) < 1e-9
                        const inWarn = root.inZone(v)
                        const a = angV(v)
                        ctx.lineWidth = R * (isMajor ? dm.majorW : dm.minorW)
                        ctx.strokeStyle = inWarn ? Theme.error
                                                 : (isZero ? Theme.accent : (isMajor ? Theme.textPrimary : Theme.textSecondary))
                        ctx.beginPath()
                        ctx.moveTo(cx + Math.cos(a) * R * (isMajor ? dm.majorIn : dm.minorIn), cy + Math.sin(a) * R * (isMajor ? dm.majorIn : dm.minorIn))
                        ctx.lineTo(cx + Math.cos(a) * R * dm.tickOut, cy + Math.sin(a) * R * dm.tickOut)
                        ctx.stroke()
                        if (isMajor) {
                            ctx.fillStyle = inWarn ? Theme.error : (isZero || root.dialStyle === "sport" ? Theme.textPrimary : Theme.textSecondary)
                            ctx.fillText((isZero ? 0 : v / root.labelDiv).toFixed(dec),
                                         cx + Math.cos(a) * R * dm.labelR, cy + Math.sin(a) * R * dm.labelR)
                        }
                    }
                }
            }

            // ---- 進捗(シンプル: 細いリング / スポーツ: 点灯するセグメント)。0 から現在値まで ----
            Canvas {
                id: progress
                anchors.fill: parent
                visible: root.dialStyle !== "classic"
                renderStrategy: Canvas.Cooperative
                readonly property string key: !visible ? "" :
                    [width, height, dial.rpx,
                     root.dialStyle === "sport" ? dial.litFrom + ":" + dial.litTo : dial.angOf(root.shown).toFixed(1),
                     root.minV, root.maxV, root.warnV, root.warnOn,
                     root.warnBelow, root.dialStyle, root.startAngle, root.endAngle, Theme.accent, Theme.warn,
                     Theme.error].join("|")
                onKeyChanged: if (visible) requestPaint()

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const R = dial.rpx, dm = dial.dims
                    if (R <= 1) return
                    const lo = Math.min(root.originV, root.shown), hi = Math.max(root.originV, root.shown)
                    ctx.lineCap = "butt"
                    ctx.lineWidth = R * dm.trackW

                    if (root.dialStyle === "sport") {
                        // 警告値の手前(範囲の 10%)は注意色、警告ゾーンは警告色
                        const near = (root.maxV - root.minV) * 0.1
                        const colorOf = (v) => {
                            if (root.inZone(v)) return Theme.error
                            if (root.hasWarnZone && (root.warnBelow ? v <= root.warnV + near : v >= root.warnV - near)) return Theme.warn
                            return Theme.accent
                        }
                        // 光彩(shadowBlur)は描画が重いので使わない。点灯している範囲だけ描く
                        for (let i = dial.litFrom; i <= dial.litTo; ++i) {
                            dial.drawSeg(ctx, i, R, colorOf(dial.segValue(i)))
                        }
                        return
                    }

                    if (dial.angOf(hi) - dial.angOf(lo) < 0.2) return
                    const seg = (from, to, color) => {
                        if (to <= from) return
                        ctx.strokeStyle = color
                        ctx.beginPath()
                        ctx.arc(dial.cx, dial.cy, R * dm.trackR, dial.rad(dial.angOf(from)), dial.rad(dial.angOf(to)))
                        ctx.stroke()
                    }
                    if (root.hasWarnZone) {
                        // 警告ゾーンと重なる部分だけ警告色
                        const zLo = Math.max(lo, root.zoneLo), zHi = Math.min(hi, root.zoneHi)
                        if (zHi > zLo) {
                            seg(lo, zLo, Theme.accent)
                            seg(zLo, zHi, Theme.error)
                            seg(zHi, hi, Theme.accent)
                            return
                        }
                    }
                    seg(lo, hi, Theme.accent)
                }
            }

            // ---- 針(先細りの形。回転だけで値に追従し、形は大きさ・色が変わったときだけ描き直す) ----
            Item {
                id: needle
                x: dial.cx
                y: dial.cy
                width: 0
                height: 0
                rotation: dial.angOf(root.shown)

                Canvas {
                    id: needleShape
                    readonly property real tip: dial.rpx * dial.dims.needleTip
                    readonly property real tail: root.needleTail ? dial.rpx * 0.22 : 0
                    readonly property real base: Math.max(4, dial.rpx * (root.dialStyle === "sport" ? 0.055 : 0.07))
                    readonly property color needleFill: root.warning ? Theme.error : root.needleColor
                    x: -width / 2
                    y: -tip
                    width: Math.ceil(base + 2)
                    height: Math.ceil(tip + tail + 2)
                    renderStrategy: Canvas.Cooperative
                    readonly property string key: [width, height, tip, tail, base, needleFill].join("|")
                    onKeyChanged: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const c = width / 2
                        const tipHalf = Math.max(0.75, base * 0.1)
                        const baseHalf = base / 2
                        const tailHalf = base * 0.32
                        ctx.fillStyle = needleFill
                        ctx.beginPath()
                        ctx.moveTo(c - tipHalf, 0)
                        ctx.lineTo(c + tipHalf, 0)
                        ctx.lineTo(c + baseHalf, tip)
                        if (tail > 0) {
                            ctx.lineTo(c + tailHalf, tip + tail)
                            ctx.lineTo(c - tailHalf, tip + tail)
                        }
                        ctx.lineTo(c - baseHalf, tip)
                        ctx.closePath()
                        ctx.fill()
                    }
                }
            }

            // ---- 名前(中心円の上、内側の細い円の内側。針はこの上を通る) ----
            Row {
                id: dialLabel
                visible: root.labelVisible
                readonly property real h: dial.rpx * (root.compact ? 0.15 : 0.13)
                readonly property real cyU: -Math.max(root.hubSize / 2 + 0.1, 0.32)   // 中心からの位置(半径比)
                // 内側の細い円(半径 0.6)に収まる幅
                readonly property real maxW: 2 * Math.sqrt(Math.max(0.01, 0.58 * 0.58 - cyU * cyU)) * dial.rpx
                x: dial.cx - width / 2
                y: dial.cy + cyU * dial.rpx - h / 2
                height: h
                spacing: h * 0.25
                opacity: root.labelOpacity
                MaterialIcon {
                    id: dialLabelIcon
                    visible: root.showIcon
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.labelIcon
                    size: dialLabel.h
                    color: root.warning ? Theme.error : Theme.accent
                    opacity: root.warning ? root.blink : 1
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, dialLabel.maxW - (root.showIcon ? dialLabel.h + dialLabel.spacing : 0))
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.pixelSize: Math.max(10, dialLabel.h * 0.78)
                    elide: Text.ElideRight
                    color: root.labelColor
                    text: root.labelText
                }
            }

            // ---- 中心円 ----
            Rectangle {
                x: dial.cx - width / 2
                y: dial.cy - height / 2
                width: dial.rpx * root.hubSize
                height: width
                radius: width / 2
                color: root.hubColor
                border.width: Math.max(1, dial.rpx * 0.02)
                border.color: root.warning ? Theme.error : (root.dialStyle === "sport" ? Theme.accent : Theme.panelBorder)
                Rectangle {   // 針の色の芯
                    anchors.centerIn: parent
                    width: Math.min(parent.width * 0.32, dial.rpx * 0.06)
                    height: width
                    radius: width / 2
                    color: root.warning ? Theme.error : root.needleColor
                }
            }

            // ---- デジタル表示(アナログ+デジタル) ----
            Column {
                visible: root.style === "both"
                x: dial.cx + dial.readout.x * dial.rpx
                y: dial.cy + dial.readout.y * dial.rpx
                width: dial.readout.w * dial.rpx
                height: dial.readout.h * dial.rpx
                Text {
                    width: parent.width
                    height: parent.height * 0.7
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.italic: true   // 数値は全種類で太字の斜体
                    font.pixelSize: 300
                    minimumPixelSize: 12
                    fontSizeMode: Text.Fit
                    text: root.fmt(root.shown, root.decimals)
                    color: root.valueColor
                }
                Text {
                    width: parent.width
                    height: parent.height * 0.3
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignTop
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(11, dial.rpx * 0.13)
                    text: root.unitText
                    color: Theme.textSecondary
                }
            }

            // ---- 単位(アナログのみ) ----
            Text {
                visible: root.style === "analog"
                x: dial.cx - width / 2
                y: dial.cy + dial.unitY * dial.rpx - height / 2
                font.family: Theme.fontFamily
                font.pixelSize: Math.max(11, dial.rpx * 0.13)
                text: dial.scaleUnitText
                color: Theme.textSecondary
            }
        }

        // ============================================================ デジタルのみ: 大きな数字と横バー
        Item {
            id: digital
            visible: root.style === "digital"
            anchors.fill: parent

            readonly property real barH: Math.max(8, root.s * 0.045)
            readonly property real scaleH: root.compact ? 0 : Math.round(root.titleFontSize * 0.8) + 4

            // 名前(警告中は警告メッセージ)
            Row {
                id: digitalLabel
                visible: root.labelVisible
                anchors { top: parent.top; left: parent.left }
                width: parent.width - mockTag.width - 8
                height: visible ? Math.max(root.titleBarHeight, Math.round(digital.height * 0.12)) : 0
                spacing: 8
                opacity: root.labelOpacity
                MaterialIcon {
                    visible: root.showIcon
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.labelIcon
                    size: digitalLabel.height * 0.9
                    color: root.warning ? Theme.error : Theme.accent
                    opacity: root.warning ? root.blink : 1
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, digitalLabel.width - (root.showIcon ? digitalLabel.height + digitalLabel.spacing : 0))
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.pixelSize: Math.max(11, digitalLabel.height * 0.72)
                    elide: Text.ElideRight
                    color: root.labelColor
                    text: root.labelText
                }
            }

            // 数値 + 単位(数値の右下に単位)
            Item {
                id: valueBox
                anchors { top: digitalLabel.bottom; left: parent.left; right: parent.right; bottom: barBox.top
                          bottomMargin: root.m * 0.5 }
                Text {
                    id: valueText
                    anchors { left: parent.left; right: unitLabel.left; top: parent.top; bottom: parent.bottom
                              rightMargin: 6 }
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.italic: true
                    font.pixelSize: 300
                    minimumPixelSize: 14
                    fontSizeMode: Text.Fit
                    text: root.fmt(root.shown, root.decimals)
                    color: root.valueColor
                }
                Text {
                    id: unitLabel
                    anchors { right: parent.right; baseline: valueText.baseline }
                    width: Math.max(implicitWidth, parent.width * 0.18)
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(14, Math.min(valueBox.height * 0.3, 40))
                    text: root.unitText
                    color: Theme.textSecondary
                }
            }

            // 横バー(0 から現在値まで塗る。警告ゾーン・0 の目印つき)と、両端の値
            Item {
                id: barBox
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: digital.barH + digital.scaleH + 4

                Item {
                    id: bar
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: digital.barH
                    readonly property real originX: width * root.frac(root.originV)
                    readonly property real valueX: width * root.frac(root.shown)

                    Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.panelBorder }
                    Rectangle {   // 警告ゾーン
                        visible: root.hasWarnZone
                        x: bar.width * root.frac(root.zoneLo)
                        width: bar.width * root.frac(root.zoneHi) - x
                        height: parent.height
                        radius: height / 2
                        color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.4)
                    }
                    Rectangle {   // 現在値
                        x: Math.min(bar.originX, bar.valueX)
                        width: Math.max(2, Math.abs(bar.valueX - bar.originX))
                        height: parent.height
                        radius: height / 2
                        color: root.warning ? Theme.error : Theme.accent
                    }
                    Rectangle {   // 0 の目印
                        visible: root.originV > root.minV && root.originV < root.maxV
                        x: bar.originX - width / 2
                        y: -2
                        width: 2
                        height: parent.height + 4
                        color: Theme.textPrimary
                        opacity: 0.6
                    }
                }
                Text {
                    visible: !root.compact
                    anchors { left: parent.left; top: bar.bottom; topMargin: 4 }
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.round(root.titleFontSize * 0.8)
                    color: root.warnOn && root.warnBelow ? Theme.error : Theme.textSecondary
                    text: root.fmt(root.minV, root.unitDef.stepDec)
                }
                Text {
                    visible: !root.compact
                    anchors { right: parent.right; top: bar.bottom; topMargin: 4 }
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.round(root.titleFontSize * 0.8)
                    color: root.warnOn && !root.warnBelow ? Theme.error : Theme.textSecondary
                    text: root.fmt(root.maxV, root.unitDef.stepDec)
                }
            }
        }
    }

    // ================================================================ 警告メッセージ(警告中だけ、メーターの下側に重ねて表示)
    Rectangle {
        id: warnBanner
        z: 3
        visible: opacity > 0
        opacity: root.warning ? (0.55 + 0.45 * root.blink) : 0
        Behavior on opacity { enabled: !root.warning; NumberAnimation { duration: 180 } }
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: root.m }
        width: Math.min(parent.width - 2 * root.m,
                        warnText.implicitWidth + (root.showIcon ? height * 0.62 + 6 : 0) + height)
        height: root.compact ? Math.max(20, Math.round(root.s * 0.17)) : Math.max(26, Math.round(root.s * 0.13))
        radius: height / 2
        color: Theme.mix(Theme.panel, Theme.error, 0.22)
        border.width: 2
        border.color: Theme.error
        Row {
            id: warnRow
            anchors.centerIn: parent
            spacing: 6
            MaterialIcon {
                visible: root.showIcon
                anchors.verticalCenter: parent.verticalCenter
                name: "warning"
                size: warnBanner.height * 0.62
                color: Theme.error
            }
            Text {
                id: warnText
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, warnBanner.width - warnBanner.height - (root.showIcon ? warnBanner.height * 0.62 + 6 : 0))
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: Math.max(12, Math.round(warnBanner.height * 0.5))
                elide: Text.ElideRight
                color: Theme.error
                text: root.config.warnMessage || "警告"
            }
        }
    }
}
