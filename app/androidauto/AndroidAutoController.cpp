/**
 * @file AndroidAutoController.cpp
 * @brief AndroidAutoController の実装。
 */
#include "AndroidAutoController.h"

#include <QDateTime>
#include <QDebug>
#include <QImage>
#include <QMetaObject>
#include <QSettings>

#include <QTime>

#include "VideoSurfaceItem.h"
#include "core/NotificationManager.h"

namespace opencruise {

namespace {

/**
 * @brief 状態を QML 用のキー文字列へ変換する。
 */
QString keyFor(aa::LinkState state) {
    switch (state) {
    case aa::LinkState::Unavailable: return QStringLiteral("unavailable");
    case aa::LinkState::Waiting: return QStringLiteral("waiting");
    case aa::LinkState::Connecting: return QStringLiteral("connecting");
    case aa::LinkState::Connected: return QStringLiteral("connected");
    case aa::LinkState::Streaming: return QStringLiteral("streaming");
    }
    return QStringLiteral("unavailable");
}

/**
 * @brief 状態を画面表示用の日本語へ変換する。
 */
QString textFor(aa::LinkState state) {
    switch (state) {
    case aa::LinkState::Unavailable: return QStringLiteral("利用不可");
    case aa::LinkState::Waiting: return QStringLiteral("待機中");
    case aa::LinkState::Connecting: return QStringLiteral("接続中");
    case aa::LinkState::Connected: return QStringLiteral("接続済み");
    case aa::LinkState::Streaming: return QStringLiteral("映像受信中");
    }
    return QString();
}

} // namespace

/**
 * @brief デコーダとテスト送出を初期化し、状態を「利用不可」にしておく。
 */
namespace {
/// 自動モードの昼夜判定。簡易的に 6:00〜18:00 を昼とする（日の出日の入りは考慮しない）
bool isNightByClock() {
    const int hour = QTime::currentTime().hour();
    return hour < 6 || hour >= 18;
}
} // namespace

AndroidAutoController::AndroidAutoController(QObject *parent)
    : QObject(parent),
      decoder_([this](const QImage &image) { handleDecodedFrame(image); }),
      testFeeder_([this](const std::uint8_t *data, std::size_t size) { handleVideoData(data, size); }) {
    {
        QSettings store(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"),
                        QStringLiteral("OpenCruise"));
        settings_.resolution = store.value(QStringLiteral("stream/resolution"), 0).toInt();
        settings_.fps = store.value(QStringLiteral("stream/fps"), 30).toInt();
        settings_ = settings_.sanitized();
        fullscreenOnStream_ = store.value(QStringLiteral("ui/fullscreenOnStream"), false).toBool();
        themeMode_ = qBound(0, store.value(QStringLiteral("ui/themeMode"), 2).toInt(), 2);
        accentIndex_ = qMax(0, store.value(QStringLiteral("ui/accentIndex"), 0).toInt());
        aaFollowsTheme_ = store.value(QStringLiteral("ui/aaFollowsTheme"), true).toBool();
    }
    nightActive_ = themeMode_ == 1 || (themeMode_ == 2 && isNightByClock());
    themeTimer_.setInterval(60 * 1000);
    connect(&themeTimer_, &QTimer::timeout, this, [this]() { updateNight(); });
    themeTimer_.start();
    stateKey_ = keyFor(aa::LinkState::Unavailable);
    stateText_ = textFor(aa::LinkState::Unavailable);
    detailText_ = QStringLiteral("接続処理は開始されていません");
    if (!decoder_.isReady()) {
        lastIssue_ = QStringLiteral("映像デコーダ: ") + decoder_.errorString();
    }

    // 接続中/接続済みのまま何も起きない場合に気付けるよう、経過を定期的に記録する。
    connect(&watchdog_, &QTimer::timeout, this, [this]() {
        const auto link = static_cast<aa::LinkState>(currentState_);
        // 接続待ちのままでも「アプリは動いていて状態が変わっていない」ことを記録する
        const qint64 elapsed = startedAtMs_ > 0 ? QDateTime::currentMSecsSinceEpoch() - startedAtMs_ : -1;
        qInfo().noquote() << "[aa] 監視:" << textFor(link) << "のまま" << elapsed << "ms 経過 (受信映像"
                          << videoPackets_.load() << "通 /" << videoBytes_.load() << "バイト, デコード済み"
                          << frameCount_ << "フレーム)";
    });
    watchdog_.start(30000);
}

/**
 * @brief 停止してから破棄する。
 */
AndroidAutoController::~AndroidAutoController() {
    // 描画アイテムが先に破棄されていなければ、this を指すタッチの送り先を外しておく
    VideoSurfaceItem *surface = nullptr;
    {
        std::lock_guard<std::mutex> lock(surfaceMutex_);
        surface = surface_;
        surface_ = nullptr;
    }
    if (surface != nullptr) {
        surface->setTouchSink(nullptr);
    }
    if (restartThread_.joinable()) {
        restartThread_.join();
    }
    stop();
}

/**
 * @brief ビルド時に aasdk が有効かを返す。
 */
bool AndroidAutoController::aasdkEnabled() const {
#ifdef OPENCRUISE_WITH_AASDK
    return true;
#else
    return false;
#endif
}

/**
 * @brief 描画アイテムを登録する。アイテム破棄時に参照を外す。
 */
void AndroidAutoController::attachSurface(VideoSurfaceItem *surface) {
    VideoSurfaceItem *previous = nullptr;
    {
        std::lock_guard<std::mutex> lock(surfaceMutex_);
        previous = surface_;
        surface_ = surface;
    }
    if (previous != nullptr && previous != surface) {
        previous->setTouchSink(nullptr);
    }
    if (surface != nullptr) {
        surface->setTouchSize(settings_.width(), settings_.height());
        surface->setTouchSink([this](const aa::TouchEvent &event) { sendTouch(event); });
        connect(surface, &QObject::destroyed, this, [this]() {
            std::lock_guard<std::mutex> lock(surfaceMutex_);
            surface_ = nullptr;
        });
    }
}

/**
 * @brief タッチ操作を接続層へ渡す。接続層が動いていなければ接続層側で捨てられる。
 */
void AndroidAutoController::sendTouch(const aa::TouchEvent &event) {
    if (backend_) {
        backend_->sendTouch(event);
    }
}

/**
 * @brief 接続層を生成して接続待ちを開始する。失敗時は「利用不可」として UI に出す。
 */
void AndroidAutoController::start() {
    if (restarting_ || (backend_ && backend_->isRunning())) {
        return;
    }

    // 接続層のコールバックはワーカースレッドから来るので、UI 状態の更新は必ずキュー経由にする
    aa::BackendCallbacks callbacks;
    callbacks.onStateChanged = [this](aa::LinkState state, const std::string &detail) {
        QMetaObject::invokeMethod(
            this,
            [this, state, text = QString::fromStdString(detail)]() { applyState(static_cast<int>(state), text); },
            Qt::QueuedConnection);
    };
    callbacks.onVideoData = [this](const std::uint8_t *data, std::size_t size) { handleVideoData(data, size); };
    // 音声もワーカースレッドから来る。PCM をコピーして UI スレッドの再生器へ渡す
    callbacks.onAudioData = [this](int kind, const std::uint8_t *data, std::size_t size) {
        QByteArray pcm(reinterpret_cast<const char *>(data), static_cast<qsizetype>(size));
        QMetaObject::invokeMethod(
            this, [this, kind, pcm]() { audioPlayer_.write(kind, pcm); }, Qt::QueuedConnection);
    };
    callbacks.onAudioStop = [this](int kind) {
        QMetaObject::invokeMethod(this, [this, kind]() { audioPlayer_.stop(kind); }, Qt::QueuedConnection);
    };
    callbacks.onLog = [](const std::string &message) { qInfo().noquote() << "[aa]" << QString::fromStdString(message); };

    backend_ = std::make_unique<aa::AasdkBackend>(std::move(callbacks), settings_);
    backend_->setNightMode(aaFollowsTheme_ && nightActive_); // 接続確立時の初期値としてスマホへ送られる
    std::string error;
    if (!backend_->start(error)) {
        qWarning().noquote() << "[aa] 接続処理を開始できません:" << QString::fromStdString(error);
        applyState(static_cast<int>(aa::LinkState::Unavailable), QString::fromStdString(error));
    }
}

/**
 * @brief 解像度を変更する。
 */
void AndroidAutoController::setResolutionIndex(int index) {
    aa::StreamSettings next = settings_;
    next.resolution = index;
    changeStreamSettings(next);
}

/**
 * @brief fps を変更する。
 */
void AndroidAutoController::setFps(int fps) {
    aa::StreamSettings next = settings_;
    next.fps = fps;
    changeStreamSettings(next);
}

/**
 * @brief フルスクリーン設定を保存する。
 */
void AndroidAutoController::setFullscreenOnStream(bool enabled) {
    if (fullscreenOnStream_ == enabled) {
        return;
    }
    fullscreenOnStream_ = enabled;
    QSettings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"), QStringLiteral("OpenCruise"))
        .setValue(QStringLiteral("ui/fullscreenOnStream"), enabled);
    emit settingsChanged();
}

/**
 * @brief テーマ(昼/夜/自動)を変更して保存する。
 */
void AndroidAutoController::setThemeMode(int mode) {
    mode = qBound(0, mode, 2);
    if (mode == themeMode_) {
        return;
    }
    themeMode_ = mode;
    QSettings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"), QStringLiteral("OpenCruise"))
        .setValue(QStringLiteral("ui/themeMode"), themeMode_);
    emit themeChanged();
    updateNight();
}

/**
 * @brief アクセント色を変更して保存する。
 */
void AndroidAutoController::setAccentIndex(int index) {
    index = qMax(0, index);
    if (index == accentIndex_) {
        return;
    }
    accentIndex_ = index;
    QSettings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"), QStringLiteral("OpenCruise"))
        .setValue(QStringLiteral("ui/accentIndex"), accentIndex_);
    emit themeChanged();
}

/**
 * @brief Android Auto の昼夜をアプリのテーマに連動させるかを変更する。
 */
void AndroidAutoController::setAaFollowsTheme(bool enabled) {
    if (enabled == aaFollowsTheme_) {
        return;
    }
    aaFollowsTheme_ = enabled;
    QSettings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"), QStringLiteral("OpenCruise"))
        .setValue(QStringLiteral("ui/aaFollowsTheme"), aaFollowsTheme_);
    emit themeChanged();
    pushNightToBackend();
}

/**
 * @brief 昼夜を再計算する。変化があれば QML と Android Auto の両方へ反映する。
 */
void AndroidAutoController::updateNight() {
    const bool night = themeMode_ == 1 || (themeMode_ == 2 && isNightByClock());
    if (night == nightActive_) {
        return;
    }
    nightActive_ = night;
    emit themeChanged();
    pushNightToBackend();
}

/**
 * @brief 昼夜を接続層へ渡す。接続中なら NIGHT_MODE センサーとして Android Auto へ即時送信される。
 */
void AndroidAutoController::pushNightToBackend() {
    if (backend_) {
        backend_->setNightMode(aaFollowsTheme_ && nightActive_);
    }
}

/**
 * @brief 映像設定を保存して反映する。動作中の接続層は stop()（ByeBye 送信→応答待ち→切断）してから作り直す。
 *
 * @note 接続層の停止は別スレッドで行うので UI は止まらない。
 */
void AndroidAutoController::changeStreamSettings(const aa::StreamSettings &requested) {
    const aa::StreamSettings next = requested.sanitized();
    if (next == settings_) {
        return;
    }
    settings_ = next;
    {
        QSettings store(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"),
                        QStringLiteral("OpenCruise"));
        store.setValue(QStringLiteral("stream/resolution"), settings_.resolution);
        store.setValue(QStringLiteral("stream/fps"), settings_.fps);
    }
    {
        std::lock_guard<std::mutex> lock(surfaceMutex_);
        if (surface_ != nullptr) {
            surface_->setTouchSize(settings_.width(), settings_.height());
        }
    }
    emit settingsChanged();

    if (backend_ && backend_->isRunning()) {
        qInfo().noquote() << "[aa] 映像設定の変更のため、切断して再接続待機します:" << settings_.width() << "x"
                          << settings_.height() << "@" << settings_.fps << "fps";
        restartBackendAsync();
    }
}

/**
 * @brief 古い接続層を別スレッドで正規に停止し、完了後に最新の設定で接続待ちを再開する。
 */
void AndroidAutoController::restartBackendAsync() {
    if (restarting_ || !backend_) {
        return; // 再起動中なら、完了時の start() が最新の settings_ を使う
    }
    restarting_ = true;
    applyState(static_cast<int>(aa::LinkState::Waiting),
               QStringLiteral("映像設定の変更のため切断しています。再接続を待機します"));
    std::shared_ptr<aa::AasdkBackend> old = std::move(backend_);
    restartThread_ = std::thread([this, old]() mutable {
        old->stop(); // ByeBye 送信→応答待ち→切断（最大数秒）
        old.reset();
        QMetaObject::invokeMethod(
            this,
            [this]() {
                if (restartThread_.joinable()) {
                    restartThread_.join();
                }
                restarting_ = false;
                start();
            },
            Qt::QueuedConnection);
    });
}

/**
 * @brief テスト送出と接続層を停止する。
 */
void AndroidAutoController::stop() {
    testFeeder_.stop();
    if (backend_) {
        backend_->stop();
        backend_.reset();
    }
}

/**
 * @brief 開発用: テスト映像を流し込み、状態を「映像受信中(テスト)」にする。
 */
void AndroidAutoController::playTestStream(const QString &path) {
    QString error;
    if (!testFeeder_.start(path, error)) {
        qWarning().noquote() << "[aa] テスト映像を開始できません:" << error;
        applyState(static_cast<int>(aa::LinkState::Unavailable), error);
        return;
    }
    applyState(static_cast<int>(aa::LinkState::Streaming),
               QStringLiteral("テスト映像を再生中（aasdk 経由ではありません）"));
}

/**
 * @brief UI スレッドで状態を更新する。待機/未接続系に戻る時は映像と統計をリセットする。
 */
void AndroidAutoController::applyState(int state, const QString &detail) {
    const auto link = static_cast<aa::LinkState>(state);
    const auto previous = static_cast<aa::LinkState>(currentState_);
    currentState_ = state;

    if (link == aa::LinkState::Connecting && previous != aa::LinkState::Connecting) {
        ++attemptCount_;
        startedAtMs_ = QDateTime::currentMSecsSinceEpoch();
        videoPackets_ = 0;
        videoBytes_ = 0;
        qInfo().noquote() << "[aa] 接続処理を開始します (試行" << attemptCount_ << "回目)";
    } else if (link == aa::LinkState::Waiting && previous != aa::LinkState::Waiting) {
        videoPackets_ = 0;
        videoBytes_ = 0;
        qInfo().noquote() << "[aa] 待機に戻りました (前回:" << textFor(previous) << ")";
    } else if (link == aa::LinkState::Connected && previous != aa::LinkState::Connected &&
               previous != aa::LinkState::Streaming) {
        // 接続が確立した（Service Discovery 完了）ときに 1 回だけ通知する
        NotificationManager::notify(QStringLiteral("Android Auto に接続しました"),
                                    QStringLiteral("スマートフォンとの接続が確立しました"),
                                    NotificationManager::Success, QStringLiteral("smartphone"));
    }

    const bool wasActive = previous == aa::LinkState::Connecting || previous == aa::LinkState::Connected ||
                           previous == aa::LinkState::Streaming;
    const bool dropped = (link == aa::LinkState::Waiting && wasActive) || link == aa::LinkState::Unavailable;
    if (dropped && lastIssue_ != detail) {
        lastIssue_ = detail;
        emit lastIssueChanged();
    }

    if (link == aa::LinkState::Waiting || link == aa::LinkState::Connecting || link == aa::LinkState::Unavailable) {
        decoder_.reset();
        audioPlayer_.stopAll(); // 切断・再接続時は音声出力も作り直す
        decoderErrorReported_ = false;
        frameCount_ = 0;
        videoInfo_ = QStringLiteral("-");
        emit videoStatsChanged();
        std::lock_guard<std::mutex> lock(surfaceMutex_);
        if (surface_ != nullptr) {
            surface_->clear();
        }
    }

    stateKey_ = keyFor(link);
    stateText_ = textFor(link);
    detailText_ = detail;
    qInfo().noquote() << "[aa] 状態:" << stateText_ << "-" << detail
                      << (startedAtMs_ > 0 ? QStringLiteral("(接続開始から %1 ms)")
                                                 .arg(QDateTime::currentMSecsSinceEpoch() - startedAtMs_)
                                           : QString());
    emit stateChanged();
}

/**
 * @brief 映像データをデコーダへ渡す（接続層スレッド/テスト送出スレッドで実行される）。
 */
void AndroidAutoController::handleVideoData(const std::uint8_t *data, std::size_t size) {
    const qulonglong packets = ++videoPackets_;
    videoBytes_ += static_cast<qulonglong>(size);
    if (packets == 1 || packets % 60 == 0) {
        qInfo().noquote() << "[aa] 映像データを受信しました (累計" << packets << "通 /" << videoBytes_
                          << "バイト, 今回" << size << "バイト)";
    }
    if (!decoder_.isReady()) {
        if (!decoderErrorReported_.exchange(true)) {
            qWarning().noquote() << "[aa] 映像デコーダが使えません:" << decoder_.errorString();
        }
        return;
    }
    decoder_.decode(data, size);
}

/**
 * @brief デコード済みフレームを描画アイテムへ渡す。統計表示は 30 フレームごと(と初回)に更新する。
 */
void AndroidAutoController::handleDecodedFrame(const QImage &image) {
    {
        std::lock_guard<std::mutex> lock(surfaceMutex_);
        if (surface_ != nullptr) {
            surface_->submitFrame(image);
        }
    }
    const qulonglong count = ++frameCount_;
    if (count == 1 || count % 30 == 0) {
        qInfo().noquote() << "[aa] デコード済みフレーム:" << count << "枚目" << image.width() << "x"
                          << image.height();
        const QString info = QStringLiteral("%1 x %2").arg(image.width()).arg(image.height());
        QMetaObject::invokeMethod(
            this,
            [this, info]() {
                videoInfo_ = info;
                emit videoStatsChanged();
            },
            Qt::QueuedConnection);
    }
}

} // namespace opencruise
