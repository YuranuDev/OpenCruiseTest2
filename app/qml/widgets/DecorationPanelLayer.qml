// ウィジェットのパネルと中身の間に出す、飾りの画像(重ね方「パネル」)。WidgetBase がパネルの上・中身の下に置く。
// 画面全体の大きさの DecorationLayer("panel")を、このウィジェットの画面上の位置(origin)の分だけずらし、
// パネルの形(角丸)に切り抜いて出す。どのウィジェットのパネルにも、画面の同じ所に同じ画像が見える(パネル越しの窓のように)。
// 角丸の切り抜き: Qt 6.5 以降の MultiEffect、無ければ Qt5Compat の OpacityMask を使う。どちらも無いとき・
// ソフトウェア描画(効果が描かれない)のときは四角く切り抜く(角の丸みの外へ、少しだけはみ出る)。
// このウィジェットに重なる「パネル」の画像が無いときは何も作らない(軽くするため)。
import QtQuick
import OpenCruise

Item {
    id: root
    property Item store: null
    property point origin: Qt.point(0, 0)   // このウィジェットの左上の、画面(LauncherScreen)上の位置
    property real rootW: 1
    property real rootH: 1
    property real radius: Theme.radius + 6

    // このウィジェットに重なる「パネル」の画像があるか
    readonly property bool hit: {
        if (!store) return false
        store.revision; store.count
        const m = store.model
        for (let i = 0; i < m.count; ++i) {
            const it = m.get(i)
            if (it.zone !== "panel") continue
            const x = it.rx * rootW, y = it.ry * rootH, w = it.rw * rootW, h = w * it.ar
            if (x < origin.x + width && x + w > origin.x && y < origin.y + height && y + h > origin.y) return true
        }
        return false
    }
    visible: hit

    // ---- 切り抜く中身(画面全体の層を、ずらして置く) ----
    Item {
        id: content
        anchors.fill: parent
        clip: true
        DecorationLayer {
            x: -root.origin.x
            y: -root.origin.y
            width: root.rootW
            height: root.rootH
            store: root.hit ? root.store : null
            layerName: "panel"
        }
    }

    // ---- 角丸の切り抜き(使える効果を一度だけ調べ、作れたらそれを使う) ----
    property var effect: null
    // 効果で切り抜くか(ソフトウェア描画では効果が描かれないので使わない)
    readonly property bool useEffect: effect !== null && root.GraphicsInfo.api !== GraphicsInfo.Software
    onUseEffectChanged: if (effect) effect.visible = useEffect
    // 角丸の形(効果のマスク。画面には出さない)
    Rectangle {
        id: maskShape
        anchors.fill: parent
        radius: root.radius
        color: "black"
        visible: false
        layer.enabled: root.useEffect
    }
    ShaderEffectSource {
        id: contentTex
        anchors.fill: parent
        sourceItem: root.useEffect ? content : null
        hideSource: true
        visible: false
        live: true
    }
    function makeEffect() {
        if (effect !== null || !hit) return
        // Qt 6.5 以降
        const sources = [
            "import QtQuick; import QtQuick.Effects; MultiEffect { anchors.fill: parent; maskEnabled: true;"
            + " maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }",
            "import QtQuick; import Qt5Compat.GraphicalEffects; OpacityMask { anchors.fill: parent }"
        ]
        if (DecorationEffects.kind < 0) {
            // まだ調べていない: 上から順に作ってみる
            for (let k = 0; k < sources.length; ++k) {
                try {
                    const e = Qt.createQmlObject(sources[k], root, "DecorationMask")
                    DecorationEffects.kind = k
                    attach(e)
                    return
                } catch (err) { /* 次を試す */ }
            }
            DecorationEffects.kind = sources.length   // どれも無い(四角く切り抜く)
            console.info("[decor] rounded clipping is not available (no MultiEffect / Qt5Compat); using a square clip")
            return
        }
        if (DecorationEffects.kind < sources.length) {
            try { attach(Qt.createQmlObject(sources[DecorationEffects.kind], root, "DecorationMask")) } catch (err) { }
        }
    }
    function attach(e) {
        e.source = contentTex
        e.maskSource = maskShape
        effect = e
        e.visible = useEffect
    }
    onHitChanged: makeEffect()
    Component.onCompleted: makeEffect()
}
