// 設定ジャンル「表示」: 昼夜テーマ・Android Auto との連動・アクセント色・画面の明るさ・
//   表示する画面(外部画面)と回転・描画方式(垂直同期・フレームレート)。画面と描画は displaySettings(core/DisplaySettings)。
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
            description: "Ctrl+Shift+L / K で段階的に変えられます(L で明るく、K で暗く)"

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

        SettingsRow {
            label: "表示する画面"
            description: "「外部画面があれば外部画面」にすると、起動時や接続したときに自動で外部画面へ切り替え、外すとメイン画面に戻ります。"
                         + "画面を指定した場合も、その画面が外れている間はメイン画面に出し、つながると戻ります"
            stacked: true

            SettingsDeviceList {
                model: displaySettings.screenNames
                currentIndex: displaySettings.screenIndex
                onPicked: (index) => displaySettings.screenIndex = index
            }
        }

        SettingsInfoRow {
            label: "表示中の画面"
            value: (displaySettings.targetScreenName !== "" ? displaySettings.targetScreenName : "--")
                   + (displaySettings.usingFallback ? "(選んだ画面が未接続のためメイン画面)" : "")
            valueColor: displaySettings.usingFallback ? Theme.warn : Theme.textPrimary
        }

        SettingsInfoRow {
            label: "外部画面"
            value: displaySettings.externalConnected ? "接続中" : "なし"
        }

        SettingsRow {
            label: "全部の画面に表示"
            description: "上で選んだ画面(操作する画面)以外の、つながっているすべての画面にも同じ表示を映します。映した画面は見るだけで、操作はできません"

            SettingsSwitch {
                checked: displaySettings.mirrorAll
                onToggled: (value) => displaySettings.mirrorAll = value
            }
        }

        SettingsRow {
            visible: displaySettings.mirrorAll
            label: "ミラーの方式"
            description: "OS は画面の複製表示(" + (displaySettings.osMirrorSupported ? displaySettings.osMirrorBackend : "この環境では使えません")
                         + ")を使い、アプリの負荷が増えません。アプリ内は表示を写して映すので、どの環境でも使えますが負荷が増えます"

            SettingsChoice {
                model: ["アプリ内", "OS"]
                currentIndex: displaySettings.mirrorMethod
                onPicked: (index) => displaySettings.mirrorMethod = index
            }
        }

        SettingsInfoRow {
            visible: displaySettings.mirrorAll && displaySettings.mirrorMethod === 1
            label: "OS のミラー"
            value: displaySettings.osMirrorStatus + (displaySettings.osMirrorSupported ? "" : "(代わりにアプリ内の方式で映します)")
            valueColor: displaySettings.osMirrorSupported ? Theme.textPrimary : Theme.warn
        }

        SettingsRow {
            visible: displaySettings.appMirrorActive
            label: "映す画面の更新回数"
            description: "多いほど滑らかですが、描画の負荷が上がります"

            SettingsChoice {
                model: ["15 回/秒", "30 回/秒", "60 回/秒"]
                currentIndex: displaySettings.mirrorFps <= 15 ? 0 : (displaySettings.mirrorFps >= 60 ? 2 : 1)
                onPicked: (index) => displaySettings.mirrorFps = [15, 30, 60][index]
            }
        }

        SettingsRow {
            label: "画面の回転"
            description: "縦置きの画面などに合わせて、表示全体を回します(タッチの向きも合わせて回ります)"

            SettingsChoice {
                model: ["0°", "90°", "180°", "270°"]
                currentIndex: displaySettings.rotation / 90
                onPicked: (index) => displaySettings.rotation = index * 90
            }
        }

        SettingsNote {
            text: "画面の選択と回転はすぐに反映されます。"
                  + "eglfs(デスクトップ環境なしで直接表示)では出力先を途中で変えられないことがあり、"
                  + "その場合は QT_QPA_EGLFS_KMS_CONFIG で出力する画面を指定してください。現在のプラットフォーム: "
                  + displaySettings.platformName
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

        SettingsRow {
            visible: displaySettings.restartRequired
            label: "再起動して反映"
            description: "描画の設定は、アプリを再起動したときに反映されます"

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
