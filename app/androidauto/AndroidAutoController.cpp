/**
 * @file AndroidAutoController.cpp
 * @brief AndroidAutoController の実装。
 */
#include "AndroidAutoController.h"

#include <QDebug>
#include <QImage>
#include <QMetaObject>

#include "VideoSurfaceItem.h"

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
AndroidAutoController::AndroidAutoController(QObject *parent)
    : QObject(parent),
      decoder_([this](const QImage &image) { handleDecodedFrame(image); }),
      testFeeder_([this](const std::uint8_t *data, std::size_t size) { handleVideoData(data, size); }) {
    stateKey_ = keyFor(aa::LinkState::Unavailable);
    stateText_ = textFor(aa::LinkState::Unavailable);
    detailText_ = QStringLiteral("接続処理は開始されていません");
    if (!decoder_.isReady()) {
        lastIssue_ = QStringLiteral("映像デコーダ: ") + decoder_.errorString();
    }
}

/**
 * @brief 停止してから破棄する。
 */
AndroidAutoController::~AndroidAutoController() { stop(); }

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
    {
        std::lock_guard<std::mutex> lock(surfaceMutex_);
        surface_ = surface;
    }
    if (surface != nullptr) {
        connect(surface, &QObject::destroyed, this, [this]() {
            std::lock_guard<std::mutex> lock(surfaceMutex_);
            surface_ = nullptr;
        });
    }
}

/**
 * @brief 接続層を生成して接続待ちを開始する。失敗時は「利用不可」として UI に出す。
 */
void AndroidAutoController::start() {
    if (backend_ && backend_->isRunning()) {
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
    callbacks.onLog = [](const std::string &message) { qInfo().noquote() << "[aa]" << QString::fromStdString(message); };

    backend_ = std::make_unique<aa::AasdkBackend>(std::move(callbacks));
    std::string error;
    if (!backend_->start(error)) {
        qWarning().noquote() << "[aa] 接続処理を開始できません:" << QString::fromStdString(error);
        applyState(static_cast<int>(aa::LinkState::Unavailable), QString::fromStdString(error));
    }
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

    const bool wasActive = previous == aa::LinkState::Connecting || previous == aa::LinkState::Connected ||
                           previous == aa::LinkState::Streaming;
    const bool dropped = (link == aa::LinkState::Waiting && wasActive) || link == aa::LinkState::Unavailable;
    if (dropped && lastIssue_ != detail) {
        lastIssue_ = detail;
        emit lastIssueChanged();
    }

    if (link == aa::LinkState::Waiting || link == aa::LinkState::Connecting || link == aa::LinkState::Unavailable) {
        decoder_.reset();
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
    qInfo().noquote() << "[aa] 状態:" << stateText_ << "-" << detail;
    emit stateChanged();
}

/**
 * @brief 映像データをデコーダへ渡す（接続層スレッド/テスト送出スレッドで実行される）。
 */
void AndroidAutoController::handleVideoData(const std::uint8_t *data, std::size_t size) {
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
