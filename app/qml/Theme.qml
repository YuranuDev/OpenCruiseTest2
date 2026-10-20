// 画面全体で共有する色・サイズ（シングルトン）。暗色基調の車載向け配色。
pragma Singleton
import QtQuick

QtObject {
    readonly property color background: "#0d1015"
    readonly property color panel: "#161b23"
    readonly property color panelBorder: "#252c37"
    readonly property color textPrimary: "#e8ebf0"
    readonly property color textSecondary: "#8c95a3"
    readonly property color accent: "#4da3ff"
    readonly property color ok: "#3ddc84"
    readonly property color warn: "#ffb74d"
    readonly property color error: "#ff5c5c"
    readonly property int radius: 14
    readonly property int margin: 16

    // 接続状態キーに対応する表示色
    function stateColor(key) {
        switch (key) {
        case "streaming": return ok
        case "connected": return accent
        case "connecting": return accent
        case "waiting": return warn
        default: return error
        }
    }
}
