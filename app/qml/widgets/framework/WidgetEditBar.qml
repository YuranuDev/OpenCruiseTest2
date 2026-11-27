// 編集モードの上部パネル。上段で編集対象を切り替え、下段に対象ごとの操作をまとめる。
import QtQuick
import QtQuick.Controls
import OpenCruise

Item {
    id: root
    property Item area: null
    property Item pages: null
    property string panelMode: "widgets"     // widgets / decor / theme / wallpaper
    property bool editNight: Theme.night      // テーマ・壁紙・飾りの編集先。表示中の時間帯とは独立
    signal panelModeRequested(string mode)
    signal addRequested()
    signal settingsRequested(var entries)
    signal doneRequested()
    signal addDecorRequested()
    property bool canUndo: false
    signal undoRequested()

    readonly property real unit: Theme.uiScale
    readonly property int actionHeight: Math.max(38, Math.round(48 * unit))
    readonly property bool decorMode: panelMode === "decor"
    readonly property int selCount: pages ? pages.selectedEntries().length : (area ? area.selection.length : 0)
    readonly property int selPages: pages ? pages.selectedPageCount() : 1
    readonly property int pageSelCount: area ? area.selection.length : 0
    readonly property int widgetCount: area ? area.count : 0
    readonly property int allWidgetCount: pages ? pages.widgetTotal() : widgetCount
    readonly property var profile: editNight ? themeSettings.nightProfile : themeSettings.dayProfile
    readonly property var themeModes: [
        { mode: "widgets", label: "ウィジェット", icon: "widgets" },
        { mode: "decor", label: "飾り", icon: "image" },
        { mode: "theme", label: "テーマ", icon: "palette" },
        { mode: "wallpaper", label: "壁紙", icon: "wallpaper" }
    ]
    readonly property var aaModes: [
        { mode: "widgets", label: "ウィジェット", icon: "widgets" },
        { mode: "theme", label: "テーマ", icon: "palette" },
        { mode: "wallpaper", label: "壁紙", icon: "wallpaper" }
    ]
    readonly property var backgroundKinds: [
        { label: "テーマに合わせる", value: "auto" },
        { label: "無地", value: "none" },
        { label: "カーボン", value: "carbon" },
        { label: "ヘアライン", value: "brushed" },
        { label: "パンチング", value: "dots" },
        { label: "ストライプ", value: "stripes" },
        { label: "画像", value: "image" }
    ]

    function selectedEntries() {
        if (pages) return pages.selectedEntries()
        return area ? area.selection.map(w => ({ area: area, wid: w })) : []
    }
    function updateProfile(values) {
        const next = Object.assign({}, root.profile)
        Object.assign(next, values)
        if (root.editNight) themeSettings.nightProfile = next
        else themeSettings.dayProfile = next
    }
    function setProfileValue(key, value) {
        const values = {}
        values[key] = value
        updateProfile(values)
    }
    function openColorPicker() {
        if (root.profile.accentCustom === "") {
            const presets = Theme.accentPresetsFor(root.profile.style)
            updateProfile({ accentCustom: presets[Math.min(root.profile.accentIndex, presets.length - 1)] })
        }
        colorPopup.open()
    }

    property bool confirmDelete: false
    property real confirmAt: 0
    onSelCountChanged: confirmDelete = false
    onVisibleChanged: confirmDelete = false
    onPanelModeChanged: if (panelMode === "wallpaper") themeSettings.refreshBackgroundImages()
    Timer { id: confirmTimer; interval: 3000; onTriggered: root.confirmDelete = false }

    component BarButton: Rectangle {
        id: b
        property string icon: ""
        property string text: ""
        property bool showText: true
        property string tone: "normal"       // normal / accent / danger / dangerSolid
        property bool buttonEnabled: true
        signal clicked()
        readonly property bool solid: tone === "accent" || tone === "dangerSolid"
        readonly property color toneColor: tone === "danger" || tone === "dangerSolid" ? Theme.error : Theme.accent
        readonly property color onSolid: tone === "dangerSolid" ? "#ffffff" : Theme.textOnAccent
        height: root.actionHeight
        width: Math.max(height, buttonRow.implicitWidth + 24 * root.unit)
        radius: height / 2
        opacity: buttonEnabled ? 1 : 0.4
        color: tone === "accent" ? Theme.mix(Theme.accentFill, "#000000", buttonMouse.pressed ? 0.2 : 0)
             : tone === "dangerSolid" ? Theme.mix(Theme.error, "#000000", buttonMouse.pressed ? 0.2 : 0)
             : Theme.mix(Theme.panel, toneColor, buttonMouse.pressed ? 0.35 : 0.08)
        border.width: solid ? 0 : 1.5
        border.color: tone === "normal" ? Theme.panelBorder : toneColor
        scale: buttonMouse.pressed ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: 80 } }
        Row {
            id: buttonRow
            anchors.centerIn: parent
            spacing: 6 * root.unit
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: b.icon
                size: Math.max(18, Math.round(b.height * 0.46))
                color: b.solid ? b.onSolid : b.toneColor
            }
            Text {
                visible: b.showText && b.text !== ""
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.fontFamily
                font.pixelSize: Math.max(15, Math.round(b.height * 0.36))
                font.bold: true
                color: b.solid ? b.onSolid : Theme.textPrimary
                text: b.text
            }
        }
        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            enabled: b.buttonEnabled
            onClicked: b.clicked()
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4 * root.unit
        radius: 24 * root.unit
        color: Theme.mix(Theme.panel, Theme.accent, 0.06)
        border.color: Theme.mix(Theme.panelBorder, Theme.accent, 0.5)
        opacity: root.decorMode ? 0.3 : 1
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }

    // 上段は編集対象だけを選ぶ。編集操作は下段へ分け、ボタン同士が詰まらないようにする。
    Item {
        id: headerRow
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 4 * root.unit
                  leftMargin: 10 * root.unit; rightMargin: 10 * root.unit }
        height: root.actionHeight

        Row {
            id: sectionLabel
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            spacing: 7 * root.unit
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "edit"
                size: Math.max(22, Math.round(headerRow.height * 0.55))
                color: Theme.accent
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "編集"
                font.family: Theme.fontFamily
                font.pixelSize: Math.max(16, Math.round(headerRow.height * 0.38))
                font.bold: true
                color: Theme.textPrimary
            }
        }

        BarButton {
            id: doneButton
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            tone: "accent"
            icon: "check"
            text: "完了"
            onClicked: root.doneRequested()
        }

        Flickable {
            id: modeViewport
            anchors { left: sectionLabel.right; right: doneButton.left; verticalCenter: parent.verticalCenter
                      leftMargin: 10 * root.unit; rightMargin: 10 * root.unit }
            height: parent.height
            clip: true
            contentWidth: modeRow.implicitWidth
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentWidth > width
            Row {
                id: modeRow
                height: modeViewport.height
                spacing: 7 * root.unit
                Repeater {
                    model: root.pages ? root.themeModes : root.aaModes
                    BarButton {
                        required property var modelData
                        icon: modelData.icon
                        text: modelData.label
                        tone: root.panelMode === modelData.mode ? "accent" : "normal"
                        onClicked: root.panelModeRequested(modelData.mode)
                    }
                }
            }
        }
    }

    // 下段だけを横スクロール可能にする。操作群は用途ごとに並べ、狭い画面でも重ならない。
    Flickable {
        id: controlsViewport
        anchors { left: parent.left; right: parent.right; top: headerRow.bottom; bottom: parent.bottom
                  leftMargin: 10 * root.unit; rightMargin: 10 * root.unit
                  topMargin: 4 * root.unit; bottomMargin: 5 * root.unit }
        clip: true
        contentWidth: controlsRow.implicitWidth
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width

        Row {
            id: controlsRow
            height: controlsViewport.height
            spacing: 8 * root.unit

            // ウィジェット配置・選択
            Row {
                id: widgetControls
                visible: root.panelMode === "widgets"
                width: visible ? implicitWidth : 0
                height: root.actionHeight
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * root.unit
                BarButton {
                    visible: root.pages !== null && root.pages.count > 1
                    icon: "chevron_left"
                    buttonEnabled: root.pages && root.pages.current > 0
                    onClicked: if (root.pages && root.pages.current > 0) root.pages.setCurrent(root.pages.current - 1)
                }
                Text {
                    visible: root.pages !== null && root.pages.count > 1
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(15, 17 * root.unit)
                    color: Theme.textSecondary
                    text: root.pages ? (root.pages.names[root.pages.current] || "") + "  " + (root.pages.current + 1) + " / " + root.pages.count : ""
                }
                BarButton {
                    visible: root.pages !== null && root.pages.count > 1
                    icon: "chevron_right"
                    buttonEnabled: root.pages && root.pages.current < root.pages.count - 1
                    onClicked: if (root.pages && root.pages.current < root.pages.count - 1) root.pages.setCurrent(root.pages.current + 1)
                }
                Rectangle { visible: root.pages !== null && root.pages.count > 1; width: 1; height: parent.height * 0.65; anchors.verticalCenter: parent.verticalCenter; color: Theme.panelBorder }
                Text {
                    visible: root.selCount === 0
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(14, 16 * root.unit)
                    color: Theme.textSecondary
                    text: "タップで選択 ・ ドラッグで移動"
                }
                Text {
                    visible: root.selCount > 0
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(15, 17 * root.unit)
                    font.bold: true
                    color: Theme.accent
                    text: root.selCount + " 個選択中" + (root.selPages > 1 ? " (" + root.selPages + " ページ)" : "")
                }
                BarButton {
                    visible: root.selCount > 0
                    icon: "tune"
                    text: "まとめて設定"
                    onClicked: { root.confirmDelete = false; root.settingsRequested(root.selectedEntries()) }
                }
                BarButton {
                    visible: root.selCount > 0
                    icon: "delete"
                    tone: root.confirmDelete ? "dangerSolid" : "danger"
                    text: root.confirmDelete ? "もう一度押すと " + root.selCount + " 個を削除" : "削除"
                    onClicked: {
                        if (!root.confirmDelete) {
                            root.confirmDelete = true
                            root.confirmAt = Date.now()
                            confirmTimer.restart()
                            return
                        }
                        if (Date.now() - root.confirmAt < 400) return
                        confirmTimer.stop()
                        root.confirmDelete = false
                        if (root.pages) root.pages.removeAllSelected()
                        else if (root.area) root.area.removeSelected()
                    }
                }
                BarButton {
                    visible: root.selCount > 0
                    icon: "deselect"
                    text: "選択を解除"
                    onClicked: root.pages ? root.pages.clearAllSelection() : root.area.clearSelection()
                }
                Rectangle { visible: root.selCount > 0; width: 1; height: parent.height * 0.65; anchors.verticalCenter: parent.verticalCenter; color: Theme.panelBorder }
                BarButton {
                    visible: root.widgetCount > 0 && root.pageSelCount < root.widgetCount
                    icon: "select_all"
                    text: root.pages && root.pages.count > 1 ? "このページを選択" : "すべて選択"
                    onClicked: if (root.area) root.area.selectAll()
                }
                BarButton {
                    visible: root.pages !== null && root.pages.count > 1 && root.allWidgetCount > 0 && root.selCount < root.allWidgetCount
                    icon: "library_add_check"
                    text: "全ページを選択"
                    onClicked: root.pages.selectAllPages()
                }
                BarButton {
                    tone: "accent"
                    icon: "add"
                    text: "ウィジェットを追加"
                    onClicked: root.addRequested()
                }
            }

            // 飾り画像の配置。時間帯の切り替えは表示中の時刻と無関係に選べる。
            Row {
                id: decorControls
                visible: root.panelMode === "decor"
                width: visible ? implicitWidth : 0
                height: root.actionHeight
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * root.unit
                BarButton {
                    icon: "brightness_5"
                    text: "昼の飾り"
                    tone: root.pages && !root.pages.decorationNight ? "accent" : "normal"
                    onClicked: if (root.pages) root.pages.decorationNight = false
                }
                BarButton {
                    icon: "brightness_2"
                    text: "夜の飾り"
                    tone: root.pages && root.pages.decorationNight ? "accent" : "normal"
                    onClicked: if (root.pages) root.pages.decorationNight = true
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(14, 16 * root.unit)
                    color: Theme.textSecondary
                    text: "タップで選択 ・ ドラッグで移動 ・ 右下のつまみで大きさ"
                }
                BarButton {
                    visible: root.canUndo
                    icon: "undo"
                    text: "元に戻す"
                    onClicked: root.undoRequested()
                }
                BarButton {
                    tone: "accent"
                    icon: "add_photo_alternate"
                    text: "画像を追加"
                    onClicked: root.addDecorRequested()
                }
                Text {
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(12, 14 * root.unit)
                    color: Theme.textSecondary
                    text: "画像フォルダ: " + themeSettings.decorationFolder
                }
            }

            // テーマ設定: プロファイル、適用モード、スタイル、アクセント色をまとめる。
            Row {
                id: themeControls
                visible: root.panelMode === "theme"
                width: visible ? implicitWidth : 0
                height: root.actionHeight
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7 * root.unit
                BarButton {
                    icon: "brightness_5"
                    text: "昼の設定"
                    tone: !root.editNight ? "accent" : "normal"
                    onClicked: root.editNight = false
                }
                BarButton {
                    icon: "brightness_2"
                    text: "夜の設定"
                    tone: root.editNight ? "accent" : "normal"
                    onClicked: root.editNight = true
                }
                Rectangle { width: 1; height: parent.height * 0.65; anchors.verticalCenter: parent.verticalCenter; color: Theme.panelBorder }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(13, 15 * root.unit)
                    color: Theme.textSecondary
                    text: "表示: " + (androidAuto.nightActive ? "夜 (ライト ON)" : "昼 (ライト OFF)") + " ・ Android Auto 連動"
                }
                Rectangle { width: 1; height: parent.height * 0.65; anchors.verticalCenter: parent.verticalCenter; color: Theme.panelBorder }
                BarButton {
                    icon: "dashboard"
                    text: "シンプル"
                    tone: root.profile.style === "simple" ? "accent" : "normal"
                    onClicked: root.updateProfile({ style: "simple" })
                }
                BarButton {
                    icon: "view_quilt"
                    text: "クラシック"
                    tone: root.profile.style === "classic" ? "accent" : "normal"
                    onClicked: root.updateProfile({ style: "classic" })
                }
                Rectangle { width: 1; height: parent.height * 0.65; anchors.verticalCenter: parent.verticalCenter; color: Theme.panelBorder }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(13, 15 * root.unit)
                    color: Theme.textSecondary
                    text: "アクセント: " + (root.profile.accentCustom !== "" ? "カスタム" : Theme.accentNamesFor(root.profile.style)[root.profile.accentIndex])
                }
                Repeater {
                    model: Theme.accentPresetsFor(root.profile.style)
                    Item {
                        required property int index
                        required property var modelData
                        width: Math.max(36, 42 * root.unit)
                        height: root.actionHeight
                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.max(30, 36 * root.unit)
                            height: width
                            radius: width / 2
                            color: modelData
                            border.width: root.profile.accentCustom === "" && root.profile.accentIndex === index ? 3 : 1
                            border.color: root.profile.accentCustom === "" && root.profile.accentIndex === index ? Theme.textPrimary : Theme.panelBorder
                            MaterialIcon {
                                anchors.centerIn: parent
                                visible: root.profile.accentCustom === "" && root.profile.accentIndex === index
                                name: "check"
                                size: parent.width * 0.55
                                color: "#111111"
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.updateProfile({ accentCustom: "", accentIndex: index })
                            }
                        }
                    }
                }
                BarButton {
                    icon: "colorize"
                    text: "色を調整"
                    onClicked: root.openColorPicker()
                }
            }

            // 壁紙設定: 種類、画像、表示方式、濃さを同じプロファイルで編集する。
            Row {
                id: wallpaperControls
                visible: root.panelMode === "wallpaper"
                width: visible ? implicitWidth : 0
                height: root.actionHeight
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7 * root.unit
                BarButton {
                    icon: "brightness_5"
                    text: "昼の設定"
                    tone: !root.editNight ? "accent" : "normal"
                    onClicked: root.editNight = false
                }
                BarButton {
                    icon: "brightness_2"
                    text: "夜の設定"
                    tone: root.editNight ? "accent" : "normal"
                    onClicked: root.editNight = true
                }
                Rectangle { width: 1; height: parent.height * 0.65; anchors.verticalCenter: parent.verticalCenter; color: Theme.panelBorder }
                Repeater {
                    model: root.backgroundKinds
                    BarButton {
                        required property var modelData
                        text: modelData.label
                        tone: root.profile.background === modelData.value ? "accent" : "normal"
                        onClicked: root.updateProfile({ background: modelData.value })
                    }
                }
                Repeater {
                    model: root.profile.background === "image" ? themeSettings.backgroundImages : []
                    BarButton {
                        required property var modelData
                        icon: "image"
                        text: modelData
                        tone: root.profile.backgroundImage === modelData ? "accent" : "normal"
                        onClicked: root.updateProfile({ backgroundImage: modelData })
                    }
                }
                Text {
                    visible: root.profile.background === "image" && themeSettings.backgroundImages.length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(13, 15 * root.unit)
                    color: Theme.textSecondary
                    text: "画像がありません: " + themeSettings.backgroundFolder
                }
                BarButton {
                    visible: root.profile.background === "image"
                    icon: "refresh"
                    text: "画像を読み直す"
                    onClicked: themeSettings.refreshBackgroundImages()
                }
                Rectangle { visible: root.profile.background === "image"; width: 1; height: parent.height * 0.65; anchors.verticalCenter: parent.verticalCenter; color: Theme.panelBorder }
                Text {
                    visible: root.profile.background === "image"
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(13, 15 * root.unit)
                    color: Theme.textSecondary
                    text: "表示"
                }
                BarButton {
                    visible: root.profile.background === "image"
                    icon: "grid_on"
                    text: "並べる"
                    tone: root.profile.backgroundFit === 0 ? "accent" : "normal"
                    onClicked: root.updateProfile({ backgroundFit: 0 })
                }
                BarButton {
                    visible: root.profile.background === "image"
                    icon: "fit_screen"
                    text: "埋める"
                    tone: root.profile.backgroundFit === 1 ? "accent" : "normal"
                    onClicked: root.updateProfile({ backgroundFit: 1 })
                }
                BarButton {
                    visible: root.profile.background === "image"
                    icon: "aspect_ratio"
                    text: "引き伸ばす"
                    tone: root.profile.backgroundFit === 2 ? "accent" : "normal"
                    onClicked: root.updateProfile({ backgroundFit: 2 })
                }
                Rectangle { visible: root.profile.background === "image"; width: 1; height: parent.height * 0.65; anchors.verticalCenter: parent.verticalCenter; color: Theme.panelBorder }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(13, 15 * root.unit)
                    color: Theme.textSecondary
                    text: "画面の明るさ"
                }
                SettingsSlider {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 230 * root.unit
                    height: Math.min(parent.height, 64 * root.unit)
                    from: brightnessController.minimum
                    iconName: "brightness_high"
                    iconMinName: "brightness_low"
                    value: root.editNight ? brightnessController.nightBrightness : brightnessController.dayBrightness
                    onMoved: (v) => {
                        if (root.editNight) brightnessController.nightBrightness = v
                        else brightnessController.dayBrightness = v
                    }
                }
                Rectangle { width: 1; height: parent.height * 0.65; anchors.verticalCenter: parent.verticalCenter; color: Theme.panelBorder }
                Text {
                    visible: root.profile.background !== "none"
                             && !(root.profile.background === "auto" && root.profile.style !== "classic")
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(13, 15 * root.unit)
                    color: Theme.textSecondary
                    text: "背景の濃さ"
                }
                SettingsSlider {
                    visible: root.profile.background !== "none"
                             && !(root.profile.background === "auto" && root.profile.style !== "classic")
                    anchors.verticalCenter: parent.verticalCenter
                    width: 250 * root.unit
                    height: Math.min(parent.height, 64 * root.unit)
                    iconName: "wallpaper"
                    iconMinName: "wallpaper"
                    value: root.profile.backgroundOpacity
                    onMoved: (v) => root.setProfileValue("backgroundOpacity", v)
                }
            }
        }
    }

    Rectangle {
        id: scrollTrack
        visible: controlsViewport.contentWidth > controlsViewport.width
        x: controlsViewport.x
        y: controlsViewport.y + controlsViewport.height - height
        width: controlsViewport.width
        height: 3 * root.unit
        radius: height / 2
        color: Theme.panelBorder
        Rectangle {
            width: Math.max(28 * root.unit, scrollTrack.width * controlsViewport.width / controlsViewport.contentWidth)
            height: parent.height
            radius: height / 2
            x: controlsViewport.contentX / Math.max(1, controlsViewport.contentWidth - controlsViewport.width)
               * (scrollTrack.width - width)
            color: Theme.accent
        }
    }

    Popup {
        id: colorPopup
        parent: Overlay.overlay
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? (parent.height - height) / 2 : 0
        width: parent ? Math.min(620 * root.unit, parent.width - 24 * root.unit) : 560 * root.unit
        height: Math.min(colorContent.implicitHeight + 24 * root.unit, parent ? parent.height - 24 * root.unit : 460 * root.unit)
        padding: 12 * root.unit
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: Theme.radius + 4
            color: Theme.panel
            border.width: 2
            border.color: Theme.accent
        }
        contentItem: Column {
            id: colorContent
            width: colorPopup.width - colorPopup.padding * 2
            spacing: 8 * root.unit
            Text {
                text: "アクセント色を調整"
                font.family: Theme.fontFamily
                font.pixelSize: 22 * root.unit
                font.bold: true
                color: Theme.textPrimary
            }
            SettingsColorPicker {
                width: colorPopup.width - colorPopup.padding * 2
                color: root.profile.accentCustom !== "" ? root.profile.accentCustom : Theme.accent
                onPicked: (c) => root.setProfileValue("accentCustom", c)
            }
            Item {
                width: parent.width
                height: root.actionHeight
                BarButton {
                    anchors.right: parent.right
                    tone: "accent"
                    icon: "check"
                    text: "完了"
                    onClicked: colorPopup.close()
                }
            }
        }
    }
}
