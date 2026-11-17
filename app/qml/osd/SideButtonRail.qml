// 画面の端のボタン(物理ボタンの代わり。設定「表示 > 画面 > 画面の端のボタン」で 左端 / 右端 / 出さない)。
// 上から: メニュー(下から出るメニューの開閉)/ 音量(＋・今の値・−)/ 明るさ(＋・今の値・−)。
//  - 音量・明るさは、キーボードのショートカット(Ctrl+Shift+V / B・K / L)と同じ動き(Main.qml の stepVolume / stepBrightness)。
//    押すとすぐ 1 段変わり、押しっぱなしで連続して変わる。変えると、画面の下に音量・明るさの表示が出る
//  - 今の値の所をタップすると、変えずに音量・明るさの表示だけを出す(表示のバーで細かく変えられる)
//  - Main.qml の rotor の中に置くので、画面の回転に合わせて回る。各画面はこの帯の分だけ狭くなる(重ならない)
// 高さが足りない画面では、ボタンを小さくして縦に収める。
import QtQuick
import OpenCruise

Rectangle {
    id: root
    /// 帯を置く側: 1 = 左端 / 2 = 右端(内側の縁の線を引く側を決める)
    property int edge: 2
    /// 下から出るメニューが開いているか(メニューのボタンを選んだ色にする)
    property bool menuOpen: false
    signal menuClicked()
    signal volumeStep(int dir)
    signal brightnessStep(int dir)
    signal volumeShow()
    signal brightnessShow()

    readonly property real unit: Theme.uiScale
    readonly property real pad: Math.round(8 * unit)
    readonly property real gap: Math.round(10 * unit)          // ボタンどうしの間
    readonly property real groupGap: Math.round(22 * unit)     // メニュー・音量・明るさのまとまりの間
    // ボタン 5 つと値 2 つを縦に収める高さ(大きすぎず、小さい画面では縮める)
    readonly property real cell: Math.max(36 * unit, Math.min(width - 2 * pad, 76 * unit,
                                                              (height - 2 * pad - 4 * gap - 2 * groupGap - 2 * valueH) / 5))
    readonly property real valueH: Math.round(44 * unit)

    color: Theme.mix(Theme.panel, Theme.background, 0.35)
    // 内側(画面の中身の側)の縁の線
    Rectangle {
        anchors { top: parent.top; bottom: parent.bottom }
        x: root.edge === 1 ? parent.width - width : 0
        width: 1
        color: Theme.panelBorder
    }
    // 帯の上は、下の画面へタッチを通さない(ボタンの隙間を押しても何も起きない)
    MouseArea { anchors.fill: parent }

    // ---- ボタン 1 つ(押しっぱなしで繰り返す) ----
    component RailButton: Panel {
        id: btn
        property string icon: ""
        property bool repeat: false
        property bool selected: false
        signal triggered()
        width: root.cell
        height: root.cell
        radius: Math.round(root.cell * 0.22)
        tintAmount: touch.pressed ? 0.55 : (selected ? 1 : 0)
        border.color: selected ? Theme.accent : Theme.panelBorder
        MaterialIcon {
            anchors.centerIn: parent
            name: btn.icon
            size: Math.round(root.cell * 0.56)
            color: btn.selected && !Theme.classic ? Theme.textOnAccent : Theme.textPrimary
        }
        MouseArea {
            id: touch
            anchors.fill: parent
            anchors.margins: -Math.round(root.gap / 2)   // 隙間の半分まで押せる範囲を広げる
            onPressed: {
                btn.triggered()
                if (btn.repeat) hold.restart()
            }
            onReleased: { hold.stop(); again.stop() }
            onCanceled: { hold.stop(); again.stop() }
        }
        // 押しっぱなし: 0.4 秒後から、0.12 秒ごとに繰り返す
        Timer { id: hold; interval: 400; onTriggered: again.start() }
        Timer { id: again; interval: 120; repeat: true; onTriggered: btn.triggered() }
    }

    // ---- 今の値(アイコン + 数字)。タップで表示だけを出す ----
    component RailValue: Item {
        id: val
        property string icon: ""
        property int value: 0
        signal tapped()
        width: root.cell
        height: root.valueH
        Column {
            anchors.centerIn: parent
            spacing: 0
            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: val.icon
                size: Math.round(root.valueH * 0.5)
                color: val.value === 0 ? Theme.textSecondary : Theme.accent
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                font.family: Theme.numberFontFamily
                font.pixelSize: Math.round(root.valueH * 0.36)
                font.bold: true
                color: Theme.textSecondary
                text: val.value
            }
        }
        MouseArea { anchors.fill: parent; onClicked: val.tapped() }
    }

    Column {
        anchors.centerIn: parent
        spacing: root.gap

        RailButton {
            icon: "menu"
            selected: root.menuOpen
            onTriggered: root.menuClicked()
        }
        Item { width: 1; height: root.groupGap - root.gap }

        // 音量
        RailButton { icon: "add"; repeat: true; onTriggered: root.volumeStep(1) }
        RailValue {
            icon: audioSettings.masterVolume === 0 ? "volume_off" : (audioSettings.masterVolume < 50 ? "volume_down" : "volume_up")
            value: audioSettings.masterVolume
            onTapped: root.volumeShow()
        }
        RailButton { icon: "remove"; repeat: true; onTriggered: root.volumeStep(-1) }
        Item { width: 1; height: root.groupGap - root.gap }

        // 明るさ
        RailButton { icon: "add"; repeat: true; onTriggered: root.brightnessStep(1) }
        RailValue {
            icon: "brightness_medium"
            value: brightnessController.brightness
            onTapped: root.brightnessShow()
        }
        RailButton { icon: "remove"; repeat: true; onTriggered: root.brightnessStep(-1) }
    }
}
