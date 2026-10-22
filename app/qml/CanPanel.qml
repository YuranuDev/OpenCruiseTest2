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
            Text { font.family: Theme.fontFamily; text: "車両情報"; color: Theme.textSecondary; font.pixelSize: 20 }
            Rectangle {
                width: tag.implicitWidth + 16
                height: 26
                radius: 13
                color: "transparent"
                border.color: Theme.warn
                Text { font.family: Theme.fontFamily; id: tag; anchors.centerIn: parent; text: can.sourceText; color: Theme.warn; font.pixelSize: 14 }
            }
        }

        Column {
            Text { font.family: Theme.fontFamily; text: "速度"; color: Theme.textSecondary; font.pixelSize: 18 }
            Row {
                spacing: 8
                Text { font.family: Theme.fontFamily; text: can.speedKmh; color: Theme.textPrimary; font.pixelSize: 84; font.bold: true }
                Text { font.family: Theme.fontFamily; text: "km/h"; color: Theme.textSecondary; font.pixelSize: 22; anchors.baseline: undefined; y: 52 }
            }
        }

        Column {
            width: parent.width
            spacing: 6
            Row {
                spacing: 8
                Text { font.family: Theme.fontFamily; text: "回転数"; color: Theme.textSecondary; font.pixelSize: 18 }
                Text { font.family: Theme.fontFamily; text: can.rpm + " rpm"; color: Theme.textPrimary; font.pixelSize: 22 }
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
                Text { font.family: Theme.fontFamily; text: "水温"; color: Theme.textSecondary; font.pixelSize: 18 }
                Text { font.family: Theme.fontFamily; text: can.coolantTempC + " ℃"; color: Theme.textPrimary; font.pixelSize: 30 }
            }
            Column {
                Text { font.family: Theme.fontFamily; text: "燃料"; color: Theme.textSecondary; font.pixelSize: 18 }
                Text { font.family: Theme.fontFamily; text: can.fuelPercent + " %"; color: Theme.textPrimary; font.pixelSize: 30 }
            }
        }
    }
}
