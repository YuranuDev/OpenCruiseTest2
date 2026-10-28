// 選んだ飾りの画像の操作パネル(初期画面の下、ナビバーの場所に重ねて出す。画像を選んでいる間だけ)。
//  濃さ(スライダー)・左右反転・奥/手前・いちばん上へ・複製・削除(2 回押し)・選択の解除
import QtQuick
import OpenCruise

Panel {
    id: root
    property Item store: null
    readonly property string sid: store ? store.selectedId : ""
    readonly property real unit: Theme.uiScale
    readonly property bool compact: width < 1100 * unit

    radius: Theme.radius + 6
    tint: Theme.accent
    tintAmount: 0.05
    border.color: Theme.mix(Theme.panelBorder, Theme.accent, 0.5)

    property bool confirmDelete: false
    property real confirmAt: 0
    onSidChanged: confirmDelete = false
    Timer { id: confirmTimer; interval: 3000; onTriggered: root.confirmDelete = false }

    // ListModel の値は束縛で追えないことがあるので、操作のたびに読み直す
    property int tick: 0
    function cur(key, d) { tick; const it = store ? store.get(sid) : null; return it ? it[key] : d }
    function setv(key, v, save) { store.setValue(sid, key, v, save); tick++ }

    component PanelButton: Rectangle {
        id: b
        property string icon: ""
        property string text: ""
        property bool on: false
        property string tone: "normal"   // "normal" / "danger" / "dangerSolid"
        signal clicked()
        readonly property color toneColor: tone === "normal" ? Theme.accent : Theme.error
        height: Math.round(52 * root.unit)
        width: Math.max(height, bRow.implicitWidth + 26 * root.unit)
        radius: height / 2
        color: tone === "dangerSolid" ? Theme.mix(Theme.error, "#000000", bMouse.pressed ? 0.2 : 0)
             : on ? Theme.mix(Theme.accentFill, "#000000", bMouse.pressed ? 0.2 : 0)
             : Theme.mix(Theme.panel, toneColor, bMouse.pressed ? 0.35 : 0.08)
        border.width: (on || tone === "dangerSolid") ? 0 : 1.5
        border.color: tone === "normal" ? Theme.panelBorder : toneColor
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Row {
            id: bRow
            anchors.centerIn: parent
            spacing: 6 * root.unit
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: b.icon
                size: Math.round(b.height * 0.5)
                color: b.tone === "dangerSolid" ? "#ffffff" : b.on ? Theme.textOnAccent : b.toneColor
            }
            Text {
                visible: b.text !== ""
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.fontFamily
                font.pixelSize: Math.round(b.height * 0.36)
                font.bold: true
                color: b.tone === "dangerSolid" ? "#ffffff" : b.on ? Theme.textOnAccent : Theme.textPrimary
                text: b.text
            }
        }
        MouseArea { id: bMouse; anchors.fill: parent; onClicked: b.clicked() }
    }

    Row {
        id: row
        anchors { left: parent.left; leftMargin: 16 * root.unit; verticalCenter: parent.verticalCenter }
        spacing: 10 * root.unit

        // 濃さ(つまみの中に % を出す。狭い画面でも動かせる幅を残す)
        Item {
            id: opSlider
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(150 * root.unit, root.width - buttons.width - 60 * root.unit)
            height: Math.round(56 * root.unit)
            readonly property int value: Math.round(root.cur("op", 1) * 100)
            readonly property int from: 5
            MaterialIcon {
                id: opIcon
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                name: "opacity"
                size: Math.round(32 * root.unit)
                color: Theme.accent
            }
            Item {
                id: track
                anchors { left: opIcon.right; leftMargin: 8 * root.unit; right: parent.right; verticalCenter: parent.verticalCenter }
                height: parent.height
                readonly property real knob: Math.round(54 * root.unit)
                Rectangle {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    height: 12 * root.unit
                    radius: height / 2
                    color: Theme.panelBorder
                    Rectangle {
                        width: knobRect.x + knobRect.width / 2
                        height: parent.height
                        radius: height / 2
                        color: Theme.accent
                    }
                }
                Rectangle {
                    id: knobRect
                    width: track.knob
                    height: Math.round(40 * root.unit)
                    radius: height / 2
                    anchors.verticalCenter: parent.verticalCenter
                    x: (track.width - width) * (opSlider.value - opSlider.from) / (100 - opSlider.from)
                    color: Theme.panel
                    border.width: opMouse.pressed ? 3 : 2
                    border.color: Theme.accent
                    Text {
                        anchors.centerIn: parent
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(16 * root.unit)
                        font.bold: true
                        color: Theme.textPrimary
                        text: opSlider.value + "%"
                    }
                }
                MouseArea {
                    id: opMouse
                    anchors.fill: parent
                    preventStealing: true
                    function apply(mx) {
                        const t = Math.max(0, Math.min(1, (mx - track.knob / 2) / Math.max(1, track.width - track.knob)))
                        root.setv("op", Math.round(opSlider.from + t * (100 - opSlider.from)) / 100, false)
                    }
                    onPressed: (m) => apply(m.x)
                    onPositionChanged: (m) => { if (pressed) apply(m.x) }
                    onReleased: root.store.save()
                    onCanceled: root.store.save()
                }
            }
        }

        Row {
            id: buttons
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * root.unit
            PanelButton {
                icon: "flip"
                text: root.compact ? "" : "反転"
                on: root.cur("flip", false)
                onClicked: root.setv("flip", !root.cur("flip", false), true)
            }
            // 重ね方(3 つから 1 つ): 奥(ウィジェットの後ろ)/ パネル(パネルの上・中身の下)/ 手前(ウィジェットの前)
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                height: Math.round(52 * root.unit)
                width: seg.implicitWidth + 8 * root.unit
                radius: height / 2
                color: Theme.mix(Theme.panel, Theme.background, 0.5)
                border.width: 1
                border.color: Theme.panelBorder
                Row {
                    id: seg
                    anchors.centerIn: parent
                    spacing: 2 * root.unit
                    Repeater {
                        model: [{ key: "back", icon: "flip_to_back", text: "奥" },
                                { key: "panel", icon: "layers", text: "パネル" },
                                { key: "front", icon: "flip_to_front", text: "手前" }]
                        PanelButton {
                            required property var modelData
                            height: Math.round(44 * root.unit)
                            icon: modelData.icon
                            text: modelData.text   // 狭くても文字は出す(どれを選んでいるか分かるように)
                            on: root.cur("zone", "back") === modelData.key
                            border.width: 0
                            color: on ? Theme.accentFill : "transparent"
                            onClicked: root.setv("zone", modelData.key, true)
                        }
                    }
                }
            }
            PanelButton {
                visible: !root.compact   // 狭いときは省く(重ね方の文字を優先)
                icon: "vertical_align_top"
                text: root.compact ? "" : "いちばん上へ"
                onClicked: { root.store.raise(root.sid); root.tick++ }
            }
            PanelButton {
                icon: "content_copy"
                text: root.compact ? "" : "複製"
                onClicked: root.store.duplicate(root.sid)
            }
            PanelButton {
                icon: "delete"
                tone: root.confirmDelete ? "dangerSolid" : "danger"
                text: root.confirmDelete ? "もう一度押すと削除" : (root.compact ? "" : "削除")
                onClicked: {
                    if (!root.confirmDelete) {
                        root.confirmDelete = true
                        root.confirmAt = Date.now()
                        confirmTimer.restart()
                        return
                    }
                    if (Date.now() - root.confirmAt < 400) return   // 2 度押しの勢いで消さない
                    confirmTimer.stop()
                    root.confirmDelete = false
                    root.store.remove(root.sid)
                }
            }
            PanelButton {
                icon: "close"
                onClicked: root.store.selectedId = ""
            }
        }
    }
}
