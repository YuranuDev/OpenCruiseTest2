// 設定画面。左側にジャンル一覧、右側に選択中ジャンルの設定ページを表示する(車載向けの大きなタッチ操作用)。
//
// ■ ジャンルを足す
//   1. 右側に出すページを SettingsPage を土台にした新しい .qml として作る(例: SettingsPageAudio.qml)。
//   2. 下の categories に SettingsCategory { icon: "..."; title: "..."; page: SettingsPageAudio {} } を 1 行足す。
//   3. app/CMakeLists.txt の QML_FILES に新しい .qml を足す。
//   アイコン名は Material Icons(https://fonts.google.com/icons)から選ぶ。
//
// ■ 設定項目を足す
//   該当ジャンルのページの SettingsSection の中へ、SettingsRow(+ SettingsChoice / SettingsSwitch など)や
//   SettingsInfoRow(読み取り専用)を足す。部品の使い方は各 .qml の先頭コメントを参照。
import QtQuick
import QtQuick.Controls

Rectangle {
    id: root
    color: Theme.background
    signal back()

    readonly property real unit: Theme.uiScale
    // 選択中のジャンル(categories の番号)
    property int currentIndex: 0

    // ---- ジャンル一覧(表示順)。ここに足すだけで左の一覧と右のページへ反映される ----
    property list<SettingsCategory> categories: [
        SettingsCategory { icon: "tune";          title: "一般";         page: SettingsPageGeneral {} },
        SettingsCategory { icon: "palette";       title: "表示";         page: SettingsPageDisplay {} },
        SettingsCategory { icon: "power_settings_new"; title: "電源管理"; page: SettingsPagePower {} },
        SettingsCategory { icon: "volume_up";     title: "サウンド";     page: SettingsPageAudio {} },
        SettingsCategory { icon: "android";       title: "Android Auto"; page: SettingsPageAndroidAuto {} },
        SettingsCategory { icon: "notifications"; title: "通知";         page: SettingsPageNotifications {} },
        SettingsCategory { icon: "directions_car"; title: "車両";        page: SettingsPageVehicle {} },
        SettingsCategory { icon: "monitor_heart"; title: "システム";    page: SettingsPageSystem {} },
        SettingsCategory { icon: "info";          title: "情報";         page: SettingsPageAbout {} }
    ]

    // ---- ヘッダー: 戻るボタン + タイトル ----
    Item {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: Theme.margin }
        height: 80 * root.unit

        Rectangle {
            id: backButton
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: backRow.width + 48 * root.unit
            height: 68 * root.unit
            radius: Theme.radius + 2
            color: Theme.mix(Theme.panel, Theme.accentFill, backMouse.pressed ? 0.45 : 0)
            border.width: backMouse.pressed ? 2 : 1
            border.color: backMouse.pressed ? Theme.accent : Theme.panelBorder
            scale: backMouse.pressed ? 0.97 : 1.0
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

            Row {
                id: backRow
                anchors.centerIn: parent
                spacing: 10 * root.unit
                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "arrow_back"
                    size: 38 * root.unit
                    color: Theme.accent
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    text: "戻る"
                    color: Theme.textPrimary
                    font.pixelSize: 28 * root.unit
                    font.bold: true
                }
            }
            MouseArea {
                id: backMouse
                anchors.fill: parent
                onClicked: { root.back() }
            }
        }

        NotificationBell {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            size: 68 * root.unit
        }

        Text {
            anchors.centerIn: parent
            font.family: Theme.fontFamily
            text: "設定"
            color: Theme.textPrimary
            font.pixelSize: 38 * root.unit
            font.bold: true
        }
    }

    // ---- 左: ジャンル一覧 ----
    Rectangle {
        id: sidebar
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left
                  leftMargin: Theme.margin; bottomMargin: Theme.margin; topMargin: 4 }
        width: 340 * root.unit
        color: Theme.panel
        radius: Theme.radius + 6
        border.width: 1
        border.color: Theme.panelBorder

        ListView {
            anchors { fill: parent; margins: 10 * root.unit }
            model: root.categories.length
            spacing: 8 * root.unit
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: SettingsCategoryButton {
                width: ListView.view.width
                icon: root.categories[index].icon
                title: root.categories[index].title
                selected: index === root.currentIndex
                onClicked: root.currentIndex = index
            }
        }
    }

    // ---- 右: 選択中ジャンルの設定ページ ----
    Item {
        id: pageArea
        anchors { top: header.bottom; bottom: parent.bottom; left: sidebar.right; right: parent.right
                  leftMargin: Theme.margin; rightMargin: Theme.margin; bottomMargin: Theme.margin; topMargin: 4 }

        Loader {
            id: pageLoader
            anchors.fill: parent
            sourceComponent: root.categories.length > 0 ? root.categories[root.currentIndex].page : null
            // ジャンルを切り替えたとき、中身がぱっと変わらないよう軽くフェードインする
            onLoaded: fadeIn.restart()
            NumberAnimation { id: fadeIn; target: pageLoader; property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic }
        }
    }
}
