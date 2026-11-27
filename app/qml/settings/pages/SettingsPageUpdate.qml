// 設定「システム > アップデート」: アプリの更新(updater = UpdateManager)。
//   今の版 / USB メモリにある更新ファイル / ネット(開発 PC の scripts/update-server.sh)の更新 / 進み具合と再起動 / 前の版に戻す
// 走行中(車速 5 km/h 以上)は更新を始めない(再起動で画面が消えるため)。
// 更新ファイルは scripts/build-os.sh --app-update で作る(USB メモリの直下か opencruise-update/ に置く)。
import QtQuick
import OpenCruise

SettingsPage {
    id: page
    readonly property bool busy: updater.state === "downloading" || updater.state === "installing"
    readonly property bool moving: VehicleSignals.has("speed") && VehicleSignals.value("speed") >= 5
    // 画像を USB メモリから取り込んでいる間(ImageImporter)は、更新の開始・再起動をしない(コピーが途中で止まらないように)
    readonly property bool copying: imageImporter.importing
    readonly property bool canStart: !busy && !moving && !copying
    function sizeText(n) { return n >= 1048576 ? (n / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(n / 1024)) + " KB" }
    function buildText(b) {
        const s = String(b || "")
        return s.length >= 12 ? s.substr(0, 4) + "-" + s.substr(4, 2) + "-" + s.substr(6, 2) + " " + s.substr(8, 2) + ":" + s.substr(10, 2) : (s || "不明")
    }

    // 1 つの更新ファイル(USB・ネット)の行
    component UpdateRow: SettingsRow {
        id: ur
        property var entry: ({})
        property string source: ""
        signal install()
        label: (entry.newer ? "新しい版: " : entry.current ? "今の版と同じ: " : "古い版: ") + (entry.buildText || page.buildText(entry.build))
        description: [source, entry.version ? "v" + entry.version : "", entry.size ? page.sizeText(entry.size) : "", entry.notes || ""]
                     .filter(x => x !== "").join(" ・ ")
        ActionButton {
            text: ur.entry.newer ? "更新する" : "この版を入れる"
            selected: ur.entry.newer === true
            opacity: page.canStart ? 1 : 0.4
            onClicked: if (page.canStart) ur.install()
        }
    }

    // ---- 状態(進み具合・再起動) ----
    SettingsSection {
        title: "アップデート"
        icon: "system_update"

        SettingsInfoRow { label: "今のアプリ"; value: page.buildText(updater.currentBuild) + (updater.runningUpdate ? "(更新で入れた版)" : "(OS に入っている版)") }
        SettingsInfoRow {
            visible: updater.builtinBuild !== "" && updater.builtinBuild !== updater.currentBuild
            label: "OS に入っている版"
            value: page.buildText(updater.builtinBuild)
        }
        SettingsRow {
            visible: updater.rolledBackFrom !== ""
            label: "起動できなかった版を戻しました"
            description: page.buildText(updater.rolledBackFrom) + " の版が 3 回続けて起動できなかったので、前の版で起動しています。ログ(設定 > 情報)で原因を確かめてください"
            ActionButton { text: "閉じる"; onClicked: updater.clearRolledBack() }
        }
        SettingsRow {
            visible: updater.state !== "idle" || updater.message !== ""
            label: updater.state === "ready" ? "入れ終わりました"
                   : updater.state === "error" ? "できませんでした"
                   : updater.state === "downloading" ? "ダウンロード中"
                   : updater.state === "installing" ? "入れています" : "お知らせ"
            description: updater.message
            stacked: page.busy
            Item {
                width: page.busy ? Math.min(page.width - 40, 700 * Theme.uiScale) : row.implicitWidth
                height: page.busy ? 64 * Theme.uiScale : row.implicitHeight
                // 進み具合(分からないときは動くだけのバー)
                Rectangle {
                    visible: page.busy
                    anchors { left: parent.left; right: cancelBtn.left; rightMargin: 16 * Theme.uiScale; verticalCenter: parent.verticalCenter }
                    height: 14 * Theme.uiScale
                    radius: height / 2
                    color: Theme.mix(Theme.panel, Theme.textSecondary, 0.25)
                    clip: true
                    Rectangle {
                        id: bar
                        height: parent.height
                        radius: height / 2
                        color: Theme.accent
                        width: updater.progress >= 0 ? parent.width * updater.progress : parent.width * 0.3
                        property real slide: 0
                        x: updater.progress >= 0 ? 0 : (parent.width - width) * slide
                        SequentialAnimation on slide {
                            running: page.busy && updater.progress < 0
                            loops: Animation.Infinite
                            NumberAnimation { from: 0; to: 1; duration: 900; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 1; to: 0; duration: 900; easing.type: Easing.InOutSine }
                        }
                    }
                }
                ActionButton {
                    id: cancelBtn
                    visible: page.busy
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: "やめる"
                    onClicked: updater.cancel()
                }
                Row {
                    id: row
                    visible: !page.busy
                    spacing: 12 * Theme.uiScale
                    ActionButton {
                        visible: updater.state === "ready"
                        text: "今すぐ再起動"
                        selected: true
                        opacity: (page.moving || page.copying) ? 0.4 : 1
                        onClicked: if (!page.moving && !page.copying) updater.restartApp()
                    }
                }
            }
        }
        SettingsNote {
            visible: page.moving
            text: "走行中は更新を始めません。停車してから操作してください"
            color: Theme.warn
        }
    }

    // ---- USB メモリ ----
    SettingsSection {
        title: "USB メモリから"
        icon: "usb"

        SettingsNote {
            visible: updater.usbUpdates.length === 0
            text: updater.usbPresent ? "USB メモリに更新ファイル(.ocapp)が見つかりません。直下か opencruise-update フォルダに置いてください"
                                     : "更新ファイル(.ocapp)を入れた USB メモリを挿すと、ここに出ます"
        }
        Repeater {
            model: updater.usbUpdates
            UpdateRow {
                required property var modelData
                entry: modelData
                source: "USB(" + modelData.file + ")"
                onInstall: updater.installFile(modelData.path)
            }
        }
    }

    // ---- ネット ----
    SettingsSection {
        title: "ネットから"
        icon: "cloud_download"

        SettingsRow {
            label: "更新元を確認"
            description: updater.serverUrl + " ・ " + updater.netStatus
            ActionButton {
                text: "確認"
                opacity: page.busy ? 0.4 : 1
                onClicked: if (!page.busy) updater.checkNetwork()
            }
        }
        UpdateRow {
            visible: updater.netUpdate.build !== undefined
            entry: updater.netUpdate
            source: "ネット"
            onInstall: updater.installNetwork()
        }
        SettingsNote {
            text: "開発 PC で scripts/update-server.sh を動かし、車と同じ Wi-Fi(設定 > ネットワーク)か、有線 LAN・USB テザリングでつないでください"
        }
    }

    // ---- 前の版に戻す ----
    SettingsSection {
        title: "前の版に戻す"
        icon: "history"
        visible: updater.canRollback

        SettingsRow {
            label: "前の版に戻す"
            description: "戻し先: " + updater.rollbackTarget + "。再起動すると反映されます"
            ActionButton {
                text: "戻す"
                opacity: page.canStart ? 1 : 0.4
                onClicked: if (page.canStart) updater.rollback()
            }
        }
    }
}
