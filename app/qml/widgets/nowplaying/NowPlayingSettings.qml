// 再生中ウィジェットの設定: アルバム名・再生位置バーの表示、モックデータの使用。
import QtQuick
import OpenCruise

WidgetSettingsBase {
    id: root

    SettingsRow {
        label: "アルバム名を表示"
        SettingsSwitch {
            checked: root.config.showAlbum !== false
            onToggled: (v) => root.edit("showAlbum", v)
        }
    }
    SettingsRow {
        label: "再生位置のバーを表示"
        description: "スマホが曲の長さを通知したときだけ表示されます"
        SettingsSwitch {
            checked: root.config.showProgress !== false
            onToggled: (v) => root.edit("showProgress", v)
        }
    }
    SettingsRow {
        label: "モックデータを使う"
        description: "スマホから再生情報が届かない間、仮の曲を表示します(スマホ関連のウィジェット全体に反映)"
        SettingsSwitch {
            checked: phoneStatus.mockEnabled
            onToggled: (v) => phoneStatus.mockEnabled = v
        }
    }
}
