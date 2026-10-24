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

    // ---- メーター(GaugeWidget)で測れる値の定義。種類ごとの defaultConfig の metric で選ぶ ----
    //   title / icon     既定の見出しとアイコン
    //   units            単位の候補(先頭が既定)。表示値 = 基本単位の値 × scale + offset
    //                    dec: 表示の小数桁 / step, stepDec: 設定の刻みと小数桁 / labelDiv: 目盛りの数字を割る値
    //   limitMin / limitMax / minSpan   設定できる最小値・最大値の範囲と、最小〜最大の最低の幅(基本単位)
    //   warnBelow        true なら「警告値以下」で警告(燃料など)
    //   warnMessage      警告メッセージの入力欄の例
    readonly property var gaugeSpecs: ({
        boost: { title: "ブースト", icon: "speed",
                 units: [{ id: "bar", label: "bar", scale: 1, dec: 2, step: 0.1, stepDec: 1 },
                         { id: "psi", label: "psi", scale: 14.5038, dec: 1, step: 1, stepDec: 0 }],
                 limitMin: -1.0, limitMax: 5.0, minSpan: 0.5,
                 minLabel: "最小値(負圧側)", minHint: "目盛りの左端。負圧を測れるよう、通常は 0 より小さくします",
                 warnMessage: "ブースト圧が高すぎます" },
        rpm:   { title: "回転数", icon: "av_timer",
                 units: [{ id: "rpm", label: "rpm", scale: 1, dec: 0, step: 500, stepDec: 0, labelDiv: 1000 }],
                 limitMin: 0, limitMax: 12000, minSpan: 1000, warnMessage: "回転数が高すぎます" },
        speed: { title: "速度", icon: "directions_car",
                 units: [{ id: "kmh", label: "km/h", scale: 1, dec: 0, step: 10, stepDec: 0 },
                         { id: "mph", label: "mph", scale: 0.621371, dec: 0, step: 5, stepDec: 0 }],
                 limitMin: 0, limitMax: 400, minSpan: 40, warnMessage: "速度に注意してください" },
        coolant: { title: "水温", icon: "thermostat",
                 units: [{ id: "c", label: "℃", scale: 1, dec: 0, step: 5, stepDec: 0 },
                         { id: "f", label: "℉", scale: 1.8, offset: 32, dec: 0, step: 5, stepDec: 0 }],
                 limitMin: -40, limitMax: 150, minSpan: 20, warnMessage: "水温が高すぎます" },
        fuel:  { title: "燃料", icon: "local_gas_station",
                 units: [{ id: "pct", label: "%", scale: 1, dec: 0, step: 5, stepDec: 0 }],
                 limitMin: 0, limitMax: 100, minSpan: 20, warnBelow: true, warnMessage: "燃料が残りわずかです" }
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
            type: "turbo", genre: "vehicle", name: "ターボ圧計", icon: "speed",
            description: "ブースト圧のアナログ+デジタルメーター(警告値あり)",
            component: gaugeComp, settings: gaugeSettings,
            defaultSize: { w: 4, h: 5 }, minSize: { w: 2, h: 2 }, maxSize: { w: 8, h: 6 },
            // 値は bar 基準で保存する(単位を切り替えても警告値などがずれない)
            defaultConfig: gaugeConfig({ metric: "boost", unit: "bar", min: -1.0, max: 2.0,
                                         warnEnabled: true, warn: 1.6, warnMessage: "ブースト圧が高すぎます" }),
            dragStart: "hold", mock: true
        },
        {
            type: "tacho", genre: "vehicle", name: "タコメーター", icon: "av_timer",
            description: "エンジン回転数のメーター(レッドゾーンの警告あり)",
            component: gaugeComp, settings: gaugeSettings,
            defaultSize: { w: 4, h: 5 }, minSize: { w: 2, h: 2 }, maxSize: { w: 8, h: 6 },
            defaultConfig: gaugeConfig({ metric: "rpm", unit: "rpm", min: 0, max: 8000, dialStyle: "sport",
                                         warnEnabled: true, warn: 6500, warnMessage: "回転数が高すぎます" }),
            dragStart: "hold", mock: true
        },
        {
            type: "speedGauge", genre: "vehicle", name: "スピードメーター", icon: "directions_car",
            description: "車速のメーター(km/h・mph)",
            component: gaugeComp, settings: gaugeSettings,
            defaultSize: { w: 4, h: 5 }, minSize: { w: 2, h: 2 }, maxSize: { w: 8, h: 6 },
            defaultConfig: gaugeConfig({ metric: "speed", unit: "kmh", min: 0, max: 180,
                                         warnEnabled: false, warn: 120, warnMessage: "速度に注意してください" }),
            dragStart: "hold", mock: true
        },
        {
            type: "coolant", genre: "vehicle", name: "水温計", icon: "thermostat",
            description: "冷却水の温度のメーター(オーバーヒートの警告あり)",
            component: gaugeComp, settings: gaugeSettings,
            defaultSize: { w: 3, h: 3 }, minSize: { w: 2, h: 2 }, maxSize: { w: 8, h: 6 },
            defaultConfig: gaugeConfig({ metric: "coolant", unit: "c", min: 40, max: 130,
                                         dialStyle: "minimal", startAngle: -90, endAngle: 90,
                                         warnEnabled: true, warn: 105, warnMessage: "水温が高すぎます" }),
            dragStart: "hold", mock: true
        },
        {
            type: "fuel", genre: "vehicle", name: "燃料計", icon: "local_gas_station",
            description: "燃料の残量のメーター(残りわずかの警告あり)",
            component: gaugeComp, settings: gaugeSettings,
            defaultSize: { w: 3, h: 3 }, minSize: { w: 2, h: 2 }, maxSize: { w: 8, h: 6 },
            defaultConfig: gaugeConfig({ metric: "fuel", unit: "pct", min: 0, max: 100,
                                         dialStyle: "minimal", startAngle: -90, endAngle: 90,
                                         warnEnabled: true, warn: 15, warnMessage: "燃料が残りわずかです" }),
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
        }
    ]

    // ---- 初期配置(従来の「左に時計カード、右にウィジェット領域」を再現し、右側に連携系を並べる) ----
    readonly property var defaultLayout: [
        { type: "greeting",    col: 0, row: 0, w: 4, h: 1 },
        { type: "clock",       col: 0, row: 1, w: 4, h: 5 },
        { type: "turbo",       col: 4, row: 0, w: 4, h: 6 },
        { type: "phone",       col: 8, row: 0, w: 4, h: 3 },
        { type: "phoneNotice", col: 8, row: 3, w: 4, h: 3 }
    ]

    function find(type) {
        for (let i = 0; i < types.length; ++i) {
            if (types[i].type === type) return types[i]
        }
        return null
    }

    function ofGenre(genreId) {
        return types.filter(t => t.genre === genreId)
    }
}
