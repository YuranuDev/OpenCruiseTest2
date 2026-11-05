// 車両データ(メーターと同じ計測値)の直近の履歴(シングルトン)。グラフウィジェットが読む。
// Main.qml が sampleMs ごとに push() で全計測値(基本単位)を入れる。ウィジェットとは別に持つので、
// グラフを足した直後やページを切り替えても、それまでの履歴をそのまま描ける。最大 maxSamples 件(約 10 分)。
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
