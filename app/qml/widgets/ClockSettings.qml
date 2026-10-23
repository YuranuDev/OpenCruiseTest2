// 時計ウィジェットの設定: 枠・配置・日付。
import QtQuick
import OpenCruise

WidgetSettingsBase {
    id: root

    SettingsRow {
        label: "枠"
        description: "「なし」にすると背景のカードを描きません"
        SettingsChoice {
            model: ["カード", "なし"]
            currentIndex: root.config.frame === "plain" ? 1 : 0
            onPicked: (i) => root.edit("frame", i === 1 ? "plain" : "card")
        }
    }
    SettingsRow {
        label: "配置"
        SettingsChoice {
            model: ["左寄せ", "中央"]
            currentIndex: root.config.align === "center" ? 1 : 0
            onPicked: (i) => root.edit("align", i === 1 ? "center" : "left")
        }
    }
    SettingsRow {
        label: "日付を表示"
        SettingsSwitch {
            checked: root.config.showDate !== false
            onToggled: (v) => root.edit("showDate", v)
        }
    }
}
