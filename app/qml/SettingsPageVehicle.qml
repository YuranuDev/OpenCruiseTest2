// 設定ジャンル「車両」: CAN 情報のデータ源と、ダミーデータ(モック)の設定。
// ダミーデータは、メーター・グラフに使う分と Android Auto へ送る分を別々に切り替えられる
// (メーター・グラフの分を切ると、データ源が無いときの表示 =「データなし」を確かめられる)。
import QtQuick

SettingsPage {
    SettingsSection {
        title: "車両情報 (CAN)"
        icon: "directions_car"

        SettingsInfoRow { label: "データ源"; value: can.sourceText + "（実 CAN 通信は未実装）"; valueColor: Theme.warn }
    }

    // ダミーデータ(モック)の車の動き。実 CAN 通信が入るまでの、メーターなどの確認用
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
        SettingsRow {
            label: "フリーホイール(惰性走行)"
            description: "走行中にアクセルを離すと、駆動を切り離して惰性で走ります(回転はアイドリングへ落ち、エンジンブレーキが掛かりません)。"
                         + "アクセルかブレーキを踏むと、回転を車速に合わせてからつなぎ直します"
            SettingsSwitch {
                checked: can.mockFreewheel
                onToggled: (value) => can.mockFreewheel = value
            }
        }
        SettingsInfoRow {
            label: "今の状態"
            value: Math.round(can.speedKmh) + " km/h ・ " + Math.round(can.rpm) + " rpm ・ "
                   + (can.mockTransmission === 1
                      ? (can.gear > 0 ? "疑似変速 " + can.gear + " 段" : "変速比 " + can.transmissionRatio.toFixed(2))
                      : can.gear + " 速")
                   + " ・ アクセル " + Math.round(can.throttlePercent) + " %"
                   + (can.freewheeling ? " ・ 惰性走行中" : "")
        }
    }
}
