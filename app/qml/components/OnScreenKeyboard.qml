// 画面キーボード(英数字・記号)。文字の入力欄(TextField / TextInput)をタップしてフォーカスが入ると、画面の下から出る。
// Wi-Fi のパスワードなど、車のタッチ画面で文字を入れるためのもの(日本語は入れられない。物理キーボードもそのまま使える)。
// Main.qml が target に今フォーカスのある部品(window.activeFocusItem)を渡す。キーを押すと target に文字を足す。
//   ⇧: 次の 1 文字だけ大文字(2 回押すと固定) / #+=: 記号 / ←: 1 文字消す / 完了: 入力を終える(フォーカスを外す)
// キーはフォーカスを取らない(MouseArea だけ)ので、押しても入力欄のフォーカスは外れない。
import QtQuick
import OpenCruise

Rectangle {
    id: kb
    /// 文字を入れる先(フォーカスのある部品)。入力欄でなければ出さない
    property Item target: null
    readonly property bool editable: target !== null && target.insert !== undefined && target.cursorPosition !== undefined
                                     && target.readOnly !== true
    readonly property real unit: Theme.uiScale
    // 0 = 小文字 / 1 = 次の 1 文字だけ大文字 / 2 = 大文字に固定
    property int shift: 0
    property bool symbols: false
    property bool hiddenByUser: false
    onTargetChanged: { hiddenByUser = false; shift = 0 }
    readonly property bool shown: editable && !hiddenByUser

    readonly property var letterRows: ["1234567890", "qwertyuiop", "asdfghjkl@", "zxcvbnm-_."]
    readonly property var symbolRows: ["1234567890", "!@#$%^&*()", "~`'\"+=/\\|?", "[]{}<>;:,."]
    readonly property var rows: symbols ? symbolRows : letterRows

    height: Math.round(Math.min(parent ? parent.height * 0.42 : 300, 360 * unit))
    color: Theme.mix(Theme.background, Theme.panel, 0.5)
    border.color: Theme.panelBorder
    y: parent ? (shown ? parent.height - height : parent.height + 8) : 0
    visible: y < (parent ? parent.height : 0)
    Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    // 後ろへタッチを通さない
    MouseArea { anchors.fill: parent }

    function put(ch) {
        if (!editable) return
        const c = shift > 0 && !symbols ? ch.toUpperCase() : ch
        if (target.selectedText !== undefined && target.selectedText.length > 0) target.remove(target.selectionStart, target.selectionEnd)
        target.insert(target.cursorPosition, c)
        if (shift === 1) shift = 0
    }
    function backspace() {
        if (!editable) return
        if (target.selectedText !== undefined && target.selectedText.length > 0) { target.remove(target.selectionStart, target.selectionEnd); return }
        if (target.cursorPosition > 0) target.remove(target.cursorPosition - 1, target.cursorPosition)
    }
    function done() {
        if (target && target.accepted !== undefined) target.accepted()
        if (target) target.focus = false
        hiddenByUser = true
    }

    component Key: Rectangle {
        id: key
        property string label: ""
        property string icon: ""
        property real units: 1
        property bool accent: false
        signal pressed()
        width: (keys.width - 9 * keys.spacing) / 10 * units + (units - 1) * keys.spacing
        height: (keys.height - 4 * keys.spacing) / 5
        radius: Theme.radius * 0.6
        color: keyMouse.pressed ? Theme.accentFill : (accent ? Theme.mix(Theme.panel, Theme.accent, 0.25) : Theme.panel)
        border.color: Theme.panelBorder
        Text {
            visible: key.icon === ""
            anchors.centerIn: parent
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(key.height * 0.45)
            color: Theme.textPrimary
            text: key.label
        }
        MaterialIcon {
            visible: key.icon !== ""
            anchors.centerIn: parent
            name: key.icon
            size: Math.round(key.height * 0.55)
            color: Theme.textPrimary
        }
        MouseArea {
            id: keyMouse
            anchors.fill: parent
            onPressed: key.pressed()
            // 消すキーは押しっぱなしで続けて消す
            pressAndHoldInterval: 400
            onPressAndHold: if (key.icon === "backspace") repeatTimer.start()
            onReleased: repeatTimer.stop()
            onCanceled: repeatTimer.stop()
            Timer { id: repeatTimer; interval: 70; repeat: true; onTriggered: key.pressed() }
        }
    }

    Column {
        id: keys
        anchors { fill: parent; margins: 8 * kb.unit }
        spacing: 6 * kb.unit
        Repeater {
            model: kb.rows
            Row {
                required property string modelData
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: keys.spacing
                Repeater {
                    model: modelData.length
                    Key {
                        required property int index
                        readonly property string ch: parent.modelData.charAt(index)
                        label: kb.shift > 0 && !kb.symbols ? ch.toUpperCase() : ch
                        onPressed: kb.put(ch)
                    }
                }
            }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: keys.spacing
            Key { units: 1.5; icon: kb.shift === 2 ? "keyboard_capslock" : "arrow_upward"; accent: kb.shift > 0
                  opacity: kb.symbols ? 0.4 : 1
                  onPressed: if (!kb.symbols) kb.shift = (kb.shift + 1) % 3 }
            Key { units: 1.5; label: kb.symbols ? "abc" : "#+="; onPressed: kb.symbols = !kb.symbols }
            Key { units: 3; label: "space"; onPressed: kb.put(" ") }
            Key { units: 1.5; icon: "backspace"; onPressed: kb.backspace() }
            Key { units: 2; label: "完了"; accent: true; onPressed: kb.done() }
        }
    }
}
