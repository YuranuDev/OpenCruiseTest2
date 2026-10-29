// ナビ案内ウィジェットの設定(枠は全ウィジェット共通): レイアウト・距離の単位・道路名・「その次」・接近の強調・モック表示(表示テスト)。
import QtQuick
import OpenCruise

WidgetSettingsBase {
    id: root

    SettingsRow {
        label: "レイアウト"
        description: "コンパクトは「その次」を出さず、主案内だけを大きく表示します"
        SettingsChoice {
            model: ["標準", "コンパクト"]
            currentIndex: root.config.layout === "compact" ? 1 : 0
            onPicked: (i) => root.edit("layout", i === 1 ? "compact" : "standard")
        }
    }
    SettingsRow {
        label: "距離の単位"
        description: "自動は 1 km 未満を m、以上を km で表示します(単位は必ず付きます)"
        SettingsChoice {
            model: ["自動", "m", "km"]
            currentIndex: root.config.distanceUnit === "km" ? 2 : (root.config.distanceUnit === "m" ? 1 : 0)
            onPicked: (i) => root.edit("distanceUnit", i === 2 ? "km" : (i === 1 ? "m" : "auto"))
        }
    }
    SettingsRow {
        label: "道路名を表示"
        description: "オフ、または道路名が無いときは「右折」などの方向名を表示します"
        SettingsSwitch {
            checked: root.config.showRoad !== false
            onToggled: (v) => root.edit("showRoad", v)
        }
    }
    SettingsRow {
        visible: root.config.layout !== "compact"
        label: "「その次」の案内を表示"
        SettingsSwitch {
            checked: root.config.showNext !== false
            onToggled: (v) => root.edit("showNext", v)
        }
    }
    SettingsRow {
        label: "接近の強調"
        description: "この距離以内になると、距離と矢印を警告色にし、残り距離のバーを出します(0 でオフ)"
        WSStepper {
            value: root.config.nearHighlight === undefined ? 100 : root.config.nearHighlight
            from: 0
            to: 500
            step: 50
            suffix: " m"
            onMoved: (v) => root.edit("nearHighlight", v)
        }
    }
    SettingsRow {
        label: "モック表示(テスト)"
        description: "仮の案内を表示して、見た目を確かめます。Android Auto のナビが動いている間は、実際の案内を優先します"
        SettingsSwitch {
            checked: root.config.mockEnabled === true
            onToggled: (v) => root.edit("mockEnabled", v)
        }
    }
    SettingsRow {
        visible: root.config.mockEnabled === true
        label: "モックの内容"
        description: "右折(道路名あり)/ 出口(長い距離・km 表示)/ ロータリー(道路名なし)/ 目的地(「その次」なし)"
        SettingsChoice {
            model: ["右折", "出口", "ロータリー", "目的地"]
            currentIndex: root.config.mockScenario === undefined ? 0 : root.config.mockScenario
            onPicked: (i) => root.edit("mockScenario", i)
        }
    }
    SettingsRow {
        visible: root.config.mockEnabled === true
        label: "距離を自動で縮める"
        description: "オンで、距離が減って 0 になると最初から繰り返します(接近の強調も確認できます)。オフで、下の距離に固定します"
        SettingsSwitch {
            checked: root.config.mockAuto !== false
            onToggled: (v) => root.edit("mockAuto", v)
        }
    }
    SettingsRow {
        visible: root.config.mockEnabled === true && root.config.mockAuto === false
        label: "固定する距離"
        WSStepper {
            value: root.config.mockDistance === undefined ? 300 : root.config.mockDistance
            from: 0
            to: 5000
            step: 50
            suffix: " m"
            onMoved: (v) => root.edit("mockDistance", v)
        }
    }
    SettingsNote {
        text: "「その次」は Android Auto が送る 2 件目のステップ(方向・道路名)です。2 件目までの距離はプロトコルから提供されないため表示しません。"
    }
}
