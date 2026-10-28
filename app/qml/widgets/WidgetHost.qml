// 配置エリア上の 1 つのウィジェットの入れ物。位置・大きさ(グリッド)、ドラッグ移動、スナップ、
// タップ/ダブルタップの振り分け、表示・消去のアニメーションを受け持つ。ウィジェットの中身は知らない。
//
// ドラッグ: 既定は「長押し(約 0.3 秒)で持ち上げ → そのままドラッグ」。ウィジェット自身が横スワイプなどの
// 操作を持つ場合に衝突しないため。定義(WidgetRegistry)の dragStart を "immediate" にすると、少し動かしただけで
// 持ち上がる。移動中は WidgetArea が配置エリアを表示し、離すと最寄りの空きマスへスナップする。
//
// 編集モード(area.editMode)のとき: 中身の操作は受けず、上に編集用の表示(editLayer)を重ねる。
//  - 名前(左下)と大きさ「3 x 2」(右下)、設定(左上)と削除(右上)の丸いボタン
//  - タップで選択/解除、少し動かすとすぐドラッグ(選択中の 1 つなら、選択中のものをまとめて動かす)
//  - 押し間違えを防ぐため: 2 つのボタンは反対の角に離して置き、ドラッグ中は出さない。
//    削除は 2 回押し(1 回目で赤い「削除」に広がり、0.4〜3 秒の間にもう一度押すと消す。押さなければ元に戻る)
import QtQuick
import OpenCruise

Item {
    id: host

    // ---- 所属先と、モデル(ListModel)の列 ----
    property Item area: null
    required property string wid
    required property string wtype
    required property int col
    required property int row
    required property int w
    required property int h
    required property var config

    readonly property var def: WidgetRegistry.find(wtype)
    // 定義の既定値に保存値を重ねた設定(ウィジェットへ渡す)
    readonly property var cfg: Object.assign({}, def ? def.defaultConfig : {}, config)

    property bool lifting: false
    property bool shown: false
    readonly property bool editing: area.editMode
    readonly property bool selected: { area.selection; return area.isSelected(wid) }
    // まとめて動かしているときの、一緒に動く側(動かしているもの以外)
    readonly property bool following: area.groupDragging && area.dragId !== wid && area.groupIds.indexOf(wid) >= 0
    readonly property var groupOffset: area.groupOffset
    onGroupOffsetChanged: if (following) { snapAnim.stop(); x = tx + groupOffset.x; y = ty + groupOffset.y }
    onFollowingChanged: if (!following) snapTo(true)
    readonly property var item: loader.item

    // ---- 目標位置(グリッド → ピクセル) ----
    // 表示するマス。ドラッグ中に押しのけられている間は、仮の位置(area.tempPos)を使う
    readonly property var temp: area.tempPos[wid]
    readonly property int effCol: temp !== undefined ? temp.col : col
    readonly property int effRow: temp !== undefined ? temp.row : row
    readonly property real tx: area.cellW * effCol + area.pad
    readonly property real ty: area.cellH * effRow + area.pad
    width: area.cellW * w - 2 * area.pad
    height: area.cellH * h - 2 * area.pad
    Behavior on width { enabled: area.animReady; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    Behavior on height { enabled: area.animReady; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

    // 持ち上げ中・戻り中は他のウィジェットより手前に出す
    z: (lifting || following || snapAnim.running) ? 100 : 1

    // x / y は束縛せず、snapTo() で動かす(ドラッグ中は指に追従、離したらアニメーションでスナップ)
    function snapTo(animated) {
        if (animated && area.animReady) {
            snapAnim.restart()
        } else {
            snapAnim.stop()
            x = tx
            y = ty
        }
    }
    onTxChanged: if (!lifting && !following) snapTo(true)
    onTyChanged: if (!lifting && !following) snapTo(true)
    Component.onCompleted: { snapTo(false); shown = true }

    ParallelAnimation {
        id: snapAnim
        NumberAnimation { target: host; property: "x"; to: host.tx; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
        NumberAnimation { target: host; property: "y"; to: host.ty; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
    }

    // ---- 持ち上げ・移動・離す ----
    function beginLift() {
        if (lifting) return
        snapAnim.stop()
        lifting = true
        area.dragBegin(wid)
    }
    function dragMove(nx, ny) {
        const p = area.clampDrag(wid, nx, ny, width, height)
        x = p.x
        y = p.y
        area.dragUpdate(wid, x, y)
    }
    function endLift() {
        if (!lifting) return
        lifting = false
        area.dragEnd(wid)   // 確定した位置(col/row)がモデルに入る
        snapTo(true)        // 位置が変わらなかった場合も、元のマスへ滑らかに戻す
    }

    // ---- 消去(フェードアウトしてからモデルから外す) ----
    function playRemove() {
        shown = false
        removeTimer.start()
    }
    Timer { id: removeTimer; interval: 220; onTriggered: host.area.finishRemove(host.wid) }

    // ---- 見た目(持ち上げ・表示/消去で拡大縮小・透明度) ----
    Item {
        id: body
        anchors.fill: parent
        scale: host.lifting || host.following ? 1.04 : (host.shown ? 1.0 : 0.9)
        opacity: host.shown ? (host.lifting || host.following ? 0.94 : 1.0) : 0.0
        Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        // 背景側の操作(ドラッグ・タップ・ダブルタップ)。ウィジェットの中身より奥に置き、中身の MouseArea を優先する
        MouseArea {
            id: ma
            anchors.fill: parent
            enabled: !host.editing   // 編集モードでは editLayer が受ける
            pressAndHoldInterval: 300
            preventStealing: host.lifting
            property real lastX: 0
            property real lastY: 0
            property real grabX: 0
            property real grabY: 0
            property real pressX: 0
            property real pressY: 0

            function follow() {
                const p = ma.mapToItem(host.area, lastX, lastY)
                host.dragMove(p.x - grabX, p.y - grabY)
            }

            onPressed: (mouse) => { lastX = pressX = mouse.x; lastY = pressY = mouse.y }
            onPressAndHold: {
                if (host.def && host.def.dragStart === "hold") {
                    grabX = lastX; grabY = lastY
                    host.beginLift()
                }
            }
            onPositionChanged: (mouse) => {
                lastX = mouse.x; lastY = mouse.y
                if (!host.lifting && host.def && host.def.dragStart === "immediate"
                        && Math.hypot(mouse.x - pressX, mouse.y - pressY) > 14) {
                    grabX = pressX; grabY = pressY
                    host.beginLift()
                }
                if (host.lifting) follow()
            }
            onReleased: host.endLift()
            onCanceled: host.endLift()
            onClicked: if (loader.item) loader.item.tapped()
            onDoubleClicked: {
                const action = loader.item ? loader.item.doubleTapAction : "settings"
                if (action === "settings") {
                    if (host.def && host.def.settings) host.area.settingsRequested(host.wid)
                } else if (action === "custom" && loader.item) {
                    loader.item.doubleTapped()
                }
            }
        }

        // ウィジェット本体は少しずつ作る(非同期)。たくさん並んでいても、作っている間に画面が止まらない
        Loader {
            id: loader
            anchors.fill: parent
            asynchronous: true
            sourceComponent: host.def ? host.def.component : null
            // 作っている途中の数を WidgetRegistry に知らせる(起動画面に「ウィジェット n / m」と出す)
            property bool counted: false
            function count() {
                const loading = status === Loader.Loading
                if (loading && !counted) { counted = true; ++WidgetRegistry.widgetsLoading }
                else if (!loading && counted) {
                    counted = false
                    --WidgetRegistry.widgetsLoading
                    if (status === Loader.Ready) ++WidgetRegistry.widgetsLoaded
                }
            }
            onStatusChanged: count()
            Component.onCompleted: count()
            Component.onDestruction: if (counted) { counted = false; --WidgetRegistry.widgetsLoading }
        }
        Binding { target: loader.item; property: "config"; value: host.cfg; when: loader.item !== null }
        Binding { target: loader.item; property: "lifting"; value: host.lifting; when: loader.item !== null }
        Binding { target: loader.item; property: "gridW"; value: host.w; when: loader.item !== null }
        Binding { target: loader.item; property: "gridH"; value: host.h; when: loader.item !== null }
        Binding { target: loader.item; property: "widgetId"; value: host.wid; when: loader.item !== null }
        // 飾りの画像(重ね方「パネル」): 今のページのものだけ、画面上の位置とあわせて渡す
        Binding {
            target: loader.item; property: "decorStore"; when: loader.item !== null
            value: host.area.decorSource && host.area.decorSource.pageIndex === host.area.pageIndex ? host.area.decorSource : null
        }
        Binding {
            target: loader.item; property: "decorOrigin"; when: loader.item !== null && host.area.decorSource !== null
            value: Qt.point(host.area.decorOx + host.x, host.area.decorOy + host.y)
        }
        Binding { target: loader.item; property: "decorRootW"; value: host.area.decorSource ? host.area.decorSource.areaW : 1; when: loader.item !== null }
        Binding { target: loader.item; property: "decorRootH"; value: host.area.decorSource ? host.area.decorSource.areaH : 1; when: loader.item !== null }

        // 持ち上げ中の縁取り
        Rectangle {
            anchors.fill: parent
            radius: Theme.radius + 6
            color: "transparent"
            border.width: 2
            border.color: Theme.accent
            opacity: host.lifting && !host.editing ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }

        // ---- 編集モードの表示と操作 ----
        Item {
            id: editLayer
            anchors.fill: parent
            opacity: host.editing ? 1 : 0
            visible: opacity > 0
            enabled: host.editing
            Behavior on opacity { NumberAnimation { duration: 180 } }

            readonly property real u: Theme.uiScale
            // 丸いボタンの大きさ(小さいウィジェットでも、名前・大きさの表示と重ならない範囲で、押しやすい大きさ)
            readonly property real btn: Math.max(28, 30 * u, Math.min(46 * u, Math.min(width * 0.3, height * 0.36)))
            readonly property real inset: Math.max(4, 6 * u)
            readonly property real labelH: Math.max(16, Math.min(24 * u, height * 0.22))
            // 低いウィジェット(1 マスの高さなど)では、名前・大きさを出さずにボタンだけにする(重ならないように)
            readonly property bool roomForLabels: height >= btn + labelH + 3 * inset
            // 削除の確認中(1 回目を押した後)
            property bool confirmDelete: false
            property real confirmAt: 0   // 1 回目を押した時刻。続けて素早く 2 回押しても消さない(0.4 秒あける)
            onVisibleChanged: confirmDelete = false
            Timer { id: confirmTimer; interval: 3000; onTriggered: editLayer.confirmDelete = false }

            // 中身を少し暗くして、編集中であることと選択の有無を示す
            Rectangle {
                anchors.fill: parent
                radius: Theme.radius + 6
                color: host.selected ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                                     : Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.35)
                border.width: host.selected ? 3 : 1.5
                border.color: host.selected ? Theme.accent : Theme.mix(Theme.panelBorder, Theme.textSecondary, 0.5)
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            // タップで選択、ドラッグで移動(長押しは要らない)
            MouseArea {
                id: editMouse
                anchors.fill: parent
                preventStealing: host.lifting
                property real pressX: 0
                property real pressY: 0
                property real grabX: 0
                property real grabY: 0
                property bool moved: false
                onPressed: (mouse) => { pressX = mouse.x; pressY = mouse.y; moved = false; editLayer.confirmDelete = false }
                onPositionChanged: (mouse) => {
                    if (!host.lifting && Math.hypot(mouse.x - pressX, mouse.y - pressY) > 10 * editLayer.u) {
                        moved = true
                        grabX = pressX; grabY = pressY
                        host.beginLift()
                    }
                    if (host.lifting) {
                        const p = editMouse.mapToItem(host.area, mouse.x, mouse.y)
                        host.dragMove(p.x - grabX, p.y - grabY)
                    }
                }
                onReleased: host.endLift()
                onCanceled: host.endLift()
                onClicked: if (!moved) host.area.toggleSelect(host.wid)
            }

            // 名前(左下)
            Rectangle {
                id: nameTag
                visible: editLayer.roomForLabels
                anchors { left: parent.left; bottom: parent.bottom; margins: editLayer.inset }
                height: editLayer.labelH
                width: Math.min(nameRow.implicitWidth + height * 0.7, parent.width - sizeTag.width - 3 * editLayer.inset)
                radius: height / 2
                color: host.selected ? Theme.accent : Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.92)
                border.color: host.selected ? Theme.accent : Theme.panelBorder
                clip: true
                Row {
                    id: nameRow
                    anchors { left: parent.left; leftMargin: parent.height * 0.35; verticalCenter: parent.verticalCenter }
                    spacing: 3
                    MaterialIcon {
                        visible: host.selected
                        anchors.verticalCenter: parent.verticalCenter
                        name: "check"
                        size: Math.round(nameTag.height * 0.75)
                        color: Theme.textOnAccent
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(nameTag.height * 0.62)
                        font.bold: true
                        color: host.selected ? Theme.textOnAccent : Theme.textPrimary
                        text: String(host.cfg.titleText || "").trim() !== "" ? host.cfg.titleText : (host.def ? host.def.name : "")
                    }
                }
            }
            // 大きさ(右下)「3 x 2」
            Rectangle {
                id: sizeTag
                visible: editLayer.roomForLabels
                anchors { right: parent.right; bottom: parent.bottom; margins: editLayer.inset }
                height: editLayer.labelH
                width: sizeText.implicitWidth + height * 0.7
                radius: height / 2
                color: Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.92)
                border.color: Theme.panelBorder
                Text {
                    id: sizeText
                    anchors.centerIn: parent
                    font.family: Theme.numberFontFamily
                    font.pixelSize: Math.round(sizeTag.height * 0.62)
                    font.bold: true
                    color: Theme.textPrimary
                    text: host.w + " x " + host.h
                }
            }

            // 設定(左上)。設定画面の無いウィジェットには出さない
            Rectangle {
                id: settingsBtn
                visible: host.def && host.def.settings && !host.lifting && !host.area.dragging
                anchors { left: parent.left; top: parent.top; margins: editLayer.inset }
                width: editLayer.btn
                height: width
                radius: width / 2
                color: Theme.mix(Theme.panel, Theme.accent, settingsMouse.pressed ? 0.45 : 0.12)
                border.width: 2
                border.color: Theme.accent
                scale: settingsMouse.pressed ? 0.92 : 1
                MaterialIcon {
                    anchors.centerIn: parent
                    name: "settings"
                    size: Math.round(parent.width * 0.58)
                    color: Theme.accent
                }
                MouseArea {
                    id: settingsMouse
                    anchors.fill: parent
                    onClicked: { editLayer.confirmDelete = false; host.area.settingsRequested(host.wid) }
                }
            }

            // 削除(右上)。2 回押しで消す(1 回目は赤い「削除」に広がる)
            Rectangle {
                id: deleteBtn
                visible: !host.lifting && !host.area.dragging
                anchors { right: parent.right; top: parent.top; margins: editLayer.inset }
                height: editLayer.btn
                width: editLayer.confirmDelete ? Math.min(parent.width - 2 * editLayer.inset, deleteRow.implicitWidth + height * 0.8) : height
                radius: height / 2
                color: editLayer.confirmDelete ? Theme.error : Theme.mix(Theme.panel, Theme.error, deleteMouse.pressed ? 0.45 : 0.12)
                border.width: 2
                border.color: Theme.error
                scale: deleteMouse.pressed ? 0.92 : 1
                Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                clip: true
                Row {
                    id: deleteRow
                    anchors.centerIn: parent
                    spacing: 2
                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: editLayer.confirmDelete ? "delete" : "close"
                        size: Math.round(deleteBtn.height * 0.58)
                        color: editLayer.confirmDelete ? "#ffffff" : Theme.error
                    }
                    Text {
                        visible: editLayer.confirmDelete
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(deleteBtn.height * 0.42)
                        font.bold: true
                        color: "#ffffff"
                        text: "削除"
                    }
                }
                MouseArea {
                    id: deleteMouse
                    anchors.fill: parent
                    onClicked: {
                        if (editLayer.confirmDelete) {
                            if (Date.now() - editLayer.confirmAt < 400) return   // 2 度押しの勢いで消さない
                            confirmTimer.stop()
                            editLayer.confirmDelete = false
                            host.area.removeWidget(host.wid)
                        } else {
                            editLayer.confirmDelete = true
                            editLayer.confirmAt = Date.now()
                            confirmTimer.restart()
                        }
                    }
                }
            }
        }
    }
}
