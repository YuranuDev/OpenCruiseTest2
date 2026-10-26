// メーター(GaugeWidget)の設定: 表示方式・メーターの種類・単位・最小値/最大値・角度・針と中心円・アイコン・警告。
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
        visible: root.config.style !== "digital" && !root.needleless
        label: "針の色"
        description: "警告中は警告色で表示します"
        stacked: true
        SettingsColorPalette {
            width: Math.min(root.width, 620 * Theme.uiScale)
            options: root.colorOptions
            selectedValue: root.config.needleColor || "theme"
            onPicked: (v) => root.edit("needleColor", v)
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
    SettingsRow {
        label: "警告"
        description: (root.warnBelow ? "警告値以下で、色・アイコン・メッセージで知らせます"
                                     : "警告値以上で、色・アイコン・メッセージで知らせます")
                     + "。警告と通知の設定は、同じ種類のメーターすべてで共通です"
        SettingsSwitch {
            checked: root.config.warnEnabled === true
            onToggled: (v) => root.edit("warnEnabled", v)
        }
    }
    SettingsRow {
        visible: root.config.warnEnabled === true
        label: "警告値"
        WSStepper {
            value: root.toShown(root.config.warn)
            from: root.toShown(root.config.min)
            to: root.toShown(root.config.max)
            step: root.step
            decimals: root.dec
            suffix: root.suffix
            onMoved: (v) => root.save("warn", v)
        }
    }
    SettingsRow {
        visible: root.config.warnEnabled === true
        label: "警告メッセージを表示"
        description: "オフにすると、メッセージは出さずに色とアイコンだけで知らせます"
        SettingsSwitch {
            checked: root.config.showWarnMessage !== false
            onToggled: (v) => root.edit("showWarnMessage", v)
        }
    }
    SettingsRow {
        visible: root.config.warnEnabled === true
        label: "警告音を鳴らす"
        description: "鳴っている間はメーター全体が赤く点滅します。タップすると、その警告が解除されるまで止まります(音は 設定 > サウンド > 警告音)"
        SettingsSwitch {
            checked: root.config.warnBeep === true
            onToggled: (v) => root.edit("warnBeep", v)
        }
    }
    // 以前の設定(warnPopup: true)は「1 回だけ」として扱う
    readonly property string popupMode: config.warnPopupMode === "once" || config.warnPopupMode === "live"
                                        || config.warnPopupMode === "off"
                                        ? config.warnPopupMode : (config.warnPopup === true ? "once" : "off")
    SettingsRow {
        visible: root.config.warnEnabled === true
        label: "ポップアップ通知"
        description: "「1 回だけ」: 警告になったときに通知を出し(8 秒で消えます)、表示中は今の値を更新し続けます。"
                     + "まだ出ている間にもう一度警告になると、同じ通知を書き換えます。\n"
                     + "「出し続ける」: 警告中は通知を出したままにし、今の値を更新し続けます。タップで消せます。\n"
                     + "どちらも、警告が解除されると、その警告の間の最大値(燃料などは最低値)を出してから消えます。\n"
                     + "いくつかのメーターが同時に警告したときは、1 つの通知にまとめます(「出し続ける」のメーターが警告中なら、まとめた通知も出したまま)"
        stacked: true
        SettingsChoice {
            model: ["オフ", "1 回だけ", "警告中は出し続ける"]
            currentIndex: ["off", "once", "live"].indexOf(root.popupMode)
            onPicked: (index) => root.edit("warnPopupMode", ["off", "once", "live"][index])
        }
    }
    SettingsRow {
        visible: root.config.warnEnabled === true && root.popupMode !== "off"
        label: "通知に詳細を表示"
        description: "通知に、今の値と並べて警告値も入れます"
        SettingsSwitch {
            checked: root.config.warnPopupDetail !== false
            onToggled: (v) => root.edit("warnPopupDetail", v)
        }
    }
    SettingsRow {
        visible: root.config.warnEnabled === true && root.config.showWarnMessage !== false
        label: "警告メッセージ"
        stacked: true
        WSTextField {
            width: 520 * Theme.uiScale
            text: root.config.warnMessage || ""
            placeholder: root.gauge.warnMessage || "警告"
            maxLength: 24
            onChanging: (t) => root.preview("warnMessage", t)
            onEdited: (t) => root.edit("warnMessage", t)
        }
    }

    // ---- 注意(警告の手前の段階) ----
    // 注意値の既定: 警告値の手前(範囲の 10%)。警告を使っていなければ、範囲の 8 割(燃料などは 2 割)
    function defaultCautionBase() {
        const span = maxBase - minBase
        if (config.warnEnabled === true && config.warn !== undefined) {
            const w = Number(config.warn)
            return warnBelow ? Math.min(maxBase, w + span * 0.1) : Math.max(minBase, w - span * 0.1)
        }
        return warnBelow ? minBase + span * 0.2 : minBase + span * 0.8
    }
    SettingsRow {
        label: "注意"
        description: (root.warnBelow ? "注意値以下になると" : "注意値以上になると")
                     + "、注意音を 1 回鳴らし、メーターを黄色くして知らせます(警告値まで行くと警告が優先します)。"
                     + "注意の設定も、同じ種類のメーターすべてで共通です"
        SettingsSwitch {
            checked: root.config.cautionEnabled === true
            onToggled: (v) => {
                if (v && root.config.caution === undefined)
                    root.edit("caution", Number(root.defaultCautionBase().toFixed(3)))
                root.edit("cautionEnabled", v)
            }
        }
    }
    SettingsRow {
        visible: root.config.cautionEnabled === true
        label: "注意値"
        description: root.config.warnEnabled === true
                     && (root.warnBelow ? Number(root.config.caution) <= Number(root.config.warn)
                                        : Number(root.config.caution) >= Number(root.config.warn))
                     ? "注意値が警告値より奥にあるため、注意は出ません(警告値より手前にしてください)" : ""
        WSStepper {
            value: root.toShown(root.config.caution !== undefined ? root.config.caution : root.defaultCautionBase())
            from: root.toShown(root.config.min)
            to: root.toShown(root.config.max)
            step: root.step
            decimals: root.dec
            suffix: root.suffix
            onMoved: (v) => root.save("caution", v)
        }
    }
    SettingsRow {
        visible: root.config.cautionEnabled === true
        label: "注意音を鳴らす"
        description: "注意値を超えたときに 1 回だけ鳴らします(音は 設定 > サウンド > 注意音)"
        SettingsSwitch {
            checked: root.config.cautionBeep !== false
            onToggled: (v) => root.edit("cautionBeep", v)
        }
    }
    SettingsRow {
        visible: root.config.cautionEnabled === true
        label: "注意の通知"
        description: "注意値を超えたときに通知を出し(8 秒で消えます)、表示中は今の値を更新し続けます。"
                     + "警告になれば警告の通知に、解除されれば「正常に戻りました」に変わります"
        SettingsSwitch {
            checked: root.config.cautionPopup !== false
            onToggled: (v) => root.edit("cautionPopup", v)
        }
    }
    SettingsRow {
        visible: root.config.cautionEnabled === true
        label: "注意メッセージ"
        description: "通知の見出しと、メーターの下に出すメッセージ(「警告メッセージを表示」がオンのとき)"
        stacked: true
        WSTextField {
            width: 520 * Theme.uiScale
            text: root.config.cautionMessage || ""
            placeholder: root.titleTextOf() + "に注意"
            maxLength: 24
            onChanging: (t) => root.preview("cautionMessage", t)
            onEdited: (t) => root.edit("cautionMessage", t)
        }
    }
    function titleTextOf() {
        const custom = String(config.titleText || "").trim()
        return custom !== "" ? custom : gauge.title
    }
}
