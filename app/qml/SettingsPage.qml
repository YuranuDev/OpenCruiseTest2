// 設定ページの土台。縦にスクロールできる領域で、中に SettingsSection を並べる。
//   SettingsPage {
//       SettingsSection { title: "..."; icon: "..."; SettingsRow { ... } }
//   }
// 子要素は自動的に縦一列(間隔つき)に並ぶ。指やタッチで上下にスワイプでき、右端に太めのスクロールバーを出す。
import QtQuick
import QtQuick.Controls

Flickable {
    id: root
    default property alias content: column.data

    readonly property real unit: Theme.uiScale

    contentWidth: width
    contentHeight: column.implicitHeight + 16 * unit
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick

    ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
        implicitWidth: 14 * root.unit
    }

    Column {
        id: column
        // 右端のスクロールバーと重ならないよう、少し余白を空ける
        width: root.width - 22 * root.unit
        spacing: Theme.margin * root.unit
    }
}
