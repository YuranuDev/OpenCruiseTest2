// ウィジェットの追加パネル。ジャンルごとのタブに、追加できるウィジェットをタイルのグリッドで並べる(WidgetRegistry の定義から自動生成)。
// タイルをタップすると、エリア(今のページ)の空いている最初の場所に置かれ、パネルが閉じる(置ける場所が無ければパネルの下に知らせる)。「初期配置に戻す」は 2 回押しで実行する
// (全ページが初期配置に戻る)。「車両」では一覧の上のスイッチで、メーターとグラフを切り替えて追加できる。
// 数が多い「車両」は、分類(基本・エンジン・燃料・吸気…。WidgetRegistry.vehicleSections)ごとに見出しを付けて並べ、
// 上のチップで分類を絞り込める。今データが来ていない計測値(このECUでは出ない項目・データ元なし)のものは、
// 分類に関係なく最後の「データなし」の見出しの下にまとめる。
import QtQuick
import OpenCruise

Item {
    id: root

    property var area: null          // WidgetArea
    property bool open: false
    property string genre: WidgetRegistry.genres[0].id
    property bool confirmReset: false
    // 「車載連携」の一覧: "gauge"(メーター) / "graph"(グラフ)
    property string vehicleMode: "gauge"
    readonly property bool showVehicleSwitch: genre === "vehicle"
    readonly property var entries: showVehicleSwitch && vehicleMode === "graph" ? WidgetRegistry.graphEntries()
                                                                              : WidgetRegistry.ofGenre(genre)
    // データが来ていないものも出すか(「車両」だけ。下のチップで切り替える)
    property bool showNoData: true
    // 分類での絞り込み(「車両」だけ。"" = すべて)
    property string sectionFilter: ""
    onGenreChanged: sectionFilter = ""
    readonly property var sectionList: WidgetRegistry.vehicleSections
    // 見出しごとのまとまり: [{ title, icon, noData, items }]。データが無いものは最後にまとめる
    // 宣言的な束縛にはしない: データの有無(entryHasData)は車両の値(回転数・ECU の revision など)を読むので、束縛にすると
    // 値が来るたびに(約 5〜10 回/秒)作り直され、タイルの Repeater も作り直されて、押している途中のタイルが消え、
    // タップが効かなかった。決まったとき(開いた・ジャンル・分類・メーター/グラフ・データなしの表示を変えた)と、
    // 開いている間の 2 秒ごとの見直しで、並びが変わったときだけ入れ替える(rebuildBlocks)。
    property var blocks: []
    property string blocksKey: ""
    function computeBlocks() {
        const list = entries.filter(e => sectionFilter === "" || WidgetRegistry.sectionOf(e) === sectionFilter)
        if (!showVehicleSwitch) return list.length > 0 ? [{ title: "", icon: "", noData: false, items: list }] : []
        const out = []
        for (const sec of WidgetRegistry.vehicleSections) {
            const items = list.filter(e => WidgetRegistry.sectionOf(e) === sec.id && WidgetRegistry.entryHasData(e))
            if (items.length > 0) out.push({ title: sec.title, icon: sec.icon, noData: false, items: items })
        }
        const none = list.filter(e => !WidgetRegistry.entryHasData(e))
        if (none.length > 0 && showNoData) out.push({ title: "データなし(今はデータが来ていない)", icon: "block", noData: true, items: none })
        return out
    }
    function rebuildBlocks() {
        const out = computeBlocks()
        // 並び(見出しと、各タイルの種類・計測値)が同じなら入れ替えない(タイルを作り直さない)
        const key = JSON.stringify(out.map(b => [b.title, b.items.map(e => e.type + "/" + (e.config && e.config.metric !== undefined ? e.config.metric : ""))]))
        if (key === blocksKey) return
        blocksKey = key
        blocks = out
    }
    onOpenChanged: {
        if (open) rebuildBlocks()
        else noSpaceShown = false
    }
    onEntriesChanged: rebuildBlocks()
    onSectionFilterChanged: rebuildBlocks()
    onShowNoDataChanged: rebuildBlocks()
    Component.onCompleted: rebuildBlocks()
    // データの有無は値が来るたびに変わりうるので、開いている間だけ 2 秒ごとに見直す(並びが変わったときだけ入れ替わる)
    Timer { interval: 2000; repeat: true; running: root.open && root.showVehicleSwitch; onTriggered: root.rebuildBlocks() }

    readonly property real unit: Theme.uiScale

    function show() { confirmReset = false; noSpaceShown = false; open = true; rebuildBlocks() }
    // 置ける場所が無くて追加できなかったとき、パネルの下に知らせる(画面上部の通知は、ほかの通知
    // (車両異常の警告など)に紛れて気づきにくく、「押しても何も起きない」ように見えていたため)
    property bool noSpaceShown: false
    function showNoSpace() { noSpaceShown = true; noSpaceTimer.restart() }
    Timer { id: noSpaceTimer; interval: 5000; onTriggered: root.noSpaceShown = false }

    function close() { open = false }

    visible: scrim.opacity > 0

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "black"
        opacity: root.open ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; enabled: root.open; onClicked: root.close() }
    }

    Panel {   // テーマに合わせた面(クラシックはグラデーションとハイライト)
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Theme.margin, 980 * root.unit)
        height: Math.min(parent.height - 2 * Theme.margin, 700 * root.unit)
        radius: Theme.radius + 8
        color: Theme.panel
        border.color: Theme.panelBorder
        scale: root.open ? 1 : 0.92
        opacity: root.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea { anchors.fill: parent }

        // ---- 上段: タイトルとジャンルのタブ ----
        Item {
            id: head
            anchors { top: parent.top; left: parent.left; right: parent.right
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5 }
            height: 168 * root.unit

            Text {
                anchors { top: parent.top; topMargin: 18 * root.unit; left: parent.left }
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: 30 * root.unit
                color: Theme.textPrimary
                text: "ウィジェットを追加"
            }
            Row {
                id: tabs
                anchors { bottom: parent.bottom; bottomMargin: 14 * root.unit; left: parent.left; right: parent.right }
                spacing: Theme.margin * 0.6
                readonly property real cellW: (width - spacing * (WidgetRegistry.genres.length - 1)) / WidgetRegistry.genres.length

                Repeater {
                    model: WidgetRegistry.genres
                    Rectangle {
                        required property var modelData
                        readonly property bool on: root.genre === modelData.id
                        width: tabs.cellW
                        height: 76 * root.unit
                        radius: Theme.radius
                        color: Theme.mix(Theme.panel, Theme.accent, tabMouse.pressed ? 0.35 : (on ? 0.14 : 0))
                        border.width: on ? 2 : 1
                        border.color: on ? Theme.accent : Theme.panelBorder
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 8 * root.unit
                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: modelData.icon
                                size: 30 * root.unit
                                color: Theme.accent
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: Theme.fontFamily
                                font.bold: true
                                font.pixelSize: 19 * root.unit
                                color: Theme.textPrimary
                                text: modelData.name
                            }
                        }
                        MouseArea { id: tabMouse; anchors.fill: parent; onClicked: root.genre = modelData.id }
                    }
                }
            }
        }

        // ---- 中段: そのジャンルのウィジェット(タイルを並べたグリッド。分類ごとに見出し。データが無いものは最後) ----
        Flickable {
            id: flick
            anchors { top: head.bottom; bottom: foot.top; left: parent.left; right: parent.right
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5 }
            clip: true
            contentWidth: width
            contentHeight: list.height + Theme.margin
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Column {
                id: list
                width: flick.width
                spacing: Theme.margin * 0.6

                // 「車両」だけ: メーター / グラフの切り替えと、分類で絞り込むチップ
                Item {
                    visible: root.showVehicleSwitch
                    width: list.width
                    height: 60 * root.unit
                    Row {
                        spacing: Theme.margin * 0.6
                        Repeater {
                            model: [{ id: "gauge", label: "メーター", icon: "mdi:gauge" },
                                    { id: "graph", label: "グラフ", icon: "show_chart" }]
                            Rectangle {
                                required property var modelData
                                readonly property bool on: root.vehicleMode === modelData.id
                                width: 200 * root.unit
                                height: 60 * root.unit
                                radius: height / 2
                                color: on ? Theme.accentFill : Theme.mix(Theme.panel, Theme.accent, modeMouse.pressed ? 0.3 : 0)
                                border.width: on ? 2 : 1
                                border.color: on ? Theme.accent : Theme.panelBorder
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 8 * root.unit
                                    MaterialIcon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: modelData.icon
                                        size: 28 * root.unit
                                        color: parent.parent.on ? Theme.textOnAccent : Theme.accent
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        font.family: Theme.fontFamily
                                        font.bold: true
                                        font.pixelSize: 21 * root.unit
                                        color: parent.parent.on ? Theme.textOnAccent : Theme.textPrimary
                                        text: modelData.label
                                    }
                                }
                                MouseArea { id: modeMouse; anchors.fill: parent; onClicked: root.vehicleMode = modelData.id }
                            }
                        }
                    }
                    // データが来ていないものを出す / 隠す
                    Rectangle {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: noDataRow.implicitWidth + 32 * root.unit
                        height: 46 * root.unit
                        radius: height / 2
                        color: Theme.mix(Theme.panel, Theme.accent, noDataMouse.pressed ? 0.2 : 0)
                        border.width: 1
                        border.color: root.showNoData ? Theme.panelBorder : Theme.accent
                        Row {
                            id: noDataRow
                            anchors.centerIn: parent
                            spacing: 6 * root.unit
                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: root.showNoData ? "visibility" : "visibility_off"
                                size: 22 * root.unit
                                color: root.showNoData ? Theme.textSecondary : Theme.accent
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: Theme.fontFamily
                                font.pixelSize: 18 * root.unit
                                color: Theme.textPrimary
                                text: root.showNoData ? "データなしも表示" : "データなしを隠す"
                            }
                        }
                        MouseArea { id: noDataMouse; anchors.fill: parent; onClicked: root.showNoData = !root.showNoData }
                    }
                }
                Flow {
                    visible: root.showVehicleSwitch
                    width: list.width
                    spacing: 8 * root.unit
                    Repeater {
                        model: [{ id: "", title: "すべて" }].concat(root.sectionList)
                        Rectangle {
                            required property var modelData
                            readonly property bool on: root.sectionFilter === modelData.id
                            width: chipText.implicitWidth + 32 * root.unit
                            height: 46 * root.unit
                            radius: height / 2
                            color: on ? Theme.mix(Theme.panel, Theme.accent, 0.3) : Theme.mix(Theme.panel, Theme.accent, chipMouse.pressed ? 0.2 : 0)
                            border.width: on ? 2 : 1
                            border.color: on ? Theme.accent : Theme.panelBorder
                            Text {
                                id: chipText
                                anchors.centerIn: parent
                                font.family: Theme.fontFamily
                                font.pixelSize: 18 * root.unit
                                font.bold: parent.on
                                color: Theme.textPrimary
                                text: modelData.title
                            }
                            MouseArea { id: chipMouse; anchors.fill: parent; onClicked: root.sectionFilter = modelData.id }
                        }
                    }
                }

                // 分類ごとの見出し + タイルのグリッド
                Repeater {
                    model: root.blocks
                    Column {
                        id: block
                        required property var modelData
                        width: list.width
                        spacing: Theme.margin * 0.5
                        Row {
                            visible: block.modelData.title !== ""
                            spacing: 8 * root.unit
                            topPadding: 6 * root.unit
                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: block.modelData.icon
                                size: 24 * root.unit
                                color: block.modelData.noData ? Theme.textSecondary : Theme.accent
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: Theme.fontFamily
                                font.bold: true
                                font.pixelSize: 20 * root.unit
                                color: Theme.textSecondary
                                text: block.modelData.title + "(" + block.modelData.items.length + ")"
                            }
                        }
                        Grid {
                            id: grid
                            readonly property int cols: Math.max(2, Math.floor((list.width + spacing) / (210 * root.unit + spacing)))
                            readonly property real cellW: (list.width - spacing * (cols - 1)) / cols
                            columns: cols
                            spacing: Theme.margin * 0.5
                            Repeater {
                                model: block.modelData.items
                                Rectangle {
                                    required property var modelData
                                    width: grid.cellW
                                    height: 176 * root.unit
                                    radius: Theme.radius + 4
                                    opacity: block.modelData.noData ? 0.6 : 1
                                    color: Theme.mix(Theme.panel, Theme.accent, cardMouse.pressed ? 0.3 : 0.04)
                                    border.width: cardMouse.pressed ? 2 : 1
                                    border.color: cardMouse.pressed ? Theme.accent : Theme.panelBorder
                                    scale: cardMouse.pressed ? 0.97 : 1
                                    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

                                    MaterialIcon {
                                        id: cardIcon
                                        anchors { top: parent.top; topMargin: 16 * root.unit; horizontalCenter: parent.horizontalCenter }
                                        name: modelData.icon
                                        size: 50 * root.unit
                                        color: block.modelData.noData ? Theme.textSecondary : Theme.accent
                                    }
                                    // 右上: モック / データなし
                                    Rectangle {
                                        visible: modelData.mock || block.modelData.noData
                                        anchors { top: parent.top; right: parent.right; margins: 8 * root.unit }
                                        width: tag.implicitWidth + 12
                                        height: tag.implicitHeight + 4
                                        radius: height / 2
                                        color: "transparent"
                                        border.color: block.modelData.noData ? Theme.textSecondary : Theme.warn
                                        Text {
                                            id: tag
                                            anchors.centerIn: parent
                                            font.family: Theme.fontFamily
                                            text: block.modelData.noData ? "データなし" : "モック"
                                            color: block.modelData.noData ? Theme.textSecondary : Theme.warn
                                            font.pixelSize: 12 * root.unit
                                        }
                                    }
                                    Text {
                                        id: cardName
                                        anchors { top: cardIcon.bottom; topMargin: 8 * root.unit; left: parent.left; right: parent.right
                                                  leftMargin: 10 * root.unit; rightMargin: 10 * root.unit }
                                        horizontalAlignment: Text.AlignHCenter
                                        font.family: Theme.fontFamily
                                        font.bold: true
                                        font.pixelSize: 21 * root.unit
                                        color: Theme.textPrimary
                                        elide: Text.ElideRight
                                        text: modelData.name
                                    }
                                    Text {
                                        anchors { top: cardName.bottom; topMargin: 4 * root.unit; left: parent.left; right: parent.right
                                                  leftMargin: 10 * root.unit; rightMargin: 10 * root.unit }
                                        horizontalAlignment: Text.AlignHCenter
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 15 * root.unit
                                        color: Theme.textSecondary
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        text: modelData.description
                                    }
                                    MouseArea {
                                        id: cardMouse
                                        anchors.fill: parent
                                        onClicked: {
                                            if (!root.area) return
                                            if (root.area.addWidget(modelData.type, modelData.config)) root.close()
                                            else root.showNoSpace()   // 置ける場所が無い(このパネルの中に知らせる)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Text {
                    visible: root.blocks.length === 0
                    width: list.width
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: 40 * root.unit
                    font.family: Theme.fontFamily
                    font.pixelSize: 20 * root.unit
                    color: Theme.textSecondary
                    text: "この分類のウィジェットはありません"
                }
            }
        }

        // ---- 追加できなかったときの知らせ(下段のすぐ上) ----
        Rectangle {
            id: noSpaceBanner
            z: 2
            anchors { bottom: foot.top; left: parent.left; right: parent.right; bottomMargin: 8 * root.unit
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5 }
            height: noSpaceRow.implicitHeight + 24 * root.unit
            radius: Theme.radius + 2
            color: Theme.mix(Theme.panel, Theme.warn, 0.22)
            border.width: 2
            border.color: Theme.warn
            opacity: root.noSpaceShown ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Row {
                id: noSpaceRow
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 16 * root.unit; rightMargin: 16 * root.unit }
                spacing: 12 * root.unit
                MaterialIcon { anchors.verticalCenter: parent.verticalCenter; name: "warning"; size: 34 * root.unit; color: Theme.warn }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: noSpaceRow.width - 46 * root.unit
                    wrapMode: Text.WordWrap
                    font.family: Theme.fontFamily
                    font.pixelSize: 19 * root.unit
                    color: Theme.textPrimary
                    text: "このページには置ける場所がありません。ウィジェットを消すか小さくするか、別のページ(上の「＋」で増やせます)に切り替えてから追加してください"
                }
            }
            MouseArea { anchors.fill: parent; onClicked: root.noSpaceShown = false }
        }

        // ---- 下段 ----
        Item {
            id: foot
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5 }
            height: 96 * root.unit
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 1
                color: Theme.panelBorder
            }
            ActionButton {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: root.confirmReset ? "もう一度押すと初期配置に戻します" : "初期配置に戻す"
                onClicked: {
                    if (!root.confirmReset) {
                        root.confirmReset = true
                        resetTimer.restart()
                    } else {
                        root.confirmReset = false
                        if (root.area) root.area.resetLayout()
                        root.close()
                    }
                }
            }
            Timer { id: resetTimer; interval: 4000; onTriggered: root.confirmReset = false }
            ActionButton {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                selected: true
                text: "閉じる"
                onClicked: root.close()
            }
        }
    }
}
