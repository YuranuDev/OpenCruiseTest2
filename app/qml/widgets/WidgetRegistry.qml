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
    property Component turboComp: Component { TurboGaugeWidget {} }
    property Component turboSettings: Component { TurboGaugeSettings {} }
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
            component: turboComp, settings: turboSettings,
            defaultSize: { w: 4, h: 5 }, minSize: { w: 3, h: 3 }, maxSize: { w: 8, h: 6 },
            // 値は bar 基準で保存する(単位を切り替えても警告値などがずれない)
            defaultConfig: { style: "both", dialStyle: "classic", unit: "bar", min: -1.0, max: 2.0,
                             startAngle: -135, endAngle: 135, autoLabelPosition: true,
                             needleTail: true, hubSize: 16, hubColor: "panel", needleColor: "theme",
                             showIcon: true, warnEnabled: true, warn: 1.6, warnMessage: "ブースト圧が高すぎます" },
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
