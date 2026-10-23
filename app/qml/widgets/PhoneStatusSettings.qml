// スマホ状態ウィジェットの設定: 残り時間・電波の表示、低残量のしきい値とメッセージ、モックデータの使用。
import QtQuick
import OpenCruise

WidgetSettingsBase {
    id: root

    SettingsRow {
        label: "残り時間を表示"
        description: "スマホが残り時間を通知したときだけ表示されます"
        SettingsSwitch {
            checked: root.config.showRemaining !== false
            onToggled: (v) => root.edit("showRemaining", v)
        }
    }
    SettingsRow {
        label: "電波を表示"
        description: "スマホが電波強度を通知したときに表示します(届かない間はモックの値)"
        SettingsSwitch {
            checked: root.config.showSignal !== false
            onToggled: (v) => root.edit("showSignal", v)
        }
    }
    SettingsRow {
        label: "低残量の警告しきい値"
        description: "この残量以下(またはスマホが危険と通知)で、赤・アイコン・メッセージで警告します"
        WSStepper {
            value: root.config.lowThreshold
            from: 5
            to: 50
            step: 5
            suffix: " %"
            onMoved: (v) => root.edit("lowThreshold", v)
        }
    }
    SettingsRow {
        label: "警告メッセージ"
        stacked: true
        WSTextField {
            width: 520 * Theme.uiScale
            text: root.config.lowMessage || ""
            placeholder: "スマホの充電が残りわずかです"
            maxLength: 24
            onEdited: (t) => root.edit("lowMessage", t)
        }
    }
    SettingsRow {
        label: "モックデータを使う"
        description: "スマホから取れない項目を、仮の値で表示します(スマホ関連のウィジェット全体に反映)"
        SettingsSwitch {
            checked: phoneStatus.mockEnabled
            onToggled: (v) => phoneStatus.mockEnabled = v
        }
    }
}
