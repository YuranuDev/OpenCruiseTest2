// 横並びの大型選択ボタン(排他選択)。選択中はアクセント色の塗り + チェックマークで、色が分からなくても判別できる。
//   SettingsChoice { model: ["昼", "夜", "自動"]; currentIndex: androidAuto.themeMode; onPicked: (i) => androidAuto.themeMode = i }
// 押しても currentIndex は自動では変わらない。picked で受けた側が設定を書き換え、currentIndex の束縛で見た目へ反映する。
// 選択肢が多くて 1 行に入りきらないときは、折り返して 2 行以上にする。使える幅は、置かれた SettingsRow の
// controlMaxWidth(項目名の下に置くときは行の幅、右に置くときは行の幅の約 6 割)。maxWidth で直接決めてもよい。
import QtQuick

Flow {
    id: root
    property var model: []
    property int currentIndex: -1
    signal picked(int index)

    readonly property real unit: Theme.uiScale
    // 使える幅(SettingsRow の中なら自動。それ以外は制限なし)
    property real maxWidth: parent && parent.parent && parent.parent.controlMaxWidth !== undefined
                            ? parent.parent.controlMaxWidth : 1e6
    // 各ボタンの幅(ボタン自身が、作られたとき・幅が変わったときに知らせる)。
    // Repeater.itemAt() で読むと、作られる順番によっては、まだボタンが無い時点の幅(ほぼ 0)のまま計算し直されず、
    // ボタンが 1 つずつ折り返して右へはみ出すことがある(環境・解像度によって起きる)ので、ボタンから知らせてもらう
    property var itemWidths: []
    property int itemsRevision: 0
    function setItemWidth(i, w) {
        if (itemWidths[i] === w) return
        const list = itemWidths.slice()
        list[i] = w
        itemWidths = list
        ++itemsRevision
    }
    readonly property int itemCount: model ? (model.length !== undefined ? model.length : buttons.count) : 0
    // 1 行に並べたときの幅(まだ幅を知らせていないボタンは、ボタンの最小の幅で見積もる)
    readonly property real naturalWidth: {
        itemsRevision
        let w = 0
        for (let i = 0; i < itemCount; ++i) {
            const iw = itemWidths[i]
            w += iw > 0 ? iw : 112 * unit
        }
        return w + spacing * Math.max(0, itemCount - 1)
    }

    spacing: 10 * unit
    // 小数の誤差で最後のボタンが折り返さないよう、少しだけ余裕を持たせる
    width: Math.max(1, Math.min(Math.ceil(naturalWidth) + 1, maxWidth))

    Repeater {
        id: buttons
        model: root.model

        Rectangle {
            id: btn
            readonly property bool selected: index === root.currentIndex

            implicitWidth: Math.max(112 * root.unit, content.implicitWidth + 44 * root.unit)
            width: implicitWidth
            onImplicitWidthChanged: root.setItemWidth(index, implicitWidth)
            Component.onCompleted: root.setItemWidth(index, implicitWidth)
            height: 64 * root.unit
            radius: Theme.radius
            color: selected ? Theme.accentFill
                            : Theme.mix(Theme.background, Theme.accentFill, mouse.pressed ? 0.45 : 0)
            border.width: selected || mouse.pressed ? 2 : 1
            border.color: selected || mouse.pressed ? Theme.accent : Theme.panelBorder
            scale: mouse.pressed ? 0.97 : 1.0
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

            Row {
                id: content
                anchors.centerIn: parent
                spacing: 8 * root.unit

                MaterialIcon {
                    visible: modelData && modelData.icon !== undefined
                    anchors.verticalCenter: parent.verticalCenter
                    name: modelData && modelData.icon !== undefined ? modelData.icon : "check"
                    size: 28 * root.unit
                    color: btn.selected ? Theme.textOnAccent : Theme.accent
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    text: modelData && modelData.label !== undefined ? modelData.label : modelData
                    color: btn.selected ? Theme.textOnAccent : Theme.textPrimary
                    font.pixelSize: 24 * root.unit
                    font.bold: btn.selected
                }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                onClicked: { root.picked(index) }
            }
        }
    }
}
