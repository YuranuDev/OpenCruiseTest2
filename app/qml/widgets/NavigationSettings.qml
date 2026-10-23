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
        text: "案内内容は接続中の Android Auto ナビアプリが送信する情報に従います。現行の NavigationStatus は次の 1 案内のみを送信するため、2 件先までの表示には対応する案内データが必要です。"
    }
}
