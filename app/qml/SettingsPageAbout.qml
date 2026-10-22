// 設定ジャンル「情報」: アプリのバージョンなど。
import QtQuick

SettingsPage {
    SettingsSection {
        title: "アプリ情報"
        icon: "info"

        SettingsInfoRow { label: "バージョン"; value: "OpenCruise 0.1.0 (プロトタイプ)" }
    }
}
