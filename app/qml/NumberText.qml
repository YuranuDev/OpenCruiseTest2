// 数値の表示。数値のフォント(設定「数値のフォント」)が等幅でなくても、桁(0〜9)の幅をそろえて表示する。
// 比例フォントでは「1」だけが細いなどで、値が変わるたびに幅が揺れて、右揃え・中央揃えの数字が動いて見える。
// それを防ぐため、1 文字ずつ並べる。数字は 0〜9 のうち最も広い幅の枠に入れて、細い数字(1 など)は枠の中央に置く。
// 数字以外(. - : % 文字など)は、そのフォントの幅のまま。等幅のフォントなら、見た目は Text とほぼ同じ。
//
// Text の代わりに使えるように、よく使う項目を持つ(wrapMode・elide は無い。1 行だけ)。
//   text / color / bold / italic / fontFamily(既定は数値のフォント)
//   pixelSize … 大きさ。fit が true のときは「収まる範囲での上限」(Text.Fit と同じ。minimumPixelSize が下限)
//   horizontalAlignment / verticalAlignment … 枠(width × height)の中での位置
//   effectivePixelSize / contentWidth / contentHeight … 実際に使う大きさと、文字が占める大きさ
import QtQuick

Item {
    id: root

    property string text: ""
    property color color: Theme.textPrimary
    property string fontFamily: Theme.numberFontFamily
    property bool bold: false
    property bool italic: false
    property int pixelSize: 16
    property int minimumPixelSize: 8
    property bool fit: false
    property int horizontalAlignment: Text.AlignLeft
    property int verticalAlignment: Text.AlignVCenter

    // 測るときの基準の大きさ(実際の大きさは、これを何倍かする)
    readonly property int refPx: 100
    FontMetrics {
        id: fm
        font.family: root.fontFamily
        font.bold: root.bold
        font.italic: root.italic
        font.pixelSize: root.refPx
    }

    // 数字 0〜9 のうち、最も広い幅(基準の大きさでの値。フォントが変わったときだけ測り直す)
    readonly property real digitW: {
        fm.font   // フォントが変わったら測り直す(FontMetrics の更新後に評価されるよう、FontMetrics の font を読む)
        let w = 0
        for (let d = 0; d < 10; ++d) w = Math.max(w, fm.advanceWidth(String(d)))
        return w
    }
    readonly property real lineH: { fm.font; return fm.height }
    readonly property real ascent: { fm.font; return fm.ascent }

    // 1 文字ずつの位置(基準の大きさでの値)と、全体の幅
    readonly property var layout: {
        fm.font
        const s = String(root.text)
        const dw = root.digitW
        const list = []
        let x = 0
        for (let i = 0; i < s.length; ++i) {
            const ch = s[i]
            const natural = fm.advanceWidth(ch)
            const isDigit = ch >= "0" && ch <= "9"
            const adv = isDigit ? dw : natural
            if (ch !== " ") list.push({ ch: ch, x: x + (adv - natural) / 2 })   // 細い数字は枠の中央に置く
            x += adv
        }
        return { glyphs: list, width: x }
    }

    // 実際の大きさ。fit のときは、枠(width × height)に収まる最大の大きさ(pixelSize 以下、minimumPixelSize 以上)
    readonly property int effectivePixelSize: {
        let p = root.pixelSize
        if (root.fit) {
            if (root.layout.width > 0 && root.width > 0) p = Math.min(p, root.width * root.refPx / root.layout.width)
            if (root.lineH > 0 && root.height > 0) p = Math.min(p, root.height * root.refPx / root.lineH)
            p = Math.max(root.minimumPixelSize, p)
        }
        return Math.max(1, Math.floor(p))
    }
    readonly property real k: effectivePixelSize / refPx
    readonly property real contentWidth: layout.width * k
    readonly property real contentHeight: lineH * k

    // fit のときは、枠の大きさで決まるので、大きさの元は pixelSize で測る(循環させない)
    implicitWidth: layout.width * pixelSize / refPx
    implicitHeight: lineH * pixelSize / refPx

    readonly property real offsetX: horizontalAlignment === Text.AlignRight ? width - contentWidth
                                  : horizontalAlignment === Text.AlignHCenter ? (width - contentWidth) / 2 : 0
    readonly property real offsetY: verticalAlignment === Text.AlignBottom ? height - contentHeight
                                  : verticalAlignment === Text.AlignTop ? 0 : (height - contentHeight) / 2
    // 単位の文字などを、数字の下端(ベースライン)にそろえるときに使う(anchors.baseline)
    baselineOffset: offsetY + ascent * k

    Repeater {
        model: root.layout.glyphs.length
        Text {
            required property int index
            readonly property var g: root.layout.glyphs[index]
            x: root.offsetX + (g ? g.x : 0) * root.k
            y: root.offsetY
            text: g ? g.ch : ""
            color: root.color
            font.family: root.fontFamily
            font.bold: root.bold
            font.italic: root.italic
            font.pixelSize: root.effectivePixelSize
        }
    }
}
