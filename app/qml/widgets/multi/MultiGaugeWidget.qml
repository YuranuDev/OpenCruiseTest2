// マルチ表示: いくつかの計測値を、名前・数値・細いバーで縦に並べる(監視用。水温・油温・電圧など)。
// config.items: 計測値の id の並び(最大 6)/ config.showBars: バーを出すか。
// 値・範囲・単位はその計測値のメーターの既定(WidgetRegistry.metricDefaults)。警告・注意は AlertRules のルールの状態で色を変える
// (警告 = 赤で点滅 / 注意 = 黄)。データが来ていない項目は「--」。
import QtQuick
import OpenCruise

WidgetBase {
    id: root

    readonly property var items: (Array.isArray(config.items) ? config.items : []).filter(m => !!WidgetRegistry.gaugeSpecs[m]).slice(0, 6)
    readonly property bool showBars: config.showBars !== false
    readonly property real m: root.innerMargin
    readonly property bool anyAlert: { AlertRules.stateRevision; return items.some(k => AlertRules.levelFor(k) === 2) }

    property real blink: 1
    SequentialAnimation on blink {
        running: root.anyAlert && root.onScreen && !root.lifting
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 380; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 380; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.blink = 1
    }

    Text {
        visible: root.items.length === 0
        anchors.centerIn: parent
        width: parent.width - 2 * root.m
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        font.family: Theme.fontFamily
        font.pixelSize: root.bodyFontSize
        color: Theme.textSecondary
        text: "設定で表示する値を選んでください"
    }

    Column {
        id: rows
        anchors { fill: parent; margins: root.m }
        readonly property real rowH: height / Math.max(1, root.items.length)
        Repeater {
            model: root.items
            Item {
                id: row
                required property string modelData
                required property int index
                width: rows.width
                height: rows.rowH
                readonly property var spec: WidgetRegistry.gaugeSpecs[modelData]
                readonly property var def: WidgetRegistry.metricDefaults(modelData)
                readonly property var u: def.unit || spec.units[0]
                readonly property bool has: WidgetRegistry.metricHas(modelData)
                readonly property real base: has ? WidgetRegistry.metricValue(modelData) : NaN
                readonly property real shown: Number(base) * u.scale + (u.offset || 0)
                readonly property real lo: Number(def.min) * u.scale + (u.offset || 0)
                readonly property real hi: Number(def.max) * u.scale + (u.offset || 0)
                readonly property int level: { AlertRules.stateRevision; return AlertRules.levelFor(modelData) }
                readonly property color stateColor: level === 2 ? Theme.error : level === 1 ? Theme.warn : Theme.accent
                readonly property real barH: root.showBars ? Math.max(4, Math.min(12, height * 0.14)) : 0
                // 名前と数値の行
                Item {
                    id: line
                    anchors { left: parent.left; right: parent.right; top: parent.top; bottom: bar.top; bottomMargin: Math.max(2, row.height * 0.05) }
                    MaterialIcon {
                        id: icon
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        name: row.level > 0 ? "warning" : row.spec.icon
                        size: Math.min(line.height * 0.7, root.bodyFontSize * 1.2)
                        color: row.level > 0 ? row.stateColor : Theme.textSecondary
                        opacity: row.level === 2 ? root.blink : 1
                    }
                    Text {
                        anchors { left: icon.right; leftMargin: 6; verticalCenter: parent.verticalCenter; right: value.left; rightMargin: 6 }
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.max(11, Math.min(line.height * 0.45, root.bodyFontSize))
                        color: row.level > 0 ? row.stateColor : Theme.textSecondary
                        elide: Text.ElideRight
                        text: row.spec.title
                    }
                    NumberText {
                        id: value
                        anchors { right: unit.left; rightMargin: 4; top: parent.top; bottom: parent.bottom }
                        width: Math.min(parent.width * 0.5, implicitWidth)
                        horizontalAlignment: Text.AlignRight
                        bold: true
                        italic: Theme.numberItalic
                        pixelSize: Math.max(12, Math.round(line.height * 0.82))
                        fit: true
                        color: row.level > 0 ? row.stateColor : Theme.textPrimary
                        text: row.has ? Number(row.shown).toFixed(row.u.dec) : "--"
                    }
                    Text {
                        id: unit
                        anchors { right: parent.right; baseline: value.baseline }
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.max(10, Math.round(line.height * 0.3))
                        color: Theme.textSecondary
                        text: row.u.label
                    }
                }
                Rectangle {
                    id: bar
                    visible: root.showBars
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: Math.max(2, row.height * 0.1) }
                    height: row.barH
                    radius: height / 2
                    color: Theme.mix(Theme.panel, Theme.textSecondary, 0.22)
                    Rectangle {
                        height: parent.height
                        radius: height / 2
                        color: row.stateColor
                        width: row.has ? Math.max(height, parent.width * Math.max(0, Math.min(1, (row.shown - row.lo) / Math.max(1e-9, row.hi - row.lo)))) : 0
                        Behavior on width { enabled: root.onScreen; NumberAnimation { duration: 180 } }
                    }
                }
            }
        }
    }
}
