// ウィジェットの設定ダイアログ。ウィジェットをダブルタップすると開く(設定画面を持つウィジェットだけ)。
// 中身は、種類ごとの設定画面(WidgetRegistry の settings)+ 全ウィジェット共通の「タイトル」「サイズ」「削除」。
// 左に設定、右にプレビュー(実際の配置と同じ大きさ・設定のウィジェットを縮小表示)を並べる。
// 設定は変更のたびに WidgetArea へ反映・保存される(「完了」で閉じるだけ)。
import QtQuick
import OpenCruise

Item {
    id: root

    property var area: null          // WidgetArea
    property string wid: ""
    property bool open: false

    readonly property real unit: Theme.uiScale
    readonly property var wtype: { if (area) area.revision; return area ? area.typeOf(wid) : "" }
    readonly property var def: WidgetRegistry.find(wtype)
    // 最新の設定・サイズ(area.revision が変わるたびに読み直す)
    readonly property var cfg: { if (area) area.revision; return area ? area.configOf(wid) : ({}) }
    readonly property var size: { if (area) area.revision; return area ? area.sizeOf(wid) : ({ w: 1, h: 1 }) }

    // 設定部分の表示倍率(部品は車載向けに大きいので、プレビューを並べるため少し縮める。タッチ領域も同じ比率で縮む)
    readonly property real contentScale: 0.84

    function show(id) { wid = id; open = true }
    function close() {
        // 入力中のテキスト欄からフォーカスを外し、確定(editingFinished)させてから閉じる
        panel.forceActiveFocus()
        open = false
    }

    visible: scrim.opacity > 0

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "black"
        opacity: root.open ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; enabled: root.open; onClicked: root.close() }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Theme.margin, 1220 * root.unit)
        height: Math.min(parent.height - 2 * Theme.margin, 660 * root.unit)
        radius: Theme.radius + 8
        color: Theme.panel
        border.color: Theme.panelBorder
        scale: root.open ? 1 : 0.92
        opacity: root.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea { anchors.fill: parent }   // パネル内のタップでスクリムが反応しないようにする

        // ---- 上段 ----
        Item {
            id: titleBar
            anchors { top: parent.top; left: parent.left; right: parent.right
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5 }
            height: 72 * root.unit
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14 * root.unit
                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.def ? root.def.icon : "widgets"
                    size: 34 * root.unit
                    color: Theme.accent
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.pixelSize: 26 * root.unit
                    color: Theme.textPrimary
                    text: root.def ? root.def.name + " の設定" : "ウィジェットの設定"
                }
            }
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color: Theme.panelBorder
            }
        }

        // ---- 設定の中身(左) ----
        Flickable {
            id: flick
            anchors { top: titleBar.bottom; bottom: footer.top; left: parent.left; right: divider.left
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin }
            clip: true
            contentWidth: width
            contentHeight: col.height * root.contentScale
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Column {
                id: col
                // 縮小表示ぶん広く組んでから、左上を基準に縮める
                width: flick.width / root.contentScale
                scale: root.contentScale
                transformOrigin: Item.TopLeft

                Loader {
                    id: settingsLoader
                    width: parent.width
                    sourceComponent: root.def ? root.def.settings : null
                }
                Binding { target: settingsLoader.item; property: "config"; value: root.cfg; when: settingsLoader.item !== null }
                Connections {
                    target: settingsLoader.item
                    function onEdit(key, value) { if (root.area) root.area.setConfigValue(root.wid, key, value) }
                    // 文字の入力中: 保存せずに、ウィジェットへだけすぐ反映する(確定時は onEdit で保存)
                    function onPreview(key, value) { if (root.area) root.area.previewConfigValue(root.wid, key, value) }
                }

                // ---- 全ウィジェット共通: 枠 ----
                SettingsRow {
                    label: "枠"
                    description: "「なし」にすると背景のカードを描きません"
                    SettingsChoice {
                        model: ["カード", "なし"]
                        currentIndex: root.cfg.frame === "plain" ? 1 : 0
                        onPicked: (i) => { if (root.area) root.area.setConfigValue(root.wid, "frame", i === 1 ? "plain" : "card") }
                    }
                }

                // ---- 全ウィジェット共通: タイトル ----
                SettingsRow {
                    label: "上部タイトルを表示"
                    SettingsSwitch {
                        checked: root.cfg.showTitle !== false
                        onToggled: (v) => { if (root.area) root.area.setConfigValue(root.wid, "showTitle", v) }
                    }
                }
                SettingsRow {
                    label: "タイトル文字"
                    description: "空欄ならウィジェット標準の名前を表示します"
                    stacked: true
                    WSTextField {
                        width: 520 * Theme.uiScale
                        text: root.cfg.titleText || ""
                        placeholder: root.def ? root.def.name : "タイトル"
                        maxLength: 32
                        // 入力中はウィジェットとプレビューに即反映、保存は確定時(WSTextField の edited)
                        onChanging: (t) => { if (root.area) root.area.previewConfigValue(root.wid, "titleText", t) }
                        onEdited: (t) => { if (root.area) root.area.setConfigValue(root.wid, "titleText", t) }
                    }
                }

                // ---- 共通: サイズ ----
                SettingsRow {
                    label: "サイズ(横)"
                    description: "グリッドのマス数です。隣のウィジェットと重なる大きさにはできません"
                    WSStepper {
                        value: root.size.w
                        from: root.def ? root.def.minSize.w : 1
                        to: root.def ? root.def.maxSize.w : 12
                        step: 1
                        suffix: " マス"
                        onMoved: (v) => { if (root.area) root.area.resizeWidget(root.wid, v, root.size.h) }
                    }
                }
                SettingsRow {
                    label: "サイズ(縦)"
                    WSStepper {
                        value: root.size.h
                        from: root.def ? root.def.minSize.h : 1
                        to: root.def ? root.def.maxSize.h : 6
                        step: 1
                        suffix: " マス"
                        onMoved: (v) => { if (root.area) root.area.resizeWidget(root.wid, root.size.w, v) }
                    }
                }
            }
        }

        // ---- 区切り線 ----
        Rectangle {
            id: divider
            anchors { top: titleBar.bottom; bottom: footer.top; right: preview.left
                      topMargin: Theme.margin; bottomMargin: Theme.margin; rightMargin: Theme.margin }
            width: 1
            color: Theme.panelBorder
        }

        // ---- プレビュー(右) ----
        Item {
            id: preview
            anchors { top: titleBar.bottom; bottom: footer.top; right: parent.right
                      topMargin: Theme.margin; bottomMargin: Theme.margin; rightMargin: Theme.margin * 1.5 }
            width: Math.round(panel.width * 0.4)

            // ホーム画面上での実際の大きさ(px)。この大きさで作ってから、枠に収まるよう縮小する
            readonly property real natW: root.area ? Math.max(1, root.area.cellW * root.size.w - 2 * root.area.pad) : 1
            readonly property real natH: root.area ? Math.max(1, root.area.cellH * root.size.h - 2 * root.area.pad) : 1

            Item {
                id: previewHead
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 36 * root.unit
                Text {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    font.family: Theme.fontFamily
                    font.pixelSize: 20 * root.unit
                    font.bold: true
                    color: Theme.textSecondary
                    text: "プレビュー"
                }
                Text {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    font.family: Theme.fontFamily
                    font.pixelSize: 18 * root.unit
                    color: Theme.textSecondary
                    text: root.size.w + " × " + root.size.h + " マス"
                }
            }

            Rectangle {
                id: stage
                anchors { top: previewHead.bottom; bottom: parent.bottom; left: parent.left; right: parent.right
                          topMargin: 8 * root.unit }
                radius: Theme.radius + 6
                color: Theme.background
                border.color: Theme.panelBorder
                clip: true

                Item {
                    id: previewBox
                    readonly property real inner: 20 * root.unit
                    readonly property real fit: Math.min(1, (stage.width - 2 * inner) / preview.natW,
                                                            (stage.height - 2 * inner) / preview.natH)
                    width: preview.natW
                    height: preview.natH
                    anchors.centerIn: parent
                    scale: Math.max(0.05, fit)

                    Loader {
                        id: previewLoader
                        anchors.fill: parent
                        // 開いている間(閉じるアニメーション中も含む)だけ作る
                        active: root.visible && root.def !== null
                        sourceComponent: root.def ? root.def.component : null
                    }
                    Binding { target: previewLoader.item; property: "config"; value: root.cfg; when: previewLoader.item !== null }
                    Binding { target: previewLoader.item; property: "gridW"; value: root.size.w; when: previewLoader.item !== null }
                    Binding { target: previewLoader.item; property: "gridH"; value: root.size.h; when: previewLoader.item !== null }
                }

                // プレビューは見るだけ(タップ・ドラッグを受けない)
                MouseArea { anchors.fill: parent }
            }
        }

        // ---- 下段 ----
        Item {
            id: footer
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5 }
            height: 84 * root.unit
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 1
                color: Theme.panelBorder
            }
            Row {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                ActionButton {
                    text: "このウィジェットを削除"
                    onClicked: {
                        if (root.area) root.area.removeWidget(root.wid)
                        root.close()
                    }
                }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                ActionButton {
                    selected: true
                    text: "完了"
                    onClicked: root.close()
                }
            }
        }
    }
}
