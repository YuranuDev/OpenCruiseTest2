// 表示する計測値の並びを編集する部品(マルチ表示・警告灯パネルの設定)。
//   ・今の並び: 1 行ずつ(アイコン・名前・データの有無)。右の ↑ ↓ で並べ替え、✕ で外す
//   ・「追加」: 分類(走行・エンジン・燃料…)ごとのチップから、タップで足す(データが来ていないものは薄く「データなし」)
// items は計測値の id の配列。extras は計測値以外の項目([{ id, title, icon }]。警告灯パネルの「故障コード」など)
// bulk: true なら「データが来ている値を全部入れる」「全部入れる」「全部外す」のボタンも出す
import QtQuick
import OpenCruise

Column {
    id: root
    property var items: []
    property int maxCount: 6
    property var extras: []
    property bool bulk: false
    signal changedItems(var list)

    readonly property real unit: Theme.uiScale
    property bool adding: false
    spacing: 10 * unit

    function titleOf(id) {
        for (const e of extras) if (e.id === id) return e.title
        const s = WidgetRegistry.gaugeSpecs[id]
        return s ? s.title : id
    }
    function iconOf(id) {
        for (const e of extras) if (e.id === id) return e.icon
        const s = WidgetRegistry.gaugeSpecs[id]
        return s ? s.icon : "help"
    }
    function hasData(id) {
        for (const e of extras) if (e.id === id) return true
        return WidgetRegistry.metricHas(id)
    }
    function move(i, d) {
        const l = items.slice(), j = i + d
        if (j < 0 || j >= l.length) return
        const t = l[i]; l[i] = l[j]; l[j] = t
        changedItems(l)
    }
    function remove(i) { const l = items.slice(); l.splice(i, 1); changedItems(l) }
    // 候補の全部(分類の順)。onlyData なら今データが来ているものだけ
    function allIds(onlyData) {
        const out = []
        for (const b of choices) for (const id of b.ids) if (!onlyData || hasData(id)) out.push(id)
        return out.slice(0, maxCount)
    }
    function add(id) {
        if (items.indexOf(id) >= 0 || items.length >= maxCount) return
        changedItems(items.concat([id]))
    }
    // 追加の候補: 分類ごと(計測値の分類の順)。最後に extras
    readonly property var choices: {
        const specs = WidgetRegistry.gaugeSpecs
        const out = []
        for (const g of VehicleSignals.numberGroups) {
            const ids = Object.keys(specs).filter(k => VehicleSignals.groupOf(k) === g.id)
            if (ids.length > 0) out.push({ title: g.title, ids: ids })
        }
        const other = Object.keys(specs).filter(k => !out.some(b => b.ids.indexOf(k) >= 0))
        if (other.length > 0) out.push({ title: "そのほか", ids: other })
        if (extras.length > 0) out.push({ title: "車両の状態", ids: extras.map(e => e.id) })
        return out
    }

    // 小さな丸いボタン
    component RoundButton: Rectangle {
        id: rb
        property string icon: ""
        property bool enabledButton: true
        signal clicked()
        width: 56 * root.unit
        height: width
        radius: width / 2
        color: rbMouse.pressed ? Theme.accentFill : "transparent"
        border.width: 1
        border.color: Theme.panelBorder
        opacity: enabledButton ? 1 : 0.3
        MaterialIcon { anchors.centerIn: parent; name: rb.icon; size: 30 * root.unit; color: Theme.textPrimary }
        MouseArea { id: rbMouse; anchors.fill: parent; enabled: rb.enabledButton; onClicked: rb.clicked() }
    }

    Repeater {
        model: root.items.length
        Rectangle {
            id: row
            required property int index
            readonly property string mid: root.items[index] || ""
            width: root.width
            height: 72 * root.unit
            radius: Theme.radius
            color: Theme.mix(Theme.background, Theme.panel, 0.5)
            border.width: 1
            border.color: Theme.panelBorder
            MaterialIcon {
                id: rowIcon
                anchors { left: parent.left; leftMargin: 16 * root.unit; verticalCenter: parent.verticalCenter }
                name: root.iconOf(row.mid)
                size: 34 * root.unit
                color: Theme.accent
            }
            Text {
                anchors { left: rowIcon.right; leftMargin: 12 * root.unit; right: rowButtons.left; rightMargin: 8 * root.unit
                          verticalCenter: parent.verticalCenter }
                font.family: Theme.fontFamily
                font.pixelSize: 23 * root.unit
                color: Theme.textPrimary
                elide: Text.ElideRight
                text: (row.index + 1) + ". " + root.titleOf(row.mid) + (root.hasData(row.mid) ? "" : "(データなし)")
            }
            Row {
                id: rowButtons
                anchors { right: parent.right; rightMargin: 8 * root.unit; verticalCenter: parent.verticalCenter }
                spacing: 6 * root.unit
                RoundButton { icon: "arrow_upward"; enabledButton: row.index > 0; onClicked: root.move(row.index, -1) }
                RoundButton { icon: "arrow_downward"; enabledButton: row.index < root.items.length - 1; onClicked: root.move(row.index, 1) }
                RoundButton { icon: "close"; onClicked: root.remove(row.index) }
            }
        }
    }
    Text {
        visible: root.items.length === 0
        font.family: Theme.fontFamily
        font.pixelSize: 20 * root.unit
        color: Theme.textSecondary
        text: "まだ何もありません。下の「追加」から選んでください"
    }

    Flow {
        width: root.width
        spacing: 12 * root.unit
        ActionButton {
            text: root.adding ? "追加を閉じる" : (root.items.length >= root.maxCount ? "いっぱいです(最大 " + root.maxCount + " 個)" : "追加")
            selected: root.adding
            onClicked: root.adding = !root.adding
        }
        ActionButton {
            visible: root.bulk
            text: "データが来ている値を全部入れる"
            onClicked: root.changedItems(root.allIds(true))
        }
        ActionButton {
            visible: root.bulk
            text: "全部入れる"
            onClicked: root.changedItems(root.allIds(false))
        }
        ActionButton {
            visible: root.bulk && root.items.length > 0
            text: "全部外す"
            onClicked: root.changedItems([])
        }
    }

    // 追加の候補(分類ごとのチップ)
    Column {
        visible: root.adding
        width: root.width
        spacing: 8 * root.unit
        Repeater {
            model: root.choices
            Column {
                required property var modelData
                width: root.width
                spacing: 6 * root.unit
                Text {
                    font.family: Theme.fontFamily
                    font.pixelSize: 19 * root.unit
                    font.bold: true
                    color: Theme.textSecondary
                    text: modelData.title
                }
                Flow {
                    width: parent.width
                    spacing: 8 * root.unit
                    Repeater {
                        model: modelData.ids
                        Rectangle {
                            id: chip
                            required property string modelData
                            readonly property bool added: root.items.indexOf(modelData) >= 0
                            readonly property bool full: root.items.length >= root.maxCount
                            readonly property bool dataOk: root.hasData(modelData)
                            width: chipRow.implicitWidth + 28 * root.unit
                            height: 54 * root.unit
                            radius: height / 2
                            color: added ? Theme.accentFill : Theme.mix(Theme.background, Theme.accentFill, chipMouse.pressed ? 0.45 : 0)
                            border.width: 1
                            border.color: added ? Theme.accent : Theme.panelBorder
                            opacity: added || full ? 0.55 : (dataOk ? 1 : 0.6)
                            Row {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 6 * root.unit
                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: chip.added ? "check" : root.iconOf(chip.modelData)
                                    size: 24 * root.unit
                                    color: chip.added ? Theme.textOnAccent : Theme.accent
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 20 * root.unit
                                    color: chip.added ? Theme.textOnAccent : Theme.textPrimary
                                    text: root.titleOf(chip.modelData) + (chip.dataOk ? "" : "(データなし)")
                                }
                            }
                            MouseArea {
                                id: chipMouse
                                anchors.fill: parent
                                enabled: !chip.added && !chip.full
                                onClicked: root.add(chip.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
