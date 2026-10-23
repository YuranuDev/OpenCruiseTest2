// 設定ジャンル「表示」: 昼夜テーマ・Android Auto との連動・アクセント色・画面の明るさ。
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
}
