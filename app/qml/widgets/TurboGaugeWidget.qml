// ターボ圧計。実際のブースト計のように、アナログ(目盛り・針・警告ゾーン)とデジタル(数値)を組み合わせたメーター。
// 値は can.boostBar(現状はモック)。設定は bar 基準で保存され、表示と編集のときだけ psi に換算する。
//  - 表示方式: アナログ+デジタル / アナログ / デジタル
//  - 最小値・最大値・単位(bar/psi)・アイコン表示・警告値・警告メッセージ
// 警告値以上になると、針と数値が赤になり、アイコンと警告メッセージが点滅する(解除は警告値より少し下がったとき)。
import QtQuick
import OpenCruise

WidgetBase {
    id: root

    // ---- 設定(表示単位に換算済み) ----
    readonly property string style: config.style === "analog" || config.style === "digital" ? config.style : "both"
    readonly property string dialStyle: config.dialStyle === "minimal" || config.dialStyle === "sport" ? config.dialStyle : "classic"
    readonly property bool usePsi: config.unit === "psi"
    readonly property real k: usePsi ? 14.5038 : 1.0           // bar → 表示単位
    readonly property string unitText: usePsi ? "psi" : "bar"
    readonly property real minV: config.min * k
    readonly property real maxV: Math.max(config.max * k, minV + 0.1)
    readonly property real warnV: config.warn * k
    readonly property bool warnOn: config.warnEnabled === true
    readonly property bool showIcon: config.showIcon !== false
    readonly property real startAngle: Math.max(-180, Math.min(-90, config.startAngle === undefined ? -135 : Number(config.startAngle)))
    readonly property real endAngle: Math.max(90, Math.min(180, config.endAngle === undefined ? 135 : Number(config.endAngle)))
    readonly property real sweepAngle: endAngle - startAngle
    readonly property bool autoLabelPosition: config.autoLabelPosition !== false
    readonly property bool needleTail: config.needleTail !== false
    readonly property real hubSize: Math.max(0.08, Math.min(0.32, (config.hubSize || 16) / 100))
    readonly property color needleColor: configuredColor("needleColor", Theme.accent)
    readonly property color hubColor: configuredColor("hubColor", Theme.panel)
    readonly property int decimals: usePsi ? 1 : 2

    function configuredColor(key, fallback) {
        const value = String(config[key] || "")
        if (value === "theme") return Theme.accent
        if (value === "panel") return Theme.panel
        return /^#[0-9a-f]{6}$/i.test(value) ? Qt.color(value) : fallback
    }

    // ---- 値(針は滑らかに動かす) ----
    readonly property real rawValue: can.boostBar * k
    property real shown: rawValue
    Behavior on shown { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    function frac(v) { return Math.max(0, Math.min(1, (v - minV) / (maxV - minV))) }

    // ---- 警告(ヒステリシスつき) ----
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
    readonly property real m: Math.max(10, root.s * 0.05)

    // 点滅(警告中だけ動かす)
    property real blink: 1
    SequentialAnimation on blink {
        running: root.warning && !root.lifting
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 380; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 380; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.blink = 1
    }

    Rectangle {   // モックデータ中の表示
        anchors { top: parent.top; right: parent.right; topMargin: root.m; rightMargin: root.m }
        width: mockTag.implicitWidth + 14
        height: mockTag.implicitHeight + 6
        radius: height / 2
        color: "transparent"
        border.color: Theme.warn
        Text {
            id: mockTag
            anchors.centerIn: parent
            font.family: Theme.fontFamily
            text: "モック"
            color: Theme.warn
            font.pixelSize: root.detailFontSize
        }
    }

    // ---- 下段: 警告メッセージ(警告値の案内と兼用。高さは常に確保して、警告の出入りで配置が動かないようにする) ----
    Item {
        id: footer
        z: 1
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                  leftMargin: root.m; rightMargin: root.m; bottomMargin: root.m * 0.8 }
        height: root.warning ? Math.max(26, root.s * 0.095) : 0
        visible: root.warning

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.18)
            border.color: Theme.error
            opacity: root.warning ? root.blink : 0
            visible: opacity > 0
        }
        Text {
            anchors.centerIn: parent
            width: parent.width - 20
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.fontFamily
            font.bold: root.warning
            font.pixelSize: root.bodyFontSize
            elide: Text.ElideRight
            color: root.warning ? Theme.error : Theme.textSecondary
            text: (root.showIcon ? "⚠ " : "") + (root.config.warnMessage || "警告")
        }
    }

    // ---- 本体 ----
    Item {
        id: bodyBox
        anchors {
            top: parent.top; left: parent.left; right: parent.right
            bottom: parent.bottom
            margins: root.m * 0.5
        }

        // ===== アナログ(アナログ+デジタル / アナログ) =====
        Item {
            id: dial
            visible: root.style !== "digital"
            readonly property real size: Math.min(bodyBox.width, bodyBox.height)
            readonly property real r: size / 2
            width: size
            height: size
            anchors.centerIn: parent

            // 目盛り・警告ゾーン(設定・サイズ・配色が変わったときだけ描き直す)
            Canvas {
                id: face
                anchors.fill: parent
                property color cTrack: Theme.panelBorder
                property color cText: Theme.textSecondary
                property color cMajor: Theme.textPrimary
                property color cWarn: Theme.error
                property color cAccent: Theme.accent
                property real vMin: root.minV
                property real vMax: root.maxV
                property real vWarn: root.warnV
                property real vShown: root.shown
                property bool wOn: root.warnOn
                property string faceStyle: root.dialStyle
                property string fam: Theme.fontFamily
                onCTrackChanged: requestPaint()
                onCTextChanged: requestPaint()
                onCMajorChanged: requestPaint()
                onCWarnChanged: requestPaint()
                onCAccentChanged: requestPaint()
                onVMinChanged: requestPaint()
                onVMaxChanged: requestPaint()
                onVWarnChanged: requestPaint()
                onVShownChanged: requestPaint()
                onWOnChanged: requestPaint()
                onFaceStyleChanged: requestPaint()
                onFamChanged: requestPaint()
                onWidthChanged: requestPaint()

                // 設定した開始角度から時計回りに描画。値表示は開始・終了角の間の空きへ置く。
                property real startDegrees: root.startAngle
                property real sweepDegrees: root.sweepAngle
                readonly property real a0: (startDegrees - 90) * Math.PI / 180
                readonly property real sweep: sweepDegrees * Math.PI / 180
                onStartDegreesChanged: requestPaint()
                onSweepDegreesChanged: requestPaint()

                function niceStep(range) {
                    const c = [0.1, 0.2, 0.25, 0.5, 1, 2, 2.5, 5, 10, 20, 25, 50, 100]
                    for (let i = 0; i < c.length; ++i) {
                        if (range / c[i] <= 8) return c[i]
                    }
                    return 100
                }

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const R = width / 2
                    if (R <= 0) return
                    const cx = R, cy = R
                    const range = vMax - vMin
                    const ang = (v) => a0 + sweep * Math.max(0, Math.min(1, (v - vMin) / range))

                    // 外周のトラックと警告ゾーン
                    const tr = R * 0.9
                    ctx.lineCap = "butt"
                    ctx.lineWidth = R * 0.06
                    ctx.strokeStyle = cTrack
                    ctx.beginPath()
                    ctx.arc(cx, cy, tr, a0, a0 + sweep)
                    ctx.stroke()
                    if (faceStyle === "sport" && vShown > vMin) {
                        ctx.strokeStyle = cAccent
                        ctx.beginPath()
                        ctx.arc(cx, cy, tr, a0, ang(vShown))
                        ctx.stroke()
                    }
                    if (wOn && vWarn < vMax) {
                        ctx.strokeStyle = cWarn
                        ctx.beginPath()
                        ctx.arc(cx, cy, tr, ang(Math.max(vWarn, vMin)), a0 + sweep)
                        ctx.stroke()
                    }

                    // 目盛り(大目盛りに数字、間に小目盛り 4 本)
                    const step = niceStep(range)
                    const dec = step >= 1 ? 0 : (step >= 0.1 ? 1 : 2)
                    const subdivisions = faceStyle === "minimal" ? 2 : (faceStyle === "sport" ? 4 : 5)
                    const minor = step / subdivisions
                    const first = Math.ceil(vMin / minor - 1e-9)
                    for (let n = first; n * minor <= vMax + 1e-9; ++n) {
                        const v = n * minor
                        const isMajor = Math.abs(v / step - Math.round(v / step)) < 1e-6
                        const a = ang(v)
                        const inner = R * (isMajor ? 0.72 : (faceStyle === "minimal" ? 0.8 : 0.78))
                        const outer = R * (faceStyle === "minimal" ? 0.85 : 0.83)
                        ctx.lineWidth = isMajor ? R * (faceStyle === "sport" ? 0.032 : 0.025)
                                                : R * (faceStyle === "minimal" ? 0.008 : 0.012)
                        ctx.strokeStyle = (wOn && v >= vWarn - 1e-9) ? cWarn : (isMajor ? cMajor : cText)
                        ctx.beginPath()
                        ctx.moveTo(cx + Math.cos(a) * inner, cy + Math.sin(a) * inner)
                        ctx.lineTo(cx + Math.cos(a) * outer, cy + Math.sin(a) * outer)
                        ctx.stroke()
                        if (isMajor) {
                            ctx.fillStyle = (wOn && v >= vWarn - 1e-9) ? cWarn : cText
                            ctx.font = "bold " + Math.max(9, Math.round(R * (faceStyle === "minimal" ? 0.095 : 0.085))) + "px '" + fam + "'"
                            ctx.textAlign = "center"
                            ctx.textBaseline = "middle"
                            const lr = R * (faceStyle === "sport" ? 0.58 : 0.6)
                            ctx.fillText((Math.abs(v) < 1e-9 ? 0 : v).toFixed(dec), cx + Math.cos(a) * lr, cy + Math.sin(a) * lr)
                        }
                    }
                }
            }

            // 針(中心に回転軸。値の変化はスムージング済みの shown に追従する)
            Item {
                id: needle
                x: dial.r
                y: dial.r
                width: 0
                height: 0
                rotation: root.startAngle + root.frac(root.shown) * root.sweepAngle
                Rectangle {
                    x: -width / 2
                    y: -dial.r * 0.8
                    width: Math.max(3, dial.r * 0.045)
                    height: dial.r * (root.needleTail ? 0.92 : 0.8)
                    radius: width / 2
                    color: root.warning ? Theme.error : root.needleColor
                }
            }
            Rectangle {   // 針の軸
                anchors.centerIn: parent
                width: dial.r * root.hubSize
                height: width
                radius: width / 2
                color: root.hubColor
                border.width: Math.max(1, dial.r * 0.025)
                border.color: root.warning ? Theme.error : Theme.panelBorder
            }

            // ゲージの見出しは針の中心より少し上に重ねて表示する。
            Row {
                id: dialTitle
                visible: root.titleVisible
                anchors.horizontalCenter: parent.horizontalCenter
                y: dial.r * 0.57
                width: Math.min(dial.width * 0.74, 260)
                height: Math.max(18, dial.r * 0.16)
                spacing: Math.max(4, dial.r * 0.04)
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radius
                    color: Theme.panel
                    opacity: 0.92
                    border.color: Theme.panelBorder
                }
                MaterialIcon {
                    visible: root.showIcon
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.warning ? "warning" : "speed"
                    size: Math.min(parent.height * 0.8, dial.r * 0.14)
                    color: root.warning ? Theme.error : Theme.accent
                    opacity: root.warning ? root.blink : 1
                }
                Text {
                    width: Math.max(0, dialTitle.width - (root.showIcon ? dialTitle.height * 0.8 + dialTitle.spacing : 0))
                    height: parent.height
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(10, Math.min(root.headerFontSize, dial.r * 0.13))
                    font.bold: true
                    color: Theme.textPrimary
                    text: root.titleText("ブースト")
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
            }

            // デジタル表示(アナログ+デジタルのときだけ。針軸から離して外側へ配置)
            Column {
                visible: root.style === "both"
                readonly property real gapAngle: (root.endAngle - 90 + (360 - root.sweepAngle) / 2) * Math.PI / 180
                readonly property real gapRadius: dial.r * 0.72
                readonly property bool horizontalGap: Math.abs(Math.cos(gapAngle)) > Math.abs(Math.sin(gapAngle))
                readonly property real hubClearance: dial.r * root.hubSize / 2 + dial.r * 0.06
                width: horizontalGap ? dial.r * 0.73 : Math.min(dial.width * 0.82, dial.r * 1.6)
                height: dial.r * 0.46
                x: root.autoLabelPosition
                   ? (horizontalGap && Math.cos(gapAngle) > 0
                      ? Math.max(0, Math.min(dial.width - width - dial.r * 0.05,
                                             Math.max(dial.r + hubClearance, dial.r + Math.cos(gapAngle) * gapRadius - width / 2)))
                      : (horizontalGap ? Math.max(0, Math.min(dial.width - width - dial.r * 0.05,
                                                              Math.min(dial.r - hubClearance - width,
                                                                       dial.r + Math.cos(gapAngle) * gapRadius - width / 2)))
                         : Math.max(0, Math.min(dial.width - width - dial.r * 0.05, dial.r + Math.cos(gapAngle) * gapRadius - width / 2))))
                   : (dial.width - width) / 2
                y: root.autoLabelPosition
                   ? (!horizontalGap && Math.sin(gapAngle) > 0
                      ? Math.min(dial.height - height - dial.r * 0.05,
                                 Math.max(dial.r + hubClearance, dial.r + Math.sin(gapAngle) * gapRadius - height / 2))
                      : (!horizontalGap ? Math.max(0, Math.min(dial.r - hubClearance - height,
                                                               dial.r + Math.sin(gapAngle) * gapRadius - height / 2))
                         : Math.max(0, Math.min(dial.height - height - dial.r * 0.05,
                                                dial.r + Math.sin(gapAngle) * gapRadius - height / 2))))
                   : dial.r + dial.r * 0.4
                spacing: 0
                Text {
                    width: parent.width
                    height: dial.r * 0.34
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.pixelSize: 300
                    minimumPixelSize: 14
                    fontSizeMode: Text.Fit
                    text: root.shown.toFixed(root.decimals)
                    color: root.valueColor
                }
                Text {
                    width: parent.width
                    height: dial.r * 0.12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(9, dial.r * 0.11)
                    text: root.unitText
                    color: Theme.textSecondary
                }
            }
        }

        // ===== デジタルのみ: 大きな数字と横バー =====
        Item {
            visible: root.style === "digital"
            anchors.fill: parent

            Row {
                visible: root.titleVisible
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
                width: Math.min(parent.width * 0.8, 260)
                height: Math.max(20, root.s * 0.11)
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
                    width: Math.max(0, parent.width - (root.showIcon ? parent.height + parent.spacing : 0))
                    height: parent.height
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: root.headerFontSize
                    font.bold: true
                    text: root.titleText("ブースト")
                    color: Theme.textSecondary
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Column {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                anchors.verticalCenterOffset: root.titleVisible ? parent.height * 0.1 : 0
                spacing: root.m * 0.4
                Text {
                    width: parent.width
                    height: Math.max(30, bodyBox.height * 0.45)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.pixelSize: 300
                    minimumPixelSize: 14
                    fontSizeMode: Text.Fit
                    text: root.shown.toFixed(root.decimals)
                    color: root.valueColor
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: root.detailFontSize
                    text: root.unitText
                    color: Theme.textSecondary
                }
                Item {   // 横バー(警告ゾーンつき)
                    width: parent.width - root.m
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: Math.max(10, root.s * 0.05)
                    Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.panelBorder }
                    Rectangle {
                        visible: root.warnOn
                        x: parent.width * root.frac(root.warnV)
                        width: parent.width - x
                        height: parent.height
                        radius: height / 2
                        color: Theme.error
                        opacity: 0.55
                    }
                    Rectangle {
                        width: Math.max(parent.height, parent.width * root.frac(root.shown))
                        height: parent.height
                        radius: height / 2
                        color: root.warning ? Theme.error : Theme.accent
                    }
                }
            }
        }
    }
}
