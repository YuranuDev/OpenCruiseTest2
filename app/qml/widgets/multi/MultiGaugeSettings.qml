// マルチ表示(MultiGaugeWidget)の設定: 表示する値の並び(MetricListEditor)とバーの有無。
// 範囲・単位は、それぞれの計測値のメーターの既定を使う。警告・注意は 設定 > 車両 > 警告・注意 のルール
import QtQuick
import OpenCruise

WidgetSettingsBase {
    id: root

    WidgetSettingsGroup {
        title: "表示"
        icon: "list"

        SettingsRow {
            label: "表示する値"
            description: "上から順に並びます(最大 6 個)。範囲と単位は、その値のメーターの既定です"
            stacked: true
            MetricListEditor {
                width: Math.min(root.width, 900 * Theme.uiScale)
                items: Array.isArray(root.config.items) ? root.config.items : []
                maxCount: 6
                onChangedItems: (list) => root.edit("items", list)
            }
        }
        SettingsRow {
            label: "バーを表示"
            description: "オフにすると名前と数値だけになり、小さいサイズでも文字が大きくなります"
            SettingsSwitch {
                checked: root.config.showBars !== false
                onToggled: (v) => root.edit("showBars", v)
            }
        }
    }
}
