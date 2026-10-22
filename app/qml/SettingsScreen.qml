// 設定画面（仮）。ユーザー名・フォント、映像・表示、現状の接続診断情報を表示する。
import QtQuick
import QtQuick.Controls

Rectangle {
    id: root
    color: Theme.background
    signal back()

    // 診断情報の 1 行（左: 項目名、右: 値）
    component InfoRow: Row {
        property alias label: name.text
        property alias value: val.text
        property color valueColor: Theme.textPrimary
        spacing: 20
        Text { font.family: Theme.fontFamily; id: name; width: 220; color: Theme.textSecondary; font.pixelSize: 20 }
        Text { font.family: Theme.fontFamily; id: val; width: 640; color: parent.valueColor; font.pixelSize: 20; wrapMode: Text.WordWrap }
    }

    Item {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: Theme.margin }
        height: 76

        ActionButton {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            text: "← 戻る"
            onClicked: root.back()
        }
        Text {
            font.family: Theme.fontFamily
            anchors.centerIn: parent
            text: "設定"
            color: Theme.textPrimary
            font.pixelSize: 34
        }
    }

    Flickable {
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; margins: Theme.margin }
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

    Column {
        id: content
        width: parent.width
        spacing: Theme.margin

        Rectangle {
            width: parent.width
            height: userColumn.implicitHeight + 36
            color: Theme.panel
            radius: Theme.radius
            border.color: Theme.panelBorder

            Column {
                id: userColumn
                x: 20; y: 18
                width: parent.width - 40
                spacing: 12
                Text { font.family: Theme.fontFamily; text: "ユーザー・フォント"; color: Theme.textPrimary; font.pixelSize: 26 }
                Row {
                    spacing: 10
                    Text { font.family: Theme.fontFamily; width: 220; anchors.verticalCenter: parent.verticalCenter; text: "ユーザー名"; color: Theme.textSecondary; font.pixelSize: 20 }
                    // 初期画面の挨拶に使う。入力確定(Enter / フォーカス移動)で保存する
                    TextField {
                        id: nameField
                        width: 420
                        height: 52
                        text: appSettings.userName
                        placeholderText: "名前を入力(未設定なら挨拶のみ)"
                        font.family: Theme.fontFamily
                        font.pixelSize: 22
                        color: Theme.textPrimary
                        placeholderTextColor: Theme.textSecondary
                        selectByMouse: true
                        maximumLength: 24
                        leftPadding: 16
                        background: Rectangle {
                            radius: Theme.radius
                            color: Theme.background
                            border.width: nameField.activeFocus ? 2 : 1
                            border.color: nameField.activeFocus ? Theme.accent : Theme.panelBorder
                        }
                        onEditingFinished: appSettings.userName = text
                    }
                }
                Row {
                    spacing: 10
                    visible: appSettings.fontFamilies.length > 0
                    Text { font.family: Theme.fontFamily; width: 220; anchors.verticalCenter: parent.verticalCenter; text: "フォント"; color: Theme.textSecondary; font.pixelSize: 20 }
                    Repeater {
                        model: appSettings.fontFamilies
                        ActionButton {
                            text: modelData
                            selected: appSettings.fontFamily === modelData
                            onClicked: appSettings.fontFamily = modelData
                        }
                    }
                }
                Text {
                    font.family: Theme.fontFamily
                    visible: appSettings.fontFamilies.length === 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "同梱フォントを読み込めませんでした(実行ファイルの隣の fonts フォルダを確認してください)。OS 既定のフォントで表示しています。"
                    color: Theme.warn
                    font.pixelSize: 18
                }
                // 選択中フォントの見本(太さの違いも確認できる)
                Column {
                    visible: appSettings.fontFamilies.length > 0
                    spacing: 4
                    Text { font.family: Theme.fontFamily; text: "見本: 東京都 1234567890 ABCabc — 安全運転でいきましょう"; color: Theme.textPrimary; font.pixelSize: 24 }
                    Text { font.family: Theme.fontFamily; text: "Light 見本: 東京都 1234567890 ABCabc"; color: Theme.textSecondary; font.pixelSize: 22; font.weight: Font.Light }
                    Text { font.family: Theme.fontFamily; text: "Bold 見本: 東京都 1234567890 ABCabc"; color: Theme.textSecondary; font.pixelSize: 22; font.bold: true }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: videoColumn.implicitHeight + 36
            color: Theme.panel
            radius: Theme.radius
            border.color: Theme.panelBorder

            Column {
                id: videoColumn
                x: 20; y: 18
                spacing: 12
                Text { font.family: Theme.fontFamily; text: "映像・表示"; color: Theme.textPrimary; font.pixelSize: 26 }
                Row {
                    spacing: 10
                    Text { font.family: Theme.fontFamily; width: 220; anchors.verticalCenter: parent.verticalCenter; text: "解像度"; color: Theme.textSecondary; font.pixelSize: 20 }
                    Repeater {
                        model: ["800x480", "1280x720", "1920x1080"]
                        ActionButton {
                            text: modelData
                            selected: androidAuto.resolutionIndex === index
                            onClicked: androidAuto.resolutionIndex = index
                        }
                    }
                }
                Row {
                    spacing: 10
                    Text { font.family: Theme.fontFamily; width: 220; anchors.verticalCenter: parent.verticalCenter; text: "フレームレート"; color: Theme.textSecondary; font.pixelSize: 20 }
                    Repeater {
                        model: [30, 60]
                        ActionButton {
                            text: modelData + " fps"
                            selected: androidAuto.fps === modelData
                            onClicked: androidAuto.fps = modelData
                        }
                    }
                }
                Row {
                    spacing: 10
                    Text { font.family: Theme.fontFamily; width: 220; anchors.verticalCenter: parent.verticalCenter; text: "接続後フルスクリーン"; color: Theme.textSecondary; font.pixelSize: 20 }
                    ActionButton {
                        text: "ON"
                        selected: androidAuto.fullscreenOnStream
                        onClicked: androidAuto.fullscreenOnStream = true
                    }
                    ActionButton {
                        text: "OFF"
                        selected: !androidAuto.fullscreenOnStream
                        onClicked: androidAuto.fullscreenOnStream = false
                    }
                }
                Row {
                    spacing: 10
                    Text { font.family: Theme.fontFamily; width: 220; anchors.verticalCenter: parent.verticalCenter; text: "テーマ"; color: Theme.textSecondary; font.pixelSize: 20 }
                    Repeater {
                        model: ["昼", "夜", "自動"]
                        ActionButton {
                            text: modelData
                            selected: androidAuto.themeMode === index
                            onClicked: androidAuto.themeMode = index
                        }
                    }
                }
                Row {
                    spacing: 10
                    Text { font.family: Theme.fontFamily; width: 220; anchors.verticalCenter: parent.verticalCenter; text: "Android Auto も連動"; color: Theme.textSecondary; font.pixelSize: 20 }
                    ActionButton {
                        text: "ON"
                        selected: androidAuto.aaFollowsTheme
                        onClicked: androidAuto.aaFollowsTheme = true
                    }
                    ActionButton {
                        text: "OFF"
                        selected: !androidAuto.aaFollowsTheme
                        onClicked: androidAuto.aaFollowsTheme = false
                    }
                }
                Row {
                    spacing: 14
                    Text { font.family: Theme.fontFamily; width: 220; anchors.verticalCenter: parent.verticalCenter; text: "アクセント色"; color: Theme.textSecondary; font.pixelSize: 20 }
                    Repeater {
                        model: Theme.accentPresets
                        Rectangle {
                            width: 44; height: 44; radius: 22
                            color: modelData
                            border.width: androidAuto.accentIndex === index ? 4 : 1
                            border.color: androidAuto.accentIndex === index ? Theme.textPrimary : Theme.panelBorder
                            MouseArea { anchors.fill: parent; onClicked: androidAuto.accentIndex = index }
                        }
                    }
                }
                Text {
                    font.family: Theme.fontFamily
                    width: 860
                    wrapMode: Text.WordWrap
                    text: "解像度・fps を変更すると、接続中の場合は一度正規に切断してから再接続待機になります。"
                          + "自動テーマは 6:00〜18:00 が昼です。Android Auto 側のテーマは、スマホの Android Auto 設定で昼夜を「自動」にしているときに車載機の昼夜に従います。"
                          + "フルスクリーン中は、画面右端を左へスワイプ、または Esc / F10 / Menu / Windows キーでメニューを開けます。"
                    color: Theme.textSecondary
                    font.pixelSize: 16
                }
            }
        }

        Rectangle {
            width: parent.width
            height: aaColumn.implicitHeight + 36
            color: Theme.panel
            radius: Theme.radius
            border.color: Theme.panelBorder

            Column {
                id: aaColumn
                x: 20; y: 18
                spacing: 10
                Text { font.family: Theme.fontFamily; text: "Android Auto"; color: Theme.textPrimary; font.pixelSize: 26 }
                InfoRow { label: "状態"; value: androidAuto.stateText; valueColor: Theme.stateColor(androidAuto.stateKey) }
                InfoRow { label: "詳細"; value: androidAuto.detailText }
                InfoRow { label: "直近の切断/エラー"; value: androidAuto.lastIssue === "" ? "なし" : androidAuto.lastIssue }
                InfoRow { label: "受信フレーム数"; value: androidAuto.frameCount }
                InfoRow { label: "映像サイズ"; value: androidAuto.videoInfo }
                InfoRow { label: "aasdk 接続処理"; value: androidAuto.aasdkEnabled ? "ビルドに含まれる" : "含まれない (OFF)" }
            }
        }

        Rectangle {
            width: parent.width
            height: canColumn.implicitHeight + 36
            color: Theme.panel
            radius: Theme.radius
            border.color: Theme.panelBorder

            Column {
                id: canColumn
                x: 20; y: 18
                spacing: 10
                Text { font.family: Theme.fontFamily; text: "車両情報 (CAN)"; color: Theme.textPrimary; font.pixelSize: 26 }
                InfoRow { label: "データ源"; value: can.sourceText + "（実 CAN 通信は未実装）"; valueColor: Theme.warn }
            }
        }

        Text {
            font.family: Theme.fontFamily
            text: "OpenCruise 0.1.0 (プロトタイプ)"
            color: Theme.textSecondary
            font.pixelSize: 16
        }
    }
    }
}
