// ナビ案内ウィジェットの設定: 枠・レイアウト・距離の単位・道路名・「その次」・接近の強調。
import QtQuick
import OpenCruise

WidgetSettingsBase {
    id: root

    SettingsRow {
        label: "枠"
        description: "「なし」にすると背景のカードを描きません"
        SettingsChoice {
            model: ["カード", "なし"]
            currentIndex: root.config.frame === "plain" ? 1 : 0
            onPicked: (i) => root.edit("frame", i === 1 ? "plain" : "card")
        }
    }
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
        description: "この距離以内になると、距離と矢印を警告色にします(0 でオフ)"
        WSStepper {
            value: root.config.nearHighlight === undefined ? 100 : root.config.nearHighlight
            from: 0
            to: 500
            step: 50
            suffix: " m"
            onMoved: (v) => root.edit("nearHighlight", v)
        }
    }
    SettingsNote {
        text: "「その次」は Android Auto が送る 2 件目のステップ(方向・道路名)です。2 件目までの距離はプロトコルから提供されないため表示しません。"
    }
}
