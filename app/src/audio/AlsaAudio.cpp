/**
 * @file AlsaAudio.cpp
 * @brief ALSA の機器への直接の出力(アプリ内で混ぜる)と録音の実装。
 */
#include "AlsaAudio.h"

#include "core/Log.h"

#include <alsa/asoundlib.h>

#include <QFile>
#include <QHash>

#include <algorithm>
#include <chrono>
#include <cmath>

namespace opencruise::alsa {

namespace {

constexpr int kPeriodFrames = 480;          // 10ms ごとに混ぜて書き込む
constexpr unsigned kLatencyUs = 60000;      // 機器側のバッファ(遅れ)
constexpr int kIdleCloseMs = 3000;          // 音が無い状態がこれだけ続いたら機器を閉じる
constexpr int kRetryMs = 2000;              // 開けなかったときに試し直す間隔
constexpr int kQueueMaxFrames = kRate;      // 1 秒より溜まったら
constexpr int kQueueKeepFrames = kRate * 4 / 10;   // 0.4 秒だけ残して捨てる

QString errorText(int err) { return QString::fromLocal8Bit(snd_strerror(err)); }

/// HDMI / DisplayPort の PCM に、モニター・テレビがつながっているか(ELD を読む)。
/// ELD は HDMI の機器が送ってくる情報で、つながっていないときは空(先頭が 0)。名前は基本ブロックの 16 バイト目から(長さは 4 バイト目の下位 5 ビット)
int readMonitor(snd_ctl_t *ctl, int dev, QString *name) {
    snd_ctl_elem_id_t *id = nullptr;
    snd_ctl_elem_id_alloca(&id);
    snd_ctl_elem_id_set_interface(id, SND_CTL_ELEM_IFACE_PCM);
    snd_ctl_elem_id_set_name(id, "ELD");
    snd_ctl_elem_id_set_device(id, static_cast<unsigned>(dev));
    snd_ctl_elem_info_t *info = nullptr;
    snd_ctl_elem_info_alloca(&info);
    snd_ctl_elem_info_set_id(info, id);
    if (snd_ctl_elem_info(ctl, info) < 0 || snd_ctl_elem_info_get_type(info) != SND_CTL_ELEM_TYPE_BYTES) return -1;
    const unsigned count = snd_ctl_elem_info_get_count(info);
    snd_ctl_elem_value_t *value = nullptr;
    snd_ctl_elem_value_alloca(&value);
    snd_ctl_elem_value_set_id(value, id);
    if (snd_ctl_elem_read(ctl, value) < 0) return -1;
    const auto *b = static_cast<const unsigned char *>(snd_ctl_elem_value_get_bytes(value));
    if (!b || count < 20 || b[0] == 0) return 0;
    const unsigned len = std::min<unsigned>(b[4] & 0x1F, count - 20);
    *name = QString::fromLatin1(reinterpret_cast<const char *>(b + 20), static_cast<int>(len)).trimmed();
    return 1;
}

QList<DeviceInfo> listDevices(snd_pcm_stream_t stream) {
    QList<DeviceInfo> list;
    int card = -1;
    while (snd_card_next(&card) == 0 && card >= 0) {
        snd_ctl_t *ctl = nullptr;
        if (snd_ctl_open(&ctl, QStringLiteral("hw:%1").arg(card).toLatin1().constData(), 0) < 0) continue;
        snd_ctl_card_info_t *info = nullptr;
        snd_ctl_card_info_alloca(&info);
        if (snd_ctl_card_info(ctl, info) < 0) {
            snd_ctl_close(ctl);
            continue;
        }
        const QString cardId = QString::fromLocal8Bit(snd_ctl_card_info_get_id(info));
        DeviceFacts f;
        f.capture = stream == SND_PCM_STREAM_CAPTURE;
        f.cardName = QString::fromLocal8Bit(snd_ctl_card_info_get_name(info));
        f.driver = QString::fromLocal8Bit(snd_ctl_card_info_get_driver(info));
        int hdmiCount = 0;
        int dev = -1;
        while (snd_ctl_pcm_next_device(ctl, &dev) == 0 && dev >= 0) {
            snd_pcm_info_t *pcmInfo = nullptr;
            snd_pcm_info_alloca(&pcmInfo);
            snd_pcm_info_set_device(pcmInfo, static_cast<unsigned>(dev));
            snd_pcm_info_set_subdevice(pcmInfo, 0);
            snd_pcm_info_set_stream(pcmInfo, stream);
            if (snd_ctl_pcm_info(ctl, pcmInfo) < 0) continue;   // この向き(再生/録音)が無い
            f.pcmId = QString::fromLocal8Bit(snd_pcm_info_get_id(pcmInfo));
            f.pcmName = QString::fromLocal8Bit(snd_pcm_info_get_name(pcmInfo));
            f.device = dev;
            const bool hdmi = (f.pcmId + QLatin1Char(' ') + f.pcmName).contains(QLatin1String("HDMI"), Qt::CaseInsensitive)
                              || f.pcmId.startsWith(QLatin1String("DP"), Qt::CaseInsensitive);
            f.hdmiNumber = hdmi ? ++hdmiCount : 0;
            f.monitorName.clear();
            f.monitorState = hdmi ? readMonitor(ctl, dev, &f.monitorName) : -1;
            list.append({QStringLiteral("plughw:CARD=%1,DEV=%2").arg(cardId).arg(dev), deviceLabel(f)});
        }
        snd_ctl_close(ctl);
    }
    // 同じ名前が並んだら(同じ種類のカードが 2 枚など)、見分けが付くように番号を付ける
    for (int i = 0; i < list.size(); ++i) {
        int n = 1;
        for (int j = i + 1; j < list.size(); ++j)
            if (list[j].name == list[i].name) list[j].name += QStringLiteral(" (%1)").arg(++n);
    }
    return list;
}

} // namespace

QString deviceLabel(const DeviceFacts &f) {
    const QString card = f.cardName.isEmpty() ? QStringLiteral("サウンドカード") : f.cardName;
    const QString both = f.pcmId + QLatin1Char(' ') + f.pcmName;
    // HDMI / DisplayPort(外部モニター・テレビ)。つながっていれば相手の名前
    if (f.hdmiNumber > 0) {
        QString s = QStringLiteral("HDMI / DisplayPort %1").arg(f.hdmiNumber);
        if (f.monitorState == 1) s += f.monitorName.isEmpty() ? QStringLiteral(" ・ モニターに接続中") : QStringLiteral(" ・ ") + f.monitorName;
        else if (f.monitorState == 0) s += QStringLiteral("(つながっていません)");
        return s;
    }
    // USB の音声機器(USB スピーカー・ヘッドセット・USB マイクなど)はカードの名前が製品名
    if (f.driver.contains(QLatin1String("USB"), Qt::CaseInsensitive))
        return QStringLiteral("USB 音声 ・ %1").arg(card);
    if (f.driver.contains(QLatin1String("Loopback"), Qt::CaseInsensitive) || card.contains(QLatin1String("Loopback")))
        return QStringLiteral("ループバック(仮想の機器) ・ デバイス %1").arg(f.device);
    if (both.contains(QLatin1String("Digital"), Qt::CaseInsensitive) || both.contains(QLatin1String("SPDIF"), Qt::CaseInsensitive)
        || both.contains(QLatin1String("IEC958"), Qt::CaseInsensitive))
        return QStringLiteral("デジタル(光・同軸) ・ %1").arg(card);
    const auto has = [&both](const char *word) { return both.contains(QLatin1String(word), Qt::CaseInsensitive); };
    const QString rate = has("16k") ? QStringLiteral(" 16kHz") : QString();
    // スピーカーとヘッドホンが別の PCM になっている機器(Intel SOF + RT5682 などのヘッドセット用コーデック +
    // スピーカー用アンプの構成。PCM の名前が "Headset" / "Speakers" / "DMIC" など)は、それぞれ別の名前にする
    if (has("Headset") || has("Headphone") || has("Jack"))
        return (f.capture ? QStringLiteral("ヘッドセットのマイク ・ %1") : QStringLiteral("ヘッドホン端子 ・ %1")).arg(card);
    if (has("Speaker") || has("Spk") || has("Amp"))
        return (f.capture ? QStringLiteral("スピーカーの戻り(エコー除去用) ・ %1") : QStringLiteral("スピーカー ・ %1")).arg(card);
    if (has("DMIC"))
        return QStringLiteral("内蔵マイク%1 ・ %2").arg(rate, card);
    // スピーカーとヘッドホンが同じ PCM の機器(Intel HDA の "ALC… Analog" など。ヘッドホンを挿すとスピーカーが消える)
    if (has("Analog") || has("Mic"))
        return (f.capture ? QStringLiteral("内蔵マイク・マイク端子 ・ %1") : QStringLiteral("スピーカー・ヘッドホン端子 ・ %1")).arg(card);
    // 分からないものは、カード名と PCM の名前(PCM の名前も無ければ番号)
    const QString pcm = f.pcmName.isEmpty() || f.pcmName == QLatin1String("PCM") ? QStringLiteral("デバイス %1").arg(f.device) : f.pcmName;
    return QStringLiteral("%1 ・ %2").arg(card, pcm);
}

QList<DeviceInfo> outputDevices() { return listDevices(SND_PCM_STREAM_PLAYBACK); }
QList<DeviceInfo> inputDevices() { return listDevices(SND_PCM_STREAM_CAPTURE); }

QString cardsSignature() {
    QString sig;
    for (const char *path : {"/proc/asound/cards", "/proc/asound/pcm"}) {
        QFile f(QString::fromLatin1(path));
        if (f.open(QIODevice::ReadOnly)) sig += QString::fromLocal8Bit(f.readAll());
    }
    return sig;
}

// ---------------------------------------------------------------- QueueSource
QueueSource::QueueSource(int rate, int channels) : rate_(std::max(1, rate)), channels_(std::clamp(channels, 1, 2)) {}

void QueueSource::push(const QByteArray &pcm) {
    const int frameBytes = 2 * channels_;
    const int n = static_cast<int>(pcm.size() / frameBytes);
    if (n <= 0) return;
    const auto *in = reinterpret_cast<const int16_t *>(pcm.constData());
    auto sampleL = [&](int i) { return in[i * channels_] / 32768.f; };
    auto sampleR = [&](int i) { return in[i * channels_ + (channels_ - 1)] / 32768.f; };
    const double step = static_cast<double>(rate_) / kRate;
    std::lock_guard<std::mutex> lock(mutex_);
    finishing_ = false;   // 止めた後にまたデータが来たら、続けて流す
    // 届いた形式(rate_)から 48kHz へ、隣り合う 2 つの間をつないで直す(1 つ前の届いた分の最後の音から続ける)
    double t = phase_;
    while (t < n) {
        const int i = static_cast<int>(t);
        const float f = static_cast<float>(t - i);
        const float aL = i == 0 ? lastL_ : sampleL(i - 1), aR = i == 0 ? lastR_ : sampleR(i - 1);
        const float bL = sampleL(i), bR = sampleR(i);
        buffer_.push_back(aL + (bL - aL) * f);
        buffer_.push_back(aR + (bR - aR) * f);
        t += step;
    }
    phase_ = t - n;
    lastL_ = sampleL(n - 1);
    lastR_ = sampleR(n - 1);
    if (buffer_.size() > static_cast<size_t>(kQueueMaxFrames * kChannels)) {
        buffer_.erase(buffer_.begin(), buffer_.end() - kQueueKeepFrames * kChannels);
        log::warn("AUDIO", QStringLiteral("queue too long; dropped old audio"));
    }
}

void QueueSource::clear() {
    std::lock_guard<std::mutex> lock(mutex_);
    buffer_.clear();
}

qint64 QueueSource::queuedFrames() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return static_cast<qint64>(buffer_.size() / kChannels);
}

bool QueueSource::mixInto(float *out, int frames) {
    std::lock_guard<std::mutex> lock(mutex_);
    const float g = gain.load();
    const size_t n = std::min(buffer_.size(), static_cast<size_t>(frames * kChannels));
    for (size_t i = 0; i < n; ++i) out[i] += buffer_[i] * g;
    buffer_.erase(buffer_.begin(), buffer_.begin() + static_cast<std::ptrdiff_t>(n));
    return !(finishing_ && buffer_.empty());
}

// ---------------------------------------------------------------- ClipSource
ClipSource::ClipSource(std::shared_ptr<const std::vector<int16_t>> clip, int loops) : clip_(std::move(clip)), loops_(loops) {}

bool ClipSource::mixInto(float *out, int frames) {
    if (stopped_ || !clip_ || clip_->empty()) {
        finished_ = true;
        return false;
    }
    const float g = gain.load() / 32768.f;
    int done = 0;
    while (done < frames) {
        const size_t left = (clip_->size() - pos_) / kChannels;
        const int n = static_cast<int>(std::min<size_t>(left, static_cast<size_t>(frames - done)));
        for (int i = 0; i < n * kChannels; ++i) out[done * kChannels + i] += (*clip_)[pos_ + static_cast<size_t>(i)] * g;
        pos_ += static_cast<size_t>(n * kChannels);
        done += n;
        if (pos_ >= clip_->size()) {
            if (loops_ < 0 || --loops_ > 0) {
                pos_ = 0;   // 繰り返す
            } else {
                finished_ = true;
                return false;
            }
        }
    }
    return true;
}

// ---------------------------------------------------------------- Output
Output::Output(QString device, bool start) : device_(std::move(device)) {
    if (start) thread_ = std::thread([this]() { run(); });
}

Output::~Output() {
    quit_ = true;
    if (thread_.joinable()) thread_.join();
}

void Output::add(const std::shared_ptr<Source> &source) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (std::find(sources_.begin(), sources_.end(), source) == sources_.end()) sources_.push_back(source);
}

void Output::remove(const std::shared_ptr<Source> &source) {
    std::lock_guard<std::mutex> lock(mutex_);
    sources_.erase(std::remove(sources_.begin(), sources_.end(), source), sources_.end());
}

void Output::run() {
    using Clock = std::chrono::steady_clock;
    snd_pcm_t *pcm = nullptr;
    auto idleSince = Clock::now();
    auto nextTry = Clock::now();
    bool warned = false;
    std::vector<float> mix(kPeriodFrames * kChannels);
    std::vector<int16_t> out(kPeriodFrames * kChannels);
    const QByteArray name = device_.toLocal8Bit();

    auto closePcm = [&](const char *why) {
        if (!pcm) return;
        snd_pcm_drop(pcm);
        snd_pcm_close(pcm);
        pcm = nullptr;
        log::info("AUDIO", QStringLiteral("ALSA output closed (%1): %2").arg(QString::fromLatin1(why), device_));
    };

    while (!quit_) {
        std::vector<std::shared_ptr<Source>> list;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            list = sources_;
        }
        const auto now = Clock::now();
        if (list.empty()) {
            // 音が無い: しばらく無音を書いて、続けば機器を閉じる(ほかのアプリも使えるように)
            if (!pcm || now - idleSince > std::chrono::milliseconds(kIdleCloseMs)) {
                closePcm("idle");
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
                continue;
            }
        } else {
            idleSince = now;
        }
        if (!pcm) {
            if (now < nextTry) {
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
                continue;
            }
            int err = snd_pcm_open(&pcm, name.constData(), SND_PCM_STREAM_PLAYBACK, 0);
            if (err >= 0) err = snd_pcm_set_params(pcm, SND_PCM_FORMAT_S16_LE, SND_PCM_ACCESS_RW_INTERLEAVED, kChannels, kRate, 1, kLatencyUs);
            if (err < 0) {
                if (pcm) snd_pcm_close(pcm);
                pcm = nullptr;
                if (!warned) log::warn("AUDIO", QStringLiteral("cannot open ALSA output %1: %2 (retrying)").arg(device_, errorText(err)));
                warned = true;
                nextTry = now + std::chrono::milliseconds(kRetryMs);
                continue;
            }
            warned = false;
            log::info("AUDIO", QStringLiteral("ALSA output opened: %1 (48000 Hz / 2 ch, mixed in the app)").arg(device_));
        }

        std::fill(mix.begin(), mix.end(), 0.f);
        std::vector<std::shared_ptr<Source>> done;
        for (const auto &s : list) {
            if (!s->mixInto(mix.data(), kPeriodFrames)) done.push_back(s);
        }
        if (!done.empty()) {
            std::lock_guard<std::mutex> lock(mutex_);
            for (const auto &s : done) sources_.erase(std::remove(sources_.begin(), sources_.end(), s), sources_.end());
        }
        for (size_t i = 0; i < mix.size(); ++i) {
            const float v = std::clamp(mix[i], -1.f, 1.f);   // 足し合わせてあふれた分は切る
            out[i] = static_cast<int16_t>(std::lround(v * 32767.f));
        }
        int frames = kPeriodFrames;
        const int16_t *p = out.data();
        while (frames > 0 && !quit_) {
            const snd_pcm_sframes_t n = snd_pcm_writei(pcm, p, static_cast<snd_pcm_uframes_t>(frames));   // 機器の速さに合わせて待つ
            if (n == -EAGAIN) continue;
            if (n < 0) {
                const int r = snd_pcm_recover(pcm, static_cast<int>(n), 1);   // 途切れ(アンダーラン)・サスペンドから戻す
                if (r < 0) {
                    log::warn("AUDIO", QStringLiteral("ALSA write error on %1: %2").arg(device_, errorText(static_cast<int>(n))));
                    closePcm("error");
                    nextTry = Clock::now() + std::chrono::milliseconds(kRetryMs);
                    break;
                }
                continue;
            }
            frames -= static_cast<int>(n);
            p += n * kChannels;
        }
    }
    closePcm("quit");
}

namespace {
std::mutex gOutputsMutex;
QHash<QString, Output *> gOutputs;
bool gShutdown = false;
} // namespace

Output *outputFor(const QString &device) {
    const QString name = device.isEmpty() ? QStringLiteral("default") : device;
    std::lock_guard<std::mutex> lock(gOutputsMutex);
    if (gShutdown) {
        static Output inert(QStringLiteral("(closed)"), false);   // 終了後: 何も鳴らさない
        return &inert;
    }
    Output *&o = gOutputs[name];
    if (!o) o = new Output(name);
    return o;
}

void shutdown() {
    std::lock_guard<std::mutex> lock(gOutputsMutex);
    gShutdown = true;
    qDeleteAll(gOutputs);
    gOutputs.clear();
}

// ---------------------------------------------------------------- Capture
Capture::Capture(QString device, std::function<void(const QByteArray &)> onData, std::function<void(const QString &)> onError)
    : device_(device.isEmpty() ? QStringLiteral("default") : std::move(device)), onData_(std::move(onData)), onError_(std::move(onError)) {}

Capture::~Capture() { stop(); }

bool Capture::start() {
    stop();
    snd_pcm_t *pcm = nullptr;
    int err = snd_pcm_open(&pcm, device_.toLocal8Bit().constData(), SND_PCM_STREAM_CAPTURE, SND_PCM_NONBLOCK);   // 止めるときに待ちを抜けられるように
    if (err >= 0) err = snd_pcm_set_params(pcm, SND_PCM_FORMAT_S16_LE, SND_PCM_ACCESS_RW_INTERLEAVED, 1, 16000, 1, 100000);
    if (err < 0) {
        if (pcm) snd_pcm_close(pcm);
        error_ = QStringLiteral("Could not start recording: %1 (%2)").arg(errorText(err), device_);
        return false;
    }
    pcm_ = pcm;
    quit_ = false;
    error_.clear();
    log::info("AUDIO", QStringLiteral("ALSA capture opened: %1 (16000 Hz / 1 ch)").arg(device_));
    thread_ = std::thread([this, pcm]() {
        std::vector<int16_t> buf(320);   // 20ms
        snd_pcm_start(pcm);
        while (!quit_) {
            // 待たずに読み、まだ無ければ少し休む(止める合図をすぐ見られるように。snd_pcm_wait はプラグインによって起きないことがある)
            const snd_pcm_sframes_t n = snd_pcm_readi(pcm, buf.data(), buf.size());
            if (n == -EAGAIN || n == 0) {
                std::this_thread::sleep_for(std::chrono::milliseconds(5));
                continue;
            }
            if (n < 0) {
                if (snd_pcm_recover(pcm, static_cast<int>(n), 1) >= 0) continue;
                if (!quit_ && onError_) onError_(QStringLiteral("Recording error (code %1)").arg(static_cast<int>(n)));
                break;
            }
            if (n > 0 && onData_) onData_(QByteArray(reinterpret_cast<const char *>(buf.data()), static_cast<int>(n) * 2));
        }
    });
    return true;
}

void Capture::stop() {
    quit_ = true;
    if (thread_.joinable()) thread_.join();
    if (pcm_) {
        snd_pcm_close(static_cast<snd_pcm_t *>(pcm_));
        pcm_ = nullptr;
        log::info("AUDIO", QStringLiteral("ALSA capture closed: %1").arg(device_));
    }
}

} // namespace opencruise::alsa
