/**
 * @file SystemStats.h
 * @brief 本機(車載 PC)の CPU / GPU / メモリの使用状況を集めて QML へ公開するクラス。
 *
 * Linux 専用(/proc と /sys、NVIDIA は NVML を実行時に読み込む)。値が取れない項目は kUnavailable(-1)になり、
 * QML 側は「--」と表示する。ドライバや機種によって取れる項目が違うため、取れないこと自体は異常ではない。
 *
 * 対応状況:
 *  - CPU  : 使用率(/proc/stat) / 周波数(cpufreq、無ければ /proc/cpuinfo) / 温度(coretemp, k10temp など)
 *  - メモリ: 使用率・使用量・総量(/proc/meminfo の MemAvailable 基準)
 *  - GPU  : NVIDIA(NVML) / AMD(amdgpu) / Intel(i915, xe)。Intel の使用率はアイドル(RC6)時間から求めた近似値
 */
#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>

class QLibrary;

namespace opencruise {

class SystemStats : public QObject {
    Q_OBJECT
    /** 値が取れない項目は -1。使用率は 0〜100、周波数は MHz、温度は ℃、メモリは MB。 */
    Q_PROPERTY(int cpuPercent READ cpuPercent NOTIFY changed)
    Q_PROPERTY(int cpuFreqMHz READ cpuFreqMHz NOTIFY changed)
    Q_PROPERTY(int cpuTempC READ cpuTempC NOTIFY changed)
    Q_PROPERTY(int gpuPercent READ gpuPercent NOTIFY changed)
    Q_PROPERTY(int gpuFreqMHz READ gpuFreqMHz NOTIFY changed)
    Q_PROPERTY(int gpuTempC READ gpuTempC NOTIFY changed)
    Q_PROPERTY(int memPercent READ memPercent NOTIFY changed)
    Q_PROPERTY(int memUsedMB READ memUsedMB NOTIFY changed)
    Q_PROPERTY(int memTotalMB READ memTotalMB NOTIFY changed)
    /** CPU の型番(例: "Intel(R) N100")。取れなければ空。 */
    Q_PROPERTY(QString cpuName READ cpuName CONSTANT)
    /** GPU の名前と、値の取得元(例: "NVML" / "amdgpu" / "i915")。GPU が見つからなければ空。 */
    Q_PROPERTY(QString gpuName READ gpuName CONSTANT)
    Q_PROPERTY(QString gpuSource READ gpuSource CONSTANT)
    /** フルスクリーン時のメニューに、この情報を表示するか(設定として保存される)。 */
    Q_PROPERTY(bool showInMenu READ showInMenu WRITE setShowInMenu NOTIFY showInMenuChanged)

public:
    static constexpr int kUnavailable = -1;

    explicit SystemStats(QObject *parent = nullptr);
    ~SystemStats() override;

    int cpuPercent() const { return v_.cpuPercent; }
    int cpuFreqMHz() const { return v_.cpuFreqMHz; }
    int cpuTempC() const { return v_.cpuTempC; }
    int gpuPercent() const { return v_.gpuPercent; }
    int gpuFreqMHz() const { return v_.gpuFreqMHz; }
    int gpuTempC() const { return v_.gpuTempC; }
    int memPercent() const { return v_.memPercent; }
    int memUsedMB() const { return v_.memUsedMB; }
    int memTotalMB() const { return v_.memTotalMB; }
    QString cpuName() const { return cpuName_; }
    QString gpuName() const { return gpuName_; }
    QString gpuSource() const { return gpuSource_; }
    bool showInMenu() const { return showInMenu_; }
    void setShowInMenu(bool enabled);

signals:
    /** @brief いずれかの値が変わったとき(1 秒ごとに確認し、変化があったときだけ通知する)。 */
    void changed();
    void showInMenuChanged();

private:
    struct Values {
        int cpuPercent = kUnavailable;
        int cpuFreqMHz = kUnavailable;
        int cpuTempC = kUnavailable;
        int gpuPercent = kUnavailable;
        int gpuFreqMHz = kUnavailable;
        int gpuTempC = kUnavailable;
        int memPercent = kUnavailable;
        int memUsedMB = kUnavailable;
        int memTotalMB = kUnavailable;
        bool operator==(const Values &o) const {
            return cpuPercent == o.cpuPercent && cpuFreqMHz == o.cpuFreqMHz && cpuTempC == o.cpuTempC &&
                   gpuPercent == o.gpuPercent && gpuFreqMHz == o.gpuFreqMHz && gpuTempC == o.gpuTempC &&
                   memPercent == o.memPercent && memUsedMB == o.memUsedMB && memTotalMB == o.memTotalMB;
        }
        bool operator!=(const Values &o) const { return !(*this == o); }
    };

    void update();

    // ---- CPU / メモリ ----
    int readCpuPercent();
    int readCpuFreqMHz() const;
    int readCpuTempC() const;
    void readMemory(Values &v) const;
    void detectCpu();

    // ---- GPU ----
    void detectGpu();
    bool detectNvml();
    bool detectDrm();
    void readGpu(Values &v);

    QTimer timer_;
    Values v_;
    bool showInMenu_ = true;

    // CPU
    QString cpuName_;
    QStringList cpuFreqPaths_; ///< scaling_cur_freq の一覧(コアごと)
    QString cpuTempPath_;      ///< 温度(ミリ℃)を返すファイル
    qulonglong prevCpuTotal_ = 0;
    qulonglong prevCpuIdle_ = 0;
    bool haveCpuBaseline_ = false;

    // GPU 共通
    enum class GpuKind { None, Nvml, Amd, Intel };
    GpuKind gpuKind_ = GpuKind::None;
    QString gpuName_;
    QString gpuSource_;
    // GPU: sysfs(AMD / Intel)
    QString gpuBusyPath_;  ///< 使用率(%)を返すファイル(AMD)
    QString gpuFreqPath_;  ///< 周波数を返すファイル
    double gpuFreqScale_ = 1.0; ///< ファイルの値 × これ = MHz
    QString gpuPpDpmPath_; ///< AMD の pp_dpm_sclk(周波数が他に無いとき)
    QString gpuTempPath_;  ///< 温度(ミリ℃)
    QString gpuIdlePath_;  ///< Intel: アイドル(RC6)の累積時間 [ms]
    qlonglong prevIdleMs_ = -1;
    QElapsedTimer idleClock_;

    // GPU: NVML(libnvidia-ml を実行時に読み込む。無い環境でもビルド・起動できる)
    QLibrary *nvmlLib_ = nullptr;
    void *nvmlDevice_ = nullptr;
    using FnDeviceUtil = int (*)(void *, void *);
    using FnDeviceClock = int (*)(void *, int, unsigned int *);
    using FnDeviceTemp = int (*)(void *, int, unsigned int *);
    FnDeviceUtil nvmlUtil_ = nullptr;
    FnDeviceClock nvmlClock_ = nullptr;
    FnDeviceTemp nvmlTemp_ = nullptr;
    int (*nvmlShutdown_)() = nullptr;
};

} // namespace opencruise
