// 車両画面(メニューの「車両」)。車両のデータ(VIN 車両信号・SEN 外付けセンサー・DIAG エンジン ECU の各ノード)を、
// データ元で分けずに 1 つの車両データとして見る(まとめるのは VehicleSignals)。値の横に小さく、どのノードから来た値かを出す。
// 左に項目の一覧、右に選んだ項目の中身(設定画面と同じ形)。右の上には「車両 › 項目」と中身の例を出す。
//   概要            車両の状態(異常の有無)・チェックランプと、主要な値のタイル
//   ライブデータ    すべての計測値を分類(走行・エンジン・燃料…)ごとに一覧(データの無い項目は「--」。隠すこともできる)
//   スイッチ・作動状態  バック・エンジン・ファン・燃料ポンプ・ブレーキなどの ON / OFF をランプで
//   故障コード      現在起きている異常(赤)と過去の記録(黄)を分けて、コード・内容・状態を出す(消去はしない)
//   データ元・ECU 情報  ノードごとの状態と、両方から取れる項目でどちらを使っているか、ECU の情報と通信の状態
// 値は ecu.revision(約 5Hz)と車両信号の変化に合わせて書き換わる。
import QtQuick
import QtQuick.Controls
import OpenCruise

Rectangle {
    id: root
    color: "transparent"   // 背景は Main.qml の ThemeBackground
    signal back()

    readonly property real unit: Theme.uiScale
    property int currentIndex: 0

    readonly property var pages: [
        { id: "overview", icon: "dashboard",       title: "概要",               description: "車両の状態・チェックランプ・主要な値" },
        { id: "live",     icon: "monitor_heart",   title: "ライブデータ",       description: "すべての計測値を分類ごとに" },
        { id: "switch",   icon: "toggle_on",       title: "スイッチ・作動状態", description: "バック・ファン・燃料ポンプなど" },
        { id: "dtc",      icon: "mdi:car-wrench",  title: "故障コード",         description: "現在の異常と過去の記録" },
        { id: "sources",  icon: "hub",             title: "データ元・ECU 情報", description: "ノードの状態・ECU の情報と通信" }
    ]
    readonly property var current: pages[currentIndex]

    // ---- 項目(VIN / SEN の計測値は VehicleSignals、ECU だけの項目は ecu)。どちらも id で引く ----
    function paramOf(id) { for (const p of ecu.params) if (p.id === id) return p; return null }
    function isNode(id) { return !!VehicleSignals.nodeMetrics[id] }
    function itemTitle(id) {
        if (id === "gear") return "ギア"
        if (isNode(id)) { const s = WidgetRegistry.gaugeSpecs[id]; return s ? s.title : id }
        const p = paramOf(id); return p ? p.title : id
    }
    function itemIcon(id) {
        if (id === "gear") return "mdi:car-shift-pattern"
        if (isNode(id)) { const s = WidgetRegistry.gaugeSpecs[id]; return s ? s.icon : "" }
        const p = paramOf(id); return p ? p.icon : ""
    }
    function itemUnit(id) {
        if (id === "gear") return "速"
        if (isNode(id)) { const s = WidgetRegistry.gaugeSpecs[id]; return s ? s.units[0].label : "" }
        const p = paramOf(id); return p ? p.unit : ""
    }
    function itemDec(id) {
        if (id === "gear") return 0
        if (isNode(id)) { const s = WidgetRegistry.gaugeSpecs[id]; return s ? s.units[0].dec : 0 }
        const p = paramOf(id); return p ? p.dec : 0
    }
    function has(id) {
        if (isNode(id)) return VehicleSignals.has(id) && !(id === "gear" && VehicleSignals.value(id) <= 0)
        ecu.revision; return ecu.has(id)
    }
    /// 数値だけ(単位なし。無ければ "--")
    function numText(id) {
        if (!has(id)) return "--"
        const v = isNode(id) ? VehicleSignals.value(id) : (ecu.revision, ecu.value(id))
        return Number(v).toFixed(itemDec(id))
    }
    /// 画面に出す文字(数値は単位つき。ECU の列挙・ビットは説明。無ければ "--")
    function t(id) {
        if (isNode(id)) { const n = numText(id); return n === "--" ? n : n + " " + itemUnit(id) }
        ecu.revision; return ecu.text(id)
    }
    /// どのノードから来た値か("VIN" / "SEN" / "ECU"。無ければ "")
    function sourceTag(id) {
        if (isNode(id)) { if (!has(id)) return ""; const n = VehicleSignals.nodeOf(id); return n === "DIAG" ? "ECU" : n }
        return has(id) ? "ECU" : ""
    }

    // ---- ヘッダー: 戻るボタン + タイトル ----
    Item {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: Theme.margin }
        height: 80 * root.unit

        Rectangle {
            id: backButton
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: backRow.width + 48 * root.unit
            height: 68 * root.unit
            radius: Theme.radius + 2
            color: Theme.mix(Theme.panel, Theme.accentFill, backMouse.pressed ? 0.45 : 0)
            border.width: backMouse.pressed ? 2 : 1
            border.color: backMouse.pressed ? Theme.accent : Theme.panelBorder
            Row {
                id: backRow
                anchors.centerIn: parent
                spacing: 10 * root.unit
                MaterialIcon { anchors.verticalCenter: parent.verticalCenter; name: "arrow_back"; size: 38 * root.unit; color: Theme.accent }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    text: "戻る"
                    color: Theme.textPrimary
                    font.pixelSize: 28 * root.unit
                    font.bold: true
                }
            }
            MouseArea { id: backMouse; anchors.fill: parent; onClicked: root.back() }
        }
        Text {
            anchors.centerIn: parent
            font.family: Theme.fontFamily
            text: "車両"
            color: Theme.textPrimary
            font.pixelSize: 38 * root.unit
            font.bold: true
        }
        NotificationBell {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            size: 68 * root.unit
        }
    }

    // ---- 左: 項目の一覧 ----
    Rectangle {
        id: sidebar
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left
                  leftMargin: Theme.margin; bottomMargin: Theme.margin; topMargin: 4 }
        width: 340 * root.unit
        color: Theme.panel
        radius: Theme.radius + 6
        border.width: 1
        border.color: Theme.panelBorder

        Flickable {
            anchors { fill: parent; margins: 10 * root.unit }
            contentHeight: sideCol.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: sideCol
                width: parent.width
                spacing: 6 * root.unit
                Repeater {
                    model: root.pages
                    SettingsCategoryButton {
                        required property var modelData
                        required property int index
                        width: sideCol.width
                        icon: modelData.icon
                        title: modelData.title
                        // 故障コードは件数を出す(現在のものがあれば強調)
                        description: modelData.id === "dtc" && ecu.available
                                     ? (ecu.currentDtcCount > 0 ? "現在 " + ecu.currentDtcCount + " 件・過去 " + ecu.pastDtcCount + " 件"
                                        : ecu.pastDtcCount > 0 ? "過去の記録 " + ecu.pastDtcCount + " 件" : "異常なし")
                                     : modelData.description
                        selected: index === root.currentIndex
                        onClicked: root.currentIndex = index
                        // 現在の異常があれば、故障コードの項目に赤い印
                        Rectangle {
                            visible: modelData.id === "dtc" && ecu.available && ecu.currentDtcCount > 0
                            anchors { right: parent.right; rightMargin: 14 * root.unit; verticalCenter: parent.verticalCenter }
                            width: 16 * root.unit; height: width; radius: width / 2
                            color: Theme.error
                        }
                    }
                }
            }
        }
    }

    // ---- 右: 選んだ項目 ----
    Item {
        id: pageArea
        anchors { top: header.bottom; bottom: parent.bottom; left: sidebar.right; right: parent.right
                  leftMargin: Theme.margin; rightMargin: Theme.margin; bottomMargin: Theme.margin; topMargin: 4 }

        // 今いる場所: 「車両 › 項目」と中身の例
        Item {
            id: pageHeader
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 74 * root.unit
            Row {
                id: crumb
                anchors { left: parent.left; leftMargin: 6 * root.unit; top: parent.top; topMargin: 2 * root.unit }
                spacing: 8 * root.unit
                MaterialIcon { anchors.verticalCenter: parent.verticalCenter; name: "directions_car"; size: 22 * root.unit; color: Theme.textSecondary }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: 19 * root.unit
                    color: Theme.textSecondary
                    text: "車両  ›"
                }
                MaterialIcon { anchors.verticalCenter: parent.verticalCenter; name: root.current.icon; size: 30 * root.unit; color: Theme.accent }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: 30 * root.unit
                    font.bold: true
                    color: Theme.textPrimary
                    text: root.current.title
                }
            }
            Text {
                anchors { left: parent.left; leftMargin: 6 * root.unit; right: parent.right; top: crumb.bottom; topMargin: 2 * root.unit }
                font.family: Theme.fontFamily
                font.pixelSize: 17 * root.unit
                color: Theme.textSecondary
                elide: Text.ElideRight
                text: root.current.description + " ・ データ元: " + VehicleSignals.nodes.map(n => n.id + " " + VehicleSignals.nodeStatus(n.id).text).join(" / ")
            }
        }

        Loader {
            id: pageLoader
            anchors { top: pageHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; topMargin: 6 * root.unit }
            sourceComponent: ({ overview: overviewPage, live: livePage, switch: switchPage, dtc: dtcPage,
                                sources: sourcesPage })[root.current.id]
            onLoaded: fadeIn.restart()
            NumberAnimation { id: fadeIn; target: pageLoader; property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic }
        }
    }

    // どのノードから来た値かの小さな印("VIN" / "SEN" / "ECU")
    component SourceChip: Rectangle {
        id: chip
        property string tag: ""
        readonly property real u: Theme.uiScale
        visible: tag !== ""
        width: chipLabel.implicitWidth + 14 * u
        height: chipLabel.implicitHeight + 4 * u
        radius: height / 2
        color: "transparent"
        border.width: 1
        border.color: Theme.panelBorder
        Text {
            id: chipLabel
            anchors.centerIn: parent
            font.family: Theme.fontFamily
            font.pixelSize: 13 * chip.u
            font.bold: true
            color: Theme.textSecondary
            text: chip.tag
        }
    }

    // 値のタイル(名前・値・単位・データ元の印)。概要で使う
    component ValueTile: Rectangle {
        id: tile
        property string title: ""
        property string icon: ""
        property string value: "--"
        property string unitText: ""
        property string tag: ""
        property color valueColor: Theme.textPrimary
        readonly property real u: Theme.uiScale
        height: 118 * u
        radius: Theme.radius + 4
        color: Theme.mix(Theme.panel, Theme.background, 0.25)
        border.width: 1
        border.color: Theme.panelBorder
        Row {
            anchors { left: parent.left; top: parent.top; leftMargin: 14 * tile.u; topMargin: 12 * tile.u; right: parent.right }
            spacing: 6 * tile.u
            MaterialIcon { anchors.verticalCenter: parent.verticalCenter; name: tile.icon; size: 22 * tile.u; color: Theme.accent }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 40 * tile.u - tileChip.width
                font.family: Theme.fontFamily
                font.pixelSize: 17 * tile.u
                color: Theme.textSecondary
                elide: Text.ElideRight
                text: tile.title
            }
        }
        SourceChip { id: tileChip; tag: tile.tag; anchors { right: parent.right; top: parent.top; rightMargin: 10 * tile.u; topMargin: 12 * tile.u } }
        Row {
            anchors { left: parent.left; bottom: parent.bottom; leftMargin: 14 * tile.u; bottomMargin: 10 * tile.u }
            spacing: 6 * tile.u
            Text {
                anchors.baseline: parent.children[1].baseline
                font.family: Theme.numberFontFamily
                font.pixelSize: 40 * tile.u
                font.bold: true
                font.italic: Theme.numberItalic
                color: tile.value === "--" ? Theme.textSecondary : tile.valueColor
                text: tile.value
            }
            Text {
                font.family: Theme.fontFamily
                font.pixelSize: 18 * tile.u
                color: Theme.textSecondary
                text: tile.value === "--" ? "" : tile.unitText
            }
        }
    }

    // 項目のタイル(id から名前・値・単位・データ元を引く。VIN / SEN の項目も ECU の項目も同じ)
    component ItemTile: ValueTile {
        property string itemId: ""
        title: root.itemTitle(itemId)
        icon: root.itemIcon(itemId)
        unitText: root.itemUnit(itemId)
        value: root.numText(itemId)
        tag: root.sourceTag(itemId)
    }

    // ================================================================ 概要
    Component {
        id: overviewPage
        SettingsPage {
            id: ov
            // 車両の状態(いちばん上に大きく)。警告・注意(現在の異常・過去の記録)が出ているときは、タップで故障コードへ
            Rectangle {
                id: banner
                readonly property bool linked: level >= 1
                readonly property int level: !ecu.available ? -1 : ecu.currentDtcCount > 0 || ecu.milOn ? 2 : ecu.pastDtcCount > 0 ? 1 : 0
                readonly property color tone: level === 2 ? Theme.error : level === 1 ? Theme.warn : level === 0 ? Theme.ok : Theme.textSecondary
                width: parent.width
                height: stateCol.implicitHeight + 40 * root.unit
                radius: Theme.radius + 6
                color: Theme.mix(Theme.panel, tone, bannerMouse.pressed ? 0.32 : 0.16)
                border.width: 2
                border.color: tone
                Row {
                    anchors { left: parent.left; leftMargin: 24 * root.unit; verticalCenter: parent.verticalCenter }
                    spacing: 20 * root.unit
                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: parent.parent.level === 2 ? "error" : parent.parent.level === 1 ? "history" : parent.parent.level === 0 ? "check_circle" : "link_off"
                        size: 64 * root.unit
                        color: parent.parent.tone
                    }
                    Column {
                        id: stateCol
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4 * root.unit
                        width: ov.width - (banner.linked ? 380 : 160) * root.unit
                        Text {
                            font.family: Theme.fontFamily
                            font.pixelSize: 30 * root.unit
                            font.bold: true
                            color: Theme.textPrimary
                            text: { const lv = parent.parent.parent.level
                                return lv === 2 ? "車両に異常があります" : lv === 1 ? "過去の異常の記録があります"
                                     : lv === 0 ? "異常はありません" : "ECU のデータがありません" }
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            font.family: Theme.fontFamily
                            font.pixelSize: 19 * root.unit
                            color: Theme.textSecondary
                            text: { const lv = parent.parent.parent.level
                                if (lv < 0) return "エンジン ECU(DIAG): " + VehicleSignals.nodeStatus("DIAG").text
                                const cur = ecu.dtcSummary("current"), past = ecu.dtcSummary("past")
                                return (ecu.milOn ? "チェックランプ点灯 ・ " : "チェックランプ消灯 ・ ")
                                       + (cur !== "" ? "現在: " + cur : past !== "" ? "過去: " + past : "故障コードなし") }
                        }
                    }
                }
                // 右端: 故障コードへ(警告・注意が出ているときだけ)
                Row {
                    visible: banner.linked
                    anchors { right: parent.right; rightMargin: 18 * root.unit; verticalCenter: parent.verticalCenter }
                    spacing: 2 * root.unit
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.fontFamily
                        font.pixelSize: 19 * root.unit
                        font.bold: true
                        color: banner.tone
                        text: "故障コードを見る"
                    }
                    MaterialIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron_right"; size: 36 * root.unit; color: banner.tone }
                }
                MouseArea {
                    id: bannerMouse
                    anchors.fill: parent
                    enabled: banner.linked
                    onClicked: root.currentIndex = root.pages.findIndex(p => p.id === "dtc")
                }
            }

            SettingsSection {
                title: "主要な値"
                icon: "speed"
                Grid {
                    id: tiles
                    width: parent.width
                    columns: Math.max(2, Math.floor(width / (220 * root.unit)))
                    spacing: 12 * root.unit
                    readonly property real cellW: (width - spacing * (columns - 1)) / columns
                    Repeater {
                        model: ["speed", "rpm", "coolant", "throttle", "boost", "voltage",
                                "load", "iat", "ignition", "map", "totalTrimB1", "o2B1S1"]
                        ItemTile { required property var modelData; width: tiles.cellW; itemId: modelData }
                    }
                }
                Item { width: 1; height: 12 * root.unit }
                SettingsInfoRow { label: "燃料系の状態"; value: root.t("fuelStatusB1") }
                SettingsInfoRow {
                    label: "データ元"
                    value: VehicleSignals.nodes.map(n => n.id + " " + VehicleSignals.nodeStatus(n.id).text).join(" / ")
                    valueColor: Theme.textSecondary
                }
            }
        }
    }

    // ================================================================ ライブデータ
    // 1 行: 名前・値・データ元の印
    component LiveRow: Item {
        id: row
        property string itemId: ""
        readonly property real u: Theme.uiScale
        readonly property bool ok: root.has(itemId)
        readonly property var p: root.isNode(itemId) ? null : root.paramOf(itemId)
        width: parent ? parent.width : 0
        height: 60 * u
        Text {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: parent.width * 0.42
            font.family: Theme.fontFamily
            font.pixelSize: 21 * row.u
            color: Theme.textSecondary
            elide: Text.ElideRight
            text: root.itemTitle(row.itemId)
        }
        Text {
            x: parent.width * 0.44
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.56 - liveChip.width - 12 * row.u
            font.family: Theme.fontFamily
            font.pixelSize: 21 * row.u
            color: row.ok ? Theme.textPrimary : Theme.textSecondary
            elide: Text.ElideRight
            text: root.t(row.itemId) + (row.ok || !row.p || row.p.note === "" ? "" : "(" + row.p.note + ")")
        }
        SourceChip { id: liveChip; tag: root.sourceTag(row.itemId); anchors { right: parent.right; verticalCenter: parent.verticalCenter } }
        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.panelBorder; opacity: 0.6 }
    }
    Component {
        id: livePage
        SettingsPage {
            id: lp
            property bool hideMissing: false
            SettingsSection {
                title: "表示"
                icon: "tune"
                SettingsRow {
                    label: "データの無い項目を隠す"
                    description: "このECUでは出ない項目(応答が FF)や、まだ受け取っていない項目を一覧から外します"
                    SettingsSwitch { checked: lp.hideMissing; onToggled: (v) => lp.hideMissing = v }
                }
            }
            Repeater {
                model: VehicleSignals.numberGroups
                SettingsSection {
                    id: gsec
                    required property var modelData
                    // 分類の中は、車両信号(VIN / SEN)の項目 → ECU だけの項目(車両信号にまとめた ECU の項目は出さない)
                    readonly property var items: Object.keys(VehicleSignals.nodeMetrics).filter(k => VehicleSignals.nodeMetrics[k].group === modelData.id)
                        .concat(ecu.params.filter(p => p.group === modelData.id && p.kind !== "bit"
                                                      && VehicleSignals.mergedEcuIds.indexOf(p.id) < 0).map(p => p.id))
                    title: modelData.title
                    icon: modelData.icon
                    visible: items.length > 0 && (!lp.hideMissing || items.some(id => root.has(id)))
                    Repeater {
                        model: gsec.items
                        LiveRow {
                            required property var modelData
                            itemId: modelData
                            visible: !lp.hideMissing || root.has(modelData)
                        }
                    }
                }
            }
            SettingsNote {
                text: "右の印はデータ元のノードです(VIN 車両信号 / SEN 外付けセンサー / ECU エンジン ECU)。"
                      + "車速・回転数・水温・電圧・アクセルは両方から取れるので 1 つにまとめ、使っている方を出します(選び方は 設定 > 車両 > 車両データ)。"
                      + "ECU の値は `21 00` / `21 02` の応答から換算しています(docs/reference/kei_kline_params.csv。位置は HN22S の実車では未確認)。"
            }
        }
    }

    // ================================================================ スイッチ・作動状態
    Component {
        id: switchPage
        SettingsPage {
            SettingsSection {
                title: "スイッチ・作動状態"
                icon: "toggle_on"
                Grid {
                    id: lamps
                    width: parent.width
                    columns: Math.max(2, Math.floor(width / (230 * root.unit)))
                    spacing: 12 * root.unit
                    readonly property real cellW: (width - spacing * (columns - 1)) / columns
                    Repeater {
                        // 車両信号(VIN)の状態 → ECU のスイッチ(ビット)。{ id, title, icon, known, on, tag }
                        model: {
                            ecu.revision
                            const list = [
                                { id: "reverse", title: "バック", icon: "mdi:car-back", known: true, on: reverseCamera.reverse, tag: "VIN" },
                                { id: "engine", title: "エンジン始動", icon: "mdi:engine", known: can.dataAvailable, on: can.engineRunning, tag: can.dataAvailable ? "VIN" : "" }
                            ]
                            for (const p of ecu.params.filter(p => p.kind === "bit"))
                                list.push({ id: p.id, title: p.title, icon: p.icon, known: ecu.has(p.id), on: ecu.has(p.id) && ecu.value(p.id) !== 0,
                                            tag: ecu.has(p.id) ? "ECU" : "" })
                            return list
                        }
                        Rectangle {
                            required property var modelData
                            readonly property bool known: modelData.known
                            readonly property bool on: modelData.on
                            width: lamps.cellW
                            height: 88 * root.unit
                            radius: Theme.radius + 4
                            color: on ? Theme.mix(Theme.panel, Theme.accent, 0.35) : Theme.mix(Theme.panel, Theme.background, 0.25)
                            border.width: on ? 2 : 1
                            border.color: on ? Theme.accent : Theme.panelBorder
                            opacity: known ? 1 : 0.5
                            SourceChip { tag: modelData.tag; anchors { right: parent.right; top: parent.top; rightMargin: 8 * root.unit; topMargin: 8 * root.unit } }
                            Row {
                                anchors { left: parent.left; leftMargin: 14 * root.unit; verticalCenter: parent.verticalCenter }
                                spacing: 12 * root.unit
                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: modelData.icon
                                    size: 34 * root.unit
                                    color: parent.parent.on ? Theme.accent : Theme.textSecondary
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        width: lamps.cellW - 130 * root.unit
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 19 * root.unit
                                        color: Theme.textPrimary
                                        elide: Text.ElideRight
                                        text: modelData.title
                                    }
                                    Text {
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 17 * root.unit
                                        font.bold: true
                                        color: parent.parent.parent.on ? Theme.accent : Theme.textSecondary
                                        text: parent.parent.parent.known ? (parent.parent.parent.on ? "ON" : "OFF") : "データなし"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ================================================================ 故障コード
    component DtcCard: Rectangle {
        id: dc
        property var item: ({})
        property color tone: Theme.error
        readonly property real u: Theme.uiScale
        width: parent ? parent.width : 0
        height: dcCol.implicitHeight + 28 * u
        radius: Theme.radius + 4
        color: Theme.mix(Theme.panel, tone, 0.1)
        border.width: 2
        border.color: tone
        Column {
            id: dcCol
            x: 18 * dc.u
            y: 14 * dc.u
            width: dc.width - 36 * dc.u
            spacing: 4 * dc.u
            Row {
                spacing: 14 * dc.u
                Text {
                    font.family: Theme.numberFontFamily
                    font.pixelSize: 32 * dc.u
                    font.bold: true
                    color: dc.tone
                    text: dc.item.code || ""
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: 18 * dc.u
                    color: Theme.textSecondary
                    text: (dc.item.statusText || "") + " ・ 状態 0x" + (dc.item.status || "--")
                          + (dc.item.lampRequest ? " ・ チェックランプ点灯の要求" : "")
                }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: 22 * dc.u
                font.bold: true
                color: Theme.textPrimary
                text: dc.item.description ? dc.item.description : "(この故障コードの説明は一覧にありません)"
            }
            Text {
                visible: (dc.item.descriptionEn || "") !== "" && dc.item.descriptionEn !== dc.item.description
                width: parent.width
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: 16 * dc.u
                font.italic: true
                color: Theme.textSecondary
                text: dc.item.descriptionEn || ""
            }
            Text {
                visible: (dc.item.system || "") !== ""
                font.family: Theme.fontFamily
                font.pixelSize: 17 * dc.u
                color: Theme.textSecondary
                text: (dc.item.system || "") + " ・ " + (dc.item.category || "")
            }
            Text {
                visible: (dc.item.detail || "") !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: 16 * dc.u
                color: Theme.textSecondary
                text: "検出条件: " + (dc.item.detail || "")
            }
        }
    }
    Component {
        id: dtcPage
        SettingsPage {
            SettingsSection {
                title: "まとめ"
                icon: "summarize"
                SettingsInfoRow {
                    label: "チェックランプ"
                    value: !ecu.available ? "--" : ecu.milOn ? "点灯している" : "消えている"
                    valueColor: ecu.milOn ? Theme.error : Theme.textPrimary
                }
                SettingsInfoRow {
                    label: "現在起きている異常"
                    value: ecu.available ? ecu.currentDtcCount + " 件" : "--"
                    valueColor: ecu.currentDtcCount > 0 ? Theme.error : Theme.textPrimary
                }
                SettingsInfoRow {
                    label: "過去の異常の記録"
                    value: ecu.available ? ecu.pastDtcCount + " 件" : "--"
                    valueColor: ecu.pastDtcCount > 0 ? Theme.warn : Theme.textPrimary
                }
            }
            SettingsSection {
                title: "現在起きている異常"
                icon: "error"
                Column {
                    width: parent.width
                    spacing: 10 * root.unit
                    Repeater {
                        model: ecu.dtcs.filter(d => d.state !== "past")
                        DtcCard { required property var modelData; item: modelData; tone: Theme.error }
                    }
                    SettingsNote { visible: ecu.currentDtcCount === 0; text: ecu.available ? "ありません" : "ECU のデータがありません" }
                }
            }
            SettingsSection {
                title: "過去の異常の記録"
                icon: "history"
                Column {
                    width: parent.width
                    spacing: 10 * root.unit
                    Repeater {
                        model: ecu.dtcs.filter(d => d.state === "past")
                        DtcCard { required property var modelData; item: modelData; tone: Theme.warn }
                    }
                    SettingsNote { visible: ecu.pastDtcCount === 0; text: ecu.available ? "ありません" : "ECU のデータがありません" }
                }
            }
            SettingsNote {
                text: "故障コードの消去は行いません(ECU への書き込みはしない方針)。"
                      + "現在 / 過去の区別は、状態バイトのビット 6〜5(ISO 14230-3 の記録状態)から推定しています(実車で未確認)。"
                      + "説明はスズキの故障コード一覧(日本語訳。原文の英語も下に小さく出します)から引いています。"
                      + "通知の出し方は 設定 > 車両 > 警告・注意 の「車両異常」で変えられます。"
            }
        }
    }

    // ================================================================ データ元・ECU 情報
    Component {
        id: sourcesPage
        SettingsPage {
            // ノードごとの状態
            SettingsSection {
                title: "データ元(ノード)"
                icon: "hub"
                Repeater {
                    model: VehicleSignals.nodes
                    SettingsInfoRow {
                        required property var modelData
                        readonly property var st: VehicleSignals.nodeStatus(modelData.id)
                        label: modelData.id + "  " + modelData.title
                        value: st.text
                        valueColor: !st.available ? Theme.textSecondary : st.mock ? Theme.warn : Theme.ok
                    }
                }
                SettingsNote {
                    text: "VIN: 車速・回転数・ギア・アクセル・ブレーキ・電圧・燃料・バック / SEN: ブースト・水温・油温・油圧 / "
                          + "DIAG: エンジン ECU(K-Line)の計測値・スイッチ・故障コード。VIN と SEN はノードとの通信が入るまでダミーデータです。"
                }
            }
            // 両方から取れる項目で、今どちらを使っているか
            SettingsSection {
                title: "同じ項目のデータ元"
                icon: "alt_route"
                Repeater {
                    model: VehicleSignals.mergedIds
                    SettingsInfoRow {
                        required property var modelData
                        readonly property string now: VehicleSignals.nodeOf(modelData)
                        readonly property var mode: VehicleSignals.sourceModes.find(m => m.id === VehicleSignals.pref(modelData))
                        label: root.itemTitle(modelData)
                        value: (now === "" ? "データなし" : now === "DIAG" ? "ECU" : now) + " を使用(" + (mode ? mode.title : "") + ")"
                        valueColor: now === "" ? Theme.textSecondary : Theme.textPrimary
                    }
                }
                SettingsNote {
                    text: (VehicleSignals.overridden ? "今は「すべての項目をまとめて」の上書きを使っています。" : "")
                          + "選び方は 設定 > 車両 > 車両データ で変えられます。"
                }
            }
            SettingsSection {
                title: "ECU 情報"
                icon: "memory"
                Repeater {
                    model: ecu.ecuInfo
                    SettingsInfoRow { required property var modelData; label: modelData.label; value: modelData.value }
                }
            }
            SettingsSection {
                title: "ECU の通信(K-Line)"
                icon: "cable"
                SettingsInfoRow {
                    label: "状態"
                    value: VehicleSignals.nodeStatus("DIAG").text
                    valueColor: ecu.linkState === "connected" ? Theme.ok : ecu.linkState === "mock" ? Theme.warn : Theme.textSecondary
                }
                SettingsInfoRow { label: "データ元"; value: ecu.sourceText }
                SettingsInfoRow { label: "更新の速さ"; value: ecu.available ? ecu.rateHz.toFixed(1) + " 回/秒(21 00)" : "--" }
                SettingsInfoRow { label: "応答時間"; value: ecu.responseMs >= 0 ? ecu.responseMs + " ms" : "--" }
                SettingsInfoRow { label: "受け取った回数"; value: String(ecu.frameCount) }
                SettingsInfoRow { label: "異常の回数"; value: String(ecu.errorCount); valueColor: ecu.errorCount > 0 ? Theme.warn : Theme.textPrimary }
                SettingsInfoRow { label: "最後に受け取った時刻"; value: ecu.lastUpdateText }
                SettingsNote {
                    text: "K-Line(KWP2000、10400bps、ECU アドレス 0x11)の通信はまだありません。実際の通信(DIAG ノード)は、"
                          + "受け取った応答を EcuData の受け口(ingestBlock / ingestDtcList / ingestEcuInfo)へ渡すだけで、この画面・メーター・警告に反映されます。"
                }
            }
        }
    }
}
