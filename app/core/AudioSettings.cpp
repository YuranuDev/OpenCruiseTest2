/**
 * @file AudioSettings.cpp
 * @brief AudioSettings の実装。
 */
#include "AudioSettings.h"

#include <algorithm>
#include <cmath>
#include <utility>

#include <QSettings>

#include "Log.h"

namespace opencruise {

namespace {

QSettings openStore() {
    return QSettings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"),
                     QStringLiteral("OpenCruise"));
}

/// 保存キーに使うグループ名
QString keyName(AudioSettings::Group group) {
    switch (group) {
    case AudioSettings::Map: return QStringLiteral("map");
    case AudioSettings::Music: return QStringLiteral("music");
    default: return QStringLiteral("system");
    }
}

QString displayName(AudioSettings::Group group) {
    switch (group) {
    case AudioSettings::Map: return QStringLiteral("マップ音声");
    case AudioSettings::Music: return QStringLiteral("音楽音声");
    default: return QStringLiteral("システム");
    }
}

} // namespace

AudioSettings::AudioSettings(QObject *parent) : QObject(parent) {
    const QSettings store = openStore();
    masterVolume_ = std::clamp(store.value(QStringLiteral("audio/masterVolume"), 100).toInt(), 0, 100);
    for (int i = 0; i < GroupCount; ++i) {
        const Group group = static_cast<Group>(i);
        volumes_[i] = std::clamp(store.value(QStringLiteral("audio/%1Volume").arg(keyName(group)), 100).toInt(), 0, 100);
        // 機器の id は任意のバイト列のため、Base64 で保存する
        selectedIds_[i] = QByteArray::fromBase64(
            store.value(QStringLiteral("audio/%1Device").arg(keyName(group)), QString()).toString().toLatin1());
    }

    outputs_ = QMediaDevices::audioOutputs();
    outputNames_ << QStringLiteral("システム既定");
    for (const QAudioDevice &dev : std::as_const(outputs_)) {
        outputNames_ << dev.description();
    }
    log::info("AUDIO", QStringLiteral("found %1 output devices").arg(outputs_.size()));

    connect(&mediaDevices_, &QMediaDevices::audioOutputsChanged, this, [this]() { refreshOutputs(); });

    micEnabled_ = store.value(QStringLiteral("audio/micEnabled"), true).toBool();
    selectedMicId_ = QByteArray::fromBase64(store.value(QStringLiteral("audio/micDevice"), QString()).toString().toLatin1());
    inputs_ = QMediaDevices::audioInputs();
    inputNames_ << QStringLiteral("システム既定");
    for (const QAudioDevice &dev : std::as_const(inputs_)) {
        inputNames_ << dev.description();
    }
    log::info("AUDIO", QStringLiteral("found %1 input devices").arg(inputs_.size()));
    connect(&mediaDevices_, &QMediaDevices::audioInputsChanged, this, [this]() { refreshInputs(); });
}

AudioSettings::Group AudioSettings::groupForKind(int kind) {
    switch (kind) {
    case 1: return Music;
    case 2: return Map;
    default: return System; // 0 (Android Auto のシステム音)
    }
}

double AudioSettings::individualGain(Group group) const {
    const double linear = volumes_[group] / 100.0;
    return linear * linear;
}

double AudioSettings::masterGain() const {
    const double linear = masterVolume_ / 100.0;
    return linear * linear;
}

double AudioSettings::gain(Group group) const {
    // 個別 × マスターを、ここ 1 か所だけで合成する
    return individualGain(group) * masterGain();
}

void AudioSettings::setMasterVolume(int volume) {
    volume = std::clamp(volume, 0, 100);
    if (volume == masterVolume_) {
        return;
    }
    masterVolume_ = volume;
    openStore().setValue(QStringLiteral("audio/masterVolume"), volume);
    emit masterVolumeChanged();
    // 再生中の出力へ反映させるため、全グループの音量が変わったものとして通知する(個別の設定値そのものは変わらない)
    for (int i = 0; i < GroupCount; ++i) {
        emit volumeChangedFor(i);
    }
}

void AudioSettings::adjustMasterVolume(int delta) {
    setMasterVolume(masterVolume_ + delta);
}

void AudioSettings::setVolume(Group group, int volume) {
    volume = std::clamp(volume, 0, 100);
    if (volume == volumes_[group]) {
        return;
    }
    volumes_[group] = volume;
    openStore().setValue(QStringLiteral("audio/%1Volume").arg(keyName(group)), volume);
    emit volumesChanged();
    emit volumeChangedFor(static_cast<int>(group));
}

QByteArray AudioSettings::resolvedId(Group group) const {
    if (!selectedIds_[group].isEmpty()) {
        for (const QAudioDevice &dev : outputs_) {
            if (dev.id() == selectedIds_[group]) {
                return dev.id();
            }
        }
    }
    return QMediaDevices::defaultAudioOutput().id();
}

int AudioSettings::deviceIndex(Group group) const {
    if (selectedIds_[group].isEmpty()) {
        return 0;
    }
    for (int i = 0; i < outputs_.size(); ++i) {
        if (outputs_[i].id() == selectedIds_[group]) {
            return i + 1;
        }
    }
    return 0; // 保存した機器が未接続の間はシステム既定で鳴らす(選択は保持し、再接続で戻る)
}

QAudioDevice AudioSettings::device(Group group) const {
    const int index = deviceIndex(group);
    if (index > 0) {
        return outputs_[index - 1];
    }
    return QMediaDevices::defaultAudioOutput();
}

void AudioSettings::setDeviceIndex(Group group, int index) {
    if (index < 0 || index > outputs_.size()) {
        return;
    }
    const QByteArray id = index == 0 ? QByteArray() : outputs_[index - 1].id();
    if (id == selectedIds_[group]) {
        return;
    }
    selectedIds_[group] = id;
    openStore().setValue(QStringLiteral("audio/%1Device").arg(keyName(group)), QString::fromLatin1(id.toBase64()));
    log::info("AUDIO", QStringLiteral("%1 output: %2")
                           .arg(keyName(group), index == 0 ? QStringLiteral("system default") : outputNames_.value(index)));
    emit devicesChanged();
    emit deviceChangedFor(static_cast<int>(group));
}

void AudioSettings::refreshOutputs() {
    QByteArray before[GroupCount];
    for (int i = 0; i < GroupCount; ++i) {
        before[i] = resolvedId(static_cast<Group>(i));
    }

    outputs_ = QMediaDevices::audioOutputs();
    outputNames_.clear();
    outputNames_ << QStringLiteral("システム既定");
    for (const QAudioDevice &dev : std::as_const(outputs_)) {
        outputNames_ << dev.description();
    }
    log::info("AUDIO", QStringLiteral("output devices changed (%1)").arg(outputs_.size()));
    emit outputsChanged();
    emit devicesChanged(); // 番号が指す機器がずれた可能性があるので、選択表示も更新させる

    for (int i = 0; i < GroupCount; ++i) {
        if (resolvedId(static_cast<Group>(i)) != before[i]) {
            emit deviceChangedFor(i);
        }
    }
}

void AudioSettings::setMicEnabled(bool enabled) {
    if (enabled == micEnabled_) {
        return;
    }
    micEnabled_ = enabled;
    openStore().setValue(QStringLiteral("audio/micEnabled"), enabled);
    log::info("AUDIO", QStringLiteral("microphone: %1").arg(enabled ? QStringLiteral("on") : QStringLiteral("off")));
    emit micChanged();
}

int AudioSettings::micDeviceIndex() const {
    if (selectedMicId_.isEmpty()) {
        return 0;
    }
    for (int i = 0; i < inputs_.size(); ++i) {
        if (inputs_[i].id() == selectedMicId_) {
            return i + 1;
        }
    }
    return 0; // 保存した機器が未接続の間はシステム既定を使う(選択は保持し、再接続で戻る)
}

QAudioDevice AudioSettings::micDevice() const {
    const int index = micDeviceIndex();
    if (index > 0) {
        return inputs_[index - 1];
    }
    return QMediaDevices::defaultAudioInput();
}

void AudioSettings::setMicDeviceIndex(int index) {
    if (index < 0 || index > inputs_.size()) {
        return;
    }
    const QByteArray id = index == 0 ? QByteArray() : inputs_[index - 1].id();
    if (id == selectedMicId_) {
        return;
    }
    selectedMicId_ = id;
    openStore().setValue(QStringLiteral("audio/micDevice"), QString::fromLatin1(id.toBase64()));
    log::info("AUDIO", QStringLiteral("microphone input: %1").arg(index == 0 ? QStringLiteral("system default") : inputNames_.value(index)));
    emit micChanged();
}

void AudioSettings::refreshInputs() {
    inputs_ = QMediaDevices::audioInputs();
    inputNames_.clear();
    inputNames_ << QStringLiteral("システム既定");
    for (const QAudioDevice &dev : std::as_const(inputs_)) {
        inputNames_ << dev.description();
    }
    log::info("AUDIO", QStringLiteral("input devices changed (%1)").arg(inputs_.size()));
    emit inputsChanged();
    emit micChanged(); // 番号が指す機器がずれた/選んだ機器が現れた・消えた可能性があるので、録音側にも見直させる
}

} // namespace opencruise
