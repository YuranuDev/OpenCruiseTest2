// 警告・注意のルール(シングルトン)。メーターとは別に、条件を見て警告・注意を出す(メーターが無くても動く)。
// ルールは 設定 > 警告・注意 で作る・変える。保存は widgetStore.alertRulesJson(JSON)。
//
// ルール 1 件:
//   { id, enabled, level: "warn"(警告) | "caution"(注意),
//     conditions: [{ source, op, value, value2 }],   すべて満たしたとき(かつ)
//     holdSec      条件がこの秒数続いたら出す(0 ならすぐ)
//     armedOnly    エンジンが始動してから(can.warningsArmed)だけ見る
//     message      見出し(通知の見出し・メーターの帯のメッセージ)
//     banner       メーターの帯にメッセージを出すか(false なら色・アイコンだけ)
//     beep         警告: 消音するまで警告音を鳴らす / 注意: なったときに注意音を 1 回
//     popup        "off" / "once"(8 秒) / "live"(出し続ける)。popupDetail: 通知に条件の値も入れる
//     showOnGauge  同じ計測値のメーターに、範囲(目盛りの帯)と状態(色・点滅・帯のメッセージ)を出す
//     unit         画面での単位(数値の条件。計測値の単位の id。保存する値は基本単位のまま) }
// 条件(source)に使える値:
//   数値: メーターの計測値(WidgetRegistry.gaugeSpecs。エンジン ECU(K-Line)の計測値を含む。範囲はメーターの目盛りに関係なく、
//         計測値の限界まで使える)と、
//         extraNumbers(ギア・スマホの電池)。op: "above"(以上)/ "below"(以下)/ "outside"(範囲外)/ "inside"(範囲内)
//   状態: boolSources(エンジン・バック・Android Auto・スマホ・車両データ・故障コード(現在 / 過去)・チェックランプ)。op: "on" / "off"
//   車両異常: 故障コードの「現在」(警告)と「過去」(注意)の既定のルールを入れておく(defaultDtcRules。版 2 で足した)。
//         通知の本文はコードと内容(ecu.dtcSummary)
//   ドア・ロックなど外部機器の信号は、データ元ができたら boolSources に 1 行足すだけで使える。
// 数値の条件は、いったん満たしたら、範囲の 2% 戻るまで解除しない(境目でちらつかないように)。
//
// 出し方(音・通知)は WarningAlarm の仕組みをそのまま使う:
//   警告音: WarningAlarm.raise("alert:" + id, …)。消音(acknowledge)は同じ通知の組の分もまとめて
//   通知: 組(数値の条件があれば最初の計測値ごと = "alert:<計測値>"、無ければルールごと)に 1 つ。
//         組の中でいちばん高い段階のルールを出し、警告 ⇄ 注意の移り変わりも 1 つの通知の中で書き換える
// メーターはここから範囲(zonesFor)と状態(levelFor / activeRuleFor / beepingFor)を読むだけ。
pragma Singleton
import QtQuick
import OpenCruise

QtObject {
    id: alerts

    // ================================================================ 条件に使える値
    // メーター以外の数値(単位などはメーターの計測値と同じ形)
    readonly property var extraNumbers: ({
        gear: { title: "ギア", icon: "mdi:car-shift-pattern",
                units: [{ id: "gear", label: "速", scale: 1, dec: 0, step: 1, stepDec: 0 }],
                limitMin: 0, limitMax: 8 },
        phoneBattery: { title: "スマホの電池", icon: "battery_alert",
                units: [{ id: "pct", label: "%", scale: 1, dec: 0, step: 5, stepDec: 0 }],
                limitMin: 0, limitMax: 100 }
    })
    // オン/オフの状態
    readonly property var boolSources: ({
        engine:   { title: "エンジン始動", icon: "mdi:engine", onText: "始動している", offText: "止まっている" },
        reverse:  { title: "バック(リバース)", icon: "mdi:car-back", onText: "バックに入っている", offText: "バックではない" },
        aa:       { title: "Android Auto", icon: "android", onText: "接続している", offText: "接続していない" },
        phone:    { title: "スマホ", icon: "smartphone", onText: "接続している", offText: "接続していない" },
        vehicle:  { title: "車両データ", icon: "directions_car", onText: "受信している", offText: "受信していない" },
        // エンジン ECU(K-Line)の車両異常。故障コードの「現在」は現在起きている・起きかけているもの、「過去」は記録だけのもの
        dtcCurrent: { title: "故障コード(現在)", icon: "mdi:car-wrench", onText: "ある", offText: "ない" },
        dtcPast:    { title: "故障コード(過去)", icon: "history", onText: "ある", offText: "ない" },
        mil:        { title: "チェックランプ", icon: "mdi:engine-outline", onText: "点灯している", offText: "消えている" }
    })
    // 条件の選択肢に出す順: 計測値を分類(走行・エンジン・燃料…。VehicleSignals)ごとに(各分類の中は車両信号 → ECU)
    //   → そのほかの数値(スマホの電池) → 車両異常 → 状態。データ元(VIN / SEN / ECU)では分けない
    readonly property var sourceIds: {
        const specs = WidgetRegistry.gaugeSpecs
        const numbers = Object.keys(specs).concat(Object.keys(extraNumbers))
        const out = []
        for (const g of VehicleSignals.numberGroups) {
            const inGroup = numbers.filter(k => VehicleSignals.groupOf(k) === g.id)
            for (const k of inGroup.filter(k => !(specs[k] && specs[k].ecu))) out.push(k)
            for (const k of inGroup.filter(k => specs[k] && specs[k].ecu)) out.push(k)
        }
        for (const k of numbers) if (out.indexOf(k) < 0) out.push(k)   // 分類の無い数値(スマホの電池など)
        const diag = ["dtcCurrent", "dtcPast", "mil"]
        return out.concat(diag).concat(Object.keys(boolSources).filter(k => diag.indexOf(k) < 0))
    }
    // 選択肢・設定画面の見出しの分類: "g:<分類>"(車両の計測値)/ "number"(そのほかの数値)/ "diag"(車両異常)/ "state"
    function sourceGroup(source) {
        if (numberSpec(source)) {
            const g = VehicleSignals.groupOf(source)
            return g !== "" ? "g:" + g : "number"
        }
        if (source === "dtcCurrent" || source === "dtcPast" || source === "mil") return "diag"
        return "state"
    }
    // 分類の一覧(sourceIds の順)と、短い名前(選択肢用)
    readonly property var sourceGroups: {
        const out = []
        for (const id of sourceIds) { const g = sourceGroup(id); if (out.indexOf(g) < 0) out.push(g) }
        return out
    }
    function sourceGroupShort(group) {
        if (group === "number") return "そのほかの数値"
        if (group === "diag") return "車両異常"
        if (group === "state") return "状態"
        return VehicleSignals.groupTitle(group.slice(2))
    }
    function sourceGroupTitle(group) {
        if (group === "number") return "そのほかの数値(スマホの電池)"
        if (group === "diag") return "車両異常(故障コード・チェックランプ)"
        if (group === "state") return "状態(エンジン・バック・Android Auto・スマホ・車両データ)"
        return VehicleSignals.groupTitle(group.slice(2))
    }

    function isNumber(source) { return numberSpec(source) !== null }
    function numberSpec(source) { return WidgetRegistry.gaugeSpecs[source] || extraNumbers[source] || null }
    function sourceTitle(source) {
        const n = numberSpec(source)
        if (n) return n.title
        const b = boolSources[source]
        return b ? b.title : source
    }
    function sourceIcon(source) {
        const n = numberSpec(source)
        if (n) return n.icon
        const b = boolSources[source]
        return b ? b.icon : "warning"
    }
    function unitOf(rule, source) {
        const spec = numberSpec(source)
        if (!spec) return null
        for (const u of spec.units) if (u.id === rule.unit) return u
        return spec.units[0]
    }
    function toShown(base, u) { return Number(base) * u.scale + (u.offset || 0) }
    function toBase(shown, u) { return (Number(shown) - (u.offset || 0)) / u.scale }
    function fmt(v, dec) { return Number(v).toFixed(Math.max(0, dec)) }

    // 今の値(数値の条件はデータが無ければ undefined。そのときは条件を満たさない)
    function readSource(source) {
        switch (source) {
        // 車両信号(VIN / SEN)の計測値(ECU と両方にある項目は、設定の選び方で選んだ方)
        case "rpm": case "speed": case "coolant": case "fuel": case "oilTemp": case "oilPressure":
        case "voltage": case "throttle": case "brake": case "boost": case "gear":
            return VehicleSignals.has(source) ? VehicleSignals.value(source) : undefined
        case "phoneBattery": return phoneStatus.connected && phoneStatus.batteryLevel >= 0 ? phoneStatus.batteryLevel : undefined
        case "engine": return can.engineRunning
        case "reverse": return reverseCamera.reverse
        case "aa": return androidAuto.stateKey === "connected" || androidAuto.stateKey === "streaming"
        case "phone": return phoneStatus.connected
        case "vehicle": return can.dataAvailable
        case "dtcCurrent": return ecu.available ? ecu.currentDtcCount > 0 : undefined
        case "dtcPast": return ecu.available ? ecu.pastDtcCount > 0 : undefined
        case "mil": return ecu.available ? ecu.milOn : undefined
        }
        // エンジン ECU の計測値(このECUで出ない項目・データ元なしなら undefined)
        const spec = WidgetRegistry.gaugeSpecs[source]
        if (spec && spec.ecu) return ecu.has(spec.ecu) ? ecu.value(spec.ecu) : undefined
        return undefined
    }

    // ================================================================ ルール
    property var rules: []
    /// ルールが変わるたびに増える(束縛が読み直すため)
    property int revision: 0
    /// 状態(警告・注意中か)が変わるたびに増える
    property int stateRevision: 0
    property bool loaded: false

    readonly property var opsNumber: [{ id: "above", label: "以上" }, { id: "below", label: "以下" },
                                      { id: "outside", label: "範囲外" }, { id: "inside", label: "範囲内" }]
    readonly property var opsBool: [{ id: "on", label: "オン" }, { id: "off", label: "オフ" }]

    function find(id) {
        for (const r of rules) if (r.id === id) return r
        return null
    }
    function newId() { return "r" + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36) }

    // その計測値のメーターの既定の設定(警告値・注意値など。無ければ null)
    function gaugeDefaults(metric) {
        for (const t of WidgetRegistry.types)
            if (t.component === WidgetRegistry.gaugeComp && t.defaultConfig && t.defaultConfig.metric === metric) return t.defaultConfig
        return null
    }
    // 新しいルールの既定値(source: 最初の条件の値。level: "warn" / "caution")
    function makeRule(source, level) {
        const src = source || "coolant"
        const lv = level === "caution" ? "caution" : "warn"
        const spec = numberSpec(src)
        const cond = { source: src, op: spec ? (spec.warnBelow ? "below" : "above") : "on", value: 0, value2: 0 }
        if (spec) {
            // メーターの既定の警告値・注意値があればそれ。無ければ範囲の 8 割(以下で出るものは 2 割)
            const def = gaugeDefaults(src)
            const span = spec.limitMax - spec.limitMin
            const fallback = spec.warnBelow ? spec.limitMin + span * 0.2 : spec.limitMin + span * 0.8
            const v = def ? (lv === "caution" ? def.caution : def.warn) : undefined
            cond.value = Number((v !== undefined ? Number(v) : fallback).toFixed(3))
            cond.value2 = Number(Math.min(spec.limitMax, cond.value + span * 0.1).toFixed(3))
        }
        return { id: newId(), enabled: true, level: lv, conditions: [cond], holdSec: 0, armedOnly: true,
                 message: (spec && lv === "warn" && spec.warnMessage) ? spec.warnMessage
                          : sourceTitle(src) + (lv === "warn" ? "の警告" : "に注意"),
                 banner: true, beep: lv === "warn", popup: "once", popupDetail: true, showOnGauge: true,
                 unit: spec ? spec.units[0].id : "" }
    }
    // 古い保存データ・足りない項目を補う
    function normalize(r) {
        const out = Object.assign({ enabled: true, level: "warn", conditions: [], holdSec: 0, armedOnly: true,
                                    message: "", banner: true, beep: false, popup: "once", popupDetail: true,
                                    showOnGauge: true, unit: "" }, r)
        if (!out.id) out.id = newId()
        out.level = out.level === "caution" ? "caution" : "warn"
        out.conditions = (out.conditions || []).filter(c => c && (numberSpec(c.source) || boolSources[c.source]))
                                               .map(c => Object.assign({ op: "above", value: 0, value2: 0 }, c))
        if (out.conditions.length === 0) out.conditions = makeRule("coolant", out.level).conditions
        if (["off", "once", "live"].indexOf(out.popup) < 0) out.popup = "once"
        out.holdSec = Math.max(0, Math.min(600, Number(out.holdSec) || 0))
        return out
    }

    function load() {
        let list = null
        try {
            const o = widgetStore.alertRulesJson !== "" ? JSON.parse(widgetStore.alertRulesJson) : null
            if (o && Array.isArray(o.rules)) list = o.rules
        } catch (e) {
            console.warn("[ALERTS] could not read the saved alert rules; rebuilding them from the gauge settings")
        }
        let version = 0
        try { version = widgetStore.alertRulesJson !== "" ? (JSON.parse(widgetStore.alertRulesJson).version || 1) : 0 } catch (e) { }
        rules = (list !== null ? list : migrate()).map(normalize)
        // 版 2: 車両異常(故障コード)のルールを足す(前の版で保存したルールにも、1 回だけ足す)
        if (version < 2) rules = rules.concat(defaultDtcRules().filter(d => !rules.some(r => r.id === d.id)).map(normalize))
        loaded = true
        if (list === null || version < 2) save()
        ++revision
        resetStates()
    }
    function save() {
        widgetStore.alertRulesJson = JSON.stringify({ version: 2, rules: rules })
    }
    function changed() {
        rules = rules.slice()
        save()
        ++revision
        evaluate()
    }

    // 車両異常(エンジン ECU の故障コード)の既定のルール: 現在起きているものは警告(警告音・通知)、過去の記録は注意(通知 1 回)
    function defaultDtcRules() {
        return [
            { id: "dtc-current", enabled: true, level: "warn", conditions: [{ source: "dtcCurrent", op: "on", value: 0, value2: 0 }],
              holdSec: 0, armedOnly: false, message: "車両に異常があります", banner: true, beep: true, popup: "live",
              popupDetail: true, showOnGauge: false, unit: "" },
            { id: "dtc-past", enabled: true, level: "caution", conditions: [{ source: "dtcPast", op: "on", value: 0, value2: 0 }],
              holdSec: 0, armedOnly: false, message: "過去の車両異常の記録があります", banner: true, beep: false, popup: "once",
              popupDetail: true, showOnGauge: false, unit: "" }
        ]
    }

    // ---- 変更(設定画面・メーターの設定から) ----
    function addRule(source, level) {
        const r = makeRule(source, level)
        rules = rules.concat([r])
        changed()
        return r.id
    }
    function removeRule(id) {
        const st = states[id]
        if (st && st.active) deactivate(find(id), st)
        delete states[id]
        rules = rules.filter(r => r.id !== id)
        changed()
        refreshGroups()
    }
    // 変えたルールは新しいオブジェクトに置き換える(同じオブジェクトのままだと、画面の束縛が変化に気づかないため)
    function replaceRule(id, make) {
        const i = rules.findIndex(r => r.id === id)
        if (i < 0) return null
        const r = make(Object.assign({}, rules[i], { conditions: rules[i].conditions.map(c => Object.assign({}, c)) }))
        const list = rules.slice()
        list[i] = r
        rules = list
        return r
    }
    function updateRule(id, patch) {
        const r = replaceRule(id, (x) => Object.assign(x, patch))
        if (!r) return
        // 段階・音を変えたら、今の警告音の登録をやり直す
        const st = states[id]
        if (st && st.active && (patch.level !== undefined || patch.beep !== undefined || patch.message !== undefined)) {
            WarningAlarm.clear(alarmKey(r))
            if (r.level === "warn" && r.beep) WarningAlarm.raise(alarmKey(r), r.message, groupOf(r))
        }
        changed()
        refreshGroups()
    }
    function updateCondition(id, index, patch) {
        const old = find(id)
        if (!old || !old.conditions[index]) return
        replaceRule(id, (r) => {
            const c = Object.assign(r.conditions[index], patch)
            // 種類が変わったら、比べ方と値を、その種類の既定にする
            if (patch.source !== undefined && patch.source !== old.conditions[index].source)
                Object.assign(c, makeRule(patch.source, r.level).conditions[0])
            if (index === 0 && patch.source !== undefined) {
                const spec = numberSpec(c.source)
                r.unit = spec ? spec.units[0].id : ""
            }
            return r
        })
        changed()
    }
    function addCondition(id) {
        if (!replaceRule(id, (r) => { r.conditions.push({ source: "engine", op: "on", value: 0, value2: 0 }); return r })) return
        changed()
    }
    function removeCondition(id, index) {
        const old = find(id)
        if (!old || old.conditions.length <= 1) return
        replaceRule(id, (r) => { r.conditions = r.conditions.filter((c, i) => i !== index); return r })
        changed()
    }
    function moveRule(id, dir) {
        const i = rules.findIndex(r => r.id === id)
        const j = i + dir
        if (i < 0 || j < 0 || j >= rules.length) return
        const list = rules.slice()
        const t = list[i]; list[i] = list[j]; list[j] = t
        rules = list
        changed()
    }

    // 同じセンサー(最初の条件)のルールの中で、前後のものと入れ替える(設定画面はセンサーごとに並べるため)
    function moveRuleWithin(id, dir) {
        const i = rules.findIndex(r => r.id === id)
        if (i < 0) return
        const src = rules[i].conditions[0].source
        let j = i + dir
        while (j >= 0 && j < rules.length && rules[j].conditions[0].source !== src) j += dir
        if (j < 0 || j >= rules.length) return
        const list = rules.slice()
        const t = list[i]; list[i] = list[j]; list[j] = t
        rules = list
        changed()
    }

    // ---- 文字にする(設定画面の一覧・通知) ----
    function conditionText(rule, c) {
        const spec = numberSpec(c.source)
        if (!spec) {
            const b = boolSources[c.source]
            return b ? b.title + "が" + (c.op === "off" ? b.offText : b.onText) : c.source
        }
        const u = unitOf(rule, c.source)
        const v = fmt(toShown(c.value, u), u.stepDec) + " " + u.label
        const v2 = fmt(toShown(c.value2, u), u.stepDec) + " " + u.label
        switch (c.op) {
        case "below": return spec.title + " " + v + " 以下"
        case "outside": return spec.title + "が " + v + " 〜 " + v2 + " の外"
        case "inside": return spec.title + "が " + v + " 〜 " + v2 + " の間"
        }
        return spec.title + " " + v + " 以上"
    }
    function summary(rule, withoutHold) {
        let s = rule.conditions.map(c => conditionText(rule, c)).join(" かつ ")
        if (rule.holdSec > 0 && !withoutHold) s += "(" + rule.holdSec + " 秒続いたら)"
        return s
    }

    // ================================================================ 判定
    /// id → { active, pendingSince, since }
    property var states: ({})
    function resetStates() {
        for (const id in states) {
            const st = states[id]
            if (st.active) deactivate(find(id), st)
        }
        states = ({})
        ++stateRevision
    }
    function hysteresisOf(source) {
        const spec = numberSpec(source)
        return spec ? (spec.limitMax - spec.limitMin) * 0.02 : 0
    }
    function conditionMet(c, active) {
        const v = readSource(c.source)
        if (v === undefined || v === null) return false
        if (typeof v === "boolean") return c.op === "off" ? !v : v
        if (boolSources[c.source]) return c.op === "off" ? !v : !!v
        const h = active ? hysteresisOf(c.source) : 0
        const lo = Math.min(c.value, c.value2), hi = Math.max(c.value, c.value2)
        switch (c.op) {
        case "below": return v <= c.value + h
        case "outside": return v <= lo + h || v >= hi - h
        case "inside": return v >= lo - h && v <= hi + h
        }
        return v >= c.value - h
    }
    readonly property bool armed: can.warningsArmed && released
    readonly property bool released: typeof boot === "undefined" || boot.released

    function evaluate() {
        if (!loaded) return
        const now = Date.now()
        let any = false
        for (const r of rules) {
            let st = states[r.id]
            if (!st) { st = { active: false, pendingSince: 0, since: 0 }; states[r.id] = st }
            const allowed = r.enabled && released && (!r.armedOnly || can.warningsArmed)
            const met = allowed && r.conditions.length > 0 && r.conditions.every(c => conditionMet(c, st.active))
            if (met && !st.active) {
                if (st.pendingSince === 0) st.pendingSince = now
                if (now - st.pendingSince >= r.holdSec * 1000) { activate(r, st, now); any = true }
            } else if (!met) {
                st.pendingSince = 0
                if (st.active) { deactivate(r, st); any = true }
            }
        }
        if (any) ++stateRevision
        refreshGroups()
    }
    function alarmKey(r) { return "alert:" + r.id }
    function activate(r, st, now) {
        st.active = true
        st.since = now
        console.log("[ALERTS] " + r.level + " on: " + r.id + " (" + r.conditions.map(c => c.source + " " + c.op).join(" and ") + ")")
        if (r.beep) {
            if (r.level === "warn") WarningAlarm.raise(alarmKey(r), r.message, groupOf(r))
            else WarningAlarm.caution()
        }
    }
    function deactivate(r, st) {
        st.active = false
        st.pendingSince = 0
        if (r) {
            console.log("[ALERTS] " + r.level + " off: " + r.id)
            WarningAlarm.clear(alarmKey(r))
        }
    }
    function isActive(id) { const st = states[id]; return st !== undefined && st.active }

    property Timer ticker: Timer {
        interval: 200
        repeat: true
        running: alerts.loaded
        onTriggered: alerts.evaluate()
    }
    onArmedChanged: evaluate()

    // ================================================================ 通知(組ごとに 1 つ)
    // 組: 数値の条件があれば最初の計測値ごと(同じ計測値の警告と注意は 1 つの通知)。無ければルールごと
    function primaryNumber(r) {
        for (const c of r.conditions) if (isNumber(c.source)) return c
        return null
    }
    function groupOf(r) {
        const c = primaryNumber(r)
        return c ? "alert:" + c.source : "alert:rule:" + r.id
    }
    /// group → { open, min, max, warned, topRule }(警告・注意の間の最大・最小値など)
    property var episodes: ({})
    function refreshGroups() {
        if (!loaded) return
        // 組ごとに、今いちばん高い段階のルール(警告 > 注意。同じなら先のもの)
        const tops = {}
        for (const r of rules) {
            if (!isActive(r.id) || r.popup === "off") continue
            const g = groupOf(r)
            const t = tops[g]
            if (!t || (t.level !== "warn" && r.level === "warn")) tops[g] = r
        }
        for (const g in tops) {
            const r = tops[g]
            const c = primaryNumber(r)
            const v = c ? readSource(c.source) : undefined
            let ep = episodes[g]
            if (!ep || !ep.open) { ep = { open: true, min: v, max: v, warned: false }; episodes[g] = ep }
            if (typeof v === "number") {
                if (ep.min === undefined || v < ep.min) ep.min = v
                if (ep.max === undefined || v > ep.max) ep.max = v
            }
            if (r.level === "warn") ep.warned = true
            // 通知の書き換えは 0.5 秒ごと(段階・見出しが変わったときはすぐ)
            const now = Date.now()
            if (ep.topRule === r && now - (ep.reportedAt || 0) < 500) continue
            ep.topRule = r
            ep.reportedAt = now
            WarningAlarm.noticeReport(g, { title: r.message, text: noticeText(r, ep, true), level: r.level === "warn" ? 3 : 2,
                                          warning: true, icon: sourceIcon(r.conditions[0].source), mode: r.popup })
        }
        // 解除された組: その間の最大値(最小値)を出して消える(WarningAlarm が 8 秒出して履歴に残す)
        for (const g in episodes) {
            const ep = episodes[g]
            if (!ep.open || tops[g]) continue
            ep.open = false
            const r = ep.topRule
            if (!r) continue
            // 計測値 1 つだけの条件なら「水温が正常に戻りました」、組み合わせなら「〜 が解除されました」
            const single = r.conditions.length === 1 && isNumber(r.conditions[0].source)
            WarningAlarm.noticeReport(g, { title: single ? sourceTitle(r.conditions[0].source) + "が正常に戻りました"
                                                         : "「" + r.message + "」が解除されました",
                                          text: noticeText(r, ep, false), level: 2, warning: false,
                                          icon: sourceIcon(r.conditions[0].source), mode: "once" })
        }
    }
    // 通知の本文: 今の値(と、その間の最大・最小値)。詳細つきなら条件も
    function noticeText(r, ep, live) {
        // 車両異常(故障コード)は、コードと内容を本文にする(現在のものは赤の警告、過去のものは黄の注意として出る)
        for (const dc of r.conditions) {
            if (dc.op !== "on") continue
            if (dc.source === "dtcCurrent" || dc.source === "mil") return ecu.dtcSummary("current")
            if (dc.source === "dtcPast") return ecu.dtcSummary("past")
        }
        const c = primaryNumber(r)
        const detail = r.popupDetail ? "(" + summary(r, true) + ")" : ""
        if (!c) return live ? detail.replace(/^\(|\)$/g, "") : ""
        const u = unitOf(r, c.source)
        const v = readSource(c.source)
        // その間の行き過ぎ: 以下で出るものは最低値、それ以外は最大値(範囲外は外れた側)
        const lowSide = c.op === "below" || (c.op === "outside" && ep.min !== undefined
                                             && ep.min <= Math.min(c.value, c.value2))
        const peak = lowSide ? ep.min : ep.max
        const peakText = typeof peak === "number" ? (lowSide ? "最低 " : "最大 ") + fmt(toShown(peak, u), u.dec) + " " + u.label : ""
        if (!live) return peakText + detail
        if (typeof v !== "number") return detail
        let line = "現在 " + fmt(toShown(v, u), u.dec) + " " + u.label
        if (peakText !== "" && Math.abs(peak - v) * u.scale >= Math.pow(10, -u.dec)) line += " ・ " + peakText
        return line + detail
    }

    // ================================================================ メーター向け
    // その計測値の条件を持つルール(メーターに出すもの)
    function rulesFor(source) {
        revision
        return rules.filter(r => r.enabled && r.showOnGauge && r.conditions.some(c => c.source === source))
    }
    // 目盛りに描く範囲(基本単位。lo / hi は ±Infinity もある)。警告・注意それぞれ
    function zonesFor(source) {
        const out = []
        for (const r of rulesFor(source)) {
            for (const c of r.conditions) {
                if (c.source !== source) continue
                const lo = Math.min(c.value, c.value2), hi = Math.max(c.value, c.value2)
                switch (c.op) {
                case "below": out.push({ level: r.level, lo: -Infinity, hi: c.value }); break
                case "outside": out.push({ level: r.level, lo: -Infinity, hi: lo }); out.push({ level: r.level, lo: hi, hi: Infinity }); break
                case "inside": out.push({ level: r.level, lo: lo, hi: hi }); break
                default: out.push({ level: r.level, lo: c.value, hi: Infinity })
                }
            }
        }
        return out
    }
    // 今その計測値で出ている、いちばん高い段階のルール(無ければ null)
    function activeRuleFor(source) {
        stateRevision
        let top = null
        for (const r of rulesFor(source)) {
            if (!isActive(r.id)) continue
            if (!top || (top.level !== "warn" && r.level === "warn")) top = r
        }
        return top
    }
    // 2 = 警告 / 1 = 注意 / 0 = なし
    function levelFor(source) {
        const r = activeRuleFor(source)
        return r ? (r.level === "warn" ? 2 : 1) : 0
    }
    // 警告音を出している(出していた)警告。alarming: 警告音つきの警告中 / beeping: まだ消音していない
    function alarmingFor(source) {
        stateRevision
        for (const r of rulesFor(source)) if (isActive(r.id) && r.level === "warn" && r.beep) return true
        return false
    }
    function beepingFor(source) {
        WarningAlarm.revision
        stateRevision
        for (const r of rulesFor(source))
            if (isActive(r.id) && r.level === "warn" && r.beep && WarningAlarm.isSounding(alarmKey(r))) return true
        return false
    }
    function acknowledgeFor(source) {
        for (const r of rulesFor(source))
            if (isActive(r.id) && r.level === "warn" && r.beep) WarningAlarm.acknowledge(alarmKey(r))
    }

    // ================================================================ 以前の設定(メーターごと)からの移行
    // 初めてこの仕組みで起動したとき、メーターの警告・注意の設定(同じ計測値のメーターで共通だった)からルールを作る。
    // 置いてあるメーターの計測値は、その設定(有効・無効もそのまま)。置いていない計測値は、既定の値で無効のルールを作る
    function migrate() {
        const found = {}   // 計測値 → 保存されていたメーターの設定(既定に重ねたもの)
        const scan = (json) => {
            if (!json) return
            let o = null
            try { o = JSON.parse(json) } catch (e) { return }
            // ページの中身が無い(初期配置のまま)ページは、初期配置のメーターを置いたとみなす
            const lists = o && Array.isArray(o.pages)
                          ? o.pages.map(p => Array.isArray(p.widgets) ? p.widgets : WidgetRegistry.defaultLayout)
                          : [o && Array.isArray(o.widgets) ? o.widgets : []]
            for (const list of lists) {
                for (const w of list) {
                    const def = WidgetRegistry.find(w.type)
                    // 見た目違いの入り口(シフトライトなど)は、計測値の既定(警告値)を持たないので読まない
                    if (!def || def.component !== WidgetRegistry.gaugeComp || !def.defaultConfig || def.variant === true) continue
                    const cfg = Object.assign({}, def.defaultConfig, w.config || {})
                    if (!found[cfg.metric]) found[cfg.metric] = cfg
                }
            }
        }
        scan(widgetStore.layoutJson)
        scan(widgetStore.aaLayoutJson)
        const placedNothing = widgetStore.layoutJson === ""   // 初期配置のまま(保存なし)なら、初期配置のメーターを置いたとみなす
        if (placedNothing) {
            for (const item of WidgetRegistry.defaultLayout) {
                const def = WidgetRegistry.find(item.type)
                if (def && def.component === WidgetRegistry.gaugeComp && def.defaultConfig && !found[def.defaultConfig.metric])
                    found[def.defaultConfig.metric] = Object.assign({}, def.defaultConfig)
            }
        }
        const list = []
        for (const t of WidgetRegistry.types) {
            if (t.component !== WidgetRegistry.gaugeComp || !t.defaultConfig) continue
            const metric = t.defaultConfig.metric
            const spec = WidgetRegistry.gaugeSpecs[metric]
            if (!spec || list.some(r => r.conditions[0].source === metric)) continue
            const placed = found[metric] !== undefined
            const cfg = placed ? found[metric] : t.defaultConfig
            const op = spec.warnBelow ? "below" : "above"
            const popupMode = ["once", "live", "off"].indexOf(cfg.warnPopupMode) >= 0 ? cfg.warnPopupMode
                              : (cfg.warnPopup === true ? "once" : "off")
            if (cfg.warn !== undefined) {
                list.push({ id: "w-" + metric, enabled: placed && cfg.warnEnabled === true, level: "warn",
                            conditions: [{ source: metric, op: op, value: Number(cfg.warn), value2: 0 }],
                            holdSec: 0, armedOnly: true, message: cfg.warnMessage || spec.warnMessage || spec.title + "の警告",
                            banner: cfg.showWarnMessage !== false, beep: cfg.warnBeep === true, popup: popupMode,
                            popupDetail: cfg.warnPopupDetail !== false, showOnGauge: true, unit: cfg.unit || spec.units[0].id })
            }
            if (cfg.caution !== undefined) {
                const title = String(cfg.titleText || "").trim() || spec.title
                list.push({ id: "c-" + metric, enabled: placed && cfg.cautionEnabled === true, level: "caution",
                            conditions: [{ source: metric, op: op, value: Number(cfg.caution), value2: 0 }],
                            holdSec: 0, armedOnly: true, message: cfg.cautionMessage || title + "に注意",
                            banner: cfg.showCautionMessage !== false, beep: cfg.cautionBeep !== false,
                            popup: cfg.cautionPopup !== false ? "once" : "off",
                            popupDetail: cfg.warnPopupDetail !== false, showOnGauge: true, unit: cfg.unit || spec.units[0].id })
            }
        }
        console.log("[ALERTS] created " + list.length + " alert rules from the gauge settings")
        return list
    }

    Component.onCompleted: load()
}
