// Android Auto NavigationStatus チャネルから受け取った次の案内を表示する。
import QtQuick
import OpenCruise

WidgetBase {
    id: root

    readonly property real m: Math.max(6, Math.min(14, root.s * 0.055))
    readonly property bool hasNextCue: androidAuto.nextNavigationManeuver > 0
    readonly property real headerHeight: Math.max(18, root.s * 0.12)
    readonly property real nextCueHeight: Math.max(27, Math.min(root.s * 0.19, root.height * 0.22))

    function maneuverIcon(kind, side) {
        const right = side === 2
        switch (kind) {
        case 3: case 4: case 5: return right ? "turn_right" : "turn_left"
        case 6: return right ? "u_turn_right" : "u_turn_left"
        case 7: return right ? "ramp_right" : "ramp_left"
        case 8: return right ? "ramp_right" : "ramp_left"
        case 9: return right ? "fork_right" : "fork_left"
        case 10: return "merge"
        case 11: case 12: case 13: return right ? "roundabout_right" : "roundabout_left"
        case 19: return "flag"
        default: return "straight"
        }
    }

    function distanceText(meters) {
        // 自動表示では Android Auto の表示文字列を使う。ただし数値距離が
        // 0 より大きいのに表示文字列が 0 を示す場合は、数値を優先する。
        const label = androidAuto.navigationDistanceLabel.trim()
        const labelIsZero = /^(0+(?:[.,]0+)?\s*(?:m|km|メートル|キロメートル)?)$/i.test(label)
        if (config.distanceUnit !== "km" && label !== "" && !(meters > 0 && labelIsZero))
            return label
        if (meters < 0) return ""
        if (config.distanceUnit === "km") return (meters / 1000).toFixed(1) + " km"
        return meters >= 1000 ? (meters / 1000).toFixed(1) + " km" : meters + " m"
    }

    // ---- 見出し ----
    Row {
        id: header
        anchors { top: parent.top; left: parent.left; topMargin: root.m * 0.65; leftMargin: root.m }
        height: root.headerHeight
        spacing: root.m * 0.45

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: "navigation"
            size: Math.min(parent.height, root.s * 0.13)
            color: Theme.accent
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "ナビ案内"
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(11, root.s * 0.075)
            elide: Text.ElideRight
        }
    }

    // ---- 次の曲がり角 ----
    Item {
        id: mainCue
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom
                  leftMargin: root.m; rightMargin: root.m; topMargin: root.m * 0.35
                  bottomMargin: root.hasNextCue ? nextCue.height + root.m * 1.25 : root.m }
        clip: true

        Rectangle {
            anchors.fill: parent
            radius: Math.min(Theme.radius, height * 0.12)
            color: Theme.panelBorder
            opacity: androidAuto.navigationActive ? 0.24 : 0
        }

        Row {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                      leftMargin: root.m * 0.55; rightMargin: root.m * 0.55 }
            spacing: root.m * 0.55
            visible: androidAuto.navigationActive

            MaterialIcon {
                id: mainDirection
                anchors.verticalCenter: parent.verticalCenter
                name: root.maneuverIcon(androidAuto.navigationManeuver, androidAuto.navigationSide)
                size: Math.max(22, Math.min(root.s * 0.42, mainCue.height * 0.72, mainCue.width * 0.25))
                color: Theme.accent
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - mainDirection.width - parent.spacing)
                spacing: Math.max(1, mainCue.height * 0.025)

                Text {
                    width: parent.width
                    height: Math.max(16, mainCue.height * 0.34)
                    verticalAlignment: Text.AlignVCenter
                    text: androidAuto.navigationRoad !== "" && config.showRoad !== false
                          ? androidAuto.navigationRoad : "次の案内"
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.pixelSize: 100
                    minimumPixelSize: 11
                    fontSizeMode: Text.Fit
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    height: Math.max(20, mainCue.height * 0.48)
                    verticalAlignment: Text.AlignVCenter
                    visible: androidAuto.navigationDistanceMeters >= 0 || androidAuto.navigationDistanceLabel !== ""
                    text: root.distanceText(androidAuto.navigationDistanceMeters)
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.pixelSize: 160
                    minimumPixelSize: 12
                    fontSizeMode: Text.Fit
                    elide: Text.ElideRight
                }
            }
        }

        Column {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: root.m * 0.25
            visible: !androidAuto.navigationActive

            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "navigation"
                size: Math.min(root.s * 0.24, mainCue.height * 0.38)
                color: Theme.textSecondary
                opacity: 0.65
            }
            Text {
                width: parent.width - root.m
                anchors.horizontalCenter: parent.horizontalCenter
                text: "ナビ案内を待っています"
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Math.max(11, root.s * 0.075)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
            }
        }
    }

    // ---- その次の案内。横幅・高さが小さいときも一行で省略して主案内を圧迫しない ----
    Item {
        id: nextCue
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                  leftMargin: root.m; rightMargin: root.m; bottomMargin: root.m * 0.55 }
        height: root.nextCueHeight
        visible: androidAuto.navigationActive && root.hasNextCue

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 1
            color: Theme.panelBorder
        }

        Row {
            anchors { fill: parent; topMargin: 1; leftMargin: root.m * 0.15; rightMargin: root.m * 0.15 }
            spacing: root.m * 0.45

            MaterialIcon {
                id: nextDirection
                anchors.verticalCenter: parent.verticalCenter
                name: root.maneuverIcon(androidAuto.nextNavigationManeuver, androidAuto.nextNavigationSide)
                size: Math.max(16, Math.min(parent.height * 0.68, root.s * 0.19))
                color: Theme.accent
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - nextDirection.width - parent.spacing)
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: (config.showRoad !== false && androidAuto.nextNavigationRoad !== "")
                      ? androidAuto.nextNavigationRoad : "その次の案内"
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: 100
                minimumPixelSize: 10
                fontSizeMode: Text.Fit
                elide: Text.ElideRight
            }
        }
    }
}
