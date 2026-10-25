// 警告音(ビープ)の鳴らし元(シングルトン)。メーターなど、しきい値を超えたウィジェットはここへ登録するだけで、
// 自分では音を鳴らさない。登録が 1 つ以上あり、確認(消音)されていないものがある間だけ、一定の間隔で beep() を出す。
// 音は Main.qml が beep() を受けて systemSound.play("alert") で鳴らす(鳴らす場所は 1 か所だけ)。
// 複数のウィジェットが同時に警告しても、ビープは 1 つのリズムで鳴り、重ならない。
//
//   WarningAlarm.raise(key, title)  警告を登録する(key はウィジェットごとに一意。同じ key は 1 件)
//   WarningAlarm.clear(key)         警告が解除された・ウィジェットが消えた
//   WarningAlarm.acknowledge(key)   確認した(タップ)。その警告が解除されるまで、その分のビープは止める
//   WarningAlarm.isSounding(key)    その警告でビープが鳴っているか(revision を読んでから呼ぶと束縛が更新される)
pragma Singleton
import QtQuick

QtObject {
    id: alarm

    /// ビープの間隔(ms)。Main.qml が設定(systemSound.alertInterval)を流し込む
    property int interval: 1400
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

    function raise(key, title) {
        if (key === "" || entries[key] !== undefined) return
        entries[key] = { title: title || "", acked: false, at: Date.now() }
        update()
    }
    function clear(key) {
        if (entries[key] === undefined) return
        delete entries[key]
        update()
    }
    function acknowledge(key) {
        const e = entries[key]
        if (e === undefined || e.acked) return
        e.acked = true
        update()
    }
    function isActive(key) { return entries[key] !== undefined }
    function isSounding(key) { const e = entries[key]; return e !== undefined && !e.acked }

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
        running: alarm.soundingCount > 0
        triggeredOnStart: true   // 最初の警告ではすぐ鳴らす。2 件目以降は今のリズムに合わせる
        onTriggered: alarm.beep()
    }
}
