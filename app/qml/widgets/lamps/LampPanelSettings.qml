// 警告灯パネル(LampPanelWidget)の設定。
//   表示: 表示方法(見やすさ優先 / ダッシュボード風)・正常のとき(緑で光る / 暗く / 出さない)・名前・数値・データなしを隠す
//   並べる値: MetricListEditor(計測値と「故障コード」「チェックランプ」。データが来ている値を全部入れる・全部入れる・全部外す)
// 注意・警告になる値は 設定 > 車両 > 警告・注意 のルールで決める(ここでは変えない)
import QtQuick
import OpenCruise

WidgetSettingsBase {
    id: root

    WidgetSettingsGroup {
        title: "表示"
        icon: "tune"

        SettingsRow {
            label: "表示方法"
            description: "見やすさ優先: 枠と文字で状態を出します / ダッシュボード風: 暗い面に記号だけが光ります(純正の警告灯に近い)"
            stacked: true
            SettingsChoice {
                model: [{ label: "見やすさ優先", icon: "view_module" }, { label: "ダッシュボード風", icon: "mdi:car-light-dimmed" }]
                currentIndex: root.config.lampStyle === "dash" ? 1 : 0
                onPicked: (i) => root.edit("lampStyle", i === 1 ? "dash" : "readable")
            }
        }
        SettingsRow {
            label: "正常のとき"
            description: "「出さない」にすると、注意・警告になったものだけが並びます(すべて正常なら「異常なし」)"
            stacked: true
            SettingsChoice {
                readonly property var ids: ["green", "quiet", "hidden"]
                model: ["緑で光る", "暗く表示(注意・警告だけ光る)", "出さない"]
                currentIndex: Math.max(0, ids.indexOf(root.config.okStyle))
                onPicked: (i) => root.edit("okStyle", ids[i])
            }
        }
        SettingsRow {
            label: "名前を表示"
            description: "オフにすると記号だけになります(たくさん並べるときに向きます)"
            SettingsSwitch {
                checked: root.config.showNames !== false
                onToggled: (v) => root.edit("showNames", v)
            }
        }
        SettingsRow {
            label: "数値を表示"
            description: "故障コードは件数、チェックランプは点灯・消灯を出します"
            SettingsSwitch {
                checked: root.config.showValues !== false
                onToggled: (v) => root.edit("showValues", v)
            }
        }
        SettingsRow {
            label: "データが来ていないものを隠す"
            description: "この車・今の接続で取れない値を並べないようにします(取れるようになると出ます)"
            SettingsSwitch {
                checked: root.config.hideNoData === true
                onToggled: (v) => root.edit("hideNoData", v)
            }
        }
    }

    WidgetSettingsGroup {
        title: "並べる値"
        icon: "list"

        SettingsRow {
            label: "並べる値"
            description: "上から順に(横に詰めて)並びます。注意・警告になる値は 設定 > 車両 > 警告・注意 のルールで決まります"
            stacked: true
            MetricListEditor {
                width: Math.min(root.width, 900 * Theme.uiScale)
                items: Array.isArray(root.config.items) ? root.config.items : []
                maxCount: 60
                bulk: true
                extras: [{ id: "dtc", title: "故障コード", icon: "mdi:car-wrench" },
                         { id: "mil", title: "チェックランプ", icon: "mdi:engine-outline" }]
                onChangedItems: (list) => root.edit("items", list)
            }
        }
    }
}
