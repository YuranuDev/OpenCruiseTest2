// 設定ジャンル「サウンド」: マップ音声・音楽音声・システム音量の 3 つの音量と、それぞれの出力先、
//   および Android Auto の音声入力に使うマイク(使用する/しない、入力元)。
//   マップ音声 = Android Auto のナビ案内、音楽音声 = Android Auto のメディア、
//   システム   = アプリの操作音・起動音と Android Auto のシステム音。
//   効果音     = 操作音・起動音に使う WAV(フォルダ分けされた一覧から選ぶ。SystemSound)。
//   マスター音量 = 上の 3 つすべてに掛かる共通の倍率(3 つの設定値は変わらない)。Ctrl+Shift+V/B でも変えられる。
import QtQuick

SettingsPage {
    SettingsSection {
        title: "音量"
        icon: "volume_up"

        SettingsRow {
            label: "マスター音量"
            description: "すべての音声にまとめて掛かる音量。下の各音量の設定はそのまま保たれます(Ctrl+Shift+V/B)"

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
        id: soundSection
        title: "効果音"
        icon: "music_note"

        // カテゴリ(click / start / alert)の選択肢。systemSound.revision を読むことで、選択・再読み込みのたびに作り直す
        function optionsOf(category) { systemSound.revision; return systemSound.soundOptions(category) }
        function labelsOf(options) {
            return options.map(o => o.folder === "" ? o.name : o.name + "(" + o.folder + ")")
        }
        function indexOf(options, category) {
            systemSound.revision
            const id = systemSound.selectedSound(category)
            for (let i = 0; i < options.length; ++i) {
                if (options[i].id === id) return i
            }
            return -1
        }

        SettingsRow {
            id: clickRow
            readonly property var options: soundSection.optionsOf("click")
            label: "操作音"
            description: "画面に触れたときの音。選ぶと試しに鳴らします"
            stacked: true

            SettingsDeviceList {
                model: soundSection.labelsOf(clickRow.options)
                currentIndex: soundSection.indexOf(clickRow.options, "click")
                onPicked: (index) => {
                    const id = clickRow.options[index].id
                    systemSound.setSelectedSound("click", id)
                    systemSound.preview("click", id)
                }
            }
        }

        SettingsRow {
            id: startRow
            readonly property var options: soundSection.optionsOf("start")
            label: "起動音"
            description: "アプリの起動時に鳴らす音。選ぶと試しに鳴らします"
            stacked: true

            SettingsDeviceList {
                model: soundSection.labelsOf(startRow.options)
                currentIndex: soundSection.indexOf(startRow.options, "start")
                onPicked: (index) => {
                    const id = startRow.options[index].id
                    systemSound.setSelectedSound("start", id)
                    systemSound.preview("start", id)
                }
            }
        }

        SettingsRow {
            id: alertRow
            readonly property var options: soundSection.optionsOf("alert")
            label: "警告音"
            description: "メーターが警告値を超えたときに繰り返し鳴らす音(メーターの設定で「警告音を鳴らす」をオンにしたとき)。選ぶと試しに鳴らします"
            stacked: true

            SettingsDeviceList {
                model: soundSection.labelsOf(alertRow.options)
                currentIndex: soundSection.indexOf(alertRow.options, "alert")
                onPicked: (index) => {
                    const id = alertRow.options[index].id
                    systemSound.setSelectedSound("alert", id)
                    systemSound.preview("alert", id)
                }
            }
        }

        SettingsRow {
            label: "効果音フォルダを読み直す"
            description: "ユーザーフォルダへ WAV を追加・削除したあとに押すと、一覧に反映します"

            ActionButton {
                text: "読み直す"
                onClicked: systemSound.rescan()
            }
        }

        SettingsInfoRow { label: "ユーザーフォルダ"; value: systemSound.userSoundDirectory }
        SettingsInfoRow {
            label: "同梱フォルダ"
            value: systemSound.builtinSoundDirectory !== "" ? systemSound.builtinSoundDirectory : "見つかりません(既定の音だけ使えます)"
            valueColor: systemSound.builtinSoundDirectory !== "" ? Theme.textPrimary : Theme.warn
        }

        SettingsNote {
            text: "効果音は種類ごとのフォルダ(操作音 = click、起動音 = start)に入っている WAV ファイルから選べます。"
                  + "ユーザーフォルダの click / start / alert へ WAV を置くと一覧に追加されます(MP3 などは使えません)。"
                  + "音量と出力先は「システム」の設定に従います。"
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
