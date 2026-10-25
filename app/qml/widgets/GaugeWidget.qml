// 汎用のメーター(ターボ圧計・タコメーター・スピードメーター・水温計・燃料計・油温計・油圧計・電圧計で共通)。
// 何を測るかは config.metric(WidgetRegistry の defaultConfig で種類ごとに固定)で決まり、計測値の定義
// (データ元・単位・換算・設定できる範囲・既定の見出し)は WidgetRegistry.gaugeSpecs にまとめてある。
// 設定値(最小・最大・警告値)は基本単位(bar / rpm / km/h / ℃ / % / V)で保存し、表示と編集のときだけ選んだ単位に換算する。
//  - 表示方式: アナログ+デジタル / アナログ / デジタル
//  - メーターの種類: クラシック(細い外周+目盛り+警告帯) / シンプル(細い進捗リング) / スポーツ(セグメント式のバー)
//    どの種類も、数字の内側に細い円を引き、数値は太字の斜体で表示する
//  - 最小値・最大値・単位・開始/終了角度・数値の配置・針の出っ張り・中心円の大きさと色・針の色
//  - アイコン表示・警告値・警告メッセージ(燃料計のように「この値以下で警告」の計測値もある)
//  - 2×2 などの小さいサイズ(短辺 2 マス以下)は小型表示(compact)。名前と数値を少し大きめにする
// 警告になると、針と数値が赤になり、名前の横のアイコンが警告マークになって点滅し、警告メッセージの帯がメーターに重なる
// (解除は警告値から少し戻ったとき)。
// 警告(と、警告音・通知)は、エンジンが始動したとみなされてから有効になる(can.warningsArmed。判定は VehicleDataManager)。
// エンジン停止とみなされると、警告中でも解除する(エンジンを止めたときの油圧・電圧の低下で鳴らないように)。
// ピーク表示(config.peakMode): "max"(既定。最大値) / "min"(最小値) / "off"。数値のすぐ上に小さく「MAX 値 単位 ↺」を出し
//   (アナログのみのときは単位の下)、タップでリセットする(今の値から測り直す)。起動中だけ覚える(再起動するとリセット)。
// 警告音(config.warnBeep): 警告中は WarningAlarm に登録し、ビープを鳴らしてもらう(自分では鳴らさない)。
//   鳴っている間はメーター全体を赤く点滅させ、太い赤枠と「消音」の印を出して、どのメーターが鳴っているか分かるようにする。
//   タップすると、その警告が解除されるまで音を止める(赤い表示は残す)。設定画面のプレビューでは鳴らさない。
// ポップアップ通知(config.warnPopupMode。通知はどれも赤いエラー表示):
//   "once": 警告になったときに通知を出す(8 秒で消える)。表示中は今の値を 0.5 秒ごとに書き換え、もう一度警告に
//           なったときにまだ出ていれば、新しく出さずに同じ通知を書き換えて、表示時間を数え直す
//   "live": 警告中は通知を出し続け、今の値を 0.5 秒ごとに書き換える。警告が解除されると消える。
//           タップで消すと、その警告が解除されるまでは出し直さない
//   警告が解除された(警告値の内側へ戻った)ときは、その警告の間の最大値(下側で警告する計測値は最低値)を
//   「解除」として通知に出す(赤 → 橙。8 秒で消える。出し続ける通知もこのとき消えずに解除の表示へ変わる)。
//   config.warnPopupDetail がオンなら、警告値も通知に入れる。
//   以前の設定(config.warnPopup === true)は "once" として扱う。
//
// レイアウトの考え方:
//  1. 上部の見出し・下の警告欄は持たず、名前と警告メッセージはメーターの中(中心円の上)に出す
//  2. アナログは「半径 1 の円」で、弧・中心円・数値表示が実際に占める範囲(外接矩形)を求め、
//     その矩形が本体に最大で収まる半径を決める(弧の欠けている側の余白を無駄にしない)
//  3. 目盛り(静的)・進捗(値に追従)・針は別々に描き、値が変わっても目盛りは描き直さない
import QtQuick
import OpenCruise

WidgetBase {
    id: root

    // ---------------------------------------------------------------- 計測値の定義と単位
    readonly property string metric: WidgetRegistry.gaugeSpecs[config.metric] ? config.metric : "boost"
    readonly property var gauge: WidgetRegistry.gaugeSpecs[metric]
    readonly property var unitDef: {
        const list = gauge.units
        for (let i = 0; i < list.length; ++i) {
            if (list[i].id === config.unit) return list[i]
        }
        return list[0]
    }
    function toShown(base) { return Number(base) * unitDef.scale + (unitDef.offset || 0) }
    readonly property string unitText: unitDef.label
    readonly property int decimals: unitDef.dec
    readonly property real labelDiv: unitDef.labelDiv || 1        // 目盛りの数字を割る値(回転数の ×1000 など)
    readonly property bool warnBelow: gauge.warnBelow === true    // true なら「警告値以下」で警告

    // ---------------------------------------------------------------- 設定(表示単位に換算済み)
    readonly property string style: config.style === "analog" || config.style === "digital" ? config.style : "both"
    readonly property string dialStyle: config.dialStyle === "minimal" || config.dialStyle === "sport" ? config.dialStyle : "classic"
    readonly property real minV: toShown(config.min)
    readonly property real maxV: Math.max(toShown(config.max), minV + 0.1)
    readonly property real warnV: toShown(config.warn)
    readonly property bool warnOn: config.warnEnabled === true
    readonly property bool showWarnMessage: config.showWarnMessage !== false   // false なら色・アイコンだけで知らせる
    readonly property bool showIcon: config.showIcon !== false
    readonly property real startAngle: Math.max(-180, Math.min(-90, config.startAngle === undefined ? -135 : Number(config.startAngle)))
    readonly property real endAngle: Math.max(90, Math.min(180, config.endAngle === undefined ? 135 : Number(config.endAngle)))
    readonly property real sweepAngle: endAngle - startAngle
    readonly property bool autoLabelPosition: config.autoLabelPosition !== false
    readonly property bool needleTail: config.needleTail !== false
    readonly property real hubSize: Math.max(0.08, Math.min(0.5, (config.hubSize || 16) / 100))   // 直径 / 半径
    readonly property color needleColor: configuredColor("needleColor", Theme.accent)
    readonly property color hubColor: configuredColor("hubColor", Theme.panel)

    function configuredColor(key, fallback) {
        const value = String(config[key] || "")
        if (value === "theme") return Theme.accent
        if (value === "panel") return Theme.panel
        return /^#[0-9a-f]{6}$/i.test(value) ? Qt.color(value) : fallback
    }

    // ---------------------------------------------------------------- 値
    // データ元(現状は VehicleDataManager のモック)。束縛の依存を確実に取るため、プロパティを直接読む
    readonly property real sourceValue: {
        switch (metric) {
        case "rpm": return can.rpm
        case "speed": return can.speedKmh
        case "coolant": return can.coolantTempC
        case "fuel": return can.fuelPercent
        case "oilTemp": return can.oilTempC
        case "oilPressure": return can.oilPressureBar
        case "voltage": return can.batteryVolts
        default: return can.boostBar
        }
    }
    readonly property real rawValue: toShown(sourceValue)
    // 針・数値は滑らかに追従させる(データは約 10Hz)
    property real shown: rawValue
    Behavior on shown { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

    function frac(v) { return Math.max(0, Math.min(1, (v - minV) / (maxV - minV))) }
    // 進捗の起点(0。範囲外なら近い端。ブーストの負圧は 0 から左へ伸びる)
    readonly property real originV: Math.max(minV, Math.min(maxV, 0))
    // 警告ゾーン(表示単位)。上側警告なら [警告値, 最大]、下側警告なら [最小, 警告値]
    readonly property bool hasWarnZone: warnOn && (warnBelow ? warnV > minV : warnV < maxV)
    readonly property real zoneLo: warnBelow ? minV : Math.max(warnV, minV)
    readonly property real zoneHi: warnBelow ? Math.min(warnV, maxV) : maxV
    function inZone(v) { return hasWarnZone && (warnBelow ? v <= warnV + 1e-9 : v >= warnV - 1e-9) }
    // 「-0.00」を出さない数値整形
    function fmt(v, dec) {
        const half = 0.5 * Math.pow(10, -dec)
        return (Math.abs(v) < half ? 0 : v).toFixed(dec)
    }

    // ---------------------------------------------------------------- 警告(ヒステリシスつき)
    property bool warning: false
    readonly property bool warningsArmed: can.warningsArmed
    onWarningsArmedChanged: updateWarning()
    function updateWarning() {
        const hysteresis = (maxV - minV) * 0.03
        if (!warnOn || !warningsArmed) warning = false
        else if (warnBelow) {
            if (!warning && rawValue <= warnV) warning = true
            else if (warning && rawValue > warnV + hysteresis) warning = false
        } else {
            if (!warning && rawValue >= warnV) warning = true
            else if (warning && rawValue < warnV - hysteresis) warning = false
        }
    }
    onRawValueChanged: { updateWarning(); updatePeak(); if (warning) updateEpisode() }
    onWarnOnChanged: updateWarning()
    onWarnVChanged: updateWarning()
    onWarnBelowChanged: updateWarning()
    Component.onCompleted: updateWarning()

    // 警告音が鳴っている間は背景が赤く点滅するので、数値は白にして読みやすくする
    readonly property color valueColor: beeping ? "#ffffff" : (warning ? Theme.error : Theme.textPrimary)

    // ---------------------------------------------------------------- ピーク(最大・最小)
    readonly property string peakMode: config.peakMode === "min" || config.peakMode === "off" ? config.peakMode : "max"
    property real peak: NaN
    function updatePeak() {
        if (isNaN(peak)) peak = rawValue
        else if (peakMode === "min" ? rawValue < peak : rawValue > peak) peak = rawValue
    }
    function resetPeak() { peak = rawValue }
    readonly property bool peakShown: peakMode !== "off" && !isNaN(peak)

    // ピークの小さな表示(数値の上に置く)。タップでリセット
    component PeakLabel: Item {
        id: pl
        property real px: 12
        property int align: Text.AlignHCenter
        visible: root.peakShown
        height: Math.ceil(px * 1.35)
        Row {
            id: plRow
            anchors.verticalCenter: parent.verticalCenter
            x: pl.align === Text.AlignRight ? pl.width - width : (pl.align === Text.AlignLeft ? 0 : (pl.width - width) / 2)
            spacing: Math.round(pl.px * 0.3)
            opacity: plMouse.pressed ? 0.5 : 0.9
            Text {
                anchors.baseline: plValue.baseline
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: Math.round(pl.px * 0.75)
                color: Theme.textSecondary
                text: root.peakMode === "min" ? "MIN" : "MAX"
            }
            Text {
                id: plValue
                font.family: Theme.fontFamily
                font.bold: true
                font.italic: true
                font.pixelSize: Math.round(pl.px)
                color: root.inZone(root.peak) ? Theme.error : Theme.textSecondary
                text: isNaN(root.peak) ? "" : root.fmt(root.peak, root.decimals)
            }
            Text {
                anchors.baseline: plValue.baseline
                font.family: Theme.fontFamily
                font.pixelSize: Math.round(pl.px * 0.75)
                color: Theme.textSecondary
                text: root.unitText
            }
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "restart_alt"
                size: Math.round(pl.px * 1.05)
                color: Theme.textSecondary
            }
        }
        MouseArea {
            id: plMouse
            // 小さくても押しやすいよう、文字より広めに受ける
            x: plRow.x - pl.px; y: -pl.px * 0.5
            width: plRow.width + pl.px * 2; height: pl.height + pl.px
            onClicked: root.resetPeak()
        }
    }
    onPeakModeChanged: resetPeak()
    onUnitDefChanged: resetPeak()

    // 点滅(警告中だけ動かす)
    property real blink: 1
    SequentialAnimation on blink {
        running: root.warning && !root.lifting
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 380; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 380; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.blink = 1
    }

    // ---------------------------------------------------------------- 警告音・ポップアップ通知
    readonly property bool beepOn: warnOn && config.warnBeep === true
    readonly property string popupMode: config.warnPopupMode === "once" || config.warnPopupMode === "live"
                                        || config.warnPopupMode === "off"
                                        ? config.warnPopupMode : (config.warnPopup === true ? "once" : "off")
    readonly property bool popupOn: warnOn && popupMode === "once"
    readonly property bool popupDetail: config.warnPopupDetail !== false
    // 警告音を出したい状態(配置されているウィジェットだけ。プレビューは widgetId が空)
    readonly property bool alarming: beepOn && warning && widgetId !== ""
    // 今ビープが鳴っているか / 鳴っていたがタップで止めたか
    readonly property bool beeping: { WarningAlarm.revision; return alarming && WarningAlarm.isSounding(widgetId) }
    readonly property bool silenced: alarming && !beeping
    property string raisedKey: ""     // WarningAlarm に登録している key
    function syncAlarm() {
        const want = alarming ? widgetId : ""
        if (raisedKey === want) return
        if (raisedKey !== "") WarningAlarm.clear(raisedKey)
        raisedKey = want
        if (want !== "") WarningAlarm.raise(want, labelText)
    }
    onAlarmingChanged: syncAlarm()
    onWidgetIdChanged: syncAlarm()
    Component.onDestruction: {
        if (raisedKey !== "") WarningAlarm.clear(raisedKey)
        if (liveNoticeId >= 0) notifications.dismiss(liveNoticeId)
    }
    onTapped: if (beeping) WarningAlarm.acknowledge(widgetId)

    // 通知のタイトル(警告中の状態)。警告メッセージ(例: 「油温が高すぎます」)をそのまま使う
    readonly property string warnTitle: config.warnMessage || gauge.warnMessage || (labelText + "が警告値を超えています")
    // 今の警告の間の最大値(下側で警告する計測値は最低値)。警告になったときに測り始める
    property real episodePeak: NaN
    function updateEpisode() {
        if (isNaN(episodePeak) || (warnBelow ? rawValue < episodePeak : rawValue > episodePeak)) episodePeak = rawValue
    }
    readonly property string episodeLabel: warnBelow ? "最低" : "最大"
    // 通知のタイトル・レベル(警告中は赤、解除後は橙)。warning が変わった直後のハンドラーからも呼ぶので、
    // 束縛ではなく関数にして、その時点の warning で決める
    function noticeTitle() { return warning ? warnTitle : labelText + "が正常に戻りました" }
    function noticeLevel() { return warning ? 3 : 2 }
    // 通知の本文: 値だけの 1 行。警告中は今の値(行き過ぎていればその警告の間の最大値も)、
    // 解除後はその警告の間の最大値。「通知に詳細を表示」なら警告値も付ける
    function warnPopupText() {
        const limit = popupDetail ? "(警告値 " + fmt(warnV, decimals) + " " + unitText + (warnBelow ? " 以下)" : " 以上)") : ""
        const peakText = isNaN(episodePeak) ? "" : episodeLabel + " " + fmt(episodePeak, decimals) + " " + unitText
        if (!warning) return (peakText !== "" ? peakText : "") + limit
        let line = "現在 " + fmt(rawValue, decimals) + " " + unitText
        if (peakText !== "" && Math.abs(episodePeak - rawValue) >= Math.pow(10, -decimals))
            line += " ・ " + peakText
        return line + limit
    }
    // 「1 回だけ」の通知。表示中の通知があれば書き換えて表示時間を数え直し、無ければ新しく出す
    readonly property int onceDurationMs: 8000
    property int onceNoticeId: -1
    function showWarnPopup() {
        if (onceNoticeId >= 0
                && notifications.update(onceNoticeId, noticeTitle(), warnPopupText(), noticeLevel(), onceDurationMs)) return
        onceNoticeId = notifications.show(noticeTitle(), warnPopupText(), noticeLevel(), gauge.icon, onceDurationMs)
    }
    onWarningChanged: {
        if (warning) {
            episodePeak = rawValue
            if (popupOn && widgetId !== "") showWarnPopup()
        } else if (onceNoticeId >= 0) {
            if (!warningsArmed) {
                // エンジン停止で警告を無効にした: 「正常に戻りました」とは言えないので、通知は閉じる
                notifications.dismiss(onceNoticeId)
                onceNoticeId = -1
            } else if (!notifications.update(onceNoticeId, noticeTitle(), warnPopupText(), noticeLevel(), onceDurationMs)) {
                // 「1 回だけ」の通知がまだ出ていれば、解除の表示(最大値)に変えて、表示時間を数え直す
                onceNoticeId = -1
            }
        }
    }

    // 出し続ける通知("live")
    readonly property bool wantLiveNotice: warnOn && popupMode === "live" && warning && widgetId !== ""
    property int liveNoticeId: -1
    property bool liveDismissed: false   // タップで消された(警告が解除されるまで出し直さない)
    function syncLiveNotice() {
        if (wantLiveNotice) {
            if (liveDismissed) return
            // 前の警告の解除の表示がまだ出ていれば、新しく出さずにそれを書き換える(消えないようにする)
            if (liveNoticeId >= 0 && notifications.update(liveNoticeId, noticeTitle(), warnPopupText(), 3, 0)) return
            liveNoticeId = notifications.show(noticeTitle(), warnPopupText(), 3, gauge.icon, 0)
        } else {
            if (liveNoticeId >= 0) {
                if (!warning && warnOn && warningsArmed && popupMode === "live" && widgetId !== "") {
                    // 警告が解除された: 消さずに解除の表示(その警告の間の最大値)へ変え、しばらくしたら消す。
                    // id は覚えておき、消える前にまた警告になったら同じ通知を使う
                    if (!notifications.update(liveNoticeId, noticeTitle(), warnPopupText(), noticeLevel(), onceDurationMs))
                        liveNoticeId = -1
                } else {
                    notifications.dismiss(liveNoticeId)   // 設定を変えた・ウィジェットが消えた・エンジン停止
                    liveNoticeId = -1
                }
            }
            liveDismissed = false
        }
    }
    onWantLiveNoticeChanged: syncLiveNotice()
    Timer {   // 「1 回だけ」の通知の値の更新(表示中だけ。表示時間はそのまま)
        interval: 500
        repeat: true
        running: root.onceNoticeId >= 0
        onTriggered: {
            if (!notifications.update(root.onceNoticeId, root.noticeTitle(), root.warnPopupText(), root.noticeLevel()))
                root.onceNoticeId = -1   // 時間が来て消えた・タップで消された
        }
    }
    Timer {   // 出し続ける通知の値の更新(0.5 秒ごと)。消されていたら止める
        interval: 500
        repeat: true
        running: root.liveNoticeId >= 0 && root.wantLiveNotice
        onTriggered: {
            if (!notifications.update(root.liveNoticeId, root.noticeTitle(), root.warnPopupText(), 3)) {
                root.liveNoticeId = -1
                root.liveDismissed = true
            }
        }
    }

    // ---------------------------------------------------------------- 寸法
    readonly property real m: root.innerMargin
    // 小型表示(短辺 2 マス以下、2×2 など)。目盛りは普通のサイズと同じ。名前と数値の枠を少し大きめにし、デジタルの両端の値は省く
    readonly property bool compact: Math.min(gridW, gridH) <= 2

    // ---------------------------------------------------------------- メーター内の名前(上部の見出しの代わり)
    // アイコン+名前。警告中はアイコンが警告マークになり点滅する。警告メッセージは下の帯をメーターに重ねて出す
    readonly property bool labelVisible: titleVisible
    readonly property string labelIcon: warning ? "warning" : gauge.icon
    readonly property string labelText: titleText(gauge.title)
    readonly property color labelColor: warning ? Theme.error : Theme.textSecondary
    readonly property real labelOpacity: 1

    // 警告音が鳴っている間: メーター全体を赤く点滅させる(中身より下に敷く)
    Rectangle {
        z: -1
        anchors.fill: parent
        radius: Theme.radius + 6
        color: Theme.error
        visible: opacity > 0
        opacity: root.beeping ? 0.12 + 0.26 * (1 - root.blink) / 0.65 : (root.silenced ? 0.1 : 0)
    }

    // モックデータ中の表示(右上)
    Rectangle {
        id: mockTag
        z: 2
        anchors { top: parent.top; right: parent.right; topMargin: root.m * 0.7; rightMargin: root.m }
        width: mockText.implicitWidth + 14
        height: mockText.implicitHeight + 4
        radius: height / 2
        color: "transparent"
        border.color: Theme.warn
        Text {
            id: mockText
            anchors.centerIn: parent
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(root.titleFontSize * (root.compact ? 0.65 : 0.75))
            text: "モック"
            color: Theme.warn
        }
    }

    // ================================================================ 本体
    Item {
        id: body
        anchors { fill: parent; margins: root.m }

        // ============================================================ アナログ
        Item {
            id: dial
            visible: root.style !== "digital"

            // ---- 半径 1 の円で考えた配置(中心が原点、0° が真上・時計回り) ----
            // 数値表示の枠。auto のときは弧の空き(開始と終了の間)の方向へ置き、中心円とは重ならないようにする
            readonly property var readout: {
                // 数値を大きく見せるため広めに取る(小型表示は少し縦に広げる)
                // ピーク表示があるときは、枠の上端にピーク表示の 1 行(peakH)を足し、その分だけ中心から離す
                // (数値の大きさは変えない。ピーク表示は針の反対側の出っ張りの先より外になる)
                const ph = dial.peakH
                const w = 0.72, h = (root.compact ? 0.56 : 0.5) + ph
                const hubClear = root.hubSize / 2 + 0.05
                let cx = 0, cy = 0.52 + ph / 2
                if (root.autoLabelPosition) {
                    const g = ((root.startAngle + root.endAngle) / 2 + 180) * Math.PI / 180
                    const rr = ((360 - root.sweepAngle) >= 60 ? 0.56 : 0.5) + ph / 2
                    cx = Math.sin(g) * rr
                    cy = -Math.cos(g) * rr
                }
                if (cy - h / 2 < hubClear) cy = hubClear + h / 2
                return { x: cx - w / 2, y: cy - h / 2, w: w, h: h }
            }
            // 数値の上のピーク表示の高さ(半径比)。アナログ+デジタルでピーク表示があるときだけ
            readonly property real peakH: root.peakShown && root.style === "both" ? 0.12 : 0
            // アナログのみのときの単位表示(中心円の下)
            readonly property real unitY: root.hubSize / 2 + 0.16
            readonly property string scaleUnitText: root.labelDiv > 1 ? "×" + root.labelDiv + " " + root.unitText : root.unitText

            // 弧・中心円・数値表示が占める範囲
            readonly property var bounds: {
                const xs = [], ys = []
                const add = (deg, r) => {
                    const a = deg * Math.PI / 180
                    xs.push(Math.sin(a) * r); ys.push(-Math.cos(a) * r)
                }
                add(root.startAngle, 1)
                add(root.endAngle, 1)
                for (let d = -180; d <= 180; d += 90) {
                    if (d >= root.startAngle && d <= root.endAngle) add(d, 1)
                }
                const hr = root.hubSize / 2
                xs.push(-hr, hr); ys.push(-hr, hr)
                if (root.style === "both") {
                    xs.push(readout.x, readout.x + readout.w)
                    ys.push(readout.y, readout.y + readout.h)
                } else {
                    // 単位と、その下のピーク表示(ある場合)まで
                    ys.push(root.peakShown ? unitY + 0.29 : unitY + 0.07)
                }
                const pad = 0.02
                return { minX: Math.min(...xs) - pad, maxX: Math.max(...xs) + pad,
                         minY: Math.min(...ys) - pad, maxY: Math.max(...ys) + pad }
            }

            // ---- 実寸(px) ----
            // 半径(px)。QML のプロパティ名は小文字始まりが必須なので rpx とする
            readonly property real rpx: Math.max(1, Math.min(body.width / (bounds.maxX - bounds.minX),
                                                             body.height / (bounds.maxY - bounds.minY)))
            readonly property real cx: -bounds.minX * rpx
            readonly property real cy: -bounds.minY * rpx
            width: (bounds.maxX - bounds.minX) * rpx
            height: (bounds.maxY - bounds.minY) * rpx
            anchors.centerIn: parent

            // メーターの種類ごとの寸法(半径に対する比)
            // どの種類も、数字は内側の細い円(ringR)の外側、目盛りはさらに外側に置く
            readonly property var dims: root.dialStyle === "sport"
                ? { trackR: 0.92, trackW: 0.12, majorIn: 0.78, minorIn: 0.80, tickOut: 0.835, labelR: 0.665,
                    majorW: 0.03, minorW: 0.012, sub: 2, labelPx: 0.14, needleTip: 0.8, ringR: 0.5 }
                : (root.dialStyle === "minimal"
                   ? { trackR: 0.95, trackW: 0.03, majorIn: 0.83, minorIn: 0.86, tickOut: 0.89, labelR: 0.685,
                       majorW: 0.02, minorW: 0.01, sub: 2, labelPx: 0.13, needleTip: 0.86, ringR: 0.5 }
                   : { trackR: 0.96, trackW: 0.025, majorIn: 0.77, minorIn: 0.82, tickOut: 0.87, labelR: 0.655,
                       majorW: 0.026, minorW: 0.011, sub: 5, labelPx: 0.125, needleTip: 0.88, ringR: 0.5 })

            // スポーツのセグメント(数と 1 つあたりの角度。セグメントの間は少し空ける)
            readonly property int segCount: Math.max(16, Math.round(root.sweepAngle / 6))
            readonly property real segDeg: root.sweepAngle / segCount
            readonly property real segGap: Math.min(1.8, segDeg * 0.3)

            // 点灯するセグメントの範囲(中央の値が 0〜現在値の間にあるもの)。変わったときだけ描き直す
            readonly property int litFrom: {
                const lo = Math.min(root.originV, root.shown)
                return Math.max(0, Math.ceil((lo - root.minV) / (root.maxV - root.minV) * segCount - 0.5 - 1e-9))
            }
            readonly property int litTo: {
                const hi = Math.max(root.originV, root.shown)
                return Math.min(segCount - 1, Math.floor((hi - root.minV) / (root.maxV - root.minV) * segCount - 0.5 + 1e-9))
            }

            // 角度(度、0° が真上)→ Canvas の角度(ラジアン、0 が右)
            function rad(deg) { return (deg - 90) * Math.PI / 180 }
            function angOf(v) { return root.startAngle + root.frac(v) * root.sweepAngle }
            // セグメント i の中央の値
            function segValue(i) { return root.minV + (root.maxV - root.minV) * (i + 0.5) / segCount }
            // セグメント i を描く(角度は弧の上の位置)
            function drawSeg(ctx, i, R, color) {
                const d0 = root.startAngle + i * segDeg + segGap / 2
                const d1 = root.startAngle + (i + 1) * segDeg - segGap / 2
                ctx.strokeStyle = color
                ctx.beginPath()
                ctx.arc(cx, cy, R * dims.trackR, rad(d0), rad(d1))
                ctx.stroke()
            }

            // ---- 目盛り・警告帯(設定・大きさ・配色が変わったときだけ描き直す) ----
            Canvas {
                id: face
                anchors.fill: parent
                renderStrategy: Canvas.Cooperative
                readonly property string key: [width, height, dial.cx, dial.cy, dial.rpx, root.minV, root.maxV, root.warnV,
                                               root.warnOn, root.warnBelow, root.labelDiv, root.dialStyle, root.startAngle,
                                               root.endAngle, root.compact, Theme.panel, Theme.panelBorder, Theme.textSecondary,
                                               Theme.textPrimary, Theme.error, Theme.accent, Theme.fontFamily].join("|")
                onKeyChanged: requestPaint()

                // 大目盛りの間隔。1 / 2 / 5 × 10^n(と 0.25)から、数字が詰まりすぎない最小のものを選ぶ
                function niceStep(range, maxMajors) {
                    const c = []
                    for (let e = -2; e <= 5; ++e) {
                        const p = Math.pow(10, e)
                        c.push(p, 2 * p)
                        if (e === -1) c.push(0.25)
                        c.push(5 * p)
                    }
                    c.sort((a, b) => a - b)
                    for (let i = 0; i < c.length; ++i) {
                        if (range / c[i] <= maxMajors) return c[i]
                    }
                    return c[c.length - 1]
                }

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const R = dial.rpx, cx = dial.cx, cy = dial.cy, dm = dial.dims
                    if (R <= 1) return
                    const a0 = dial.rad(root.startAngle), a1 = dial.rad(root.endAngle)
                    const angV = (v) => dial.rad(dial.angOf(v))
                    const zoneColor = Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.35)

                    if (root.dialStyle === "classic") {
                        // 外周の細い線
                        ctx.lineCap = "butt"
                        ctx.lineWidth = R * dm.trackW
                        ctx.strokeStyle = Theme.panelBorder
                        ctx.beginPath()
                        ctx.arc(cx, cy, R * dm.trackR, a0, a1)
                        ctx.stroke()
                        // 警告ゾーン: 目盛りの外側に赤い帯
                        if (root.hasWarnZone) {
                            ctx.lineWidth = R * 0.04
                            ctx.strokeStyle = Theme.error
                            ctx.beginPath()
                            ctx.arc(cx, cy, R * 0.905, angV(root.zoneLo), angV(root.zoneHi))
                            ctx.stroke()
                        }
                    } else if (root.dialStyle === "minimal") {
                        ctx.lineCap = "round"
                        ctx.lineWidth = R * dm.trackW
                        ctx.strokeStyle = Theme.panelBorder
                        ctx.beginPath()
                        ctx.arc(cx, cy, R * dm.trackR, a0, a1)
                        ctx.stroke()
                        if (root.hasWarnZone) {
                            ctx.lineCap = "butt"
                            ctx.strokeStyle = zoneColor
                            ctx.beginPath()
                            ctx.arc(cx, cy, R * dm.trackR, angV(root.zoneLo), angV(root.zoneHi))
                            ctx.stroke()
                        }
                    } else {
                        // スポーツ: 消灯したセグメント(警告ゾーンは赤みを帯びる)
                        ctx.lineCap = "butt"
                        ctx.lineWidth = R * dm.trackW
                        for (let i = 0; i < dial.segCount; ++i) {
                            dial.drawSeg(ctx, i, R, root.inZone(dial.segValue(i)) ? zoneColor
                                                                                  : Theme.mix(Theme.panel, Theme.panelBorder, 0.9))
                        }
                    }

                    // 内側の細い円(全種類共通。数字の内側の区切り)
                    ctx.lineCap = "butt"
                    ctx.lineWidth = Math.max(1, R * 0.008)
                    ctx.strokeStyle = Theme.panelBorder
                    ctx.beginPath()
                    ctx.arc(cx, cy, R * dm.ringR, a0, a1)
                    ctx.stroke()

                    // 目盛り(大目盛りに数字。0 は強調)
                    const range = root.maxV - root.minV
                    const maxMajors = Math.max(4, Math.round(root.sweepAngle / 30))
                    const step = niceStep(range / root.labelDiv, maxMajors) * root.labelDiv
                    const stepShown = step / root.labelDiv
                    const dec = stepShown >= 1 ? 0 : (Math.abs(stepShown * 10 - Math.round(stepShown * 10)) < 1e-6 ? 1 : 2)
                    const minor = step / dm.sub
                    const first = Math.ceil(root.minV / minor - 1e-9)
                    ctx.lineCap = "butt"
                    ctx.textAlign = "center"
                    ctx.textBaseline = "middle"
                    const px = Math.max(9, Math.round(R * dm.labelPx))
                    ctx.font = "bold " + px + "px '" + Theme.fontFamily + "'"
                    for (let n = first; n * minor <= root.maxV + 1e-9; ++n) {
                        const v = n * minor
                        const isMajor = Math.abs(v / step - Math.round(v / step)) < 1e-6
                        const isZero = Math.abs(v) < 1e-9
                        const inWarn = root.inZone(v)
                        const a = angV(v)
                        ctx.lineWidth = R * (isMajor ? dm.majorW : dm.minorW)
                        ctx.strokeStyle = inWarn ? Theme.error
                                                 : (isZero ? Theme.accent : (isMajor ? Theme.textPrimary : Theme.textSecondary))
                        ctx.beginPath()
                        ctx.moveTo(cx + Math.cos(a) * R * (isMajor ? dm.majorIn : dm.minorIn), cy + Math.sin(a) * R * (isMajor ? dm.majorIn : dm.minorIn))
                        ctx.lineTo(cx + Math.cos(a) * R * dm.tickOut, cy + Math.sin(a) * R * dm.tickOut)
                        ctx.stroke()
                        if (isMajor) {
                            ctx.fillStyle = inWarn ? Theme.error : (isZero || root.dialStyle === "sport" ? Theme.textPrimary : Theme.textSecondary)
                            ctx.fillText((isZero ? 0 : v / root.labelDiv).toFixed(dec),
                                         cx + Math.cos(a) * R * dm.labelR, cy + Math.sin(a) * R * dm.labelR)
                        }
                    }
                }
            }

            // ---- 進捗(シンプル: 細いリング / スポーツ: 点灯するセグメント)。0 から現在値まで ----
            Canvas {
                id: progress
                anchors.fill: parent
                visible: root.dialStyle !== "classic"
                renderStrategy: Canvas.Cooperative
                readonly property string key: !visible ? "" :
                    [width, height, dial.rpx,
                     root.dialStyle === "sport" ? dial.litFrom + ":" + dial.litTo : dial.angOf(root.shown).toFixed(1),
                     root.minV, root.maxV, root.warnV, root.warnOn,
                     root.warnBelow, root.dialStyle, root.startAngle, root.endAngle, Theme.accent, Theme.warn,
                     Theme.error].join("|")
                onKeyChanged: if (visible) requestPaint()

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const R = dial.rpx, dm = dial.dims
                    if (R <= 1) return
                    const lo = Math.min(root.originV, root.shown), hi = Math.max(root.originV, root.shown)
                    ctx.lineCap = "butt"
                    ctx.lineWidth = R * dm.trackW

                    if (root.dialStyle === "sport") {
                        // 警告値の手前(範囲の 10%)は注意色、警告ゾーンは警告色
                        const near = (root.maxV - root.minV) * 0.1
                        const colorOf = (v) => {
                            if (root.inZone(v)) return Theme.error
                            if (root.hasWarnZone && (root.warnBelow ? v <= root.warnV + near : v >= root.warnV - near)) return Theme.warn
                            return Theme.accent
                        }
                        // 光彩(shadowBlur)は描画が重いので使わない。点灯している範囲だけ描く
                        for (let i = dial.litFrom; i <= dial.litTo; ++i) {
                            dial.drawSeg(ctx, i, R, colorOf(dial.segValue(i)))
                        }
                        return
                    }

                    if (dial.angOf(hi) - dial.angOf(lo) < 0.2) return
                    const seg = (from, to, color) => {
                        if (to <= from) return
                        ctx.strokeStyle = color
                        ctx.beginPath()
                        ctx.arc(dial.cx, dial.cy, R * dm.trackR, dial.rad(dial.angOf(from)), dial.rad(dial.angOf(to)))
                        ctx.stroke()
                    }
                    if (root.hasWarnZone) {
                        // 警告ゾーンと重なる部分だけ警告色
                        const zLo = Math.max(lo, root.zoneLo), zHi = Math.min(hi, root.zoneHi)
                        if (zHi > zLo) {
                            seg(lo, zLo, Theme.accent)
                            seg(zLo, zHi, Theme.error)
                            seg(zHi, hi, Theme.accent)
                            return
                        }
                    }
                    seg(lo, hi, Theme.accent)
                }
            }

            // ---- 針(先細りの形。回転だけで値に追従し、形は大きさ・色が変わったときだけ描き直す) ----
            Item {
                id: needle
                z: 3   // 名前・数値より手前(針はそれらの上を通る)
                x: dial.cx
                y: dial.cy
                width: 0
                height: 0
                rotation: dial.angOf(root.shown)

                Canvas {
                    id: needleShape
                    readonly property real tip: dial.rpx * dial.dims.needleTip
                    readonly property real tail: root.needleTail ? dial.rpx * 0.22 : 0
                    readonly property real base: Math.max(4, dial.rpx * (root.dialStyle === "sport" ? 0.055 : 0.07))
                    readonly property color needleFill: root.warning ? Theme.error : root.needleColor
                    x: -width / 2
                    y: -tip
                    width: Math.ceil(base + 2)
                    height: Math.ceil(tip + tail + 2)
                    renderStrategy: Canvas.Cooperative
                    readonly property string key: [width, height, tip, tail, base, needleFill].join("|")
                    onKeyChanged: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const c = width / 2
                        const tipHalf = Math.max(0.75, base * 0.1)
                        const baseHalf = base / 2
                        const tailHalf = base * 0.32
                        ctx.fillStyle = needleFill
                        ctx.beginPath()
                        ctx.moveTo(c - tipHalf, 0)
                        ctx.lineTo(c + tipHalf, 0)
                        ctx.lineTo(c + baseHalf, tip)
                        if (tail > 0) {
                            ctx.lineTo(c + tailHalf, tip + tail)
                            ctx.lineTo(c - tailHalf, tip + tail)
                        }
                        ctx.lineTo(c - baseHalf, tip)
                        ctx.closePath()
                        ctx.fill()
                    }
                }
            }

            // ---- 名前(中心円の上、内側の細い円の内側。針はこの上を通る = z で針より奥に置く) ----
            Row {
                id: dialLabel
                z: 1   // 針・中心円より奥
                visible: root.labelVisible
                readonly property real h: dial.rpx * (root.compact ? 0.15 : 0.13)
                readonly property real cyU: -Math.max(root.hubSize / 2 + 0.1, 0.32)   // 中心からの位置(半径比)
                // 内側の細い円(半径 0.6)に収まる幅
                readonly property real maxW: 2 * Math.sqrt(Math.max(0.01, 0.58 * 0.58 - cyU * cyU)) * dial.rpx
                x: dial.cx - width / 2
                y: dial.cy + cyU * dial.rpx - h / 2
                height: h
                spacing: h * 0.25
                opacity: root.labelOpacity
                MaterialIcon {
                    id: dialLabelIcon
                    visible: root.showIcon
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.labelIcon
                    size: dialLabel.h
                    color: root.warning ? Theme.error : Theme.accent
                    opacity: root.warning ? root.blink : 1
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, dialLabel.maxW - (root.showIcon ? dialLabel.h + dialLabel.spacing : 0))
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.pixelSize: Math.max(10, dialLabel.h * 0.78)
                    elide: Text.ElideRight
                    color: root.labelColor
                    text: root.labelText
                }
            }

            // ---- 中心円 ----
            Rectangle {
                z: 4   // 針の根元を隠す
                x: dial.cx - width / 2
                y: dial.cy - height / 2
                width: dial.rpx * root.hubSize
                height: width
                radius: width / 2
                color: root.hubColor
                border.width: Math.max(1, dial.rpx * 0.02)
                border.color: root.warning ? Theme.error : (root.dialStyle === "sport" ? Theme.accent : Theme.panelBorder)
            }

            // ---- デジタル表示(アナログ+デジタル) ----
            Column {
                visible: root.style === "both"
                x: dial.cx + dial.readout.x * dial.rpx
                y: dial.cy + dial.readout.y * dial.rpx
                width: dial.readout.w * dial.rpx
                height: dial.readout.h * dial.rpx
                // 数字の下の余白(字の下がり)の分だけ、単位を数値へ近づける
                spacing: -Math.round(dialValue.contentHeight * 0.14)
                PeakLabel {
                    width: parent.width
                    height: dial.peakH * dial.rpx
                    px: Math.max(10, Math.round(dial.rpx * 0.085))
                }
                Text {
                    id: dialValue
                    width: parent.width
                    height: (parent.height - dial.peakH * dial.rpx) * 0.7
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignBottom   // 単位との間を詰めるため、枠の下端に寄せる
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.italic: true   // 数値は全種類で太字の斜体
                    font.pixelSize: 300
                    minimumPixelSize: 12
                    fontSizeMode: Text.Fit
                    text: root.fmt(root.shown, root.decimals)
                    color: root.valueColor
                }
                Text {
                    width: parent.width
                    height: (parent.height - dial.peakH * dial.rpx) * 0.3
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignTop
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(11, dial.rpx * 0.13)
                    text: root.unitText
                    color: Theme.textSecondary
                }
            }

            // ---- 単位(アナログのみ) ----
            Text {
                visible: root.style === "analog"
                x: dial.cx - width / 2
                y: dial.cy + dial.unitY * dial.rpx - height / 2
                font.family: Theme.fontFamily
                font.pixelSize: Math.max(11, dial.rpx * 0.13)
                text: dial.scaleUnitText
                color: Theme.textSecondary
            }
            PeakLabel {   // アナログのみ: 単位の下
                visible: root.style === "analog" && root.peakShown
                width: dial.rpx * 1.2
                x: dial.cx - width / 2
                y: dial.cy + (dial.unitY + 0.13) * dial.rpx
                px: Math.max(11, Math.round(dial.rpx * 0.1))
            }
        }

        // ============================================================ デジタルのみ: 大きな数字と横バー
        Item {
            id: digital
            visible: root.style === "digital"
            anchors.fill: parent

            readonly property real barH: Math.max(8, root.s * 0.045)
            readonly property real scaleH: root.compact ? 0 : Math.round(root.titleFontSize * 0.8) + 4

            // 名前(警告中は警告メッセージ)
            Row {
                id: digitalLabel
                visible: root.labelVisible
                anchors { top: parent.top; left: parent.left }
                width: parent.width - mockTag.width - 8
                height: visible ? Math.max(root.titleBarHeight, Math.round(digital.height * 0.12)) : 0
                spacing: 8
                opacity: root.labelOpacity
                MaterialIcon {
                    visible: root.showIcon
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.labelIcon
                    size: digitalLabel.height * 0.9
                    color: root.warning ? Theme.error : Theme.accent
                    opacity: root.warning ? root.blink : 1
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, digitalLabel.width - (root.showIcon ? digitalLabel.height + digitalLabel.spacing : 0))
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.pixelSize: Math.max(11, digitalLabel.height * 0.72)
                    elide: Text.ElideRight
                    color: root.labelColor
                    text: root.labelText
                }
            }

            // 数値 + 単位(数値の右下に単位)
            Item {
                id: valueBox
                anchors { top: digitalLabel.bottom; left: parent.left; right: parent.right; bottom: barBox.top
                          bottomMargin: root.m * 0.5 }
                PeakLabel {
                    id: digitalPeak
                    anchors { top: parent.top; right: parent.right }
                    width: parent.width
                    align: Text.AlignRight
                    px: Math.max(11, Math.min(valueBox.height * 0.13, 20))
                }
                Text {
                    id: valueText
                    anchors { left: parent.left; right: unitLabel.left; top: root.peakShown ? digitalPeak.bottom : parent.top
                              bottom: parent.bottom; rightMargin: 6 }
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.italic: true
                    font.pixelSize: 300
                    minimumPixelSize: 14
                    fontSizeMode: Text.Fit
                    text: root.fmt(root.shown, root.decimals)
                    color: root.valueColor
                }
                Text {
                    id: unitLabel
                    anchors { right: parent.right; baseline: valueText.baseline }
                    width: Math.max(implicitWidth, parent.width * 0.18)
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(14, Math.min(valueBox.height * 0.3, 40))
                    text: root.unitText
                    color: Theme.textSecondary
                }
            }

            // 横バー(0 から現在値まで塗る。警告ゾーン・0 の目印つき)と、両端の値
            Item {
                id: barBox
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: digital.barH + digital.scaleH + 4

                Item {
                    id: bar
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: digital.barH
                    readonly property real originX: width * root.frac(root.originV)
                    readonly property real valueX: width * root.frac(root.shown)

                    Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.panelBorder }
                    Rectangle {   // 警告ゾーン
                        visible: root.hasWarnZone
                        x: bar.width * root.frac(root.zoneLo)
                        width: bar.width * root.frac(root.zoneHi) - x
                        height: parent.height
                        radius: height / 2
                        color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.4)
                    }
                    Rectangle {   // 現在値
                        x: Math.min(bar.originX, bar.valueX)
                        width: Math.max(2, Math.abs(bar.valueX - bar.originX))
                        height: parent.height
                        radius: height / 2
                        color: root.warning ? Theme.error : Theme.accent
                    }
                    Rectangle {   // 0 の目印
                        visible: root.originV > root.minV && root.originV < root.maxV
                        x: bar.originX - width / 2
                        y: -2
                        width: 2
                        height: parent.height + 4
                        color: Theme.textPrimary
                        opacity: 0.6
                    }
                }
                Text {
                    visible: !root.compact
                    anchors { left: parent.left; top: bar.bottom; topMargin: 4 }
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.round(root.titleFontSize * 0.8)
                    color: root.warnOn && root.warnBelow ? Theme.error : Theme.textSecondary
                    text: root.fmt(root.minV, root.unitDef.stepDec)
                }
                Text {
                    visible: !root.compact
                    anchors { right: parent.right; top: bar.bottom; topMargin: 4 }
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.round(root.titleFontSize * 0.8)
                    color: root.warnOn && !root.warnBelow ? Theme.error : Theme.textSecondary
                    text: root.fmt(root.maxV, root.unitDef.stepDec)
                }
            }
        }
    }

    // ================================================================ 警告音が鳴っているメーターの目印
    // 太い赤枠(鳴っている間は点滅、止めた後は細く常時表示)
    Rectangle {
        z: 5
        anchors.fill: parent
        radius: Theme.radius + 6
        color: "transparent"
        visible: root.alarming
        border.width: root.beeping ? Math.max(4, Math.round(root.s * 0.03)) : 2
        border.color: Theme.error
        opacity: root.beeping ? 0.45 + 0.55 * root.blink : 0.8
    }
    // 左上の印: 鳴っている間は「タップで消音」、止めた後は「消音中」
    Rectangle {
        z: 6
        visible: root.alarming
        anchors { top: parent.top; left: parent.left; topMargin: root.m * 0.7; leftMargin: root.m * 0.7 }
        readonly property bool wide: root.width >= 230
        height: Math.max(22, Math.round(root.titleFontSize * 1.6))
        width: alarmRow.implicitWidth + height * 0.7
        radius: height / 2
        color: root.beeping ? Theme.error : "transparent"
        border.width: root.beeping ? 0 : 1.5
        border.color: Theme.error
        Row {
            id: alarmRow
            anchors.centerIn: parent
            spacing: 4
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.beeping ? "volume_up" : "volume_off"
                size: Math.round(parent.parent.height * 0.68)
                color: root.beeping ? Theme.textOnAccent : Theme.error
            }
            Text {
                visible: parent.parent.wide
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: Math.round(parent.parent.height * 0.5)
                color: root.beeping ? Theme.textOnAccent : Theme.error
                text: root.beeping ? "タップで消音" : "消音中"
            }
        }
    }

    // ================================================================ 警告メッセージ(警告中だけ、メーターの下側に重ねて表示)
    Rectangle {
        id: warnBanner
        z: 3
        visible: opacity > 0
        opacity: root.warning && root.showWarnMessage ? (0.55 + 0.45 * root.blink) : 0
        Behavior on opacity { enabled: !(root.warning && root.showWarnMessage); NumberAnimation { duration: 180 } }
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: root.m }
        width: Math.min(parent.width - 2 * root.m,
                        warnText.implicitWidth + (root.showIcon ? height * 0.62 + 6 : 0) + height)
        height: root.compact ? Math.max(20, Math.round(root.s * 0.17)) : Math.max(26, Math.round(root.s * 0.13))
        radius: height / 2
        color: Theme.mix(Theme.panel, Theme.error, 0.22)
        border.width: 2
        border.color: Theme.error
        Row {
            id: warnRow
            anchors.centerIn: parent
            spacing: 6
            MaterialIcon {
                visible: root.showIcon
                anchors.verticalCenter: parent.verticalCenter
                name: "warning"
                size: warnBanner.height * 0.62
                color: Theme.error
            }
            Text {
                id: warnText
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, warnBanner.width - warnBanner.height - (root.showIcon ? warnBanner.height * 0.62 + 6 : 0))
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: Math.max(12, Math.round(warnBanner.height * 0.5))
                elide: Text.ElideRight
                color: Theme.error
                text: root.config.warnMessage || "警告"
            }
        }
    }
}
