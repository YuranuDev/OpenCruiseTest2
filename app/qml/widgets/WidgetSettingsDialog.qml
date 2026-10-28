// ウィジェットの設定ダイアログ。ウィジェットをダブルタップすると開く(設定画面を持つウィジェットだけ)。
// 中身は、種類ごとの設定画面(WidgetRegistry の settings)+ 全ウィジェット共通の「タイトル」「サイズ」「削除」。
// 設定は上のタブでジャンルに分けて表示する。種類ごとのジャンルは設定画面の WidgetSettingsGroup から作り、
// 最後に全ウィジェット共通の「枠・サイズ」(枠・上部タイトル・サイズ)を付ける。選んだタブは種類ごとに覚えておく。
// 左に設定、右にプレビュー(実際の配置と同じ大きさ・設定のウィジェットを縮小表示)を並べる。
// 設定は変更のたびに WidgetArea へ反映・保存される(「完了」で閉じるだけ)。
// 「一緒に変える」で同じ種類のウィジェット(全ページ)を選ぶと、開いている間に変えた項目がそれらにも同時に入る
// (計測値ごとに違う範囲・単位・警告値・注意値・目盛り間隔と、タイトル文字は写さない。WidgetRegistry.copiesTogether)。
// まとめて設定(showMulti。編集モードで複数選んだとき): 選んだウィジェットすべてに同じ値を入れる。
//  - 同じ種類(設定画面が同じ)だけなら、その種類の設定をすべて出す。違う種類が混ざっていれば、共通の項目(枠・上部タイトル)だけ
//  - 表示している値・プレビューは 1 つめのもの。タイトル文字・サイズは、まとめては変えない
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

    // ---- タブ(ジャンル) ----
    readonly property string commonKey: "__common"
    // 種類ごとの設定画面のジャンル + 共通の「枠・サイズ」
    readonly property var tabs: {
        const own = settingsLoader.item && settingsLoader.item.tabs ? settingsLoader.item.tabs : []
        return own.concat([{ key: commonKey, title: multi ? "枠・タイトル" : "枠・サイズ", icon: "aspect_ratio", active: false }])
    }
    // ---- まとめて設定(複数選択) ----
    property bool multi: false
    property var multiEntries: []      // 選んだウィジェット({ area, wid }。ページをまたいでもよい。1 つめを表示する)
    readonly property var multiWids: multiEntries.map(e => e.wid)
    // 選んだものがあるページ(エリア)の数
    readonly property int multiAreaCount: {
        const seen = []
        for (const e of multiEntries) if (seen.indexOf(e.area) < 0) seen.push(e.area)
        return seen.length
    }
    // 選んだものがすべて同じ種類(設定画面が同じ)か
    readonly property bool multiSameKind: {
        if (!multi || !area) return false
        area.revision
        for (const e of multiEntries) if (!WidgetRegistry.canEditTogether(wtype, e.area.typeOf(e.wid))) return false
        return true
    }
    // 選んだものの名前(同じ名前は「×2」とまとめる)
    readonly property string multiSummary: {
        if (!multi || !area) return ""
        area.revision
        const counts = {}, order = []
        for (const e of multiEntries) {
            const d = WidgetRegistry.find(e.area.typeOf(e.wid))
            const n = d ? d.name : "?"
            if (counts[n] === undefined) { counts[n] = 0; order.push(n) }
            counts[n]++
        }
        return order.map(n => counts[n] > 1 ? n + " ×" + counts[n] : n).join("、")
    }
    property bool confirmDelete: false
    property real confirmAt: 0
    Timer { id: deleteTimer; interval: 3000; onTriggered: root.confirmDelete = false }
    property string tabKey: ""                 // 選んだタブ
    property var lastTabs: ({})                // 種類ごとに最後に選んだタブ(アプリを閉じるまで)
    // 実際に表示するタブ(選んだタブが今は出せないときは先頭)。束縛にはせず、ここで書き換える
    // (画面を壊している途中にタブが切り替わると、壊れかけの行の寸法が計算し直されて警告が大量に出るため)
    property string currentTab: ""
    property bool tearingDown: false
    // アプリの終了時: 設定の中身を、まだ部品が生きているうちに先に片付ける。終了の最後に画面全体を壊すときに
    // まとめて壊すと、壊れかけの行の寸法が計算し直されて警告(Cannot read property ... of null)が大量に出るため
    property bool shuttingDown: false
    Connections {
        target: Qt.application
        function onAboutToQuit() { root.tearingDown = true; root.shuttingDown = true }
    }
    Component.onDestruction: tearingDown = true
    function updateCurrentTab() {
        if (tearingDown) return
        let key = tabs.length > 0 ? tabs[0].key : commonKey
        for (let i = 0; i < tabs.length; ++i) if (tabs[i].key === tabKey) { key = tabKey; break }
        if (currentTab !== key) currentTab = key
    }
    onTabsChanged: updateCurrentTab()
    onTabKeyChanged: updateCurrentTab()
    Component.onCompleted: updateCurrentTab()
    function selectTab(key) {
        panel.forceActiveFocus()        // 入力中の文字を確定させてから切り替える
        tabKey = key
        const m = lastTabs
        m[wtype] = key
        lastTabs = m
        flick.contentY = 0
    }

    // ---- 一緒に変えるウィジェット(開いている間だけ。{ area, wid } の配列) ----
    property var partners: []
    property bool partnerPickerOpen: false
    property var partnerCandidates: []
    // 一緒に変えられるウィジェット(このウィジェットと設定画面が同じもの。ページがあれば全ページから)
    function findCandidates() {
        if (!area) return []
        const pg = area.pages
        const areas = []
        if (pg) {
            for (let i = 0; i < pg.count; ++i) {
                const a = pg.areaAt(i)
                if (a) areas.push({ area: a, where: (i + 1) + " ページ目" + (pg.names[i] ? "「" + pg.names[i] + "」" : "") })
            }
        } else {
            areas.push({ area: area, where: "" })
        }
        const out = []
        for (const e of areas) {
            for (const w of e.area.widgetEntries()) {
                if (e.area === area && w.wid === wid) continue
                if (!WidgetRegistry.canEditTogether(wtype, w.wtype)) continue
                const d = WidgetRegistry.find(w.wtype)
                const c = e.area.configOf(w.wid)
                out.push({ area: e.area, wid: w.wid, icon: d.icon,
                           title: d.name + (c.titleText ? "「" + c.titleText + "」" : ""),
                           where: (e.where ? e.where + "・" : "") + "左から " + (w.col + 1) + " マス目、上から " + (w.row + 1) + " マス目" })
            }
        }
        return out
    }
    function isPartner(c) { return partners.some(p => p.area === c.area && p.wid === c.wid) }
    function togglePartner(c) {
        partners = isPartner(c) ? partners.filter(p => !(p.area === c.area && p.wid === c.wid))
                                : partners.concat([{ area: c.area, wid: c.wid }])
    }
    function openPartnerPicker() {
        panel.forceActiveFocus()
        partnerCandidates = findCandidates()
        partnerPickerOpen = true
    }
    // 設定を変える(選んだウィジェットにも、写す項目なら同じ値を入れる)
    function setValue(key, value) {
        if (!area) return
        area.setConfigValue(wid, key, value)
        for (const p of partners) {
            if (WidgetRegistry.copiesTogether(p.area.typeOf(p.wid), key)) p.area.setConfigValue(p.wid, key, value)
        }
    }
    // 入力中の仮の反映(保存しない)
    function previewValue(key, value) {
        if (!area) return
        area.previewConfigValue(wid, key, value)
        for (const p of partners) {
            if (WidgetRegistry.copiesTogether(p.area.typeOf(p.wid), key)) p.area.previewConfigValue(p.wid, key, value)
        }
    }

    function show(id) {
        multi = false
        multiEntries = []
        wid = id
        partners = []
        partnerPickerOpen = false
        confirmDelete = false
        tabKey = lastTabs[wtype] !== undefined ? lastTabs[wtype] : ""
        flick.contentY = 0
        open = true
    }
    // 複数のウィジェットをまとめて設定する(1 つめの設定を表示し、変えた値を全部に入れる)。
    // list は ID の配列(今の area のもの)か、{ area, wid } の配列(ページをまたぐとき)
    function showMulti(list) {
        if (!list || list.length === 0) return
        const entries = list.map(x => typeof x === "string" ? ({ area: area, wid: x }) : x)
        area = entries[0].area
        if (entries.length === 1) { show(entries[0].wid); return }
        wid = entries[0].wid
        multiEntries = entries
        multi = true
        partners = entries.slice(1)
        partnerPickerOpen = false
        confirmDelete = false
        tabKey = multiSameKind && lastTabs[wtype] !== undefined ? lastTabs[wtype] : (multiSameKind ? "" : commonKey)
        flick.contentY = 0
        open = true
    }
    function close() {
        // 入力中のテキスト欄からフォーカスを外し、確定(editingFinished)させてから閉じる
        panel.forceActiveFocus()
        partnerPickerOpen = false
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
                    name: root.multi && !root.multiSameKind ? "select_all" : (root.def ? root.def.icon : "widgets")
                    size: 34 * root.unit
                    color: Theme.accent
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.pixelSize: 26 * root.unit
                    color: Theme.textPrimary
                    // 同じ種類だけ(例: ターボ圧計 2 個)なら名前、ほかは個数だけ(名前の一覧は右に出す)
                    text: root.multi ? (root.multiSummary.indexOf("、") < 0 && root.def ? root.def.name + " " + root.multiWids.length + " 個をまとめて設定"
                                                                       : root.multiWids.length + " 個のウィジェットをまとめて設定")
                                     : (root.def ? root.def.name + " の設定" : "ウィジェットの設定")
                }
            }
            // まとめて設定: 選んだものの一覧
            Text {
                visible: root.multi
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: Math.min(implicitWidth, parent.width * 0.45)
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: 19 * root.unit
                color: Theme.textSecondary
                text: root.multiSummary
            }
            // 一緒に変えるウィジェットを選ぶ(まとめて設定のときは、もう選んであるので出さない)
            Row {
                visible: !root.multi
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 12 * root.unit
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.partners.length > 0
                    font.family: Theme.fontFamily
                    font.pixelSize: 19 * root.unit
                    color: Theme.accent
                    text: "ほか " + root.partners.length + " 個も一緒に変更中"
                }
                ActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    selected: root.partnerPickerOpen
                    text: "一緒に変える"
                    onClicked: root.partnerPickerOpen ? (root.partnerPickerOpen = false) : root.openPartnerPicker()
                }
            }
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color: Theme.panelBorder
            }
        }

        // ---- タブ(左の設定欄の上)。入りきらないときは横にスクロールする ----
        Flickable {
            id: tabBar
            anchors { top: titleBar.bottom; left: parent.left; right: divider.left
                      leftMargin: Theme.margin * 1.5 - 8 * root.unit; rightMargin: Theme.margin; topMargin: 10 * root.unit }
            height: 66 * root.unit
            clip: true
            contentWidth: tabRow.width
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentWidth > width

            Row {
                id: tabRow
                height: parent.height
                spacing: 2 * root.unit
                Repeater {
                    model: root.tabs
                    Rectangle {
                        id: tab
                        readonly property bool selected: modelData.key === root.currentTab
                        width: tabContent.width + 26 * root.unit
                        height: tabRow.height
                        radius: Theme.radius
                        color: selected ? Theme.mix(Theme.panel, Theme.accentFill, 0.35)
                                        : Theme.mix(Theme.panel, Theme.accentFill, tabMouse.pressed ? 0.22 : 0)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row {
                            id: tabContent
                            anchors.centerIn: parent
                            spacing: 6 * root.unit
                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: modelData.icon || "tune"
                                size: 26 * root.unit
                                color: tab.selected ? Theme.accent : Theme.textSecondary
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: Theme.fontFamily
                                font.pixelSize: 21 * root.unit
                                font.bold: tab.selected
                                color: tab.selected ? Theme.textPrimary : Theme.textSecondary
                                text: modelData.title
                            }
                            // その機能がオンになっている印(警告・注意など)
                            Rectangle {
                                visible: modelData.active === true
                                anchors.verticalCenter: parent.verticalCenter
                                width: 10 * root.unit
                                height: width
                                radius: width / 2
                                color: Theme.ok
                            }
                        }
                        // 選択中の下線
                        Rectangle {
                            visible: tab.selected
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                                      leftMargin: 12 * root.unit; rightMargin: 12 * root.unit }
                            height: 4 * root.unit
                            radius: height / 2
                            color: Theme.accent
                        }
                        MouseArea {
                            id: tabMouse
                            anchors.fill: parent
                            onClicked: root.selectTab(modelData.key)
                        }
                    }
                }
            }
        }
        // 右にまだタブがあるときは、右端をぼかして続きがあることを示す
        Rectangle {
            anchors { top: tabBar.top; bottom: tabBar.bottom; right: tabBar.right }
            width: 48 * root.unit
            visible: tabBar.contentX + tabBar.width < tabBar.contentWidth - 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Theme.panel }
            }
        }
        Rectangle {
            id: tabLine
            anchors { top: tabBar.bottom; left: parent.left; right: divider.left
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin }
            height: 1
            color: Theme.panelBorder
        }

        // ---- 設定の中身(左) ----
        Flickable {
            id: flick
            anchors { top: tabLine.bottom; bottom: footer.top; left: parent.left; right: divider.left
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin; topMargin: 4 * root.unit }
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

                // まとめて設定の案内
                Rectangle {
                    visible: root.multi
                    width: parent.width
                    height: multiNote.implicitHeight + 24 * root.unit
                    radius: Theme.radius
                    color: Theme.mix(Theme.panel, Theme.accent, 0.1)
                    border.color: Theme.mix(Theme.panelBorder, Theme.accent, 0.5)
                    MaterialIcon {
                        id: multiIcon
                        anchors { left: parent.left; leftMargin: 14 * root.unit; top: parent.top; topMargin: 12 * root.unit }
                        name: "info"
                        size: 28 * root.unit
                        color: Theme.accent
                    }
                    Text {
                        id: multiNote
                        anchors { left: multiIcon.right; leftMargin: 10 * root.unit; right: parent.right; rightMargin: 14 * root.unit
                                  top: parent.top; topMargin: 12 * root.unit }
                        wrapMode: Text.WordWrap
                        font.family: Theme.fontFamily
                        font.pixelSize: 20 * root.unit
                        color: Theme.textPrimary
                        text: "ここで変えた項目が、選んだ " + root.multiWids.length + " 個すべてに入ります"
                              + (root.multiAreaCount > 1 ? "(" + root.multiAreaCount + " ページにまたがっています)" : "")
                              + "。表示しているのは 1 つめの今の設定です。"
                              + (root.multiSameKind ? "範囲・単位・警告値・注意値・目盛り間隔とタイトル文字は、それぞれのままです。"
                                                    : "種類の違うウィジェットが混ざっているので、共通の項目(枠・上部タイトル)だけを変えられます。")
                    }
                }
                Item { visible: root.multi; width: 1; height: 10 * root.unit }

                Loader {
                    id: settingsLoader
                    width: parent.width
                    visible: root.currentTab !== root.commonKey
                    active: !root.shuttingDown && (!root.multi || root.multiSameKind)
                    sourceComponent: root.def ? root.def.settings : null
                }
                Binding { target: settingsLoader.item; property: "config"; value: root.cfg; when: settingsLoader.item !== null }
                Binding { target: settingsLoader.item; property: "currentKey"; value: root.currentTab; when: settingsLoader.item !== null }
                Connections {
                    target: settingsLoader.item
                    function onEdit(key, value) { root.setValue(key, value) }
                    // 文字の入力中: 保存せずに、ウィジェットへだけすぐ反映する(確定時は onEdit で保存)
                    function onPreview(key, value) { root.previewValue(key, value) }
                }

                // ---- 全ウィジェット共通(「枠・サイズ」タブ): 枠・タイトル・サイズ ----
                Loader {
                    id: commonLoader
                    width: parent.width
                    visible: root.currentTab === root.commonKey
                    active: !root.shuttingDown
                    sourceComponent: Component {
                        Column {
                            width: commonLoader.width
                            SettingsRow {
                                label: "枠"
                                description: "「なし」にすると背景のカードを描きません"
                                SettingsChoice {
                                    model: ["カード", "なし"]
                                    currentIndex: root.cfg.frame === "plain" ? 1 : 0
                                    onPicked: (i) => root.setValue("frame", i === 1 ? "plain" : "card")
                                }
                            }

                            // ---- 全ウィジェット共通: タイトル ----
                            SettingsRow {
                                label: "上部タイトルを表示"
                                SettingsSwitch {
                                    checked: root.cfg.showTitle !== false
                                    onToggled: (v) => root.setValue("showTitle", v)
                                }
                            }
                            SettingsRow {
                                visible: !root.multi   // タイトル文字は 1 つずつ
                                label: "タイトル文字"
                                description: "空欄ならウィジェット標準の名前を表示します"
                                stacked: true
                                WSTextField {
                                    width: 520 * Theme.uiScale
                                    text: root.cfg.titleText || ""
                                    placeholder: root.def ? root.def.name : "タイトル"
                                    maxLength: 32
                                    // 入力中はウィジェットとプレビューに即反映、保存は確定時(WSTextField の edited)
                                    onChanging: (t) => root.previewValue("titleText", t)
                                    onEdited: (t) => root.setValue("titleText", t)
                                }
                            }

                            // ---- 共通: サイズ ----
                            SettingsRow {
                                visible: !root.multi   // サイズは 1 つずつ(編集画面のマス数を見ながら)
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
                                visible: !root.multi
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
                    text: root.multi ? "プレビュー(1 つめ)" : "プレビュー"
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
                        active: root.visible && root.def !== null && !root.shuttingDown
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

        // ---- 一緒に変えるウィジェットの選択(設定欄・プレビューの上に重ねる) ----
        Rectangle {
            id: partnerPicker
            z: 5
            visible: root.partnerPickerOpen
            // 左右は端まで覆う(下のタブが端からはみ出して見えないように)。中身は左右に余白を取る
            anchors { top: titleBar.bottom; bottom: footer.top; left: parent.left; right: parent.right
                      leftMargin: 1; rightMargin: 1 }
            color: Theme.panel
            MouseArea { anchors.fill: parent }   // 下の設定欄へタップを通さない

            Column {
                id: pickerHead
                anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 14 * root.unit
                          leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5 }
                spacing: 4 * root.unit
                Text {
                    width: parent.width
                    font.family: Theme.fontFamily
                    font.pixelSize: 24 * root.unit
                    font.bold: true
                    color: Theme.textPrimary
                    text: "一緒に変えるウィジェット"
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    font.family: Theme.fontFamily
                    font.pixelSize: 18 * root.unit
                    color: Theme.textSecondary
                    text: "選んだウィジェットにも、この画面を開いている間に変えた設定が同時に入ります(今の設定は写しません)。"
                          + "範囲・単位・警告値・注意値・目盛り間隔と、タイトル文字は、それぞれのウィジェットのままにします。"
                }
            }
            Flickable {
                id: pickerList
                anchors { top: pickerHead.bottom; bottom: parent.bottom; left: parent.left; right: parent.right
                          topMargin: 12 * root.unit; bottomMargin: 8 * root.unit
                          leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5 }
                clip: true
                contentHeight: pickerCol.height
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                Column {
                    id: pickerCol
                    width: pickerList.width
                    spacing: 6 * root.unit
                    Text {
                        visible: root.partnerCandidates.length === 0
                        font.family: Theme.fontFamily
                        font.pixelSize: 20 * root.unit
                        color: Theme.textSecondary
                        text: "同じ種類のウィジェットがほかにありません"
                    }
                    Repeater {
                        model: root.partnerCandidates
                        Rectangle {
                            id: candRow
                            required property var modelData
                            // partners が変わるたびに見直す
                            readonly property bool checked: { root.partners; return root.isPartner(modelData) }
                            width: pickerCol.width
                            height: 76 * root.unit
                            radius: Theme.radius
                            color: Theme.mix(Theme.panel, Theme.accentFill, checked ? 0.3 : (candMouse.pressed ? 0.15 : 0))
                            border.color: checked ? Theme.accent : Theme.panelBorder
                            Row {
                                anchors { left: parent.left; leftMargin: 16 * root.unit; verticalCenter: parent.verticalCenter }
                                spacing: 14 * root.unit
                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: candRow.checked ? "check_box" : "check_box_outline_blank"
                                    size: 34 * root.unit
                                    color: candRow.checked ? Theme.accent : Theme.textSecondary
                                }
                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: candRow.modelData.icon || "widgets"
                                    size: 30 * root.unit
                                    color: Theme.accent
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 21 * root.unit
                                        color: Theme.textPrimary
                                        text: candRow.modelData.title
                                    }
                                    Text {
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 16 * root.unit
                                        color: Theme.textSecondary
                                        text: candRow.modelData.where
                                    }
                                }
                            }
                            MouseArea {
                                id: candMouse
                                anchors.fill: parent
                                onClicked: root.togglePartner(candRow.modelData)
                            }
                        }
                    }
                }
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
                // 削除は 2 回押し(1 回目で確認の文に変わる。3 秒で元に戻る)
                ActionButton {
                    color: root.confirmDelete ? Theme.error : Theme.panel
                    text: root.confirmDelete ? (root.multi ? "もう一度押すと " + root.multiWids.length + " 個を削除" : "もう一度押すと削除")
                                             : (root.multi ? "選んだ " + root.multiWids.length + " 個を削除" : "このウィジェットを削除")
                    onClicked: {
                        if (!root.confirmDelete) {
                            root.confirmDelete = true
                            root.confirmAt = Date.now()
                            deleteTimer.restart()
                            return
                        }
                        if (Date.now() - root.confirmAt < 400) return   // 2 度押しの勢いで消さない
                        deleteTimer.stop()
                        root.confirmDelete = false
                        if (root.multi) {
                            for (const e of root.multiEntries) e.area.removeWidget(e.wid)
                        } else if (root.area) {
                            root.area.removeWidget(root.wid)
                        }
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
