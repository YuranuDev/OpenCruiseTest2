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
    /// 鳴らしている(確認されていない)警告の数
    property int soundingCount: 0
    /// 鳴らしている警告の名前(新しい順)
    property var soundingTitles: []

    /// key → { title, acked }
    property var entries: ({})

    /// ビープを 1 回鳴らす合図(Main.qml が受けて鳴らす)
    signal beep()

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

    // ---- 最大・最小値のリセット ----
    signal peakResetRequested(string group, string sourceKey)
    function resetPeak(group, sourceKey) { if (group !== "") peakResetRequested(group, sourceKey) }

    function update() {
        const list = []
        for (const k in entries) {
            if (!entries[k].acked) list.push(entries[k])
        }
        list.sort((a, b) => b.at - a.at)
        soundingTitles = list.map(e => e.title)
        soundingCount = list.length
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
