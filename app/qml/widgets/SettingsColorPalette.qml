// 設定用の折り返し式カラーパレット。
import QtQuick
import OpenCruise

Item {
    id: root
    property var options: []
    property string selectedValue: ""
    // true なら、選択中の色にチェックマークも出す(色だけに頼らない)
    property bool showCheck: false
    // 見本の丸の直径(基準値。uiScale を掛ける)
    property real swatchSize: 52
    signal picked(string value)

    readonly property real unit: Theme.uiScale
    implicitHeight: flow.implicitHeight
    height: implicitHeight

    Flow {
        id: flow
        width: root.width
        spacing: 8 * root.unit

        Repeater {
            model: root.options

            delegate: Item {
                required property var modelData
                width: (root.swatchSize + 16) * root.unit
                height: (root.swatchSize + 26) * root.unit

                Rectangle {
                    id: swatch
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.swatchSize * root.unit
                    height: width
                    radius: width / 2
                    // swatch があれば見本にその色を使う(「針と同じ」など、値が色そのものでない選択肢)
                    color: modelData.swatch !== undefined ? modelData.swatch
                           : modelData.value === "theme" ? Theme.accent
                           : (modelData.value === "panel" ? Theme.panel : modelData.value)
                    border.width: root.selectedValue === modelData.value ? 3 * root.unit : 1
                    border.color: root.selectedValue === modelData.value ? Theme.textPrimary : Theme.panelBorder

                    MaterialIcon {
                        visible: root.showCheck && root.selectedValue === modelData.value
                        anchors.centerIn: parent
                        name: "check"
                        size: Math.round(parent.width * 0.6)
                        color: "#0d1015"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.picked(modelData.value)
                    }
                }
                Text {
                    anchors { top: swatch.bottom; left: parent.left; right: parent.right }
                    height: 22 * root.unit
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: 14 * root.unit
                    color: Theme.textSecondary
                    text: modelData.label
                    elide: Text.ElideRight
                }
            }
        }
    }
}
