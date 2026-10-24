// 設定用の折り返し式カラーパレット。
import QtQuick
import OpenCruise

Item {
    id: root
    property var options: []
    property string selectedValue: ""
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
                width: 68 * root.unit
                height: 78 * root.unit

                Rectangle {
                    id: swatch
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 52 * root.unit
                    height: width
                    radius: width / 2
                    color: modelData.value === "theme" ? Theme.accent
                           : (modelData.value === "panel" ? Theme.panel : modelData.value)
                    border.width: root.selectedValue === modelData.value ? 3 * root.unit : 1
                    border.color: root.selectedValue === modelData.value ? Theme.textPrimary : Theme.panelBorder

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
