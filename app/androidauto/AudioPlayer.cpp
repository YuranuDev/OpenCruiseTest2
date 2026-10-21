/**
 * @file AudioPlayer.cpp
 * @brief AudioPlayer の実装。
 */
#include "AudioPlayer.h"

#include <QAudioDevice>
#include <QAudioFormat>
#include <QDebug>
#include <QMediaDevices>

namespace opencruise {

namespace {
constexpr int kBufferMs = 300; ///< 出力バッファ長。これを超えて溜まる分は捨てる
const char *nameOf(int kind) { return kind == 1 ? "media" : kind == 2 ? "guidance" : "system"; }
} // namespace

/**
 * @brief PCM を書き込む。
 */
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

        const auto devices = QMediaDevices::audioOutputs();

        qInfo() << "[audio] output device count:" << devices.size();

        for (const auto &d : devices) {
            qInfo() << "[audio] output:"
                    << d.description()
                    << "id:" << d.id();
        }

        const QAudioDevice device = QMediaDevices::defaultAudioOutput();

        qInfo() << "[audio] device valid:" << !device.isNull();

        if (!device.isNull()) {
            qInfo() << "[audio] device id:" << device.id();
            qInfo() << "[audio] device description:" << device.description();
            qInfo() << "[audio] preferred format:" << device.preferredFormat();
            qInfo() << "[audio] requested format:" << format;
            qInfo() << "[audio] format supported:" << device.isFormatSupported(format);
        }
        
        if (device.isNull() || !device.isFormatSupported(format)) {
            qWarning().noquote() << "[audio] 出力デバイスが無い、または形式に未対応です:" << nameOf(kind);
            ch.failed = true;
            return;
        }
        ch.sink = std::make_unique<QAudioSink>(device, format);
        ch.sink->setBufferSize(format.sampleRate() * format.channelCount() * 2 * kBufferMs / 1000);
        ch.device = ch.sink->start();
        if (ch.device == nullptr) {
            qWarning().noquote() << "[audio] 出力を開始できませんでした:" << nameOf(kind);
            ch.sink.reset();
            ch.failed = true;
            return;
        }
        qInfo().noquote() << "[audio] 再生を開始します:" << nameOf(kind) << format.sampleRate() << "Hz"
                          << format.channelCount() << "ch";
    }
    if (ch.sink->bytesFree() >= pcm.size()) {
        ch.device->write(pcm);
    } // 空きが無ければ捨てて遅延の蓄積を防ぐ
}

/**
 * @brief 指定チャネルを止める。
 */
void AudioPlayer::stop(int kind) {
    if (kind < 0 || kind > 2) {
        return;
    }
    Channel &ch = channels_[kind];
    if (ch.sink) {
        ch.sink->stop();
    }
    ch.sink.reset();
    ch.device = nullptr;
    ch.failed = false;
}

/**
 * @brief すべて止める。
 */
void AudioPlayer::stopAll() {
    for (int kind = 0; kind < 3; ++kind) {
        stop(kind);
    }
}

} // namespace opencruise
