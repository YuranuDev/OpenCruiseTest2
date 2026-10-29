// ウィジェット配置エリア(1 ページ分)。初期画面の中央領域の全体を、cols × rows のグリッドとして使う。
//  - 配置と設定(config)は ListModel(layout)に持ち、変更のたびに pages(WidgetPages)へ渡して保存してもらう
//  - ドラッグ中(dragging)だけグリッドと移動先の枠をフェード表示し、離すと最寄りの空きマスへスナップする
//  - 置いてあるウィジェットの上に重ねると、重なったウィジェットを押しのける(重ねた位置から遠ざかる向きへ。
//    動かしている間は押しのけた先へ仮に動かして見せ、離すと確定する)。押しのけられないときは、重ならない最寄りのマスへ寄せる
// 外部(設定ダイアログ・追加パネル)からは、下の関数群(addWidget / removeWidget / setConfigValue /
// resizeWidget / resetLayout / configOf)と settingsRequested シグナルを使う。
//
// 編集モード(editMode。初期画面・Android Auto 画面の「編集」で入る):
//  - グリッドを常に出し、各ウィジェットに名前・大きさ(「3 x 2」)・設定と削除の丸いボタンを重ねる(WidgetHost)
//  - ウィジェットの中身は操作できない。タップで選択/解除(selection)、ドラッグですぐ移動(長押しは要らない)
//  - 選んだウィジェットをドラッグすると、選択中のものが並びを保ってまとめて動く(入らない・重なる場所には置けない)
// 編集モードでないときの操作(ダブルタップで設定、長押しで移動)は今まで通り。
import QtQuick
import OpenCruise

Item {
    id: widgetArea

    // ---- グリッド ----
    readonly property int cols: 12
    readonly property int rows: 6
    readonly property real cellW: width / cols
    readonly property real cellH: height / rows
    // ウィジェット同士の隙間の半分
    readonly property real pad: 4 * Theme.uiScale

    // ---- 状態 ----
    property bool animReady: false     // false の間は位置・大きさの変化をアニメーションしない(起動直後・リサイズ中)
    property string dragId: ""
    readonly property bool dragging: dragId !== ""
    // 右下のつまみでサイズを変えている間のウィジェット(編集モード)
    property string resizeId: ""
    readonly property bool resizing: resizeId !== ""
    property var resizeStart: ({ w: 0, h: 0 })
    // ---- 編集モード・選択 ----
    property bool editMode: false
    property var selection: []          // 選んだウィジェットの ID
    onEditModeChanged: if (!editMode) clearSelection()
    // ページの束(WidgetPages)へ知らせる(ページをまたいだ選択の数を数え直すため。Android Auto 画面では無し)
    onSelectionChanged: if (pages && pages.noteSelectionChanged) pages.noteSelectionChanged()
    // まとめて移動(選択中のものを動かしているとき): 動かしているもの以外は、動かしている量(groupOffset。px)だけずらして表示する
    property var groupIds: []
    property var groupStart: ({})       // 動かし始めたときの位置(wid → { col, row, w, h })
    property var groupOffset: ({ x: 0, y: 0 })
    property var groupPreview: []       // 離したときに入るマス(選択中のものすべて)
    readonly property bool groupDragging: dragging && groupIds.length > 1
    property var preview: ({ col: 0, row: 0, w: 1, h: 1, ok: true })
    // ドラッグ中に押しのけたウィジェットの仮の位置(wid → { col, row })。WidgetHost がこちらを優先して表示する
    property var tempPos: ({})
    // ---- 使えないマス(Android Auto 画面の映像の場所) ----
    // { col, row, w, h }(null なら無し)。ここにはウィジェットを置けない(移動・追加・サイズ変更とも)。
    // 変わったときは、重なったウィジェットを近くの空きへ動かし、空きが無ければ「よけておく」(parked)。
    // よけたウィジェットは保存内容に残し、空きができたら自動で戻す(消えない)
    property var blocked: null
    property var parked: []
    property bool loaded: false
    // ウィジェットが 1 つも無いときの案内(「ウィジェットを追加」)を出すか
    property bool showEmptyState: true
    onBlockedChanged: if (loaded) applyBlocked()

    // ---- 飾りの画像(重ね方「パネル」。初期画面のページだけ) ----
    property Item decorSource: null    // DecorationStore
    property real decorOx: 0           // このエリアの左上の、画面上の位置
    property real decorOy: 0

    // ---- ページ ----
    property Item pages: null          // WidgetPages(保存先)
    property int pageIndex: 0
    // このページに、警告音を鳴らしている(または消音中の)ウィジェットがあるか(ページのタブを赤くする)
    readonly property bool alarmActive: {
        WarningAlarm.revision; revision
        for (let i = 0; i < layout.count; ++i) {
            if (WarningAlarm.isActive(layout.get(i).wid)) return true
        }
        return false
    }
    // 保存・設定変更のたびに増える。設定ダイアログが最新の設定を読み直すために束縛する
    property int revision: 0
    readonly property int count: layout.count

    signal settingsRequested(string wid)
    signal pickerRequested()

    ListModel { id: layout; dynamicRoles: true }

    Timer {
        id: readyTimer
        interval: 150
        onTriggered: widgetArea.animReady = true
    }
    onWidthChanged: { animReady = false; readyTimer.restart() }
    onHeightChanged: { animReady = false; readyTimer.restart() }

    // ---------------------------------------------------------------- 配置の計算
    function indexOfId(wid) {
        for (let i = 0; i < layout.count; ++i) {
            if (layout.get(i).wid === wid) return i
        }
        return -1
    }

    // (c, r, w, h) が ignore 以外のウィジェットと重なるか
    function overlapsBlocked(c, r, w, h) {
        const b = blocked
        return !!b && c < b.col + b.w && c + w > b.col && r < b.row + b.h && r + h > b.row
    }
    function overlaps(c, r, w, h, ignore) {
        if (overlapsBlocked(c, r, w, h)) return true
        for (let i = 0; i < layout.count; ++i) {
            const it = layout.get(i)
            if (it.wid === ignore) continue
            if (c < it.col + it.w && c + w > it.col && r < it.row + it.h && r + h > it.row) return true
        }
        return false
    }

    // 希望のマスに置けなければ、重ならない最寄りのマスを返す。どこにも置けなければ ok:false
    function resolveSpot(wid, c, r, w, h) {
        c = Math.max(0, Math.min(cols - w, c))
        r = Math.max(0, Math.min(rows - h, r))
        if (!overlaps(c, r, w, h, wid)) return { col: c, row: r, ok: true }
        let best = null
        let bestD = 1e9
        for (let rr = 0; rr <= rows - h; ++rr) {
            for (let cc = 0; cc <= cols - w; ++cc) {
                if (overlaps(cc, rr, w, h, wid)) continue
                const d = (cc - c) * (cc - c) + (rr - r) * (rr - r)
                if (d < bestD) { bestD = d; best = { col: cc, row: rr, ok: true } }
            }
        }
        return best ? best : { col: c, row: r, ok: false }
    }

    // ---- 押しのけ ----
    function rectsOverlap(a, b) {
        return a.col < b.col + b.w && a.col + a.w > b.col && a.row < b.row + b.h && a.row + a.h > b.row
    }
    function fits(rect, fixed) {
        if (rect.col < 0 || rect.row < 0 || rect.col + rect.w > cols || rect.row + rect.h > rows) return false
        for (let i = 0; i < fixed.length; ++i) {
            if (rectsOverlap(rect, fixed[i])) return false
        }
        return true
    }
    // wid を (c, r) に置くとき、重なるウィジェットを押しのける配置を考える。
    // 押しのける向き: 重ねたウィジェットの中心から見て、相手の中心がある側(左右・上下のうち離れている軸を先に)。
    // その向きでだめなら他の向き、それでもだめなら元の位置に近い空きマス。どれも無ければ ok:false
    function planDrop(wid, c, r, w, h) {
        c = Math.max(0, Math.min(cols - w, c))
        r = Math.max(0, Math.min(rows - h, r))
        const target = { col: c, row: r, w: w, h: h }
        if (overlapsBlocked(c, r, w, h)) return { col: c, row: r, ok: false, moves: {} }   // 使えないマスには置けない
        const hit = [], fixed = [target]
        if (blocked) fixed.push(blocked)
        for (let i = 0; i < layout.count; ++i) {
            const it = layout.get(i)
            if (it.wid === wid) continue
            const rect = { wid: it.wid, col: it.col, row: it.row, w: it.w, h: it.h }
            if (rectsOverlap(rect, target)) hit.push(rect)
            else fixed.push(rect)
        }
        const moves = {}
        if (hit.length === 0) return { col: c, row: r, ok: true, moves: moves }
        hit.sort((a, b) => b.w * b.h - a.w * a.h)   // 大きいものから場所を決める
        const tcx = c + w / 2, tcy = r + h / 2
        for (let k = 0; k < hit.length; ++k) {
            const o = hit[k]
            const dx = (o.col + o.w / 2) - tcx, dy = (o.row + o.h / 2) - tcy
            const horiz = [dx < 0 ? { col: c - o.w, row: o.row } : { col: c + w, row: o.row },
                           dx < 0 ? { col: c + w, row: o.row } : { col: c - o.w, row: o.row }]
            const vert = [dy < 0 ? { col: o.col, row: r - o.h } : { col: o.col, row: r + h },
                          dy < 0 ? { col: o.col, row: r + h } : { col: o.col, row: r - o.h }]
            const cands = Math.abs(dx) / w >= Math.abs(dy) / h ? [horiz[0], vert[0], vert[1], horiz[1]]
                                                               : [vert[0], horiz[0], horiz[1], vert[1]]
            let placed = null
            for (let j = 0; j < cands.length && !placed; ++j) {
                const rect = { col: cands[j].col, row: cands[j].row, w: o.w, h: o.h }
                if (fits(rect, fixed)) placed = rect
            }
            if (!placed) {   // 元の位置に近い空きマス
                let bestD = 1e9
                for (let rr = 0; rr <= rows - o.h; ++rr) {
                    for (let cc = 0; cc <= cols - o.w; ++cc) {
                        const rect = { col: cc, row: rr, w: o.w, h: o.h }
                        if (!fits(rect, fixed)) continue
                        const d = (cc - o.col) * (cc - o.col) + (rr - o.row) * (rr - o.row)
                        if (d < bestD) { bestD = d; placed = rect }
                    }
                }
            }
            if (!placed) return { col: c, row: r, ok: false, moves: {} }
            moves[o.wid] = { col: placed.col, row: placed.row }
            fixed.push(placed)
        }
        return { col: c, row: r, ok: true, moves: moves }
    }

    function newId() {
        return "w" + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36)
    }

    // ---------------------------------------------------------------- 選択(編集モード)
    function isSelected(wid) { return selection.indexOf(wid) >= 0 }
    function toggleSelect(wid) {
        selection = isSelected(wid) ? selection.filter(w => w !== wid) : selection.concat([wid])
    }
    function clearSelection() { if (selection.length > 0) selection = [] }
    function selectAll() {
        const list = []
        for (let i = 0; i < layout.count; ++i) list.push(layout.get(i).wid)
        selection = list
    }
    // 選んだウィジェットをまとめて消す
    function removeSelected() {
        const list = selection
        selection = []
        for (const wid of list) removeWidget(wid)
    }

    // ---------------------------------------------------------------- ドラッグ(WidgetHost から呼ばれる)
    function dragBegin(wid) {
        const i = indexOfId(wid)
        if (i < 0) return
        const it = layout.get(i)
        preview = { col: it.col, row: it.row, w: it.w, h: it.h, ok: true }
        // 編集モードで、選んだものを 2 つ以上選んでいて、その 1 つを動かしたときは、まとめて動かす
        if (editMode && selection.length > 1 && isSelected(wid)) {
            const start = {}
            const ids = []
            for (const s of selection) {
                const j = indexOfId(s)
                if (j < 0) continue
                const o = layout.get(j)
                start[s] = { col: o.col, row: o.row, w: o.w, h: o.h }
                ids.push(s)
            }
            groupStart = start
            groupIds = ids
            groupOffset = { x: 0, y: 0 }
            groupPreview = ids.map(s => Object.assign({ ok: true }, start[s]))
        }
        dragId = wid
    }

    // ドラッグ中の位置(左上の px)を、エリアの中に収める。まとめて動かすときは、全体がエリアから出ないようにする
    function clampDrag(wid, x, y, w, h) {
        if (groupIds.length > 1 && dragId === wid && groupStart[wid]) {
            const a = groupStart[wid]
            let minC = 0, minR = 0, maxC = cols, maxR = rows
            for (const s of groupIds) {
                const g = groupStart[s]
                minC = Math.max(minC, a.col - g.col)                  // 一番左のものが 0 より左へ出ない
                minR = Math.max(minR, a.row - g.row)
                maxC = Math.min(maxC, cols - (g.col + g.w - a.col))   // 一番右のものが右端から出ない
                maxR = Math.min(maxR, rows - (g.row + g.h - a.row))
            }
            return { x: Math.max(minC * cellW + pad, Math.min(maxC * cellW + pad, x)),
                     y: Math.max(minR * cellH + pad, Math.min(maxR * cellH + pad, y)) }
        }
        return { x: Math.max(0, Math.min(width - w, x)), y: Math.max(0, Math.min(height - h, y)) }
    }

    // まとめて動かすとき: 動かしているもののマスのずれ(dc, dr)を全員に足した配置が置けるか
    function planGroup(dc, dr) {
        const rects = []
        let ok = true
        for (const s of groupIds) {
            const g = groupStart[s]
            const rect = { col: g.col + dc, row: g.row + dr, w: g.w, h: g.h }
            if (rect.col < 0 || rect.row < 0 || rect.col + rect.w > cols || rect.row + rect.h > rows
                    || overlapsBlocked(rect.col, rect.row, rect.w, rect.h)) ok = false
            for (let i = 0; i < layout.count && ok; ++i) {
                const it = layout.get(i)
                if (groupIds.indexOf(it.wid) >= 0) continue   // 一緒に動くもの同士は重ならない(並びを保つ)
                if (rectsOverlap(rect, it)) ok = false
            }
            rects.push(rect)
        }
        return { ok: ok, rects: rects }
    }

    function dragUpdate(wid, x, y) {
        const i = indexOfId(wid)
        if (i < 0) return
        const it = layout.get(i)
        const c = Math.round((x - pad) / cellW), r = Math.round((y - pad) / cellH)
        if (groupIds.length > 1) {
            const a = groupStart[wid]
            groupOffset = { x: x - (a.col * cellW + pad), y: y - (a.row * cellH + pad) }
            const plan = planGroup(c - a.col, r - a.row)
            groupPreview = plan.rects.map(rc => Object.assign({ ok: plan.ok }, rc))
            preview = { col: c, row: r, w: it.w, h: it.h, ok: plan.ok }
            return
        }
        // まず押しのけを試し、だめなら重ならない最寄りのマスへ寄せる(従来どおり)
        const plan = planDrop(wid, c, r, it.w, it.h)
        if (plan.ok) {
            preview = { col: plan.col, row: plan.row, w: it.w, h: it.h, ok: true }
            if (JSON.stringify(plan.moves) !== JSON.stringify(tempPos)) tempPos = plan.moves
            return
        }
        if (Object.keys(tempPos).length > 0) tempPos = ({})
        const s = resolveSpot(wid, c, r, it.w, it.h)
        preview = s.ok ? { col: s.col, row: s.row, w: it.w, h: it.h, ok: true }
                       : { col: it.col, row: it.row, w: it.w, h: it.h, ok: false }
    }

    function dragEnd(wid) {
        const i = indexOfId(wid)
        let changed = false
        if (groupIds.length > 1) {
            // まとめて動かしたとき: 全員が置ければ確定、置けなければ元の位置へ戻す
            const a = groupStart[wid]
            const plan = a ? planGroup(preview.col - a.col, preview.row - a.row) : { ok: false }
            if (a && plan.ok && (preview.col !== a.col || preview.row !== a.row)) {
                for (let k = 0; k < groupIds.length; ++k) {
                    const j = indexOfId(groupIds[k])
                    if (j < 0) continue
                    layout.setProperty(j, "col", plan.rects[k].col)
                    layout.setProperty(j, "row", plan.rects[k].row)
                }
                changed = true
            }
            groupIds = []
            groupStart = ({})
            groupPreview = []
            groupOffset = { x: 0, y: 0 }
            tempPos = ({})
            if (changed) saveLayout()
            dragId = ""
            return
        }
        if (i >= 0 && preview.ok) {
            // 押しのけたウィジェットを確定する
            for (const other in tempPos) {
                const j = indexOfId(other)
                if (j < 0) continue
                layout.setProperty(j, "col", tempPos[other].col)
                layout.setProperty(j, "row", tempPos[other].row)
                changed = true
            }
            if (layout.get(i).col !== preview.col || layout.get(i).row !== preview.row) {
                layout.setProperty(i, "col", preview.col)
                layout.setProperty(i, "row", preview.row)
                changed = true
            }
        }
        tempPos = ({})
        if (changed) saveLayout()
        dragId = ""
    }

    // ---------------------------------------------------------------- 追加・削除・サイズ・設定
    // 空いている場所へ追加する。既定サイズで置けなければ、最低サイズまで小さくして置ける場所を探す
    // (置けるサイズのうち面積が最も大きいもの。同じ面積なら既定サイズの縦横比に近いもの)。
    // 最低サイズでも置けなければ通知して false
    function findFreeSpot(w, h) {
        for (let r = 0; r <= rows - h; ++r) {
            for (let c = 0; c <= cols - w; ++c) {
                if (!overlaps(c, r, w, h, "")) return { col: c, row: r }
            }
        }
        return null
    }
    function addWidget(type, initialConfig) {
        const def = WidgetRegistry.find(type)
        if (!def) return false
        const dw = Math.min(cols, def.defaultSize.w), dh = Math.min(rows, def.defaultSize.h)
        const mw = Math.min(dw, def.minSize.w), mh = Math.min(dh, def.minSize.h)
        let best = null
        for (let w = dw; w >= mw; --w) {
            for (let h = dh; h >= mh; --h) {
                const area = w * h
                const shapeDiff = (dw - w) + (dh - h)
                if (best && (area < best.area || (area === best.area && shapeDiff >= best.shapeDiff))) continue
                const spot = findFreeSpot(w, h)
                if (spot) best = { col: spot.col, row: spot.row, w: w, h: h, area: area, shapeDiff: shapeDiff }
            }
        }
        if (!best) {
            notifications.show("空きがありません", "ウィジェットを削除するか、サイズを小さくしてください", 2, "widgets")
            return false
        }
        // 通知・警告の設定は、同じ種類のほかのウィジェットと共通(リンク)なので、今の値を引き継ぐ
        const linked = WidgetRegistry.withLinked(type, Object.assign({}, def.defaultConfig, initialConfig || {}))
        const cfg = Object.assign({}, initialConfig || {})
        for (const k of WidgetRegistry.linkedKeys(type)) if (linked[k] !== undefined) cfg[k] = linked[k]
        layout.append({ wid: newId(), wtype: type, col: best.col, row: best.row, w: best.w, h: best.h,
                        config: cfg })
        saveLayout()
        return true
    }

    function removeWidget(wid) {
        const i = indexOfId(wid)
        if (i >= 0) rep.itemAt(i).playRemove()
    }
    function finishRemove(wid) {
        const i = indexOfId(wid)
        if (isSelected(wid)) selection = selection.filter(w => w !== wid)
        if (i >= 0) {
            layout.remove(i)
            unpark()          // 空きができたので、よけておいたウィジェットを戻せるか試す
            saveLayout()
        }
    }

    // 使えないマスが変わったとき: 重なったウィジェットを近くの空きへ動かす(空きが無ければよけておく)
    function applyBlocked() {
        let changed = false
        for (let i = layout.count - 1; i >= 0; --i) {
            const it = layout.get(i)
            if (!overlapsBlocked(it.col, it.row, it.w, it.h)) continue
            const s = resolveSpot(it.wid, it.col, it.row, it.w, it.h)
            if (s.ok) {
                layout.setProperty(i, "col", s.col)
                layout.setProperty(i, "row", s.row)
            } else {
                parked = parked.concat([{ id: it.wid, type: it.wtype, col: it.col, row: it.row, w: it.w, h: it.h, config: it.config }])
                layout.remove(i)
            }
            changed = true
        }
        if (unpark()) changed = true
        if (changed) saveLayout()
    }
    // よけておいたウィジェットを、元の位置の近くの空きへ戻す。戻せたら true
    function unpark() {
        if (parked.length === 0) return false
        const rest = []
        let any = false
        for (const e of parked) {
            const s = resolveSpot("", e.col, e.row, e.w, e.h)
            if (s.ok) {
                layout.append({ wid: e.id || newId(), wtype: e.type, col: s.col, row: s.row, w: e.w, h: e.h, config: e.config || {} })
                any = true
            } else {
                rest.push(e)
            }
        }
        parked = rest
        return any
    }

    // ---- つまみ(右下)でのサイズ変更。WidgetHost から呼ばれる ----
    // 左上のマスは動かさず、右下の角だけを動かす。指の位置はマスに丸めて、そのつど大きさに反映する
    // (保存は離したとき)。最小・最大サイズの範囲で、隣のウィジェットや使えないマスに重なる分は広げない
    function resizeBegin(wid) {
        const i = indexOfId(wid)
        if (i < 0) return
        const it = layout.get(i)
        resizeStart = { w: it.w, h: it.h }
        resizeId = wid
    }
    // cornerX / cornerY: ウィジェットの右下の角にしたい位置(この配置エリアの中の px)
    function resizeUpdate(wid, cornerX, cornerY) {
        if (resizeId !== wid) return
        const i = indexOfId(wid)
        if (i < 0) return
        const it = layout.get(i)
        const def = WidgetRegistry.find(it.wtype)
        if (!def) return
        const minW = def.minSize.w, minH = def.minSize.h
        const maxW = Math.max(minW, Math.min(def.maxSize.w, cols - it.col))
        const maxH = Math.max(minH, Math.min(def.maxSize.h, rows - it.row))
        // 角の位置(右端 = cellW * (col + w) - pad)から、ほしいマス数を出す
        const wantW = Math.max(minW, Math.min(maxW, Math.round((cornerX + pad) / cellW) - it.col))
        const wantH = Math.max(minH, Math.min(maxH, Math.round((cornerY + pad) / cellH) - it.row))
        // ほしい大きさに一番近い、重ならない大きさを選ぶ
        let bestW = it.w, bestH = it.h, bestD = 1e9
        for (let ww = minW; ww <= maxW; ++ww) {
            for (let hh = minH; hh <= maxH; ++hh) {
                const d = (ww - wantW) * (ww - wantW) + (hh - wantH) * (hh - wantH)
                if (d >= bestD) continue
                if (overlaps(it.col, it.row, ww, hh, wid)) continue
                bestD = d; bestW = ww; bestH = hh
            }
        }
        if (bestW !== it.w) layout.setProperty(i, "w", bestW)
        if (bestH !== it.h) layout.setProperty(i, "h", bestH)
    }
    function resizeEnd(wid) {
        if (resizeId !== wid) return
        resizeId = ""
        const i = indexOfId(wid)
        if (i < 0) return
        const it = layout.get(i)
        if (it.w !== resizeStart.w || it.h !== resizeStart.h) saveLayout()
    }

    // サイズ(マス数)を変える。隣のウィジェットと重なる・範囲外になる場合は、できる範囲(重ならない最大)に収める。変えられたら true
    function resizeWidget(wid, w, h) {
        const i = indexOfId(wid)
        if (i < 0) return false
        const it = layout.get(i)
        const def = WidgetRegistry.find(it.wtype)
        w = Math.max(def.minSize.w, Math.min(def.maxSize.w, Math.min(cols, w)))
        h = Math.max(def.minSize.h, Math.min(def.maxSize.h, Math.min(rows, h)))
        const c = Math.min(it.col, cols - w)
        const r = Math.min(it.row, rows - h)
        if (overlaps(c, r, w, h, wid)) {
            notifications.show("サイズを変えられません", "隣のウィジェットと重なります。先に移動してください", 0, "widgets")
            return false
        }
        layout.setProperty(i, "w", w)
        layout.setProperty(i, "h", h)
        layout.setProperty(i, "col", c)
        layout.setProperty(i, "row", r)
        saveLayout()
        return true
    }

    function sizeOf(wid) {
        const i = indexOfId(wid)
        return i < 0 ? { w: 1, h: 1 } : { w: layout.get(i).w, h: layout.get(i).h }
    }
    // 置いてあるウィジェットの一覧(よけておいたものは除く)。{ wid, wtype, col, row }
    function widgetEntries() {
        const list = []
        for (let i = 0; i < layout.count; ++i) {
            const it = layout.get(i)
            list.push({ wid: it.wid, wtype: it.wtype, col: it.col, row: it.row })
        }
        return list
    }
    function typeOf(wid) {
        const i = indexOfId(wid)
        return i < 0 ? "" : layout.get(i).wtype
    }

    // 定義の既定値に保存値を重ねた、現在の設定
    function configOf(wid) {
        const i = indexOfId(wid)
        if (i < 0) return {}
        const it = layout.get(i)
        const def = WidgetRegistry.find(it.wtype)
        return Object.assign({}, def ? def.defaultConfig : {}, it.config)
    }

    function setConfigValue(wid, key, value) {
        const i = indexOfId(wid)
        if (i < 0) return
        const cur = Object.assign({}, layout.get(i).config)
        cur[key] = value
        layout.setProperty(i, "config", cur)
        saveLayout()
        WidgetRegistry.publishLinked(layout.get(i).wtype, configOf(wid), key, value, wid, true)
    }

    // 設定値を画面にだけ反映する(保存しない)。文字入力中のリアルタイム表示用。確定時は setConfigValue で保存する
    function previewConfigValue(wid, key, value) {
        const i = indexOfId(wid)
        if (i < 0) return
        const cur = Object.assign({}, layout.get(i).config)
        if (cur[key] === value) return
        cur[key] = value
        layout.setProperty(i, "config", cur)
        revision++
        WidgetRegistry.publishLinked(layout.get(i).wtype, configOf(wid), key, value, wid, false)
    }

    // ---------------------------------------------------------------- 設定のリンク
    // 通知・警告の設定は同じ種類のウィジェットで共通。どこか(ほかのページ・Android Auto 画面も)で変わったら、
    // このエリアの同じ種類のウィジェット(よけておいたものも)に同じ値を入れる
    Connections {
        target: WidgetRegistry
        function onLinkedChanged(group, key, value, sourceWid, save) {
            let changed = false
            for (let i = 0; i < layout.count; ++i) {
                const it = layout.get(i)
                if (it.wid === sourceWid || WidgetRegistry.linkGroupFor(it.wtype, widgetArea.configOf(it.wid), key) !== group) continue
                const cur = Object.assign({}, it.config)
                if (cur[key] === value) continue
                cur[key] = value
                layout.setProperty(i, "config", cur)
                changed = true
            }
            if (save) {
                let parkedChanged = false
                const list = widgetArea.parked.map(p => {
                    const def = WidgetRegistry.find(p.type)
                    const cfg = Object.assign({}, def ? def.defaultConfig : {}, p.config)
                    if (p.id === sourceWid || WidgetRegistry.linkGroupFor(p.type, cfg, key) !== group
                            || (p.config && p.config[key] === value)) return p
                    parkedChanged = true
                    return Object.assign({}, p, { config: Object.assign({}, p.config, { [key]: value }) })
                })
                if (parkedChanged) widgetArea.parked = list
                if (changed || parkedChanged) widgetArea.saveLayout()
            } else if (changed) {
                widgetArea.revision++
            }
        }
    }

    // 全ページを初期配置に戻す(WidgetPages がページを作り直す)
    function resetLayout() {
        if (pages) pages.resetAll()
    }

    // ---------------------------------------------------------------- 保存・復元
    function saveLayout() {
        const list = []
        for (let i = 0; i < layout.count; ++i) {
            const it = layout.get(i)
            list.push({ id: it.wid, type: it.wtype, col: it.col, row: it.row, w: it.w, h: it.h, config: it.config })
        }
        // よけておいたウィジェットも保存に残す(空きができたら戻す)
        if (pages) pages.savePage(pageIndex, list.concat(parked))
        revision++
    }

    function loadLayout() {
        layout.clear()
        parked = []
        // このページの保存内容(null なら初期配置)
        let list = pages ? pages.pageWidgets(pageIndex) : null
        if (!Array.isArray(list)) list = WidgetRegistry.defaultLayout
        const used = {}
        for (let i = 0; i < list.length; ++i) {
            let e = list[i]
            const def = WidgetRegistry.find(e.type)
            if (!def) continue   // 今のバージョンに無い種類は読み飛ばす(配置は壊さない)
            const w = Math.max(def.minSize.w, Math.min(def.maxSize.w, Math.min(cols, e.w || def.defaultSize.w)))
            const h = Math.max(def.minSize.h, Math.min(def.maxSize.h, Math.min(rows, e.h || def.defaultSize.h)))
            const c = Math.max(0, Math.min(cols - w, e.col || 0))
            const r = Math.max(0, Math.min(rows - h, e.row || 0))
            const wid = (e.id && !used[e.id]) ? e.id : newId()
            used[wid] = true
            // 以前の既定の警告メッセージ(「ブースト圧〜」)は、今の呼び方(ターボ圧)に直す。自分で書いたものはそのまま
            if (e.config && e.config.warnMessage === "ブースト圧が高すぎます")
                e = Object.assign({}, e, { config: Object.assign({}, e.config, { warnMessage: "ターボ圧が高すぎます" }) })
            // リンクしている設定(通知・警告)の今の値を覚えておく(あとで足すウィジェットが引き継ぐ)
            if (e.config) {
                const full = Object.assign({}, def.defaultConfig, e.config)
                for (const k of WidgetRegistry.linkedKeys(e.type)) {
                    if (e.config[k] !== undefined)
                        WidgetRegistry.rememberLinked(WidgetRegistry.linkGroupFor(e.type, full, k), k, e.config[k], false)
                }
            }
            if (overlaps(c, r, w, h, "")) {
                // 重なっていたら(使えないマスが広がった・保存内容が壊れているなど)、近くの空きへ。無ければよけておく
                const s = resolveSpot("", c, r, w, h)
                if (s.ok) layout.append({ wid: wid, wtype: e.type, col: s.col, row: s.row, w: w, h: h, config: e.config || {} })
                else parked = parked.concat([{ id: wid, type: e.type, col: c, row: r, w: w, h: h, config: e.config || {} }])
                continue
            }
            layout.append({ wid: wid, wtype: e.type, col: c, row: r, w: w, h: h, config: e.config || {} })
        }
    }

    Component.onCompleted: {
        loadLayout()
        loaded = true
        readyTimer.start()
    }

    // ---------------------------------------------------------------- 配置エリアの表示(移動中だけ)
    Item {
        id: gridLayer
        anchors.fill: parent
        z: 0
        opacity: widgetArea.dragging || widgetArea.editMode ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius + 6
            // 半透明にして、背景の模様・画像と、奥に置いた飾りの画像が透けて見えるようにする
            readonly property color base: Theme.mix(Theme.background, Theme.accent, 0.04)
            color: Qt.rgba(base.r, base.g, base.b, 0.55)
            border.width: 1
            border.color: Theme.panelBorder
        }

        Repeater {
            model: widgetArea.cols * widgetArea.rows
            Rectangle {
                required property int index
                x: (index % widgetArea.cols) * widgetArea.cellW + widgetArea.pad
                y: Math.floor(index / widgetArea.cols) * widgetArea.cellH + widgetArea.pad
                width: widgetArea.cellW - 2 * widgetArea.pad
                height: widgetArea.cellH - 2 * widgetArea.pad
                radius: Theme.radius
                color: "transparent"
                border.width: 1
                border.color: Theme.mix(Theme.panelBorder, Theme.accent, 0.25)
            }
        }

        // 使えないマス(Android Auto の映像の場所)
        Rectangle {
            visible: !!widgetArea.blocked
            x: widgetArea.blocked ? widgetArea.blocked.col * widgetArea.cellW + widgetArea.pad : 0
            y: widgetArea.blocked ? widgetArea.blocked.row * widgetArea.cellH + widgetArea.pad : 0
            width: widgetArea.blocked ? widgetArea.blocked.w * widgetArea.cellW - 2 * widgetArea.pad : 0
            height: widgetArea.blocked ? widgetArea.blocked.h * widgetArea.cellH - 2 * widgetArea.pad : 0
            radius: Theme.radius + 6
            color: Theme.mix(Theme.background, Theme.panelBorder, 0.5)
            border.color: Theme.panelBorder
        }

        // まとめて動かしているとき: 離したときに入るマス(選択中のものすべて。置けないときは赤)
        Repeater {
            model: widgetArea.groupPreview
            Rectangle {
                required property var modelData
                x: modelData.col * widgetArea.cellW + widgetArea.pad
                y: modelData.row * widgetArea.cellH + widgetArea.pad
                width: modelData.w * widgetArea.cellW - 2 * widgetArea.pad
                height: modelData.h * widgetArea.cellH - 2 * widgetArea.pad
                radius: Theme.radius + 6
                color: modelData.ok ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                    : Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.14)
                border.width: 2
                border.color: modelData.ok ? Theme.accent : Theme.error
            }
        }

        // 離したときに入るマス(スナップ先)
        Rectangle {
            visible: !widgetArea.groupDragging && widgetArea.dragging
            x: widgetArea.preview.col * widgetArea.cellW + widgetArea.pad
            y: widgetArea.preview.row * widgetArea.cellH + widgetArea.pad
            width: widgetArea.preview.w * widgetArea.cellW - 2 * widgetArea.pad
            height: widgetArea.preview.h * widgetArea.cellH - 2 * widgetArea.pad
            radius: Theme.radius + 6
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
            border.width: 2
            border.color: widgetArea.preview.ok ? Theme.accent : Theme.error
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
    }

    // ---------------------------------------------------------------- ウィジェット
    Repeater {
        id: rep
        model: layout
        WidgetHost { area: widgetArea }
    }

    // ---------------------------------------------------------------- 1 つも無いとき
    Column {
        anchors.centerIn: parent
        spacing: 14 * Theme.uiScale
        opacity: layout.count === 0 && widgetArea.showEmptyState ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 240 } }

        MaterialIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "widgets"
            size: 56 * Theme.uiScale
            color: Theme.textSecondary
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            font.family: Theme.fontFamily
            text: "ウィジェットがありません"
            color: Theme.textSecondary
            font.pixelSize: 24 * Theme.uiScale
        }
        ActionButton {
            anchors.horizontalCenter: parent.horizontalCenter
            selected: true
            text: "ウィジェットを追加"
            onClicked: widgetArea.pickerRequested()
        }
    }
}
