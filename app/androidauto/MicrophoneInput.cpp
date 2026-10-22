/**
 * @file MicrophoneInput.cpp
 * @brief MicrophoneInput の実装。
 */
#include "MicrophoneInput.h"

#include <QAudioDevice>
#include <QAudioFormat>
#include <QDebug>
#include <QIODevice>
#include <QMediaDevices>
#include <QMetaObject>

namespace opencruise {

namespace {
constexpr int kSampleRate = 16000; ///< AasdkMicrophoneHandler::fillFeatures の申告値と一致させる
constexpr int kChannels = 1;
constexpr int kBufferMs = 40;      ///< 録音バッファ。この単位で readyRead が来る(遅延と送信回数のバランス)
} // namespace

MicrophoneInput::MicrophoneInput(QObject *parent) : QObject(parent) {
    refreshStatus();
}

MicrophoneInput::~MicrophoneInput() {
    stopCapture();
}

void MicrophoneInput::setSettings(AudioSettings *settings) {
    if (settings_) {
        settings_->disconnect(this);
    }
    settings_ = settings;
    if (settings_) {
        connect(settings_, &AudioSettings::micChanged, this, [this]() { reconcile(); });
    }
    reconcile();
}

void MicrophoneInput::setRequested(bool requested) {
    if (requested == requested_) {
        return;
    }
    requested_ = requested;
    qInfo().noquote() << "[mic] Android Auto がマイクを" << (requested ? "要求しました" : "閉じました");
    reconcile();
}

void MicrophoneInput::reconcile() {
    const bool enabled = settings_ ? settings_->micEnabled() : true;
    if (!(requested_ && enabled)) {
        stopCapture();
        errorText_.clear();
        refreshStatus();
        return;
    }
    if (source_) {
        // 入力元の選択(や接続状況)が変わっていたら作り直す。変わっていなければ何もしない
        const QAudioDevice wanted = settings_ ? settings_->micDevice() : QMediaDevices::defaultAudioInput();
        if (wanted.id() == currentDeviceId_) {
            return;
        }
        qInfo().noquote() << "[mic] 入力元が変わったため、録音を作り直します";
        stopCapture();
    }
    startCapture();
}

void MicrophoneInput::startCapture() {
    errorText_.clear();

    QAudioFormat format;
    format.setSampleRate(kSampleRate);
    format.setChannelCount(kChannels);
    format.setSampleFormat(QAudioFormat::Int16);

    // 設定で選ばれた入力元を使う。選んだ機器が形式に対応しない場合は、システム既定へ切り替える
    QAudioDevice device = settings_ ? settings_->micDevice() : QMediaDevices::defaultAudioInput();
    if (!device.isNull() && !device.isFormatSupported(format)) {
        const QAudioDevice fallback = QMediaDevices::defaultAudioInput();
        if (!fallback.isNull() && fallback.id() != device.id()) {
            qWarning().noquote() << "[mic] 選択した入力元が形式に未対応のため、システム既定を使います:" << device.description();
            device = fallback;
        }
    }
    if (device.isNull()) {
        errorText_ = QStringLiteral("入力デバイスが見つかりません");
    } else if (!device.isFormatSupported(format)) {
        errorText_ = QStringLiteral("入力デバイスが 16kHz/16bit/モノラルに対応していません: ") + device.description();
    }
    if (!errorText_.isEmpty()) {
        qWarning().noquote() << "[mic] 録音を開始できません:" << errorText_;
        refreshStatus();
        return;
    }

    const int bytesPerSecond = kSampleRate * kChannels * 2;
    auto source = std::make_unique<QAudioSource>(device, format);
    source->setBufferSize(bytesPerSecond * kBufferMs / 1000);
    // 録音中の異常(機器の取り外しなど)は、デバイスを閉じてエラー表示にする。次の要求/設定変更で再試行する
    connect(source.get(), &QAudioSource::stateChanged, this, [this]() {
        if (source_ && source_->error() != QAudio::NoError) {
            errorText_ = QStringLiteral("録音中にエラーが発生しました (コード %1)").arg(static_cast<int>(source_->error()));
            qWarning().noquote() << "[mic]" << errorText_;
            // シグナルの処理中に自分自身を破棄しないよう、後で閉じる
            QMetaObject::invokeMethod(
                this,
                [this]() {
                    const QString keep = errorText_;
                    stopCapture();
                    errorText_ = keep;
                    refreshStatus();
                },
                Qt::QueuedConnection);
        }
    });

    QIODevice *io = source->start(); // pull モード: readyRead で読み出す
    if (io == nullptr || source->error() != QAudio::NoError) {
        errorText_ = QStringLiteral("録音を開始できませんでした: ") + device.description();
        qWarning().noquote() << "[mic]" << errorText_ << "error:" << static_cast<int>(source->error());
        source->stop();
        refreshStatus();
        return;
    }
    connect(io, &QIODevice::readyRead, this, [this]() { onReadyRead(); });

    source_ = std::move(source);
    io_ = io;
    currentDeviceId_ = device.id();
    currentDeviceName_ = device.description();
    qInfo().noquote() << "[mic] 録音を開始します:" << kSampleRate << "Hz" << kChannels << "ch on" << currentDeviceName_;
    refreshStatus();
}

void MicrophoneInput::stopCapture() {
    if (!source_) {
        return;
    }
    source_->stop();
    source_.reset();
    io_ = nullptr;
    currentDeviceId_.clear();
    currentDeviceName_.clear();
    qInfo().noquote() << "[mic] 録音を停止しました";
}

void MicrophoneInput::onReadyRead() {
    if (io_ == nullptr) {
        return;
    }
    const QByteArray pcm = io_->readAll();
    if (!pcm.isEmpty()) {
        emit captured(pcm);
    }
}

void MicrophoneInput::refreshStatus() {
    QString text;
    const bool enabled = settings_ ? settings_->micEnabled() : true;
    if (!errorText_.isEmpty()) {
        text = QStringLiteral("エラー: ") + errorText_;
    } else if (source_) {
        text = QStringLiteral("録音中 (%1)").arg(currentDeviceName_);
    } else if (!enabled) {
        text = QStringLiteral("オフ(使用しません)");
    } else {
        text = QStringLiteral("待機中(Android Auto が音声入力を使うときだけ録音します)");
    }
    if (text != statusText_) {
        statusText_ = text;
        emit statusChanged();
    }
}

} // namespace opencruise
