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
    readonly property bool usePsi: config.unit === "psi"
    readonly property real k: usePsi ? 14.5038 : 1.0           // bar → 表示単位
    readonly property string unitText: usePsi ? "psi" : "bar"
    readonly property real minV: config.min * k
    readonly property real maxV: Math.max(config.max * k, minV + 0.1)
    readonly property real warnV: config.warn * k
    readonly property bool warnOn: config.warnEnabled === true
    readonly property bool showIcon: config.showIcon !== false
    readonly property int decimals: usePsi ? 1 : 2

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

    // ---- 上段: アイコンと名称 ----
    Row {
        id: header
        anchors { top: parent.top; left: parent.left; topMargin: root.m; leftMargin: root.m }
        spacing: 8
        height: Math.max(22, root.s * 0.075)
        MaterialIcon {
            visible: root.showIcon
            anchors.verticalCenter: parent.verticalCenter
            name: root.warning ? "warning" : "speed"
            size: parent.height
            color: root.warning ? Theme.error : Theme.accent
            opacity: root.warning ? root.blink : 1
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily
            text: "ブースト"
            color: Theme.textSecondary
            font.pixelSize: Math.max(13, root.s * 0.055)
        }
    }
    Rectangle {   // モックデータ中の表示
        anchors { verticalCenter: header.verticalCenter; right: parent.right; rightMargin: root.m }
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
            font.pixelSize: Math.max(10, root.s * 0.035)
        }
    }

    // ---- 下段: 警告メッセージ(警告値の案内と兼用。高さは常に確保して、警告の出入りで配置が動かないようにする) ----
    Item {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                  leftMargin: root.m; rightMargin: root.m; bottomMargin: root.m * 0.8 }
        height: Math.max(26, root.s * 0.095)
        visible: root.warnOn

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
            font.pixelSize: Math.max(13, root.s * 0.055)
            elide: Text.ElideRight
            color: root.warning ? Theme.error : Theme.textSecondary
            text: root.warning
                  ? ((root.showIcon ? "⚠ " : "") + (root.config.warnMessage || "警告"))
                  : "警告値 " + root.warnV.toFixed(root.decimals) + " " + root.unitText
        }
    }

    // ---- 本体 ----
    Item {
        id: bodyBox
        anchors {
            top: header.bottom; left: parent.left; right: parent.right
            bottom: root.warnOn ? footer.top : parent.bottom
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
                property real vMin: root.minV
                property real vMax: root.maxV
                property real vWarn: root.warnV
                property bool wOn: root.warnOn
                property string fam: Theme.fontFamily
                onCTrackChanged: requestPaint()
                onCTextChanged: requestPaint()
                onCMajorChanged: requestPaint()
                onCWarnChanged: requestPaint()
                onVMinChanged: requestPaint()
                onVMaxChanged: requestPaint()
                onVWarnChanged: requestPaint()
                onWOnChanged: requestPaint()
                onFamChanged: requestPaint()
                onWidthChanged: requestPaint()

                // 135° から時計回りに 270°(下が開いた形)
                readonly property real a0: Math.PI * 0.75
                readonly property real sweep: Math.PI * 1.5

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
                    if (wOn && vWarn < vMax) {
                        ctx.strokeStyle = cWarn
                        ctx.beginPath()
                        ctx.arc(cx, cy, tr, ang(Math.max(vWarn, vMin)), a0 + sweep)
                        ctx.stroke()
                    }

                    // 目盛り(大目盛りに数字、間に小目盛り 4 本)
                    const step = niceStep(range)
                    const dec = step >= 1 ? 0 : (step >= 0.1 ? 1 : 2)
                    const minor = step / 5
                    const first = Math.ceil(vMin / minor - 1e-9)
                    for (let n = first; n * minor <= vMax + 1e-9; ++n) {
                        const v = n * minor
                        const isMajor = Math.abs(v / step - Math.round(v / step)) < 1e-6
                        const a = ang(v)
                        const inner = R * (isMajor ? 0.72 : 0.78)
                        const outer = R * 0.83
                        ctx.lineWidth = isMajor ? R * 0.025 : R * 0.012
                        ctx.strokeStyle = (wOn && v >= vWarn - 1e-9) ? cWarn : (isMajor ? cMajor : cText)
                        ctx.beginPath()
                        ctx.moveTo(cx + Math.cos(a) * inner, cy + Math.sin(a) * inner)
                        ctx.lineTo(cx + Math.cos(a) * outer, cy + Math.sin(a) * outer)
                        ctx.stroke()
                        if (isMajor) {
                            ctx.fillStyle = (wOn && v >= vWarn - 1e-9) ? cWarn : cText
                            ctx.font = "bold " + Math.round(R * 0.11) + "px '" + fam + "'"
                            ctx.textAlign = "center"
                            ctx.textBaseline = "middle"
                            const lr = R * 0.6
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
                rotation: -135 + root.frac(root.shown) * 270
                Rectangle {
                    x: -width / 2
                    y: -dial.r * 0.8
                    width: Math.max(3, dial.r * 0.045)
                    height: dial.r * 0.8 + dial.r * 0.12
                    radius: width / 2
                    color: root.warning ? Theme.error : Theme.accent
                }
            }
            Rectangle {   // 針の軸
                anchors.centerIn: parent
                width: dial.r * 0.16
                height: width
                radius: width / 2
                color: Theme.panel
                border.width: Math.max(2, dial.r * 0.03)
                border.color: root.warning ? Theme.error : Theme.accent
            }

            // デジタル表示(アナログ+デジタルのときだけ。下の開いた部分に置く)
            Column {
                visible: root.style === "both"
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.verticalCenter; topMargin: dial.r * 0.3 }
                spacing: 0
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.pixelSize: Math.max(16, dial.r * 0.38)
                    text: root.shown.toFixed(root.decimals)
                    color: root.valueColor
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(11, dial.r * 0.14)
                    text: root.unitText
                    color: Theme.textSecondary
                }
            }
        }

        // ===== デジタルのみ: 大きな数字と横バー =====
        Item {
            visible: root.style === "digital"
            anchors.fill: parent

            Column {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
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
                    font.pixelSize: Math.max(12, root.s * 0.075)
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
