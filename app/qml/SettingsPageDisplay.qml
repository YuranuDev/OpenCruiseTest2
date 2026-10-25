// 設定ジャンル「表示」: 昼夜テーマ・Android Auto との連動・アクセント色・画面の明るさ・
//   表示する画面と回転・描画方式(垂直同期・フレームレート)は displaySettings(core/DisplaySettings)、
//   eglfs での操作する画面と外部モニターへのミラーは drmDisplay(core/DrmDisplay)。
import QtQuick

SettingsPage {
    SettingsSection {
        title: "テーマ"
        icon: "brightness_6"

        SettingsRow {
            label: "昼夜"
            description: "自動は 6:00〜18:00 が昼です"

            SettingsChoice {
                model: ["昼", "夜", "自動"]
                currentIndex: androidAuto.themeMode
                onPicked: (index) => androidAuto.themeMode = index
            }
        }

        SettingsRow {
            label: "Android Auto も連動"
            description: "スマホの Android Auto 設定で昼夜を「自動」にしているとき、車載機の昼夜に従います"

            SettingsSwitch {
                checked: androidAuto.aaFollowsTheme
                onToggled: (value) => androidAuto.aaFollowsTheme = value
            }
        }

        SettingsRow {
            label: "アクセント色"
            stacked: true

            Row {
                spacing: 16 * Theme.uiScale

                Repeater {
                    model: Theme.accentPresets

                    Rectangle {
                        readonly property bool selected: androidAuto.accentIndex === index
                        width: 64 * Theme.uiScale
                        height: width
                        radius: width / 2
                        color: modelData
                        border.width: selected ? 4 : 1
                        border.color: selected ? Theme.textPrimary : Theme.panelBorder
                        scale: swatchMouse.pressed ? 0.94 : 1.0
                        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

                        // 色だけに頼らず、選択中はチェックマークも出す
                        MaterialIcon {
                            visible: parent.selected
                            anchors.centerIn: parent
                            name: "check"
                            size: 36 * Theme.uiScale
                            color: "#0d1015"
                        }
                        MouseArea {
                            id: swatchMouse
                            anchors.fill: parent
                            onClicked: { androidAuto.accentIndex = index }
                        }
                    }
                }
            }
        }
    }

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

    SettingsSection {
        title: "描画"
        icon: "speed"

        SettingsRow {
            label: "描画方式"
            description: "画面が乱れる・起動しないときに切り替えます。ソフトウェアは GPU を使わない代わりに重く、Android Auto の映像が出ない場合があります"

            SettingsChoice {
                model: ["自動", "OpenGL", "Vulkan", "ソフトウェア"]
                currentIndex: displaySettings.graphicsApi
                onPicked: (index) => displaySettings.graphicsApi = index
            }
        }

        SettingsRow {
            label: "垂直同期"
            description: "オンにすると画面のちらつき(ティアリング)を防ぎます。オフは遅延が減る代わりに、描画が増えて消費電力が上がります"

            SettingsSwitch {
                checked: displaySettings.vsync
                onToggled: (value) => displaySettings.vsync = value
            }
        }

        SettingsRow {
            visible: displaySettings.vsync
            label: "フレームレート"
            description: "画面のリフレッシュレートに対する描画の割合(60Hz の画面で 1/2 なら 30fps)。下げると省電力になります"

            SettingsChoice {
                model: ["最大", "1/2", "1/3"]
                currentIndex: displaySettings.frameDivider - 1
                onPicked: (index) => displaySettings.frameDivider = index + 1
            }
        }

        SettingsInfoRow { label: "使用中の描画方式"; value: displaySettings.activeGraphicsApi }
        SettingsInfoRow {
            visible: displaySettings.graphicsNote !== ""
            label: "描画方式の注意"
            value: displaySettings.graphicsNote
            valueColor: Theme.warn
        }

        SettingsRow {
            visible: displaySettings.restartRequired
            label: "再起動して反映"

            ActionButton {
                text: "今すぐ再起動"
                onClicked: displaySettings.restartApp()
            }
        }

        SettingsNote {
            text: "垂直同期とフレームレートは、描画方式やドライバによっては効かないことがあります(主に OpenGL で有効)。"
        }
    }
}
