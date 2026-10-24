// 設定ジャンル「情報」: アプリ(バージョン・Qt・ビルド・ログ)と、動作している Linux の情報。
// 値は appInfo(core/AppInfo)から読む。起動ログに出る環境情報と同じ情報源。
import QtQuick

SettingsPage {
    SettingsSection {
        title: "アプリ情報"
        icon: "info"

        SettingsInfoRow { label: "アプリ"; value: appInfo.appName + " " + appInfo.appVersion + " (プロトタイプ)" }
        SettingsInfoRow { label: "Qt"; value: appInfo.qtVersion }
        SettingsInfoRow { label: "ビルド"; value: appInfo.buildInfo }
        SettingsInfoRow {
            label: "Android Auto 接続層"
            value: appInfo.aasdkEnabled ? "aasdk 有効" : "aasdk 無効(スタブ)"
            valueColor: appInfo.aasdkEnabled ? Theme.textPrimary : Theme.warn
        }
        SettingsInfoRow { label: "描画プラットフォーム"; value: appInfo.platformName }
        SettingsInfoRow { label: "起動時刻"; value: appInfo.startedAt }
        SettingsInfoRow { label: "稼働時間"; value: appInfo.appUptime }
        SettingsInfoRow { label: "プロセス ID"; value: String(appInfo.processId) }
    }

    SettingsSection {
        title: "ログ"
        icon: "description"

        SettingsInfoRow {
            label: "ファイル出力"
            value: appInfo.fileLogging ? "有効" : "無効(コンソールのみ)"
            valueColor: appInfo.fileLogging ? Theme.textPrimary : Theme.warn
        }
        SettingsInfoRow { label: "ログファイル"; value: appInfo.logFile }
        SettingsInfoRow { label: "保存先"; value: appInfo.logDirectory }
    }

    SettingsSection {
        title: "Linux"
        icon: "computer"

        SettingsInfoRow { label: "OS"; value: appInfo.osName }
        SettingsInfoRow { label: "カーネル"; value: appInfo.kernel }
        SettingsInfoRow { label: "CPU アーキテクチャ"; value: appInfo.cpuArchitecture }
        SettingsInfoRow { label: "C ライブラリ"; value: appInfo.libcVersion }
        SettingsInfoRow { label: "デスクトップ"; value: appInfo.session }
        SettingsInfoRow { label: "ホスト名"; value: appInfo.hostName }
        SettingsInfoRow { label: "ロケール"; value: appInfo.locale }
        SettingsInfoRow { label: "起動からの時間"; value: appInfo.systemUptime }
    }
}
