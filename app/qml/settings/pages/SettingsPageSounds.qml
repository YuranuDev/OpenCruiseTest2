// 設定「音 > 効果音」: 操作音・起動音・警告音・注意音(systemSound)。
//   WAV(起動音は MP3 も)をフォルダ分けされた一覧から選ぶ。警告音は合成音も選べ、波形・高さ・回数・長さ・音量と、繰り返す間隔を決められる。
import QtQuick
import OpenCruise

SettingsPage {
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
            description: "選ぶと試しに鳴らします"
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
            description: "選ぶと試しに鳴らします"
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
            description: "警告のルール(設定 > 車両 > 警告・注意)で「警告音を鳴らす」をオンにしたときに使います。選ぶと試しに鳴らします"
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
            id: cautionRow
            readonly property var options: soundSection.optionsOf("caution")
            label: "注意音"
            description: "注意になったときに 1 回だけ鳴らします(設定 > 車両 > 警告・注意 の各ルールの「注意音を鳴らす」)。選ぶと試しに鳴らします"
            stacked: true

            SettingsDeviceList {
                model: soundSection.labelsOf(cautionRow.options)
                currentIndex: soundSection.indexOf(cautionRow.options, "caution")
                onPicked: (index) => {
                    const id = cautionRow.options[index].id
                    systemSound.setSelectedSound("caution", id)
                    systemSound.preview("caution", id)
                }
            }
        }

        // ---- 警告音の繰り返しと合成音 ----
        readonly property bool synthSelected: { systemSound.revision; return systemSound.selectedSound("alert") === "synth" }
        function setSynth(key, v) { systemSound.setSynthValue(key, v); synthPreview.restart() }
        // 合成音の設定を変えたら、少し待ってから試しに鳴らす(＋−を連打・長押ししている間は鳴らさない)
        Timer { id: synthPreview; interval: 450; onTriggered: systemSound.previewSynth() }

        SettingsRow {
            visible: soundSection.synthSelected
            label: "合成音のプリセット"
            description: "下の音の設定と、鳴らし方・繰り返す間隔をまとめて切り替えます。選ぶと試しに鳴らします"
            stacked: true
            SettingsChoice {
                model: ["ピピッ", "ピー", "ピポピポ", "速い連打", "チャイム", "ずっとピーー", "ずっとピーポー"]
                currentIndex: -1
                onPicked: (index) => {
                    systemSound.applySynthPreset(["pipi", "pii", "pipo", "fast", "chime", "continuous", "continuousPipo"][index])
                    systemSound.previewSynth()
                }
            }
        }
        SettingsRow {
            label: "警告音の鳴らし方"
            description: "どちらも、警告中のメーターか、ホーム画面の解除ボタンをタップすると止まります"
            stacked: true
            SettingsChoice {
                model: ["間隔をあけて繰り返す", "警告中ずっと鳴らす"]
                currentIndex: systemSound.alertContinuous ? 1 : 0
                onPicked: (index) => systemSound.alertContinuous = index === 1
            }
        }
        SettingsRow {
            visible: !systemSound.alertContinuous
            label: "警告音を繰り返す間隔"
            WSStepper {
                value: systemSound.alertInterval / 1000
                from: 0.3; to: 10; step: 0.1; decimals: 1; suffix: " 秒"
                onMoved: (v) => systemSound.alertInterval = Math.round(v * 1000)
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
            description: "1 回分(繰り返しの 1 回)に鳴らす音の数"
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
                         + (systemSound.alertContinuous ? "(警告中はこれをくり返し続けます)"
                            : systemSound.synthLengthMs > systemSound.alertInterval
                            ? "(繰り返す間隔より長いため、次の音で途切れます)" : "")
            ActionButton {
                text: "鳴らす"
                onClicked: systemSound.previewSynth()
            }
        }

        SettingsRow {
            label: "効果音フォルダを読み直す"
            description: "ユーザーフォルダの WAV・MP3 を追加・削除したあとに押します"

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
            text: "効果音は種類ごとのフォルダ(操作音 = click、起動音 = start、警告音 = alert、注意音 = caution)に入っている WAV ファイルから選べます。"
                  + "起動音だけは MP3 も選べます。ユーザーフォルダの click / start / alert / caution へファイルを置くと一覧に追加されます"
                  + "(操作音・警告音・注意音はすぐ鳴らすため WAV だけです)。"
                  + "音量と出力先は「システム」の設定に従います。"
        }
    }
}
