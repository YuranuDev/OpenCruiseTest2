// グラフ(GraphWidget)の設定: 単位・表示する時間・縦軸(固定 / 自動)と範囲・警告線・塗りつぶし・統計。
// 値は基本単位で保存し、表示と編集は選んだ単位で行う(メーターの設定と同じ)。
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
    readonly property real minBase: config.min !== undefined ? config.min : gauge.limitMin
    readonly property real maxBase: config.max !== undefined ? config.max : gauge.limitMax
    readonly property var windows: [30, 60, 300, 600]

    function toShown(base) { return Number(base) * unitDef.scale + (unitDef.offset || 0) }
    function toBase(shown) { return (shown - (unitDef.offset || 0)) / unitDef.scale }
    function save(key, shownValue) { root.edit(key, Number(toBase(shownValue).toFixed(3))) }

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
        label: "表示する時間"
        SettingsChoice {
            model: ["30 秒", "1 分", "5 分", "10 分"]
            currentIndex: Math.max(0, root.windows.indexOf(Number(root.config.windowSec || 60)))
            onPicked: (i) => root.edit("windowSec", root.windows[i])
        }
    }
    SettingsRow {
        label: "縦軸"
        description: "「固定」は下の最小値〜最大値、「自動」は表示している値に合わせて広げ縮めします"
        SettingsChoice {
            model: ["固定", "自動"]
            currentIndex: root.config.autoScale === true ? 1 : 0
            onPicked: (i) => root.edit("autoScale", i === 1)
        }
    }
    SettingsRow {
        visible: root.config.autoScale !== true
        label: "最小値"
        WSStepper {
            value: root.toShown(root.minBase)
            from: root.toShown(root.gauge.limitMin)
            to: root.toShown(root.maxBase - root.gauge.minSpan)
            step: root.step
            decimals: root.dec
            suffix: root.suffix
            onMoved: (v) => root.save("min", v)
        }
    }
    SettingsRow {
        visible: root.config.autoScale !== true
        label: "最大値"
        WSStepper {
            value: root.toShown(root.maxBase)
            from: root.toShown(root.minBase + root.gauge.minSpan)
            to: root.toShown(root.gauge.limitMax)
            step: root.step
            decimals: root.dec
            suffix: root.suffix
            onMoved: (v) => root.save("max", v)
        }
    }
    SettingsRow {
        label: "警告線"
        description: root.gauge.warnBelow ? "警告値に赤い線を引き、それより下を薄い赤にします。今の値が警告値以下なら赤で表示します"
                                          : "警告値に赤い線を引き、それより上を薄い赤にします。今の値が警告値以上なら赤で表示します"
        SettingsSwitch {
            checked: root.config.warnEnabled === true
            onToggled: (v) => root.edit("warnEnabled", v)
        }
    }
    SettingsRow {
        visible: root.config.warnEnabled === true
        label: "警告値"
        WSStepper {
            value: root.toShown(root.config.warn !== undefined ? root.config.warn : root.maxBase)
            from: root.toShown(root.gauge.limitMin)
            to: root.toShown(root.gauge.limitMax)
            step: root.step
            decimals: root.dec
            suffix: root.suffix
            onMoved: (v) => root.save("warn", v)
        }
    }
    SettingsRow {
        label: "線の下を塗りつぶす"
        SettingsSwitch {
            checked: root.config.fill !== false
            onToggled: (v) => root.edit("fill", v)
        }
    }
    SettingsRow {
        label: "最大・最小・平均を表示"
        description: "表示している時間の中の値です。ウィジェットの高さが足りないときは出ません"
        SettingsSwitch {
            checked: root.config.showStats !== false
            onToggled: (v) => root.edit("showStats", v)
        }
    }
}
