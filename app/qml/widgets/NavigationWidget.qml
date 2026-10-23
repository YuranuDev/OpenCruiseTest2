// Android Auto NavigationStatus チャネルから受け取った次の案内を表示する。
import QtQuick
import OpenCruise

WidgetBase {
    id: root
    readonly property real m: Math.max(8, root.s * 0.06)
    readonly property bool hasNextCue: androidAuto.nextNavigationManeuver > 0

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
        if (config.distanceUnit !== "km" && androidAuto.navigationDistanceLabel !== "")
            return androidAuto.navigationDistanceLabel
        if (meters < 0) return ""
        if (config.distanceUnit === "km") return (meters / 1000).toFixed(1) + " km"
        return meters >= 1000 ? (meters / 1000).toFixed(1) + " km" : meters + " m"
    }

    Row {
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: root.m }
        spacing: 8
        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: "navigation"
            size: Math.max(18, root.s * 0.11)
            color: Theme.accent
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "ナビ案内"
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(12, root.s * 0.075)
        }
    }

    Item {
        anchors { fill: parent; topMargin: root.m * 2.3; leftMargin: root.m; rightMargin: root.m
                  bottomMargin: root.hasNextCue ? root.s * 0.24 : root.m }
        visible: androidAuto.navigationActive
        MaterialIcon {
            id: direction
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            name: root.maneuverIcon(androidAuto.navigationManeuver, androidAuto.navigationSide)
            size: Math.min(parent.height * 0.68, parent.width * 0.28)
            color: Theme.accent
        }
        Column {
            anchors { left: direction.right; leftMargin: root.m; right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 4
            Text {
                width: parent.width
                text: androidAuto.navigationRoad !== "" && config.showRoad !== false ? androidAuto.navigationRoad : "次の案内"
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Math.max(15, root.s * 0.105)
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                visible: androidAuto.navigationDistanceMeters >= 0 || androidAuto.navigationDistanceLabel !== ""
                text: root.distanceText(androidAuto.navigationDistanceMeters)
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Math.max(13, root.s * 0.085)
            }
        }
    }

    Row {
        id: nextCue
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: root.m; rightMargin: root.m; bottomMargin: root.m * 0.6 }
        visible: androidAuto.navigationActive && root.hasNextCue
        height: root.s * 0.19
        spacing: root.m
        MaterialIcon {
            id: nextCueIcon
            anchors.verticalCenter: parent.verticalCenter
            name: root.maneuverIcon(androidAuto.nextNavigationManeuver, androidAuto.nextNavigationSide)
            size: parent.height * 0.82
            color: Theme.accent
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - nextCueIcon.width - root.m
            text: (config.showRoad !== false && androidAuto.nextNavigationRoad !== "")
                  ? androidAuto.nextNavigationRoad : "その次の案内"
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(11, root.s * 0.07)
            elide: Text.ElideRight
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !androidAuto.navigationActive
        text: "ナビ案内を待っています"
        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: Math.max(12, root.s * 0.075)
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        width: parent.width - root.m * 2
    }
}
