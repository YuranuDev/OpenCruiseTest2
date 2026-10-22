// 設定ジャンル「サウンド」: マップ音声・音楽音声・システム音量の 3 つの音量と、それぞれの出力先、
//   および Android Auto の音声入力に使うマイク(使用する/しない、入力元)。
//   マップ音声 = Android Auto のナビ案内、音楽音声 = Android Auto のメディア、
//   システム   = アプリの操作音・起動音と Android Auto のシステム音。
import QtQuick

SettingsPage {
    SettingsSection {
        title: "音量"
        icon: "volume_up"

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
            description: "音楽・動画などのメディア音声"

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
    }

    SettingsSection {
        title: "マイク"
        icon: "mic"

        SettingsRow {
            label: "マイクを使用する"
            description: "オフにすると、Android Auto の音声入力(音声操作など)に音声を送りません"

            SettingsSwitch {
                checked: audioSettings.micEnabled
                onToggled: (value) => audioSettings.micEnabled = value
            }
        }

        SettingsRow {
            label: "マイクの入力元"
            stacked: true

            SettingsDeviceList {
                model: audioSettings.inputNames
                currentIndex: audioSettings.micDeviceIndex
                onPicked: (index) => audioSettings.micDeviceIndex = index
            }
        }

        SettingsInfoRow {
            label: "マイクの状態"
            value: androidAuto.microphoneStatus
        }

        SettingsNote {
            text: "録音するのは、Android Auto が音声入力を使っている間だけです。"
                  + "入力元を変更すると、録音中でも新しい入力元へ切り替わります。"
                  + "選んだ機器が接続されていない間は、システム既定のデバイスを使い、再接続すると選んだ機器へ戻ります。"
        }
    }
}
