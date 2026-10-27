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
    // ボタンが作られた・消えたときに増える(naturalWidth を計算し直すため。itemAt() の結果の変化は通知されないので、
    // これが無いと、ボタンがまだ作られていない時点の幅(ほぼ 0)のままになり、ボタンが 1 つずつ折り返して右へはみ出す)
    property int itemsRevision: 0
    // 1 行に並べたときの幅
    readonly property real naturalWidth: {
        itemsRevision
        let w = 0
        for (let i = 0; i < buttons.count; ++i) {
            const it = buttons.itemAt(i)
            if (it) w += it.implicitWidth
        }
        return w + spacing * Math.max(0, buttons.count - 1)
    }

    spacing: 10 * unit
    width: Math.max(1, Math.min(naturalWidth, maxWidth))

    Repeater {
        id: buttons
        model: root.model
        onItemAdded: root.itemsRevision++
        onItemRemoved: root.itemsRevision++

        Rectangle {
            id: btn
            readonly property bool selected: index === root.currentIndex

            implicitWidth: Math.max(112 * root.unit, content.implicitWidth + 44 * root.unit)
            width: implicitWidth
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
