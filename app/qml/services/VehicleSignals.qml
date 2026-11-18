// 車両のデータを 1 つにまとめる所(シングルトン)。画面・メーター・グラフ・警告は、データ元(ノード)を気にせずここから読む。
//
// データ元はノードごとに分かれている(system-architecture.md):
//   VIN  車両信号ノード     車速・回転数・ギア・アクセル・ブレーキ・電圧・燃料・バック   (QML では can = VehicleDataManager)
//   SEN  外付けセンサーノード  ブースト・水温・油温・油圧                                  (同上)
//   DIAG 診断通信ノード     エンジン ECU(K-Line / KWP2000)の計測値・故障コード          (QML では ecu = EcuData)
// 今は VIN / SEN ともダミーで、可否も 1 つ(can.dataAvailable)。ノードとの通信が入ったら、ここの nodeHas() をノードごとにする。
//
// 両方から取れる項目(車速・回転数・水温・電圧・アクセル)は 1 つの項目にまとめ、どちらの値を使うかを選ぶ:
//   auto(既定。VIN/SEN 優先、無ければ ECU)/ ecuFirst(ECU 優先)/ node(VIN/SEN だけ)/ ecu(ECU だけ)
//   選び方は ecu.sourcePrefs に保存(設定 > 車両 > 車両データ)。ecu.sourceOverride を選ぶと、項目ごとの設定に関係なく
//   すべての項目をその選び方にする(項目ごとの設定は消さずに残す。上書きをやめると元に戻る)。
// 分類(走行・エンジン・燃料・吸気…)は ecu.groups をそのまま使い、VIN / SEN の項目も同じ分類に入れる。
pragma Singleton
import QtQuick
import OpenCruise

QtObject {
    id: root

    // ---- 車両信号(VIN / SEN)の計測値。node: 出どころのノード、group: 分類、ecu: 同じ値の ECU の項目 ----
    readonly property var nodeMetrics: ({
        speed:       { node: "VIN", group: "drive",    ecu: "ecuSpeed" },
        gear:        { node: "VIN", group: "drive" },
        brake:       { node: "VIN", group: "drive" },
        rpm:         { node: "VIN", group: "engine",   ecu: "ecuRpm" },
        coolant:     { node: "SEN", group: "engine",   ecu: "ecuCoolant" },
        oilTemp:     { node: "SEN", group: "engine" },
        oilPressure: { node: "SEN", group: "engine" },
        fuel:        { node: "VIN", group: "fuel" },
        boost:       { node: "SEN", group: "air" },
        throttle:    { node: "VIN", group: "throttle", ecu: "accelPos" },
        voltage:     { node: "VIN", group: "electric", ecu: "ecuBattery" }
    })
    /// 両方から取れる項目(設定で選び方を変えられる)
    readonly property var mergedIds: Object.keys(nodeMetrics).filter(k => !!nodeMetrics[k].ecu)
    /// ECU の項目のうち、上の項目にまとめたもの(一覧などでは出さない)
    readonly property var mergedEcuIds: mergedIds.map(k => nodeMetrics[k].ecu)

    // ---- ノード ----
    readonly property var nodes: [
        { id: "VIN",  title: "車両信号",            icon: "directions_car", description: "車速・回転数・ギア・アクセル・ブレーキ・電圧・燃料・バック" },
        { id: "SEN",  title: "外付けセンサー",      icon: "sensors",        description: "ブースト・水温・油温・油圧" },
        { id: "DIAG", title: "エンジン ECU(K-Line)", icon: "memory",         description: "ECU の計測値・スイッチ・故障コード・ECU 情報" }
    ]
    function nodeTitle(id) { for (const n of nodes) if (n.id === id) return n.title; return id }
    /// ノードの状態: { available, mock, text }
    function nodeStatus(id) {
        if (id === "DIAG") {
            const t = ({ none: "データ元なし", mock: "ダミーデータ", connecting: "接続中", connected: "通信中", lost: "途切れた" })[ecu.linkState]
            return { available: ecu.available, mock: ecu.linkState === "mock", text: t || ecu.linkState }
        }
        // VIN / SEN: 今はダミーだけ(1 つのデータ元)
        return { available: can.dataAvailable, mock: can.dataAvailable, text: can.dataAvailable ? "ダミーデータ" : "データ元なし" }
    }

    // ---- 分類(switch はスイッチ・作動状態の分類なので、数値の分類からは外す) ----
    readonly property var groups: ecu.groups
    readonly property var numberGroups: ecu.groups.filter(g => g.id !== "switch")
    function groupTitle(id) { for (const g of ecu.groups) if (g.id === id) return g.title; return id }
    function groupIcon(id) { for (const g of ecu.groups) if (g.id === id) return g.icon; return "" }
    /// 計測値の分類(VIN / SEN の項目、ECU の項目どちらも)
    function groupOf(metric) {
        if (nodeMetrics[metric]) return nodeMetrics[metric].group
        const g = paramGroups[metric]
        return g ? g : ""
    }
    /// ECU の項目の分類(id → 分類。ecu.params は変わらないので 1 回だけ作る)
    readonly property var paramGroups: {
        const out = {}
        for (const p of ecu.params) out[p.id] = p.group
        return out
    }

    // ---- 選び方 ----
    readonly property var sourceModes: [
        { id: "auto",     title: "VIN/SEN 優先" },
        { id: "ecuFirst", title: "ECU 優先" },
        { id: "node",     title: "VIN/SEN だけ" },
        { id: "ecu",      title: "ECU だけ" }
    ]
    /// 実際に使う選び方(上書きの設定があれば、項目ごとの設定に関係なくそちら)
    // 設定は変わったときだけ JavaScript に変換して持っておく(ecu.sourcePrefs を読むたびに変換すると、値を読むたびに重くなるため)
    readonly property var prefsMap: ecu.sourcePrefs
    readonly property string overrideMode: ecu.sourceOverride
    function pref(metric) {
        if (overrideMode !== "") return overrideMode
        const p = prefsMap[metric]; return p ? p : "auto"
    }
    /// 項目ごとの設定(上書きを考えない)
    function itemPref(metric) { const p = prefsMap[metric]; return p ? p : "auto" }
    readonly property bool overridden: overrideMode !== ""
    function setOverride(mode) { ecu.sourceOverride = mode }
    function setPref(metric, mode) { ecu.setSourcePref(metric, mode) }

    // ---- 値 ----
    /// VIN / SEN の値(束縛が値の変化に付いてくるよう、プロパティを直接読む)
    function nodeRaw(metric) {
        switch (metric) {
        case "speed": return can.speedKmh
        case "gear": return can.gear
        case "brake": return can.brakePercent
        case "rpm": return can.rpm
        case "coolant": return can.coolantTempC
        case "oilTemp": return can.oilTempC
        case "oilPressure": return can.oilPressureBar
        case "fuel": return can.fuelPercent
        case "boost": return can.boostBar
        case "throttle": return can.throttlePercent
        case "voltage": return can.batteryVolts
        }
        return NaN
    }
    function nodeHas(metric) { return !!nodeMetrics[metric] && can.dataAvailable }
    function ecuHas(metric) {
        const m = nodeMetrics[metric]
        ecu.revision
        return !!m && !!m.ecu && ecu.has(m.ecu)
    }
    /// 今使っているデータ元: "node" / "ecu" / ""(どちらも無い)
    function sourceOf(metric) {
        const n = nodeHas(metric), e = ecuHas(metric)
        switch (pref(metric)) {
        case "ecuFirst": return e ? "ecu" : (n ? "node" : "")
        case "node": return n ? "node" : ""
        case "ecu": return e ? "ecu" : ""
        }
        return n ? "node" : (e ? "ecu" : "")
    }
    /// 今使っているノードの名前("VIN" / "SEN" / "DIAG"。無ければ "")
    function nodeOf(metric) {
        const s = sourceOf(metric)
        return s === "node" ? nodeMetrics[metric].node : s === "ecu" ? "DIAG" : ""
    }
    function has(metric) { return sourceOf(metric) !== "" }
    /// 値(基本単位)。無ければ NaN
    function value(metric) {
        const s = sourceOf(metric)
        if (s === "node") return nodeRaw(metric)
        if (s === "ecu") { ecu.revision; return ecu.value(nodeMetrics[metric].ecu) }
        return NaN
    }
    /// 今の値がダミーか
    function isMock(metric) {
        const s = sourceOf(metric)
        return s === "node" ? nodeStatus("VIN").mock : s === "ecu" ? ecu.linkState === "mock" : false
    }
    /// VIN / SEN の項目の今の値をまとめて(グラフの履歴用。来ている項目だけ)
    function values() {
        const out = {}
        for (const k of Object.keys(nodeMetrics)) if (has(k)) out[k] = value(k)
        return out
    }
    /// 何かのデータが来ているか
    readonly property bool anyAvailable: can.dataAvailable || ecu.available
}
