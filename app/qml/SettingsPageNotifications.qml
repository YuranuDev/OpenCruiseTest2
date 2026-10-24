// 設定ジャンル「通知」: スマートフォン通知のポップアップ表示。
import QtQuick

SettingsPage {
    SettingsSection {
        title: "スマートフォン通知"
        icon: "notifications"

        SettingsRow {
            label: "ポップアップ通知を表示"
            description: "オンにすると、受信したスマホ通知を画面上部に表示します"

            SettingsSwitch {
                checked: appSettings.phoneNoticePopupEnabled
                onToggled: (enabled) => appSettings.phoneNoticePopupEnabled = enabled
            }
        }

        SettingsNote {
            text: "オフの場合も、スマホ通知ウィジェットの一覧には通知が保存・表示されます。"
        }
    }
}
