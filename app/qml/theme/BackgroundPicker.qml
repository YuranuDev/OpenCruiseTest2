// 壁紙の種類・画像をプレビューから選ぶパネル。画像を選ぶと種類も「画像」に切り替わる。
import QtQuick
import OpenCruise

Item {
    id: root
    property bool open: false
    property bool fitSelection: false
    property string selectedKind: "auto"
    property string selectedImage: ""
    property int previewOpacity: 60
    property int previewFit: 1
    readonly property real unit: Theme.uiScale
    signal picked(string kind, string file)
    signal fitPicked(int fit)

    readonly property var entries: {
        const result = [
            { label: "テーマに合わせる", value: "auto", file: "" },
            { label: "無地", value: "none", file: "" },
            { label: "カーボン", value: "carbon", file: "" },
            { label: "ヘアライン", value: "brushed", file: "" },
            { label: "パンチング", value: "dots", file: "" },
            { label: "ストライプ", value: "stripes", file: "" }
        ]
        const images = themeSettings.backgroundImages
        if (images.length === 0) {
            result.push({ label: "画像を使う", value: "image", file: "" })
        } else {
            for (let i = 0; i < images.length; ++i)
                result.push({ label: images[i], value: "image", file: images[i] })
        }
        return result
    }
    readonly property var fitEntries: [
        { label: "並べる", fit: 0 },
        { label: "画面を埋める", fit: 1 },
        { label: "引き伸ばす", fit: 2 }
    ]

    function show() {
        themeSettings.refreshBackgroundImages()
        fitSelection = false
        open = true
    }
    function showFit() {
        fitSelection = true
        open = true
    }
    function close() { open = false; fitSelection = false }

    visible: open || scrim.opacity > 0

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
                text: (root.fitSelection ? "画像の表示方法" : "壁紙を選択")
                      + " (" + (themeSettings.nightMode ? "夜" : "昼") + ")"
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 10 * root.unit
                ActionButton {
                    text: root.fitSelection ? "壁紙に戻る" : "読み直す"
                    onClicked: root.fitSelection ? root.show() : themeSettings.refreshBackgroundImages()
                }
                ActionButton {
                    text: "閉じる"
                    onClicked: root.close()
                }
            }
        }

        GridView {
            id: grid
            anchors { top: head.bottom; bottom: foot.top; left: parent.left; right: parent.right
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5 }
            clip: true
            readonly property int columns: Math.max(2, Math.floor(width / (210 * root.unit)))
            cellWidth: width / columns
            cellHeight: cellWidth * 0.78
            boundsBehavior: Flickable.StopAtBounds
            model: root.open ? (root.fitSelection ? root.fitEntries : root.entries) : []

            delegate: Item {
                id: cell
                required property var modelData
                width: grid.cellWidth
                height: grid.cellHeight
                readonly property bool isFit: root.fitSelection
                readonly property bool isImage: !isFit && modelData.value === "image"
                readonly property string fileName: isFit ? root.selectedImage : (isImage ? modelData.file : "")
                readonly property bool selected: isFit ? root.previewFit === modelData.fit
                                               : root.selectedKind === modelData.value
                                                 && (!isImage || root.selectedImage === modelData.file)

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 6 * root.unit
                    radius: Theme.radius
                    color: Theme.mix(Theme.background, Theme.accent, tileMouse.pressed ? 0.26 : 0.04)
                    border.width: cell.selected ? 3 : 1
                    border.color: cell.selected || tileMouse.pressed ? Theme.accent : Theme.panelBorder

                    Item {
                        id: preview
                        anchors { top: parent.top; left: parent.left; right: parent.right; bottom: label.top
                                  margins: 8 * root.unit }
                        clip: true
                        ThemeBackground {
                            anchors.fill: parent
                            visible: !cell.isImage && !cell.isFit
                            kindOverride: cell.isFit ? "none" : cell.modelData.value
                            opacityOverride: root.previewOpacity
                            fitOverride: cell.isFit ? cell.modelData.fit : root.previewFit
                        }
                        Rectangle {
                            anchors.fill: parent
                            visible: cell.isImage || cell.isFit
                            color: Theme.background
                            Image {
                                id: filePreview
                                anchors.fill: parent
                                visible: (cell.isImage || cell.isFit) && cell.fileName !== ""
                                source: visible ? themeSettings.backgroundUrl(cell.fileName) : ""
                                asynchronous: true
                                cache: false
                                readonly property int fit: cell.isFit ? cell.modelData.fit : root.previewFit
                                fillMode: fit === 0 ? Image.Tile : (fit === 2 ? Image.Stretch : Image.PreserveAspectCrop)
                                opacity: root.previewOpacity / 100
                                sourceSize.width: 480
                                smooth: true
                            }
                            MaterialIcon {
                                anchors.centerIn: parent
                                visible: (cell.isImage || cell.isFit)
                                         && (cell.fileName === "" || filePreview.status === Image.Error)
                                name: "image"
                                size: 42 * root.unit
                                color: Theme.textSecondary
                            }
                        }
                    }

                    Text {
                        id: label
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right
                                  margins: 8 * root.unit }
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideMiddle
                        font.family: Theme.fontFamily
                        font.pixelSize: 16 * root.unit
                        color: cell.selected ? Theme.accent : Theme.textSecondary
                        text: cell.modelData.label
                    }
                }

                MouseArea {
                    id: tileMouse
                    anchors.fill: parent
                    enabled: cell.isFit ? cell.fileName === "" || filePreview.status === Image.Ready
                                        : (!cell.isImage || cell.fileName === "" || filePreview.status === Image.Ready)
                    onClicked: {
                        if (cell.isFit) root.fitPicked(cell.modelData.fit)
                        else root.picked(cell.modelData.value, cell.modelData.file)
                        root.close()
                    }
                }
            }
        }

        Text {
            id: foot
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right
                      leftMargin: Theme.margin * 1.5; rightMargin: Theme.margin * 1.5; bottomMargin: 16 * root.unit }
            wrapMode: Text.WrapAnywhere
            font.family: Theme.fontFamily
            font.pixelSize: 17 * root.unit
            color: Theme.textSecondary
            text: root.fitSelection
                  ? "画像の表示方法を選ぶと、昼夜別の設定に保存されます"
                  : "画像フォルダ: " + themeSettings.backgroundFolder + "\n画像を選ぶと昼夜別の壁紙に設定されます"
        }
    }
}
