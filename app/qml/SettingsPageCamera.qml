// 設定ジャンル「カメラ」: バックカメラ(バック信号での自動切り替え・使うカメラ・映し方)。
// バック信号は今はダミーだけ(キーボードの Ctrl+Shift+R か、下のスイッチ)。将来は外部マイコンから受ける。
import QtQuick

SettingsPage {
    Component.onCompleted: reverseCamera.refreshDevices()

    SettingsSection {
        title: "バックカメラ"
        icon: "videocam"

        SettingsRow {
            label: "バックで自動で切り替える"
            description: "バック信号が入ると、どの画面でもカメラの映像に切り替えます"
            SettingsSwitch {
                checked: reverseCamera.autoSwitch
                onToggled: (value) => reverseCamera.autoSwitch = value
            }
        }
        SettingsRow {
            label: "元の画面に戻るまで"
            description: "バック信号が切れてから戻るまでの時間。切り返しで何度も切り替わらないようにします"
            SettingsChoice {
                readonly property var secs: [0, 1, 2, 3, 5]
                model: ["すぐ", "1 秒", "2 秒", "3 秒", "5 秒"]
                currentIndex: secs.indexOf(reverseCamera.returnDelay)
                onPicked: (i) => reverseCamera.returnDelay = secs[i]
            }
        }
        SettingsRow {
            label: "映像を確認"
            description: "バック信号に関係なく、今の設定でカメラの映像を出します(右上の「確認を終わる」で戻ります)"
            ActionButton {
                text: "映像を確認"
                onClicked: reverseCamera.setPreview(true)
            }
        }
    }

    SettingsSection {
        title: "使うカメラ"
        icon: "mdi:video-input-component"

        SettingsRow {
            label: "カメラ"
            description: "UVC で認識されるキャプチャーボード・USB カメラから選びます。「自動」は最初に見つかったカメラです"
            stacked: true
            SettingsDeviceList {
                model: reverseCamera.deviceNames
                currentIndex: reverseCamera.deviceIndex
                onPicked: (i) => reverseCamera.deviceIndex = i
            }
        }
        SettingsNote {
            visible: reverseCamera.missingDevice !== ""
            color: Theme.warn
            text: "選んでいたカメラ「" + reverseCamera.missingDevice + "」が見つかりません。つなぐと自動で使います(ほかのカメラには替えません)"
        }
        SettingsNote {
            visible: reverseCamera.deviceNames.length <= 1
            text: "カメラが見つかりません。キャプチャーボード・USB カメラをつなぐと、ここに出ます"
        }
        SettingsInfoRow {
            visible: reverseCamera.cameraState === "active"
            label: "使用中"
            value: reverseCamera.activeDescription
        }
        SettingsRow {
            label: "一覧を読み直す"
            ActionButton {
                text: "読み直す"
                onClicked: reverseCamera.refreshDevices()
            }
        }
    }

    SettingsSection {
        title: "映し方"
        icon: "tune"

        SettingsRow {
            label: "左右反転"
            description: "カメラが鏡像(ミラー)で出力しない場合にオンにします。バックカメラは通常、鏡像で映します"
            SettingsSwitch {
                checked: reverseCamera.mirror
                onToggled: (value) => reverseCamera.mirror = value
            }
        }
        SettingsRow {
            label: "ガイド線"
            description: "距離の目安の線(手前から 赤・黄・緑)を重ねます。目安なので、実際の距離とは合わせていません"
            SettingsSwitch {
                checked: reverseCamera.guides
                onToggled: (value) => reverseCamera.guides = value
            }
        }
        SettingsRow {
            label: "表示のしかた"
            SettingsChoice {
                model: ["全体を表示", "画面を埋める"]
                currentIndex: reverseCamera.fill ? 1 : 0
                onPicked: (i) => reverseCamera.fill = i === 1
            }
        }
        SettingsRow {
            label: "すぐに映す"
            description: "カメラを常に動かしておき、バックに入れたらすぐに映します(電力・CPU を少し多く使います)。"
                         + "オフなら、バックに入れてからカメラを動かします(映るまで少し待つことがあります)"
            SettingsSwitch {
                checked: reverseCamera.keepWarm
                onToggled: (value) => reverseCamera.keepWarm = value
            }
        }
    }

    SettingsSection {
        title: "バック信号"
        icon: "mdi:car-back"

        SettingsInfoRow {
            label: "入力元"
            value: "ダミー(外部マイコンからの入力は未実装)"
            valueColor: Theme.warn
        }
        SettingsRow {
            label: "ダミーのバック信号"
            description: "キーボードの Ctrl+Shift+R でも入/切できます"
            SettingsSwitch {
                checked: reverseCamera.mockReverse
                onToggled: (value) => reverseCamera.mockReverse = value
            }
        }
        SettingsInfoRow {
            label: "今の状態"
            value: reverseCamera.reverse ? "バック(R)" : "バックではない"
            valueColor: reverseCamera.reverse ? Theme.error : Theme.textPrimary
        }
    }
}
