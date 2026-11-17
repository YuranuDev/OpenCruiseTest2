// メーター(GaugeWidget)の設定。ジャンル(タブ)ごとに分ける:
//   表示(表示方式・種類・単位・範囲・アイコン・ピーク)/ 目盛り・針(角度・目盛りの分割・針と中心円)/ 警告・注意
// 警告・注意はメーターとは別のルール(AlertRules。設定 > 警告・注意)。ここでは、この計測値のルールの値とオン/オフだけ変えられる
// 計測値ごとの単位・範囲・刻みは WidgetRegistry.gaugeSpecs(config.metric)から取る。
// 値は基本単位(bar / rpm / km/h / ℃ / % / V)で保存し、表示と編集は選んだ単位で行う。
import QtQuick
import OpenCruise

WidgetSettingsBase {
    id: root

    readonly property var gauge: WidgetRegistry.gaugeSpecs[config.metric] || WidgetRegistry.gaugeSpecs.boost
    readonly property var unitDef: {
        const list = gauge.units
        for (let i = 0; i < list.length; ++i) {
            if (list[i].id === config.unit) return list[i]
        }
        return list[0]
    }
    readonly property int unitIndex: gauge.units.indexOf(unitDef)
    readonly property string suffix: " " + unitDef.label
    readonly property real step: unitDef.step
    readonly property int dec: unitDef.stepDec
    readonly property bool warnBelow: gauge.warnBelow === true
    // メーターの種類(以前の「スポーツ」「バンド」はマーカーとして扱う)
    readonly property var dialStyles: ["classic", "minimal", "marker", "retro", "neon", "ring"]
    readonly property string dialStyle: dialStyles.indexOf(config.dialStyle) >= 0 ? config.dialStyle
                                        : (config.dialStyle === "sport" || config.dialStyle === "band" ? "marker" : "classic")
    // 0 をまたぐ範囲のときは、マイナス側・プラス側で目盛りを分けられる(ターボ圧なら負圧・正圧)
    readonly property bool crossesZero: toShown(minBase) < 0 && toShown(maxBase) > 0
    readonly property real minBase: config.min !== undefined ? Number(config.min) : gauge.limitMin
    readonly property real maxBase: config.max !== undefined ? Number(config.max) : gauge.limitMax
    readonly property string negName: gauge.negLabel || "マイナス側"
    readonly property string posName: gauge.posLabel || "プラス側"
    readonly property bool splitOn: config.splitScale === true && crossesZero && config.style !== "digital"
    readonly property real startA: config.startAngle === undefined ? -135 : Number(config.startAngle)
    readonly property real endA: config.endAngle === undefined ? 135 : Number(config.endAngle)
    // 分けていないときの 0 の位置(分けたときの初期値)
    readonly property real linearZero: {
        const lo = toShown(minBase), hi = toShown(maxBase)
        return Math.round((startA + (0 - lo) / Math.max(1e-9, hi - lo) * (endA - startA)) / 5) * 5
    }
    // 目盛りの間隔は差の値なので、単位の倍率だけで換算する(基本単位で保存)
    function stepShown(key) { return Number(config[key]) > 0 ? Number(config[key]) * unitDef.scale : 0 }
    function saveStep(key, shownValue) { root.edit(key, Number((shownValue / unitDef.scale).toFixed(4))) }
    // 針と中心円が無い種類(マーカー・リング)
    readonly property bool needleless: dialStyle === "marker" || dialStyle === "ring"
    // 針の反対側の出っ張りの設定を出すか
    readonly property bool tailShown: config.style !== "digital" && !needleless && config.needleTail !== false
    // 「針と同じ」の見本の色(針の色の設定。テーマ・パネルはその色)
    readonly property color needleSwatch: {
        const v = String(config.needleColor || "theme")
        return v === "theme" ? Theme.accent : v === "panel" ? Theme.panel : v
    }
    readonly property var colorOptions: [
        { label: "テーマ", value: "theme" }, { label: "パネル", value: "panel" },
        { label: "白", value: "#ffffff" }, { label: "赤", value: "#f44336" },
        { label: "橙", value: "#ff9800" }, { label: "黄", value: "#ffeb3b" },
        { label: "緑", value: "#4caf50" }, { label: "青", value: "#2196f3" },
        { label: "紫", value: "#9c27b0" }
    ]

    // 基本単位 ⇔ 表示単位
    function toShown(base) { return Number(base) * unitDef.scale + (unitDef.offset || 0) }
    function toBase(shown) { return (shown - (unitDef.offset || 0)) / unitDef.scale }
    // 表示単位の値 → 基本単位に直して保存(換算の端数は丸める)
    function save(key, shownValue) {
        root.edit(key, Number(toBase(shownValue).toFixed(3)))
    }

    WidgetSettingsGroup {
        title: "表示"
        icon: "speed"

        SettingsRow {
            label: "表示方式"
            SettingsChoice {
                model: ["アナログ+デジタル", "アナログ", "デジタル"]
                currentIndex: root.config.style === "analog" ? 1 : (root.config.style === "digital" ? 2 : 0)
                onPicked: (i) => root.edit("style", i === 1 ? "analog" : (i === 2 ? "digital" : "both"))
            }
        }
        SettingsRow {
            visible: root.config.style !== "digital"
            label: "メーターの種類"
            description: "マーカーとリングは針を出さず、数値を中央に大きく表示します"
            SettingsChoice {
                model: ["クラシック", "シンプル", "マーカー", "レトロ", "ネオン", "リング"]
                currentIndex: root.dialStyles.indexOf(root.dialStyle)
                onPicked: (i) => root.edit("dialStyle", root.dialStyles[i])
            }
        }
        SettingsRow {
            visible: root.gauge.units.length > 1
            label: "単位"
            SettingsChoice {
                model: root.gauge.units.map(u => u.label)
                currentIndex: root.unitIndex
                onPicked: (i) => root.edit("unit", root.gauge.units[i].id)
            }
        }
        SettingsRow {
            label: root.gauge.minLabel || "最小値"
            description: root.gauge.minHint || ""
            WSStepper {
                value: root.toShown(root.config.min)
                from: root.toShown(root.gauge.limitMin)
                to: root.toShown(root.config.max - root.gauge.minSpan)
                step: root.step
                decimals: root.dec
                suffix: root.suffix
                onMoved: (v) => root.save("min", v)
            }
        }
        SettingsRow {
            label: "最大値"
            WSStepper {
                value: root.toShown(root.config.max)
                from: root.toShown(root.config.min + root.gauge.minSpan)
                to: root.toShown(root.gauge.limitMax)
                step: root.step
                decimals: root.dec
                suffix: root.suffix
                onMoved: (v) => root.save("max", v)
            }
        }
        SettingsRow {
            label: "オープニング表示"
            description: "針を最小値から最大値まで振ってから、今の値へ戻します。起動画面が消えたとき(データが来ていれば)と、データが無かったところへデータが来たときに行います"
            SettingsSwitch {
                checked: root.config.openingSweep !== false
                onToggled: (v) => root.edit("openingSweep", v)
            }
        }
        SettingsRow {
            label: "アイコンを表示"
            description: "警告中は警告マークに変わり、点滅します"
            SettingsSwitch {
                checked: root.config.showIcon !== false
                onToggled: (v) => root.edit("showIcon", v)
            }
        }
        SettingsRow {
            label: "ピーク表示"
            description: "数値の上に小さく出します。タップでリセットします(再起動してもリセットされます)"
            stacked: true
            SettingsChoice {
                model: ["オフ", "最大(MAX)", "最小(MIN)"]
                currentIndex: root.config.peakMode === "off" ? 0 : (root.config.peakMode === "min" ? 2 : 1)
                onPicked: (index) => root.edit("peakMode", ["off", "max", "min"][index])
            }
        }
    }

    WidgetSettingsGroup {
        title: "目盛り・針"
        icon: "architecture"
        available: root.config.style !== "digital"

        SettingsRow {
            visible: root.config.style !== "digital"
            label: "開始角度"
            WSStepper {
                value: root.config.startAngle === undefined ? -135 : root.config.startAngle
                from: -180
                to: -90
                step: 5
                suffix: "°"
                onMoved: (v) => root.edit("startAngle", v)
            }
        }
        SettingsRow {
            visible: root.config.style !== "digital"
            label: "終了角度"
            WSStepper {
                value: root.config.endAngle === undefined ? 135 : root.config.endAngle
                from: 90
                to: 180
                step: 5
                suffix: "°"
                onMoved: (v) => root.edit("endAngle", v)
            }
        }
        // 目盛りの間隔と細かい目盛り(分けないとき。すべてのメーター)
        SettingsRow {
            visible: !root.splitOn && root.dialStyle !== "ring"
            label: "目盛り間隔"
            description: "大目盛り(数字)の間隔。0 で自動"
            WSStepper {
                value: root.stepShown("majorStep")
                from: 0
                to: Math.max(root.step, root.toShown(root.maxBase) - root.toShown(root.minBase))
                step: root.step
                decimals: root.dec
                suffix: root.suffix
                onMoved: (v) => root.saveStep("majorStep", v)
            }
        }
        SettingsRow {
            visible: !root.splitOn && root.dialStyle !== "ring"
            label: "細かい目盛り"
            description: "大目盛りの間を何等分するか。0 でメーターの種類ごとの既定"
            WSStepper {
                value: Number(root.config.minorSub) || 0
                from: 0
                to: 10
                step: 1
                suffix: " 等分"
                onMoved: (v) => root.edit("minorSub", v)
            }
        }
        SettingsRow {
            visible: root.crossesZero && root.config.style !== "digital"
            label: root.negName + "と" + root.posName + "で目盛りを分ける"
            description: "0 の位置を境に、それぞれ別の縮尺と目盛りで描きます"
            SettingsSwitch {
                checked: root.config.splitScale === true
                onToggled: (v) => root.edit("splitScale", v)
            }
        }
        SettingsRow {
            visible: root.splitOn
            label: "0 の位置"
            WSStepper {
                value: root.config.zeroAngle !== undefined ? Number(root.config.zeroAngle) : root.linearZero
                from: root.startA + 10
                to: root.endA - 10
                step: 5
                suffix: "°"
                onMoved: (v) => root.edit("zeroAngle", v)
            }
        }
        SettingsRow {
            visible: root.splitOn
            label: root.negName + "の目盛り間隔"
            description: "大目盛り(数字)の間隔。0 で自動"
            WSStepper {
                value: root.stepShown("negStep")
                from: 0
                to: Math.max(root.step, -root.toShown(root.minBase))
                step: root.step
                decimals: root.dec
                suffix: root.suffix
                onMoved: (v) => root.saveStep("negStep", v)
            }
        }
        SettingsRow {
            visible: root.splitOn
            label: root.negName + "の細かい目盛り"
            description: "大目盛りの間を何等分するか。0 で自動"
            WSStepper {
                value: Number(root.config.negSub) || 0
                from: 0
                to: 10
                step: 1
                suffix: " 等分"
                onMoved: (v) => root.edit("negSub", v)
            }
        }
        SettingsRow {
            visible: root.splitOn
            label: root.posName + "の目盛り間隔"
            description: "大目盛り(数字)の間隔。0 で自動"
            WSStepper {
                value: root.stepShown("posStep")
                from: 0
                to: Math.max(root.step, root.toShown(root.maxBase))
                step: root.step
                decimals: root.dec
                suffix: root.suffix
                onMoved: (v) => root.saveStep("posStep", v)
            }
        }
        SettingsRow {
            visible: root.splitOn
            label: root.posName + "の細かい目盛り"
            description: "大目盛りの間を何等分するか。0 で自動"
            WSStepper {
                value: Number(root.config.posSub) || 0
                from: 0
                to: 10
                step: 1
                suffix: " 等分"
                onMoved: (v) => root.edit("posSub", v)
            }
        }
        SettingsRow {
            visible: root.splitOn
            label: root.negName + "の数字の大きさ"
            description: "0 の近くの数字の大きさ"
            WSStepper {
                value: Number(root.config.negFont) || 100
                from: 50
                to: 200
                step: 10
                suffix: " %"
                onMoved: (v) => root.edit("negFont", v)
            }
        }
        SettingsRow {
            visible: root.splitOn
            label: root.negName + "の端に向けた大きさの変化"
            description: "目盛りの端での数字の大きさ(0 の近くに対する割合)。100 % で一定、大きくすると端へ向けて大きくなります"
            WSStepper {
                value: Number(root.config.negFontEnd) || 100
                from: 50
                to: 200
                step: 10
                suffix: " %"
                onMoved: (v) => root.edit("negFontEnd", v)
            }
        }
        SettingsRow {
            visible: root.splitOn
            label: root.posName + "の数字の大きさ"
            description: "0 の近くの数字の大きさ"
            WSStepper {
                value: Number(root.config.posFont) || 100
                from: 50
                to: 200
                step: 10
                suffix: " %"
                onMoved: (v) => root.edit("posFont", v)
            }
        }
        SettingsRow {
            visible: root.splitOn
            label: root.posName + "の端に向けた大きさの変化"
            description: "目盛りの端での数字の大きさ(0 の近くに対する割合)。100 % で一定、大きくすると端へ向けて大きくなります"
            WSStepper {
                value: Number(root.config.posFontEnd) || 100
                from: 50
                to: 200
                step: 10
                suffix: " %"
                onMoved: (v) => root.edit("posFontEnd", v)
            }
        }
        SettingsRow {
            visible: root.config.style === "both" && !root.needleless
            label: "数値を空き位置に配置"
            description: "開始角度と終了角度の間の空きに現在値を表示します"
            SettingsSwitch {
                checked: root.config.autoLabelPosition !== false
                onToggled: (v) => root.edit("autoLabelPosition", v)
            }
        }
        SettingsRow {
            visible: root.config.style !== "digital" && !root.needleless
            label: "針の反対側の出っ張り"
            SettingsSwitch {
                checked: root.config.needleTail !== false
                onToggled: (v) => root.edit("needleTail", v)
            }
        }
        SettingsRow {
            visible: root.tailShown
            label: "出っ張りの長さ"
            description: "メーターの半径に対する割合"
            WSStepper {
                value: Number(root.config.tailLength) || 22
                from: 5
                to: 60
                step: 1
                suffix: "%"
                onMoved: (v) => root.edit("tailLength", v)
            }
        }
        SettingsRow {
            visible: root.tailShown
            label: "出っ張りの幅"
            description: "先の幅。針の根元の幅に対する割合(100% で根元と同じ幅)"
            WSStepper {
                value: Number(root.config.tailWidth) || 64
                from: 20
                to: 200
                step: 5
                suffix: "%"
                onMoved: (v) => root.edit("tailWidth", v)
            }
        }
        SettingsRow {
            visible: root.tailShown
            label: "出っ張りの色"
            description: "警告中は、決めた色に関係なく針・中心円と一緒に赤くなります"
            stacked: true
            SettingsColorPalette {
                width: Math.min(root.width, 620 * Theme.uiScale)
                options: [{ label: "針と同じ", value: "same", swatch: root.needleSwatch }].concat(root.colorOptions)
                selectedValue: root.config.tailColor || "same"
                onPicked: (v) => root.edit("tailColor", v)
            }
        }
        SettingsRow {
            visible: root.config.style !== "digital" && !root.needleless
            label: "中心円のサイズ"
            description: "メーターの半径に対する割合"
            WSStepper {
                value: root.config.hubSize || 16
                from: 8
                to: 50
                step: 2
                suffix: "%"
                onMoved: (v) => root.edit("hubSize", v)
            }
        }
        SettingsRow {
            visible: root.config.style !== "digital" && !root.needleless
            label: "中心円の色"
            stacked: true
            SettingsColorPalette {
                width: Math.min(root.width, 620 * Theme.uiScale)
                options: root.colorOptions
                selectedValue: root.config.hubColor || "panel"
                onPicked: (v) => root.edit("hubColor", v)
            }
        }
        SettingsRow {
            // 針の無いマーカー・リングは、針の代わりの三角の印・帯の色になる
            visible: root.config.style !== "digital"
            label: root.dialStyle === "marker" ? "印(三角)の色" : root.dialStyle === "ring" ? "リングの色" : "針の色"
            description: root.needleless ? (root.dialStyle === "marker" ? "警告の範囲では赤で表示します(注意の範囲では色を変えません)" : "警告・注意の範囲は警告色・注意色で表示します")
                                          : "警告中は、出っ張り・中心円と一緒に赤くなります(注意中は色を変えません)"
            stacked: true
            SettingsColorPalette {
                width: Math.min(root.width, 620 * Theme.uiScale)
                options: root.colorOptions
                selectedValue: root.config.needleColor || "theme"
                onPicked: (v) => root.edit("needleColor", v)
            }
        }
        SettingsRow {
            visible: root.config.style !== "digital" && root.dialStyle === "marker"
            label: "線の色"
            description: "0 から印までの線。警告・注意の範囲は警告色・注意色で表示します"
            stacked: true
            SettingsColorPalette {
                width: Math.min(root.width, 620 * Theme.uiScale)
                options: root.colorOptions
                selectedValue: root.config.lineColor || "theme"
                onPicked: (v) => root.edit("lineColor", v)
            }
        }
    }

    // 警告・注意は 設定 > 警告・注意 のルール(AlertRules)が出す(メーターが無くても動く)。
    // ここでは、この計測値を使うルールの オン/オフ と値だけを変えられる(値の範囲はメーターの目盛りに関係なく、計測値の限界まで)
    WidgetSettingsGroup {
        title: "警告・注意"
        icon: "warning"
        active: root.config.showAlerts !== false && root.metricRules.some(r => r.enabled)

        SettingsRow {
            label: "警告・注意をこのメーターに表示"
            description: "この計測値のルールの範囲を目盛りに描き、警告・注意になったら色・点滅・メッセージで知らせます。"
                         + "オフにしても、警告音・通知は(ルールの設定どおり)出ます"
            SettingsSwitch {
                checked: root.config.showAlerts !== false
                onToggled: (v) => root.edit("showAlerts", v)
            }
        }
        // 件数だけを model にする(値を変えるたびに作り直さない。長押しの連続変化が途切れないように)
        Repeater {
            model: root.metricRules.length
            SettingsRow {
                id: ruleRow
                required property int index
                readonly property var modelData: root.metricRules[index] || root.metricRules[0]
                // 値を変える条件(この計測値の最初の条件)
                readonly property int condIndex: modelData.conditions.findIndex(c => c.source === root.config.metric)
                readonly property var cond: modelData.conditions[condIndex]
                readonly property bool twoValues: cond.op === "outside" || cond.op === "inside"
                label: (modelData.level === "warn" ? "警告: " : "注意: ") + modelData.message
                description: { AlertRules.stateRevision
                    return AlertRules.summary(modelData) + (AlertRules.isActive(modelData.id) ? "  ・ 今出ています" : "") }
                stacked: true
                Row {
                    spacing: 20 * Theme.uiScale
                    SettingsSwitch {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: ruleRow.modelData.enabled
                        onToggled: (v) => AlertRules.updateRule(ruleRow.modelData.id, { enabled: v })
                    }
                    WSStepper {
                        anchors.verticalCenter: parent.verticalCenter
                        value: root.toShown(ruleRow.cond.value)
                        from: root.toShown(root.gauge.limitMin)
                        to: root.toShown(root.gauge.limitMax)
                        step: root.step
                        decimals: root.dec
                        suffix: root.suffix
                        onMoved: (v) => AlertRules.updateCondition(ruleRow.modelData.id, ruleRow.condIndex,
                                                                   { value: Number(root.toBase(v).toFixed(3)) })
                    }
                    Text {
                        visible: ruleRow.twoValues
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.fontFamily
                        font.pixelSize: 24 * Theme.uiScale
                        color: Theme.textSecondary
                        text: "〜"
                    }
                    WSStepper {
                        visible: ruleRow.twoValues
                        anchors.verticalCenter: parent.verticalCenter
                        value: root.toShown(ruleRow.cond.value2)
                        from: root.toShown(root.gauge.limitMin)
                        to: root.toShown(root.gauge.limitMax)
                        step: root.step
                        decimals: root.dec
                        suffix: root.suffix
                        onMoved: (v) => AlertRules.updateCondition(ruleRow.modelData.id, ruleRow.condIndex,
                                                                   { value2: Number(root.toBase(v).toFixed(3)) })
                    }
                }
            }
        }
        SettingsRow {
            label: "この計測値のルールを追加"
            description: "条件・音・通知・続いた時間などの細かい設定は 設定 > 車両 > 警告・注意 で変えます"
            stacked: true
            Row {
                spacing: 12 * Theme.uiScale
                ActionButton { text: "警告を追加"; onClicked: AlertRules.addRule(root.config.metric, "warn") }
                ActionButton { text: "注意を追加"; onClicked: AlertRules.addRule(root.config.metric, "caution") }
            }
        }
    }
    // この計測値を条件に使うルール(オフのものも)
    readonly property var metricRules: { AlertRules.revision
        return AlertRules.rules.filter(r => r.conditions.some(c => c.source === root.config.metric)) }

    function titleTextOf() {
        const custom = String(config.titleText || "").trim()
        return custom !== "" ? custom : gauge.title
    }
}
