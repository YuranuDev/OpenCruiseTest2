// ターボ圧計の設定: 表示方式・単位・最小値/最大値・アイコン・警告値・警告メッセージ。
// 値は bar 基準で保存し、表示と編集は選んだ単位(bar/psi)で行う。
import QtQuick
import OpenCruise

WidgetSettingsBase {
    id: root

    readonly property bool psi: config.unit === "psi"
    readonly property real k: psi ? 14.5038 : 1.0
    readonly property string suffix: psi ? " psi" : " bar"
    readonly property real step: psi ? 1 : 0.1
    readonly property int dec: psi ? 0 : 1
    // 最小値と最大値の最低の幅(bar)
    readonly property real minSpan: 0.5

    // 表示単位の値 → bar に直して保存(psi は 0.1bar 未満が出ないよう丸める)
    function save(key, shownValue) {
        root.edit(key, Number((shownValue / root.k).toFixed(3)))
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
        label: "単位"
        SettingsChoice {
            model: ["bar", "psi"]
            currentIndex: root.psi ? 1 : 0
            onPicked: (i) => root.edit("unit", i === 1 ? "psi" : "bar")
        }
    }
    SettingsRow {
        label: "最小値(負圧側)"
        description: "目盛りの左端。負圧を測れるよう、通常は 0 より小さくします"
        WSStepper {
            value: root.config.min * root.k
            from: -1.0 * root.k
            to: (root.config.max - root.minSpan) * root.k
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
            value: root.config.max * root.k
            from: (root.config.min + root.minSpan) * root.k
            to: 5.0 * root.k
            step: root.step
            decimals: root.dec
            suffix: root.suffix
            onMoved: (v) => root.save("max", v)
        }
    }
    SettingsRow {
        label: "アイコンを表示"
        description: "警告中はアイコンが警告マークに変わり、点滅します"
        SettingsSwitch {
            checked: root.config.showIcon !== false
            onToggled: (v) => root.edit("showIcon", v)
        }
    }
    SettingsRow {
        label: "警告"
        description: "警告値以上で、色・アイコン・メッセージで知らせます"
        SettingsSwitch {
            checked: root.config.warnEnabled === true
            onToggled: (v) => root.edit("warnEnabled", v)
        }
    }
    SettingsRow {
        visible: root.config.warnEnabled === true
        label: "警告値"
        WSStepper {
            value: root.config.warn * root.k
            from: root.config.min * root.k
            to: root.config.max * root.k
            step: root.step
            decimals: root.dec
            suffix: root.suffix
            onMoved: (v) => root.save("warn", v)
        }
    }
    SettingsRow {
        visible: root.config.warnEnabled === true
        label: "警告メッセージ"
        description: "警告中にメーターの下へ表示します"
        stacked: true
        WSTextField {
            width: 520 * Theme.uiScale
            text: root.config.warnMessage || ""
            placeholder: "ブースト圧が高すぎます"
            maxLength: 24
            onEdited: (t) => root.edit("warnMessage", t)
        }
    }
}
