// CAN 情報（現在はダミーデータ）の表示パネル。速度・回転数・水温・燃料。
import QtQuick

Rectangle {
    color: Theme.panel
    radius: Theme.radius
    border.color: Theme.panelBorder

    Column {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 14

        Row {
            spacing: 8
            Text { text: "車両情報"; color: Theme.textSecondary; font.pixelSize: 20 }
            Rectangle {
                width: tag.implicitWidth + 16
                height: 26
                radius: 13
                color: "transparent"
                border.color: Theme.warn
                Text { id: tag; anchors.centerIn: parent; text: can.sourceText; color: Theme.warn; font.pixelSize: 14 }
            }
        }

        Column {
            Text { text: "速度"; color: Theme.textSecondary; font.pixelSize: 18 }
            Row {
                spacing: 8
                Text { text: can.speedKmh; color: Theme.textPrimary; font.pixelSize: 84; font.bold: true }
                Text { text: "km/h"; color: Theme.textSecondary; font.pixelSize: 22; anchors.baseline: undefined; y: 52 }
            }
        }

        Column {
            width: parent.width
            spacing: 6
            Row {
                spacing: 8
                Text { text: "回転数"; color: Theme.textSecondary; font.pixelSize: 18 }
                Text { text: can.rpm + " rpm"; color: Theme.textPrimary; font.pixelSize: 22 }
            }
            Rectangle {
                width: parent.width
                height: 10
                radius: 5
                color: Theme.panelBorder
                Rectangle {
                    height: parent.height
                    radius: 5
                    width: parent.width * Math.min(1, can.rpm / 7000)
                    color: can.rpm > 5500 ? Theme.error : Theme.accent
                }
            }
        }

        Row {
            spacing: 28
            Column {
                Text { text: "水温"; color: Theme.textSecondary; font.pixelSize: 18 }
                Text { text: can.coolantTempC + " ℃"; color: Theme.textPrimary; font.pixelSize: 30 }
            }
            Column {
                Text { text: "燃料"; color: Theme.textSecondary; font.pixelSize: 18 }
                Text { text: can.fuelPercent + " %"; color: Theme.textPrimary; font.pixelSize: 30 }
            }
        }
    }
}
