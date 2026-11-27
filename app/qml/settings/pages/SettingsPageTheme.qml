// 設定「表示と操作 > テーマ・背景」: 昼夜別の見た目、Android Auto との連動、背景画像など。
import QtQuick
import OpenCruise

SettingsPage {
    id: page
    property bool editingNight: androidAuto.nightActive
    readonly property var profile: editingNight ? themeSettings.nightProfile : themeSettings.dayProfile

    function updateProfile(key, value) {
        const values = {}
        values[key] = value
        updateProfileValues(values)
    }
    function updateProfileValues(values) {
        const next = Object.assign({}, page.profile)
        Object.assign(next, values)
        if (page.editingNight) themeSettings.nightProfile = next
        else themeSettings.dayProfile = next
    }

    Component.onCompleted: themeSettings.refreshBackgroundImages()

    SettingsSection {
        title: "テーマ"
        icon: "brightness_6"

        SettingsRow {
            label: "編集する時間帯"
            description: "昼と夜のテーマ・アクセント色・背景を別々に設定できます。現在の表示: "
                         + (androidAuto.nightActive ? "夜" : "昼")
            SettingsChoice {
                model: ["昼", "夜"]
                currentIndex: page.editingNight ? 1 : 0
                onPicked: (index) => page.editingNight = index === 1
            }
        }

        SettingsRow {
            label: "テーマ"
            description: page.profile.style === "classic"
                         ? "2000 年代ごろの車の内装に合う見た目です。ガンメタ (夜)・シルバー (昼) の面に控えめな立体感、照明色はアンバーが基本です"
                         : "平らな面と大きめの角丸の、これまでの見た目です"
            SettingsChoice {
                model: ["シンプル", "クラシック"]
                currentIndex: page.profile.style === "classic" ? 1 : 0
                onPicked: (index) => page.updateProfile("style", index === 1 ? "classic" : "simple")
            }
        }

        SettingsRow {
            label: "昼夜"
            description: "自動は 6:00〜18:00 が昼です。選択した昼夜プロファイルと背景に切り替わります"
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
            id: accentRow
            label: "アクセント色"
            description: "ボタンや強調の色です。テーマ (シンプル / クラシック) ごとに、色の候補が変わります"
            stacked: true
            SettingsColorPalette {
                width: Math.min(accentRow.width, 760 * Theme.uiScale)
                swatchSize: 56
                showCheck: true
                readonly property var profilePresets: Theme.accentPresetsFor(page.profile.style)
                readonly property var profileNames: Theme.accentNamesFor(page.profile.style)
                options: profilePresets.map((c, i) => ({ label: profileNames[i], value: String(i), swatch: c }))
                         .concat([{ label: "カスタム", value: "custom",
                                    swatch: page.profile.accentCustom !== "" ? page.profile.accentCustom : Theme.textSecondary }])
                selectedValue: page.profile.accentCustom !== ""
                               ? "custom" : String(Math.min(page.profile.accentIndex, profilePresets.length - 1))
                onPicked: (v) => {
                    if (v === "custom") {
                        if (page.profile.accentCustom === "")
                            page.updateProfile("accentCustom", profilePresets[Math.min(page.profile.accentIndex, profilePresets.length - 1)])
                    } else {
                        page.updateProfileValues({ accentCustom: "", accentIndex: parseInt(v) })
                    }
                }
            }
        }

        SettingsRow {
            id: customRow
            visible: page.profile.accentCustom !== ""
            label: "カスタム色"
            description: "色相・鮮やかさ・明るさで自由に決めます (「#rrggbb」も入力できます)。文字が読めなくなるので、暗すぎる色にはできません"
            stacked: true
            SettingsColorPicker {
                width: Math.min(customRow.width, 640 * Theme.uiScale)
                color: page.profile.accentCustom !== "" ? page.profile.accentCustom : "#4da3ff"
                onPicked: (c) => page.updateProfile("accentCustom", c)
            }
        }
    }

    SettingsSection {
        title: "背景"
        icon: "wallpaper"

        SettingsRow {
            label: "背景"
            description: (page.editingNight ? "夜" : "昼") + "側の背景です。「テーマに合わせる」は、シンプルなら無地、クラシックならカーボンです"
            stacked: true
            SettingsChoice {
                model: ["テーマに合わせる", "無地", "カーボン", "ヘアライン", "パンチング", "ストライプ", "画像"]
                readonly property var kinds: ["auto", "none", "carbon", "brushed", "dots", "stripes", "image"]
                currentIndex: Math.max(0, kinds.indexOf(page.profile.background))
                onPicked: (index) => page.updateProfile("background", kinds[index])
            }
        }

        SettingsRow {
            visible: page.profile.background === "image" && themeSettings.backgroundImages.length > 0
            label: "画像"
            stacked: true
            SettingsChoice {
                model: themeSettings.backgroundImages
                currentIndex: themeSettings.backgroundImages.indexOf(page.profile.backgroundImage)
                onPicked: (index) => page.updateProfile("backgroundImage", themeSettings.backgroundImages[index])
            }
        }
        SettingsRow {
            visible: page.profile.background === "image"
            label: "画像の表示"
            SettingsChoice {
                model: ["並べる", "画面を埋める", "引き伸ばす"]
                currentIndex: page.profile.backgroundFit
                onPicked: (index) => page.updateProfile("backgroundFit", index)
            }
        }
        SettingsNote {
            visible: page.profile.background === "image"
            text: (themeSettings.backgroundImages.length === 0 ? "画像がまだありません。" : "")
                  + "次のフォルダに PNG / JPEG を置くと、ここで選べます (置いたら「読み直す」): " + themeSettings.backgroundFolder
        }
        SettingsRow {
            visible: page.profile.background === "image"
            label: "画像フォルダを読み直す"
            ActionButton {
                text: "読み直す"
                onClicked: themeSettings.refreshBackgroundImages()
            }
        }

        SettingsRow {
            visible: page.profile.background !== "none" && !(page.profile.background === "auto" && page.profile.style !== "classic")
            label: "背景の濃さ"
            description: "濃くすると模様・画像がはっきりしますが、文字が読みにくくなることがあります"
            SettingsSlider {
                iconName: "wallpaper"
                iconMinName: "wallpaper"
                value: page.profile.backgroundOpacity
                onMoved: (v) => page.updateProfile("backgroundOpacity", v)
            }
        }

        SettingsNote {
            text: "キャラなどの画像は、初期画面の「編集」→「画像」で配置します。編集バーで昼・夜を選び、"
                  + "時間帯ごとに配置を分けられます(ウィジェットの奥・パネル・手前)。画像のフォルダ： " + themeSettings.decorationFolder
        }
    }
}
