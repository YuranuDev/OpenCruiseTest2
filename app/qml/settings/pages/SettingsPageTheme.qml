// 設定「表示と操作 > テーマ・背景」: テーマ (シンプル / クラシック)・昼夜・Android Auto との連動・アクセント色 (プリセット・カスタム色) と、
//   背景 (無地・模様・画像と濃さ)。どちらも themeSettings(ui/ThemeSettings)。
import QtQuick
import OpenCruise

SettingsPage {
    id: page

    // 設定画面を開いたときに、背景の画像フォルダを読み直す (置いた画像がすぐ選べるように)
    Component.onCompleted: {
        themeSettings.refreshBackgroundImages()
    }

    SettingsSection {
        title: "テーマ"
        icon: "brightness_6"

        SettingsRow {
            label: "テーマ"
            description: themeSettings.style === "classic"
                         ? "2000 年代ごろの車の内装に合う見た目です。ガンメタ (夜)・シルバー (昼) の面に控えめな立体感、照明色はアンバーが基本です"
                         : "平らな面と大きめの角丸の、これまでの見た目です"
            SettingsChoice {
                model: ["シンプル", "クラシック"]
                currentIndex: themeSettings.style === "classic" ? 1 : 0
                onPicked: (index) => themeSettings.style = index === 1 ? "classic" : "simple"
            }
        }

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
            id: accentRow
            label: "アクセント色"
            description: "ボタンや強調の色です。テーマ (シンプル / クラシック) ごとに、色の候補が変わります"
            stacked: true

            SettingsColorPalette {
                width: Math.min(accentRow.width, 760 * Theme.uiScale)
                swatchSize: 56
                showCheck: true
                // プリセット + 末尾に「カスタム」 (自由に決めた色。まだ決めていなければ灰色の見本)
                options: Theme.accentPresets.map((c, i) => ({ label: Theme.accentNames[i], value: String(i), swatch: c }))
                         .concat([{ label: "カスタム", value: "custom",
                                    swatch: androidAuto.accentCustom !== "" ? androidAuto.accentCustom : Theme.textSecondary }])
                selectedValue: androidAuto.accentCustom !== ""
                               ? "custom" : String(Math.min(androidAuto.accentIndex, Theme.accentPresets.length - 1))
                onPicked: (v) => {
                    if (v === "custom") {
                        // 今のアクセント色を出発点にして、自由に変えられるようにする
                        if (androidAuto.accentCustom === "") androidAuto.accentCustom = String(Theme.accentBase)
                    } else {
                        androidAuto.accentCustom = ""
                        androidAuto.accentIndex = parseInt(v)
                    }
                }
            }
        }

        SettingsRow {
            id: customRow
            visible: androidAuto.accentCustom !== ""
            label: "カスタム色"
            description: "色相・鮮やかさ・明るさで自由に決めます (「#rrggbb」も入力できます)。文字が読めなくなるので、暗すぎる色にはできません"
            stacked: true

            SettingsColorPicker {
                width: Math.min(customRow.width, 640 * Theme.uiScale)
                color: androidAuto.accentCustom !== "" ? androidAuto.accentCustom : "#4da3ff"
                onPicked: (c) => androidAuto.accentCustom = c
            }
        }
    }

    SettingsSection {
        title: "背景"
        icon: "wallpaper"

        SettingsRow {
            label: "背景"
            description: "「テーマに合わせる」は、シンプルなら無地、クラシックならカーボンです"
            stacked: true
            SettingsChoice {
                model: ["テーマに合わせる", "無地", "カーボン", "ヘアライン", "パンチング", "ストライプ", "画像"]
                readonly property var kinds: ["auto", "none", "carbon", "brushed", "dots", "stripes", "image"]
                currentIndex: Math.max(0, kinds.indexOf(themeSettings.background))
                onPicked: (index) => themeSettings.background = kinds[index]
            }
        }

        // ---- 画像 ----
        SettingsRow {
            visible: themeSettings.background === "image" && themeSettings.backgroundImages.length > 0
            label: "画像"
            stacked: true
            SettingsChoice {
                model: themeSettings.backgroundImages
                currentIndex: themeSettings.backgroundImages.indexOf(themeSettings.backgroundImage)
                onPicked: (index) => themeSettings.backgroundImage = themeSettings.backgroundImages[index]
            }
        }
        SettingsRow {
            visible: themeSettings.background === "image"
            label: "画像の表示"
            SettingsChoice {
                model: ["並べる", "画面を埋める", "引き伸ばす"]
                currentIndex: themeSettings.backgroundFit
                onPicked: (index) => themeSettings.backgroundFit = index
            }
        }
        SettingsNote {
            visible: themeSettings.background === "image"
            text: (themeSettings.backgroundImages.length === 0 ? "画像がまだありません。" : "")
                  + "次のフォルダに PNG / JPEG を置くと、ここで選べます (置いたら「読み直す」): " + themeSettings.backgroundFolder
        }
        SettingsRow {
            visible: themeSettings.background === "image"
            label: "画像フォルダを読み直す"
            ActionButton {
                text: "読み直す"
                onClicked: themeSettings.refreshBackgroundImages()
            }
        }

        SettingsRow {
            visible: themeSettings.background !== "none" && !(themeSettings.background === "auto" && themeSettings.style !== "classic")
            label: "背景の濃さ"
            description: "濃くすると模様・画像がはっきりしますが、文字が読みにくくなることがあります"
            SettingsSlider {
                iconName: "wallpaper"
                iconMinName: "wallpaper"
                value: themeSettings.backgroundOpacity
                onMoved: (v) => themeSettings.backgroundOpacity = v
            }
        }

        SettingsNote {
            text: "キャラなどの画像は、初期画面の「編集」→ バーの「画像」で、ページごとに好きな場所へ置けます"
                  + "(ウィジェットの奥・手前、ステータスバーの上も)。画像のフォルダ： " + themeSettings.decorationFolder
        }
    }
}
