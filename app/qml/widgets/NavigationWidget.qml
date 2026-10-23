// ナビ案内ウィジェット(Android Auto 連携)。NavigationStatus チャネルの次の曲がり角を表示する。
//
// レイアウト(ウィジェットの縦横比に追従して自動で切り替わる):
//   ・主案内   … 方向アイコン + 道路名(または方向名) + 距離。横長なら左右、縦長・正方形なら上下に並ぶ
//   ・その次   … 横長なら右側の列、縦長なら下の帯。2 件目の距離はプロトコルから来ないので方向と道路名だけ
//   ・コンパクト … 主案内だけを大きく表示する
// 設定(config): frame / layout / distanceUnit / showRoad / showNext / nearHighlight(「設定」参照)
//
// 距離は必ず単位つきで表示する。数値(メートル)がある場合は常にそれを整形し、スマホ側の表示文字列は
// 数値が取れないときの代わりとしてだけ使う(単位が欠けた文字列は補う)。
import QtQuick
import OpenCruise

WidgetBase {
    id: root

    framed: config.frame !== "plain"

    // ---- 設定 ----
    readonly property bool compact: config.layout === "compact"
    readonly property string unitMode: config.distanceUnit === "km" || config.distanceUnit === "m" ? config.distanceUnit : "auto"
    readonly property bool showRoad: config.showRoad !== false
    readonly property int nearMeters: config.nearHighlight === undefined ? 100 : Math.max(0, config.nearHighlight)

    // ---- 状態 ----
    readonly property bool active: androidAuto.navigationActive
    readonly property real meters: androidAuto.navigationDistanceMeters
    readonly property bool hasNext: androidAuto.nextNavigationManeuver > 0
    readonly property bool showNext: active && hasNext && !compact && config.showNext !== false
    readonly property bool near: active && nearMeters > 0 && meters >= 0 && meters <= nearMeters
    readonly property string distanceString: formatDistance(meters, androidAuto.navigationDistanceLabel)
    readonly property string mainRoad: showRoad ? androidAuto.navigationRoad : ""
    readonly property string mainSub: mainRoad !== "" ? mainRoad : maneuverName(androidAuto.navigationManeuver, androidAuto.navigationSide)
    readonly property string nextSub: (showRoad && androidAuto.nextNavigationRoad !== "")
                                      ? androidAuto.nextNavigationRoad
                                      : maneuverName(androidAuto.nextNavigationManeuver, androidAuto.nextNavigationSide)

    readonly property real m: Math.max(8, Math.min(16, s * 0.07))
    readonly property bool wide: width >= height * 1.5

    // ---- 変換 ----
    function maneuverIcon(kind, side) {
        const right = side === 2
        switch (kind) {
        case 3: case 4: case 5: return right ? "turn_right" : "turn_left"
        case 6: return right ? "u_turn_right" : "u_turn_left"
        case 7: case 8: return right ? "ramp_right" : "ramp_left"
        case 9: return right ? "fork_right" : "fork_left"
        case 10: return "merge"
        case 11: case 12: case 13: return right ? "roundabout_right" : "roundabout_left"
        case 19: return "flag"
        default: return "straight"
        }
    }

    function maneuverName(kind, side) {
        const right = side === 2
        switch (kind) {
        case 3: case 4: case 5: return right ? "右折" : "左折"
        case 6: return "Uターン"
        case 7: case 8: return "出口・ランプ"
        case 9: return right ? "右方向" : "左方向"
        case 10: return "合流"
        case 11: case 12: case 13: return "ロータリー"
        case 19: return "目的地"
        default: return "直進"
        }
    }

    // メートルを単位つきの文字列にする。単位の指定: auto(1 km 未満は m、以上は km)/ m / km
    function formatMeters(value, mode) {
        if (mode === "km")
            return (value / 1000).toFixed(value >= 10000 ? 0 : 1) + " km"
        if (mode === "m")
            return Math.round(value) + " m"
        if (value < 1000)
            return Math.round(value) + " m"
        return (value / 1000).toFixed(value >= 10000 ? 0 : 1) + " km"
    }

    // 数字だけの表示文字列に単位を補う(小数点があれば km、なければ m とみなす)
    function normalizeLabel(label) {
        const t = label.trim()
        if (t === "") return ""
        if (/^[0-9]+([.,][0-9]+)?$/.test(t))
            return t + (/[.,]/.test(t) ? " km" : " m")
        return t
    }

    function formatDistance(value, label) {
        const text = normalizeLabel(label)
        const labelIsZero = /^0+([.,]0+)?\s*(m|km|メートル|キロメートル)?$/i.test(text)
        if (value > 0) return formatMeters(value, unitMode)
        if (text !== "" && !labelIsZero) return text
        if (value === 0) return formatMeters(0, unitMode === "km" ? "km" : "m")
        return ""
    }

    // ---- 待機中 ----
    Column {
        anchors { centerIn: parent }
        width: parent.width - root.m * 2
        spacing: root.m * 0.4
        visible: !root.active
        opacity: 0.8

        MaterialIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "navigation"
            size: Math.max(20, Math.min(root.height * 0.36, root.width * 0.2))
            color: Theme.textSecondary
        }
        Text {
            width: parent.width
            height: Math.max(14, root.height * 0.14)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "ナビ案内を待っています"
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: height
            minimumPixelSize: 9
            fontSizeMode: Text.Fit
            elide: Text.ElideRight
        }
    }

    // ---- 案内中 ----
    Item {
        id: body
        anchors { fill: parent; margins: root.m }
        visible: root.active

        // 「その次」の領域の大きさ(出さないときは 0)
        readonly property real nextW: root.showNext && root.wide ? Math.min(width * 0.3, 240) : 0
        readonly property real nextH: root.showNext && !root.wide ? Math.min(height * 0.3, 64) : 0

        Item {
            id: main
            anchors { left: parent.left; top: parent.top }
            width: body.width - (body.nextW > 0 ? body.nextW + root.m : 0)
            height: body.height - (body.nextH > 0 ? body.nextH + root.m : 0)

            readonly property bool horizontal: width >= height * 1.15
            readonly property bool hasSub: root.mainSub !== ""

            Row {
                id: mainHeader
                anchors { top: parent.top; left: parent.left; right: parent.right }
                spacing: 8
                height: Math.max(20, Math.min(28, main.height * 0.13))

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "navigation"
                    size: parent.height
                    color: Theme.accent
                }
                Text {
                    width: Math.max(0, mainHeader.width - mainHeader.spacing - mainHeader.height)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "次の案内"
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(13, root.s * 0.085)
                    elide: Text.ElideRight
                }
            }

            Item {
                id: mainContent
                anchors { left: parent.left; right: parent.right; top: mainHeader.bottom; bottom: parent.bottom }
                anchors.topMargin: root.m * 0.25
                readonly property real iconSize: Math.max(20, main.horizontal ? Math.min(height, width * 0.36)
                                                                              : Math.min(width * 0.55, height * 0.42))

                MaterialIcon {
                    id: mainIcon
                    x: main.horizontal ? 0 : (mainContent.width - mainContent.iconSize) / 2
                    y: main.horizontal ? (mainContent.height - mainContent.iconSize) / 2 : 0
                    name: root.maneuverIcon(androidAuto.navigationManeuver, androidAuto.navigationSide)
                    size: mainContent.iconSize
                    color: root.near ? Theme.warn : Theme.accent
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                Item {
                    id: textBox
                    x: main.horizontal ? mainContent.iconSize + root.m : 0
                    y: main.horizontal ? 0 : mainContent.iconSize + root.m * 0.4
                    width: mainContent.width - x
                    height: mainContent.height - y

                    Column {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: Math.max(4, Math.min(12, textBox.height * 0.06))

                        Text {   // 道路名(なければ方向名)を主表示
                            width: parent.width
                            height: Math.max(16, textBox.height * (root.distanceString !== "" ? 0.5 : 0.9))
                            horizontalAlignment: main.horizontal ? Text.AlignLeft : Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            visible: main.hasSub
                            text: root.mainSub
                            color: Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.bold: true
                            font.pixelSize: height
                            minimumPixelSize: 9
                            fontSizeMode: Text.Fit
                            elide: Text.ElideRight
                        }
                        Text {   // 距離
                            width: parent.width
                            height: root.distanceString !== "" ? Math.max(10, Math.min(textBox.height * (main.hasSub ? 0.25 : 0.9), root.s * 0.12)) : 0
                            horizontalAlignment: main.horizontal ? Text.AlignLeft : Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            visible: root.distanceString !== ""
                            text: root.distanceString
                            color: root.near ? Theme.warn : Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: height
                            minimumPixelSize: 10
                            fontSizeMode: Text.Fit
                            elide: Text.ElideRight
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                    }
                }
            }
        }

        // ---- その次の案内 ----
        Item {
            id: nextCue
            visible: root.showNext
            anchors { right: parent.right; bottom: parent.bottom }
            width: root.wide ? body.nextW : body.width
            height: root.wide ? body.height : body.nextH

            Rectangle {   // 主案内との区切り線
                color: Theme.panelBorder
                x: root.wide ? -root.m * 0.5 : 0
                y: root.wide ? 0 : -root.m * 0.5
                width: root.wide ? 1 : parent.width
                height: root.wide ? parent.height : 1
            }

            // 横長: 縦に並べる(見出し・アイコン・名称)
            Column {
                visible: root.wide
                anchors { fill: parent; leftMargin: root.m * 0.3 }
                spacing: Math.max(2, parent.height * 0.04)

                Text {
                    width: parent.width
                    height: Math.max(11, Math.min(parent.height * 0.14, 18))
                    text: "その次"
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: height
                    minimumPixelSize: 8
                    fontSizeMode: Text.Fit
                    elide: Text.ElideRight
                }
                MaterialIcon {
                    name: root.maneuverIcon(androidAuto.nextNavigationManeuver, androidAuto.nextNavigationSide)
                    size: Math.max(18, Math.min(parent.width * 0.45, parent.height * 0.4))
                    color: Theme.accent
                }
                Text {
                    width: parent.width
                    height: Math.max(12, parent.height * 0.26)
                    verticalAlignment: Text.AlignTop
                    text: root.nextSub
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(11, Math.min(height * 0.55, 18))
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            // 縦長: 1 行にまとめる(アイコン + 名称)
            Row {
                visible: !root.wide
                anchors { fill: parent; topMargin: 1 }
                spacing: root.m * 0.6

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.maneuverIcon(androidAuto.nextNavigationManeuver, androidAuto.nextNavigationSide)
                    size: Math.max(16, parent.height * 0.7)
                    color: Theme.accent
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - parent.height * 0.7 - parent.spacing)
                    height: parent.height * 0.6
                    verticalAlignment: Text.AlignVCenter
                    text: "その次: " + root.nextSub
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: height
                    minimumPixelSize: 9
                    fontSizeMode: Text.Fit
                    elide: Text.ElideRight
                }
            }
        }
    }
}
