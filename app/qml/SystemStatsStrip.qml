// システム情報(CPU / GPU / メモリ)を 3 枚のカードで横に並べた帯。フルスクリーン時のメニューで使う。
// 周波数・温度が取れない項目は、その部分だけ省く(全部取れなければ「周波数・温度は取得できません」)。
import QtQuick

Item {
    id: root
    property real unit: Theme.uiScale
    readonly property real cardHeight: 84 * unit
    readonly property real spacing: Theme.margin
    height: cardHeight

    // 「3.4 GHz · 62 ℃」のような補足文字列を作る。取れない要素は省く
    function freqText(mhz) {
        if (mhz < 0) return ""
        return mhz >= 1000 ? (mhz / 1000).toFixed(2) + " GHz" : mhz + " MHz"
    }
    function tempText(c) { return c < 0 ? "" : c + " ℃" }
    function joinParts(a, b) {
        var parts = []
        if (a !== "") parts.push(a)
        if (b !== "") parts.push(b)
        return parts.length > 0 ? parts.join(" · ") : "周波数・温度は取得不可"
    }
    function gb(mb) { return (mb / 1024).toFixed(1) }

    readonly property real cardWidth: (width - 2 * spacing) / 3

    StatCard {
        x: 0; width: root.cardWidth; height: root.height; unit: root.unit
        title: "CPU"
        percent: systemStats.cpuPercent
        detail: root.joinParts(root.freqText(systemStats.cpuFreqMHz), root.tempText(systemStats.cpuTempC))
    }
    StatCard {
        x: root.cardWidth + root.spacing; width: root.cardWidth; height: root.height; unit: root.unit
        title: "GPU"
        percent: systemStats.gpuPercent
        detail: systemStats.gpuSource === ""
                ? "GPU を検出できません"
                : root.joinParts(root.freqText(systemStats.gpuFreqMHz), root.tempText(systemStats.gpuTempC))
    }
    StatCard {
        x: 2 * (root.cardWidth + root.spacing); width: root.cardWidth; height: root.height; unit: root.unit
        title: "メモリ"
        percent: systemStats.memPercent
        detail: systemStats.memTotalMB > 0
                ? root.gb(systemStats.memUsedMB) + " / " + root.gb(systemStats.memTotalMB) + " GB"
                : ""
    }
}
