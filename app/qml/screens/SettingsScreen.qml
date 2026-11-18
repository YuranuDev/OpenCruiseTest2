// 設定画面。左側にジャンル一覧(大きな分類ごとに見出しを付けて並べる)、右側に選択中ジャンルの設定ページを表示する
// (車載向けの大きなタッチ操作用)。右側のページの上には「分類 › ジャンル」と中身の例を出し、今どこにいるかが分かるようにする。
//
// 分類(groups)とジャンル(categories)の並び:
//   表示と操作: 画面 / テーマ・背景 / ユーザー・文字
//   音:         音量・出力先 / 効果音 / マイク
//   車両:       車両データ / 警告・注意 / バックカメラ
//   スマホ連携: Android Auto / スマホ通知
//   システム:   電源 / 描画 / システムの状態 / 情報
// よく触るもの(画面・音量)を上に、めったに触らないもの(描画・情報)を下にする。
//
// ■ ジャンルを足す
//   1. 右側に出すページを SettingsPage を土台にした新しい .qml として作る(例: SettingsPageAudio.qml)。
//   2. 下の categories の、入れたい分類(group)の所に SettingsCategory { group: "..."; icon: "..."; title: "...";
//      description: "..."; page: SettingsPageAudio {} } を 1 行足す(同じ分類はまとめて並べる)。
//   3. app/CMakeLists.txt の QML_FILES に新しい .qml を足す。
//   アイコン名は Material Icons(https://fonts.google.com/icons)から選ぶ。
//   設定の中で別の設定の場所を案内するときは「設定 > 分類 > ジャンル」と書く(例: 設定 > 音 > 効果音)。
//
// ■ 設定項目を足す
//   該当ジャンルのページの SettingsSection の中へ、SettingsRow(+ SettingsChoice / SettingsSwitch など)や
//   SettingsInfoRow(読み取り専用)を足す。部品の使い方は各 .qml の先頭コメントを参照。
import QtQuick
import QtQuick.Controls
import OpenCruise

Rectangle {
    id: root
    color: "transparent"   // 背景は Main.qml の ThemeBackground(テーマの背景色・模様・画像)
    signal back()

    readonly property real unit: Theme.uiScale
    // 選択中のジャンル(categories の番号)
    property int currentIndex: 0

    // ---- 分類(左の一覧の見出し。表示順) ----
    readonly property var groups: [
        { id: "display", title: "表示と操作", icon: "tv" },
        { id: "sound",   title: "音",         icon: "graphic_eq" },
        { id: "vehicle", title: "車両",       icon: "directions_car" },
        { id: "phone",   title: "スマホ連携", icon: "smartphone" },
        { id: "system",  title: "システム",   icon: "settings" }
    ]
    function groupOf(id) {
        for (const g of groups) if (g.id === id) return g
        return { id: id, title: "", icon: "tune" }
    }

    // ---- ジャンル一覧(表示順。同じ分類はまとめて並べる)。ここに足すだけで左の一覧と右のページへ反映される ----
    property list<SettingsCategory> categories: [
        SettingsCategory { group: "display"; icon: "monitor";       title: "画面";           description: "明るさ・回転・端のボタン・外部モニター"; page: SettingsPageDisplay {} },
        SettingsCategory { group: "display"; icon: "palette";       title: "テーマ・背景";   description: "テーマ・昼夜・アクセント色・背景";       page: SettingsPageTheme {} },
        SettingsCategory { group: "display"; icon: "person";        title: "ユーザー・文字"; description: "ユーザー名・フォント";                   page: SettingsPageGeneral {} },
        SettingsCategory { group: "sound";   icon: "volume_up";     title: "音量・出力先";   description: "マスター音量・各音量・出力先";           page: SettingsPageAudio {} },
        SettingsCategory { group: "sound";   icon: "music_note";    title: "効果音";         description: "操作音・起動音・警告音・注意音";         page: SettingsPageSounds {} },
        SettingsCategory { group: "sound";   icon: "mic";           title: "マイク";         description: "Android Auto の音声入力";                page: SettingsPageMicrophone {} },
        SettingsCategory { group: "vehicle"; icon: "speed";         title: "車両データ";     description: "データ元(ノード)・同じ項目の選び方・ダミー"; page: SettingsPageVehicle {} },
        SettingsCategory { group: "vehicle"; icon: "warning";       title: "警告・注意";     description: "条件を決めて音・通知で知らせる";         page: SettingsPageAlerts {} },
        SettingsCategory { group: "vehicle"; icon: "videocam";      title: "バックカメラ";   description: "自動の切り替え・カメラ・映し方";         page: SettingsPageCamera {} },
        SettingsCategory { group: "phone";   icon: "android";       title: "Android Auto";   description: "接続状態・ダミーデータ・映像・映像の配置";             page: SettingsPageAndroidAuto {} },
        SettingsCategory { group: "phone";   icon: "notifications"; title: "スマホ通知";     description: "通知のポップアップ";                     page: SettingsPageNotifications {} },
        SettingsCategory { group: "system";  icon: "power_settings_new"; title: "電源";      description: "電源モード・ACC OFF での終了";           page: SettingsPagePower {} },
        SettingsCategory { group: "system";  icon: "memory";        title: "描画";           description: "描画方式・垂直同期・フレームレート";     page: SettingsPageRendering {} },
        SettingsCategory { group: "system";  icon: "monitor_heart"; title: "システムの状態"; description: "CPU・GPU・メモリ";                       page: SettingsPageSystem {} },
        SettingsCategory { group: "system";  icon: "info";          title: "情報";           description: "バージョン・キーボードの操作・ログ・ライセンス";           page: SettingsPageAbout {} }
    ]
    readonly property var current: categories.length > 0 ? categories[currentIndex] : null
    readonly property var currentGroup: current ? groupOf(current.group) : null

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

    // ---- 左: ジャンル一覧(分類ごとに見出しを付ける) ----
    Rectangle {
        id: sidebar
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left
                  leftMargin: Theme.margin; bottomMargin: Theme.margin; topMargin: 4 }
        width: 340 * root.unit
        color: Theme.panel
        radius: Theme.radius + 6
        border.width: 1
        border.color: Theme.panelBorder

        Flickable {
            id: sideList
            anchors { fill: parent; margins: 10 * root.unit }
            contentHeight: sideColumn.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: sideColumn
                width: sideList.width
                spacing: 6 * root.unit

                Repeater {
                    model: root.groups
                    Column {
                        id: groupBlock
                        required property var modelData
                        required property int index
                        width: sideColumn.width
                        spacing: 6 * root.unit

                        // 分類の見出し(アイコン + 名前 + 細い線)
                        Item {
                            width: parent.width
                            height: (groupBlock.index === 0 ? 36 : 50) * root.unit
                            Row {
                                anchors { left: parent.left; leftMargin: 8 * root.unit; bottom: parent.bottom; bottomMargin: 6 * root.unit }
                                spacing: 8 * root.unit
                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: groupBlock.modelData.icon
                                    size: 22 * root.unit
                                    color: root.current && root.current.group === groupBlock.modelData.id ? Theme.accent : Theme.textSecondary
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 19 * root.unit
                                    font.bold: true
                                    color: root.current && root.current.group === groupBlock.modelData.id ? Theme.accent : Theme.textSecondary
                                    text: groupBlock.modelData.title
                                }
                            }
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 8 * root.unit; rightMargin: 8 * root.unit }
                                height: 1
                                color: Theme.panelBorder
                            }
                        }

                        Repeater {
                            model: root.categories.length
                            SettingsCategoryButton {
                                required property int index
                                readonly property var cat: root.categories[index]
                                visible: cat.group === groupBlock.modelData.id
                                width: groupBlock.width
                                height: visible ? implicitHeight : 0
                                icon: cat.icon
                                title: cat.title
                                description: cat.description
                                selected: index === root.currentIndex
                                onClicked: root.currentIndex = index
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- 右: 選択中ジャンルの設定ページ ----
    Item {
        id: pageArea
        anchors { top: header.bottom; bottom: parent.bottom; left: sidebar.right; right: parent.right
                  leftMargin: Theme.margin; rightMargin: Theme.margin; bottomMargin: Theme.margin; topMargin: 4 }

        // 今いる場所: 「分類 › ジャンル」と、ジャンルの中身の例
        Item {
            id: pageHeader
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 74 * root.unit
            Row {
                id: crumb
                anchors { left: parent.left; leftMargin: 6 * root.unit; top: parent.top; topMargin: 2 * root.unit }
                spacing: 8 * root.unit
                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.currentGroup ? root.currentGroup.icon : ""
                    size: 22 * root.unit
                    color: Theme.textSecondary
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: 19 * root.unit
                    color: Theme.textSecondary
                    text: (root.currentGroup ? root.currentGroup.title : "") + "  ›"
                }
                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.current ? root.current.icon : ""
                    size: 30 * root.unit
                    color: Theme.accent
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: 30 * root.unit
                    font.bold: true
                    color: Theme.textPrimary
                    text: root.current ? root.current.title : ""
                }
            }
            Text {
                anchors { left: parent.left; leftMargin: 6 * root.unit; right: parent.right; top: crumb.bottom; topMargin: 2 * root.unit }
                font.family: Theme.fontFamily
                font.pixelSize: 17 * root.unit
                color: Theme.textSecondary
                elide: Text.ElideRight
                text: root.current ? root.current.description : ""
            }
        }

        Loader {
            id: pageLoader
            anchors { top: pageHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; topMargin: 6 * root.unit }
            sourceComponent: root.current ? root.current.page : null
            // ジャンルを切り替えたとき、中身がぱっと変わらないよう軽くフェードインする
            onLoaded: fadeIn.restart()
            NumberAnimation { id: fadeIn; target: pageLoader; property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic }
        }
    }
}
