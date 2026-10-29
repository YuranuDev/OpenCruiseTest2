// 設定ジャンル「一般」: ユーザー名と表示フォント。
import QtQuick
import QtQuick.Controls

SettingsPage {
    SettingsSection {
        title: "ユーザー"
        icon: "person"

        SettingsRow {
            label: "ユーザー名"
            description: "初期画面の挨拶に使います(未設定なら挨拶のみ)"

            // 入力確定(Enter / フォーカス移動)で保存する
            TextField {
                id: nameField
                width: 420 * Theme.uiScale
                height: 64 * Theme.uiScale
                text: appSettings.userName
                placeholderText: "名前を入力"
                font.family: Theme.fontFamily
                font.pixelSize: 26 * Theme.uiScale
                color: Theme.textPrimary
                placeholderTextColor: Theme.textSecondary
                selectByMouse: true
                maximumLength: 24
                leftPadding: 18 * Theme.uiScale
                background: Rectangle {
                    radius: Theme.radius
                    color: Theme.background
                    border.width: nameField.activeFocus ? 2 : 1
                    border.color: nameField.activeFocus ? Theme.accent : Theme.panelBorder
                }
                onEditingFinished: appSettings.userName = text
            }
        }
    }

    SettingsSection {
        title: "フォント"
        icon: "text_fields"

        SettingsRow {
            visible: appSettings.fontFamilies.length > 0
            label: "表示フォント"
            stacked: true

            SettingsChoice {
                model: appSettings.fontFamilies
                currentIndex: appSettings.fontFamilies.indexOf(appSettings.fontFamily)
                onPicked: (index) => appSettings.fontFamily = appSettings.fontFamilies[index]
            }
        }

        SettingsNote {
            visible: appSettings.fontFamilies.length === 0
            text: "同梱フォントを読み込めませんでした(実行ファイルの隣の fonts フォルダを確認してください)。OS 既定のフォントで表示しています。"
            color: Theme.warn
        }

        // 選択中フォントの見本(太さの違いも確認できる)
        Column {
            visible: appSettings.fontFamilies.length > 0
            width: parent.width
            topPadding: 14 * Theme.uiScale
            bottomPadding: 6 * Theme.uiScale
            spacing: 4 * Theme.uiScale
            Text { font.family: Theme.fontFamily; text: "見本: 東京都 1234567890 ABCabc — 安全運転でいきましょう"; color: Theme.textPrimary; font.pixelSize: 26 * Theme.uiScale; width: parent.width; wrapMode: Text.WordWrap }
            Text { font.family: Theme.fontFamily; text: "Light 見本: 東京都 1234567890 ABCabc"; color: Theme.textSecondary; font.pixelSize: 24 * Theme.uiScale; font.weight: Font.Light }
            Text { font.family: Theme.fontFamily; text: "Bold 見本: 東京都 1234567890 ABCabc"; color: Theme.textSecondary; font.pixelSize: 24 * Theme.uiScale; font.bold: true }
        }

        // 数値(メーターの値・目盛り、グラフ、時計)だけ別のフォントにできる
        SettingsRow {
            visible: appSettings.fontFamilies.length > 0
            label: "数値のフォント"
            description: "メーターの値・目盛り、グラフ、時計の数字に使います"
            stacked: true

            SettingsChoice {
                model: ["文章と同じ"].concat(appSettings.fontFamilies)
                currentIndex: appSettings.numberFontFamily === "" ? 0 : appSettings.fontFamilies.indexOf(appSettings.numberFontFamily) + 1
                onPicked: (index) => appSettings.numberFontFamily = index === 0 ? "" : appSettings.fontFamilies[index - 1]
            }
        }

        SettingsRow {
            label: "数値を斜体にする"
            description: "メーターとグラフの値を斜めの字で表示します"

            SettingsSwitch {
                checked: appSettings.numberItalic
                onToggled: (value) => appSettings.numberItalic = value
            }
        }

        // 数値の見本(メーターの値と同じ太字)
        NumberText {
            width: parent.width
            height: Math.round(34 * Theme.uiScale * 1.6)   // 長いときは、幅に収まるまで小さくする(折り返さない)
            bold: true
            italic: Theme.numberItalic
            pixelSize: Math.round(34 * Theme.uiScale)
            minimumPixelSize: 10
            fit: true
            color: Theme.textPrimary
            text: "数値の見本: 0.50  88  3000  123.4  -1.0  12:34"
        }
    }
}
