// メーターの「見た目」を選ぶタイル(GaugeSettings)。円形の 6 種類と、円形ではない 5 種類を、アイコン・名前・ひとことの
// 説明つきで並べる(名前だけのボタンでは、どんな見た目か分からなかったため)。計測値に合うものには「おすすめ」を付ける。
import QtQuick
import OpenCruise

Column {
    id: root
    property string current: "classic"
    /// おすすめの見た目の id(無ければ空)
    property var recommended: []
    signal picked(string look)

    readonly property real unit: Theme.uiScale
    spacing: 10 * unit

    readonly property var sections: [
        { title: "円形のメーター", items: [
            { id: "classic", name: "クラシック", icon: "speed", desc: "目盛り・警告帯・針" },
            { id: "minimal", name: "シンプル", icon: "data_usage", desc: "細い進捗リングと針" },
            { id: "marker", name: "マーカー", icon: "navigation", desc: "外周を印が動く・大きな数値" },
            { id: "retro", name: "レトロ", icon: "watch", desc: "クリーム色の文字盤と赤い針" },
            { id: "neon", name: "ネオン", icon: "flare", desc: "暗い文字盤に光る細い線" },
            { id: "ring", name: "リング", icon: "donut_large", desc: "太いリング・針なし" }
        ] },
        { title: "そのほかの見た目", items: [
            { id: "trend", name: "数値+推移", icon: "mdi:chart-line", desc: "大きな数値と直近の折れ線" },
            { id: "center", name: "センター基準", icon: "mdi:arrow-left-right", desc: "基準値から左右へ伸びるバー" },
            { id: "shift", name: "シフトライト", icon: "mdi:led-strip-variant", desc: "ランプの列。変速で全点滅" },
            { id: "tank", name: "タンク", icon: "mdi:water", desc: "容器の中の液面(残量向け)" },
            { id: "histogram", name: "分布", icon: "mdi:chart-bar", desc: "この走行でどの値が多かったか" }
        ] }
    ]

    Repeater {
        model: root.sections
        Column {
            required property var modelData
            width: root.width
            spacing: 8 * root.unit
            Text {
                font.family: Theme.fontFamily
                font.pixelSize: 20 * root.unit
                font.bold: true
                color: Theme.textSecondary
                text: modelData.title
            }
            Flow {
                width: parent.width
                spacing: 10 * root.unit
                Repeater {
                    model: modelData.items
                    Rectangle {
                        id: tile
                        required property var modelData
                        readonly property bool selected: root.current === modelData.id
                        readonly property bool rec: root.recommended.indexOf(modelData.id) >= 0
                        // 幅が足りれば 3 列、狭ければ 2 列
                        readonly property int cols: root.width >= 760 * root.unit ? 3 : 2
                        width: (root.width - (cols - 1) * 10 * root.unit) / cols
                        height: 96 * root.unit
                        radius: Theme.radius
                        color: selected ? Theme.accentFill : Theme.mix(Theme.background, Theme.accentFill, tileMouse.pressed ? 0.45 : 0)
                        border.width: selected || tileMouse.pressed ? 2 : 1
                        border.color: selected || tileMouse.pressed ? Theme.accent : Theme.panelBorder
                        scale: tileMouse.pressed ? 0.98 : 1
                        Behavior on scale { NumberAnimation { duration: 90 } }
                        MaterialIcon {
                            id: tileIcon
                            anchors { left: parent.left; leftMargin: 16 * root.unit; verticalCenter: parent.verticalCenter }
                            name: tile.modelData.icon
                            size: 40 * root.unit
                            color: tile.selected ? Theme.textOnAccent : Theme.accent
                        }
                        Column {
                            anchors { left: tileIcon.right; leftMargin: 12 * root.unit; right: parent.right; rightMargin: 10 * root.unit
                                      verticalCenter: parent.verticalCenter }
                            spacing: 2 * root.unit
                            Row {
                                spacing: 8 * root.unit
                                Text {
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 23 * root.unit
                                    font.bold: true
                                    color: tile.selected ? Theme.textOnAccent : Theme.textPrimary
                                    text: tile.modelData.name
                                }
                                Rectangle {
                                    visible: tile.rec
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: recText.implicitWidth + 14 * root.unit
                                    height: recText.implicitHeight + 4 * root.unit
                                    radius: height / 2
                                    color: tile.selected ? Theme.textOnAccent : Theme.accent
                                    Text {
                                        id: recText
                                        anchors.centerIn: parent
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 15 * root.unit
                                        font.bold: true
                                        color: tile.selected ? Theme.accent : Theme.textOnAccent
                                        text: "おすすめ"
                                    }
                                }
                            }
                            Text {
                                width: parent.width
                                font.family: Theme.fontFamily
                                font.pixelSize: 17 * root.unit
                                color: tile.selected ? Theme.textOnAccent : Theme.textSecondary
                                elide: Text.ElideRight
                                text: tile.modelData.desc
                            }
                        }
                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            onClicked: root.picked(tile.modelData.id)
                        }
                    }
                }
            }
        }
    }
}
