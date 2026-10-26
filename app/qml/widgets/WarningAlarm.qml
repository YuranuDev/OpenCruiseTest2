// 警告音(ビープ)の鳴らし元(シングルトン)。メーターなど、しきい値を超えたウィジェットはここへ登録するだけで、
// 自分では音を鳴らさない。登録が 1 つ以上あり、確認(消音)されていないものがある間だけ、一定の間隔で beep() を出す。
// 音は Main.qml が beep() を受けて systemSound.play("alert") で鳴らす(鳴らす場所は 1 か所だけ)。
// 複数のウィジェットが同時に警告しても、ビープは 1 つのリズムで鳴り、重ならない。
//
//   WarningAlarm.raise(key, title, group)  警告を登録する(key はウィジェットごとに一意。同じ key は 1 件)。
//                                   group は同じ種類のウィジェットの範囲(メーターは "gauge:<計測値>")。
//                                   同じ範囲に消音中の警告があれば、新しい警告も消音で始める
//   WarningAlarm.clear(key)         警告が解除された・ウィジェットが消えた
//   WarningAlarm.acknowledge(key)   確認した(タップ)。その警告が解除されるまで、その分のビープは止める。
//                                   同じ範囲(group)の警告もまとめて確認済みにする(操作のリンク)
//   WarningAlarm.acknowledgeAll()   鳴っているすべての警告を確認済みにする(ホーム画面・メニューの解除ボタン)
//   WarningAlarm.isSounding(key)    その警告でビープが鳴っているか(revision を読んでから呼ぶと束縛が更新される)
// 同じ種類のウィジェットの操作のリンク(全ページ・Android Auto 画面をまたいで):
//   joinNotice(group, key) / leaveNotice(group, key) / isNoticeOwner(group, key)
//       警告のポップアップ通知を出すのは、同じ範囲の中で 1 つだけ(最初に登録したもの)。同じ通知が重ならない
//   resetPeak(group, sourceKey)     最大・最小値のリセット(peakResetRequested で同じ範囲のメーターへ伝える)
// 警告・注意のポップアップ通知(メーターの種類ごとに 1 つ):
//   noticeReport(group, item)       メーターが今の状態(タイトル・本文・警告中か・出し方)を知らせる
//   noticeRemove(group)             通知をやめた(設定を変えた・ウィジェットが消えた)
//   種類(group)ごとに別の通知を出す。同じ種類のメーターが何台あっても、その種類の通知は 1 つ。
//   解除されたら、その間の最大値を 8 秒出してから消す
//   通知履歴: 途中経過(「現在 …」)の通知は履歴に残さない。解除されたときに、その間の最大値(最低値)と
//   続いた時間のまとめを 1 件だけ残す(通知をタップで消していても残す)
pragma Singleton
import QtQuick

QtObject {
    id: alarm

    /// ビープの間隔(ms)。Main.qml が設定(systemSound.alertInterval)を流し込む
    property int interval: 1400
    /// true なら「ずっと鳴らす」: beep() は出さず、鳴らしている警告がある間(soundingCount > 0)ずっと鳴らしてもらう
    /// (Main.qml が soundingCount を systemSound.alertActive へ流し、SystemSound がループ再生する)
    property bool continuous: false
    /// 登録が変わるたびに増える(QML の束縛が isSounding などを読み直すため)
    property int revision: 0
    /// 鳴らしている(確認されていない)警告の数。同じ種類のメーター(group が同じ)はいくつあっても 1 件と数える
    property int soundingCount: 0
    /// 鳴らしている警告の名前(新しい順)
    property var soundingTitles: []

    /// key → { title, acked }
    property var entries: ({})

    /// ビープを 1 回鳴らす合図(Main.qml が受けて鳴らす)
    signal beep()
    /// 注意音を 1 回鳴らす合図(Main.qml が受けて鳴らす。続けて来ても SystemSound が間引く)
    signal cautionBeep()
    /// メーターが注意値を超えたときに呼ぶ(注意音を 1 回)
    function caution() { cautionBeep() }

    function raise(key, title, group) {
        if (key === "" || entries[key] !== undefined) return
        const g = group || ""
        // 同じ範囲で消音中の警告があれば、これも消音で始める(片方だけ鳴り続けないように)
        let acked = false
        if (g !== "") {
            for (const k in entries) {
                if (entries[k].group === g && entries[k].acked) { acked = true; break }
            }
        }
        entries[key] = { title: title || "", acked: acked, at: Date.now(), group: g }
        update()
    }
    function clear(key) {
        if (entries[key] === undefined) return
        delete entries[key]
        update()
    }
    function acknowledge(key) {
        const e = entries[key]
        if (e === undefined) return
        let changed = false
        for (const k in entries) {
            const x = entries[k]
            if (!x.acked && (k === key || (e.group !== "" && x.group === e.group))) { x.acked = true; changed = true }
        }
        if (changed) update()
    }
    function acknowledgeAll() {
        let changed = false
        for (const k in entries) {
            if (!entries[k].acked) { entries[k].acked = true; changed = true }
        }
        if (changed) update()
    }
    function isActive(key) { return entries[key] !== undefined }
    function isSounding(key) { const e = entries[key]; return e !== undefined && !e.acked }

    // ---- ポップアップ通知を出すウィジェット(範囲ごとに 1 つ) ----
    /// group → [key](登録順。先頭が通知を出す)
    property var noticeMembers: ({})
    /// noticeMembers が変わるたびに増える
    property int noticeRevision: 0
    function joinNotice(group, key) {
        if (group === "" || key === "") return
        const list = noticeMembers[group] || []
        if (list.indexOf(key) >= 0) return
        noticeMembers[group] = list.concat([key])
        ++noticeRevision
    }
    function leaveNotice(group, key) {
        const list = noticeMembers[group]
        if (!list || list.indexOf(key) < 0) return
        noticeMembers[group] = list.filter(k => k !== key)
        ++noticeRevision
    }
    function isNoticeOwner(group, key) {
        const list = noticeMembers[group]
        return !list || list.length === 0 || list[0] === key
    }

    // ---- 警告・注意のポップアップ通知(メーターの種類ごとに 1 つ) ----
    // 種類(group)ごとに別の通知を出す。同じ種類のメーターがいくつあっても、その種類の通知は 1 つ
    readonly property int noticeHoldMs: 8000
    /// group → { title, text, level, warning(警告・注意中か), icon, mode, at, endAt(解除された時刻), id(通知の id),
    ///           startAt(警告・注意になった時刻), topLevel(その間でいちばん高い段階) }
    property var noticeItems: ({})
    /// 載っている件数(解除の表示中のものも含む)
    property int noticeCount: 0

    function noticeReport(group, item) {
        if (group === "") return
        const prev = noticeItems[group]
        // 新しく警告(注意)になった・注意 ⇄ 警告と段階が変わったときは、通知を出し直す(今の状態を知らせる)
        const fresh = item.warning && (!prev || !prev.warning || prev.level !== item.level)
        const recovered = !item.warning && prev !== undefined && prev.warning
        if (!item.warning && !prev) return   // 警告・注意になっていないものは出さない
        const started = item.warning && (!prev || !prev.warning)
        const startAt = started ? Date.now() : (prev && prev.startAt ? prev.startAt : Date.now())
        const topLevel = item.warning ? Math.max(item.level, started || !prev ? 0 : (prev.topLevel || 0))
                                      : (prev ? (prev.topLevel || prev.level) : item.level)
        noticeItems[group] = {
            title: item.title, text: item.text, level: item.level, warning: item.warning,
            icon: item.icon, mode: item.mode,
            at: fresh ? Date.now() : (prev ? prev.at : Date.now()),
            endAt: item.warning ? 0 : (recovered ? Date.now() : (prev ? prev.endAt : Date.now())),
            id: prev ? prev.id : -1,
            startAt: startAt, topLevel: topLevel
        }
        if (recovered) archiveEpisode(noticeItems[group])
        refreshOne(group, fresh || recovered, fresh)
        noticeCount = Object.keys(noticeItems).length
    }
    function noticeRemove(group) {
        const it = noticeItems[group]
        if (it === undefined) return
        if (it.id >= 0) notifications.dismiss(it.id)
        delete noticeItems[group]
        noticeCount = Object.keys(noticeItems).length
    }
    // 解除されたときに、その間のまとめ(最大値など)を通知履歴へ 1 件残す
    function archiveEpisode(it) {
        const sec = Math.max(1, Math.round((it.endAt - it.startAt) / 1000))
        const span = sec < 60 ? sec + " 秒間" : Math.floor(sec / 60) + " 分" + (sec % 60 > 0 ? " " + (sec % 60) + " 秒" : "") + "間"
        const text = (it.text !== "" ? it.text + " ・ " : "") + span
        notifications.addHistory(it.title, text, it.topLevel || it.level, it.icon)
    }
    function noticeShowing(group) { const it = noticeItems[group]; return it !== undefined && it.id >= 0 }

    // その種類の通知を出し直す・書き換える。restart: 表示時間を数え直す(新しい警告・注意・解除のとき)。
    // allowNew: 通知が出ていなければ新しく出す(新しい警告・注意のときだけ。消えた・消された通知は、次まで出さない)
    function refreshOne(group, restart, allowNew) {
        const it = noticeItems[group]
        if (it === undefined) return
        if (!it.warning && Date.now() - it.endAt >= noticeHoldMs) {
            // 解除の表示が終わった
            if (it.id >= 0) notifications.dismiss(it.id)
            delete noticeItems[group]
            return
        }
        // 「出し続ける」の警告中は消えない。それ以外は 8 秒
        const duration = it.warning && it.mode === "live" ? 0 : noticeHoldMs
        if (it.id >= 0) {
            if (notifications.update(it.id, it.title, it.text, it.level, restart ? duration : -1)) return
            it.id = -1   // 時間が来て消えた・タップで消された
        }
        // 途中経過は履歴に残さない(解除のときに archiveEpisode でまとめを残す)
        if (allowNew) it.id = notifications.show(it.title, it.text, it.level, it.icon, duration, false)
    }
    // 中身の更新と、解除の表示の期限切れの片付け
    property Timer noticeTicker: Timer {
        interval: 500
        repeat: true
        running: alarm.noticeCount > 0
        onTriggered: {
            for (const g of Object.keys(alarm.noticeItems)) alarm.refreshOne(g, false, false)
            alarm.noticeCount = Object.keys(alarm.noticeItems).length
        }
    }

    // ---- 最大・最小値のリセット ----
    signal peakResetRequested(string group, string sourceKey)
    function resetPeak(group, sourceKey) { if (group !== "") peakResetRequested(group, sourceKey) }

    function update() {
        const list = []
        for (const k in entries) {
            if (!entries[k].acked) list.push(entries[k])
        }
        list.sort((a, b) => b.at - a.at)
        // 同じ種類のメーターは 1 件にまとめる(新しいものを残す)
        const seen = {}
        const unique = list.filter(e => {
            if (e.group === "") return true
            if (seen[e.group]) return false
            seen[e.group] = true
            return true
        })
        soundingTitles = unique.map(e => e.title)
        soundingCount = unique.length
        ++revision
    }

    property Timer ticker: Timer {
        interval: alarm.interval
        repeat: true
        running: alarm.soundingCount > 0 && !alarm.continuous
        triggeredOnStart: true   // 最初の警告ではすぐ鳴らす。2 件目以降は今のリズムに合わせる
        onTriggered: alarm.beep()
    }
}
