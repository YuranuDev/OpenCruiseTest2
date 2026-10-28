// ウィジェットのページ。ページごとに 1 つの WidgetArea を持ち、横に並べて切り替える(今のページだけ表示する)。
//  - どのページのウィジェットも常に動かしておく(隠れているページのメーターも警告・警告音を出し、
//    そのページのタブが赤くなる)。隠れているページは描画しない
//  - 切り替え: ページのタブ(PageBar)をタップ、またはウィジェットの無い所を左右にスワイプ
//  - 保存: widgetStore.layoutJson に { version: 2, current, pages: [{ id, name, widgets: [...] }] }。
//    以前の形式(version 1 = 1 ページ分の widgets)は、1 ページ目として読み込む
//  - 外からは currentArea(追加パネル・設定ダイアログの対象)と、addPage / removePage / renamePage / movePage /
//    setCurrent / resetAll、settingsRequested(area, wid) / pickerRequested() を使う
import QtQuick
import OpenCruise

Item {
    id: root

    readonly property int maxPages: 8
    readonly property int count: pageModel.count
    property int current: 0
    // ページ名(タブ用)。変わるたびに作り直す
    property var names: []
    // 保存内容(ページ id → widgets の配列。null なら初期配置)
    property var store: ({})
    readonly property Item currentArea: rep.count > current ? rep.itemAt(current) : null
    // 編集モード(全ページ共通)。選択はページごとに持つが、ページを移っても外さない(ページをまたいで選べる)
    property bool editMode: false
    // どこかのページの選択が変わるたびに増える(全ページの選択数などを束縛で読み直すため)
    property int selectionRevision: 0
    function noteSelectionChanged() { selectionRevision++ }
    // 全ページで選んでいるウィジェット({ area, wid } の配列。今のページのものを先に)
    function selectedEntries() {
        selectionRevision
        const list = []
        const order = [current]
        for (let i = 0; i < rep.count; ++i) if (i !== current) order.push(i)
        for (const i of order) {
            const a = rep.itemAt(i)
            if (!a) continue
            for (const w of a.selection) list.push({ area: a, wid: w })
        }
        return list
    }
    // 選んでいるウィジェットがあるページの数
    function selectedPageCount() {
        selectionRevision
        let n = 0
        for (let i = 0; i < rep.count; ++i) { const a = rep.itemAt(i); if (a && a.selection.length > 0) ++n }
        return n
    }
    // 全ページのウィジェットの数
    function widgetTotal() {
        selectionRevision
        let n = 0
        for (let i = 0; i < rep.count; ++i) { const a = rep.itemAt(i); if (a) n += a.count }
        return n
    }
    function clearAllSelection() {
        for (let i = 0; i < rep.count; ++i) { const a = rep.itemAt(i); if (a) a.clearSelection() }
    }
    function selectAllPages() {
        for (let i = 0; i < rep.count; ++i) { const a = rep.itemAt(i); if (a) a.selectAll() }
    }
    function removeAllSelected() {
        for (let i = 0; i < rep.count; ++i) { const a = rep.itemAt(i); if (a) a.removeSelected() }
    }

    signal settingsRequested(Item area, string wid)
    signal pickerRequested()

    clip: true

    ListModel { id: pageModel }   // { pid, name }

    function newPid() { return "p" + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36) }

    function refreshNames() {
        const list = []
        for (let i = 0; i < pageModel.count; ++i) list.push(pageModel.get(i).name)
        names = list
    }

    // ---- 保存・読み込み ----
    function persist() {
        const pages = []
        for (let i = 0; i < pageModel.count; ++i) {
            const pg = pageModel.get(i)
            const w = store[pg.pid]
            pages.push({ id: pg.pid, name: pg.name, widgets: Array.isArray(w) ? w : null })
        }
        widgetStore.layoutJson = JSON.stringify({ version: 2, current: current, pages: pages })
    }

    function load() {
        let pages = null
        let cur = 0
        try {
            const o = JSON.parse(widgetStore.layoutJson)
            if (o && o.version === 2 && Array.isArray(o.pages) && o.pages.length > 0) {
                pages = o.pages
                cur = o.current || 0
            } else if (o && o.version === 1 && Array.isArray(o.widgets)) {
                pages = [{ name: "ページ 1", widgets: o.widgets }]   // 以前の形式(1 ページだけ)
            }
        } catch (e) { /* 未保存・壊れている場合は初期配置を使う */ }
        if (pages === null) pages = [{ name: "ページ 1", widgets: null }]
        // 先に保存内容をそろえてから、ページ(WidgetArea)を作る(作られたときに pageWidgets() で読むため)
        const st = {}
        const used = {}
        const entries = []
        for (let i = 0; i < Math.min(pages.length, maxPages); ++i) {
            const p = pages[i]
            const pid = (p.id && !used[p.id]) ? p.id : newPid()
            used[pid] = true
            st[pid] = Array.isArray(p.widgets) ? p.widgets : (i === 0 ? null : [])
            entries.push({ pid: pid, name: String(p.name || ("ページ " + (i + 1))) })
        }
        pageModel.clear()
        store = st
        current = Math.max(0, Math.min(entries.length - 1, cur))
        for (let i = 0; i < entries.length; ++i) pageModel.append(entries[i])
        refreshNames()
    }

    // index 番目のページの WidgetArea(設定ダイアログの「一緒に変える」が、全ページのウィジェットを探すのに使う)
    function areaAt(index) { return rep.itemAt(index) }

    // WidgetArea から呼ばれる
    function pageWidgets(index) {
        if (index < 0 || index >= pageModel.count) return []
        return store[pageModel.get(index).pid]
    }
    function savePage(index, list) {
        if (index < 0 || index >= pageModel.count) return
        store[pageModel.get(index).pid] = list
        persist()
    }

    // ---- ページの操作 ----
    function setCurrent(index) {
        index = Math.max(0, Math.min(pageModel.count - 1, index))
        if (index === current) return
        current = index
        persist()
    }
    function addPage() {
        if (pageModel.count >= maxPages) {
            notifications.show("ページを追加できません", "ページは " + maxPages + " ページまでです", 2, "web_stories")
            return false
        }
        // 「ページ N」の N は、使われていない最小の番号
        let n = pageModel.count + 1
        for (let k = 1; k <= maxPages + 1; ++k) {
            if (names.indexOf("ページ " + k) < 0) { n = k; break }
        }
        const pid = newPid()
        store[pid] = []
        pageModel.append({ pid: pid, name: "ページ " + n })
        refreshNames()
        current = pageModel.count - 1
        persist()
        return true
    }
    function removePage(index) {
        if (pageModel.count <= 1 || index < 0 || index >= pageModel.count) return false
        const pid = pageModel.get(index).pid
        pageModel.remove(index)   // そのページのウィジェット(警告の登録も)ごと消える
        delete store[pid]
        if (current >= pageModel.count) current = pageModel.count - 1
        else if (current > index) current--
        refreshNames()
        persist()
        return true
    }
    function renamePage(index, name) {
        if (index < 0 || index >= pageModel.count) return
        name = String(name).trim()
        if (name === "") name = "ページ " + (index + 1)
        pageModel.setProperty(index, "name", name)
        refreshNames()
        persist()
    }
    // dir: -1 で左へ、+1 で右へ
    function movePage(index, dir) {
        const to = index + dir
        if (index < 0 || index >= pageModel.count || to < 0 || to >= pageModel.count) return
        pageModel.move(index, to, 1)
        if (current === index) current = to
        else if (current === to) current = index
        refreshNames()
        persist()
    }
    function resetAll() {
        widgetStore.layoutJson = ""
        load()
    }
    // そのページに警告中のウィジェットがあるか(タブ用)
    function pageAlarm(index) {
        const a = rep.itemAt(index)
        return a ? a.alarmActive : false
    }

    Component.onCompleted: load()

    // ---- 左右スワイプで切り替え(ウィジェットの無い所で受ける) ----
    MouseArea {
        anchors.fill: parent
        property real startX: 0
        property real startY: 0
        onPressed: (mouse) => { startX = mouse.x; startY = mouse.y }
        onReleased: (mouse) => {
            const dx = mouse.x - startX, dy = mouse.y - startY
            if (Math.abs(dx) > Math.max(80, width * 0.08) && Math.abs(dx) > Math.abs(dy) * 1.5)
                root.setCurrent(root.current + (dx < 0 ? 1 : -1))
        }
    }

    // ---- ページを横に並べ、今のページへ滑らせる ----
    Item {
        id: strip
        width: root.width
        height: root.height
        x: -root.current * root.width
        Behavior on x { NumberAnimation { id: slideAnim; duration: 280; easing.type: Easing.OutCubic } }

        Repeater {
            id: rep
            model: pageModel
            WidgetArea {
                id: pageArea
                required property int index
                x: index * root.width
                width: root.width
                height: root.height
                pages: root
                pageIndex: index
                editMode: root.editMode
                // 隠れているページは描画しない(切り替えのアニメーション中は、両隣も描く)
                visible: index === root.current || (slideAnim.running && Math.abs(index - root.current) <= 1)
                onSettingsRequested: (wid) => root.settingsRequested(pageArea, wid)
                onPickerRequested: root.pickerRequested()
                // ページを並び替えて index が変わっても、読み直さずにそのまま使う(保存先の index だけ変わる)
            }
        }
    }
}
