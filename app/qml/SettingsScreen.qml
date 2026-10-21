// 設定画面（仮）。現状の接続診断情報と、各機能の実装状況を表示する。
import QtQuick

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
        Text { id: name; width: 220; color: Theme.textSecondary; font.pixelSize: 20 }
        Text { id: val; width: 640; color: parent.valueColor; font.pixelSize: 20; wrapMode: Text.WordWrap }
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
            height: videoColumn.implicitHeight + 36
            color: Theme.panel
            radius: Theme.radius
            border.color: Theme.panelBorder

            Column {
                id: videoColumn
                x: 20; y: 18
                spacing: 12
                Text { text: "映像・表示"; color: Theme.textPrimary; font.pixelSize: 26 }
                Row {
                    spacing: 10
                    Text { width: 220; anchors.verticalCenter: parent.verticalCenter; text: "解像度"; color: Theme.textSecondary; font.pixelSize: 20 }
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
                    Text { width: 220; anchors.verticalCenter: parent.verticalCenter; text: "フレームレート"; color: Theme.textSecondary; font.pixelSize: 20 }
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
                    Text { width: 220; anchors.verticalCenter: parent.verticalCenter; text: "接続後フルスクリーン"; color: Theme.textSecondary; font.pixelSize: 20 }
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
                Text {
                    width: 860
                    wrapMode: Text.WordWrap
                    text: "解像度・fps を変更すると、接続中の場合は一度正規に切断してから再接続待機になります。"
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
                Text { text: "Android Auto"; color: Theme.textPrimary; font.pixelSize: 26 }
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
                Text { text: "車両情報 (CAN)"; color: Theme.textPrimary; font.pixelSize: 26 }
                InfoRow { label: "データ源"; value: can.sourceText + "（実 CAN 通信は未実装）"; valueColor: Theme.warn }
            }
        }

        Text {
            text: "OpenCruise 0.1.0 (プロトタイプ)"
            color: Theme.textSecondary
            font.pixelSize: 16
        }
    }
    }
}
