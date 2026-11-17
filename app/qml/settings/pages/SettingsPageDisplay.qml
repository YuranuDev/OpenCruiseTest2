// 設定「表示と操作 > 画面」: 画面の明るさ(brightnessController)、表示する画面・回転・画面の端のボタン(displaySettings)、
//   eglfs での操作する画面と外部モニターへのミラー(drmDisplay)。
import QtQuick
import OpenCruise

SettingsPage {
    SettingsSection {
        title: "明るさ"
        icon: "brightness_medium"

        SettingsRow {
            label: "画面の明るさ"
            description: "Ctrl+Shift+K で暗く、L で明るくできます"

            SettingsSlider {
                from: brightnessController.minimum
                iconName: "brightness_high"
                iconMinName: "brightness_low"
                value: brightnessController.brightness
                onMoved: (v) => brightnessController.brightness = v
            }
        }

        SettingsInfoRow {
            label: "調整方式"
            value: brightnessController.methodText
        }

        SettingsNote {
            text: "バックライトを直接制御できない環境(Windows、権限が無い場合、外部ディスプレイなど)では、"
                  + "画面を暗くする方式で調整します。この場合、画面の最大の明るさは変えられません。"
                  + "運転中に画面が見えなくならないよう、" + brightnessController.minimum + " % より暗くはできません。"
        }
    }

    SettingsSection {
        title: "画面"
        icon: "monitor"

        // ---- eglfs 以外(デスクトップ): どの画面に出すか ----
        SettingsRow {
            visible: !displaySettings.isEglfs
            label: "表示する画面"
            description: "「外部画面があれば外部画面」にすると、起動時や接続したときに自動で外部画面へ切り替え、外すとメイン画面に戻ります"
            stacked: true

            SettingsDeviceList {
                model: displaySettings.screenNames
                currentIndex: displaySettings.screenIndex
                onPicked: (index) => displaySettings.screenIndex = index
            }
        }

        SettingsInfoRow {
            visible: !displaySettings.isEglfs
            label: "表示中の画面"
            value: (displaySettings.targetScreenName !== "" ? displaySettings.targetScreenName : "--")
                   + (displaySettings.usingFallback ? "(選んだ画面が未接続のためメイン画面)" : "")
            valueColor: displaySettings.usingFallback ? Theme.warn : Theme.textPrimary
        }

        SettingsRow {
            label: "画面の回転"
            description: "タッチの向きも合わせて回ります"

            SettingsChoice {
                model: ["0°", "90°", "180°", "270°"]
                currentIndex: displaySettings.rotation / 90
                onPicked: (index) => displaySettings.rotation = index * 90
            }
        }

        SettingsRow {
            label: "画面の端のボタン"
            description: "物理ボタンの代わりに、画面の端にメニュー・音量・明るさのボタンを並べます(押しっぱなしで連続して変わります)。各画面はその分だけ狭くなります"
            SettingsChoice {
                model: ["出さない", "左端", "右端"]
                currentIndex: displaySettings.sideButtons
                onPicked: (index) => displaySettings.sideButtons = index
            }
        }

        SettingsNote {
            visible: !displaySettings.isEglfs
            text: "外部モニターへの複製表示(ミラー)は、OS のディスプレイ設定で行ってください。現在のプラットフォーム: "
                  + displaySettings.platformName
        }
    }

    // ---- eglfs(DRM/KMS): 操作する画面と、外部モニターへのミラー(drmDisplay) ----
    SettingsSection {
        visible: displaySettings.isEglfs
        title: "外部モニター"
        icon: "connected_tv"

        SettingsRow {
            label: "外部モニターにミラー"
            description: "操作する画面と同じ表示を映します。抜き差しはすぐ反映されます"

            SettingsSwitch {
                checked: drmDisplay.mirrorEnabled
                onToggled: (value) => drmDisplay.mirrorEnabled = value
            }
        }

        SettingsRow {
            visible: drmDisplay.mirrorEnabled
            label: "解像度の合わせ方"
            description: "同じ解像度があればそのまま映し、無ければ縦横比を保って拡大縮小します。「拡大縮小」は常に外部モニターの推奨解像度で映します"

            SettingsChoice {
                model: ["同じ解像度を優先", "拡大縮小"]
                currentIndex: drmDisplay.scaleMode
                onPicked: (index) => drmDisplay.scaleMode = index
            }
        }

        SettingsRow {
            label: "操作する画面"
            description: "タッチを受ける画面です。変更は再起動後に反映されます"
            stacked: true

            SettingsDeviceList {
                model: drmDisplay.mainChoices
                currentIndex: drmDisplay.mainChoiceIndex
                onPicked: (index) => drmDisplay.mainChoiceIndex = index
            }
        }

        // 画面(コネクタ)ごとの状態
        Repeater {
            model: drmDisplay.outputs
            SettingsInfoRow {
                required property var modelData
                label: modelData.name
                value: modelData.role + (modelData.detail !== "" ? " — " + modelData.detail : "")
                valueColor: modelData.role === "ミラーできません" ? Theme.warn
                          : (modelData.connected ? Theme.textPrimary : Theme.textSecondary)
            }
        }

        SettingsRow {
            visible: drmDisplay.restartRequired
            label: "再起動して反映"

            ActionButton {
                text: "今すぐ再起動"
                onClicked: displaySettings.restartApp()
            }
        }

        SettingsNote {
            text: drmDisplay.statusText
                  + "。外部モニターには、操作する画面の画をそのまま表示します(描画の負荷は増えません)。"
                  + "同じ GPU につながっている画面だけが対象です。"
        }
    }
}
