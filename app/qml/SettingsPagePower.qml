// 設定ジャンル「電源管理」。Linux が公開する電源管理モードを選び、アプリ設定として保持する。
import QtQuick

SettingsPage {
    SettingsSection {
        title: "電源モード"
        icon: "bolt"

        SettingsRow {
            label: "モード"
            description: "アプリ起動時と変更時に Linux の電源プロファイルへ適用します"
            stacked: true

            SettingsChoice {
                model: [{ label: "標準", icon: "tune" },
                        { label: "省電力", icon: "eco" },
                        { label: "高性能", icon: "speed" }]
                currentIndex: appSettings.powerMode
                onPicked: (index) => appSettings.powerMode = index
            }
        }

        SettingsNote {
            text: "power-profiles-daemon が必要です。現在の状態: " + appSettings.powerModeStatus
        }
    }

    SettingsSection {
        title: "モードの説明"
        icon: "info"

        SettingsInfoRow { label: "標準"; value: "バランス重視の電源プロファイル" }
        SettingsInfoRow { label: "省電力"; value: "消費電力を抑える設定を優先" }
        SettingsInfoRow { label: "高性能"; value: "性能を優先する設定" }
    }
}
