/**
 * @file SystemSound.cpp
 * @brief SystemSound の実装(効果音フォルダの一覧・選択・再生)。
 */
#include "SystemSound.h"

#include <QCoreApplication>
#include <QDir>
#include <QEvent>
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

namespace opencruise {

namespace {
constexpr qint64 kClickMinIntervalMs = 70; ///< 操作音を連打したときの最短間隔

const QString kNone = QStringLiteral("none");
const QString kBuiltinPrefix = QStringLiteral("builtin:");
const QString kUserPrefix = QStringLiteral("user:");
const QStringList kCategories = {QStringLiteral("click"), QStringLiteral("start"), QStringLiteral("alert")};

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
        if (!alertMuted_) {
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
