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
    // 選ばれているジャンルか。WidgetSettingsBase が書き換える(束縛にはしない: 画面を閉じて部品を壊している途中に
    // 表示・非表示が切り替わると、壊れかけの行の寸法が計算し直されて警告が大量に出るため)
    property bool current: false

    width: parent ? parent.width : implicitWidth
    visible: current && available

    // 土台(WidgetSettingsBase)に自分を登録する(タブの一覧はこの登録から作る)
    Component.onCompleted: if (parent && parent.registerGroup) parent.registerGroup(this)
}
