// ウィジェットの設定画面の土台。継承して、SettingsRow(+ SettingsChoice / SettingsSwitch / WSStepper / WSTextField)を並べる。
//   WidgetSettingsBase {
//       SettingsRow {
//           label: "配置"
//           SettingsChoice { model: ["左寄せ", "中央"]; currentIndex: root.config.align === "center" ? 1 : 0
//                            onPicked: (i) => root.edit("align", i === 1 ? "center" : "left") }
//       }
//   }
// 項目が多いときは、WidgetSettingsGroup でジャンルに分ける(設定ダイアログの上にタブが出て、選んだジャンルだけを表示する)。
//   WidgetSettingsBase {
//       WidgetSettingsGroup { title: "表示"; icon: "tune"; SettingsRow { ... } }
//       WidgetSettingsGroup { title: "警告"; icon: "warning"; active: root.config.warnEnabled === true; SettingsRow { ... } }
//   }
// ジャンルに分けるときは、すべての行をどれかの WidgetSettingsGroup に入れる(入れていない行は、どのタブでも表示される)。
// ジャンルに分けないときは、全体が 1 つのタブ(mainTitle)になる。
// 「枠」「上部タイトル」「サイズ」は全ウィジェット共通で、WidgetSettingsDialog が「枠・サイズ」タブに出すので、ここには書かない。
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

    // ジャンルに分けないときのタブの名前とアイコン
    property string mainTitle: "表示"
    property string mainIcon: "tune"

    // 選ばれているジャンル(WidgetSettingsDialog が設定する。WidgetSettingsGroup の title)
    property string currentKey: ""

    // タブの一覧: [{ key, title, icon, active }]
    readonly property var tabs: {
        const list = []
        for (let i = 0; i < children.length; ++i) {
            const c = children[i]
            if (c && c.isSettingsGroup === true && c.available)
                list.push({ key: c.title, title: c.title, icon: c.icon, active: c.active })
        }
        if (list.length === 0) list.push({ key: "", title: mainTitle, icon: mainIcon, active: false })
        return list
    }
    // 実際に表示するジャンル(選ばれたものが出せないときは先頭)
    readonly property string effectiveKey: {
        for (let i = 0; i < tabs.length; ++i) if (tabs[i].key === currentKey) return currentKey
        return tabs.length > 0 ? tabs[0].key : ""
    }
}
