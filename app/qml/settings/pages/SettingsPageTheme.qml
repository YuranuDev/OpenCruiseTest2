// 設定「表示と操作 > テーマ・背景」: テーマ(シンプル / クラシック)・昼夜・Android Auto との連動・アクセント色(プリセット・カスタム色)と、
//   背景(無地・模様・画像と濃さ)。どちらも themeSettings(ui/ThemeSettings)。
import QtQuick
import OpenCruise

SettingsPage {
    id: page

    // 設定画面を開いたときに、背景の画像フォルダを読み直す(置いた画像がすぐ選べるように)。USB メモリの画像も探す
    Component.onCompleted: {
        themeSettings.refreshBackgroundImages()
        imageImporter.rescan()
    }

    // ---- USB メモリから画像を取り込む(imageImporter = ui/ImageImporter) ----
    // 選んだ画像(path → true)。候補が変わっても、今ある候補の分だけを数える(消えた分は自然に外れる)
    property var picked: ({})
    readonly property bool canImport: !imageImporter.scanning && !imageImporter.importing
                                      && updater.state !== "downloading" && updater.state !== "installing"
    function selectedPaths() {
        return imageImporter.candidates.filter(c => picked[c.path] === true).map(c => c.path)
    }
    function setPicked(path, on) {
        const m = Object.assign({}, picked)
        if (on) m[path] = true; else delete m[path]
        picked = m
    }
    function setAllPicked(on) {
        const m = {}
        if (on) imageImporter.candidates.forEach(c => { m[c.path] = true })
        picked = m
    }
    function sizeText(n) { return n >= 1048576 ? (n / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(n / 1024)) + " KB" }
    function suggestText(k) { return k === "background" ? "背景用のフォルダ" : k === "decoration" ? "飾り用のフォルダ" : "" }
    function importSelected(kind) {
        const list = selectedPaths()
        if (canImport && list.length > 0) imageImporter.importFiles(list, kind)
    }

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
        title: "USB メモリから画像を取り込む"
        icon: "usb"

        SettingsNote {
            text: "USB メモリは読み取り専用でつなぐので、元のファイルは消えず、本体へコピーされます。PNG / JPEG / WebP / GIF(1 枚 32 MB・縦横 8192 px まで)が対象です。"
                  + "USB メモリの中のフォルダ名が backgrounds なら背景、decorations なら飾りへ、自動で振り分けられます"
        }
        SettingsNote {
            visible: imageImporter.candidates.length === 0
            text: imageImporter.scanning ? "USB メモリを探しています…"
                  : imageImporter.usbPresent ? "USB メモリに取り込める画像が見つかりません(3 階層目までを探します)"
                                             : "画像を入れた USB メモリを挿すと、ここに出ます"
        }
        SettingsNote {
            visible: imageImporter.omitted > 0
            text: "画像が多いので、先頭の " + imageImporter.candidates.length + " 枚だけを出しています(ほかに " + imageImporter.omitted + " 枚)。フォルダを分けて入れ直してください"
        }
        SettingsNote {
            visible: !page.canImport && !imageImporter.importing && !imageImporter.scanning
            text: "アプリの更新中は、画像を取り込めません"
        }

        Repeater {
            model: imageImporter.candidates
            SettingsRow {
                required property var modelData
                label: modelData.file
                description: [modelData.folder !== "" ? modelData.device + "/" + modelData.folder : modelData.device,
                              page.sizeText(modelData.size), page.suggestText(modelData.suggested)]
                             .filter(x => x !== "").join(" ・ ")
                SettingsSwitch {
                    checked: page.picked[modelData.path] === true
                    onToggled: (value) => page.setPicked(modelData.path, value)
                }
            }
        }

        SettingsRow {
            id: importRow
            visible: imageImporter.candidates.length > 0
            label: "取り込む"
            description: page.selectedPaths().length + " 枚を選んでいます"
            stacked: true
            Flow {
                width: importRow.width
                spacing: 12 * Theme.uiScale
                ActionButton { text: "すべて選ぶ"; onClicked: page.setAllPicked(true) }
                ActionButton { text: "選択を外す"; onClicked: page.setAllPicked(false) }
                ActionButton {
                    text: "選んだ画像を背景へ"
                    selected: true
                    opacity: page.canImport && page.selectedPaths().length > 0 ? 1 : 0.4
                    onClicked: page.importSelected("background")
                }
                ActionButton {
                    text: "選んだ画像を飾りへ"
                    selected: true
                    opacity: page.canImport && page.selectedPaths().length > 0 ? 1 : 0.4
                    onClicked: page.importSelected("decoration")
                }
                ActionButton {
                    text: "フォルダ名で振り分けて取り込む"
                    opacity: page.canImport && imageImporter.candidates.some(c => c.suggested !== "") ? 1 : 0.4
                    onClicked: {
                        const list = imageImporter.candidates.filter(c => c.suggested !== "").map(c => c.path)
                        if (page.canImport && list.length > 0) imageImporter.importFiles(list, "auto")
                    }
                }
            }
        }
        SettingsRow {
            label: "USB メモリを探し直す"
            ActionButton {
                text: "探し直す"
                opacity: page.canImport ? 1 : 0.4
                onClicked: if (page.canImport) imageImporter.rescan()
            }
        }
        SettingsNote {
            visible: imageImporter.message !== ""
            text: imageImporter.message
        }
    }
}
