// 設定ジャンル「車両」: CAN 情報のデータ源と、Android Auto へ送る車両データ(モック)の設定。
import QtQuick

SettingsPage {
    SettingsSection {
        title: "車両情報 (CAN)"
        icon: "directions_car"

        SettingsInfoRow { label: "データ源"; value: can.sourceText + "（実 CAN 通信は未実装）"; valueColor: Theme.warn }

        SettingsRow {
            label: "Android Auto へ送信(モック)"

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
    }
}
