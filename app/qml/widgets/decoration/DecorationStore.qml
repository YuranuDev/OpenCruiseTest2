// 飾りの画像(キャラなど)の、今のページの分の一覧。初期画面(LauncherScreen)に 1 つ置き、
// 表示(DecorationLayer。奥・パネル・手前)と編集(DecorationEditor / DecorationPanel)が同じものを見る。
//  - 保存先は WidgetPages(ページごとの decor)。ページが変わったら、そのページの分を読み直す
//  - 1 つ分(保存の形): { id, file, x, y, w, ar, op, flip, layer }
//    (model の列名は did / file / rx / ry / rw / ar / op / flip / zone。Item の x・y・layer と名前がぶつからないように)
//      x / y … 左上の位置(画面の幅・高さに対する割合。0〜1。少しはみ出してもよい)
//      w     … 幅(画面の幅に対する割合)。高さは w × 画面の幅 × ar(画像の縦横比 = 高さ / 幅)
//      op    … 濃さ(0.05〜1)/ flip … 左右反転
//      layer … 重ね方。"back"(奥: ウィジェット・バーの後ろ)/ "panel"(パネル: ウィジェットのパネルの上、中身の下。
//               パネルの形に切り抜いて出る)/ "front"(手前: ウィジェットの前。タッチは下へ通す)
//               (以前の形式の front: true / false も読める)
//  - 並び順が重なり順(後ろのものほど上)
//  - 動かしている間は model だけを書き換え(画面にすぐ出す)、指を離したら save() で保存する
//  - 元に戻す: 保存のたびに 1 つ前の状態を覚えておき(ページごと。30 回分)、undo() で戻す
import QtQuick
import OpenCruise

Item {
    id: root
    property Item pages: null           // WidgetPages
    readonly property int pageIndex: pages ? pages.current : -1
    readonly property alias model: items
    readonly property int count: items.count
    readonly property var layers: ["back", "panel", "front"]
    // 選んでいる画像の id(編集中だけ使う)
    property string selectedId: ""
    // 画面の大きさ(割合 ⇄ px の変換に使う。LauncherScreen の大きさ)
    property real areaW: 1
    property real areaH: 1
    // 位置・大きさ・重ね方などが変わるたびに増える(パネルの層が、どのウィジェットに重なるかを数え直すため)
    property int revision: 0

    // 元に戻す
    property var undoStack: []
    readonly property bool canUndo: undoStack.length > 0
    property string lastSaved: "[]"

    ListModel { id: items; dynamicRoles: true }
    // ページを読み直したとき(表示側がふわっと出し直す)
    signal reloaded()

    // ---- 読み込み・保存 ----
    function reload() {
        selectedId = ""
        undoStack = []
        fill(pages && pageIndex >= 0 ? pages.pageDecor(pageIndex) : [])
        lastSaved = JSON.stringify(toArray())
        reloaded()
    }
    function fill(list) {
        items.clear()
        const used = {}
        for (const e of list) {
            if (!e || typeof e.file !== "string" || e.file === "") continue
            const id = (e.id && !used[e.id]) ? String(e.id) : newId()
            used[id] = true
            items.append(sanitize(Object.assign({}, e, { id: id })))
        }
        revision++
    }
    function sanitize(e) {
        const num = (v, d) => (typeof v === "number" && isFinite(v)) ? v : d
        const w = Math.max(0.03, Math.min(1.5, num(e.w, 0.25)))
        return {
            did: String(e.id),
            file: String(e.file),
            rx: Math.max(-w, Math.min(1, num(e.x, 0.4))),
            ry: Math.max(-1, Math.min(1, num(e.y, 0.3))),
            rw: w,
            ar: Math.max(0.05, Math.min(20, num(e.ar, 1))),
            op: Math.max(0.05, Math.min(1, num(e.op, 1))),
            flip: e.flip === true,
            zone: layers.indexOf(e.layer) >= 0 ? e.layer : (e.front === true ? "front" : "back")
        }
    }
    function toArray() {
        const list = []
        for (let i = 0; i < items.count; ++i) {
            const it = items.get(i)
            list.push({ id: it.did, file: it.file, x: round(it.rx), y: round(it.ry), w: round(it.rw), ar: round(it.ar),
                        op: round(it.op), flip: it.flip, layer: it.zone })
        }
        return list
    }
    function round(v) { return Math.round(v * 10000) / 10000 }
    // 保存する(1 つ前の状態を「元に戻す」用に覚えておく。recordUndo が false なら覚えない)
    function save(recordUndo) {
        revision++
        const list = toArray()
        const now = JSON.stringify(list)
        if (now === lastSaved) return
        if (recordUndo !== false) {
            const st = undoStack.slice(-29)
            st.push(lastSaved)
            undoStack = st
        }
        lastSaved = now
        if (pages && pageIndex >= 0) pages.savePageDecor(pageIndex, list)
    }
    function undo() {
        if (undoStack.length === 0) return
        const st = undoStack.slice()
        const prev = st.pop()
        undoStack = st
        const keepSel = selectedId
        try { fill(JSON.parse(prev)) } catch (e) { return }
        selectedId = indexOf(keepSel) >= 0 ? keepSel : ""
        lastSaved = prev
        if (pages && pageIndex >= 0) pages.savePageDecor(pageIndex, toArray())
    }

    function newId() { return "d" + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36) }
    function indexOf(id) {
        for (let i = 0; i < items.count; ++i) if (items.get(i).did === id) return i
        return -1
    }
    function get(id) { const i = indexOf(id); return i < 0 ? null : items.get(i) }

    // ---- 操作 ----
    // 画像を足す(画面の中央に、幅 1/4 で。縦長の画像は高さが画面の 6 割に収まるように)。足した id を返す
    function add(file, ar) {
        ar = (typeof ar === "number" && ar > 0) ? ar : 1
        let w = 0.25
        const maxH = 0.6
        if (w * areaW * ar > maxH * areaH) w = maxH * areaH / (areaW * ar)
        const h = w * areaW * ar / areaH
        const id = newId()
        items.append(sanitize({ id: id, file: file, x: 0.5 - w / 2, y: 0.5 - h / 2, w: w, ar: ar, op: 1, flip: false, layer: "back" }))
        selectedId = id
        save()
        return id
    }
    function remove(id) {
        const i = indexOf(id)
        if (i < 0) return
        items.remove(i)
        if (selectedId === id) selectedId = ""
        save()
    }
    function duplicate(id) {
        const it = get(id)
        if (!it) return
        const nid = newId()
        items.append({ did: nid, file: it.file, rx: Math.min(0.95, it.rx + 0.03), ry: Math.min(0.95, it.ry + 0.04), rw: it.rw,
                       ar: it.ar, op: it.op, flip: it.flip, zone: it.zone })
        selectedId = nid
        save()
    }
    // 値を変える(doSave が false なら画面にだけ出す。スライダーを動かしている間)
    function setValue(id, key, value, doSave) {
        const i = indexOf(id)
        if (i < 0) return
        items.setProperty(i, key, value)
        if (doSave) save()
        else revision++
    }
    // 位置と幅をまとめて変える(画面の外へ出しすぎないように。少なくとも 1/4 は画面に残す)
    function setGeometry(id, x, y, w) {
        const i = indexOf(id)
        if (i < 0) return
        const it = items.get(i)
        w = Math.max(0.03, Math.min(1.5, w))
        const h = w * areaW * it.ar / areaH
        x = Math.max(-w * 0.75, Math.min(1 - w * 0.25, x))
        y = Math.max(-h * 0.75, Math.min(1 - h * 0.25, y))
        items.setProperty(i, "rw", w)
        items.setProperty(i, "rx", x)
        items.setProperty(i, "ry", y)
        revision++
    }
    // 大きさを変える(中心はそのまま)
    function scaleAround(id, w, cx, cy) {
        const it = get(id)
        if (!it) return
        w = Math.max(0.03, Math.min(1.5, w))
        const h = w * areaW * it.ar / areaH
        setGeometry(id, cx - w / 2, cy - h / 2, w)
    }
    // いちばん上(同じ層の中で)へ
    function raise(id) {
        const i = indexOf(id)
        if (i < 0 || i === items.count - 1) return
        items.move(i, items.count - 1, 1)
        save()
    }
    // 画像を読み込めたときに、実際の縦横比と違っていれば直す(画像を差し替えたときなど。元に戻すの対象にしない)
    function noteAspect(id, ar) {
        const i = indexOf(id)
        if (i < 0 || !(ar > 0)) return
        if (Math.abs(items.get(i).ar - ar) / ar > 0.01) {
            items.setProperty(i, "ar", ar)
            save(false)
        }
    }

    onPageIndexChanged: reload()
    Connections {
        target: root.pages
        function onDecorRevisionChanged() { root.reload() }
    }
    Component.onCompleted: reload()
}
