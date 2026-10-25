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
        Item {
            id: guide
            visible: root.active
            anchors.fill: parent

            // 「その次」の置き場所: 右の列 / 下の帯 / 出さない
            readonly property bool nextRight: root.showNext && width >= height * 2.4 && width >= 300
            readonly property bool nextBottom: root.showNext && !nextRight && height >= 120
            readonly property real nextW: nextRight ? Math.max(110, Math.min(width * 0.28, 260)) : 0
            readonly property real nextH: nextBottom ? Math.max(26, Math.min(height * 0.26, 56)) : 0

            // ---- 案内カード ----
            Item {
                id: card
                anchors { left: parent.left; top: parent.top }
                width: guide.width - (guide.nextRight ? guide.nextW + root.m : 0)
                height: guide.height - (guide.nextBottom ? guide.nextH + root.m * 0.8 : 0)

                // 縦長なら縦積み(タイル → 距離 → 道路名)、そうでなければ横並び(タイル | 距離・道路名)
                readonly property bool stacked: width < height * 0.95
                readonly property bool hasRoad: root.mainSub !== ""
                readonly property real gap: Math.max(6, root.m * 0.8)
                readonly property real tile: stacked ? Math.min(width * 0.62, height * 0.42)
                                                     : Math.min(height, width * 0.36)

                // 方向アイコンのタイル(接近すると警告色)
                Rectangle {
                    id: tileBox
                    x: card.stacked ? (card.width - width) / 2 : 0
                    y: card.stacked ? 0 : (card.height - height) / 2
                    width: card.tile
                    height: card.tile
                    radius: Math.max(Theme.radius, width * 0.18)
                    color: root.cueColor
                    Behavior on color { ColorAnimation { duration: 200 } }
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: root.maneuverIcon(androidAuto.navigationManeuver, androidAuto.navigationSide)
                        size: parent.width * 0.78
                        color: Theme.textOnAccent
                    }
                }

                // 距離と道路名
                Item {
                    id: info
                    x: card.stacked ? 0 : tileBox.width + card.gap
                    y: card.stacked ? tileBox.height + card.gap * 0.6 : 0
                    width: card.width - x
                    height: card.height - y

                    readonly property real barH: root.near ? Math.max(4, Math.round(root.s * 0.03)) : 0
                    // 距離の行の高さ(道路名があれば 55%、なければほぼ全部)
                    readonly property real distanceH: root.distanceString === "" ? 0
                                                      : Math.max(16, (height - barH) * (card.hasRoad ? 0.55 : 0.92))

                    // 距離: 数値を大きく、単位を小さく(下揃え)
                    Item {
                        id: distanceRow
                        visible: root.distanceString !== ""
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        height: info.distanceH

                        Text {
                            id: distanceValue
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: Math.min(implicitWidth, parent.width - distanceUnit.implicitWidth - 6)
                            horizontalAlignment: card.stacked ? Text.AlignHCenter : Text.AlignLeft
                            verticalAlignment: Text.AlignBottom
                            text: root.distanceParts.value
                            color: root.cueColor
                            font.family: Theme.fontFamily
                            font.bold: true
                            font.pixelSize: Math.max(14, Math.round(parent.height * 0.95))
                            minimumPixelSize: 12
                            fontSizeMode: Text.HorizontalFit
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        Text {
                            id: distanceUnit
                            anchors { left: distanceValue.right; leftMargin: 4; baseline: distanceValue.baseline }
                            text: root.distanceParts.unit
                            color: root.cueColor
                            font.family: Theme.fontFamily
                            font.bold: true
                            font.pixelSize: Math.max(11, Math.round(distanceRow.height * 0.4))   // 数値の大きさに頼らない(束縛の循環を避ける)
                        }
                        // 縦積みのときは、数値と単位のまとまりを中央に寄せる
                        transform: Translate {
                            x: card.stacked ? Math.max(0, (distanceRow.width - distanceValue.width - distanceUnit.implicitWidth - 4) / 2) : 0
                        }
                    }

                    // 接近バー(残り距離に応じて縮む)
                    Rectangle {
                        visible: root.near
                        anchors { top: distanceRow.bottom; topMargin: 2; left: parent.left }
                        width: parent.width
                        height: info.barH
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

                    // 道路名(なければ方向名)。高さに余裕があれば 2 行まで
                    Text {
                        visible: card.hasRoad
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: info.height - info.distanceH - info.barH - (root.near ? 4 : 2)
                        horizontalAlignment: card.stacked ? Text.AlignHCenter : Text.AlignLeft
                        verticalAlignment: Text.AlignTop
                        text: root.mainSub
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.bold: true
                        font.pixelSize: Math.max(12, Math.min(Math.round(height * 0.6), Math.round(root.s * 0.14), 34))
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        maximumLineCount: height >= font.pixelSize * 2.3 ? 2 : 1
                        elide: Text.ElideRight
                    }
                }
            }

            // ---- その次(右の列) ----
            Item {
                visible: guide.nextRight
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: guide.nextW

                Rectangle {   // 区切り線
                    x: -root.m * 0.5
                    width: 1
                    height: parent.height
                    color: Theme.panelBorder
                }
                Column {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: root.m * 0.3 }
                    spacing: Math.max(3, root.m * 0.4)

                    Text {
                        text: "その次"
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.max(10, Math.round(root.titleFontSize * 0.85))
                    }
                    MaterialIcon {
                        name: root.maneuverIcon(androidAuto.nextNavigationManeuver, androidAuto.nextNavigationSide)
                        size: Math.max(18, Math.min(parent.width * 0.4, guide.height * 0.34))
                        color: Theme.textSecondary
                    }
                    Text {
                        width: parent.width
                        text: root.nextSub
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.max(11, Math.min(Math.round(root.titleFontSize * 0.95), 18))
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
            }

            // ---- その次(下の帯) ----
            Rectangle {
                visible: guide.nextBottom
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: guide.nextH
                radius: Math.min(height / 2, Theme.radius)
                color: Theme.mix(Theme.panel, Theme.panelBorder, 0.6)

                Row {
                    anchors { fill: parent; leftMargin: root.m * 0.6; rightMargin: root.m * 0.6 }
                    spacing: root.m * 0.5

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "その次"
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.max(10, Math.round(guide.nextH * 0.34))
                    }
                    MaterialIcon {
                        id: nextIcon
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.maneuverIcon(androidAuto.nextNavigationManeuver, androidAuto.nextNavigationSide)
                        size: guide.nextH * 0.66
                        color: Theme.textPrimary
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, parent.width - x)
                        text: root.nextSub
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.max(11, Math.round(guide.nextH * 0.4))
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
