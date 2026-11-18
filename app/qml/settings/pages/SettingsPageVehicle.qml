// 設定「車両 > 車両データ」: データ元(ノード)の状態、両方のノードから取れる項目のデータ元の選び方、ダミーデータ(モック)の設定。
// データ元はノードごと(VIN 車両信号 / SEN 外付けセンサー / DIAG エンジン ECU(K-Line))だが、画面・メーター・警告では
// 1 つの車両データとして扱う(VehicleSignals)。ここではその中身(どのノードから来ているか)を見る・選ぶ。
// ダミーデータは、メーター・グラフに使う分と Android Auto へ送る分を別々に切り替えられる
// (メーター・グラフの分を切ると、データ源が無いときの表示 =「データなし」を確かめられる)。
import QtQuick
import OpenCruise

SettingsPage {
    // ---- データ元(ノード) ----
    SettingsSection {
        title: "データ元(ノード)"
        icon: "hub"

        Repeater {
            model: VehicleSignals.nodes
            SettingsInfoRow {
                required property var modelData
                readonly property var st: VehicleSignals.nodeStatus(modelData.id)
                label: modelData.id + "  " + modelData.title
                value: st.text + (st.mock ? "(ノードとの通信は未実装)" : "")
                valueColor: !st.available ? Theme.textSecondary : st.mock ? Theme.warn : Theme.ok
            }
        }
        SettingsNote {
            text: "VIN: 車速・回転数・ギア・アクセル・ブレーキ・電圧・燃料・バック / SEN: ブースト・水温・油温・油圧 / "
                  + "DIAG: エンジン ECU の計測値・スイッチ・故障コード。画面・メーター・警告では、まとめて 1 つの車両データとして扱います。"
                  + "中身はメニューの「車両」で見られます。"
        }
    }

    // ---- 両方のノードから取れる項目 ----
    SettingsSection {
        title: "同じ項目のデータ元"
        icon: "alt_route"

        SettingsNote {
            text: "車速・回転数・水温・電圧・アクセルは、車両信号(VIN / SEN)とエンジン ECU(DIAG)の両方から取れます。"
                  + "どちらの値を使うかを項目ごとに選べ、「すべての項目をまとめて」で全部を同じ選び方に上書きもできます(メーター・グラフ・警告・車両画面のすべてに効きます)。"
                  + "「〜優先」は、優先する方の値が無いときにもう一方を使います(既定は VIN/SEN 優先)。VIN/SEN は更新が速く(目安 50 回/秒)、ECU は約 5 回/秒です。"
        }
        // すべての項目をまとめて上書き(項目ごとの設定は残したまま、全部を同じ選び方にする)
        SettingsRow {
            label: "すべての項目をまとめて"
            description: VehicleSignals.overridden
                         ? "上書き中: 下の項目ごとの設定に関係なく、すべて「" + VehicleSignals.sourceModes.find(m => m.id === ecu.sourceOverride).title
                           + "」にします(項目ごとの設定は残っていて、「上書きしない」に戻すと元に戻ります)"
                         : "上書きしない: 下の項目ごとの設定を使います"
            stacked: true
            SettingsChoice {
                model: ["上書きしない"].concat(VehicleSignals.sourceModes.map(m => m.title))
                currentIndex: ecu.sourceOverride === "" ? 0 : 1 + VehicleSignals.sourceModes.findIndex(m => m.id === ecu.sourceOverride)
                onPicked: (i) => VehicleSignals.setOverride(i === 0 ? "" : VehicleSignals.sourceModes[i - 1].id)
            }
        }
        Repeater {
            model: VehicleSignals.mergedIds
            SettingsRow {
                required property var modelData
                readonly property var spec: WidgetRegistry.gaugeSpecs[modelData]
                readonly property string now: VehicleSignals.nodeOf(modelData)
                label: spec ? spec.title : modelData
                description: "今: " + (now === "" ? "データなし" : now === "DIAG" ? "ECU(DIAG)" : now)
                             + (VehicleSignals.overridden ? "(まとめての上書き中は、この設定は使いません)" : "")
                stacked: true
                // 上書き中は変えられない(薄く出す)
                enabled: !VehicleSignals.overridden
                opacity: enabled ? 1 : 0.45
                SettingsChoice {
                    model: VehicleSignals.sourceModes.map(m => m.title)
                    currentIndex: { ecu.sourcePrefs; return VehicleSignals.sourceModes.findIndex(m => m.id === VehicleSignals.itemPref(modelData)) }
                    onPicked: (i) => VehicleSignals.setPref(modelData, VehicleSignals.sourceModes[i].id)
                }
            }
        }
    }

    // ---- メーターの針(すべてのメーターをまとめて上書き) ----
    SettingsSection {
        title: "メーターの針"
        icon: "mdi:gauge"

        SettingsRow {
            label: "なめらか表示をまとめて上書き"
            description: appSettings.gaugeSmoothingOverride === 0
                         ? "上書きしない: メーターごとの設定(メーターの設定の「針のなめらか表示」)を使います"
                         : "上書き中: メーターごとの設定に関係なく、すべてのメーターで" + (appSettings.gaugeSmoothingOverride === 1 ? "オン" : "オフ")
                           + "にします(メーターごとの設定は残っていて、「上書きしない」に戻すと元に戻ります)"
            stacked: true
            SettingsChoice {
                model: ["上書きしない", "すべてオン", "すべてオフ"]
                currentIndex: appSettings.gaugeSmoothingOverride
                onPicked: (i) => appSettings.gaugeSmoothingOverride = i
            }
        }
        SettingsNote {
            text: "なめらか表示は、届いた値へ針を滑らかに動かします。更新の遅いデータ(エンジン ECU は約 5 回/秒)は値の間隔に合わせて動かすので、"
                  + "カクカクしませんが、わずかに(1 回の間隔の半分ほど)遅れて見えます。オフにすると遅れは無くなり、針は値が来るたびに飛びます。"
        }
    }

    // ---- ECU のダミーの故障コード ----
    SettingsSection {
        title: "ダミーの故障コード"
        icon: "mdi:car-wrench"

        SettingsRow {
            label: "故障コード"
            description: "車両画面の故障コードと、警告・注意の「車両異常」を確かめるための仮の故障コード(ECU がダミーデータのときだけ)"
            stacked: true
            SettingsChoice {
                model: ["なし", "過去の記録だけ", "現在と過去"]
                currentIndex: ecu.mockDtcMode
                onPicked: (i) => ecu.mockDtcMode = i
            }
        }
    }

    // ダミーデータ(モック)の車の動き。ノードとの通信が入るまでの、メーターなどの確認用(ECU のダミーもこの車の動きから作る)
    SettingsSection {
        title: "ダミーデータ(モック)"
        icon: "mdi:car-shift-pattern"

        SettingsRow {
            label: "メーター・グラフに使う"
            description: "オフにすると、メーター・グラフはデータ源が無いときの表示(「データなし」)になり、警告も出しません"
            SettingsSwitch {
                checked: can.mockGauges
                onToggled: (value) => can.mockGauges = value
            }
        }

        SettingsRow {
            label: "Android Auto へ送信"

            SettingsSwitch {
                checked: androidAuto.mockVehicleData
                onToggled: (value) => androidAuto.mockVehicleData = value
            }
        }

        SettingsNote {
            text: "ON にすると、ダミーデータ(速度・回転数・燃料)に、ギアと位置を加えて Android Auto へ送ります。"
                  + "位置は東京駅付近を周回するだけの架空の値で、実際の現在地ではありません(地図アプリの現在地がずれる場合があります)。"
                  + "スマートフォンが開始要求を出したセンサーだけが送られます。送信できたかはログの [sensor] で確認できます。"
        }

        SettingsRow {
            label: "変速機"
            description: can.mockTransmission === 1
                         ? "CVT: 変速比を連続的に変えます。軽く踏むと低い回転のまま加速し、踏み増すと回転が先に上がって張り付きます。大きく踏むと 7 段の疑似変速になります"
                         : "AT: 6 速。アクセルを踏むほど高い回転まで引っ張ってから変速し、変速の間は駆動力が少し抜けます"
            SettingsChoice {
                model: ["AT", "CVT"]
                currentIndex: can.mockTransmission
                onPicked: (i) => can.mockTransmission = i
            }
        }
        SettingsRow {
            label: "運転のしかた"
            description: ["じわっと踏み、全開加速はほとんどしません。早めに変速し、ブレーキも弱め",
                          "ふつうの運転。ときどき全開で加速します",
                          "深く素早く踏み、全開加速が多め。高い回転まで引っ張り、ブレーキも強め"][can.mockDriveStyle]
            SettingsChoice {
                model: ["穏やか", "普通", "アグレッシブ"]
                currentIndex: can.mockDriveStyle
                onPicked: (i) => can.mockDriveStyle = i
            }
        }
        SettingsInfoRow {
            label: "今の状態"
            value: Math.round(can.speedKmh) + " km/h ・ " + Math.round(can.rpm) + " rpm ・ "
                   + (can.mockTransmission === 1
                      ? (can.gear > 0 ? "疑似変速 " + can.gear + " 段" : "変速比 " + can.transmissionRatio.toFixed(2))
                      : can.gear + " 速")
                   + " ・ アクセル " + Math.round(can.throttlePercent) + " %"
        }
    }
}
