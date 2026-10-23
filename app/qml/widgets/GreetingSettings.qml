// あいさつウィジェットの設定: 枠・配置・名前。名前そのものは 設定 > 一般 で変える。
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
        label: "名前を付ける"
        description: "ユーザー名は 設定 > 一般 で変更できます"
        SettingsSwitch {
            checked: root.config.showName !== false
            onToggled: (v) => root.edit("showName", v)
        }
    }
}
