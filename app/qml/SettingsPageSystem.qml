// 設定ジャンル「システム」: CPU / GPU / メモリの使用状況の表示設定と、現在の値(1 秒ごとに更新)。
import QtQuick

SettingsPage {
    // 値の文字列(取れない項目は「--」)
    function num(value, unit) { return value < 0 ? "--" : value + " " + unit }
    function freq(mhz) {
        if (mhz < 0) return "--"
        return mhz >= 1000 ? (mhz / 1000).toFixed(2) + " GHz" : mhz + " MHz"
    }
    function gb(mb) { return (mb / 1024).toFixed(1) }

    SettingsSection {
        title: "表示"
        icon: "monitor_heart"

        SettingsRow {
            label: "メニューに表示"
            description: "フルスクリーン時の下メニューに、CPU・GPU・メモリの使用状況を表示します"

            SettingsSwitch {
                checked: systemStats.showInMenu
                onToggled: (value) => systemStats.showInMenu = value
            }
        }
    }

    SettingsSection {
        title: "CPU"
        icon: "memory"

        SettingsInfoRow { label: "型番"; value: systemStats.cpuName !== "" ? systemStats.cpuName : "--" }
        SettingsInfoRow { label: "使用率"; value: num(systemStats.cpuPercent, "%") }
        SettingsInfoRow { label: "周波数(平均)"; value: freq(systemStats.cpuFreqMHz) }
        SettingsInfoRow { label: "温度"; value: num(systemStats.cpuTempC, "℃") }
    }

    SettingsSection {
        title: "GPU"
        icon: "developer_board"

        SettingsInfoRow {
            label: "GPU"
            value: systemStats.gpuSource !== "" ? systemStats.gpuName + "(" + systemStats.gpuSource + ")" : "検出できません"
            valueColor: systemStats.gpuSource !== "" ? Theme.textPrimary : Theme.warn
        }
        SettingsInfoRow { label: "使用率"; value: num(systemStats.gpuPercent, "%") }
        SettingsInfoRow { label: "周波数"; value: freq(systemStats.gpuFreqMHz) }
        SettingsInfoRow { label: "温度"; value: num(systemStats.gpuTempC, "℃") }

        SettingsNote {
            text: "対応: NVIDIA(NVML) / AMD(amdgpu) / Intel(i915・xe)。Intel の使用率はアイドル時間から求めた近似値です。"
                  + "ドライバや機種によって取得できない項目は「--」になります。"
        }
    }

    SettingsSection {
        title: "メモリ"
        icon: "storage"

        SettingsInfoRow { label: "使用率"; value: num(systemStats.memPercent, "%") }
        SettingsInfoRow {
            label: "使用量 / 総量"
            value: systemStats.memTotalMB > 0 ? gb(systemStats.memUsedMB) + " / " + gb(systemStats.memTotalMB) + " GB" : "--"
        }

        SettingsNote { text: "使用量は、キャッシュとして使われている分を除いた値(MemAvailable 基準)です。" }
    }
}
