// すべてのウィジェットの土台。ウィジェットは WidgetBase を継承し、中身(子要素)だけを書けばよい。
//   WidgetBase {
//       framed: false                      // カード背景を描くか(既定は共通設定 config.frame に従う)
//       doubleTapAction: "settings"        // ダブルタップの動作: "settings"(設定画面) / "custom"(doubleTapped を使う) / "none"
//       Text { text: config.title }        // 子要素はこの中に置かれる(余白なし・全面)
//   }
// 値の受け渡し:
//   config   … 設定値(WidgetRegistry の defaultConfig に保存値を重ねたもの)。WidgetHost が注入する
//   lifting  … ドラッグで持ち上げ中か。WidgetHost が注入する(重い更新を止めたい場合などに使える)
//   gridW / gridH … グリッド上のマス数。WidgetHost(設定画面のプレビューでは WidgetSettingsDialog)が注入する
// 見出し(上部タイトル)は titleFontSize / titleBarHeight を使う。大きさはマス数で 3 段階に固定され、
// ウィジェットを大きくしても見出しだけが巨大化しない(短辺 1 マス=小 / 2 マス=中 / 3 マス以上=大)。
// 操作:
// 見えていないとき(ほかのページ・フルスクリーン中の Android Auto 画面・設定画面の裏など):
//   onScreen が false になる。表示だけのための処理(針の追従・点滅・描き直し・表示用の時刻の更新など)は止め、
//   警告の判定・警告音・通知・最大値の記録など、見えていなくても要る処理は続けること。
//   見えるようになったら(onScreen が true に戻ったら)、表示を今の値に合わせ直す。
//   tapped()        … 1 回タップ(ウィジェット自身の操作を作りたいときに受ける)
//   doubleTapped()  … doubleTapAction が "custom" のときだけ呼ばれる
// ウィジェット内に独自の MouseArea を置くとドラッグ(長押し)より優先される。その範囲では移動を始められないので、
// 小さい操作部品だけに置くこと。
import QtQuick
import OpenCruise

Item {
    id: root

    // ---- WidgetHost が注入する ----
    property var config: ({})
    property bool lifting: false
    property int gridW: 3
    property int gridH: 3
    /// 配置エリア上のウィジェットの ID(設定画面のプレビューなど、配置されていないときは空)
    property string widgetId: ""
    /// 飾りの画像(重ね方「パネル」)。初期画面のウィジェットだけ WidgetHost が注入する(無ければ出さない)
    property Item decorStore: null
    property point decorOrigin: Qt.point(0, 0)   // このウィジェットの左上の、画面上の位置
    property real decorRootW: 1
    property real decorRootH: 1
    readonly property bool titleVisible: config.showTitle !== false
    /// 画面に見えているか(親のどれかが隠れていれば false)。表示の更新だけを止めるのに使う
    /// 起動画面と注意事項が終わって、メイン画面の動きを始めてよいか(メイン画面は注意事項の前に作っておくが、動きは終わってから)
    readonly property bool released: typeof boot === "undefined" || boot.released
    readonly property bool onScreen: visible && released
    onReleasedChanged: if (released) WidgetRegistry.flushPaints()
    /// Canvas を描き直す。起動中は 1 枚ずつ間をあけて描く(WidgetRegistry.queuePaint)。終わったらすぐ描く
    function paintCanvas(canvas) {
        if (released) canvas.requestPaint()
        else WidgetRegistry.queuePaint(canvas)
    }

    function titleText(fallback) {
        const custom = String(config.titleText || "").trim()
        return custom !== "" ? custom : fallback
    }

    // ---- 継承側が決める ----
    // カード背景。既定は全ウィジェット共通の設定「枠」(config.frame: "card" / "plain")に従う
    property bool framed: config.frame !== "plain"
    property string doubleTapAction: "settings"
    // ---- 見出し(上部タイトル)の大きさ。短辺のマス数で 3 段階(1 / 2 / 3 以上は同じ) ----
    readonly property int titleTier: Math.max(1, Math.min(3, Math.min(gridW, gridH)))
    readonly property real titleFontSize: Math.max(11, Math.round([12, 14, 16][titleTier - 1] * Theme.uiScale))
    readonly property real titleBarHeight: Math.round(titleFontSize * 1.35)
    // ウィジェット内側の余白(各ウィジェットの m はこれを使う)。大きくしても余白が広がりすぎないよう上限つき
    readonly property real innerMargin: Math.max(7, Math.min(14, s * 0.045))
    // ウィジェット共通の文字階層。個別の値表示・大見出しは各ウィジェット側で調整する。
    // headerFontSize は見出し用(titleFontSize と同じ。既存ウィジェットとの互換のため残す)
    readonly property real headerFontSize: titleFontSize
    readonly property real bodyFontSize: Math.max(12, Math.min(s * 0.075, 22))
    readonly property real detailFontSize: Math.max(11, Math.min(s * 0.065, 18))
    signal tapped()
    signal doubleTapped()

    // 画面サイズに合わせた寸法の基準(短辺)
    readonly property real s: Math.min(width, height)

    default property alias content: slot.data

    Panel {   // カード(テーマに合わせた面)
        anchors.fill: parent
        radius: Theme.radius + 6
        opacity: root.framed ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    // パネルと中身の間の、飾りの画像(パネルを出しているときだけ)
    Loader {
        anchors.fill: parent
        active: root.framed && root.decorStore !== null
        sourceComponent: DecorationPanelLayer {
            store: root.decorStore
            origin: root.decorOrigin
            rootW: root.decorRootW
            rootH: root.decorRootH
            radius: Theme.radius + 6
        }
    }

    Item {
        id: slot
        anchors.fill: parent
    }
}
