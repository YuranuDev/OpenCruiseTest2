import QtQuick
import OpenCruise

WidgetSettingsBase {
    id: root
    SettingsRow {
        label: "道路名"
        description: "案内中の道路名を表示します"
        SettingsSwitch {
            checked: root.config.showRoad !== false
            onToggled: (value) => root.edit("showRoad", value)
        }
    }
    SettingsRow {
        label: "距離表示"
        SettingsChoice {
            model: ["自動", "km"]
            currentIndex: root.config.distanceUnit === "km" ? 1 : 0
            onPicked: (index) => root.edit("distanceUnit", index === 1 ? "km" : "auto")
        }
    }
    SettingsNote {
        text: "2 件分の矢印は Android Auto の NavigationState が送信するステップを表示します。距離は現在位置から次の曲がり角までの値です。2 件目までの距離はプロトコルから提供されません。"
    }
}
