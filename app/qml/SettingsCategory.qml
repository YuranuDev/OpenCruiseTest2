// 設定画面の「ジャンル」1 件ぶんの定義。SettingsScreen の categories に並べる。
//   SettingsCategory { icon: "tune"; title: "一般"; page: SettingsPageGeneral {} }
// icon は Material Icons のアイコン名、page には右側に表示するページ(SettingsPage を土台にした部品)を指定する。
import QtQuick

QtObject {
    property string icon: ""
    property string title: ""
    // 右側に表示するページ。選択されたときに生成される(未選択のジャンルは生成されない)
    property Component page: null
}
