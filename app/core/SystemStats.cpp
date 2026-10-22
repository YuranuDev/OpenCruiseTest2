/**
 * @file SystemStats.cpp
 * @brief SystemStats の実装。1 秒ごとに /proc・/sys・NVML から値を読む。
 */
#include "SystemStats.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLibrary>
#include <QRegularExpression>
#include <QSettings>

#include <algorithm>
#include <cmath>

#include "Log.h"

namespace opencruise {

namespace {

constexpr int kNA = SystemStats::kUnavailable;

/** @brief ファイルの全体を読んで前後の空白を取る。読めなければ空。(/proc・/sys はサイズ 0 と報告されるので readAll を使う) */
QByteArray readText(const QString &path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    return file.readAll().trimmed();
}

/** @brief 整数 1 個だけが書かれたファイルを読む。 */
bool readLongLong(const QString &path, qlonglong *out) {
    const QByteArray text = readText(path);
    if (text.isEmpty()) {
        return false;
    }
    bool ok = false;
    const qlonglong value = text.toLongLong(&ok);
    if (ok) {
        *out = value;
    }
    return ok;
}

/** @brief 温度ファイル(ミリ℃)を ℃ の整数にする。範囲外・読めない場合は kNA。 */
int readTempC(const QString &path) {
    qlonglong milli = 0;
    if (path.isEmpty() || !readLongLong(path, &milli)) {
        return kNA;
    }
    const int celsius = static_cast<int>(std::lround(milli / 1000.0));
    return (celsius > 0 && celsius < 150) ? celsius : kNA; // 0 や異常値はセンサー未接続とみなす
}

/** @brief dir 直下で、パターンに合う子ディレクトリ名の一覧(名前順)。シンボリックリンクも含む。 */
QStringList listDirs(const QString &dir, const QString &pattern) {
    return QDir(dir).entryList(QStringList{pattern}, QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
}

/** @brief hwmon ディレクトリ内で、使う温度入力ファイルを選ぶ。ラベルが prefer で始まるものを優先し、無ければ temp1_input。 */
QString pickTempInput(const QString &hwmonDir, const QStringList &preferLabels) {
    for (const QString &label : preferLabels) {
        for (int i = 1; i <= 16; ++i) {
            const QString labelFile = QStringLiteral("%1/temp%2_label").arg(hwmonDir).arg(i);
            if (readText(labelFile).startsWith(label.toUtf8())) {
                return QStringLiteral("%1/temp%2_input").arg(hwmonDir).arg(i);
            }
        }
    }
    const QString first = hwmonDir + QStringLiteral("/temp1_input");
    return QFile::exists(first) ? first : QString();
}

/** @brief /sys/class/hwmon から、名前が names のいずれかの温度入力ファイルを探す。 */
QString findHwmonTemp(const QStringList &names, const QStringList &preferLabels) {
    const QString root = QStringLiteral("/sys/class/hwmon");
    for (const QString &name : names) {
        for (const QString &entry : listDirs(root, QStringLiteral("hwmon*"))) {
            const QString dir = root + QLatin1Char('/') + entry;
            if (readText(dir + QStringLiteral("/name")) == name.toUtf8()) {
                const QString path = pickTempInput(dir, preferLabels);
                if (!path.isEmpty()) {
                    return path;
                }
            }
        }
    }
    return {};
}

/** @brief デバイスの hwmon ディレクトリ(device/hwmon/hwmonN)を探す。 */
QString deviceHwmonDir(const QString &deviceDir) {
    const QStringList entries = listDirs(deviceDir + QStringLiteral("/hwmon"), QStringLiteral("hwmon*"));
    return entries.isEmpty() ? QString() : deviceDir + QStringLiteral("/hwmon/") + entries.first();
}

/** @brief 最初に存在するパスを返す。無ければ空。 */
QString firstExisting(const QStringList &paths) {
    for (const QString &p : paths) {
        if (QFile::exists(p)) {
            return p;
        }
    }
    return {};
}

} // namespace

/**
 * @brief 保存済みの設定を読み、対応する機器を探して、1 秒周期の更新を始める。
 */
SystemStats::SystemStats(QObject *parent) : QObject(parent) {
    {
        QSettings store(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"),
                        QStringLiteral("OpenCruise"));
        showInMenu_ = store.value(QStringLiteral("ui/showSystemStats"), true).toBool();
    }

    detectCpu();
    detectGpu();
    log::info("SYS", QStringLiteral("システム情報: CPU=%1 / 周波数=%2 / 温度=%3 / GPU=%4")
                         .arg(cpuName_.isEmpty() ? QStringLiteral("不明") : cpuName_)
                         .arg(!cpuFreqPaths_.isEmpty() ? QStringLiteral("cpufreq") : QStringLiteral("cpuinfo"))
                         .arg(cpuTempPath_.isEmpty() ? QStringLiteral("取得不可") : cpuTempPath_)
                         .arg(gpuSource_.isEmpty() ? QStringLiteral("未検出")
                                                   : gpuName_ + QStringLiteral(" (") + gpuSource_ + QLatin1Char(')')));

    timer_.setInterval(1000);
    connect(&timer_, &QTimer::timeout, this, &SystemStats::update);
    update(); // CPU 使用率は 2 回目の更新から出る(1 回目は基準値の取得だけ)
    timer_.start();
}

SystemStats::~SystemStats() {
    if (nvmlShutdown_ != nullptr) {
        nvmlShutdown_();
    }
    delete nvmlLib_;
}

void SystemStats::setShowInMenu(bool enabled) {
    if (enabled == showInMenu_) {
        return;
    }
    showInMenu_ = enabled;
    QSettings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"), QStringLiteral("OpenCruise"))
        .setValue(QStringLiteral("ui/showSystemStats"), enabled);
    emit showInMenuChanged();
}

/**
 * @brief 全項目を読み直し、前回と変わっていれば changed を通知する。
 */
void SystemStats::update() {
    Values v;
    v.cpuPercent = readCpuPercent();
    v.cpuFreqMHz = readCpuFreqMHz();
    v.cpuTempC = readCpuTempC();
    readMemory(v);
    readGpu(v);
    if (v != v_) {
        v_ = v;
        emit changed();
    }
}

// =====================================================================================================
// CPU
// =====================================================================================================

/**
 * @brief CPU の型番と、周波数・温度を読むファイルを探す。
 */
void SystemStats::detectCpu() {
    const QByteArray info = readText(QStringLiteral("/proc/cpuinfo"));
    for (const QByteArray &line : info.split('\n')) {
        if (line.startsWith("model name")) {
            cpuName_ = QString::fromUtf8(line.mid(line.indexOf(':') + 1)).simplified();
            break;
        }
    }

    const QString cpuRoot = QStringLiteral("/sys/devices/system/cpu");
    for (const QString &entry : listDirs(cpuRoot, QStringLiteral("cpu[0-9]*"))) {
        const QString path = cpuRoot + QLatin1Char('/') + entry + QStringLiteral("/cpufreq/scaling_cur_freq");
        if (QFile::exists(path)) {
            cpuFreqPaths_ << path;
        }
    }

    // 温度: Intel=coretemp(Package) / AMD=k10temp(Tctl, Tdie) / ARM 系=cpu_thermal など。無ければ thermal_zone を見る
    cpuTempPath_ = findHwmonTemp({QStringLiteral("coretemp")}, {QStringLiteral("Package")});
    if (cpuTempPath_.isEmpty()) {
        cpuTempPath_ = findHwmonTemp({QStringLiteral("k10temp"), QStringLiteral("zenpower")},
                                     {QStringLiteral("Tdie"), QStringLiteral("Tctl")});
    }
    if (cpuTempPath_.isEmpty()) {
        cpuTempPath_ = findHwmonTemp({QStringLiteral("cpu_thermal"), QStringLiteral("cpu-thermal")}, {});
    }
    if (cpuTempPath_.isEmpty()) {
        const QString zoneRoot = QStringLiteral("/sys/class/thermal");
        for (const QString &zone : listDirs(zoneRoot, QStringLiteral("thermal_zone*"))) {
            const QByteArray type = readText(zoneRoot + QLatin1Char('/') + zone + QStringLiteral("/type"));
            if (type == "x86_pkg_temp" || type == "cpu-thermal" || type == "cpu_thermal") {
                cpuTempPath_ = zoneRoot + QLatin1Char('/') + zone + QStringLiteral("/temp");
                break;
            }
        }
    }
}

/**
 * @brief /proc/stat の累積値から、前回の読み取りからの CPU 使用率(全コア平均)を求める。
 */
int SystemStats::readCpuPercent() {
    QFile file(QStringLiteral("/proc/stat"));
    if (!file.open(QIODevice::ReadOnly)) {
        return kNA;
    }
    const QList<QByteArray> parts = file.readLine().simplified().split(' ');
    if (parts.size() < 5 || parts.first() != "cpu") {
        return kNA;
    }
    // user nice system idle iowait irq softirq steal
    qulonglong total = 0;
    for (int i = 1; i < parts.size() && i <= 8; ++i) {
        total += parts.at(i).toULongLong();
    }
    const qulonglong idle = parts.at(4).toULongLong() + (parts.size() > 5 ? parts.at(5).toULongLong() : 0);

    int percent = kNA;
    if (haveCpuBaseline_ && total > prevCpuTotal_) {
        const double busy = static_cast<double>((total - prevCpuTotal_) - (idle - prevCpuIdle_));
        percent = std::clamp(static_cast<int>(std::lround(100.0 * busy / static_cast<double>(total - prevCpuTotal_))),
                             0, 100);
    }
    prevCpuTotal_ = total;
    prevCpuIdle_ = idle;
    haveCpuBaseline_ = true;
    return percent;
}

/**
 * @brief 全コアの現在周波数の平均 [MHz]。cpufreq が無ければ /proc/cpuinfo の "cpu MHz" で代用する。
 */
int SystemStats::readCpuFreqMHz() const {
    double sumMHz = 0.0;
    int count = 0;
    if (!cpuFreqPaths_.isEmpty()) {
        for (const QString &path : cpuFreqPaths_) {
            qlonglong kHz = 0;
            if (readLongLong(path, &kHz) && kHz > 0) {
                sumMHz += kHz / 1000.0;
                ++count;
            }
        }
    } else {
        for (const QByteArray &line : readText(QStringLiteral("/proc/cpuinfo")).split('\n')) {
            if (line.startsWith("cpu MHz")) {
                bool ok = false;
                const double mhz = line.mid(line.indexOf(':') + 1).trimmed().toDouble(&ok);
                if (ok && mhz > 0) {
                    sumMHz += mhz;
                    ++count;
                }
            }
        }
    }
    return count > 0 ? static_cast<int>(std::lround(sumMHz / count)) : kNA;
}

int SystemStats::readCpuTempC() const { return readTempC(cpuTempPath_); }

// =====================================================================================================
// メモリ
// =====================================================================================================

/**
 * @brief /proc/meminfo の MemTotal と MemAvailable から使用量・使用率を求める(キャッシュは使用済みに含めない)。
 */
void SystemStats::readMemory(Values &v) const {
    qlonglong totalKb = -1;
    qlonglong availKb = -1;
    for (const QByteArray &line : readText(QStringLiteral("/proc/meminfo")).split('\n')) {
        if (line.startsWith("MemTotal:")) {
            totalKb = line.mid(9).simplified().split(' ').value(0).toLongLong();
        } else if (line.startsWith("MemAvailable:")) {
            availKb = line.mid(13).simplified().split(' ').value(0).toLongLong();
        }
        if (totalKb >= 0 && availKb >= 0) {
            break;
        }
    }
    if (totalKb <= 0 || availKb < 0) {
        return;
    }
    const qlonglong usedKb = std::max<qlonglong>(0, totalKb - availKb);
    v.memTotalMB = static_cast<int>(totalKb / 1024);
    v.memUsedMB = static_cast<int>(usedKb / 1024);
    v.memPercent = std::clamp(static_cast<int>(std::lround(100.0 * usedKb / totalKb)), 0, 100);
}

// =====================================================================================================
// GPU
// =====================================================================================================

/**
 * @brief GPU の取得方法を決める。NVIDIA(NVML)があればそれを、無ければ sysfs の AMD / Intel を使う。
 */
void SystemStats::detectGpu() {
    if (!detectNvml()) {
        detectDrm();
    }
}

/**
 * @brief libnvidia-ml を実行時に読み込み、最初の GPU を使えるようにする。ドライバが無ければ false。
 */
bool SystemStats::detectNvml() {
    auto *lib = new QLibrary(QStringLiteral("libnvidia-ml.so.1"));
    if (!lib->load()) {
        delete lib;
        return false;
    }
    using FnInit = int (*)();
    using FnHandle = int (*)(unsigned int, void **);
    using FnName = int (*)(void *, char *, unsigned int);
    const auto init = reinterpret_cast<FnInit>(lib->resolve("nvmlInit_v2"));
    const auto handle = reinterpret_cast<FnHandle>(lib->resolve("nvmlDeviceGetHandleByIndex_v2"));
    const auto name = reinterpret_cast<FnName>(lib->resolve("nvmlDeviceGetName"));
    nvmlUtil_ = reinterpret_cast<FnDeviceUtil>(lib->resolve("nvmlDeviceGetUtilizationRates"));
    nvmlClock_ = reinterpret_cast<FnDeviceClock>(lib->resolve("nvmlDeviceGetClockInfo"));
    nvmlTemp_ = reinterpret_cast<FnDeviceTemp>(lib->resolve("nvmlDeviceGetTemperature"));
    nvmlShutdown_ = reinterpret_cast<int (*)()>(lib->resolve("nvmlShutdown"));

    if (init == nullptr || handle == nullptr || nvmlUtil_ == nullptr || init() != 0) {
        nvmlUtil_ = nullptr;
        nvmlClock_ = nullptr;
        nvmlTemp_ = nullptr;
        nvmlShutdown_ = nullptr;
        delete lib;
        return false;
    }
    void *device = nullptr;
    if (handle(0, &device) != 0 || device == nullptr) {
        if (nvmlShutdown_ != nullptr) {
            nvmlShutdown_();
        }
        nvmlUtil_ = nullptr;
        nvmlClock_ = nullptr;
        nvmlTemp_ = nullptr;
        nvmlShutdown_ = nullptr;
        delete lib;
        return false;
    }
    nvmlLib_ = lib;
    nvmlDevice_ = device;
    gpuKind_ = GpuKind::Nvml;
    gpuSource_ = QStringLiteral("NVML");
    char buffer[96] = {};
    gpuName_ = (name != nullptr && name(device, buffer, sizeof(buffer)) == 0) ? QString::fromUtf8(buffer)
                                                                               : QStringLiteral("NVIDIA GPU");
    return true;
}

/**
 * @brief /sys/class/drm を調べ、AMD(amdgpu) か Intel(i915 / xe) の GPU を 1 つ選ぶ。AMD を優先する。
 */
bool SystemStats::detectDrm() {
    const QString drmRoot = QStringLiteral("/sys/class/drm");
    const QRegularExpression cardPattern(QStringLiteral("^card\\d+$"));
    QString amdCard;
    QString intelCard;
    QString intelDriver;
    for (const QString &entry : listDirs(drmRoot, QStringLiteral("card*"))) {
        if (!cardPattern.match(entry).hasMatch()) {
            continue; // card0-DP-1 などの出力端子は除く
        }
        const QString driverLink = QFileInfo(drmRoot + QLatin1Char('/') + entry + QStringLiteral("/device/driver"))
                                       .symLinkTarget();
        const QString driver = QFileInfo(driverLink).fileName();
        if (driver == QLatin1String("amdgpu") && amdCard.isEmpty()) {
            amdCard = entry;
        } else if ((driver == QLatin1String("i915") || driver == QLatin1String("xe")) && intelCard.isEmpty()) {
            intelCard = entry;
            intelDriver = driver;
        }
    }

    if (!amdCard.isEmpty()) {
        const QString card = drmRoot + QLatin1Char('/') + amdCard;
        const QString device = card + QStringLiteral("/device");
        const QString hwmon = deviceHwmonDir(device);
        gpuKind_ = GpuKind::Amd;
        gpuSource_ = QStringLiteral("amdgpu");
        const QByteArray product = readText(device + QStringLiteral("/product_name"));
        gpuName_ = product.isEmpty() ? QStringLiteral("AMD GPU") : QString::fromUtf8(product);
        gpuBusyPath_ = firstExisting({device + QStringLiteral("/gpu_busy_percent")});
        if (!hwmon.isEmpty()) {
            gpuTempPath_ = firstExisting({hwmon + QStringLiteral("/temp1_input")});
            gpuFreqPath_ = firstExisting({hwmon + QStringLiteral("/freq1_input")}); // Hz
            gpuFreqScale_ = 1e-6;
        }
        if (gpuFreqPath_.isEmpty()) {
            gpuPpDpmPath_ = firstExisting({device + QStringLiteral("/pp_dpm_sclk")});
        }
        return true;
    }

    if (!intelCard.isEmpty()) {
        const QString card = drmRoot + QLatin1Char('/') + intelCard;
        const QString device = card + QStringLiteral("/device");
        gpuKind_ = GpuKind::Intel;
        gpuSource_ = intelDriver;
        gpuName_ = QStringLiteral("Intel GPU");
        gpuFreqPath_ = firstExisting({card + QStringLiteral("/gt_cur_freq_mhz"),
                                      card + QStringLiteral("/gt/gt0/rps_cur_freq_mhz"),
                                      device + QStringLiteral("/tile0/gt0/freq0/cur_freq")});
        gpuFreqScale_ = 1.0; // いずれも MHz
        gpuIdlePath_ = firstExisting({card + QStringLiteral("/gt/gt0/rc6_residency_ms"),
                                      card + QStringLiteral("/power/rc6_residency_ms"),
                                      device + QStringLiteral("/tile0/gt0/gtidle/idle_residency_ms")});
        const QString hwmon = deviceHwmonDir(device);
        if (!hwmon.isEmpty()) {
            gpuTempPath_ = firstExisting({hwmon + QStringLiteral("/temp1_input")});
        }
        return true;
    }
    return false;
}

/**
 * @brief GPU の使用率・周波数・温度を読む。検出した方式に応じて分岐する。
 */
void SystemStats::readGpu(Values &v) {
    switch (gpuKind_) {
    case GpuKind::None:
        return;

    case GpuKind::Nvml: {
        struct Utilization { unsigned int gpu; unsigned int memory; } util{};
        if (nvmlUtil_ != nullptr && nvmlUtil_(nvmlDevice_, &util) == 0) {
            v.gpuPercent = std::clamp(static_cast<int>(util.gpu), 0, 100);
        }
        unsigned int value = 0;
        if (nvmlClock_ != nullptr && nvmlClock_(nvmlDevice_, 0 /* NVML_CLOCK_GRAPHICS */, &value) == 0) {
            v.gpuFreqMHz = static_cast<int>(value);
        }
        if (nvmlTemp_ != nullptr && nvmlTemp_(nvmlDevice_, 0 /* NVML_TEMPERATURE_GPU */, &value) == 0) {
            v.gpuTempC = static_cast<int>(value);
        }
        return;
    }

    case GpuKind::Amd:
    case GpuKind::Intel:
        break;
    }

    // ---- sysfs(AMD / Intel) ----
    qlonglong raw = 0;
    if (!gpuBusyPath_.isEmpty() && readLongLong(gpuBusyPath_, &raw)) {
        v.gpuPercent = std::clamp(static_cast<int>(raw), 0, 100);
    }
    if (!gpuFreqPath_.isEmpty() && readLongLong(gpuFreqPath_, &raw)) {
        v.gpuFreqMHz = static_cast<int>(std::lround(raw * gpuFreqScale_));
    } else if (!gpuPpDpmPath_.isEmpty()) {
        // 例: "1: 1200Mhz *"(* が現在の段)
        for (const QByteArray &line : readText(gpuPpDpmPath_).split('\n')) {
            if (line.endsWith('*')) {
                const QRegularExpressionMatch m =
                    QRegularExpression(QStringLiteral("(\\d+)\\s*[Mm][Hh][Zz]")).match(QString::fromLatin1(line));
                if (m.hasMatch()) {
                    v.gpuFreqMHz = m.captured(1).toInt();
                }
                break;
            }
        }
    }
    v.gpuTempC = readTempC(gpuTempPath_);

    // Intel は使用率そのものが sysfs に無いので、アイドル(RC6)でなかった時間の割合で近似する
    if (gpuKind_ == GpuKind::Intel && !gpuIdlePath_.isEmpty() && readLongLong(gpuIdlePath_, &raw)) {
        if (prevIdleMs_ >= 0 && idleClock_.isValid()) {
            const qint64 wallMs = idleClock_.restart();
            if (wallMs > 0) {
                const double idle = static_cast<double>(raw - prevIdleMs_) / static_cast<double>(wallMs);
                v.gpuPercent = std::clamp(static_cast<int>(std::lround(100.0 * (1.0 - idle))), 0, 100);
            }
        } else {
            idleClock_.start();
        }
        prevIdleMs_ = raw;
    }
}

} // namespace opencruise
