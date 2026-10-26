// 起動(ようこそ)画面。
//  - 中央: あいさつ(時刻に応じて。ユーザー名があれば「〜、○○ さん」)、タイトル「OpenCruise」、
//    サブタイトル「An Open-Source Car Integration System」、起動状況と進行バー
//  - 下部: 「実際の交通規制に従って走行する」旨の警告(角丸のカード。警告色のアイコンと見出しつき)
// BootManager(context property `boot`)の待ち(ESP32 などの応答待ち)が終わるまで表示を保つ。
// 待ちの制御はすべて C++ 側(BootManager)にあり、ここは表示だけ。各ステップの詳細はログに残る。
import QtQuick

Rectangle {
    id: root
    color: Theme.background

    readonly property real unit: Math.max(0.6, Math.min(width / 1280, height / 720))
    // 進行バーはなめらかに追従させる
    property real shownProgress: boot.progress
    Behavior on shownProgress { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    // あいさつ(あいさつウィジェットと同じ区切り)
    readonly property string greeting: {
        const h = clock.hour
        return (h >= 4 && h < 11) ? "おはようございます" : (h >= 11 && h < 18) ? "こんにちは" : "こんばんは"
    }
    readonly property string greetingText: appSettings.userName !== "" ? greeting + "、" + appSettings.userName + " さん" : greeting

    // 下へタッチを通さない
    MouseArea { anchors.fill: parent; enabled: root.visible }

    // 背景: 上からアクセント色がうっすら差すグラデーション
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.mix(Theme.background, Theme.accent, 0.10) }
            GradientStop { position: 0.6; color: Theme.background }
        }
    }

    // ---- 中央: あいさつ・タイトル・サブタイトル・起動状況 ----
    Column {
        id: titleBlock
        anchors.horizontalCenter: parent.horizontalCenter
        // 下の警告カードの分だけ上に寄せて、残りの高さの中央に置く
        y: Math.max(Theme.margin, (parent.height - warning.height - warning.anchors.bottomMargin - height) / 2)
        width: Math.min(parent.width - Theme.margin * 4, 900 * root.unit)
        spacing: 14 * root.unit
        // 起動画面はすぐに出す(フェードインで遅れて見えないよう、最初から表示する)

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.fontFamily
            font.pixelSize: 30 * root.unit
            color: Theme.textSecondary
            elide: Text.ElideRight
            text: root.greetingText
        }

        // タイトル: 「Open」は細め、「Cruise」は太字のアクセント色
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            Text {
                font.family: Theme.fontFamily
                font.pixelSize: 124 * root.unit
                font.weight: Font.Light
                color: Theme.textPrimary
                text: "Open"
            }
            Text {
                font.family: Theme.fontFamily
                font.pixelSize: 124 * root.unit
                font.weight: Font.Bold
                color: Theme.accent
                text: "Cruise"
            }
        }

        // サブタイトル(両側に細い線)
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 18 * root.unit
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 56 * root.unit; height: Math.max(1, 2 * root.unit)
                color: Theme.panelBorder
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.fontFamily
                font.pixelSize: 26 * root.unit
                font.letterSpacing: 1.5 * root.unit
                color: Theme.textSecondary
                text: "An Open-Source Car Integration System"
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 56 * root.unit; height: Math.max(1, 2 * root.unit)
                color: Theme.panelBorder
            }
        }

        Item { width: 1; height: 26 * root.unit }

        // 起動状況と進行バー
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.fontFamily
            font.pixelSize: 20 * root.unit
            color: boot.hasProblem && boot.done ? Theme.warn : Theme.textSecondary
            elide: Text.ElideRight
            text: boot.summaryText
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width, 520 * root.unit)
            height: 6 * root.unit
            radius: height / 2
            color: Theme.panelBorder
            Rectangle {
                width: parent.width * root.shownProgress
                height: parent.height
                radius: height / 2
                color: Theme.accent
            }
        }
    }

    // ---- 下部: 警告(角丸のカード) ----
    Rectangle {
        id: warning
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 28 * root.unit }
        width: Math.min(parent.width - 2 * 28 * root.unit, 1160 * root.unit)
        height: warningRow.implicitHeight + 2 * 20 * root.unit
        radius: Theme.radius + 6
        color: Theme.mix(Theme.panel, Theme.warn, 0.12)
        border.width: 2
        border.color: Theme.warn

        Row {
            id: warningRow
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                      leftMargin: 24 * root.unit; rightMargin: 24 * root.unit }
            spacing: 22 * root.unit

            // 警告色の丸に警告マーク
            Rectangle {
                id: warningBadge
                anchors.verticalCenter: parent.verticalCenter
                width: 76 * root.unit; height: width; radius: width / 2
                color: Theme.warn
                MaterialIcon {
                    anchors.centerIn: parent
                    name: "warning"
                    size: Math.round(parent.width * 0.6)
                    color: Theme.textOnAccent
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - warningBadge.width - parent.spacing
                spacing: 4 * root.unit
                Text {
                    font.family: Theme.fontFamily
                    font.pixelSize: 26 * root.unit
                    font.bold: true
                    font.letterSpacing: 2 * root.unit
                    color: Theme.warn
                    text: "警告"
                }
                Text {
                    width: parent.width
                    font.family: Theme.fontFamily
                    font.pixelSize: 34 * root.unit
                    font.bold: true
                    color: Theme.textPrimary
                    text: "必ず実際の交通規制(信号・標識・速度制限など)に従って走行してください。"
                    // 1 行に収める。収まらない幅では、収まる最大の大きさまで文字を縮める
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 12
                }
            }
        }
    }

    ActionButton {
        anchors { right: parent.right; top: parent.top; rightMargin: Theme.margin * 1.5; topMargin: Theme.margin * 1.5 }
        visible: boot.active
        text: "スキップ"
        onClicked: boot.skip()
    }
}
