// 車両データ(メーターと同じ計測値)の直近の履歴(シングルトン)。グラフウィジェットが読む。
// Main.qml が sampleMs ごとに push() で全計測値(基本単位)を入れる。ウィジェットとは別に持つので、
// グラフを足した直後やページを切り替えても、それまでの履歴をそのまま描ける。最大 maxSamples 件(約 10 分)。
// これとは別に、走行全体の履歴(trip。1 秒に 1 件、最大 6 時間)も持つ。メーターの「分布」表示が読む。
// trip は clear() では消さない(データ元が一時的に途切れても、その走行の分布は残す)。アプリを再起動すると消える。
pragma Singleton
import QtQuick

QtObject {
    id: history

    readonly property int sampleMs: 200
    readonly property int maxSamples: 3000
    /// push のたびに増える(グラフが描き直す合図)
    property int revision: 0
    /// metric → { t: [時刻 ms], v: [値(基本単位)] }
    property var buffers: ({})
    /// 走行全体の履歴(tripEvery 回の push に 1 件。metric → { t: [], v: [] })
    readonly property int tripEvery: 5
    readonly property int tripMaxSamples: 21600
    property var trip: ({})
    property int tripCounter: 0
    /// trip に足すたびに増える
    property int tripRevision: 0

    function push(values) {
        const now = Date.now()
        for (const key in values) {
            const v = Number(values[key])
            if (!isFinite(v)) continue
            let b = buffers[key]
            if (b === undefined) { b = { t: [], v: [] }; buffers[key] = b }
            b.t.push(now)
            b.v.push(v)
            if (b.t.length > maxSamples) {
                const drop = b.t.length - maxSamples
                b.t.splice(0, drop)
                b.v.splice(0, drop)
            }
        }
        ++revision
        if (++tripCounter >= tripEvery) {
            tripCounter = 0
            for (const key in values) {
                const v = Number(values[key])
                if (!isFinite(v)) continue
                let b = trip[key]
                if (b === undefined) { b = { t: [], v: [] }; trip[key] = b }
                b.t.push(now)
                b.v.push(v)
                if (b.t.length > tripMaxSamples) { b.t.splice(0, b.t.length - tripMaxSamples); b.v.splice(0, b.v.length - tripMaxSamples) }
            }
            ++tripRevision
        }
    }

    function tripSeries(metric) {
        const b = trip[metric]
        return b === undefined ? { t: [], v: [] } : b
    }

    // 履歴を捨てる(データ源が無くなったとき。古い値をグラフに残さない)
    function clear() {
        buffers = ({})
        ++revision
    }

    function series(metric) {
        const b = buffers[metric]
        return b === undefined ? { t: [], v: [] } : b
    }
}
