// 設定「システム > 描画」: 描画方式(OpenGL / Vulkan / ソフトウェア)・垂直同期・フレームレート(displaySettings)。
//   どれも再起動で反映する(「今すぐ再起動」は、画面を手放してから同じプロセスで起動し直す。DisplaySettings::restartApp)。
import QtQuick
import OpenCruise

SettingsPage {
    SettingsSection {
        title: "描画"
        icon: "speed"

        SettingsRow {
            label: "描画方式"
            description: "画面が乱れる・起動しないときに切り替えます。ソフトウェアは GPU を使わない代わりに重く、Android Auto の映像が出ない場合があります"

            SettingsChoice {
                model: ["自動", "OpenGL", "Vulkan", "ソフトウェア"]
                currentIndex: displaySettings.graphicsApi
                onPicked: (index) => displaySettings.graphicsApi = index
            }
        }

        SettingsRow {
            label: "垂直同期"
            description: "オンにすると画面のちらつき(ティアリング)を防ぎます。オフは遅延が減る代わりに、描画が増えて消費電力が上がります"

            SettingsSwitch {
                checked: displaySettings.vsync
                onToggled: (value) => displaySettings.vsync = value
            }
        }

        SettingsRow {
            visible: displaySettings.vsync
            label: "フレームレート"
            description: "画面のリフレッシュレートに対する描画の割合(60Hz の画面で 1/2 なら 30fps)。下げると省電力になります"

            SettingsChoice {
                model: ["最大", "1/2", "1/3"]
                currentIndex: displaySettings.frameDivider - 1
                onPicked: (index) => displaySettings.frameDivider = index + 1
            }
        }

        SettingsInfoRow { label: "使用中の描画方式"; value: displaySettings.activeGraphicsApi }
        SettingsInfoRow {
            visible: displaySettings.graphicsNote !== ""
            label: "描画方式の注意"
            value: displaySettings.graphicsNote
            valueColor: Theme.warn
        }

        SettingsRow {
            visible: displaySettings.restartRequired
            label: "再起動して反映"

            ActionButton {
                text: "今すぐ再起動"
                onClicked: displaySettings.restartApp()
            }
        }

        SettingsNote {
            text: "垂直同期とフレームレートは、描画方式やドライバによっては効かないことがあります(主に OpenGL で有効)。"
        }
    }
}
