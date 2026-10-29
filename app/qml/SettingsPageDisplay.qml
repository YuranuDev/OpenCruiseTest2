// 設定ジャンル「表示」: テーマ(シンプル / クラシック)と背景(themeSettings)・昼夜テーマ・Android Auto との連動・アクセント色(プリセット・自由に決めたカスタム色)・画面の明るさ・
//   表示する画面と回転・描画方式(垂直同期・フレームレート)は displaySettings(core/DisplaySettings)、
//   eglfs での操作する画面と外部モニターへのミラーは drmDisplay(core/DrmDisplay)。
import QtQuick
import OpenCruise

SettingsPage {
    // 設定画面を開いたときに、背景の画像フォルダを読み直す(置いた画像がすぐ選べるように)
    Component.onCompleted: themeSettings.refreshBackgroundImages()

    SettingsSection {
        title: "テーマ"
        icon: "brightness_6"

        SettingsRow {
            label: "テーマ"
            description: themeSettings.style === "classic"
                         ? "2000 年代ごろの車の内装に合う見た目です。ガンメタ(夜)・シルバー(昼)の面に控えめな立体感、照明色はアンバーが基本です"
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
            description: "ボタンや強調の色です。テーマ(シンプル / クラシック)ごとに、色の候補が変わります"
            stacked: true

            SettingsColorPalette {
                width: Math.min(accentRow.width, 760 * Theme.uiScale)
                swatchSize: 56
                showCheck: true
                // プリセット + 末尾に「カスタム」(自由に決めた色。まだ決めていなければ灰色の見本)
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
            description: "色相・鮮やかさ・明るさで自由に決めます(「#rrggbb」も入力できます)。文字が読めなくなるので、暗すぎる色にはできません"
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
                  + "次のフォルダに PNG / JPEG を置くと、ここで選べます(置いたら「読み直す」): " + themeSettings.backgroundFolder
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
                  + "(ウィジェットの奥・手前、ステータスバーの上も)。画像のフォルダ: " + themeSettings.decorationFolder
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
