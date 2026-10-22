/**
 * @file SystemSound.cpp
 * @brief SystemSound の実装(同梱 WAV の読み込みと再生)。
 */
#include "SystemSound.h"

#include <QUrl>

#include "AudioSettings.h"
#include "Log.h"

namespace opencruise {

namespace {
constexpr qint64 kClickMinIntervalMs = 70; ///< 操作音を連打したときの最短間隔
} // namespace

SystemSound::SystemSound(AudioSettings *settings, QObject *parent)
    : QObject(parent), settings_(settings), click_(this), start_(this) {
    setupEffect(click_, clickPending_, QStringLiteral("qrc:/OpenCruise/sounds/Click.wav"));
    setupEffect(start_, startPending_, QStringLiteral("qrc:/OpenCruise/sounds/Start.wav"));
    sinceClick_.start();

    if (settings_) {
        const auto onChanged = [this](int group) {
            if (group == AudioSettings::System) {
                applySettings();
            }
        };
        connect(settings_, &AudioSettings::volumeChangedFor, this, onChanged);
        connect(settings_, &AudioSettings::deviceChangedFor, this, onChanged);
    }
    applySettings();
}

void SystemSound::setupEffect(QSoundEffect &effect, bool &pending, const QString &resourcePath) {
    effect.setSource(QUrl(resourcePath));
    connect(&effect, &QSoundEffect::statusChanged, this, [this, &effect, &pending, resourcePath]() {
        if (effect.status() == QSoundEffect::Error) {
            log::warn("AUDIO", QStringLiteral("システム音を読み込めません: ") + resourcePath);
            pending = false;
        } else if (effect.status() == QSoundEffect::Ready && pending) {
            pending = false;
            effect.play();
        }
    });
}

void SystemSound::applySettings() {
    if (!settings_) {
        return;
    }
    const float gain = static_cast<float>(settings_->gain(AudioSettings::System));
    const QAudioDevice device = settings_->device(AudioSettings::System);
    for (QSoundEffect *effect : {&click_, &start_}) {
        effect->setVolume(gain);
        if (!device.isNull() && effect->audioDevice().id() != device.id()) {
            effect->setAudioDevice(device);
        }
    }
}

void SystemSound::playEffect(QSoundEffect &effect, bool &pending) {
    switch (effect.status()) {
    case QSoundEffect::Ready:
        effect.play();
        break;
    case QSoundEffect::Loading:
        pending = true; // 読み込みが終わったら鳴らす
        break;
    default:
        break; // 読み込みに失敗している(警告は読み込み時に出ている)
    }
}

void SystemSound::play(const QString &name) {
    if (name == QStringLiteral("click")) {
        if (sinceClick_.elapsed() < kClickMinIntervalMs) {
            return;
        }
        sinceClick_.restart();
        playEffect(click_, clickPending_);
    } else if (name == QStringLiteral("start")) {
        playEffect(start_, startPending_);
    }
}

} // namespace opencruise
