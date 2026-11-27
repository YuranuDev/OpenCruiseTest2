// 設定「表示と操作 > USB メモリと画像」: USB メモリから背景・飾りの画像を取り込む
import QtQuick
import OpenCruise

SettingsPage {
    id: page

    // 設定画面を開いたときに、背景の画像フォルダを読み直す (置いた画像がすぐ選べるように)。USB メモリの画像も探す
    Component.onCompleted: {
        themeSettings.refreshBackgroundImages()
        imageImporter.rescan()
    }

    // ---- USB メモリから画像を取り込む (imageImporter = ui/ImageImporter) ----
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
        title: "USB メモリから画像を取り込む"
        icon: "usb"

        SettingsNote {
            text: "USB メモリは読み取り専用でつなぐので、元のファイルは消えず、本体へコピーされます。PNG / JPEG / WebP / GIF(1 枚 32 MB・縦横 8192 px まで)が対象です。"
                  + "USB メモリの中のフォルダ名が backgrounds なら背景、decorations なら飾りへ、自動で振り分けられます"
        }
        SettingsNote {
            visible: imageImporter.candidates.length === 0
            text: imageImporter.scanning ? "USB メモリを探しています…"
                  : imageImporter.usbPresent ? "USB メモリに取り込める画像が見つかりません (3 階層目までを探します)"
                                             : "画像を入れた USB メモリを挿すと、ここに出ます"
        }
        SettingsNote {
            visible: imageImporter.omitted > 0
            text: "画像が多いので、先頭の " + imageImporter.candidates.length + " 枚だけを出しています (ほかに " + imageImporter.omitted + " 枚)。フォルダを分けて入れ直してください"
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
