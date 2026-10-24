// ウィジェット配置エリア。初期画面の中央領域の全体を、cols × rows のグリッドとして使う。
//  - 配置と設定(config)は ListModel(layout)に持ち、変更のたびに widgetStore へ JSON で保存する
//  - ドラッグ中(dragging)だけグリッドと移動先の枠をフェード表示し、離すと最寄りの空きマスへスナップする
//  - 衝突は「重ならない最寄りのマス」へ寄せる(空きが無ければ元の位置へ戻す)
// 外部(設定ダイアログ・追加パネル)からは、下の関数群(addWidget / removeWidget / setConfigValue /
// resizeWidget / resetLayout / configOf)と settingsRequested シグナルを使う。
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
    property var preview: ({ col: 0, row: 0, w: 1, h: 1, ok: true })
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
    function overlaps(c, r, w, h, ignore) {
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

    function newId() {
        return "w" + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36)
    }

    // ---------------------------------------------------------------- ドラッグ(WidgetHost から呼ばれる)
    function dragBegin(wid) {
        const i = indexOfId(wid)
        if (i < 0) return
        const it = layout.get(i)
        preview = { col: it.col, row: it.row, w: it.w, h: it.h, ok: true }
        dragId = wid
    }

    function dragUpdate(wid, x, y) {
        const i = indexOfId(wid)
        if (i < 0) return
        const it = layout.get(i)
        const s = resolveSpot(wid, Math.round((x - pad) / cellW), Math.round((y - pad) / cellH), it.w, it.h)
        preview = s.ok ? { col: s.col, row: s.row, w: it.w, h: it.h, ok: true }
                       : { col: it.col, row: it.row, w: it.w, h: it.h, ok: false }
    }

    function dragEnd(wid) {
        const i = indexOfId(wid)
        if (i >= 0 && preview.ok && (layout.get(i).col !== preview.col || layout.get(i).row !== preview.row)) {
            layout.setProperty(i, "col", preview.col)
            layout.setProperty(i, "row", preview.row)
            saveLayout()
        }
        dragId = ""
    }

    // ---------------------------------------------------------------- 追加・削除・サイズ・設定
    // 空いている最初の場所へ追加する。空きが無ければ通知して false
    function addWidget(type) {
        const def = WidgetRegistry.find(type)
        if (!def) return false
        const w = def.defaultSize.w
        const h = def.defaultSize.h
        for (let r = 0; r <= rows - h; ++r) {
            for (let c = 0; c <= cols - w; ++c) {
                if (!overlaps(c, r, w, h, "")) {
                    layout.append({ wid: newId(), wtype: type, col: c, row: r, w: w, h: h, config: {} })
                    saveLayout()
                    return true
                }
            }
        }
        notifications.show("空きがありません", "ウィジェットを削除するか、サイズを小さくしてください", 2, "widgets")
        return false
    }

    function removeWidget(wid) {
        const i = indexOfId(wid)
        if (i >= 0) rep.itemAt(i).playRemove()
    }
    function finishRemove(wid) {
        const i = indexOfId(wid)
        if (i >= 0) {
            layout.remove(i)
            saveLayout()
        }
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
    }

    function resetLayout() {
        widgetStore.layoutJson = ""
        loadLayout()
        revision++
    }

    // ---------------------------------------------------------------- 保存・復元
    function saveLayout() {
        const list = []
        for (let i = 0; i < layout.count; ++i) {
            const it = layout.get(i)
            list.push({ id: it.wid, type: it.wtype, col: it.col, row: it.row, w: it.w, h: it.h, config: it.config })
        }
        widgetStore.layoutJson = JSON.stringify({ version: 1, widgets: list })
        revision++
    }

    function loadLayout() {
        layout.clear()
        let list = null
        try {
            const o = JSON.parse(widgetStore.layoutJson)
            if (o && o.version === 1 && Array.isArray(o.widgets)) list = o.widgets
        } catch (e) { /* 未保存・壊れている場合は初期配置を使う */ }
        if (list === null) list = WidgetRegistry.defaultLayout
        const used = {}
        for (let i = 0; i < list.length; ++i) {
            const e = list[i]
            const def = WidgetRegistry.find(e.type)
            if (!def) continue   // 今のバージョンに無い種類は読み飛ばす(配置は壊さない)
            const w = Math.max(def.minSize.w, Math.min(def.maxSize.w, Math.min(cols, e.w || def.defaultSize.w)))
            const h = Math.max(def.minSize.h, Math.min(def.maxSize.h, Math.min(rows, e.h || def.defaultSize.h)))
            const c = Math.max(0, Math.min(cols - w, e.col || 0))
            const r = Math.max(0, Math.min(rows - h, e.row || 0))
            if (overlaps(c, r, w, h, "")) continue   // 保存内容が重なっていたら後のものを捨てる
            const wid = (e.id && !used[e.id]) ? e.id : newId()
            used[wid] = true
            layout.append({ wid: wid, wtype: e.type, col: c, row: r, w: w, h: h, config: e.config || {} })
        }
    }

    Component.onCompleted: {
        loadLayout()
        readyTimer.start()
    }

    // ---------------------------------------------------------------- 配置エリアの表示(移動中だけ)
    Item {
        id: gridLayer
        anchors.fill: parent
        z: 0
        opacity: widgetArea.dragging ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius + 6
            color: Theme.mix(Theme.background, Theme.accent, 0.04)
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

        // 離したときに入るマス(スナップ先)
        Rectangle {
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
        opacity: layout.count === 0 ? 1 : 0
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
