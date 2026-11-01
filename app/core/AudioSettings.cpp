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

} // namespace

AudioSettings::AudioSettings(QObject *parent) : QObject(parent) {
    const QSettings store = openStore();
    masterVolume_ = std::clamp(store.value(QStringLiteral("audio/masterVolume"), 100).toInt(), 0, 100);
    for (int i = 0; i < GroupCount; ++i) {
        const Group group = static_cast<Group>(i);
        volumes_[i] = std::clamp(store.value(QStringLiteral("audio/%1Volume").arg(keyName(group)), 100).toInt(), 0, 100);
        // 選んだ出力先の識別子。以前の保存(機器の id の Base64)は "qt:" を付けて読み替える
        const QString key = store.value(QStringLiteral("audio/%1Output").arg(keyName(group))).toString();
        const QString old = store.value(QStringLiteral("audio/%1Device").arg(keyName(group))).toString();
        selectedKeys_[i] = !key.isEmpty() ? key : (old.isEmpty() ? QString() : QStringLiteral("qt:") + old);
    }

    micEnabled_ = store.value(QStringLiteral("audio/micEnabled"), true).toBool();
    {
        const QString key = store.value(QStringLiteral("audio/micInput")).toString();
        const QString old = store.value(QStringLiteral("audio/micDevice")).toString();
        selectedMicKey_ = !key.isEmpty() ? key : (old.isEmpty() ? QString() : QStringLiteral("qt:") + old);
    }

    outputs_ = buildChoices(true);
    outputNames_ << QStringLiteral("システム既定");
    for (const Choice &c : std::as_const(outputs_)) outputNames_ << c.name;
    inputs_ = buildChoices(false);
    inputNames_ << QStringLiteral("システム既定");
    for (const Choice &c : std::as_const(inputs_)) inputNames_ << c.name;
    log::info("AUDIO", QStringLiteral("found %1 outputs / %2 inputs (%3)")
                           .arg(outputs_.size()).arg(inputs_.size())
                           .arg(pulse_.available() ? QStringLiteral("PulseAudio ports, shared") : QStringLiteral("Qt devices")));

    connect(&mediaDevices_, &QMediaDevices::audioOutputsChanged, this, [this]() { refreshOutputs(); });
    connect(&mediaDevices_, &QMediaDevices::audioInputsChanged, this, [this]() { refreshInputs(); });
    // 端子の切り替え・ヘッドホンの抜き差し・プロファイルの切り替え
    connect(&pulse_, &PulseAudioControl::changed, this, [this]() {
        refreshOutputs();
        refreshInputs();
    });
}

QList<AudioSettings::Choice> AudioSettings::buildChoices(bool output) const {
    QList<Choice> list;
    if (pulse_.available()) {
        for (const PulseAudioControl::Entry &e : output ? pulse_.outputs() : pulse_.inputs()) {
            Choice c;
            c.key = e.key;
            c.name = e.name;
            c.qtId = e.node.toUtf8();
            c.pulse = true;
            c.entry = e;
            list << c;
        }
        return list;
    }
    for (const QAudioDevice &dev : output ? QMediaDevices::audioOutputs() : QMediaDevices::audioInputs()) {
        Choice c;
        c.key = QStringLiteral("qt:") + QString::fromLatin1(dev.id().toBase64());
        c.name = dev.description();
        c.qtId = dev.id();
        list << c;
    }
    return list;
}

int AudioSettings::indexForKey(const QString &key, const QList<Choice> &choices) const {
    if (key.isEmpty()) return 0;
    // 機器(シンク/ソース)の今の端子の項目を探す
    auto nodeIndex = [&](const QString &node) {
        int any = 0;
        for (int i = 0; i < choices.size(); ++i) {
            if (choices[i].entry.node != node) continue;
            if (choices[i].entry.port == pulse_.activePort(node)) return i + 1;
            if (any == 0) any = i + 1;
        }
        return any;
    };
    if (key.startsWith(QStringLiteral("qt:"))) {
        const QByteArray id = QByteArray::fromBase64(key.mid(3).toLatin1());
        if (pulse_.available()) return nodeIndex(QString::fromUtf8(id));   // 以前の保存(シンクの名前)
        for (int i = 0; i < choices.size(); ++i) {
            if (choices[i].qtId == id) return i + 1;
        }
        return 0;
    }
    if (key.startsWith(QStringLiteral("port:"))) {
        const QString node = key.mid(5).section(QLatin1Char('|'), 0, 0);
        return nodeIndex(node);   // 端子はほかの音・ほかのアプリと共通なので、今の端子で見せる
    }
    if (key.startsWith(QStringLiteral("profile:"))) {
        const QString card = key.mid(8).section(QLatin1Char('|'), 0, 0);
        const QString profile = key.mid(8).section(QLatin1Char('|'), 1);
        if (pulse_.activeProfile(card) == profile) {
            // 切り替わった後: そのカードのシンク(の今の端子)
            for (int i = 0; i < choices.size(); ++i) {
                if (!choices[i].entry.node.isEmpty() && choices[i].entry.card == card) return nodeIndex(choices[i].entry.node);
            }
        }
        for (int i = 0; i < choices.size(); ++i) {
            if (choices[i].key == key) return i + 1;
        }
    }
    return 0;
}

QAudioDevice AudioSettings::deviceFor(int index, const QList<Choice> &choices, bool output) const {
    const QAudioDevice fallback = output ? QMediaDevices::defaultAudioOutput() : QMediaDevices::defaultAudioInput();
    if (index <= 0 || index > choices.size()) return fallback;
    const QByteArray id = choices[index - 1].qtId;
    if (id.isEmpty()) return fallback;   // プロファイルの切り替え待ち
    for (const QAudioDevice &dev : output ? QMediaDevices::audioOutputs() : QMediaDevices::audioInputs()) {
        if (dev.id() == id) return dev;
    }
    return fallback;   // Qt からはまだ見えない(切り替えの直後など)
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

int AudioSettings::deviceIndex(Group group) const {
    // 保存した機器が未接続の間は 0(システム既定で鳴らす)。選択は保持し、再接続で戻る
    return indexForKey(selectedKeys_[group], outputs_);
}

QAudioDevice AudioSettings::device(Group group) const {
    return deviceFor(deviceIndex(group), outputs_, true);
}

void AudioSettings::setDeviceIndex(Group group, int index) {
    if (index < 0 || index > outputs_.size()) {
        return;
    }
    const QString key = index == 0 ? QString() : outputs_[index - 1].key;
    if (index > 0 && outputs_[index - 1].pulse) {
        pulse_.activate(outputs_[index - 1].entry);   // 端子・プロファイルを切り替える(同じ項目でも、端子がずれていれば戻す)
    }
    if (key == selectedKeys_[group]) {
        return;
    }
    const QByteArray before = device(group).id();
    selectedKeys_[group] = key;
    openStore().setValue(QStringLiteral("audio/%1Output").arg(keyName(group)), key);
    log::info("AUDIO", QStringLiteral("%1 output: %2")
                           .arg(keyName(group), index == 0 ? QStringLiteral("system default") : outputNames_.value(index)));
    emit devicesChanged();
    if (device(group).id() != before) {
        emit deviceChangedFor(static_cast<int>(group));
    }
}

void AudioSettings::refreshOutputs() {
    QByteArray before[GroupCount];
    for (int i = 0; i < GroupCount; ++i) {
        before[i] = device(static_cast<Group>(i)).id();
    }

    outputs_ = buildChoices(true);
    QStringList names{QStringLiteral("システム既定")};
    for (const Choice &c : std::as_const(outputs_)) names << c.name;
    if (names != outputNames_) {
        outputNames_ = names;
        log::info("AUDIO", QStringLiteral("output devices changed (%1)").arg(outputs_.size()));
        emit outputsChanged();
    }
    emit devicesChanged(); // 番号が指す機器・今の端子が変わった可能性があるので、選択表示も更新させる

    for (int i = 0; i < GroupCount; ++i) {
        if (device(static_cast<Group>(i)).id() != before[i]) {
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
    // 保存した機器が未接続の間は 0(システム既定を使う)。選択は保持し、再接続で戻る
    return indexForKey(selectedMicKey_, inputs_);
}

QAudioDevice AudioSettings::micDevice() const {
    return deviceFor(micDeviceIndex(), inputs_, false);
}

void AudioSettings::setMicDeviceIndex(int index) {
    if (index < 0 || index > inputs_.size()) {
        return;
    }
    const QString key = index == 0 ? QString() : inputs_[index - 1].key;
    if (index > 0 && inputs_[index - 1].pulse) {
        pulse_.activate(inputs_[index - 1].entry);
    }
    if (key == selectedMicKey_) {
        return;
    }
    selectedMicKey_ = key;
    openStore().setValue(QStringLiteral("audio/micInput"), key);
    log::info("AUDIO", QStringLiteral("microphone input: %1").arg(index == 0 ? QStringLiteral("system default") : inputNames_.value(index)));
    emit micChanged();
}

void AudioSettings::refreshInputs() {
    inputs_ = buildChoices(false);
    QStringList names{QStringLiteral("システム既定")};
    for (const Choice &c : std::as_const(inputs_)) names << c.name;
    if (names != inputNames_) {
        inputNames_ = names;
        log::info("AUDIO", QStringLiteral("input devices changed (%1)").arg(inputs_.size()));
        emit inputsChanged();
    }
    emit micChanged(); // 番号が指す機器がずれた/選んだ機器が現れた・消えた可能性があるので、録音側にも見直させる
}

} // namespace opencruise
