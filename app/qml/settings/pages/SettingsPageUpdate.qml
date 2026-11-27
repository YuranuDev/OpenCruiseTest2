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
    // 作業中の経過時間と段階の表示。作業が始まるたびに数え直す(USB の更新はダウンロードの段階が無いので、見たときだけ出す)
    property int elapsed: 0
    property bool sawDownload: updater.stage === 1
    readonly property string elapsedText: Math.floor(elapsed / 60) + ":" + (elapsed % 60 < 10 ? "0" : "") + (elapsed % 60)
    readonly property var stepNames: sawDownload ? ["ダウンロード", "確認", "展開", "切り替え"] : ["確認", "展開", "切り替え"]
    readonly property int stepIndex: sawDownload ? updater.stage - 1 : updater.stage - 2   // 今の段階(0 始まり)
    onBusyChanged: { elapsed = 0; if (!busy) sawDownload = false }
    Connections {
        target: updater
        function onStateChanged() { if (updater.stage === 1) page.sawDownload = true }
    }
    Timer { interval: 1000; repeat: true; running: page.busy; onTriggered: page.elapsed++ }

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

    // 段階の表示 1 コマ(●と名前、次へのつなぎ線)。state: 0=まだ / 1=今 / 2=済み
    component StepMark: Row {
        id: sm
        property string name: ""
        property int state: 0
        property bool last: false
        property bool active: true   // false の間は光の輪のアニメーションを止める
        readonly property real unit: Theme.uiScale
        spacing: 8 * unit

        Item {
            width: 16 * sm.unit; height: 16 * sm.unit
            anchors.verticalCenter: parent.verticalCenter
            // 今の段階の光の輪(広がって消えるのを繰り返す)
            Rectangle {
                id: ring
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.color: Theme.accent
                border.width: 2 * sm.unit
                visible: sm.state === 1
                opacity: 0
                ParallelAnimation {
                    running: sm.active && sm.state === 1
                    loops: Animation.Infinite
                    NumberAnimation { target: ring; property: "scale"; from: 1; to: 2.1; duration: 1100; easing.type: Easing.OutQuad }
                    NumberAnimation { target: ring; property: "opacity"; from: 0.8; to: 0; duration: 1100; easing.type: Easing.OutQuad }
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: sm.state === 0 ? "transparent" : Theme.accent
                border.color: sm.state === 0 ? Theme.textSecondary : Theme.accent
                border.width: 2 * sm.unit
                Behavior on color { ColorAnimation { duration: 250 } }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: sm.name
            font.family: Theme.fontFamily
            font.pixelSize: 19 * sm.unit
            font.bold: sm.state === 1
            color: sm.state === 1 ? Theme.textPrimary : Theme.textSecondary
            opacity: sm.state === 0 ? 0.6 : 1
        }
        Rectangle {   // 次の段階へのつなぎ線(済んだら色がつく)
            visible: !sm.last
            anchors.verticalCenter: parent.verticalCenter
            width: 22 * sm.unit; height: 2 * sm.unit
            color: sm.state === 2 ? Theme.accent : Theme.mix(Theme.panel, Theme.textSecondary, 0.35)
            Behavior on color { ColorAnimation { duration: 250 } }
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
                height: page.busy ? busyCol.implicitHeight : row.implicitHeight
                Column {
                    id: busyCol
                    visible: page.busy
                    width: parent.width
                    spacing: 6 * Theme.uiScale
                    Item {
                        width: parent.width
                        height: 56 * Theme.uiScale
                        // 進み具合のバー(分かるときは伸びる塗り、分からないときは左右に往復する光。右に % か経過時間)
                        ActivityBar {
                            anchors { left: parent.left; right: cancelBtn.left; rightMargin: 16 * Theme.uiScale; verticalCenter: parent.verticalCenter }
                            height: 18 * Theme.uiScale
                            unit: Theme.uiScale
                            running: page.busy
                            progress: updater.progress
                            text: updater.progress >= 0 ? Math.round(updater.progress * 100) + "%" : page.elapsedText
                            barColor: Theme.accent
                            trackColor: Theme.mix(Theme.panel, Theme.textSecondary, 0.25)
                            textColor: Theme.textSecondary
                            fontFamily: Theme.fontFamily
                        }
                        ActionButton {
                            id: cancelBtn
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: "やめる"
                            opacity: updater.canCancel ? 1 : 0.4   // 最後の切り替えの間はやめられない
                            onClicked: if (updater.canCancel) updater.cancel()
                        }
                    }
                    // 今どの段階か(ダウンロード → 確認 → 展開 → 切り替え)
                    Flow {
                        width: parent.width
                        spacing: 6 * Theme.uiScale
                        Repeater {
                            model: page.stepNames
                            StepMark {
                                required property int index
                                required property string modelData
                                name: modelData
                                last: index === page.stepNames.length - 1
                                active: page.busy
                                state: index < page.stepIndex ? 2 : index === page.stepIndex ? 1 : 0
                            }
                        }
                    }
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
