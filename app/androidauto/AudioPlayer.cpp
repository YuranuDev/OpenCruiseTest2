/**
 * @file AudioPlayer.cpp
 * @brief AudioPlayer の実装。
 */
#include "AudioPlayer.h"

#include <algorithm>
#include <cstring>

#include <QAudioDevice>
#include <QAudioFormat>
#include <QDebug>
#include <QMediaDevices>
#include <QMutexLocker>

namespace opencruise {

namespace {
constexpr int kSinkBufferMs = 100;   ///< シンク側バッファ
constexpr int kQueueMaxMs = 1000;    ///< これを超えて溜まったら古い音を捨てる
constexpr int kQueueKeepMs = 400;    ///< 捨てるときに残す量
constexpr int kTailMs = 150;         ///< 停止時、キューが空になってから出力を閉じるまでの余韻
constexpr qint64 kIdleCloseMs = 3000; ///< 停止通知が無くてもデータが途絶えたら出力を閉じる
const char *nameOf(int kind) { return kind == 1 ? "media" : kind == 2 ? "guidance" : "system"; }
} // namespace

PcmQueueDevice::PcmQueueDevice(int bytesPerSecond, QObject *parent)
    : QIODevice(parent), bytesPerSecond_(bytesPerSecond) {
    open(QIODevice::ReadOnly);
}

void PcmQueueDevice::push(const QByteArray &pcm) {
    QMutexLocker lock(&mutex_);
    // 読み終えた先頭部分を適宜詰める
    if (readPos_ > 0 && readPos_ >= buffer_.size() / 2) {
        buffer_.remove(0, static_cast<qsizetype>(readPos_));
        readPos_ = 0;
    }
    buffer_.append(pcm);
    const qint64 queued = buffer_.size() - readPos_;
    const qint64 maxBytes = static_cast<qint64>(bytesPerSecond_) * kQueueMaxMs / 1000;
    if (queued > maxBytes) {
        const qint64 keep = static_cast<qint64>(bytesPerSecond_) * kQueueKeepMs / 1000;
        const qint64 frame = 4; // 2ch×16bit の倍数に揃えておけば 1ch でも壊れない
        readPos_ = buffer_.size() - (keep / frame) * frame;
        qWarning() << "[audio] キューが溜まりすぎたため古い音声を破棄しました";
    }
    sinceLastPush_.restart();
    pushedOnce_ = true;
}

qint64 PcmQueueDevice::queuedBytes() const {
    QMutexLocker lock(&mutex_);
    return buffer_.size() - readPos_;
}

qint64 PcmQueueDevice::msSinceLastPush() const {
    QMutexLocker lock(&mutex_);
    return pushedOnce_ ? sinceLastPush_.elapsed() : 0;
}

qint64 PcmQueueDevice::bytesAvailable() const {
    // 無音で埋めて必ず要求に応えるので、常に十分な量があると申告する
    return queuedBytes() + 65536 + QIODevice::bytesAvailable();
}

qint64 PcmQueueDevice::readData(char *data, qint64 maxlen) {
    QMutexLocker lock(&mutex_);
    const qint64 avail = buffer_.size() - readPos_;
    const qint64 n = std::min(avail, maxlen);
    if (n > 0) {
        std::memcpy(data, buffer_.constData() + readPos_, static_cast<size_t>(n));
        readPos_ += n;
    }
    if (n < maxlen) {
        std::memset(data + n, 0, static_cast<size_t>(maxlen - n)); // アンダーラン時は無音
    }
    return maxlen;
}

AudioPlayer::AudioPlayer(QObject *parent) : QObject(parent) {
    timer_.setInterval(50);
    connect(&timer_, &QTimer::timeout, this, [this]() { housekeeping(); });
}

void AudioPlayer::write(int kind, const QByteArray &pcm) {
    if (kind < 0 || kind > 2 || pcm.isEmpty()) {
        return;
    }
    Channel &ch = channels_[kind];
    if (ch.failed) {
        return;
    }
    if (!ch.sink) {
        QAudioFormat format;
        format.setSampleRate(kind == 1 ? 48000 : 16000);
        format.setChannelCount(kind == 1 ? 2 : 1);
        format.setSampleFormat(QAudioFormat::Int16);

        const QAudioDevice device = QMediaDevices::defaultAudioOutput();
        if (device.isNull() || !device.isFormatSupported(format)) {
            qWarning().noquote() << "[audio] 出力デバイスが無い、または形式に未対応です:" << nameOf(kind)
                                 << "device:" << device.description();
            ch.failed = true;
            return;
        }
        const int bytesPerSecond = format.sampleRate() * format.channelCount() * 2;
        ch.device = std::make_unique<PcmQueueDevice>(bytesPerSecond);
        ch.sink = std::make_unique<QAudioSink>(device, format);
        ch.sink->setBufferSize(bytesPerSecond * kSinkBufferMs / 1000);
        ch.sink->start(ch.device.get()); // pull モード: シンクがデバイスから読み出す
        if (ch.sink->error() != QAudio::NoError) {
            qWarning().noquote() << "[audio] 出力を開始できませんでした:" << nameOf(kind) << ch.sink->error();
            destroy(ch);
            ch.failed = true;
            return;
        }
        qInfo().noquote() << "[audio] 再生を開始します:" << nameOf(kind) << format.sampleRate() << "Hz"
                          << format.channelCount() << "ch on" << device.description();
        if (!timer_.isActive()) {
            timer_.start();
        }
    }
    ch.draining = false; // 停止後に新しいデータが来たら再開扱い
    ch.device->push(pcm);
}

void AudioPlayer::stop(int kind) {
    if (kind < 0 || kind > 2) {
        return;
    }
    Channel &ch = channels_[kind];
    ch.failed = false;
    if (ch.sink) {
        ch.draining = true; // 再生待ちを鳴らし切ってから housekeeping() が破棄する
    }
}

void AudioPlayer::stopAll() {
    for (Channel &ch : channels_) {
        destroy(ch);
        ch.failed = false;
    }
    timer_.stop();
}

void AudioPlayer::destroy(Channel &ch) {
    if (ch.sink) {
        ch.sink->stop();
    }
    ch.sink.reset();
    ch.device.reset();
    ch.draining = false;
}

void AudioPlayer::housekeeping() {
    bool anyActive = false;
    for (int kind = 0; kind < 3; ++kind) {
        Channel &ch = channels_[kind];
        if (!ch.sink) {
            continue;
        }
        const bool empty = ch.device->queuedBytes() == 0;
        // 余韻(シンク内バッファ分)を待ってから閉じる
        const bool quiet = ch.device->msSinceLastPush() >= (ch.draining ? kTailMs + kSinkBufferMs : kIdleCloseMs);
        if (empty && quiet) {
            qInfo().noquote() << "[audio] 出力を閉じます:" << nameOf(kind);
            destroy(ch);
        } else {
            anyActive = true;
        }
    }
    if (!anyActive) {
        timer_.stop();
    }
}

} // namespace opencruise
