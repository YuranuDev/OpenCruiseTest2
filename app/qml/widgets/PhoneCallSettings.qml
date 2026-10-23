// 通話ウィジェットの設定: 電話番号の表示、着信時の点滅、モックデータの使用。
import QtQuick
import OpenCruise

WidgetSettingsBase {
    id: root

    SettingsRow {
        label: "電話番号を表示"
        description: "相手の名前が分かるときに、電話番号を名前の下へ小さく出します(名前が無いときは番号を主表示にします)"
        SettingsSwitch {
            checked: root.config.showNumber !== false
            onToggled: (v) => root.edit("showNumber", v)
        }
    }
    SettingsRow {
        label: "着信時に点滅"
        SettingsSwitch {
            checked: root.config.blink !== false
            onToggled: (v) => root.edit("blink", v)
        }
    }
    SettingsRow {
        label: "モックデータを使う"
        description: "スマホから通話情報が届かない間、仮の通話(着信 → 通話中)を表示します(スマホ関連のウィジェット全体に反映)"
        SettingsSwitch {
            checked: phoneStatus.mockEnabled
            onToggled: (v) => phoneStatus.mockEnabled = v
        }
    }
}
