// 設定ジャンル「サウンド」: マップ音声・音楽音声・システム音量の 3 つの音量と、それぞれの出力先、
//   および Android Auto の音声入力に使うマイク(使用する/しない、入力元)。
//   マップ音声 = Android Auto のナビ案内、音楽音声 = Android Auto のメディア、
//   システム   = アプリの操作音・起動音と Android Auto のシステム音。
//   効果音     = 操作音・起動音・警告音に使う WAV(フォルダ分けされた一覧から選ぶ。SystemSound)。
//                警告音は WAV のほか合成音も選べ、波形・高さ・回数・長さ・音量と、繰り返す間隔を設定できる。
//   マスター音量 = 上の 3 つすべてに掛かる共通の倍率(3 つの設定値は変わらない)。Ctrl+Shift+V/B でも変えられる。
import QtQuick
import OpenCruise

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

        // ---- 警告音の繰り返しと合成音 ----
        readonly property bool synthSelected: { systemSound.revision; return systemSound.selectedSound("alert") === "synth" }
        function setSynth(key, v) { systemSound.setSynthValue(key, v); synthPreview.restart() }
        // 合成音の設定を変えたら、少し待ってから試しに鳴らす(＋−を連打・長押ししている間は鳴らさない)
        Timer { id: synthPreview; interval: 450; onTriggered: systemSound.previewSynth() }

        SettingsRow {
            label: "警告音を繰り返す間隔"
            description: "警告中、この間隔で警告音を繰り返します(WAV・合成音のどちらにも効きます)"
            WSStepper {
                value: systemSound.alertInterval / 1000
                from: 0.3; to: 10; step: 0.1; decimals: 1; suffix: " 秒"
                onMoved: (v) => systemSound.alertInterval = Math.round(v * 1000)
            }
        }
        SettingsRow {
            visible: soundSection.synthSelected
            label: "合成音のプリセット"
            description: "まとめて設定を切り替えます(繰り返す間隔も変わります)。選ぶと試しに鳴らします"
            stacked: true
            SettingsChoice {
                model: ["ピピッ", "ピー", "ピポピポ", "速い連打", "チャイム"]
                currentIndex: -1
                onPicked: (index) => {
                    systemSound.applySynthPreset(["pipi", "pii", "pipo", "fast", "chime"][index])
                    systemSound.previewSynth()
                }
            }
        }
        SettingsRow {
            visible: soundSection.synthSelected
            label: "波形"
            description: "サインはやわらかい音、矩形・のこぎりは鋭く目立つ音、三角はその中間です"
            stacked: true
            SettingsChoice {
                model: ["サイン", "矩形", "三角", "のこぎり"]
                currentIndex: systemSound.synth.waveform
                onPicked: (index) => soundSection.setSynth("waveform", index)
            }
        }
        SettingsRow {
            visible: soundSection.synthSelected
            label: "音の高さ"
            description: "1 音目の高さ。2000 Hz 前後が車内でも聞き取りやすい高さです"
            WSStepper {
                value: systemSound.synth.frequency
                from: 200; to: 6000; step: 50; suffix: " Hz"
                onMoved: (v) => soundSection.setSynth("frequency", v)
            }
        }
        SettingsRow {
            visible: soundSection.synthSelected
            label: "2 音目の高さ"
            description: "0 にすると 1 音目と同じ高さ。違う高さにすると、1 音ごとに交互に鳴らします(ピポピポ)"
            WSStepper {
                value: systemSound.synth.frequency2
                from: 0; to: 6000; step: 50; suffix: " Hz"
                onMoved: (v) => soundSection.setSynth("frequency2", v)
            }
        }
        SettingsRow {
            visible: soundSection.synthSelected
            label: "音の数"
            description: "1 回に鳴らす音の数"
            WSStepper {
                value: systemSound.synth.pulses
                from: 1; to: 8; step: 1; suffix: " 回"
                onMoved: (v) => soundSection.setSynth("pulses", v)
            }
        }
        SettingsRow {
            visible: soundSection.synthSelected
            label: "1 音の長さ"
            WSStepper {
                value: systemSound.synth.pulseMs
                from: 20; to: 1000; step: 10; suffix: " ms"
                onMoved: (v) => soundSection.setSynth("pulseMs", v)
            }
        }
        SettingsRow {
            visible: soundSection.synthSelected
            label: "音と音の間"
            WSStepper {
                value: systemSound.synth.gapMs
                from: 0; to: 1000; step: 10; suffix: " ms"
                onMoved: (v) => soundSection.setSynth("gapMs", v)
            }
        }
        SettingsRow {
            visible: soundSection.synthSelected
            label: "立ち上がり・消え際"
            description: "音の頭と終わりをなめらかにする長さ。0 にすると「プツッ」とした鋭い音になります"
            WSStepper {
                value: systemSound.synth.fadeMs
                from: 0; to: 50; step: 1; suffix: " ms"
                onMoved: (v) => soundSection.setSynth("fadeMs", v)
            }
        }
        SettingsRow {
            visible: soundSection.synthSelected
            label: "合成音の音量"
            description: "システムの音量に、さらにこの割合を掛けます"
            stacked: true
            SettingsSlider {
                value: systemSound.synth.volume
                from: 10
                onMoved: (v) => systemSound.setSynthValue("volume", v)
                onReleased: systemSound.previewSynth()
            }
        }
        SettingsRow {
            visible: soundSection.synthSelected
            label: "試しに鳴らす"
            description: "1 回の長さ: " + systemSound.synthLengthMs + " ms"
                         + (systemSound.synthLengthMs > systemSound.alertInterval
                            ? "(繰り返す間隔より長いため、次の音で途切れます)" : "")
            ActionButton {
                text: "鳴らす"
                onClicked: systemSound.previewSynth()
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
