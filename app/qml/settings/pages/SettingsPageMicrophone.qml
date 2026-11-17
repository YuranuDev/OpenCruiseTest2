// 設定「音 > マイク」: Android Auto の音声入力に使うマイク(使用する/しない、入力元、状態)。
import QtQuick
import OpenCruise

SettingsPage {
    SettingsSection {
        title: "マイク"
        icon: "mic"

        SettingsRow {
            label: "マイクを使用する"
            description: "Android Auto の音声操作に使います"

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
