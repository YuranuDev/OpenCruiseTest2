// 設定「車両 > 警告・注意」。警告・注意のルール(AlertRules)を作る・変える・消す。
// ルールはメーターとは別に動く(メーターが無くても、音・通知で知らせる)。同じ計測値のメーターには、範囲と状態も出る。
// 混み合わないよう、センサー(条件に使える値。水温・油圧・バックなど)ごとの箱に分ける。箱はタップで開閉し、
// 閉じているときは「ルール n 件(オン m 件)・今出ています」だけを出す。ルールは、そのセンサーの箱の中で足す
// (ルールは最初の条件のセンサーの箱に入る。最初の条件のセンサーを変えると、その箱へ移る)。
// 上から、車両の計測値を分類(走行・エンジン・燃料…。データ元のノードでは分けない)ごとに、そのほかの数値(スマホの電池)、
// 車両異常(故障コード・チェックランプ)、状態(エンジン・バック・Android Auto など)。
// 1 件ごとのカード: 見出し(段階・メッセージ・今出ているか・オン/オフ)と条件のまとめ。タップで開いて細かく変える。
// 一覧の Repeater は件数だけを model にする(値を変えるたびに作り直さない。数値の長押しの連続変化が途切れないように)。
import QtQuick
import OpenCruise

SettingsPage {
    id: page
    readonly property real unit: Theme.uiScale
    // 開いているルールの id / 開いているセンサーの箱
    property string openId: ""
    property string openSensor: ""
    // ルールを足して、その箱とカードを開く
    function addTo(source, level) {
        openSensor = source
        openId = AlertRules.addRule(source, level)
    }

    SettingsSection {
        title: "警告・注意"
        icon: "warning"

        SettingsNote {
            text: "条件を満たすと、警告(赤)・注意(黄)として知らせます。メーターが無くても動きます。"
                  + "下のセンサーの箱を開いて、そのセンサーのルールを足します。条件はほかのセンサーとも組み合わせられます(すべて満たしたとき)。"
                  + "同じ計測値のメーターには、範囲を目盛りの帯で、状態を色・点滅・メッセージで出します。"
                  + "数値の範囲はメーターの目盛りに関係なく、計測値の限界まで決められます。"
        }
    }

    // ---- センサーごとの箱 ----
    Repeater {
        model: AlertRules.sourceIds
        Column {
            id: sensorBlock
            required property var modelData
            required property int index
            readonly property string source: modelData
            readonly property bool isNumber: AlertRules.isNumber(source)
            // 数値・状態それぞれの最初の箱の上に見出しを出す
            // 分類(基本の数値・ECU の分類・車両異常・状態)ごとに、最初の箱の上に見出しを出す
            readonly property string groupId: AlertRules.sourceGroup(source)
            readonly property bool firstOfKind: index === 0 || AlertRules.sourceGroup(AlertRules.sourceIds[index - 1]) !== groupId
            // この箱に入るルール(最初の条件がこのセンサーのもの)の、AlertRules.rules の中での番号
            readonly property var ruleIdx: { AlertRules.revision
                const out = []
                AlertRules.rules.forEach((r, i) => { if (r.conditions[0].source === source) out.push(i) })
                return out }
            readonly property int enabledCount: { AlertRules.revision
                return ruleIdx.filter(i => AlertRules.rules[i].enabled).length }
            readonly property int activeLevel: { AlertRules.stateRevision; AlertRules.revision
                let lv = 0
                for (const i of ruleIdx) {
                    const r = AlertRules.rules[i]
                    if (AlertRules.isActive(r.id)) lv = Math.max(lv, r.level === "warn" ? 2 : 1)
                }
                return lv }
            readonly property bool expanded: page.openSensor === source
            width: parent ? parent.width : 0
            spacing: 8 * page.unit

            Item {
                visible: sensorBlock.firstOfKind
                width: parent.width
                height: 44 * page.unit
                Text {
                    anchors { left: parent.left; leftMargin: 8 * page.unit; bottom: parent.bottom; bottomMargin: 4 * page.unit }
                    font.family: Theme.fontFamily
                    font.pixelSize: 21 * page.unit
                    font.bold: true
                    color: Theme.textSecondary
                    text: AlertRules.sourceGroupTitle(sensorBlock.groupId)
                }
            }

            Panel {
                id: sensorBox
                width: parent.width
                height: sensorCol.implicitHeight + 2 * pad
                radius: Theme.radius + 6
                readonly property real pad: 18 * page.unit
                border.color: sensorBlock.activeLevel === 2 ? Theme.error : sensorBlock.activeLevel === 1 ? Theme.warn : Theme.panelBorder
                border.width: sensorBlock.activeLevel > 0 ? 2 : 1

                Column {
                    id: sensorCol
                    x: sensorBox.pad
                    y: sensorBox.pad
                    width: sensorBox.width - 2 * sensorBox.pad
                    spacing: 10 * page.unit

                    // 見出し(タップで開閉): アイコン・センサーの名前・ルールの件数・今出ているか
                    Item {
                        width: parent.width
                        height: 56 * page.unit
                        MouseArea {
                            anchors.fill: parent
                            onClicked: page.openSensor = sensorBlock.expanded ? "" : sensorBlock.source
                        }
                        Row {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            spacing: 14 * page.unit
                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: AlertRules.sourceIcon(sensorBlock.source)
                                size: 38 * page.unit
                                color: sensorBlock.activeLevel === 2 ? Theme.error : sensorBlock.activeLevel === 1 ? Theme.warn
                                     : sensorBlock.enabledCount > 0 ? Theme.accent : Theme.textSecondary
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2 * page.unit
                                Text {
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 26 * page.unit
                                    font.bold: true
                                    color: Theme.textPrimary
                                    text: AlertRules.sourceTitle(sensorBlock.source)
                                }
                                Text {
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 18 * page.unit
                                    color: sensorBlock.activeLevel === 2 ? Theme.error : sensorBlock.activeLevel === 1 ? Theme.warn : Theme.textSecondary
                                    text: (sensorBlock.ruleIdx.length === 0 ? "ルールなし"
                                           : "ルール " + sensorBlock.ruleIdx.length + " 件(オン " + sensorBlock.enabledCount + " 件)")
                                          + (sensorBlock.activeLevel === 2 ? "  ・ 警告が出ています" : sensorBlock.activeLevel === 1 ? "  ・ 注意が出ています" : "")
                                }
                            }
                        }
                        MaterialIcon {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            name: sensorBlock.expanded ? "expand_less" : "expand_more"
                            size: 38 * page.unit
                            color: Theme.textSecondary
                        }
                    }

                    // ---- 開いたとき: このセンサーのルールと、足すボタン ----
                    Column {
                        visible: sensorBlock.expanded
                        width: parent.width
                        spacing: 10 * page.unit

    Repeater {
        model: sensorBlock.expanded ? sensorBlock.ruleIdx.length : 0
        Panel {
            id: card
            required property int index
            readonly property var rule: { AlertRules.revision; return AlertRules.rules[sensorBlock.ruleIdx[index]] || null }
            readonly property bool opened: rule !== null && page.openId === rule.id
            readonly property bool active: { AlertRules.stateRevision; return rule !== null && AlertRules.isActive(rule.id) }
            readonly property color levelColor: rule && rule.level === "caution" ? Theme.warn : Theme.error
            readonly property real pad: 22 * page.unit

            width: parent ? parent.width : 0
            height: col.implicitHeight + 2 * pad
            radius: Theme.radius + 6
            visible: rule !== null
            border.color: active ? levelColor : Theme.panelBorder
            border.width: active ? 2 : 1

            Column {
                id: col
                x: card.pad
                y: card.pad
                width: card.width - 2 * card.pad
                spacing: 6 * page.unit

                // ---- 見出し(タップで開く・閉じる) ----
                Item {
                    width: parent.width
                    height: Math.max(head.implicitHeight, enabledSwitch.height)
                    MouseArea {
                        anchors.fill: parent
                        onClicked: page.openId = card.opened ? "" : card.rule.id
                    }
                    Row {
                        id: head
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        width: parent.width - enabledSwitch.width - 16 * page.unit
                        spacing: 12 * page.unit
                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: card.opened ? "expand_less" : "expand_more"
                            size: 34 * page.unit
                            color: Theme.textSecondary
                        }
                        Rectangle {   // 段階の札
                            anchors.verticalCenter: parent.verticalCenter
                            width: levelText.implicitWidth + 20 * page.unit
                            height: 34 * page.unit
                            radius: height / 2
                            color: card.rule && card.rule.enabled ? card.levelColor : Theme.panelBorder
                            Text {
                                id: levelText
                                anchors.centerIn: parent
                                font.family: Theme.fontFamily
                                font.pixelSize: 19 * page.unit
                                font.bold: true
                                color: "#ffffff"
                                text: card.rule && card.rule.level === "caution" ? "注意" : "警告"
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - x
                            spacing: 2 * page.unit
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: 26 * page.unit
                                font.bold: true
                                color: card.rule && card.rule.enabled ? Theme.textPrimary : Theme.textSecondary
                                text: (card.rule ? card.rule.message : "") + (card.active ? "  ・ 今出ています" : "")
                            }
                            Text {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                font.family: Theme.fontFamily
                                font.pixelSize: 19 * page.unit
                                color: Theme.textSecondary
                                text: card.rule ? AlertRules.summary(card.rule) : ""
                            }
                        }
                    }
                    SettingsSwitch {
                        id: enabledSwitch
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        checked: card.rule !== null && card.rule.enabled
                        onToggled: (v) => AlertRules.updateRule(card.rule.id, { enabled: v })
                    }
                }

                // ---- 開いたときの細かい設定 ----
                Loader {
                    width: parent.width
                    active: card.opened
                    visible: active
                    sourceComponent: editor
                }
            }

            Component {
                id: editor
                Column {
                    width: parent ? parent.width : 0
                    readonly property var rule: card.rule
                    readonly property bool isWarn: rule.level === "warn"

                    SettingsRow {
                        label: "段階"
                        description: "警告は赤、注意は黄で知らせます。同じ計測値で両方出ているときは警告を優先します"
                        SettingsChoice {
                            model: ["警告", "注意"]
                            currentIndex: rule.level === "caution" ? 1 : 0
                            onPicked: (i) => AlertRules.updateRule(rule.id, { level: i === 1 ? "caution" : "warn" })
                        }
                    }

                    // ---- 条件(すべて満たしたとき) ----
                    Repeater {
                        model: rule.conditions.length
                        SettingsRow {
                            id: condRow
                            required property int index
                            readonly property var cond: card.rule.conditions[index] || card.rule.conditions[0]
                            readonly property var spec: AlertRules.numberSpec(cond.source)
                            readonly property var u: AlertRules.unitOf(card.rule, cond.source)
                            readonly property bool twoValues: cond.op === "outside" || cond.op === "inside"
                            // センサーを選ぶときに開いている分類(最初は今のセンサーの分類)
                            property string pickGroup: AlertRules.sourceGroup(cond.source)
                            label: index === 0 ? "条件" : "かつ"
                            description: AlertRules.conditionText(card.rule, cond)
                            stacked: true
                            Column {
                                width: condRow.width
                                spacing: 12 * page.unit
                                // センサーは 2 段で選ぶ: 分類(基本・ECU の分類・車両異常・状態)→ その中のセンサー(選択肢が多いので)
                                SettingsChoice {
                                    maxWidth: condRow.width
                                    model: AlertRules.sourceGroups.map(g => AlertRules.sourceGroupShort(g))
                                    currentIndex: AlertRules.sourceGroups.indexOf(condRow.pickGroup)
                                    onPicked: (i) => condRow.pickGroup = AlertRules.sourceGroups[i]
                                }
                                SettingsChoice {
                                    readonly property var ids: AlertRules.sourceIds.filter(id => AlertRules.sourceGroup(id) === condRow.pickGroup)
                                    maxWidth: condRow.width
                                    model: ids.map(id => AlertRules.sourceTitle(id))
                                    currentIndex: ids.indexOf(condRow.cond.source)
                                    onPicked: (i) => {
                                        // 最初の条件のセンサーを変えると、ルールはそのセンサーの箱へ移る(箱もそちらを開く)
                                        if (condRow.index === 0) page.openSensor = ids[i]
                                        AlertRules.updateCondition(card.rule.id, condRow.index, { source: ids[i] })
                                    }
                                }
                                SettingsChoice {
                                    readonly property var ops: condRow.spec ? AlertRules.opsNumber : AlertRules.opsBool
                                    maxWidth: condRow.width
                                    model: ops.map(o => o.label)
                                    currentIndex: ops.findIndex(o => o.id === condRow.cond.op)
                                    onPicked: (i) => AlertRules.updateCondition(card.rule.id, condRow.index, { op: ops[i].id })
                                }
                                Row {
                                    visible: condRow.spec !== null
                                    spacing: 16 * page.unit
                                    WSStepper {
                                        anchors.verticalCenter: parent.verticalCenter
                                        value: condRow.u ? AlertRules.toShown(condRow.cond.value, condRow.u) : 0
                                        from: condRow.u ? AlertRules.toShown(condRow.spec.limitMin, condRow.u) : 0
                                        to: condRow.u ? AlertRules.toShown(condRow.spec.limitMax, condRow.u) : 0
                                        step: condRow.u ? condRow.u.step : 1
                                        decimals: condRow.u ? condRow.u.stepDec : 0
                                        suffix: condRow.u ? " " + condRow.u.label : ""
                                        onMoved: (v) => AlertRules.updateCondition(card.rule.id, condRow.index,
                                                                                    { value: Number(AlertRules.toBase(v, condRow.u).toFixed(3)) })
                                    }
                                    Text {
                                        visible: condRow.twoValues
                                        anchors.verticalCenter: parent.verticalCenter
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 24 * page.unit
                                        color: Theme.textSecondary
                                        text: "〜"
                                    }
                                    WSStepper {
                                        visible: condRow.twoValues
                                        anchors.verticalCenter: parent.verticalCenter
                                        value: condRow.u ? AlertRules.toShown(condRow.cond.value2, condRow.u) : 0
                                        from: condRow.u ? AlertRules.toShown(condRow.spec.limitMin, condRow.u) : 0
                                        to: condRow.u ? AlertRules.toShown(condRow.spec.limitMax, condRow.u) : 0
                                        step: condRow.u ? condRow.u.step : 1
                                        decimals: condRow.u ? condRow.u.stepDec : 0
                                        suffix: condRow.u ? " " + condRow.u.label : ""
                                        onMoved: (v) => AlertRules.updateCondition(card.rule.id, condRow.index,
                                                                                    { value2: Number(AlertRules.toBase(v, condRow.u).toFixed(3)) })
                                    }
                                }
                                ActionButton {
                                    visible: card.rule.conditions.length > 1
                                    text: "この条件を消す"
                                    onClicked: AlertRules.removeCondition(card.rule.id, condRow.index)
                                }
                            }
                        }
                    }
                    SettingsRow {
                        label: "条件を足す"
                        description: "足した条件もすべて満たしたときだけ出します(例: 速度 10 km/h 以上 かつ バック)"
                        ActionButton { text: "条件を追加"; onClicked: AlertRules.addCondition(rule.id) }
                    }
                    SettingsRow {
                        id: unitRow
                        readonly property var spec: AlertRules.numberSpec(rule.conditions[0].source)
                        visible: spec !== null && spec.units.length > 1
                        label: "単位"
                        description: "設定・通知で使う単位"
                        SettingsChoice {
                            model: unitRow.spec ? unitRow.spec.units.map(x => x.label) : []
                            currentIndex: unitRow.spec ? Math.max(0, unitRow.spec.units.findIndex(x => x.id === rule.unit)) : 0
                            onPicked: (i) => AlertRules.updateRule(rule.id, { unit: unitRow.spec.units[i].id })
                        }
                    }
                    SettingsRow {
                        label: "続いたら出す"
                        description: "条件がこの時間続いたときに出します(0 秒ならすぐ)。一瞬だけの変化では知らせたくないときに"
                        WSStepper {
                            value: rule.holdSec
                            from: 0
                            to: 600
                            step: 1
                            suffix: " 秒"
                            onMoved: (v) => AlertRules.updateRule(rule.id, { holdSec: v })
                        }
                    }
                    SettingsRow {
                        label: "エンジンが始動してから"
                        description: "オンなら、エンジンが始動したとみなされてから(始動直後の数値が落ち着いてから)だけ見ます"
                        SettingsSwitch {
                            checked: rule.armedOnly
                            onToggled: (v) => AlertRules.updateRule(rule.id, { armedOnly: v })
                        }
                    }
                    SettingsRow {
                        label: "メッセージ"
                        description: "通知の見出しと、メーターに重ねる帯のメッセージ"
                        stacked: true
                        WSTextField {
                            width: Math.min(520 * page.unit, card.width - 2 * card.pad)
                            text: rule.message
                            placeholder: AlertRules.sourceTitle(rule.conditions[0].source) + (isWarn ? "の警告" : "に注意")
                            maxLength: 24
                            onEdited: (t) => AlertRules.updateRule(rule.id, { message: t.trim() !== "" ? t.trim() : placeholder })
                        }
                    }
                    SettingsRow {
                        label: isWarn ? "警告音を鳴らす" : "注意音を鳴らす"
                        description: isWarn ? "消音するまで鳴らし続けます(メーター・ホーム画面の解除ボタンで消音。音は 設定 > 音 > 効果音 の警告音)"
                                            : "注意になったときに 1 回だけ鳴らします(音は 設定 > 音 > 効果音 の注意音)"
                        SettingsSwitch {
                            checked: rule.beep
                            onToggled: (v) => AlertRules.updateRule(rule.id, { beep: v })
                        }
                    }
                    SettingsRow {
                        label: "ポップアップ通知"
                        description: "「1 回だけ」: 出たときに通知を出し(8 秒で消えます)、表示中は今の値を更新します。"
                                     + "「出し続ける」: 出ている間は通知を出したままにします。"
                                     + "解除されると、その間の最大値(以下の条件は最低値)を出してから消え、通知履歴に 1 件残します。"
                                     + "同じ計測値のルールは 1 つの通知にまとめます"
                        stacked: true
                        SettingsChoice {
                            model: ["オフ", "1 回だけ", "出し続ける"]
                            currentIndex: ["off", "once", "live"].indexOf(rule.popup)
                            onPicked: (i) => AlertRules.updateRule(rule.id, { popup: ["off", "once", "live"][i] })
                        }
                    }
                    SettingsRow {
                        visible: rule.popup !== "off"
                        label: "通知に条件を入れる"
                        SettingsSwitch {
                            checked: rule.popupDetail
                            onToggled: (v) => AlertRules.updateRule(rule.id, { popupDetail: v })
                        }
                    }
                    SettingsRow {
                        label: "メーターに表示"
                        description: "条件に使っている計測値のメーターに、範囲(目盛りの帯)と状態(色・点滅)を出します"
                        SettingsSwitch {
                            checked: rule.showOnGauge
                            onToggled: (v) => AlertRules.updateRule(rule.id, { showOnGauge: v })
                        }
                    }
                    SettingsRow {
                        visible: rule.showOnGauge
                        label: "メーターにメッセージを出す"
                        description: "オフにすると、メーターには色とアイコンだけで知らせます"
                        SettingsSwitch {
                            checked: rule.banner
                            onToggled: (v) => AlertRules.updateRule(rule.id, { banner: v })
                        }
                    }
                    Item { width: 1; height: 12 * page.unit }
                    Row {
                        spacing: 12 * page.unit
                        ActionButton { text: "上へ"; onClicked: AlertRules.moveRuleWithin(rule.id, -1) }
                        ActionButton { text: "下へ"; onClicked: AlertRules.moveRuleWithin(rule.id, 1) }
                        ActionButton {
                            id: deleteButton
                            property bool armed: false
                            text: armed ? "もう一度押すと削除" : "このルールを削除"
                            selected: armed
                            onClicked: {
                                if (!armed) { armed = true; disarm.restart(); return }
                                page.openId = ""
                                AlertRules.removeRule(rule.id)
                            }
                            Timer { id: disarm; interval: 3000; onTriggered: deleteButton.armed = false }
                        }
                    }
                }
            }
        }
    }
                        Row {
                            spacing: 12 * page.unit
                            ActionButton { text: "警告を追加"; onClicked: page.addTo(sensorBlock.source, "warn") }
                            ActionButton { text: "注意を追加"; onClicked: page.addTo(sensorBlock.source, "caution") }
                        }
                    }
                }
            }
        }
    }
}
