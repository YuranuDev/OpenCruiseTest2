// 設定「システム > 情報」: アプリと動作環境(Linux)の情報(appInfo)、キーボードの操作の一覧、ログの出力先、使用素材・ライセンス。
import QtQuick
import OpenCruise

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

    // キーボードの操作(物理ボタン・ステアリングスイッチも、同じキーを送れば同じ動きになる)。Main.qml の Shortcut と合わせること
    SettingsSection {
        title: "キーボードの操作"
        icon: "keyboard"

        SettingsInfoRow { label: "Ctrl+Shift+V / B"; value: "音量を下げる / 上げる(押しっぱなしで連続)" }
        SettingsInfoRow { label: "Ctrl+Shift+K / L"; value: "画面の明るさを下げる / 上げる(押しっぱなしで連続)" }
        SettingsInfoRow { label: "F10・Menu・Windows キー"; value: "下から出るメニューを開く / 閉じる" }
        SettingsInfoRow { label: "Esc"; value: "閉じる・戻る(起動画面では読み込みを飛ばす。ホームでは終了の確認)" }
        SettingsInfoRow { label: "Ctrl+Shift+D"; value: "昼 / 夜のテーマを切り替える" }
        SettingsInfoRow { label: "Ctrl+Shift+R"; value: "ダミーのバック信号を入れる / 切る(バックカメラ)" }
        SettingsInfoRow { label: "Ctrl+Shift+P"; value: "ACC OFF の終了を試す(外部マイコンの代わり)" }
        SettingsInfoRow { label: "Ctrl+Alt+F1〜F6・Backspace"; value: "アプリを終了してコンソールへ(画面を直接使っているときだけ)" }
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

    // 使用素材のクレジット(CC BY 4.0 の表記の義務。画面内に出すのがいちばん望ましいとされているため、ここに出す)
    SettingsSection {
        title: "使用素材・ライセンス"
        icon: "copyright"

        SettingsInfoRow { label: "効果音"; value: "OtoLogic (https://otologic.jp) ・ CC BY 4.0" }
        SettingsInfoRow { label: "音声"; value: "AivisSpeech (https://aivis-project.com)" }
        SettingsNote {
            text: "このアプリの効果音には、OtoLogic が配布している素材音源を使用しています。"
                  + "素材のライセンスは CC BY 4.0(https://creativecommons.org/licenses/by/4.0/deed.ja)です。\n"
                  + "起動時のあいさつなどの音声は、AivisSpeech で作成しました。"
        }
    }
}
