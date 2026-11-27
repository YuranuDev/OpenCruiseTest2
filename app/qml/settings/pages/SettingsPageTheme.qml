// 設定「表示と操作 > テーマ・背景」。編集モードに集約したテーマ編集への入口。
import QtQuick
import OpenCruise

SettingsPage {
    id: page

    SettingsSection {
        title: "テーマ・壁紙の編集"
        icon: "palette"

        SettingsNote {
            text: "昼夜別のテーマ、アクセント色、壁紙、飾りは編集モードにまとめました。"
                  + "設定画面を開いている時間帯に関係なく、昼用・夜用を選んで編集できます。"
        }

        SettingsRow {
            label: "テーマと壁紙を編集"
            description: "ホーム画面の編集モードを開き、上部の「テーマ」「壁紙」から変更します"
            ActionButton {
                text: "編集モードを開く"
                selected: true
                onClicked: page.openThemeEditorRequested()
            }
        }

        SettingsNote {
            text: "昼夜の切り替えはモックのヘッドライトに連動します。ライトの ON / OFF は 設定 > 車両 > 車両データ で変更できます。"
        }
    }
}
