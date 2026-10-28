// 飾りの画像(キャラなど)を描く層。layerName の画像だけを描く。
//  "back"(奥)と "front"(手前)は初期画面に 1 枚ずつ置く。"panel"(パネル)は各ウィジェットの中(パネルと中身の間)に
//  WidgetBase が置き、画面全体の大きさのこの層を、ウィジェットの位置の分だけずらしてパネルの形に切り抜く。
// タッチは受けない(手前の画像の上を押しても、下のウィジェット・ボタンに届く)。
// 位置・大きさは DecorationStore の割合(画面の幅・高さに対する)から決める。
import QtQuick
import OpenCruise

Item {
    id: root
    property Item store: null
    property string layerName: "back"
    // 編集中(画像を置き直している間)は、画像が見つからないものも枠で出す
    property bool editing: false

    // ページを切り替えたら、ふわっと出し直す
    NumberAnimation { id: fadeIn; target: root; property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutQuad }
    Connections {
        target: root.store
        function onReloaded() { fadeIn.restart() }
    }

    Repeater {
        model: root.store ? root.store.model : null
        Item {
            id: deco
            required property string did
            required property string file
            required property real rx
            required property real ry
            required property real rw
            required property real ar
            required property real op
            required property bool flip
            required property string zone
            readonly property string url: { themeSettings.decorationImages; return themeSettings.decorationUrl(file) }
            readonly property bool mine: zone === root.layerName
            visible: mine
            x: root.width * rx
            y: root.height * ry
            width: root.width * rw
            height: width * ar

            Image {
                id: img
                anchors.fill: parent
                source: deco.mine ? deco.url : ""   // ほかの層の画像は読み込まない
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                opacity: deco.op
                // 画面に出す大きさに合わせて読み込む(大きな画像でもメモリを食いすぎない)。
                // 大きさを変えるたびに読み直さないよう、64px 刻みにする
                sourceSize.width: Math.min(2048, Math.ceil(deco.width * 1.25 / 64) * 64)
                transform: Scale { origin.x: img.width / 2; xScale: deco.flip ? -1 : 1 }
                onStatusChanged: {
                    if (status === Image.Ready && implicitWidth > 0 && root.store)
                        root.store.noteAspect(deco.did, implicitHeight / implicitWidth)
                }
            }
            // 画像が見つからない・読めないとき(編集中だけ出す。消せるように)
            Rectangle {
                anchors.fill: parent
                visible: root.editing && deco.mine && (deco.url === "" || img.status === Image.Error)
                color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.12)
                border.width: 2
                border.color: Theme.error
                radius: Theme.radius
                Text {
                    anchors.fill: parent
                    anchors.margins: 6
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WrapAnywhere
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(10, Math.min(18, parent.width / 10))
                    color: Theme.error
                    text: "画像が見つかりません\n" + deco.file
                }
            }
        }
    }
}
