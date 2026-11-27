// 「作業中」を表すバー(アップデートの進み具合など)。
//   progress >= 0(進み具合が分かる): なめらかに伸びる塗り + 塗りの上を流れる光 + 先頭でゆっくり明滅する光
//   progress <  0(分からない)     : 左右を往復する光の帯。端では縮み、真ん中では伸びて、進む向きの先頭が明るく、後ろに尾を引く
// 分かる・分からないが切り替わるときは、2 つの表示が重なったまま入れ替わる(ぱっと変わらない)。
// 色・文字は呼び出し側から渡す(テーマに依存しない部品)。running が false の間はアニメーションを止める。
import QtQuick

Item {
    id: root

    /// 進み具合(0〜1)。分からないときは負の値
    property real progress: -1
    /// false の間はアニメーションを止める(非表示のときなど)
    property bool running: true
    property color barColor: "#3b82f6"
    property color trackColor: "#30363f"
    property color textColor: "#9aa3b0"
    property string fontFamily: Qt.application.font.family
    /// バーの右に出す文字(「37%」「0:12」など)。空なら出さない
    property string text: ""
    /// 画面の拡大率(Theme.uiScale)
    property real unit: 1.0

    readonly property bool known: progress >= 0
    readonly property real frac: Math.max(0, Math.min(1, progress))
    readonly property real textWidth: text === "" ? 0 : 72 * unit

    implicitWidth: 400 * unit
    implicitHeight: 20 * unit

    // ---- 溝 ----
    Rectangle {
        id: track
        anchors { left: parent.left; right: parent.right; rightMargin: root.textWidth > 0 ? root.textWidth + 14 * root.unit : 0 }
        height: root.height
        radius: height / 2
        color: root.trackColor
        clip: true

        // ---- 進み具合が分からないとき: 往復する光の帯 ----
        Item {
            id: scan
            anchors.fill: parent
            opacity: root.known ? 0 : 1
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 280 } }

            property real slide: 0          // 0 → 1 → 0 と往復する位置(0 = 左端、1 = 右端)
            property bool goingRight: true  // 進む向き(先頭の明るい側を決める)
            readonly property real headWidth: track.width * (0.14 + 0.18 * Math.sin(Math.PI * slide))   // 端で縮み、真ん中で伸びる

            SequentialAnimation {
                running: root.running && scan.visible
                loops: Animation.Infinite
                ScriptAction { script: scan.goingRight = true }
                NumberAnimation { target: scan; property: "slide"; from: 0; to: 1; duration: 1150; easing.type: Easing.InOutSine }
                PauseAnimation { duration: 90 }
                ScriptAction { script: scan.goingRight = false }
                NumberAnimation { target: scan; property: "slide"; from: 1; to: 0; duration: 1150; easing.type: Easing.InOutSine }
                PauseAnimation { duration: 90 }
            }

            // 尾: 本体より少し遅れて付いてくる、だんだん薄く短い影。
            // 遅らせるのは x ではなく 0〜1 の位置(pos)。x で遅らせると、帯が伸びたときに右端からはみ出して切れて見える
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    property real pos: scan.slide
                    Behavior on pos { NumberAnimation { duration: 60 * (index + 1); easing.type: Easing.OutQuad } }
                    width: scan.headWidth * (1 - 0.14 * (index + 1))
                    height: scan.height
                    radius: height / 2
                    color: root.barColor
                    opacity: 0.32 / (index + 1)
                    x: (track.width - width) * pos
                }
            }
            // 本体: 進む向きの先頭が明るく、後ろへ薄くなる
            Rectangle {
                width: scan.headWidth
                height: scan.height
                radius: height / 2
                x: (track.width - width) * scan.slide
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: scan.goingRight ? Qt.alpha(root.barColor, 0.35) : Qt.lighter(root.barColor, 1.25) }
                    GradientStop { position: 0.5; color: root.barColor }
                    GradientStop { position: 1.0; color: scan.goingRight ? Qt.lighter(root.barColor, 1.25) : Qt.alpha(root.barColor, 0.35) }
                }
            }
        }

        // ---- 進み具合が分かるとき: 伸びる塗り ----
        Item {
            id: filled
            anchors.fill: parent
            opacity: root.known ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 280 } }

            Rectangle {
                id: fill
                // 0% でも丸い点として見える(高さ = 最小の幅)。進み具合の更新が飛び飛びでも、なめらかに追いかける
                width: Math.max(height, track.width * root.frac)
                height: parent.height
                radius: height / 2
                color: root.barColor
                Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                // 塗りの中を流れる光(塗りが短いうちは出さない)
                Rectangle {
                    id: shine
                    readonly property real bandWidth: Math.max(40 * root.unit, fill.width * 0.18)
                    property real t: 0
                    visible: fill.width > bandWidth * 1.6
                    width: bandWidth
                    height: fill.height - 4 * root.unit
                    y: 2 * root.unit
                    radius: height / 2
                    x: 2 * root.unit + (fill.width - width - 4 * root.unit) * t
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#00ffffff" }
                        GradientStop { position: 0.5; color: "#55ffffff" }
                        GradientStop { position: 1.0; color: "#00ffffff" }
                    }
                    SequentialAnimation on t {
                        running: root.running && filled.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 0; to: 1; duration: 1300; easing.type: Easing.InOutQuad }
                        PauseAnimation { duration: 500 }
                    }
                }

                // 先頭の光(進行中だけ。ゆっくり明滅する)
                Rectangle {
                    id: head
                    visible: root.frac < 0.995
                    width: fill.height
                    height: fill.height
                    radius: width / 2
                    x: fill.width - width
                    color: Qt.lighter(root.barColor, 1.6)
                    opacity: 0.2
                    SequentialAnimation on opacity {
                        running: root.running && filled.visible && head.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.15; to: 0.7; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.7; to: 0.15; duration: 700; easing.type: Easing.InOutSine }
                    }
                }
            }
        }
    }

    // ---- 右の文字(「37%」「0:12」) ----
    Text {
        visible: root.text !== ""
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: root.textWidth
        horizontalAlignment: Text.AlignRight
        text: root.text
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: 20 * root.unit
    }
}
