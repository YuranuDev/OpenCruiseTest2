// 設定「音 > 音量・出力先」: マスター音量と、マップ音声・音楽音声・システムの 3 つの音量、それぞれの出力先(audioSettings)。
//   マップ音声 = Android Auto のナビ案内、音楽音声 = Android Auto のメディア、
//   システム   = アプリの操作音・起動音・警告音と Android Auto のシステム音。
//   マスター音量 = 上の 3 つすべてに掛かる共通の倍率(3 つの設定値は変わらない)。Ctrl+Shift+V / B と画面の端のボタンでも変えられる。
import QtQuick
import OpenCruise

SettingsPage {
    SettingsSection {
        title: "音量"
        icon: "volume_up"

        SettingsRow {
            label: "マスター音量"
            description: "下の 3 つの音量にまとめて掛かります(各音量の設定は変わりません)。Ctrl+Shift+V で下げ、B で上げられます"

            SettingsSlider {
                value: audioSettings.masterVolume
                onMoved: (v) => audioSettings.masterVolume = v
                // 指を離したときに操作音を鳴らし、音量を確認できるようにする
                onReleased: systemSound.play("click")
            }
        }

        SettingsRow {
            label: "マップ音声"
            description: "ナビの案内音声"

            SettingsSlider {
                value: audioSettings.mapVolume
                onMoved: (v) => audioSettings.mapVolume = v
            }
        }

        SettingsRow {
            label: "音楽音声"

            SettingsSlider {
                value: audioSettings.musicVolume
                onMoved: (v) => audioSettings.musicVolume = v
            }
        }

        SettingsRow {
            label: "システム音量"
            description: "操作音・起動音・Android Auto のシステム音"

            SettingsSlider {
                value: audioSettings.systemVolume
                onMoved: (v) => audioSettings.systemVolume = v
                // 指を離したときに操作音を鳴らし、音量を確認できるようにする
                onReleased: systemSound.play("click")
            }
        }
    }

    SettingsSection {
        title: "出力先"
        icon: "speaker"

        SettingsRow {
            label: "マップ音声の出力先"
            stacked: true

            SettingsDeviceList {
                model: audioSettings.outputNames
                currentIndex: audioSettings.mapDeviceIndex
                onPicked: (index) => audioSettings.mapDeviceIndex = index
            }
        }

        SettingsRow {
            label: "音楽音声の出力先"
            stacked: true

            SettingsDeviceList {
                model: audioSettings.outputNames
                currentIndex: audioSettings.musicDeviceIndex
                onPicked: (index) => audioSettings.musicDeviceIndex = index
            }
        }

        SettingsRow {
            label: "システム音声の出力先"
            stacked: true

            SettingsDeviceList {
                model: audioSettings.outputNames
                currentIndex: audioSettings.systemDeviceIndex
                onPicked: (index) => {
                    audioSettings.systemDeviceIndex = index
                    systemSound.play("click") // 新しい出力先から確認音を鳴らす
                }
            }
        }

        SettingsNote {
            text: "出力先を変更すると、再生中の音声も新しい出力先へ切り替わります(一瞬途切れることがあります)。"
                  + "選んだ機器が接続されていない間は、システム既定のデバイスで鳴らし、再接続すると選んだ機器へ戻ります。"
        }
        SettingsNote {
            visible: audioSettings.alsaDirect
            text: "音は ALSA の機器へ直接出します(PulseAudio / PipeWire を通しません)。選んだ機器は、音を出している間このアプリが使います"
                  + "(ほかのアプリはその機器を使えません。音が止まって 3 秒たつと手放します)。"
                  + "マップ・音楽・システムの音は、同じ機器を選んでもアプリの中で混ぜて同時に鳴らし、別々の機器にも分けられます。"
                  + "「システム既定」は ALSA の既定の出力です。"
        }
    }
}
