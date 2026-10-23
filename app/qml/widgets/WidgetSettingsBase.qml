// ウィジェットの設定画面の土台。継承して、SettingsRow(+ SettingsChoice / SettingsSwitch / WSStepper / WSTextField)を並べる。
//   WidgetSettingsBase {
//       SettingsRow {
//           label: "枠"
//           SettingsChoice { model: ["カード", "なし"]; currentIndex: root.config.frame === "plain" ? 1 : 0
//                            onPicked: (i) => root.edit("frame", i === 1 ? "plain" : "card") }
//       }
//   }
// config は現在の設定(WidgetSettingsDialog が注入)。値を変えるときは edit(キー, 値) を呼ぶ(保存と反映は自動)。
import QtQuick
import OpenCruise

Column {
    id: root
    property var config: ({})
    signal edit(string key, var value)
    width: parent ? parent.width : implicitWidth
}
