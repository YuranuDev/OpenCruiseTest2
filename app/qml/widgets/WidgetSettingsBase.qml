// ウィジェットの設定画面の土台。継承して、SettingsRow(+ SettingsChoice / SettingsSwitch / WSStepper / WSTextField)を並べる。
//   WidgetSettingsBase {
//       SettingsRow {
//           label: "配置"
//           SettingsChoice { model: ["左寄せ", "中央"]; currentIndex: root.config.align === "center" ? 1 : 0
//                            onPicked: (i) => root.edit("align", i === 1 ? "center" : "left") }
//       }
// 「枠」「上部タイトル」「サイズ」は全ウィジェット共通で、WidgetSettingsDialog が出すので、ここには書かない。
//   }
// config は現在の設定(WidgetSettingsDialog が注入)。値を変えるときは edit(キー, 値) を呼ぶ(保存と反映は自動)。
// 文字の入力中は preview(キー, 値) で、保存せずにウィジェットへだけすぐ反映できる(WSTextField の changing で使う)。
import QtQuick
import OpenCruise

Column {
    id: root
    property var config: ({})
    signal edit(string key, var value)
    signal preview(string key, var value)
    width: parent ? parent.width : implicitWidth
}
