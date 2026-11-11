// 設定ジャンル「電源管理」。Linux が公開する電源管理モードを選び、アプリ設定として保持する。
import QtQuick
import OpenCruise

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
            text: "power-profiles-daemon が必要です。アプリの終了時(ACC OFF の終了では電源を切る前)に、起動前のプロファイルへ戻します。現在の状態: " + appSettings.powerModeStatus
        }
    }

    // 車両の終了(ACC OFF)に合わせたシャットダウン(ShutdownManager)
    SettingsSection {
        title: "終了(ACC OFF)"
        icon: "power_settings_new"

        SettingsRow {
            label: "終了処理が済んだら"
            description: "ACC OFF で終了を要求されたら、終了の画面(起動画面と同じロゴ)に切り替えて裏で終了処理(設定の保存・Android Auto の切断・ドアロックの解除など)を行い、済んだらこの動作をします"
            stacked: true
            SettingsChoice {
                model: [{ label: "PC の電源を切る", icon: "power_settings_new" },
                        { label: "アプリだけ終了", icon: "logout" }]
                currentIndex: shutdownManager.afterAction
                onPicked: (index) => shutdownManager.afterAction = index
            }
        }
        SettingsRow {
            label: "終了処理の上限"
            description: "終わらない処理があっても、この時間で打ち切って先へ進みます。外部マイコンが電源を切るまでの待ち時間(30 秒)より短くしてください"
            SettingsChoice {
                readonly property var secs: [10, 15, 20, 25]
                model: ["10 秒", "15 秒", "20 秒", "25 秒"]
                currentIndex: secs.indexOf(shutdownManager.timeoutSec)
                onPicked: (i) => shutdownManager.timeoutSec = secs[i]
            }
        }
        SettingsNote {
            text: "終了の要求は、外部マイコンができるまではキーボードの Ctrl+Shift+P で試せます(ACC OFF を検出したのと同じ動きをします)。"
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
