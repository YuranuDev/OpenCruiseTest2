/**
 * @file SystemSound.cpp
 * @brief SystemSound の実装(効果音フォルダの一覧・選択・再生)。
 */
#include "SystemSound.h"

#include <QCoreApplication>
#include <QDir>
#include <QEvent>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QMouseEvent>
#include <QSettings>
#include <QStandardPaths>
#include <QTouchEvent>
#include <QUrl>
#include <QVariantMap>

#include "AudioSettings.h"
#include "Log.h"

#include <algorithm>
#include <cmath>

namespace opencruise {

namespace {
constexpr qint64 kClickMinIntervalMs = 70; ///< 操作音を連打したときの最短間隔

const QString kNone = QStringLiteral("none");
const QString kBuiltinPrefix = QStringLiteral("builtin:");
const QString kUserPrefix = QStringLiteral("user:");
const QStringList kCategories = {QStringLiteral("click"), QStringLiteral("start"), QStringLiteral("alert")};
const QString kSynthId = QStringLiteral("synth"); ///< 警告音の「合成音」

/// 合成音の設定項目(範囲と既定値)
struct SynthParam {
    const char *key;
    int min;
    int max;
    int def;
};
constexpr SynthParam kSynthParams[] = {
    {"waveform", 0, 3, 0},       {"frequency", 200, 6000, 2000}, {"frequency2", 0, 6000, 0},
    {"pulses", 1, 8, 2},         {"pulseMs", 20, 1000, 90},      {"gapMs", 0, 1000, 70},
    {"fadeMs", 0, 50, 4},        {"volume", 10, 100, 80},
};
constexpr int kIntervalMin = 300;
constexpr int kIntervalMax = 10000;
constexpr int kIntervalDefault = 1400;
constexpr int kSampleRate = 44100;

const SynthParam *findParam(const QString &key) {
    for (const SynthParam &p : kSynthParams) {
        if (key == QLatin1String(p.key)) {
            return &p;
        }
    }
    return nullptr;
}

/** @brief 16 bit・モノラルの PCM を WAV ファイルに書く。 */
bool writeWav(const QString &path, const QByteArray &pcm) {
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return false;
    }
    const auto u32 = [](quint32 v) {
        const char b[4] = {char(v & 0xff), char((v >> 8) & 0xff), char((v >> 16) & 0xff), char((v >> 24) & 0xff)};
        return QByteArray(b, 4);
    };
    const auto u16 = [](quint16 v) {
        const char b[2] = {char(v & 0xff), char((v >> 8) & 0xff)};
        return QByteArray(b, 2);
    };
    QByteArray head;
    head += "RIFF" + u32(36 + pcm.size()) + "WAVE";
    head += "fmt " + u32(16) + u16(1) + u16(1) + u32(kSampleRate) + u32(kSampleRate * 2) + u16(2) + u16(16);
    head += "data" + u32(pcm.size());
    return file.write(head) == head.size() && file.write(pcm) == pcm.size();
}

QSettings openStore() {
    return QSettings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"),
                     QStringLiteral("OpenCruise"));
}

/// カテゴリの既定の音(同梱フォルダのファイル名)と、同梱フォルダが無いときに使うリソースの音
QString defaultFile(const QString &category) {
    if (category == QStringLiteral("start")) {
        return QStringLiteral("Start.wav");
    }
    if (category == QStringLiteral("alert")) {
        return QStringLiteral("Beep.wav");
    }
    return QStringLiteral("Click.wav");
}
QString fallbackResource(const QString &category) {
    return QStringLiteral("qrc:/OpenCruise/sounds/%1/%2").arg(category, defaultFile(category));
}
bool isCategory(const QString &category) {
    return kCategories.contains(category);
}
} // namespace

SystemSound::SystemSound(AudioSettings *settings, QObject *parent)
    : QObject(parent), settings_(settings), click_(this), start_(this), alert_(this), preview_(this) {
    setupEffect(click_, clickPending_);
    setupEffect(start_, startPending_);
    setupEffect(alert_, alertPending_);
    setupEffect(preview_, previewPending_);

    // ユーザーフォルダ(カテゴリごと)を作っておく。ここへ WAV を置くと一覧に出る
    for (const QString &category : kCategories) {
        QDir().mkpath(userSoundDirectory() + QLatin1Char('/') + category);
    }
    loadSynth();
    rebuildSynth();
    log::info("AUDIO", QStringLiteral("効果音フォルダ: 同梱=%1 / ユーザー=%2")
                           .arg(builtinSoundDirectory().isEmpty() ? QStringLiteral("(見つかりません)") : builtinSoundDirectory(),
                                userSoundDirectory()));
    for (const QString &category : kCategories) {
        loadCategory(category);
    }

    sinceClick_.start();
    if (auto *app = QGuiApplication::instance()) {
        app->installEventFilter(this); // パネルへの触れ/離れを監視する
    }

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

QString SystemSound::userSoundDirectory() const {
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/OpenCruise/sounds");
}

QString SystemSound::builtinSoundDirectory() const {
    const QString appDir = QCoreApplication::applicationDirPath();
    for (const QString &dir : {appDir + QStringLiteral("/sounds"),
                               QDir::cleanPath(appDir + QStringLiteral("/../share/opencruise/sounds"))}) {
        if (QFileInfo(dir).isDir()) {
            return dir;
        }
    }
    return {};
}

QStringList SystemSound::wavFiles(const QString &directory) {
    if (directory.isEmpty()) {
        return {};
    }
    return QDir(directory).entryList({QStringLiteral("*.wav"), QStringLiteral("*.WAV")}, QDir::Files | QDir::Readable,
                                     QDir::Name | QDir::IgnoreCase);
}

QVariantList SystemSound::soundOptions(const QString &category) const {
    QVariantList list;
    list.append(QVariantMap{{QStringLiteral("id"), kNone}, {QStringLiteral("name"), QStringLiteral("なし(鳴らさない)")},
                            {QStringLiteral("folder"), QString()}});
    if (!isCategory(category)) {
        return list;
    }
    if (category == QStringLiteral("alert")) {
        list.append(QVariantMap{{QStringLiteral("id"), kSynthId}, {QStringLiteral("name"), QStringLiteral("合成音(自分で設定)")},
                                {QStringLiteral("folder"), QStringLiteral("内蔵")}});
    }
    const QString builtin = builtinSoundDirectory();
    QStringList builtinFiles = wavFiles(builtin.isEmpty() ? QString() : builtin + QLatin1Char('/') + category);
    if (builtinFiles.isEmpty()) {
        builtinFiles << defaultFile(category); // 同梱フォルダが無くても、既定の音(リソース)は選べるようにする
    }
    for (const QString &file : builtinFiles) {
        list.append(QVariantMap{{QStringLiteral("id"), kBuiltinPrefix + file},
                                {QStringLiteral("name"), QFileInfo(file).completeBaseName()},
                                {QStringLiteral("folder"), QStringLiteral("同梱")}});
    }
    for (const QString &file : wavFiles(userSoundDirectory() + QLatin1Char('/') + category)) {
        list.append(QVariantMap{{QStringLiteral("id"), kUserPrefix + file},
                                {QStringLiteral("name"), QFileInfo(file).completeBaseName()},
                                {QStringLiteral("folder"), QStringLiteral("ユーザー")}});
    }
    return list;
}

QString SystemSound::selectedSound(const QString &category) const {
    return openStore().value(QStringLiteral("sound/") + category, kBuiltinPrefix + defaultFile(category)).toString();
}

void SystemSound::setSelectedSound(const QString &category, const QString &id) {
    if (!isCategory(category)) {
        return;
    }
    openStore().setValue(QStringLiteral("sound/") + category, id);
    loadCategory(category);
    applySettings();
    ++revision_;
    emit soundsChanged();
}

QUrl SystemSound::urlFor(const QString &category, const QString &id) const {
    if (id == kSynthId) {
        if (category == QStringLiteral("alert") && !synthPath_.isEmpty() && QFileInfo::exists(synthPath_)) {
            return QUrl::fromLocalFile(synthPath_);
        }
        return {};
    }
    if (id.startsWith(kBuiltinPrefix)) {
        const QString file = id.mid(kBuiltinPrefix.size());
        const QString builtin = builtinSoundDirectory();
        const QString path = builtin + QLatin1Char('/') + category + QLatin1Char('/') + file;
        if (!builtin.isEmpty() && QFileInfo::exists(path)) {
            return QUrl::fromLocalFile(path);
        }
        if (file == defaultFile(category)) {
            return QUrl(fallbackResource(category)); // 同梱フォルダが無い環境でも既定の音は鳴らす
        }
    } else if (id.startsWith(kUserPrefix)) {
        const QString path = userSoundDirectory() + QLatin1Char('/') + category + QLatin1Char('/') + id.mid(kUserPrefix.size());
        if (QFileInfo::exists(path)) {
            return QUrl::fromLocalFile(path);
        }
    }
    return {};
}

void SystemSound::loadCategory(const QString &category) {
    const QString id = selectedSound(category);
    const bool muted = id == kNone;
    QUrl url = muted ? QUrl() : urlFor(category, id);
    if (!muted && url.isEmpty()) {
        // 選んでいたファイルが消えている: 既定の音に戻す(設定はそのまま。ファイルが戻れば次回から使う)
        log::warn("AUDIO", QStringLiteral("効果音が見つかりません(%1: %2)。既定の音を使います").arg(category, id));
        url = urlFor(category, kBuiltinPrefix + defaultFile(category));
    }
    QSoundEffect &effect = effectOf(category);
    mutedOf(category) = muted;
    pendingOf(category) = false;
    if (effect.source() != url) {
        effect.setSource(url);
    }
    if (category == QStringLiteral("alert") && alertLooping_) {
        alertLooping_ = false; // ずっと鳴らしている途中で音を変えたら、新しい音で鳴らし直す
        alert_.setLoopCount(1);
        updateAlertLoop();
    } else if (category == QStringLiteral("alert")) {
        updateAlertLoop();
    }
}

QSoundEffect &SystemSound::effectOf(const QString &category) {
    if (category == QStringLiteral("start")) {
        return start_;
    }
    return category == QStringLiteral("alert") ? alert_ : click_;
}

bool &SystemSound::pendingOf(const QString &category) {
    if (category == QStringLiteral("start")) {
        return startPending_;
    }
    return category == QStringLiteral("alert") ? alertPending_ : clickPending_;
}

bool &SystemSound::mutedOf(const QString &category) {
    if (category == QStringLiteral("start")) {
        return startMuted_;
    }
    return category == QStringLiteral("alert") ? alertMuted_ : clickMuted_;
}

void SystemSound::preview(const QString &category, const QString &id) {
    if (id == kNone || !isCategory(category)) {
        preview_.stop();
        return;
    }
    const QUrl url = urlFor(category, id);
    if (url.isEmpty()) {
        return;
    }
    preview_.stop();
    if (preview_.source() != url) {
        preview_.setSource(url);
    }
    playEffect(preview_, previewPending_);
}

void SystemSound::rescan() {
    for (const QString &category : kCategories) {
        loadCategory(category);
    }
    ++revision_;
    emit soundsChanged();
}

void SystemSound::loadSynth() {
    QSettings store = openStore();
    for (const SynthParam &p : kSynthParams) {
        const int v = store.value(QStringLiteral("sound/synth/") + QLatin1String(p.key), p.def).toInt();
        synth_.insert(QLatin1String(p.key), std::clamp(v, p.min, p.max));
    }
    alertInterval_ = std::clamp(store.value(QStringLiteral("sound/alertInterval"), kIntervalDefault).toInt(),
                                kIntervalMin, kIntervalMax);
    alertContinuous_ = store.value(QStringLiteral("sound/alertContinuous"), false).toBool();
    // 前回の起動で作った合成音の WAV を消しておく
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    for (const QString &file : QDir(dir).entryList({QStringLiteral("alert-synth-*.wav")}, QDir::Files)) {
        QFile::remove(dir + QLatin1Char('/') + file);
    }
}

int SystemSound::synthLengthMs() const {
    const int pulses = synth_.value(QStringLiteral("pulses")).toInt();
    return pulses * synth_.value(QStringLiteral("pulseMs")).toInt()
           + std::max(0, pulses - 1) * synth_.value(QStringLiteral("gapMs")).toInt();
}

void SystemSound::rebuildSynth() {
    const int waveform = synth_.value(QStringLiteral("waveform")).toInt();
    const double f1 = synth_.value(QStringLiteral("frequency")).toInt();
    const int f2raw = synth_.value(QStringLiteral("frequency2")).toInt();
    const double f2 = f2raw > 0 ? f2raw : f1;
    const int pulses = synth_.value(QStringLiteral("pulses")).toInt();
    const int pulseMsLen = kSampleRate * synth_.value(QStringLiteral("pulseMs")).toInt() / 1000;
    const int gapLen = kSampleRate * synth_.value(QStringLiteral("gapMs")).toInt() / 1000;
    const int fadeMs = synth_.value(QStringLiteral("fadeMs")).toInt();
    const double amp = 0.9 * synth_.value(QStringLiteral("volume")).toInt() / 100.0;

    QByteArray pcm;
    pcm.reserve((pulses * (pulseMsLen + gapLen) + kSampleRate / 50) * 2);
    const auto put = [&pcm](double s) {
        const auto v = static_cast<qint16>(std::lround(std::clamp(s, -1.0, 1.0) * 32767.0));
        pcm.append(char(v & 0xff));
        pcm.append(char((v >> 8) & 0xff));
    };
    for (int p = 0; p < pulses; ++p) {
        const double f = (p % 2 == 1) ? f2 : f1; // 2 音目を違う高さにすると交互に鳴る
        // ずっと鳴らすときは、1 音を波の周期の整数倍にして、つなぎ目(次の音・ループの頭)で「プツッ」と言わないようにする
        int pulseLen = pulseMsLen;
        if (alertContinuous_) {
            const double period = kSampleRate / f;
            pulseLen = std::max(1, static_cast<int>(std::lround(std::max(1.0, std::round(pulseMsLen / period)) * period)));
        }
        const int fadeLen = std::min(kSampleRate * fadeMs / 1000, pulseLen / 2);
        for (int i = 0; i < pulseLen; ++i) {
            const double phase = std::fmod(f * i / kSampleRate, 1.0);
            double s = 0;
            switch (waveform) {
            case 1: s = (phase < 0.5 ? 1.0 : -1.0) * 0.55; break;      // 矩形(サインと聞こえの大きさをそろえる)
            case 2: s = 1.0 - 4.0 * std::abs(phase - 0.5); break;      // 三角
            case 3: s = (2.0 * phase - 1.0) * 0.65; break;             // のこぎり
            default: s = std::sin(6.283185307179586 * phase); break;          // サイン
            }
            double env = 1.0;
            if (fadeLen > 0) {
                env = std::min({1.0, double(i) / fadeLen, double(pulseLen - i) / fadeLen});
            }
            put(s * env * amp);
        }
        if (p < pulses - 1) {
            for (int i = 0; i < gapLen; ++i) {
                put(0);
            }
        }
    }
    if (!alertContinuous_) {
        for (int i = 0; i < kSampleRate / 50; ++i) { // 末尾に 20 ms の無音(切れ際のノイズ防止。ループするときは付けない)
            put(0);
        }
    } else if (gapLen > 0 && pulses > 0) {
        for (int i = 0; i < gapLen; ++i) { // ループの頭へ戻るまでにも、音と音の間をあける
            put(0);
        }
    }

    const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QDir().mkpath(dir);
    const QString path = dir + QStringLiteral("/alert-synth-%1.wav").arg(++synthSerial_);
    if (!writeWav(path, pcm)) {
        log::warn("AUDIO", QStringLiteral("合成音を書き出せません: ") + path);
        return;
    }
    const QString old = synthPath_;
    synthPath_ = path;
    if (selectedSound(QStringLiteral("alert")) == kSynthId) {
        loadCategory(QStringLiteral("alert"));
    }
    if (!old.isEmpty() && preview_.source() != QUrl::fromLocalFile(old)) {
        QFile::remove(old);
    }
}

void SystemSound::setSynthValue(const QString &key, const QVariant &value) {
    const SynthParam *p = findParam(key);
    if (!p) {
        return;
    }
    const int v = std::clamp(value.toInt(), p->min, p->max);
    if (synth_.value(key).toInt() == v) {
        return;
    }
    synth_.insert(key, v);
    openStore().setValue(QStringLiteral("sound/synth/") + key, v);
    rebuildSynth();
    applySettings();
    emit synthChanged();
}

void SystemSound::applySynthPreset(const QString &name) {
    struct Preset {
        const char *name;
        int waveform, frequency, frequency2, pulses, pulseMs, gapMs, fadeMs, interval;
        bool continuous;
    };
    static const Preset kPresets[] = {
        {"pipi", 0, 2000, 0, 2, 90, 70, 4, 1400, false},   // ピピッ
        {"pii", 0, 2400, 0, 1, 500, 0, 8, 1500, false},    // ピー(長め 1 音)
        {"pipo", 0, 960, 770, 4, 160, 20, 6, 1600, false}, // ピポピポ(2 音を交互)
        {"fast", 1, 3000, 0, 3, 50, 50, 2, 700, false},    // 速い連打(矩形波)
        {"chime", 2, 1300, 1000, 2, 260, 40, 12, 2200, false}, // チャイム(三角波で下がる 2 音)
        {"continuous", 0, 2400, 0, 1, 500, 0, 0, 1400, true},  // 警告中ずっと「ピーー」
        {"continuousPipo", 0, 960, 770, 2, 300, 0, 0, 1400, true}, // 警告中ずっと「ピーポーピーポー」
    };
    for (const Preset &p : kPresets) {
        if (name != QLatin1String(p.name)) {
            continue;
        }
        QSettings store = openStore();
        const std::pair<const char *, int> values[] = {{"waveform", p.waveform}, {"frequency", p.frequency},
                                                       {"frequency2", p.frequency2}, {"pulses", p.pulses},
                                                       {"pulseMs", p.pulseMs}, {"gapMs", p.gapMs}, {"fadeMs", p.fadeMs}};
        for (const auto &[key, v] : values) {
            synth_.insert(QLatin1String(key), v);
            store.setValue(QStringLiteral("sound/synth/") + QLatin1String(key), v);
        }
        alertInterval_ = p.interval;
        store.setValue(QStringLiteral("sound/alertInterval"), alertInterval_);
        alertContinuous_ = p.continuous;
        store.setValue(QStringLiteral("sound/alertContinuous"), alertContinuous_);
        rebuildSynth();
        applySettings();
        updateAlertLoop();
        emit synthChanged();
        return;
    }
}

void SystemSound::previewSynth() {
    const QUrl url = urlFor(QStringLiteral("alert"), kSynthId);
    if (url.isEmpty()) {
        return;
    }
    preview_.stop();
    if (preview_.source() != url) {
        preview_.setSource(url);
    }
    playEffect(preview_, previewPending_);
}

void SystemSound::setAlertInterval(int ms) {
    ms = std::clamp(ms, kIntervalMin, kIntervalMax);
    if (ms == alertInterval_) {
        return;
    }
    alertInterval_ = ms;
    openStore().setValue(QStringLiteral("sound/alertInterval"), ms);
    emit synthChanged();
}

void SystemSound::setAlertContinuous(bool on) {
    if (on == alertContinuous_) {
        return;
    }
    alertContinuous_ = on;
    openStore().setValue(QStringLiteral("sound/alertContinuous"), on);
    rebuildSynth(); // つなぎ目の作り方が変わる
    updateAlertLoop();
    emit synthChanged();
}

void SystemSound::setAlertActive(bool on) {
    if (on == alertActive_) {
        return;
    }
    alertActive_ = on;
    updateAlertLoop();
    emit alertActiveChanged();
}

void SystemSound::updateAlertLoop() {
    const bool loop = alertContinuous_ && alertActive_ && !alertMuted_;
    if (loop && !alertLooping_) {
        alertLooping_ = true;
        alert_.stop();
        alert_.setLoopCount(QSoundEffect::Infinite);
        playEffect(alert_, alertPending_); // 読み込み中なら、読み込みが終わってから鳴らし始める
    } else if (!loop && alertLooping_) {
        alertLooping_ = false; // 繰り返しモードの 1 回分は止めない(ループしていたときだけ止める)
        alert_.stop();
        alert_.setLoopCount(1);
        alertPending_ = false;
    }
}

void SystemSound::setupEffect(QSoundEffect &effect, bool &pending) {
    connect(&effect, &QSoundEffect::statusChanged, this, [&effect, &pending]() {
        if (effect.status() == QSoundEffect::Error) {
            log::warn("AUDIO", QStringLiteral("システム音を読み込めません: ") + effect.source().toString());
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
    for (QSoundEffect *effect : {&click_, &start_, &alert_, &preview_}) {
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
        if (clickMuted_ || sinceClick_.elapsed() < kClickMinIntervalMs) {
            return;
        }
        sinceClick_.restart();
        playEffect(click_, clickPending_);
    } else if (name == QStringLiteral("start")) {
        if (!startMuted_) {
            playEffect(start_, startPending_);
        }
    } else if (name == QStringLiteral("alert")) {
        if (!alertMuted_ && !(alertContinuous_ && alertActive_)) { // ずっと鳴らしている間は、ループに任せる
            alert_.stop(); // 前の 1 回が残っていても頭から鳴らし直す
            playEffect(alert_, alertPending_);
        }
    }
}

void SystemSound::updateTouchLatch() {
    const bool down = touchDown_ || mouseDown_;
    if (down && !latched_) {
        latched_ = true; // 離れるまで解除しない
        play(QStringLiteral("click"));
    } else if (!down) {
        latched_ = false;
    }
}

bool SystemSound::eventFilter(QObject *watched, QEvent *event) {
    if (!watched->isWindowType()) {
        return false; // ウィンドウに届いたものだけを見る(同じ入力を二重に数えない)
    }
    switch (event->type()) {
    case QEvent::TouchBegin:
    case QEvent::TouchUpdate:
    case QEvent::TouchEnd: {
        bool anyDown = false;
        for (const QEventPoint &point : static_cast<QTouchEvent *>(event)->points()) {
            if (point.state() != QEventPoint::Released) {
                anyDown = true;
            }
        }
        touchDown_ = anyDown;
        updateTouchLatch();
        break;
    }
    case QEvent::TouchCancel:
    case QEvent::ApplicationDeactivate: // 離れたイベントが届かないまま非アクティブになった場合の取りこぼし対策
        touchDown_ = false;
        mouseDown_ = false;
        updateTouchLatch();
        break;
    case QEvent::MouseButtonPress:
    case QEvent::MouseButtonRelease: {
        const auto *mouse = static_cast<QMouseEvent *>(event);
        if (mouse->source() == Qt::MouseEventNotSynthesized && mouse->button() == Qt::LeftButton) {
            mouseDown_ = event->type() == QEvent::MouseButtonPress;
            updateTouchLatch();
        }
        break;
    }
    default:
        break;
    }
    return false;
}

} // namespace opencruise
