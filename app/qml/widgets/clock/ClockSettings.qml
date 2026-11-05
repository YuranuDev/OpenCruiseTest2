// 時計ウィジェットの設定: 配置・日付。(枠は全ウィジェット共通の設定)
import QtQuick
import OpenCruise

WidgetSettingsBase {
    id: root

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
