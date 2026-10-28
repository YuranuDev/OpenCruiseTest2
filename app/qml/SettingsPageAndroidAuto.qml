// 設定ジャンル「Android Auto」: 映像(解像度・fps・フルスクリーン)、フルスクリーンでないときの映像の置き方
// (角と幅・高さのマス数。残りのマスにウィジェットを置ける)と、現在の接続診断情報。
import QtQuick
import OpenCruise

SettingsPage {
    // フレームレートの選択肢(表示順)。増やすときはここに足す
    readonly property var fpsOptions: [30, 60]

    SettingsSection {
        title: "映像"
        icon: "videocam"

        SettingsRow {
            label: "解像度"

            SettingsChoice {
                model: ["800x480", "1280x720", "1920x1080"]
                currentIndex: androidAuto.resolutionIndex
                onPicked: (index) => androidAuto.resolutionIndex = index
            }
        }

        SettingsRow {
            label: "フレームレート"

            SettingsChoice {
                model: fpsOptions.map(value => value + " fps")
                currentIndex: fpsOptions.indexOf(androidAuto.fps)
                onPicked: (index) => androidAuto.fps = fpsOptions[index]
            }
        }

        SettingsRow {
            label: "接続後フルスクリーン"

            SettingsSwitch {
                checked: androidAuto.fullscreenOnStream
                onToggled: (value) => androidAuto.fullscreenOnStream = value
            }
        }

        SettingsNote {
            text: "解像度・fps を変更すると、接続中の場合は一度正規に切断してから再接続待機になります。"
                  + "フルスクリーン中は、画面下端を上へスワイプ、または Esc / F10 / Menu / Windows キーでメニューを開けます。"
        }
    }

    SettingsSection {
        title: "画面の配置"
        icon: "dashboard"

        SettingsRow {
            label: "映像の位置"
            description: "フルスクリーンでないとき、映像を置く角"
            SettingsChoice {
                model: ["左上", "右上", "左下", "右下"]
                currentIndex: widgetStore.aaCorner
                onPicked: (index) => widgetStore.aaCorner = index
            }
        }
        SettingsRow {
            label: "映像の幅"
            WSStepper {
                value: widgetStore.aaCols
                from: 4
                to: 12
                step: 1
                suffix: " / 12 マス"
                onMoved: (v) => widgetStore.aaCols = v
            }
        }
        SettingsRow {
            label: "映像の高さ"
            WSStepper {
                value: widgetStore.aaRows
                from: 2
                to: 6
                step: 1
                suffix: " / 6 マス"
                onMoved: (v) => widgetStore.aaRows = v
            }
        }
        SettingsNote {
            text: "映像の周りの空いたマスに、ウィジェットを置けます(Android Auto 画面のメニューの「編集」から追加。編集中は映像の大きさ・角もドラッグで変えられます)。"
                  + "映像を大きくして入りきらなくなったウィジェットは、一時的に隠れ、空きができると元の近くに戻ります。"
        }
    }

    SettingsSection {
        title: "接続状態"
        icon: "usb"

        SettingsInfoRow { label: "状態"; value: androidAuto.stateText; valueColor: Theme.stateColor(androidAuto.stateKey) }
        SettingsInfoRow { label: "詳細"; value: androidAuto.detailText }
        SettingsInfoRow { label: "直近の切断/エラー"; value: androidAuto.lastIssue === "" ? "なし" : androidAuto.lastIssue }
        SettingsInfoRow { label: "受信フレーム数"; value: String(androidAuto.frameCount) }
        SettingsInfoRow { label: "映像サイズ"; value: androidAuto.videoInfo }
        SettingsInfoRow { label: "aasdk 接続処理"; value: androidAuto.aasdkEnabled ? "ビルドに含まれる" : "含まれない (OFF)" }
    }
}
