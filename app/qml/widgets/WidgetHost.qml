// 配置エリア上の 1 つのウィジェットの入れ物。位置・大きさ(グリッド)、ドラッグ移動、スナップ、
// タップ/ダブルタップの振り分け、表示・消去のアニメーションを受け持つ。ウィジェットの中身は知らない。
//
// ドラッグ: 既定は「長押し(約 0.3 秒)で持ち上げ → そのままドラッグ」。ウィジェット自身が横スワイプなどの
// 操作を持つ場合に衝突しないため。定義(WidgetRegistry)の dragStart を "immediate" にすると、少し動かしただけで
// 持ち上がる。移動中は WidgetArea が配置エリアを表示し、離すと最寄りの空きマスへスナップする。
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
    readonly property var item: loader.item

    // ---- 目標位置(グリッド → ピクセル) ----
    readonly property real tx: area.cellW * col + area.pad
    readonly property real ty: area.cellH * row + area.pad
    width: area.cellW * w - 2 * area.pad
    height: area.cellH * h - 2 * area.pad
    Behavior on width { enabled: area.animReady; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    Behavior on height { enabled: area.animReady; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

    // 持ち上げ中・戻り中は他のウィジェットより手前に出す
    z: (lifting || snapAnim.running) ? 100 : 1

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
    onTxChanged: if (!lifting) snapTo(true)
    onTyChanged: if (!lifting) snapTo(true)
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
        x = Math.max(0, Math.min(area.width - width, nx))
        y = Math.max(0, Math.min(area.height - height, ny))
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
        scale: host.lifting ? 1.04 : (host.shown ? 1.0 : 0.9)
        opacity: host.shown ? (host.lifting ? 0.94 : 1.0) : 0.0
        Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        // 背景側の操作(ドラッグ・タップ・ダブルタップ)。ウィジェットの中身より奥に置き、中身の MouseArea を優先する
        MouseArea {
            id: ma
            anchors.fill: parent
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

        Loader {
            id: loader
            anchors.fill: parent
            sourceComponent: host.def ? host.def.component : null
        }
        Binding { target: loader.item; property: "config"; value: host.cfg; when: loader.item !== null }
        Binding { target: loader.item; property: "lifting"; value: host.lifting; when: loader.item !== null }
        Binding { target: loader.item; property: "gridW"; value: host.w; when: loader.item !== null }
        Binding { target: loader.item; property: "gridH"; value: host.h; when: loader.item !== null }

        // 持ち上げ中の縁取り
        Rectangle {
            anchors.fill: parent
            radius: Theme.radius + 6
            color: "transparent"
            border.width: 2
            border.color: Theme.accent
            opacity: host.lifting ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }
    }
}
