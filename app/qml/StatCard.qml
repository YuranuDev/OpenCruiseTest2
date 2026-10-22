// システム情報 1 項目分の小さなカード(CPU / GPU / メモリ用)。
//   StatCard { title: "CPU"; percent: systemStats.cpuPercent; detail: "3.4 GHz · 62 ℃" }
// percent が負なら「取得不可」として、値を「--」・バーを空にする。
// 使用率が高いほどバーの色が accent → warn → error に変わる。
import QtQuick

Rectangle {
    id: root
    property string title: ""
    property int percent: -1
    property string detail: ""
    // 画面サイズに応じた拡大率(呼び出し側から渡す。既定は Theme.uiScale)
    property real unit: Theme.uiScale

    readonly property bool available: percent >= 0
    readonly property color barColor: !available ? Theme.panelBorder
                                      : percent >= 90 ? Theme.error
                                      : percent >= 70 ? Theme.warn
                                      : Theme.accent

    implicitHeight: 84 * unit
    radius: Theme.radius
    color: Theme.mix(Theme.panel, Theme.background, 0.45)
    border.width: 1
    border.color: Theme.panelBorder

    // 上段: 左に項目名、右に使用率
    Text {
        anchors { left: parent.left; leftMargin: 14 * root.unit; baseline: valueText.baseline }
        font.family: Theme.fontFamily
        text: root.title
        color: Theme.textSecondary
        font.pixelSize: 17 * root.unit
    }
    Text {
        id: valueText
        anchors { right: parent.right; rightMargin: 14 * root.unit; top: parent.top; topMargin: 4 * root.unit }
        font.family: Theme.fontFamily
        text: root.available ? root.percent + " %" : "--"
        color: root.available ? Theme.textPrimary : Theme.textSecondary
        font.pixelSize: 28 * root.unit
        font.bold: true
    }

    // 中段: 使用率バー
    Rectangle {
        id: track
        anchors { left: parent.left; right: parent.right; leftMargin: 14 * root.unit; rightMargin: 14 * root.unit
                  top: parent.top; topMargin: 44 * root.unit }
        height: 7 * root.unit
        radius: height / 2
        color: Theme.panelBorder
        Rectangle {
            width: root.available ? parent.width * Math.min(1, root.percent / 100) : 0
            height: parent.height
            radius: parent.radius
            color: root.barColor
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
    }

    // 下段: 周波数・温度などの補足
    Text {
        anchors { left: parent.left; right: parent.right; leftMargin: 14 * root.unit; rightMargin: 14 * root.unit
                  top: track.bottom; topMargin: 7 * root.unit }
        font.family: Theme.fontFamily
        text: root.detail
        color: Theme.textSecondary
        font.pixelSize: 15 * root.unit
        elide: Text.ElideRight
    }
}
