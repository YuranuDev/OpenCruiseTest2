// 設定ジャンル「電源管理」。Linux が公開する電源管理モードを選び、アプリ設定として保持する。
import QtQuick

SettingsPage {
    SettingsSection {
        title: "電源モード"
        icon: "bolt"

        SettingsRow {
            label: "モード"
            description: "アプリ内で選択・保存する電源モードです。Linux の設定にはまだ反映されません。"
            stacked: true

            SettingsChoice {
                model: ["標準", "省電力", "高性能"]
                currentIndex: appSettings.powerMode
                onPicked: (index) => appSettings.powerMode = index
            }
        }

        SettingsNote {
            text: "Linux の機器や権限により、電源管理設定の適用可否は異なります。"
        }
    }

    SettingsSection {
        title: "モードの説明"
        icon: "info"

        SettingsInfoRow { label: "標準"; value: "システム既定の電源設定を使用" }
        SettingsInfoRow { label: "省電力"; value: "消費電力を抑える設定を優先" }
        SettingsInfoRow { label: "高性能"; value: "性能を優先する設定" }
    }
}
