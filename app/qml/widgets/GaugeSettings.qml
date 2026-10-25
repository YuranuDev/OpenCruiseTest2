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
        description: "クラシックは目盛りと警告帯、シンプルは細いリング、スポーツは点灯するセグメントです"
        SettingsChoice {
            model: ["クラシック", "シンプル", "スポーツ"]
            currentIndex: root.config.dialStyle === "minimal" ? 1 : (root.config.dialStyle === "sport" ? 2 : 0)
            onPicked: (i) => root.edit("dialStyle", i === 1 ? "minimal" : (i === 2 ? "sport" : "classic"))
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
        description: root.gauge.minHint || "目盛りの左端"
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
        description: "目盛りの右端"
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
        description: "針が動き始める位置(-180°〜-90°)"
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
        description: "針が動き終わる位置(90°〜180°)"
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
        visible: root.config.style === "both"
        label: "数値を空き位置に配置"
        description: "開始角度と終了角度の間の空きに現在値を表示します"
        SettingsSwitch {
            checked: root.config.autoLabelPosition !== false
            onToggled: (v) => root.edit("autoLabelPosition", v)
        }
    }
    SettingsRow {
        visible: root.config.style !== "digital"
        label: "針の反対側の出っ張り"
        description: "針の軸から反対側へ伸びる部分を表示します"
        SettingsSwitch {
            checked: root.config.needleTail !== false
            onToggled: (v) => root.edit("needleTail", v)
        }
    }
    SettingsRow {
        visible: root.config.style !== "digital"
        label: "中心円のサイズ"
        description: "針の軸にある丸の大きさ(半径に対する割合)"
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
        visible: root.config.style !== "digital"
        label: "中心円の色"
        description: "中央の丸だけに適用する色"
        stacked: true
        SettingsColorPalette {
            width: Math.min(root.width, 620 * Theme.uiScale)
            options: root.colorOptions
            selectedValue: root.config.hubColor || "panel"
            onPicked: (v) => root.edit("hubColor", v)
        }
    }
    SettingsRow {
        visible: root.config.style !== "digital"
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
        description: "メーター内の名前の横に出します。警告中は警告マークに変わり、点滅します"
        SettingsSwitch {
            checked: root.config.showIcon !== false
            onToggled: (v) => root.edit("showIcon", v)
        }
    }
    SettingsRow {
        label: "ピーク表示"
        description: "右下に最大値(MAX)または最小値(MIN)を単位つきで出します。タップするとリセットします(再起動でもリセット)"
        stacked: true
        SettingsChoice {
            model: ["オフ", "最大(MAX)", "最小(MIN)"]
            currentIndex: root.config.peakMode === "off" ? 0 : (root.config.peakMode === "min" ? 2 : 1)
            onPicked: (index) => root.edit("peakMode", ["off", "max", "min"][index])
        }
    }
    SettingsRow {
        label: "警告"
        description: root.warnBelow ? "警告値以下で、色・アイコン・メッセージで知らせます"
                                    : "警告値以上で、色・アイコン・メッセージで知らせます"
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
        description: "警告中はビープ音を繰り返し鳴らし、メーター全体を赤く点滅させます。メーターをタップすると、"
                     + "その警告が解除されるまで音を止めます(音は設定「サウンド」の「警告音」で選べます)"
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
        description: "「1 回だけ」: 警告になったときに通知を出します(同じメーターは 30 秒に 1 回まで)。\n"
                     + "「出し続ける」: 警告中は通知を出したままにし、今の値を更新し続けます。タップで消せます"
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
        description: "通知に警告値を入れます(「1 回だけ」は、警告になったときの値も入れます)"
        SettingsSwitch {
            checked: root.config.warnPopupDetail !== false
            onToggled: (v) => root.edit("warnPopupDetail", v)
        }
    }
    SettingsRow {
        visible: root.config.warnEnabled === true && root.config.showWarnMessage !== false
        label: "警告メッセージ"
        description: "警告中にメーターへ重ねて表示します"
        stacked: true
        WSTextField {
            width: 520 * Theme.uiScale
            text: root.config.warnMessage || ""
            placeholder: root.gauge.warnMessage || "警告"
            maxLength: 24
            onEdited: (t) => root.edit("warnMessage", t)
        }
    }
}
