// ウィジェットの設定画面のジャンル(タブ 1 つぶん)。WidgetSettingsBase の直下に置き、中に SettingsRow を並べる。
//   WidgetSettingsGroup {
//       title: "警告"; icon: "warning"
//       active: root.config.warnEnabled === true   // タブに「オン」の印を出す(任意)
//       SettingsRow { ... }
//   }
// 設定ダイアログの上のタブで切り替え、選んだジャンルだけを表示する(タイトルがジャンルの見分けに使われるので、同じ画面の中で重ならないようにする)。
// available: false にすると、そのジャンルのタブを出さない(例: デジタル表示のときの「目盛り・針」)。
import QtQuick

Column {
    readonly property bool isSettingsGroup: true
    property string title: ""
    property string icon: "tune"
    property bool active: false
    property bool available: true
    // 選ばれているジャンルか(WidgetSettingsBase の effectiveKey と比べる)
    readonly property bool current: parent !== null && parent.effectiveKey !== undefined && parent.effectiveKey === title

    width: parent ? parent.width : implicitWidth
    visible: current && available
}
