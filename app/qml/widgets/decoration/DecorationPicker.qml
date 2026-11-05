// 飾りの画像(キャラなど)の追加パネル。画像のフォルダ(themeSettings.decorationFolder)にある画像を並べ、
// タップすると今のページの中央に置いて閉じる(置いたものは選ばれた状態になる)。
import QtQuick
import OpenCruise

Item {
    id: root
    property Item store: null
    property bool open: false
    readonly property real unit: Theme.uiScale

    function show() { themeSettings.refreshDecorationImages(); open = true }
    function close() { open = false }

    visible: scrim.opacity > 0

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "black"
        opacity: root.open ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; enabled: root.open; onClicked: root.close() }
    }

    Panel {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Theme.margin, 980 * root.unit)
        height: Math.min(parent.height - 2 * Theme.margin, 680 * root.unit)
        radius: Theme.radius + 8
        scale: root.open ? 1 : 0.92
        opacity: root.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea { anchors.fill: parent }

        // ---- 上段: タイトル・読み直す・閉じる ----
        Item {
            id: head
            anchors { top: parent.top; left: parent.left; right: parent.right
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5 }
            height: 84 * root.unit
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: 30 * root.unit
                color: Theme.textPrimary
                text: "画像を追加"
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 10 * root.unit
                ActionButton {
                    text: "読み直す"
                    onClicked: themeSettings.refreshDecorationImages()
                }
                ActionButton {
                    text: "閉じる"
                    onClicked: root.close()
                }
            }
        }

        // ---- 中段: 画像の一覧 ----
        GridView {
            id: grid
            anchors { top: head.bottom; bottom: foot.top; left: parent.left; right: parent.right
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5 }
            clip: true
            readonly property int columns: Math.max(2, Math.floor(width / (190 * root.unit)))
            cellWidth: width / columns
            cellHeight: cellWidth * 1.12
            boundsBehavior: Flickable.StopAtBounds
            model: root.open ? themeSettings.decorationImages : []

            delegate: Item {
                id: cell
                required property string modelData
                width: grid.cellWidth
                height: grid.cellHeight
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 6 * root.unit
                    radius: Theme.radius
                    color: Theme.mix(Theme.background, Theme.accent, cellMouse.pressed ? 0.3 : 0.04)
                    border.color: cellMouse.pressed ? Theme.accent : Theme.panelBorder
                    Item {
                        id: thumbBox
                        anchors { top: parent.top; left: parent.left; right: parent.right; bottom: nameText.top; margins: 8 * root.unit }
                        Image {
                            id: thumb
                            anchors.fill: parent
                            source: themeSettings.decorationUrl(cell.modelData)
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            sourceSize.width: 320
                            smooth: true
                        }
                        MaterialIcon {
                            anchors.centerIn: parent
                            visible: thumb.status === Image.Error
                            name: "broken_image"
                            size: 40 * root.unit
                            color: Theme.textSecondary
                        }
                    }
                    Text {
                        id: nameText
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 8 * root.unit }
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideMiddle
                        font.family: Theme.fontFamily
                        font.pixelSize: 16 * root.unit
                        color: Theme.textSecondary
                        text: cell.modelData
                    }
                }
                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    enabled: thumb.status === Image.Ready
                    onClicked: {
                        if (!root.store) return
                        root.store.add(cell.modelData, thumb.implicitWidth > 0 ? thumb.implicitHeight / thumb.implicitWidth : 1)
                        root.close()
                    }
                }
            }
        }

        // 1 つも無いとき
        Column {
            anchors.centerIn: grid
            width: grid.width
            spacing: 12 * root.unit
            visible: grid.count === 0
            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "add_photo_alternate"
                size: 56 * root.unit
                color: Theme.textSecondary
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                font.family: Theme.fontFamily
                font.pixelSize: 22 * root.unit
                color: Theme.textSecondary
                text: "画像がありません。下のフォルダに PNG などの画像を入れて「読み直す」を押してください"
            }
        }

        // ---- 下段: フォルダの場所 ----
        Text {
            id: foot
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5; bottomMargin: 16 * root.unit }
            wrapMode: Text.WrapAnywhere
            font.family: Theme.fontFamily
            font.pixelSize: 17 * root.unit
            color: Theme.textSecondary
            text: "画像のフォルダ: " + themeSettings.decorationFolder + "\n透過 PNG ならキャラだけを切り抜いて置けます。置いた後は、ドラッグで移動・右下のつまみで大きさを変えられます"
        }
    }
}
