/**
 * @file AlsaSoundEffect.cpp
 * @brief ALSA で鳴らす効果音の再生器の実装。
 */
#include "AlsaSoundEffect.h"

#include "AlsaAudio.h"
#include "Log.h"

#include <QAudioBuffer>
#include <QAudioDecoder>
#include <QFile>
#include <QHash>

#include <algorithm>
#include <cstring>
#include <mutex>

namespace opencruise {

namespace {

// 読み込んだ音の共有(同じファイルは 1 回だけ読む)
std::mutex gCacheMutex;
QHash<QString, std::shared_ptr<const std::vector<int16_t>>> gCache;

QString pathOf(const QUrl &url) {
    if (url.scheme() == QStringLiteral("qrc")) return QStringLiteral(":") + url.path();
    return url.isLocalFile() ? url.toLocalFile() : url.toString();
}

// 1 ch あたりの値(-1〜1)の並び(左右交互)を、48kHz / 2ch の 16bit へ直す
std::vector<int16_t> toClip(const std::vector<float> &in, int rate, int channels) {
    std::vector<int16_t> out;
    if (in.empty() || rate <= 0 || channels <= 0) return out;
    const size_t frames = in.size() / static_cast<size_t>(channels);
    const double step = static_cast<double>(rate) / alsa::kRate;
    const size_t outFrames = static_cast<size_t>(frames / step);
    out.reserve(outFrames * 2);
    auto at = [&](size_t f, int c) { return in[f * static_cast<size_t>(channels) + static_cast<size_t>(std::min(c, channels - 1))]; };
    for (size_t o = 0; o < outFrames; ++o) {
        const double t = o * step;
        const size_t i = static_cast<size_t>(t);
        const float frac = static_cast<float>(t - static_cast<double>(i));
        const size_t j = std::min(i + 1, frames - 1);
        for (int c = 0; c < 2; ++c) {
            const float v = at(i, c) + (at(j, c) - at(i, c)) * frac;
            out.push_back(static_cast<int16_t>(std::clamp(v, -1.f, 1.f) * 32767.f));
        }
    }
    return out;
}

// WAV(PCM 8 / 16 / 24 / 32bit・float)を読む。読めなければ false
bool readWav(const QByteArray &data, std::vector<int16_t> *clip) {
    if (data.size() < 12 || !data.startsWith("RIFF") || data.mid(8, 4) != "WAVE") return false;
    auto u16 = [&](int p) { return static_cast<quint16>(static_cast<quint8>(data[p]) | (static_cast<quint8>(data[p + 1]) << 8)); };
    auto u32 = [&](int p) { return static_cast<quint32>(u16(p) | (static_cast<quint32>(u16(p + 2)) << 16)); };
    int format = 0, channels = 0, rate = 0, bits = 0;
    int pos = 12;
    while (pos + 8 <= data.size()) {
        const QByteArray id = data.mid(pos, 4);
        const qint64 size = u32(pos + 4);
        const int body = pos + 8;
        if (id == "fmt " && body + 16 <= data.size()) {
            format = u16(body);
            channels = u16(body + 2);
            rate = static_cast<int>(u32(body + 4));
            bits = u16(body + 14);
            if (format == 0xFFFE && size >= 26 && body + 26 <= data.size()) format = u16(body + 24);   // WAVE_FORMAT_EXTENSIBLE
        } else if (id == "data") {
            if (channels <= 0 || rate <= 0 || (format != 1 && format != 3)) return false;
            const int bytes = bits / 8;
            if (bytes <= 0) return false;
            const qint64 end = std::min<qint64>(body + size, data.size());
            std::vector<float> samples;
            samples.reserve(static_cast<size_t>((end - body) / bytes));
            for (qint64 p = body; p + bytes <= end; p += bytes) {
                const char *s = data.constData() + p;
                float v = 0.f;
                if (format == 3 && bytes == 4) { float f; std::memcpy(&f, s, 4); v = f; }
                else if (bytes == 1) v = (static_cast<quint8>(s[0]) - 128) / 128.f;
                else if (bytes == 2) { qint16 x; std::memcpy(&x, s, 2); v = x / 32768.f; }
                else if (bytes == 3) { const qint32 x = (static_cast<quint8>(s[0]) | (static_cast<quint8>(s[1]) << 8) | (static_cast<qint8>(s[2]) << 16)); v = x / 8388608.f; }
                else if (bytes == 4) { qint32 x; std::memcpy(&x, s, 4); v = x / 2147483648.f; }
                samples.push_back(v);
            }
            *clip = toClip(samples, rate, channels);
            return !clip->empty();
        }
        pos = body + static_cast<int>(size + (size & 1));
    }
    return false;
}

} // namespace

AlsaSoundEffect::AlsaSoundEffect(QObject *parent) : QObject(parent) {}

AlsaSoundEffect::~AlsaSoundEffect() {
    stop();
}

void AlsaSoundEffect::setStatus(Status status) {
    if (status == status_) return;
    status_ = status;
    emit statusChanged();
}

void AlsaSoundEffect::setSource(const QUrl &url) {
    if (url == source_) return;
    stop();
    source_ = url;
    clip_.reset();
    if (decoder_) {
        decoder_->stop();
        decoder_->deleteLater();
        decoder_ = nullptr;
    }
    if (url.isEmpty()) {
        setStatus(Null);
        return;
    }
    const QString path = pathOf(url);
    {
        std::lock_guard<std::mutex> lock(gCacheMutex);
        if (gCache.contains(path)) {
            clip_ = gCache.value(path);
            setStatus(Loading);
            setStatus(Ready);
            return;
        }
    }
    setStatus(Loading);
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        log::warn("AUDIO", QStringLiteral("cannot open sound: %1").arg(path));
        setStatus(Error);
        return;
    }
    const QByteArray data = f.readAll();
    std::vector<int16_t> clip;
    if (readWav(data, &clip)) {
        auto shared = std::make_shared<const std::vector<int16_t>>(std::move(clip));
        {
            std::lock_guard<std::mutex> lock(gCacheMutex);
            gCache.insert(path, shared);
        }
        clip_ = shared;
        setStatus(Ready);
        return;
    }
    decodeWithQt(url);   // MP3 など
}

void AlsaSoundEffect::decodeWithQt(const QUrl &url) {
    const QString path = pathOf(url);
    decoded_.clear();
    decoder_ = new QAudioDecoder(this);
    auto *file = new QFile(path, decoder_);
    if (!file->open(QIODevice::ReadOnly)) {
        setStatus(Error);
        return;
    }
    decoder_->setSourceDevice(file);
    QAudioDecoder *dec = decoder_;
    connect(dec, &QAudioDecoder::bufferReady, this, [this, dec]() {
        const QAudioBuffer buf = dec->read();
        const QAudioFormat fmt = buf.format();
        const int ch = fmt.channelCount();
        std::vector<float> samples;
        samples.reserve(static_cast<size_t>(buf.sampleCount()));
        for (qsizetype i = 0; i < buf.sampleCount(); ++i) {
            switch (fmt.sampleFormat()) {
            case QAudioFormat::UInt8: samples.push_back((buf.constData<quint8>()[i] - 128) / 128.f); break;
            case QAudioFormat::Int16: samples.push_back(buf.constData<qint16>()[i] / 32768.f); break;
            case QAudioFormat::Int32: samples.push_back(buf.constData<qint32>()[i] / 2147483648.f); break;
            case QAudioFormat::Float: samples.push_back(buf.constData<float>()[i]); break;
            default: break;
            }
        }
        const std::vector<int16_t> part = toClip(samples, fmt.sampleRate(), ch);
        decoded_.insert(decoded_.end(), part.begin(), part.end());
    });
    connect(dec, &QAudioDecoder::finished, this, [this, dec, path]() {
        if (dec != decoder_) return;
        auto shared = std::make_shared<const std::vector<int16_t>>(std::move(decoded_));
        decoded_ = {};
        if (shared->empty()) {
            setStatus(Error);
            return;
        }
        {
            std::lock_guard<std::mutex> lock(gCacheMutex);
            gCache.insert(path, shared);
        }
        clip_ = shared;
        setStatus(Ready);
    });
    connect(dec, qOverload<QAudioDecoder::Error>(&QAudioDecoder::error), this, [this, dec, path](QAudioDecoder::Error) {
        if (dec != decoder_) return;
        log::warn("AUDIO", QStringLiteral("cannot decode sound %1: %2").arg(path, dec->errorString()));
        setStatus(Error);
    });
    dec->start();
}

void AlsaSoundEffect::setVolume(float volume) {
    volume_ = std::clamp(volume, 0.f, 1.f);
    if (playing_) playing_->gain = volume_;
}

void AlsaSoundEffect::setOutputDevice(const QString &device) {
    if (device == device_) return;
    const QString old = device_;
    device_ = device;
    if (playing_ && !playing_->finished()) {   // 鳴っている途中なら、続きを新しい出力先で
        alsa::outputFor(old)->remove(playing_);
        alsa::outputFor(device_)->add(playing_);
    }
}

bool AlsaSoundEffect::isPlaying() const {
    return playing_ && !playing_->finished();
}

void AlsaSoundEffect::play() {
    if (status_ != Ready || !clip_) return;
    stop();   // 鳴っている途中なら、頭から鳴らし直す
    playing_ = std::make_shared<alsa::ClipSource>(clip_, loopCount_ == Infinite ? -1 : std::max(1, loopCount_));
    playing_->gain = volume_;
    alsa::outputFor(device_)->add(playing_);
}

void AlsaSoundEffect::stop() {
    if (!playing_) return;
    playing_->stop();
    alsa::outputFor(device_)->remove(playing_);
    playing_.reset();
}

} // namespace opencruise
