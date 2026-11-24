// 警告灯パネル: 純正の警告灯のように、値ごとの状態を並べる。状態は 設定 > 車両 > 警告・注意 のルール(AlertRules)の判定そのまま
// (2 = 警告: 赤で点滅 / 1 = 注意: 黄 / 0 = 正常 / データなし: 灰色)。
// config:
//   items       並べるもの: 計測値の id と、"dtc"(故障コード。現在のもの = 警告、過去の記録だけ = 注意)・"mil"(チェックランプ)
//   lampStyle   "readable"(見やすさ優先: 枠・名前・数値) / "dash"(ダッシュボード風: 暗い面に記号だけが光る)
//   okStyle     正常のとき: "green"(緑で光る) / "quiet"(暗く表示) / "hidden"(出さない。注意・警告のものだけ並ぶ)
//   showNames   名前を出すか / showValues 数値を出すか(故障コードは件数、チェックランプは点灯・消灯)
//   hideNoData  データが来ていないものを出さないか
// 並びは、出すものの数とウィジェットの形から列数を自動で決める。出すものが無いとき(正常を出さない設定ですべて正常)は「異常なし」
import QtQuick
import OpenCruise

WidgetBase {
    id: root

    readonly property var items: (Array.isArray(config.items) ? config.items : [])
                                 .filter(k => k === "dtc" || k === "mil" || !!WidgetRegistry.gaugeSpecs[k])
    readonly property bool dash: config.lampStyle === "dash"
    readonly property string okStyle: ["green", "quiet", "hidden"].indexOf(config.okStyle) >= 0 ? config.okStyle : "green"
    readonly property bool showValues: config.showValues !== false
    readonly property bool showNames: config.showNames !== false
    readonly property bool hideNoData: config.hideNoData === true
    readonly property real m: root.innerMargin
    readonly property real gap: Math.max(dash ? 2 : 4, Math.round(s * (dash ? 0.02 : 0.035)))

    // ---- 状態 ----
    function hasOf(k) {
        if (k === "dtc" || k === "mil") return ecu.available
        return WidgetRegistry.metricHas(k)
    }
    function levelOf(k) {
        if (!hasOf(k)) return 0
        if (k === "dtc") return ecu.currentDtcCount > 0 ? 2 : (ecu.pastDtcCount > 0 ? 1 : 0)
        if (k === "mil") return ecu.milOn ? 2 : 0
        AlertRules.stateRevision
        return AlertRules.levelFor(k)
    }
    // 出すもの。値が来るたびに並びを作り直すと点滅などが途切れるので、並びが変わったときだけ入れ替える
    readonly property string shownKey: {
        ecu.revision; ecu.currentDtcCount; ecu.pastDtcCount; ecu.milOn; AlertRules.stateRevision; can.dataAvailable
        return items.filter(k => (!hideNoData || hasOf(k)) && (okStyle !== "hidden" || levelOf(k) > 0)).join(",")
    }
    property var shown: []
    onShownKeyChanged: shown = shownKey === "" ? [] : shownKey.split(",")
    Component.onCompleted: shown = shownKey === "" ? [] : shownKey.split(",")

    // 列数: マスがなるべく横長(見やすさ優先は 横:縦 ≒ 1.3、ダッシュボード風は正方形)で大きくなるように
    readonly property int cols: {
        const n = Math.max(1, shown.length), W = width - 2 * m, H = height - 2 * m, aspect = dash ? 1.0 : 1.3
        let best = 1, score = -1
        for (let c = 1; c <= n; ++c) {
            const r = Math.ceil(n / c)
            const cw = (W - (c - 1) * gap) / c, ch = (H - (r - 1) * gap) / r
            const sc = Math.min(cw / aspect, ch)
            if (sc > score) { score = sc; best = c }
        }
        return best
    }
    readonly property int rowsN: Math.ceil(Math.max(1, shown.length) / cols)

    readonly property bool anyWarn: { shownKey; return shown.some(k => levelOf(k) === 2) }
    property real blink: 1
    SequentialAnimation on blink {
        running: root.anyWarn && root.onScreen && !root.lifting
        loops: Animation.Infinite
        NumberAnimation { to: 0.3; duration: 380; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 380; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.blink = 1
    }

    // 何も無いとき
    Column {
        visible: root.shown.length === 0
        anchors.centerIn: parent
        width: parent.width - 2 * root.m
        spacing: 4
        readonly property bool allOk: root.items.length > 0
        MaterialIcon {
            visible: parent.allOk
            anchors.horizontalCenter: parent.horizontalCenter
            name: "check_circle"
            size: Math.round(Math.min(root.height * 0.35, root.width * 0.2))
            color: root.okStyle === "hidden" ? Theme.ok : Theme.textSecondary
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.family: Theme.fontFamily
            font.pixelSize: root.bodyFontSize
            color: Theme.textSecondary
            text: !parent.allOk ? "設定で並べる値を選んでください"
                  : root.okStyle === "hidden" ? "異常なし" : "データが来ていません"
        }
    }

    Grid {
        id: grid
        anchors { fill: parent; margins: root.m }
        columns: root.cols
        spacing: root.gap
        readonly property real cellW: (width - (root.cols - 1) * spacing) / root.cols
        readonly property real cellH: (height - (root.rowsN - 1) * spacing) / root.rowsN
        Repeater {
            model: root.shown
            Item {
                id: lamp
                required property string modelData
                readonly property bool isDtc: modelData === "dtc"
                readonly property bool isMil: modelData === "mil"
                readonly property var spec: isDtc || isMil ? null : WidgetRegistry.gaugeSpecs[modelData]
                readonly property var def: spec ? WidgetRegistry.metricDefaults(modelData) : null
                readonly property bool has: root.hasOf(modelData)
                readonly property int level: { root.shownKey; ecu.revision; return root.levelOf(modelData) }
                // 光っているか(正常の「暗く表示」は光らせない)
                readonly property bool lit: has && (level > 0 || root.okStyle === "green")
                readonly property color col: level === 2 ? Theme.error : level === 1 ? Theme.warn : Theme.ok
                readonly property color fg: lit ? col : Theme.mix(Theme.panel, Theme.textSecondary, has ? 0.55 : 0.3)
                readonly property string title: isDtc ? "故障コード" : isMil ? "チェックランプ" : spec.title
                readonly property string icon: isDtc ? "mdi:car-wrench" : isMil ? "mdi:engine-outline" : spec.icon
                readonly property string valueText: {
                    if (!has) return "--"
                    if (isDtc) return ecu.currentDtcCount > 0 ? ecu.currentDtcCount + " 件" : (ecu.pastDtcCount > 0 ? "過去 " + ecu.pastDtcCount : "なし")
                    if (isMil) return ecu.milOn ? "点灯" : "消灯"
                    ecu.revision
                    const u = def.unit || spec.units[0]
                    const v = WidgetRegistry.metricValue(modelData) * u.scale + (u.offset || 0)
                    return v.toFixed(u.dec) + " " + u.label
                }
                width: grid.cellW
                height: grid.cellH
                opacity: level === 2 ? 0.4 + 0.6 * root.blink : 1

                // ---- 見やすさ優先: 枠・塗り・名前・数値 ----
                Rectangle {
                    visible: !root.dash
                    anchors.fill: parent
                    radius: Math.min(Theme.radius + 2, height * 0.25)
                    color: lamp.lit ? Theme.mix(Theme.panel, lamp.col, lamp.level === 0 ? 0.14 : 0.26)
                                    : Theme.mix(Theme.panel, Theme.background, 0.5)
                    border.width: lamp.level > 0 ? 2 : 1.5
                    border.color: lamp.lit ? Theme.mix(Theme.panel, lamp.col, 0.9) : Theme.mix(Theme.panel, Theme.panelBorder, 0.8)
                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 8
                        spacing: 1
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 4
                            readonly property real px: Math.max(10, Math.min(lamp.height * (root.showValues && root.showNames ? 0.26 : 0.34),
                                                                             lamp.width * 0.16, root.bodyFontSize * 1.1))
                            MaterialIcon {
                                // 名前を出さないときは記号を大きく
                                visible: !root.showNames || lamp.width > lamp.height * 1.4 || !root.showValues
                                anchors.verticalCenter: parent.verticalCenter
                                name: lamp.icon
                                size: root.showNames ? parent.px * 1.15 : Math.min(lamp.height * (root.showValues ? 0.45 : 0.6), lamp.width * 0.5)
                                color: lamp.fg
                            }
                            Text {
                                visible: root.showNames
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, lamp.width - 12 - parent.px * 1.3)
                                font.family: Theme.fontFamily
                                font.bold: true
                                font.pixelSize: parent.px
                                elide: Text.ElideRight
                                color: lamp.fg
                                text: lamp.title
                            }
                        }
                        Text {
                            visible: root.showValues
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            font.family: Theme.numberFontFamily
                            font.pixelSize: Math.max(10, Math.min(lamp.height * 0.24, lamp.width * 0.15, root.bodyFontSize))
                            elide: Text.ElideRight
                            color: lamp.has ? Theme.textPrimary : Theme.textSecondary
                            text: lamp.valueText
                        }
                    }
                }

                // ---- ダッシュボード風: 暗い面に記号だけが光る(名前・数値は小さく下に) ----
                Item {
                    visible: root.dash
                    anchors.fill: parent
                    readonly property real textH: (root.showNames ? 1 : 0) + (root.showValues ? 1 : 0)
                    readonly property real px: Math.max(9, Math.min(lamp.height * 0.15, lamp.width * 0.14))
                    // 光のにじみ(注意・警告のときだけ)
                    Rectangle {
                        visible: lamp.has && lamp.level > 0
                        anchors.centerIn: dashIcon
                        width: dashIcon.size * 1.2
                        height: width
                        radius: width / 2
                        color: lamp.col
                        opacity: 0.2
                    }
                    MaterialIcon {
                        id: dashIcon
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: (parent.height - parent.textH * parent.px * 1.25 - size) / 2
                        name: lamp.icon
                        size: Math.round(Math.min(parent.width * 0.62, (parent.height - parent.textH * parent.px * 1.25) * 0.8))
                        color: lamp.fg
                    }
                    Column {
                        anchors { top: dashIcon.bottom; left: parent.left; right: parent.right }
                        Text {
                            visible: root.showNames
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            font.family: Theme.fontFamily
                            font.pixelSize: parent.parent.px
                            elide: Text.ElideRight
                            color: lamp.lit ? lamp.col : Theme.textSecondary
                            text: lamp.title
                        }
                        Text {
                            visible: root.showValues
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            font.family: Theme.numberFontFamily
                            font.pixelSize: parent.parent.px
                            elide: Text.ElideRight
                            color: lamp.has ? Theme.textPrimary : Theme.textSecondary
                            text: lamp.valueText
                        }
                    }
                }
            }
        }
    }
}
