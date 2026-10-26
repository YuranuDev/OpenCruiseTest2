// ウィジェットの種類を登録する唯一の場所(シングルトン)。新しいウィジェットを足す手順:
//   1. WidgetBase を継承した <名前>Widget.qml を作る(中身だけ書く)
//   2. 設定が要るなら WidgetSettingsBase を継承した <名前>Settings.qml を作る(設定が不要なら作らない)
//   3. この ファイルに Component を 2 つ(本体・設定)と、types への 1 項目を足す
//   4. app/CMakeLists.txt の QML_FILES に上の qml を足す
// 配置・ドラッグ・スナップ・保存・設定ダイアログ・追加パネルは、ここの定義だけで自動的に対応する。
//
// types の各項目:
//   type          保存・識別用のキー(変更すると保存済みの配置から外れるので、決めたら変えない)
//   genre         genres の id。追加パネルの分類になる
//   name / icon / description   追加パネルでの表示(icon は Material Icons 名)
//   component     本体(WidgetBase を継承したもの)
//   settings      設定画面の中身(WidgetSettingsBase を継承したもの)。null なら設定なし
//                 → ダブルタップは何もしない(または本体の doubleTapAction が "custom" なら本体が受ける)
//   defaultSize / minSize / maxSize   グリッド(12 × 6 マス)でのマス数
//   defaultConfig 設定の既定値。保存値はこれに重ねられる(キーを増やしても古い保存データはそのまま動く)
//   dragStart     "hold"(長押しで持ち上げ。既定) / "immediate"(少し動かすと持ち上げ)
//   mock          true なら、現状はモックデータで動いている(追加パネルに「モック」と表示)
//   hidden        true なら追加パネルのジャンルの一覧に出さない(グラフは「車載連携」のグラフ切り替えから、
//                 計測値ごとの項目として出す。graphEntries())
pragma Singleton
import QtQuick
import OpenCruise

QtObject {
    id: registry

    // ---- ジャンル(追加パネルの分類) ----
    readonly property var genres: [
        { id: "clock",        name: "時計・あいさつ",     icon: "schedule" },
        { id: "vehicle",      name: "車載連携",           icon: "directions_car" },
        { id: "androidauto",  name: "Android Auto連携",   icon: "smartphone" },
        { id: "notification", name: "通知連携",           icon: "notifications" }
    ]

    // ---- 本体と設定画面 ----
    property Component clockComp: Component { ClockWidget {} }
    property Component clockSettings: Component { ClockSettings {} }
    property Component greetingComp: Component { GreetingWidget {} }
    property Component greetingSettings: Component { GreetingSettings {} }
    property Component gaugeComp: Component { GaugeWidget {} }        // メーター系(ターボ圧計・タコメーターなど)で共通
    property Component gaugeSettings: Component { GaugeSettings {} }
    property Component phoneComp: Component { PhoneStatusWidget {} }
    property Component phoneSettings: Component { PhoneStatusSettings {} }
    property Component noticeComp: Component { PhoneNoticeWidget {} }
    property Component noticeSettings: Component { PhoneNoticeSettings {} }
    property Component callComp: Component { PhoneCallWidget {} }
    property Component callSettings: Component { PhoneCallSettings {} }
    property Component playingComp: Component { NowPlayingWidget {} }
    property Component playingSettings: Component { NowPlayingSettings {} }
    property Component navigationComp: Component { NavigationWidget {} }
    property Component navigationSettings: Component { NavigationSettings {} }
    property Component graphComp: Component { GraphWidget {} }        // グラフ(計測値は config.metric)
    property Component graphSettings: Component { GraphSettings {} }

    // ---- メーター(GaugeWidget)で測れる値の定義。種類ごとの defaultConfig の metric で選ぶ ----
    //   title / icon     既定の見出しとアイコン
    //   units            単位の候補(先頭が既定)。表示値 = 基本単位の値 × scale + offset
    //                    dec: 表示の小数桁 / step, stepDec: 設定の刻みと小数桁 / labelDiv: 目盛りの数字を割る値
    //   limitMin / limitMax / minSpan   設定できる最小値・最大値の範囲と、最小〜最大の最低の幅(基本単位)
    //   warnBelow        true なら「警告値以下」で警告(燃料など)
    //   warnMessage      警告メッセージの入力欄の例
    //   negLabel / posLabel  0 をまたぐ範囲で、マイナス側・プラス側の目盛りを分けるときの呼び名(ターボ圧の負圧・正圧など)
    readonly property var gaugeSpecs: ({
        boost: { title: "ブースト", icon: "mdi:car-turbocharger",
                 units: [{ id: "bar", label: "bar", scale: 1, dec: 2, step: 0.1, stepDec: 1 },
                         { id: "psi", label: "psi", scale: 14.5038, dec: 1, step: 1, stepDec: 0 }],
                 limitMin: -1.0, limitMax: 5.0, minSpan: 0.5,
                 minLabel: "最小値(負圧側)", minHint: "目盛りの左端。負圧を測れるよう、通常は 0 より小さくします",
                 negLabel: "負圧", posLabel: "正圧",
                 warnMessage: "ブースト圧が高すぎます" },
        rpm:   { title: "回転数", icon: "mdi:gauge",
                 units: [{ id: "rpm", label: "rpm", scale: 1, dec: 0, step: 500, stepDec: 0, labelDiv: 1000 }],
                 limitMin: 0, limitMax: 12000, minSpan: 1000, warnMessage: "回転数が高すぎます" },
        speed: { title: "速度", icon: "mdi:speedometer",
                 units: [{ id: "kmh", label: "km/h", scale: 1, dec: 0, step: 10, stepDec: 0 },
                         { id: "mph", label: "mph", scale: 0.621371, dec: 0, step: 5, stepDec: 0 }],
                 limitMin: 0, limitMax: 400, minSpan: 40, warnMessage: "速度に注意してください" },
        coolant: { title: "水温", icon: "mdi:coolant-temperature",
                 units: [{ id: "c", label: "℃", scale: 1, dec: 0, step: 5, stepDec: 0 },
                         { id: "f", label: "℉", scale: 1.8, offset: 32, dec: 0, step: 5, stepDec: 0 }],
                 limitMin: -40, limitMax: 150, minSpan: 20, warnMessage: "水温が高すぎます" },
        fuel:  { title: "燃料", icon: "mdi:gas-station",
                 units: [{ id: "pct", label: "%", scale: 1, dec: 0, step: 5, stepDec: 0 }],
                 limitMin: 0, limitMax: 100, minSpan: 20, warnBelow: true, warnMessage: "燃料が残りわずかです" },
        oilTemp: { title: "油温", icon: "mdi:oil-temperature",
                 units: [{ id: "c", label: "℃", scale: 1, dec: 0, step: 5, stepDec: 0 },
                         { id: "f", label: "℉", scale: 1.8, offset: 32, dec: 0, step: 5, stepDec: 0 }],
                 limitMin: -40, limitMax: 180, minSpan: 20, warnMessage: "油温が高すぎます" },
        oilPressure: { title: "油圧", icon: "mdi:oil",
                 units: [{ id: "bar", label: "bar", scale: 1, dec: 1, step: 0.5, stepDec: 1 },
                         { id: "psi", label: "psi", scale: 14.5038, dec: 0, step: 5, stepDec: 0 },
                         { id: "kpa", label: "kPa", scale: 100, dec: 0, step: 50, stepDec: 0 }],
                 limitMin: 0, limitMax: 10, minSpan: 1, warnBelow: true, warnMessage: "油圧が低すぎます" },
        voltage: { title: "電圧", icon: "mdi:car-battery",
                 units: [{ id: "v", label: "V", scale: 1, dec: 1, step: 0.5, stepDec: 1 }],
                 limitMin: 8, limitMax: 18, minSpan: 2, warnBelow: true, warnMessage: "電圧が低下しています" }
    })

    // メーターの共通の既定値に、種類ごとの値を重ねる
    function gaugeConfig(extra) {
        return Object.assign({ style: "both", dialStyle: "classic", startAngle: -135, endAngle: 135,
                               autoLabelPosition: true, needleTail: true, hubSize: 16, hubColor: "panel",
                               needleColor: "theme", showIcon: true }, extra)
    }

    // ---- 種類の一覧 ----
    readonly property var types: [
        {
            type: "greeting", genre: "clock", name: "あいさつ", icon: "waving_hand",
            description: "時刻に応じたあいさつ(ユーザー名つき)",
            component: greetingComp, settings: greetingSettings,
            defaultSize: { w: 4, h: 1 }, minSize: { w: 2, h: 1 }, maxSize: { w: 12, h: 2 },
            defaultConfig: { frame: "card", align: "left", showName: true },
            dragStart: "hold", mock: false
        },
        {
            type: "clock", genre: "clock", name: "時計", icon: "schedule",
            description: "時刻と日付",
            component: clockComp, settings: clockSettings,
            defaultSize: { w: 4, h: 5 }, minSize: { w: 2, h: 1 }, maxSize: { w: 12, h: 6 },
            defaultConfig: { frame: "card", align: "left", showDate: true },
            dragStart: "hold", mock: false
        },
        {
            type: "turbo", genre: "vehicle", name: "ターボ圧計", icon: "mdi:car-turbocharger",
            description: "ブースト圧のアナログ+デジタルメーター(警告値あり)",
            component: gaugeComp, settings: gaugeSettings,
            defaultSize: { w: 4, h: 5 }, minSize: { w: 2, h: 2 }, maxSize: { w: 8, h: 6 },
            // 値は bar 基準で保存する(単位を切り替えても警告値などがずれない)
            defaultConfig: gaugeConfig({ metric: "boost", unit: "bar", min: -1.0, max: 2.0,
                                         warnEnabled: true, warn: 1.6, warnMessage: "ブースト圧が高すぎます" }),
            dragStart: "hold", mock: true
        },
        {
            type: "tacho", genre: "vehicle", name: "タコメーター", icon: "mdi:gauge",
            description: "エンジン回転数のメーター(レッドゾーンの警告あり)",
            component: gaugeComp, settings: gaugeSettings,
            defaultSize: { w: 4, h: 5 }, minSize: { w: 2, h: 2 }, maxSize: { w: 8, h: 6 },
            defaultConfig: gaugeConfig({ metric: "rpm", unit: "rpm", min: 0, max: 8000, dialStyle: "marker",
                                         warnEnabled: true, warn: 6500, warnMessage: "回転数が高すぎます" }),
            dragStart: "hold", mock: true
        },
        {
            type: "speedGauge", genre: "vehicle", name: "スピードメーター", icon: "mdi:speedometer",
            description: "車速のメーター(km/h・mph)",
            component: gaugeComp, settings: gaugeSettings,
            defaultSize: { w: 4, h: 5 }, minSize: { w: 2, h: 2 }, maxSize: { w: 8, h: 6 },
            defaultConfig: gaugeConfig({ metric: "speed", unit: "kmh", min: 0, max: 180,
                                         warnEnabled: false, warn: 120, warnMessage: "速度に注意してください" }),
            dragStart: "hold", mock: true
        },
        {
            type: "coolant", genre: "vehicle", name: "水温計", icon: "mdi:coolant-temperature",
            description: "冷却水の温度のメーター(オーバーヒートの警告あり)",
            component: gaugeComp, settings: gaugeSettings,
            defaultSize: { w: 3, h: 3 }, minSize: { w: 2, h: 2 }, maxSize: { w: 8, h: 6 },
            defaultConfig: gaugeConfig({ metric: "coolant", unit: "c", min: 40, max: 130,
                                         dialStyle: "minimal", startAngle: -90, endAngle: 90,
                                         warnEnabled: true, warn: 105, warnMessage: "水温が高すぎます" }),
            dragStart: "hold", mock: true
        },
        {
            type: "fuel", genre: "vehicle", name: "燃料計", icon: "mdi:gas-station",
            description: "燃料の残量のメーター(残りわずかの警告あり)",
            component: gaugeComp, settings: gaugeSettings,
            defaultSize: { w: 3, h: 3 }, minSize: { w: 2, h: 2 }, maxSize: { w: 8, h: 6 },
            defaultConfig: gaugeConfig({ metric: "fuel", unit: "pct", min: 0, max: 100,
                                         dialStyle: "minimal", startAngle: -90, endAngle: 90,
                                         warnEnabled: true, warn: 15, warnMessage: "燃料が残りわずかです" }),
            dragStart: "hold", mock: true
        },
        {
            type: "oilTemp", genre: "vehicle", name: "油温計", icon: "mdi:oil-temperature",
            description: "エンジンオイルの温度のメーター(高温の警告あり)",
            component: gaugeComp, settings: gaugeSettings,
            defaultSize: { w: 3, h: 3 }, minSize: { w: 2, h: 2 }, maxSize: { w: 8, h: 6 },
            defaultConfig: gaugeConfig({ metric: "oilTemp", unit: "c", min: 50, max: 150,
                                         dialStyle: "minimal", startAngle: -90, endAngle: 90,
                                         warnEnabled: true, warn: 130, warnMessage: "油温が高すぎます" }),
            dragStart: "hold", mock: true
        },
        {
            type: "oilPressure", genre: "vehicle", name: "油圧計", icon: "mdi:oil",
            description: "エンジンオイルの圧力のメーター(低下の警告あり)",
            component: gaugeComp, settings: gaugeSettings,
            defaultSize: { w: 3, h: 3 }, minSize: { w: 2, h: 2 }, maxSize: { w: 8, h: 6 },
            defaultConfig: gaugeConfig({ metric: "oilPressure", unit: "bar", min: 0, max: 8,
                                         dialStyle: "minimal", startAngle: -90, endAngle: 90,
                                         warnEnabled: true, warn: 0.8, warnMessage: "油圧が低すぎます" }),
            dragStart: "hold", mock: true
        },
        {
            type: "voltage", genre: "vehicle", name: "電圧計", icon: "mdi:car-battery",
            description: "バッテリー・電装系の電圧のメーター(低下の警告あり)",
            component: gaugeComp, settings: gaugeSettings,
            defaultSize: { w: 3, h: 3 }, minSize: { w: 2, h: 2 }, maxSize: { w: 8, h: 6 },
            defaultConfig: gaugeConfig({ metric: "voltage", unit: "v", min: 10, max: 16,
                                         dialStyle: "minimal", startAngle: -90, endAngle: 90,
                                         warnEnabled: true, warn: 12.0, warnMessage: "電圧が低下しています" }),
            dragStart: "hold", mock: true
        },
        {
            type: "navigation", genre: "androidauto", name: "ナビ案内", icon: "navigation",
            description: "Android Auto の次の曲がり角までの距離・方向・道路名と、その次の案内",
            component: navigationComp, settings: navigationSettings,
            defaultSize: { w: 4, h: 2 }, minSize: { w: 3, h: 2 }, maxSize: { w: 8, h: 4 },
            defaultConfig: { frame: "card", layout: "standard", distanceUnit: "auto",
                             showRoad: true, showNext: true, nearHighlight: 100 },
            dragStart: "hold", mock: false
        },
        {
            type: "phone", genre: "androidauto", name: "スマホ状態", icon: "smartphone",
            description: "スマートフォンのバッテリー残量・電波・接続状態",
            component: phoneComp, settings: phoneSettings,
            defaultSize: { w: 4, h: 3 }, minSize: { w: 3, h: 2 }, maxSize: { w: 8, h: 4 },
            defaultConfig: { showRemaining: true, showSignal: true, lowThreshold: 20,
                             lowMessage: "スマホの充電が残りわずかです" },
            dragStart: "hold", mock: true
        },
        {
            type: "phoneNotice", genre: "notification", name: "スマホ通知", icon: "notifications",
            description: "スマートフォンからの通知(内容に応じたメッセージを設定可能)",
            component: noticeComp, settings: noticeSettings,
            defaultSize: { w: 4, h: 3 }, minSize: { w: 3, h: 2 }, maxSize: { w: 8, h: 6 },
            // templates: カテゴリごとの表示文。{text} が通知文に置き換わる
            defaultConfig: { mode: "list", maxItems: 3, showIcon: true, showOther: true,
                             tplCall: "{text}", tplMessage: "{text}", tplNavigation: "{text}", tplOther: "{text}" },
            dragStart: "hold", mock: true
        },
        {
            type: "phoneCall", genre: "androidauto", name: "通話", icon: "call",
            description: "スマートフォンの着信・通話中・保留の状態(相手の名前・通話時間)",
            component: callComp, settings: callSettings,
            defaultSize: { w: 4, h: 3 }, minSize: { w: 3, h: 2 }, maxSize: { w: 8, h: 5 },
            defaultConfig: { showNumber: true, blink: true },
            dragStart: "hold", mock: true
        },
        {
            type: "nowPlaying", genre: "androidauto", name: "再生中", icon: "music_note",
            description: "スマートフォンで再生中の曲(曲名・アーティスト・再生位置)",
            component: playingComp, settings: playingSettings,
            defaultSize: { w: 4, h: 3 }, minSize: { w: 3, h: 2 }, maxSize: { w: 8, h: 5 },
            defaultConfig: { showAlbum: true, showProgress: true },
            dragStart: "hold", mock: true
        },
        {
            type: "graph", genre: "vehicle", name: "グラフ", icon: "show_chart", hidden: true,
            description: "計測値の直近の変化を折れ線グラフで表示",
            component: graphComp, settings: graphSettings,
            defaultSize: { w: 4, h: 3 }, minSize: { w: 3, h: 2 }, maxSize: { w: 12, h: 6 },
            defaultConfig: { metric: "boost", windowSec: 60, autoScale: false, fill: true, showStats: true },
            dragStart: "hold", mock: true
        }
    ]

    // ---- グラフ(追加パネルの「車載連携」→「グラフ」) ----
    // 計測値ごとに、メーターの既定(範囲・警告値)を引き継いだグラフの項目を作る
    function graphConfigFor(metric) {
        for (let i = 0; i < types.length; ++i) {
            const c = types[i].defaultConfig
            if (types[i].component === gaugeComp && c && c.metric === metric) {
                return { metric: metric, unit: c.unit, min: c.min, max: c.max, warnEnabled: c.warnEnabled === true,
                         warn: c.warn, windowSec: 60, autoScale: false, fill: true, showStats: true }
            }
        }
        return { metric: metric }
    }
    function graphEntries() {
        const list = []
        for (let i = 0; i < types.length; ++i) {
            const t = types[i]
            if (t.component !== gaugeComp || !t.defaultConfig) continue
            const spec = gaugeSpecs[t.defaultConfig.metric]
            if (!spec) continue
            list.push({ type: "graph", name: spec.title + "のグラフ", icon: spec.icon, mock: t.mock,
                        description: "直近の" + spec.title + "の変化を折れ線グラフで表示(最大・最小・平均、警告線あり)",
                        config: graphConfigFor(t.defaultConfig.metric) })
        }
        return list
    }

    // ---- 初期配置(従来の「左に時計カード、右にウィジェット領域」を再現し、右側に連携系を並べる) ----
    readonly property var defaultLayout: [
        { type: "greeting",    col: 0, row: 0, w: 4, h: 1 },
        { type: "clock",       col: 0, row: 1, w: 4, h: 5 },
        { type: "turbo",       col: 4, row: 0, w: 4, h: 6 },
        { type: "phone",       col: 8, row: 0, w: 4, h: 3 },
        { type: "phoneNotice", col: 8, row: 3, w: 4, h: 3 }
    ]

    // ---- 同じ種類のウィジェットでリンクする(共通にする)設定: 通知・警告まわり ----
    // どれか 1 つで変えると、全ページ・Android Auto 画面の同じ種類のウィジェットにも同じ値が入る(WidgetArea)。
    // グラフは計測値ごとに別の種類として扱う(ブーストのグラフ同士だけがリンクする)
    readonly property var gaugeLinkedKeys: ["warnEnabled", "warn", "showWarnMessage", "warnBeep",
                                            "warnPopupMode", "warnPopup", "warnPopupDetail", "warnMessage"]
    readonly property var graphLinkedKeys: ["warnEnabled", "warn"]
    readonly property var phoneLinkedKeys: ["lowThreshold", "showLowMessage", "lowMessage"]
    readonly property var noticeLinkedKeys: ["tplCall", "tplMessage", "tplNavigation", "tplOther"]
    function linkedKeys(type) {
        const def = find(type)
        if (!def) return []
        if (def.settings === gaugeSettings) return gaugeLinkedKeys
        if (def.settings === graphSettings) return graphLinkedKeys
        if (def.settings === phoneSettings) return phoneLinkedKeys
        if (def.settings === noticeSettings) return noticeLinkedKeys
        return []
    }
    function isLinked(type, key) { return linkedKeys(type).indexOf(key) >= 0 }
    // 種類をまたいで、すべてのメーターで共通にする設定(今は無し。通知の設定も種類ごと)。
    // ここに足した項目は、計測値に関係なくすべてのメーターでリンクする
    readonly property var gaugeSharedKeys: []
    // リンクする範囲の名前(種類。グラフは計測値まで)
    function linkGroup(type, config) {
        return type === "graph" ? type + ":" + ((config && config.metric) || "") : type
    }
    // 設定項目ごとのリンクの範囲(メーターの通知の出し方は、メーターすべて)
    function linkGroupFor(type, config, key) {
        const def = find(type)
        if (def && def.settings === gaugeSettings && gaugeSharedKeys.indexOf(key) >= 0) return "gauges"
        return linkGroup(type, config)
    }
    // リンクしている設定の今の値(範囲の名前 → { key: value })。新しく足したウィジェットはこれを引き継ぐ
    property var linkedValues: ({})
    // 設定が変わった(WidgetArea が受けて、同じ範囲のほかのウィジェットに入れる)。save: false は入力中の仮の表示
    signal linkedChanged(string group, string key, var value, string sourceWid, bool save)
    function rememberLinked(group, key, value, overwrite) {
        const cur = linkedValues[group] || {}
        if (!overwrite && cur[key] !== undefined) return
        cur[key] = value
        linkedValues[group] = cur
    }
    function publishLinked(type, config, key, value, sourceWid, save) {
        if (!isLinked(type, key)) return
        const group = linkGroupFor(type, config, key)
        if (save) rememberLinked(group, key, value, true)
        linkedChanged(group, key, value, sourceWid, save)
    }
    // 新しいウィジェットの設定に、リンクしている今の値を重ねる
    function withLinked(type, config) {
        const keys = linkedKeys(type)
        const out = Object.assign({}, config)
        for (const k of keys) {
            const vals = linkedValues[linkGroupFor(type, config, k)]
            if (vals && vals[k] !== undefined) out[k] = vals[k]
        }
        return out
    }

    function find(type) {
        for (let i = 0; i < types.length; ++i) {
            if (types[i].type === type) return types[i]
        }
        return null
    }

    function ofGenre(genreId) {
        return types.filter(t => t.genre === genreId && t.hidden !== true)
    }
}
