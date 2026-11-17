// 設定画面の「ジャンル」1 件ぶんの定義。SettingsScreen の categories に並べる。
//   SettingsCategory { group: "display"; icon: "monitor"; title: "画面"; description: "明るさ・回転"; page: SettingsPageDisplay {} }
// group は SettingsScreen の groups の id(左の一覧の見出しと、ページの上の「どこにいるか」の表示に使う)。
// icon は Material Icons のアイコン名、description は一覧の名前の下に小さく出す中身の例、
// page には右側に表示するページ(SettingsPage を土台にした部品)を指定する。
import QtQuick

QtObject {
    property string group: ""
    property string icon: ""
    property string title: ""
    property string description: ""
    // 右側に表示するページ。選択されたときに生成される(未選択のジャンルは生成されない)
    property Component page: null
}
