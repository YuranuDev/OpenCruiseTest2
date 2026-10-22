// 車両情報パネル(Android Auto 表示領域の右側)。
// モックの車両データ送信が ON の間は、Android Auto へ送っている値を小さい文字の一覧で全部表示する。
// OFF の間は案内だけを出す。
import QtQuick

Rectangle {
    color: Theme.panel
    radius: Theme.radius
    border.color: Theme.panelBorder

    readonly property bool mockOn: androidAuto.mockVehicleData

    // ---- タイトル行 ----
    Row {
        id: titleRow
        anchors { top: parent.top; left: parent.left; margins: 14 }
        spacing: 8
        Text {
            font.family: Theme.fontFamily
            text: "車両情報"
            color: Theme.textSecondary
            font.pixelSize: 18
            anchors.verticalCenter: parent.verticalCenter
        }
        Rectangle {
            visible: mockOn
            width: tag.implicitWidth + 14
            height: 22
            radius: 11
            color: "transparent"
            border.color: Theme.warn
            anchors.verticalCenter: parent.verticalCenter
            Text {
                id: tag
                font.family: Theme.fontFamily
                anchors.centerIn: parent
                text: "モック送信中"
                color: Theme.warn
                font.pixelSize: 12
            }
        }
    }

    // ---- モック ON: 送信中の値の一覧 ----
    ListView {
        id: list
        visible: mockOn
        anchors { top: titleRow.bottom; topMargin: 8; left: parent.left; right: parent.right; bottom: parent.bottom
                  leftMargin: 14; rightMargin: 14; bottomMargin: 10 }
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        model: androidAuto.mockVehicleItems

        delegate: Item {
            required property var modelData
            width: list.width
            height: 24

            Text {
                font.family: Theme.fontFamily
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: modelData.label
                color: Theme.textSecondary
                font.pixelSize: 13
            }
            Text {
                font.family: Theme.fontFamily
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: modelData.value
                color: Theme.textPrimary
                font.pixelSize: 14
            }
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color: Theme.panelBorder
            }
        }
    }

    // ---- モック OFF: 案内 ----
    Text {
        visible: !mockOn
        font.family: Theme.fontFamily
        anchors { top: titleRow.bottom; topMargin: 12; left: parent.left; right: parent.right
                  leftMargin: 14; rightMargin: 14 }
        wrapMode: Text.WordWrap
        text: "モックの車両データ送信は OFF です。\n設定 > 車両 で ON にすると、Android Auto へ送る値がここに一覧表示されます。"
        color: Theme.textSecondary
        font.pixelSize: 13
    }
}
