// 「作業中」を表すバー(アップデートの進み具合など)。
//   progress >= 0(進み具合が分かる): なめらかに伸びる塗り + 塗りの上を流れる光 + 先頭でゆっくり明滅する光
//   progress <  0(分からない)     : Google(Material)風の流れるバー。2 本のバーが左端から伸びながら入り、右端の外へ抜けきるまで進む(一方向)
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

        // ---- 進み具合が分からないとき: Google(Material)風の流れるバー ----
        // 2 本のバーが 2.1 秒周期で左から右へ流れる(Material の indeterminate と同じ動き・同じ曲線)。
        //   1 本目: 左端の外から伸びながら入り、右端の外へ抜けきるまで進む(バーの左端が溝の右端に着くまで動く)
        //   2 本目: 1.15 秒遅れで同じ動きをする(1 本目が抜けていく間に次のバーが入ってくる)
        // 一方向にしか進まない。バー全体が右へ消えきってから、次の周期が左から始まる
        Item {
            id: scan
            anchors.fill: parent
            opacity: root.known ? 0 : 1
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 280 } }

            readonly property int cycle: 2100                 // 1 周期(ms)
            readonly property int travel: cycle * 6 / 10      // 動いている時間(残りは次が入るまでの間)
            readonly property int secondDelay: 1150           // 2 本目が遅れて始まる時間

            // バー 1 本。a = 左端、b = 右端の位置(溝の幅に対する割合。0 = 溝の左端、1 = 右端)。範囲外の値もとる。
            // 描くのは溝の中にある部分だけ(0〜1 に収める)ので、角丸のまま左端から伸び、右端へ縮みながら消える。
            // 親(scan)は溝いっぱいに広がっているので、幅は parent.width を使う(inline component は外の id を見られない)
            component Strip: Rectangle {
                property real a: 0
                property real b: 0
                readonly property real lo: Math.max(0, Math.min(1, a))
                readonly property real hi: Math.max(0, Math.min(1, b))
                visible: hi - lo > 0.0005
                x: parent.width * lo
                width: parent.width * (hi - lo)
                height: parent.height
                radius: height / 2
                color: root.barColor
            }

            Strip { id: bar1 }
            Strip { id: bar2 }

            // 1 本目(a: 左端 -35% → 100%、b: 右端 0% → 190%)。曲線は Material の indeterminate 1 本目と同じ
            SequentialAnimation {
                running: root.running && scan.visible
                loops: Animation.Infinite
                ParallelAnimation {
                    NumberAnimation { target: bar1; property: "a"; from: -0.35; to: 1.0; duration: scan.travel
                                      easing.type: Easing.BezierSpline; easing.bezierCurve: [0.65, 0.815, 0.735, 0.395, 1, 1] }
                    NumberAnimation { target: bar1; property: "b"; from: 0.0; to: 1.9; duration: scan.travel
                                      easing.type: Easing.BezierSpline; easing.bezierCurve: [0.65, 0.815, 0.735, 0.395, 1, 1] }
                }
                PauseAnimation { duration: scan.cycle - scan.travel }
            }
            // 2 本目(a: 左端 -200% → 107%、b: 右端 0% → 108%)。最初だけ secondDelay 遅れる
            SequentialAnimation {
                running: root.running && scan.visible
                PauseAnimation { duration: scan.secondDelay }
                SequentialAnimation {
                    loops: Animation.Infinite
                    ParallelAnimation {
                        NumberAnimation { target: bar2; property: "a"; from: -2.0; to: 1.07; duration: scan.travel
                                          easing.type: Easing.BezierSpline; easing.bezierCurve: [0.165, 0.84, 0.44, 1, 1, 1] }
                        NumberAnimation { target: bar2; property: "b"; from: 0.0; to: 1.08; duration: scan.travel
                                          easing.type: Easing.BezierSpline; easing.bezierCurve: [0.165, 0.84, 0.44, 1, 1, 1] }
                    }
                    PauseAnimation { duration: scan.cycle - scan.travel }
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
