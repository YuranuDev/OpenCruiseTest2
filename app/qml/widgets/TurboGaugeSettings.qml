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
    readonly property var colorOptions: [
        { label: "テーマ", value: "theme" }, { label: "パネル", value: "panel" },
        { label: "白", value: "#ffffff" }, { label: "赤", value: "#f44336" },
        { label: "橙", value: "#ff9800" }, { label: "黄", value: "#ffeb3b" },
        { label: "緑", value: "#4caf50" }, { label: "青", value: "#2196f3" },
        { label: "紫", value: "#9c27b0" }
    ]

    // 表示単位の値 → bar に直して保存(psi は 0.1bar 未満が出ないよう丸める)
    function save(key, shownValue) {
        root.edit(key, Number((shownValue / root.k).toFixed(3)))
    }

    SettingsRow {
        visible: root.config.style !== "digital"
        label: "メーターの種類"
        description: "クラシックは目盛りと警告帯、シンプルは細いリング、スポーツは太い進捗リングです"
        SettingsChoice {
            model: ["クラシック", "シンプル", "スポーツ"]
            currentIndex: root.config.dialStyle === "minimal" ? 1 : (root.config.dialStyle === "sport" ? 2 : 0)
            onPicked: (i) => root.edit("dialStyle", i === 1 ? "minimal" : (i === 2 ? "sport" : "classic"))
        }
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
            to: 32
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
