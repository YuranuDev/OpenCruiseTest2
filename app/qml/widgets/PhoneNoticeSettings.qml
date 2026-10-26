// スマホ通知ウィジェットの設定: 表示方法・件数・アイコン・カテゴリごとのメッセージ・テスト通知。
// メッセージの {text} は通知文に置き換わる(例:「📞 {text}」)。空欄にすると通知文そのままを表示する。
import QtQuick
import OpenCruise

WidgetSettingsBase {
    id: root

    SettingsRow {
        label: "表示方法"
        SettingsChoice {
            model: ["一覧", "最新1件", "件数のみ"]
            currentIndex: root.config.mode === "latest" ? 1 : (root.config.mode === "badge" ? 2 : 0)
            onPicked: (i) => root.edit("mode", i === 1 ? "latest" : (i === 2 ? "badge" : "list"))
        }
    }
    SettingsRow {
        visible: root.config.mode !== "latest" && root.config.mode !== "badge"
        label: "一覧の件数"
        WSStepper {
            value: root.config.maxItems
            from: 1
            to: 5
            step: 1
            suffix: " 件"
            onMoved: (v) => root.edit("maxItems", v)
        }
    }
    SettingsRow {
        label: "アイコンを表示"
        SettingsSwitch {
            checked: root.config.showIcon !== false
            onToggled: (v) => root.edit("showIcon", v)
        }
    }
    SettingsRow {
        label: "「その他」の通知も表示"
        SettingsSwitch {
            checked: root.config.showOther !== false
            onToggled: (v) => root.edit("showOther", v)
        }
    }
    SettingsRow {
        label: "通話の通知"
        description: "{text} が通知文に置き換わります(下の 3 つも同じ)。通知のメッセージは、スマホ通知のウィジェットすべてで共通です"
        stacked: true
        WSTextField { width: 520 * Theme.uiScale; text: root.config.tplCall || ""; placeholder: "{text}"; maxLength: 40
                      onChanging: (t) => root.preview("tplCall", t); onEdited: (t) => root.edit("tplCall", t) }
    }
    SettingsRow {
        label: "メッセージの通知"
        stacked: true
        WSTextField { width: 520 * Theme.uiScale; text: root.config.tplMessage || ""; placeholder: "{text}"; maxLength: 40
                      onChanging: (t) => root.preview("tplMessage", t); onEdited: (t) => root.edit("tplMessage", t) }
    }
    SettingsRow {
        label: "案内(ナビ)の通知"
        stacked: true
        WSTextField { width: 520 * Theme.uiScale; text: root.config.tplNavigation || ""; placeholder: "{text}"; maxLength: 40
                      onChanging: (t) => root.preview("tplNavigation", t); onEdited: (t) => root.edit("tplNavigation", t) }
    }
    SettingsRow {
        label: "その他の通知"
        stacked: true
        WSTextField { width: 520 * Theme.uiScale; text: root.config.tplOther || ""; placeholder: "{text}"; maxLength: 40
                      onChanging: (t) => root.preview("tplOther", t); onEdited: (t) => root.edit("tplOther", t) }
    }
    SettingsRow {
        label: "モックデータを使う"
        description: "Android Auto の通知は現状届かないため、仮の通知を約 25 秒ごとに出します"
        SettingsSwitch {
            checked: phoneStatus.mockEnabled
            onToggled: (v) => phoneStatus.mockEnabled = v
        }
    }
    SettingsRow {
        label: "テスト通知"
        description: "モックの通知を今すぐ 1 件出します"
        ActionButton {
            text: "通知を出す"
            onClicked: phoneStatus.injectMockNotice()
        }
    }
}
