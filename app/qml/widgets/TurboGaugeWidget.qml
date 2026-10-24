// ターボ圧計。実際のブースト計のように、アナログ(目盛り・針・警告ゾーン)とデジタル(数値)を組み合わせたメーター。
// 値は can.boostBar(現状はモック)。設定は bar 基準で保存され、表示と編集のときだけ psi に換算する。
//  - 表示方式: アナログ+デジタル / アナログ / デジタル
//  - メーターの種類: クラシック(目盛り+警告帯) / シンプル(細いリング) / スポーツ(太い進捗リング)
//  - 最小値・最大値・単位(bar/psi)・開始/終了角度・数値の配置・針の出っ張り・中心円の大きさと色・針の色
//  - アイコン表示・警告値・警告メッセージ
// 警告値以上になると、針と数値が赤になり、アイコンと警告メッセージが点滅する(解除は警告値より少し下がったとき)。
//
// レイアウトの考え方:
//  1. 見出し(上)・警告欄(下、警告が有効なときだけ高さを確保)を除いた残りを本体とする
//  2. アナログは「半径 1 の円」で、弧・中心円・数値表示が実際に占める範囲(外接矩形)を求め、
//     その矩形が本体に最大で収まる半径 R を決める(弧の欠けている側の余白を無駄にしない)
//  3. 目盛り(静的)・進捗リング(値に追従)・針は別々に描き、値が変わっても目盛りは描き直さない
import QtQuick
import OpenCruise

WidgetBase {
    id: root

    // ---------------------------------------------------------------- 設定(表示単位に換算済み)
    readonly property string style: config.style === "analog" || config.style === "digital" ? config.style : "both"
    readonly property string dialStyle: config.dialStyle === "minimal" || config.dialStyle === "sport" ? config.dialStyle : "classic"
    readonly property bool usePsi: config.unit === "psi"
    readonly property real k: usePsi ? 14.5038 : 1.0           // bar → 表示単位
    readonly property string unitText: usePsi ? "psi" : "bar"
    readonly property real minV: Number(config.min) * k
    readonly property real maxV: Math.max(Number(config.max) * k, minV + 0.1)
    readonly property real warnV: Number(config.warn) * k
    readonly property bool warnOn: config.warnEnabled === true
    readonly property bool showIcon: config.showIcon !== false
    readonly property real startAngle: Math.max(-180, Math.min(-90, config.startAngle === undefined ? -135 : Number(config.startAngle)))
    readonly property real endAngle: Math.max(90, Math.min(180, config.endAngle === undefined ? 135 : Number(config.endAngle)))
    readonly property real sweepAngle: endAngle - startAngle
    readonly property bool autoLabelPosition: config.autoLabelPosition !== false
    readonly property bool needleTail: config.needleTail !== false
    readonly property real hubSize: Math.max(0.08, Math.min(0.32, (config.hubSize || 16) / 100))   // 直径 / 半径
    readonly property color needleColor: configuredColor("needleColor", Theme.accent)
    readonly property color hubColor: configuredColor("hubColor", Theme.panel)
    readonly property int decimals: usePsi ? 1 : 2

    function configuredColor(key, fallback) {
        const value = String(config[key] || "")
        if (value === "theme") return Theme.accent
        if (value === "panel") return Theme.panel
        return /^#[0-9a-f]{6}$/i.test(value) ? Qt.color(value) : fallback
    }

    // ---------------------------------------------------------------- 値
    readonly property real rawValue: can.boostBar * k
    // 針・数値は滑らかに追従させる(データは約 10Hz)
    property real shown: rawValue
    Behavior on shown { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

    function frac(v) { return Math.max(0, Math.min(1, (v - minV) / (maxV - minV))) }
    // 進捗の起点(大気圧 = 0)。範囲外なら近い端
    readonly property real originV: Math.max(minV, Math.min(maxV, 0))
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
        else if (!warning && rawValue >= warnV) warning = true
        else if (warning && rawValue < warnV - hysteresis) warning = false
    }
    onRawValueChanged: updateWarning()
    onWarnOnChanged: updateWarning()
    onWarnVChanged: updateWarning()
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

    // ================================================================ 見出し(他のウィジェットと同じ形・大きさ)
    Row {
        id: header
        visible: root.titleVisible
        anchors { top: parent.top; left: parent.left; topMargin: root.titleVisible ? root.m * 0.8 : 0; leftMargin: root.m }
        width: root.width - root.m * 2 - mockTag.width - 8
        height: root.titleVisible ? root.titleBarHeight : 0
        spacing: 8
        MaterialIcon {
            visible: root.showIcon
            anchors.verticalCenter: parent.verticalCenter
            name: root.warning ? "warning" : "speed"
            size: parent.height
            color: root.warning ? Theme.error : Theme.accent
            opacity: root.warning ? root.blink : 1
        }
        Text {
            width: Math.max(0, header.width - (root.showIcon ? header.height + header.spacing : 0))
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily
            font.pixelSize: root.titleFontSize
            color: Theme.textSecondary
            text: root.titleText("ブースト")
            elide: Text.ElideRight
        }
    }

    // モックデータ中の表示(見出しの右端。見出しを隠しているときも右上に出す)
    Rectangle {
        id: mockTag
        anchors { top: parent.top; right: parent.right; topMargin: root.m * 0.8; rightMargin: root.m }
        width: mockText.implicitWidth + 14
        height: Math.max(mockText.implicitHeight + 4, root.titleVisible ? root.titleBarHeight * 0.85 : 0)
        radius: height / 2
        color: "transparent"
        border.color: Theme.warn
        Text {
            id: mockText
            anchors.centerIn: parent
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(root.titleFontSize * 0.75)
            text: "モック"
            color: Theme.warn
        }
    }

    // ================================================================ 警告欄(警告が有効なときだけ高さを確保し、出入りで配置が動かない)
    Item {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                  leftMargin: root.m; rightMargin: root.m; bottomMargin: root.warnOn ? root.m * 0.7 : 0 }
        height: root.warnOn ? Math.max(22, root.titleBarHeight) : 0
        visible: root.warnOn

        // 警告中: 点滅する帯
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.16)
            border.color: Theme.error
            opacity: root.blink
            visible: root.warning
        }
        Row {
            visible: root.warning
            anchors.centerIn: parent
            spacing: 6
            MaterialIcon {
                visible: root.showIcon
                anchors.verticalCenter: parent.verticalCenter
                name: "warning"
                size: footer.height * 0.7
                color: Theme.error
                opacity: root.blink
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, footer.width - 24 - (root.showIcon ? footer.height : 0))
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: Math.round(root.titleFontSize * 0.9)
                elide: Text.ElideRight
                color: Theme.error
                text: root.config.warnMessage || "警告"
            }
        }
        // 平常時: 警告値の案内(控えめに)
        Text {
            visible: !root.warning
            anchors.centerIn: parent
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(root.titleFontSize * 0.8)
            elide: Text.ElideRight
            color: Theme.textSecondary
            text: "警告 " + root.fmt(root.warnV, root.decimals) + " " + root.unitText + " 以上"
        }
    }

    // ================================================================ 本体
    Item {
        id: body
        anchors { top: header.bottom; bottom: footer.top; left: parent.left; right: parent.right
                  topMargin: root.titleVisible ? root.m * 0.4 : root.m * 0.6
                  bottomMargin: root.m * 0.4; leftMargin: root.m; rightMargin: root.m }

        // ============================================================ アナログ
        Item {
            id: dial
            visible: root.style !== "digital"

            // ---- 半径 1 の円で考えた配置(中心が原点、0° が真上・時計回り) ----
            // 数値表示の枠。auto のときは弧の空き(開始と終了の間)の方向へ置き、中心円とは重ならないようにする
            readonly property var readout: {
                const w = 0.62, h = 0.4
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

            // メーターの種類ごとの寸法(R に対する比)
            readonly property var spec: root.dialStyle === "sport"
                ? { trackR: 0.93, trackW: 0.12, majorIn: 0.70, minorIn: 0.76, tickOut: 0.82, labelR: 0.59,
                    majorW: 0.03, minorW: 0.012, sub: 4, labelPx: 0.105, progress: true }
                : (root.dialStyle === "minimal"
                   ? { trackR: 0.95, trackW: 0.035, majorIn: 0.80, minorIn: 0.85, tickOut: 0.89, labelR: 0.66,
                       majorW: 0.022, minorW: 0.01, sub: 2, labelPx: 0.11, progress: true }
                   : { trackR: 0.955, trackW: 0.03, majorIn: 0.72, minorIn: 0.79, tickOut: 0.86, labelR: 0.62,
                       majorW: 0.025, minorW: 0.012, sub: 5, labelPx: 0.095, progress: false })

            // 角度(度、0° が真上)→ Canvas の角度(ラジアン、0 が右)
            function rad(deg) { return (deg - 90) * Math.PI / 180 }
            function angOf(v) { return root.startAngle + root.frac(v) * root.sweepAngle }

            // ---- 目盛り・警告帯(設定・大きさ・配色が変わったときだけ描き直す) ----
            Canvas {
                id: face
                anchors.fill: parent
                renderStrategy: Canvas.Cooperative
                readonly property string key: [width, height, dial.cx, dial.cy, dial.rpx, root.minV, root.maxV, root.warnV,
                                               root.warnOn, root.dialStyle, root.startAngle, root.endAngle,
                                               Theme.panelBorder, Theme.textSecondary, Theme.textPrimary, Theme.error,
                                               Theme.accent, Theme.fontFamily].join("|")
                onKeyChanged: requestPaint()

                function niceStep(range) {
                    const c = [0.1, 0.2, 0.25, 0.5, 1, 2, 2.5, 5, 10, 20, 25, 50, 100]
                    for (let i = 0; i < c.length; ++i) {
                        if (range / c[i] <= 7) return c[i]
                    }
                    return 100
                }

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const R = dial.rpx, cx = dial.cx, cy = dial.cy, sp = dial.spec
                    if (R <= 1) return
                    const a0 = dial.rad(root.startAngle), a1 = dial.rad(root.endAngle)
                    const angV = (v) => dial.rad(dial.angOf(v))
                    const warnFrom = Math.max(root.warnV, root.minV)
                    const hasWarn = root.warnOn && root.warnV < root.maxV

                    // 文字盤の帯(クラシックのみ。弧の形に沿った薄い面で、円が途中で切れないようにする)
                    if (root.dialStyle === "classic") {
                        ctx.lineCap = "round"
                        ctx.lineWidth = R * 0.2
                        ctx.strokeStyle = Theme.mix(Theme.panel, Theme.panelBorder, 0.35)
                        ctx.beginPath()
                        ctx.arc(cx, cy, R * 0.82, a0, a1)
                        ctx.stroke()
                    }

                    // 外周のトラック
                    ctx.lineCap = root.dialStyle === "classic" ? "butt" : "round"
                    ctx.lineWidth = R * sp.trackW
                    ctx.strokeStyle = Theme.panelBorder
                    ctx.beginPath()
                    ctx.arc(cx, cy, R * sp.trackR, a0, a1)
                    ctx.stroke()

                    // 警告ゾーン
                    if (hasWarn) {
                        if (root.dialStyle === "classic") {
                            // 目盛りの外側に赤い帯
                            ctx.lineCap = "butt"
                            ctx.lineWidth = R * 0.05
                            ctx.strokeStyle = Theme.error
                            ctx.beginPath()
                            ctx.arc(cx, cy, R * 0.89, angV(warnFrom), a1)
                            ctx.stroke()
                        } else {
                            // トラックの警告側を赤く染める
                            ctx.lineCap = "butt"
                            ctx.lineWidth = R * sp.trackW
                            ctx.strokeStyle = Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.35)
                            ctx.beginPath()
                            ctx.arc(cx, cy, R * sp.trackR, angV(warnFrom), a1)
                            ctx.stroke()
                        }
                    }

                    // 目盛り(大目盛りに数字。0 は強調)
                    const range = root.maxV - root.minV
                    const step = niceStep(range)
                    const dec = step >= 1 ? 0 : (Math.abs(step * 10 - Math.round(step * 10)) < 1e-6 ? 1 : 2)
                    const minor = step / sp.sub
                    const first = Math.ceil(root.minV / minor - 1e-9)
                    ctx.lineCap = "butt"
                    ctx.textAlign = "center"
                    ctx.textBaseline = "middle"
                    const px = Math.max(9, Math.round(R * sp.labelPx))
                    for (let n = first; n * minor <= root.maxV + 1e-9; ++n) {
                        const v = n * minor
                        const isMajor = Math.abs(v / step - Math.round(v / step)) < 1e-6
                        const isZero = Math.abs(v) < 1e-9
                        const inWarn = hasWarn && v >= root.warnV - 1e-9
                        const a = angV(v)
                        const inner = R * (isMajor ? sp.majorIn : sp.minorIn)
                        const outer = R * sp.tickOut
                        ctx.lineWidth = R * (isMajor ? sp.majorW : sp.minorW)
                        ctx.strokeStyle = inWarn ? Theme.error
                                                 : (isZero ? Theme.accent : (isMajor ? Theme.textPrimary : Theme.textSecondary))
                        ctx.beginPath()
                        ctx.moveTo(cx + Math.cos(a) * inner, cy + Math.sin(a) * inner)
                        ctx.lineTo(cx + Math.cos(a) * outer, cy + Math.sin(a) * outer)
                        ctx.stroke()
                        if (isMajor) {
                            ctx.fillStyle = inWarn ? Theme.error : (isZero ? Theme.textPrimary : Theme.textSecondary)
                            ctx.font = "bold " + px + "px '" + Theme.fontFamily + "'"
                            ctx.fillText((isZero ? 0 : v).toFixed(dec),
                                         cx + Math.cos(a) * R * sp.labelR, cy + Math.sin(a) * R * sp.labelR)
                        }
                    }
                }
            }

            // ---- 進捗リング(シンプル・スポーツ。0 から現在値まで。警告値より上は警告色) ----
            Canvas {
                id: progress
                anchors.fill: parent
                visible: dial.spec.progress
                renderStrategy: Canvas.Cooperative
                readonly property string key: !visible ? "" :
                    [width, height, dial.rpx, root.shown.toFixed(3), root.minV, root.maxV, root.warnV, root.warnOn,
                     root.dialStyle, root.startAngle, root.endAngle, Theme.accent, Theme.error].join("|")
                onKeyChanged: if (visible) requestPaint()

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const R = dial.rpx, sp = dial.spec
                    if (R <= 1) return
                    const lo = Math.min(root.originV, root.shown), hi = Math.max(root.originV, root.shown)
                    if (dial.angOf(hi) - dial.angOf(lo) < 0.2) return
                    const seg = (from, to, color) => {
                        if (to <= from) return
                        ctx.strokeStyle = color
                        ctx.beginPath()
                        ctx.arc(dial.cx, dial.cy, R * sp.trackR, dial.rad(dial.angOf(from)), dial.rad(dial.angOf(to)))
                        ctx.stroke()
                    }
                    ctx.lineCap = "butt"
                    ctx.lineWidth = R * sp.trackW
                    if (root.warnOn && root.warnV < hi) {
                        seg(lo, Math.max(lo, root.warnV), Theme.accent)
                        seg(Math.max(lo, root.warnV), hi, Theme.error)
                    } else {
                        seg(lo, hi, Theme.accent)
                    }
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
                    readonly property real tip: dial.rpx * (root.dialStyle === "sport" ? 0.84 : 0.88)
                    readonly property real tail: root.needleTail ? dial.rpx * 0.22 : 0
                    readonly property real base: Math.max(4, dial.rpx * 0.07)
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

            // ---- 中心円 ----
            Rectangle {
                x: dial.cx - width / 2
                y: dial.cy - height / 2
                width: dial.rpx * root.hubSize
                height: width
                radius: width / 2
                color: root.hubColor
                border.width: Math.max(1, dial.rpx * 0.02)
                border.color: root.warning ? Theme.error : Theme.panelBorder
                Rectangle {   // 針の色の芯
                    anchors.centerIn: parent
                    width: parent.width * 0.32
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
                    height: parent.height * 0.72
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.pixelSize: 300
                    minimumPixelSize: 12
                    fontSizeMode: Text.Fit
                    text: root.fmt(root.shown, root.decimals)
                    color: root.valueColor
                }
                Text {
                    width: parent.width
                    height: parent.height * 0.28
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignTop
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(9, dial.rpx * 0.09)
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
                font.pixelSize: Math.max(9, dial.rpx * 0.09)
                text: root.unitText
                color: Theme.textSecondary
            }
        }

        // ============================================================ デジタルのみ: 大きな数字と横バー
        Item {
            id: digital
            visible: root.style === "digital"
            anchors.fill: parent

            readonly property real barH: Math.max(8, root.s * 0.045)
            readonly property real scaleH: Math.round(root.titleFontSize * 0.8) + 4

            // 数値 + 単位(数値の右下に単位)
            Item {
                id: valueBox
                anchors { top: parent.top; left: parent.left; right: parent.right; bottom: barBox.top
                          bottomMargin: root.m * 0.5 }
                Text {
                    id: valueText
                    anchors { left: parent.left; right: unitLabel.left; top: parent.top; bottom: parent.bottom
                              rightMargin: 6 }
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    font.family: Theme.fontFamily
                    font.bold: true
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
                    font.pixelSize: Math.max(12, Math.min(valueBox.height * 0.22, 28))
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
                        visible: root.warnOn && root.warnV < root.maxV
                        x: bar.width * root.frac(root.warnV)
                        width: bar.width - x
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
                    anchors { left: parent.left; top: bar.bottom; topMargin: 4 }
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.round(root.titleFontSize * 0.8)
                    color: Theme.textSecondary
                    text: root.fmt(root.minV, root.usePsi ? 0 : 1)
                }
                Text {
                    anchors { right: parent.right; top: bar.bottom; topMargin: 4 }
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.round(root.titleFontSize * 0.8)
                    color: root.warnOn ? Theme.error : Theme.textSecondary
                    text: root.fmt(root.maxV, root.usePsi ? 0 : 1)
                }
            }
        }
    }
}
