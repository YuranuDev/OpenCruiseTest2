// ギア表示(GearWidget)の設定: ギアの取り方・ギアの数・推定のための学習・シフトの目安。
// 学習: そのギアで一定の速さで走っている間(同乗者が)、「今を記録」を押す。1000 rpm あたりの速度を覚える
import QtQuick
import OpenCruise

WidgetSettingsBase {
    id: root

    readonly property int gears: [4, 5, 6].indexOf(Number(config.gears)) >= 0 ? Number(config.gears) : 5
    readonly property var ratios: Array.isArray(config.ratios) ? config.ratios : []
    readonly property bool hasSpeed: VehicleSignals.has("speed")
    readonly property bool hasRpm: VehicleSignals.has("rpm")
    readonly property real speed: hasSpeed ? VehicleSignals.value("speed") : NaN
    readonly property real rpm: hasRpm ? VehicleSignals.value("rpm") : NaN
    readonly property real nowRatio: hasSpeed && hasRpm && rpm > 300 && speed >= 5 ? speed / (rpm / 1000) : NaN
    function record(i) {
        const l = ratios.slice()
        while (l.length < gears) l.push(0)
        l[i] = Number(nowRatio.toFixed(2))
        root.edit("ratios", l)
    }
    function clearAt(i) {
        const l = ratios.slice()
        if (i < l.length) l[i] = 0
        root.edit("ratios", l)
    }

    WidgetSettingsGroup {
        title: "表示"
        icon: "tune"

        SettingsRow {
            label: "ギアの取り方"
            description: (VehicleSignals.has("gear") ? "今は車両信号からギアが来ています。" : "今は車両信号からギアが来ていません(推定になります)。")
                         + "推定は、速度と回転数の比を「学習」で記録した値と比べます"
            stacked: true
            SettingsChoice {
                model: ["自動(車両信号 → 無ければ推定)", "いつも推定"]
                currentIndex: root.config.source === "estimate" ? 1 : 0
                onPicked: (i) => root.edit("source", i === 1 ? "estimate" : "auto")
            }
        }
        SettingsRow {
            label: "ギアの数"
            SettingsChoice {
                model: ["4 速", "5 速", "6 速"]
                currentIndex: [4, 5, 6].indexOf(root.gears)
                onPicked: (i) => root.edit("gears", [4, 5, 6][i])
            }
        }
        SettingsRow {
            label: "シフトの目安"
            description: "回転数が高いと ▲(シフトアップ)、低いと ▼(シフトダウン)を出します"
            SettingsSwitch {
                checked: root.config.hint !== false
                onToggled: (v) => root.edit("hint", v)
            }
        }
        SettingsRow {
            visible: root.config.hint !== false
            label: "▲ を出す回転数"
            WSStepper {
                value: Number(root.config.upRpm) || 3500
                from: 1500; to: 9000; step: 100; suffix: " rpm"
                onMoved: (v) => root.edit("upRpm", v)
            }
        }
        SettingsRow {
            visible: root.config.hint !== false
            label: "▼ を出す回転数"
            WSStepper {
                value: Number(root.config.downRpm) || 1500
                from: 600; to: 4000; step: 100; suffix: " rpm"
                onMoved: (v) => root.edit("downRpm", v)
            }
        }
    }

    WidgetSettingsGroup {
        title: "学習"
        icon: "school"
        active: root.ratios.some(r => Number(r) > 0)

        SettingsRow {
            label: "今の値"
            description: "ギアを入れて一定の速さで走っている間に、そのギアの「今を記録」を押します(運転中は同乗者が操作してください)。"
                         + "車両信号にギアがあれば、学習しなくても表示できます"
            stacked: true
            Text {
                font.family: Theme.numberFontFamily
                font.pixelSize: 26 * Theme.uiScale
                font.bold: true
                color: isNaN(root.nowRatio) ? Theme.textSecondary : Theme.textPrimary
                text: isNaN(root.nowRatio) ? (root.hasSpeed && root.hasRpm ? "止まっています(5 km/h 以上で記録できます)" : "速度・回転数のデータがありません")
                      : Math.round(root.speed) + " km/h ・ " + Math.round(root.rpm) + " rpm → 1000 rpm あたり " + root.nowRatio.toFixed(1) + " km/h"
            }
        }
        Repeater {
            model: root.gears
            SettingsRow {
                id: gearRow
                required property int index
                readonly property real r: Number(root.ratios[index]) || 0
                label: (index + 1) + " 速"
                description: r > 0 ? "記録: 1000 rpm あたり " + r.toFixed(1) + " km/h" : "まだ記録していません"
                Row {
                    spacing: 12 * Theme.uiScale
                    ActionButton {
                        text: "今を記録"
                        opacity: isNaN(root.nowRatio) ? 0.4 : 1
                        onClicked: if (!isNaN(root.nowRatio)) root.record(gearRow.index)
                    }
                    ActionButton {
                        visible: gearRow.r > 0
                        text: "消す"
                        onClicked: root.clearAt(gearRow.index)
                    }
                }
            }
        }
    }
}
