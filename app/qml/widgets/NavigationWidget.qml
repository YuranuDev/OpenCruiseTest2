// ナビ案内ウィジェット(Android Auto 連携)。NavigationStatus チャネルの次の曲がり角を表示する。
//
// レイアウト(カーナビの案内カード風。ウィジェットの大きさで自動で組み替える):
//   ・案内カード … 左に方向アイコンのタイル、右に距離(数値を大きく・単位は小さく)と道路名(なければ方向名)。
//                  カードが縦長のときは、タイル → 距離 → 道路名 の縦積みにする
//   ・接近バー   … 「接近の強調」の距離以内になると、残り距離に応じて縮むバーを距離の下に出し、警告色にする
//   ・その次     … 横に十分長ければ右の列、縦に余裕があれば下の帯に出す(どちらも無理なら出さない)。
//                  2 件目の距離はプロトコルから来ないので、方向と道路名だけ
//   ・コンパクト … 「その次」を出さず、案内カードだけを大きく表示する
// 設定(config): layout / distanceUnit / showRoad / showNext / nearHighlight(「設定」参照)。枠と見出しは全ウィジェット共通
// モック(表示テスト): mockEnabled / mockScenario / mockAuto / mockDistance。Android Auto のナビが動いていない間だけ、
//                    仮の案内を表示する(実際の案内が始まったらそちらを優先)。出所は「モック」の札で分かる
//
// 距離は必ず単位つきで表示する。数値(メートル)がある場合は常にそれを整形し、スマホ側の表示文字列は
// 数値が取れないときの代わりとしてだけ使う(単位が欠けた文字列は補う)。
import QtQuick
import OpenCruise

WidgetBase {
    id: root


    // ---- 設定 ----
    readonly property bool compact: config.layout === "compact"
    readonly property string unitMode: config.distanceUnit === "km" || config.distanceUnit === "m" ? config.distanceUnit : "auto"
    readonly property bool showRoad: config.showRoad !== false
    readonly property int nearMeters: config.nearHighlight === undefined ? 100 : Math.max(0, config.nearHighlight)

    // ---- モック(表示テスト) ----
    // シナリオ: start = 開始距離(m)、maneuver / side = 主案内、road = 道路名、next* = その次(maneuver 0 で無し)
    readonly property var mockScenarios: [
        { start: 450,  maneuver: 3,  side: 2, road: "国道16号",              nextManeuver: 3,  nextSide: 1, nextRoad: "県道12号" },
        { start: 2400, maneuver: 7,  side: 2, road: "横浜横須賀道路 出口",   nextManeuver: 10, nextSide: 0, nextRoad: "首都高速湾岸線" },
        { start: 300,  maneuver: 11, side: 1, road: "",                      nextManeuver: 3,  nextSide: 2, nextRoad: "" },
        { start: 180,  maneuver: 19, side: 0, road: "目的地周辺",            nextManeuver: 0,  nextSide: 0, nextRoad: "" }
    ]
    readonly property bool mockWanted: config.mockEnabled === true
    // 実際のナビが動いていない間だけモックを出す
    readonly property bool isMock: mockWanted && !androidAuto.navigationActive
    readonly property var mockScene: mockScenarios[Math.max(0, Math.min(mockScenarios.length - 1, config.mockScenario === undefined ? 0 : config.mockScenario))]
    readonly property bool mockAuto: config.mockAuto !== false
    readonly property real mockFixed: config.mockDistance === undefined ? 300 : Math.max(0, config.mockDistance)
    property real mockMeters: mockScene.start

    // シナリオや自動/固定の切り替えで、距離を最初に戻す
    onMockSceneChanged: mockMeters = mockScene.start
    onMockAutoChanged: mockMeters = mockScene.start
    onIsMockChanged: mockMeters = mockScene.start

    // 自動のとき、距離を縮めて、0 になったら最初から繰り返す(画面に出ている間だけ動かす)
    Timer {
        interval: 500
        repeat: true
        running: root.isMock && root.mockAuto && root.onScreen
        onTriggered: {
            const step = Math.max(5, Math.round(root.mockScene.start / 40))
            const next = root.mockMeters - step
            root.mockMeters = next > 0 ? next : root.mockScene.start
        }
    }

    // ---- 状態(実際の値。モックが有効なときはモックの値) ----
    readonly property bool active: isMock || androidAuto.navigationActive
    readonly property real meters: isMock ? (mockAuto ? mockMeters : mockFixed) : androidAuto.navigationDistanceMeters
    readonly property string distanceLabel: isMock ? "" : androidAuto.navigationDistanceLabel
    readonly property int maneuver: isMock ? mockScene.maneuver : androidAuto.navigationManeuver
    readonly property int maneuverSide: isMock ? mockScene.side : androidAuto.navigationSide
    readonly property string roadName: isMock ? mockScene.road : androidAuto.navigationRoad
    readonly property int nextManeuver: isMock ? mockScene.nextManeuver : androidAuto.nextNavigationManeuver
    readonly property int nextSide: isMock ? mockScene.nextSide : androidAuto.nextNavigationSide
    readonly property string nextRoadName: isMock ? mockScene.nextRoad : androidAuto.nextNavigationRoad

    readonly property bool hasNext: nextManeuver > 0
    readonly property bool showNext: active && hasNext && !compact && config.showNext !== false
    readonly property bool near: active && nearMeters > 0 && meters >= 0 && meters <= nearMeters
    readonly property string distanceString: formatDistance(meters, distanceLabel)
    readonly property string mainRoad: showRoad ? roadName : ""
    readonly property string mainSub: mainRoad !== "" ? mainRoad : maneuverName(maneuver, maneuverSide)
    readonly property string nextSub: (showRoad && nextRoadName !== "")
                                      ? nextRoadName
                                      : maneuverName(nextManeuver, nextSide)

    readonly property real m: innerMargin
    // 距離を数値と単位に分ける("1.2 km" → "1.2" / "km")。分けられなければ全体を数値側に出す
    readonly property var distanceParts: {
        const t = distanceString.trim()
        const match = t.match(/^([0-9]+(?:[.,][0-9]+)?)\s*(.+)$/)
        return match ? { value: match[1], unit: match[2] } : { value: t, unit: "" }
    }
    // 接近バーの残り(1 → 0)。接近の強調の距離以内のときだけ使う
    readonly property real nearRatio: near && nearMeters > 0 ? Math.max(0, Math.min(1, meters / nearMeters)) : 1
    readonly property color cueColor: near ? Theme.warn : Theme.accent

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

    // ---- 見出し(ナビが待機中でも表示) ----
    Row {
        id: header
        visible: root.titleVisible
        anchors { top: parent.top; left: parent.left; right: parent.right
                  topMargin: root.titleVisible ? root.m * 0.8 : 0; leftMargin: root.m; rightMargin: root.m }
        spacing: 8
        height: root.titleVisible ? root.titleBarHeight : 0

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: "navigation"
            size: parent.height
            color: Theme.accent
        }
        Text {
            width: Math.max(0, header.width - header.spacing - header.height)
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily
            text: root.titleText("ナビ案内")
            color: Theme.textSecondary
            font.pixelSize: root.titleFontSize
            elide: Text.ElideRight
        }
    }

    // ---- 本体の領域(見出しの下) ----
    Item {
        id: area
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom
                  leftMargin: root.m; rightMargin: root.m; bottomMargin: root.m
                  topMargin: root.titleVisible ? root.m * 0.5 : root.m }

        // ================================================================ 待機中
        Column {
            visible: !root.active
            anchors.centerIn: parent
            width: parent.width
            spacing: root.m * 0.4
            opacity: 0.85

            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "navigation"
                size: Math.max(18, Math.min(area.height * 0.34, area.width * 0.2))
                color: Theme.textSecondary
            }
            Text {
                width: parent.width
                height: Math.max(13, Math.min(area.height * 0.14, 24))
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
            Text {
                visible: area.height >= 110
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Android Auto でナビを始めると、ここに次の曲がり角を表示します"
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Math.max(10, Math.round(root.titleFontSize * 0.8))
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        // ================================================================ 案内中
        // 文字の大きさは本体の高さから 1 か所で決め、要素の大きさはすべてそこから導く(大きさの体系):
        //   D = 距離の数値 / U = 単位(D の 45%)/ R = 道路名(D の 42%)/ N = その次(R の 85%)
        //   タイル = 距離 1 行 + 道路名 1 行の高さ(左に置き、文字のまとまりと上下中央をそろえる)
        // 「その次」は、下に帯を置く余裕があれば下、横に余裕があれば右、どちらも無ければ出さない
        Item {
            id: guide
            visible: root.active
            anchors.fill: parent

            readonly property bool hasRoad: root.mainSub !== ""
            readonly property bool hasDistance: root.distanceString !== ""
            // 「その次」の帯の高さ(下に置くとき)
            readonly property real stripH: Math.round(Math.max(24, Math.min(40, height * 0.24)))
            readonly property bool nextBottom: root.showNext && height - stripH - gapV >= 64
            readonly property bool nextRight: root.showNext && !nextBottom && width >= 460
            readonly property real nextW: nextRight ? Math.round(Math.min(220, width * 0.3)) : 0
            readonly property real gapV: Math.round(Math.max(6, root.m * 0.8))
            readonly property real gapH: Math.round(Math.max(8, root.m))

            // 案内カードの領域
            readonly property real cardW: width - (nextRight ? nextW + gapH : 0)
            readonly property real cardH: height - (nextBottom ? stripH + gapV : 0)

            // ---- 大きさの体系 ----
            // カードが縦に高ければ縦積み(タイル → 距離 → 道路名。中央そろえ)、そうでなければ横並び(タイル | 距離・道路名)
            readonly property bool stacked: cardH >= cardW * 0.62 && cardH >= 150
            readonly property real lines: hasRoad ? 1.0 + 0.42 * 1.35 : 1.0      // 文字のまとまりが距離何行分か
            readonly property real fontD: Math.round(Math.max(20, stacked
                ? Math.min(72, cardH * 0.24, cardW * 0.24)
                : Math.min(72, cardH / (lines * 1.12), (cardW - Math.min(cardH, cardW * 0.3)) * 0.22)))
            readonly property real fontU: Math.round(fontD * 0.45)
            readonly property real fontR: Math.round(Math.max(12, Math.min(30, fontD * 0.42)))
            readonly property real fontN: Math.round(Math.max(11, Math.min(20, fontR * 0.85)))
            readonly property real barH: root.near ? Math.max(4, Math.round(fontD * 0.09)) : 0
            readonly property real blockH: fontD * 1.12 + (barH > 0 ? barH + 4 : 0) + (hasRoad ? fontR * 1.35 : 0)
            readonly property real tile: Math.round(stacked ? Math.min(cardW * 0.5, cardH - blockH - gapV)
                                                            : Math.min(cardH, cardW * 0.3, blockH))

            // ---- 案内カード ----
            Item {
                id: card
                anchors { left: parent.left; top: parent.top }
                width: guide.cardW
                height: guide.cardH

                // 方向アイコンのタイル(接近すると警告色)
                // 縦積みのとき、タイル + 文字のまとまり全体をカードの上下中央に置く
                readonly property real stackTop: Math.max(0, (height - guide.tile - guide.gapV - block.height) / 2)

                Rectangle {
                    id: tileBox
                    x: guide.stacked ? (card.width - width) / 2 : 0
                    y: guide.stacked ? card.stackTop : (card.height - height) / 2
                    width: guide.tile
                    height: guide.tile
                    radius: Math.round(width * 0.2)
                    color: root.cueColor
                    Behavior on color { ColorAnimation { duration: 200 } }
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: root.maneuverIcon(root.maneuver, root.maneuverSide)
                        size: Math.round(parent.width * 0.74)
                        color: Theme.textOnAccent
                    }
                }

                // 距離・接近バー・道路名のまとまり(タイルと上下中央をそろえる)
                Column {
                    id: block
                    x: guide.stacked ? 0 : tileBox.width + guide.gapH
                    y: guide.stacked ? tileBox.y + tileBox.height + guide.gapV : (card.height - height) / 2
                    width: card.width - x
                    spacing: 0

                    Row {   // 距離: 数値を大きく、単位を小さく(下揃え)
                        visible: guide.hasDistance
                        anchors.horizontalCenter: guide.stacked ? parent.horizontalCenter : undefined
                        height: Math.round(guide.fontD * 1.12)
                        spacing: Math.round(guide.fontD * 0.08)
                        Text {
                            id: distanceValue
                            anchors.bottom: parent.bottom
                            text: root.distanceParts.value
                            color: root.cueColor
                            font.family: Theme.fontFamily
                            font.bold: true
                            font.pixelSize: guide.fontD
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        Text {
                            anchors.baseline: distanceValue.baseline
                            text: root.distanceParts.unit
                            color: root.cueColor
                            font.family: Theme.fontFamily
                            font.bold: true
                            font.pixelSize: guide.fontU
                        }
                    }

                    Item {   // 接近バー(残り距離に応じて縮む)
                        visible: root.near
                        width: block.width
                        height: guide.barH + 4
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: guide.barH
                            radius: height / 2
                            color: Theme.panelBorder
                            Rectangle {
                                width: parent.width * root.nearRatio
                                height: parent.height
                                radius: height / 2
                                color: Theme.warn
                                Behavior on width { NumberAnimation { duration: 200 } }
                            }
                        }
                    }

                    Text {   // 道路名(なければ方向名)。カードに余裕があれば 2 行まで
                        visible: guide.hasRoad
                        width: block.width
                        text: root.mainSub
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.bold: true
                        font.pixelSize: guide.fontR
                        horizontalAlignment: guide.stacked ? Text.AlignHCenter : Text.AlignLeft
                        lineHeight: 1.1
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        maximumLineCount: (guide.stacked ? card.height - guide.tile - guide.gapV : card.height)
                                          >= guide.blockH + guide.fontR * 1.4 ? 2 : 1
                        elide: Text.ElideRight
                    }
                }
            }

            // ---- その次(下の帯) ----
            Rectangle {
                visible: guide.nextBottom
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: guide.stripH
                radius: Math.round(height * 0.3)
                color: Theme.mix(Theme.panel, Theme.panelBorder, 0.6)

                Row {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: Math.round(guide.stripH * 0.35); rightMargin: Math.round(guide.stripH * 0.35) }
                    spacing: Math.round(guide.fontN * 0.5)

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "その次"
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(guide.fontN * 0.85)
                    }
                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.maneuverIcon(root.nextManeuver, root.nextSide)
                        size: Math.round(guide.fontN * 1.3)
                        color: Theme.textPrimary
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, parent.width - x)
                        text: root.nextSub
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: guide.fontN
                        elide: Text.ElideRight
                    }
                }
            }

            // ---- その次(右の列。横長で下に余裕が無いとき) ----
            Item {
                visible: guide.nextRight
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: guide.nextW

                Rectangle {   // 区切り線
                    x: -Math.round(guide.gapH / 2)
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: parent.height * 0.8
                    color: Theme.panelBorder
                }
                Column {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: Math.round(guide.fontN * 0.3)

                    Text {
                        text: "その次"
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(guide.fontN * 0.85)
                    }
                    Row {
                        width: parent.width
                        spacing: Math.round(guide.fontN * 0.4)
                        MaterialIcon {
                            id: nextIconR
                            anchors.verticalCenter: parent.verticalCenter
                            name: root.maneuverIcon(root.nextManeuver, root.nextSide)
                            size: Math.round(guide.fontN * 1.6)
                            color: Theme.textPrimary
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, parent.width - nextIconR.width - parent.spacing)
                            text: root.nextSub
                            color: Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: guide.fontN
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    // ---- モックの札(モックの案内を出している間) ----
    Rectangle {
        visible: root.isMock
        z: 10
        anchors { top: parent.top; right: parent.right; topMargin: root.m * 0.6; rightMargin: root.m }
        width: mockTag.implicitWidth + 14
        height: mockTag.implicitHeight + 6
        radius: height / 2
        color: "transparent"
        border.color: Theme.warn
        Text {
            id: mockTag
            anchors.centerIn: parent
            font.family: Theme.fontFamily
            text: "モック"
            color: Theme.warn
            font.pixelSize: root.detailFontSize
        }
    }
}
