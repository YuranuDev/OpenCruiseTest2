// 設定「システム > 情報」: アプリと動作環境(Linux)の情報(appInfo)、キーボードの操作の一覧、ログの出力先、ライセンスと使用素材。
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

    // このアプリ自身のライセンス(GPL-3.0-or-later)と、使っている主な部品。
    // GPL が対話的な画面に求める「保証がないこと・再配布の条件」の表示と、ソースコードの入手先もここに出す。部品の一覧は THIRD-PARTY-NOTICES.md と合わせること
    SettingsSection {
        title: "ライセンス"
        icon: "copyright"

        SettingsInfoRow { label: "OpenCruise"; value: "GNU GPL バージョン 3 またはそれ以降(GPL-3.0-or-later)" }
        SettingsInfoRow { label: "ソースコード"; value: "https://github.com/YuranuDev/OpenCruiseTest2" }
        SettingsInfoRow { label: "Android Auto 接続層"; value: "aasdk ・ GPL-3.0-or-later" }
        SettingsInfoRow { label: "Qt"; value: "LGPL-3.0(共有ライブラリとして使用)" }
        SettingsInfoRow { label: "H.264 デコード"; value: "OpenH264 ・ BSD-2-Clause" }
        SettingsNote {
            text: "OpenCruise は自由ソフトウェアです。GNU 一般公衆利用許諾書(GPL)のバージョン 3、またはそれ以降のうち好きなものの条件で、再配布・改変できます。\n"
                  + "このプログラムには、法律で認められる範囲で、いかなる保証もありません。\n"
                  + "ライセンスの全文は、ソースコードの LICENSE にあります。配布用のイメージでは、この機器の /usr/share/common-licenses/ にも、使っている部品ごとのライセンス文と一覧(license.manifest)が入っています。\n"
                  + "H.264 の映像のデコードには OpenH264(ソースからビルドしたもの)を使っています。H.264 の特許の許諾は含まれていません。このアプリは非商用(個人・趣味)での利用を前提としています。\n"
                  + "Android、Android Auto は Google LLC の商標です。このアプリは Google LLC と提携していません。"
        }
    }

    // 使用素材のクレジット(CC BY 4.0 の表記の義務。画面内に出すのがいちばん望ましいとされているため、ここに出す)
    SettingsSection {
        title: "使用素材"
        icon: "copyright"

        SettingsInfoRow { label: "効果音"; value: "OtoLogic (https://otologic.jp) ・ CC BY 4.0" }
        SettingsInfoRow { label: "音声"; value: "AivisSpeech (https://aivis-project.com) ・ コハク(ACML 1.0)" }
        SettingsInfoRow { label: "フォント"; value: "Noto Sans JP・LINE Seed JP・IBM Plex Sans JP ・ SIL OFL 1.1" }
        SettingsInfoRow { label: "アイコン"; value: "Material Icons・Material Design Icons ・ Apache-2.0" }
        SettingsNote {
            text: "このアプリの効果音には、OtoLogic が配布している素材音源を使用しています。"
                  + "素材のライセンスは CC BY 4.0(https://creativecommons.org/licenses/by/4.0/deed.ja)です。\n"
                  + "起動時のあいさつなどの音声は、AivisSpeech で作成しました。"
        }
    }
}
