// ギア表示: 今のギアを大きく出す。
// ギアの取り方(config.source):
//   auto     車両信号(VIN)にギアがあればそれ(CVT の無段階は「D」)。無ければ速度と回転数から推定
//   estimate いつも推定
// 推定: 1000 rpm あたりの速度(km/h)を、ギアごとに覚えた値(config.ratios。設定の「学習」で記録)と比べ、
//   いちばん近いもの(差が 12% 以内)にする。止まっている(5 km/h 未満)は「N」、どれにも近くない(クラッチを切っている
//   など)は「-」、まだ 1 つも記録していなければ「?」。
// シフトの目安(config.hint): 回転数が upRpm 以上で一番上のギアでなければ ▲、downRpm 以下で 1 速でなければ ▼
import QtQuick
import OpenCruise

WidgetBase {
    id: root

    readonly property real m: root.innerMargin
    readonly property int gears: [4, 5, 6].indexOf(Number(config.gears)) >= 0 ? Number(config.gears) : 5
    readonly property var ratios: Array.isArray(config.ratios) ? config.ratios : []
    readonly property bool hasSpeed: VehicleSignals.has("speed")
    readonly property bool hasRpm: VehicleSignals.has("rpm")
    readonly property real speed: hasSpeed ? VehicleSignals.value("speed") : NaN
    readonly property real rpm: hasRpm ? VehicleSignals.value("rpm") : NaN
    readonly property bool useSignal: config.source !== "estimate" && VehicleSignals.has("gear")
    readonly property real kmhPer1000: hasSpeed && hasRpm && rpm > 300 ? speed / (rpm / 1000) : NaN

    // 推定したギア(1〜)。0 = 止まっている / -1 = どれにも近くない / -2 = 記録なし / -3 = データなし
    readonly property int estimated: {
        if (!hasSpeed || !hasRpm) return -3
        if (speed < 5) return 0
        if (!ratios.some(r => Number(r) > 0)) return -2
        let best = -1, err = 1e9
        for (let i = 0; i < Math.min(gears, ratios.length); ++i) {
            const r = Number(ratios[i])
            if (!(r > 0)) continue
            const e = Math.abs(kmhPer1000 - r) / r
            if (e < err) { err = e; best = i + 1 }
        }
        return err <= 0.12 ? best : -1
    }
    readonly property int signalGear: useSignal ? Math.round(VehicleSignals.value("gear")) : 0
    readonly property int gearNo: useSignal ? signalGear : estimated
    readonly property string gearText: useSignal ? (signalGear >= 1 ? String(signalGear) : "D")
                                       : estimated >= 1 ? String(estimated) : estimated === 0 ? "N"
                                       : estimated === -1 ? "-" : estimated === -2 ? "?" : "--"
    readonly property bool numeric: gearNo >= 1
    readonly property int hint: {
        if (config.hint === false || !numeric || !hasRpm) return 0
        if (rpm >= (Number(config.upRpm) || 3500) && gearNo < gears) return 1
        if (rpm <= (Number(config.downRpm) || 1500) && gearNo > 1 && speed >= 5) return -1
        return 0
    }
    readonly property bool wide: width > height * 1.25

    // ギアの箱
    Rectangle {
        id: box
        x: root.m
        y: root.m
        width: root.wide ? Math.min(height * 0.85, root.width * 0.5) : root.width - 2 * root.m
        height: root.height - 2 * root.m
        radius: Theme.radius + 2
        color: Theme.mix(Theme.panel, Theme.background, 0.6)
        border.width: 1
        border.color: Theme.panelBorder
        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: root.wide ? 0 : -parent.height * 0.06
            font.family: Theme.numberFontFamily
            font.bold: true
            font.italic: Theme.numberItalic
            font.pixelSize: Math.round(Math.min(parent.height * 0.78, parent.width * (root.gearText.length > 1 ? 0.5 : 0.8)))
            color: root.numeric || root.gearText === "D" || root.gearText === "N" ? Theme.textPrimary : Theme.textSecondary
            text: root.gearText
        }
        // 目安の矢印(箱の上)
        MaterialIcon {
            visible: root.hint !== 0
            anchors { horizontalCenter: parent.horizontalCenter; top: root.hint > 0 ? parent.top : undefined
                      bottom: root.hint < 0 ? parent.bottom : undefined; margins: parent.height * 0.02 }
            name: root.hint > 0 ? "arrow_drop_up" : "arrow_drop_down"
            size: Math.round(parent.height * 0.24)
            color: root.hint > 0 ? Theme.ok : Theme.warn
        }
        // 縦長(狭い)ときの小さな説明
        Text {
            visible: !root.wide
            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: parent.height * 0.05 }
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(10, Math.round(root.titleFontSize * 0.8))
            color: Theme.textSecondary
            text: root.useSignal ? "ギア" : "推定ギア"
        }
    }

    // 横長のとき: 右に説明・速度・回転数・目安
    Column {
        visible: root.wide
        anchors { left: box.right; leftMargin: root.m * 1.2; right: parent.right; rightMargin: root.m; verticalCenter: parent.verticalCenter }
        spacing: Math.max(2, root.height * 0.02)
        readonly property real px: Math.max(12, Math.min(root.height * 0.16, root.bodyFontSize * 1.4))
        Text {
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(11, parent.px * 0.6)
            color: Theme.textSecondary
            text: root.useSignal ? "ギア(車両信号)" : "推定ギア"
        }
        Text {
            font.family: Theme.numberFontFamily
            font.bold: true
            font.pixelSize: parent.px
            color: Theme.textPrimary
            text: (root.hasSpeed ? Math.round(root.speed) : "--") + " km/h"
        }
        Text {
            font.family: Theme.numberFontFamily
            font.bold: true
            font.pixelSize: parent.px
            color: Theme.textPrimary
            text: (root.hasRpm ? Math.round(root.rpm) : "--") + " rpm"
        }
        Text {
            width: parent.width
            font.family: Theme.fontFamily
            font.bold: true
            font.pixelSize: Math.max(11, parent.px * 0.62)
            elide: Text.ElideRight
            color: root.hint > 0 ? Theme.ok : root.hint < 0 ? Theme.warn : Theme.textSecondary
            text: root.hint > 0 ? "▲ シフトアップ" : root.hint < 0 ? "▼ シフトダウン"
                  : root.gearText === "?" ? "設定でギアを学習してください" : ""
        }
    }
}
