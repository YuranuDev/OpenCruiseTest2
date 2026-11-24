// 設定「システム > ネットワーク」: Wi-Fi の接続(wifi = WifiManager。NetworkManager の nmcli)。
//   オン/オフ・つながっている Wi-Fi(IP アドレス)・見えている Wi-Fi の一覧
//   一覧をタップ: 保存済み・パスワードなし → すぐつなぐ / パスワードあり → 上にパスワードの入力欄(画面キーボード)を出す
//   つながっている Wi-Fi: 切断 / 保存済み: パスワードを消す
// 有線 LAN・USB テザリング(スマホ)は、挿せば自動でつながる(NetworkManager)。
import QtQuick
import QtQuick.Controls
import OpenCruise

SettingsPage {
    id: page
    // パスワードを入れている Wi-Fi(空なら入力欄を出さない)
    property string askSsid: ""
    Component.onCompleted: wifi.active = true
    Component.onDestruction: wifi.active = false

    function signalIcon(s) { return s >= 70 ? "signal_wifi_4_bar" : s >= 45 ? "network_wifi_3_bar" : s >= 25 ? "network_wifi_2_bar" : "network_wifi_1_bar" }

    SettingsSection {
        title: "Wi-Fi"
        icon: "wifi"

        SettingsNote {
            visible: !wifi.available
            text: "Wi-Fi は使えません: " + wifi.message
            color: Theme.warn
        }
        SettingsRow {
            visible: wifi.available
            label: "Wi-Fi"
            description: wifi.connectedSsid !== "" ? "「" + wifi.connectedSsid + "」につながっています" + (wifi.ipAddress !== "" ? "(" + wifi.ipAddress + ")" : "")
                         : wifi.enabled ? "つながっていません" : "オフ"
            SettingsSwitch {
                checked: wifi.enabled
                onToggled: (v) => wifi.setEnabled(v)
            }
        }
        SettingsNote {
            visible: wifi.available && wifi.message !== ""
            text: (wifi.busy ? "… " : "") + wifi.message
        }

        // パスワードの入力(タップした Wi-Fi が保存されていない・パスワードが要るとき)
        SettingsRow {
            visible: page.askSsid !== ""
            label: "「" + page.askSsid + "」のパスワード"
            description: "入力欄をタップすると画面キーボードが出ます"
            stacked: true
            Row {
                spacing: 12 * Theme.uiScale
                WSTextField {
                    id: pass
                    width: Math.min(page.width - 420 * Theme.uiScale, 460 * Theme.uiScale)
                    placeholder: "パスワード"
                    maxLength: 63
                    echoMode: showPass.checked ? TextInput.Normal : TextInput.Password
                    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
                    onAccepted: if (text.length >= 8) connectBtn.clicked()
                }
                ActionButton {
                    id: connectBtn
                    text: "つなぐ"
                    opacity: pass.text.length >= 8 ? 1 : 0.4
                    onClicked: {
                        if (pass.text.length < 8) return
                        wifi.connectTo(page.askSsid, pass.text)
                        pass.text = ""
                        page.askSsid = ""
                    }
                }
                ActionButton { text: "やめる"; onClicked: { pass.text = ""; page.askSsid = "" } }
            }
        }
        SettingsRow {
            visible: page.askSsid !== ""
            label: "パスワードを表示"
            SettingsSwitch { id: showPass; checked: false }
        }

        // 見えている Wi-Fi
        Repeater {
            model: wifi.available && wifi.enabled ? wifi.networks : []
            Rectangle {
                id: net
                required property var modelData
                width: parent ? parent.width : 0
                height: 84 * Theme.uiScale
                radius: Theme.radius
                color: netMouse.pressed ? Theme.accentFill : (modelData.active ? Theme.mix(Theme.panel, Theme.accent, 0.14) : "transparent")
                MaterialIcon {
                    id: sig
                    anchors { left: parent.left; leftMargin: 14 * Theme.uiScale; verticalCenter: parent.verticalCenter }
                    name: page.signalIcon(net.modelData.signal)
                    size: 36 * Theme.uiScale
                    color: net.modelData.active ? Theme.accent : Theme.textSecondary
                }
                Column {
                    anchors { left: sig.right; leftMargin: 14 * Theme.uiScale; right: netButtons.left; rightMargin: 10 * Theme.uiScale
                              verticalCenter: parent.verticalCenter }
                    Row {
                        spacing: 8 * Theme.uiScale
                        Text {
                            font.family: Theme.fontFamily
                            font.pixelSize: 25 * Theme.uiScale
                            font.bold: net.modelData.active
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                            text: net.modelData.ssid
                        }
                        MaterialIcon {
                            visible: net.modelData.secure
                            anchors.verticalCenter: parent.verticalCenter
                            name: "lock"
                            size: 22 * Theme.uiScale
                            color: Theme.textSecondary
                        }
                    }
                    Text {
                        font.family: Theme.fontFamily
                        font.pixelSize: 18 * Theme.uiScale
                        color: Theme.textSecondary
                        text: (net.modelData.active ? "接続中" : net.modelData.saved ? "保存済み" : net.modelData.secure ? "パスワードが必要" : "パスワードなし")
                              + " ・ 電波 " + net.modelData.signal + "%"
                    }
                }
                MouseArea {
                    id: netMouse
                    anchors.fill: parent
                    enabled: !wifi.busy && !net.modelData.active
                    onClicked: {
                        if (net.modelData.saved || !net.modelData.secure) wifi.connectTo(net.modelData.ssid, "")
                        else { page.askSsid = net.modelData.ssid; pass.text = ""; page.contentY = 0; pass.forceActiveFocus() }
                    }
                }
                Row {
                    id: netButtons
                    anchors { right: parent.right; rightMargin: 10 * Theme.uiScale; verticalCenter: parent.verticalCenter }
                    spacing: 10 * Theme.uiScale
                    ActionButton { visible: net.modelData.active; text: "切断"; onClicked: wifi.disconnectWifi() }
                    ActionButton { visible: net.modelData.saved && !net.modelData.active; text: "消す"; onClicked: wifi.forget(net.modelData.ssid) }
                    ActionButton {
                        visible: net.modelData.saved && net.modelData.secure && !net.modelData.active
                        text: "パスワード変更"
                        onClicked: { page.askSsid = net.modelData.ssid; pass.text = ""; page.contentY = 0; pass.forceActiveFocus() }
                    }
                }
            }
        }
        SettingsRow {
            visible: wifi.available && wifi.enabled
            label: "探し直す"
            description: "一覧は開いている間 8 秒ごとに更新します"
            ActionButton { text: "探す"; onClicked: wifi.refresh(true) }
        }
        SettingsNote {
            text: "有線 LAN と USB テザリング(スマホ)は、つなげば自動で使えます。ネットからのアップデートは 設定 > アップデート で行います"
        }
    }
}
