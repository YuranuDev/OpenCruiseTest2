// 設定の補足説明(小さめの文章)。SettingsSection の中に置く。
import QtQuick

Text {
    width: parent ? parent.width : implicitWidth
    topPadding: 10 * Theme.uiScale
    bottomPadding: 6 * Theme.uiScale
    font.family: Theme.fontFamily
    color: Theme.textSecondary
    font.pixelSize: 18 * Theme.uiScale
    wrapMode: Text.WordWrap
}
