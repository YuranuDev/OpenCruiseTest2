// 設定用の 1 行テキスト入力。1 文字ごとに changing(text)(表示だけ反映)、入力が止まって少し経ったときと
// 確定(Enter / フォーカス移動 / 閉じる)のときに edited(text)(保存)を出す。
//   WSTextField { text: config.message; placeholder: "..."; maxLength: 24; onEdited: (t) => root.edit("message", t) }
// 入力のたびに反映するのは、確定操作をしないまま他の設定を触ったり「完了」で閉じたりしても、入力が失われないようにするため
// (text は設定値に束縛されているので、他の設定の変更で設定が読み直されると、未反映の入力は保存値で上書きされてしまう)。
import QtQuick
import OpenCruise
import QtQuick.Controls

TextField {
    id: root
    property string placeholder: ""
    property int maxLength: 30
    signal edited(string text)     // 保存してよいタイミング(確定・入力が止まって少し経ったとき・閉じるとき)
    signal changing(string text)   // 1 文字ごと(画面へのリアルタイム反映用。保存はしない)

    // 保留中の入力をすぐ反映する(閉じる前などに外から呼べる)
    function commit() {
        if (!pending.running) return
        pending.stop()
        root.edited(root.text)
    }

    readonly property real unit: Theme.uiScale
    width: 420 * unit
    height: 64 * unit
    placeholderText: placeholder
    maximumLength: maxLength
    font.family: Theme.fontFamily
    font.pixelSize: 24 * unit
    color: Theme.textPrimary
    placeholderTextColor: Theme.textSecondary
    selectByMouse: true
    leftPadding: 18 * unit
    rightPadding: 18 * unit
    verticalAlignment: TextInput.AlignVCenter

    background: Rectangle {
        radius: Theme.radius
        color: Theme.panel
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? Theme.accent : Theme.panelBorder
    }

    // 入力が止まって少し経ったら保存(1 文字ごとには保存しない)
    Timer {
        id: pending
        interval: 1200
        onTriggered: root.edited(root.text)
    }
    onTextEdited: { root.changing(text); pending.restart() }
    onEditingFinished: { pending.stop(); root.edited(text) }
    onVisibleChanged: if (!visible) commit()
}
