/**
 * @file VideoSurfaceItem.cpp
 * @brief VideoSurfaceItem の実装。
 */
#include "VideoSurfaceItem.h"

#include <QPainter>

namespace opencruise {

/**
 * @brief 黒背景で描画するアイテムを作る。
 */
VideoSurfaceItem::VideoSurfaceItem(QQuickItem *parent) : QQuickPaintedItem(parent) {
    setAntialiasing(false);
    setRenderTarget(QQuickPaintedItem::FramebufferObject);
}

/**
 * @brief 黒で塗りつぶし、映像があれば縦横比を保って中央に拡大縮小描画する。
 */
void VideoSurfaceItem::paint(QPainter *painter) {
    painter->fillRect(boundingRect(), Qt::black);
    if (current_.isNull()) {
        return;
    }
    const QSizeF scaled = QSizeF(current_.size()).scaled(size(), Qt::KeepAspectRatio);
    const QRectF target(QPointF((width() - scaled.width()) / 2.0, (height() - scaled.height()) / 2.0), scaled);
    painter->setRenderHint(QPainter::SmoothPixmapTransform, true);
    painter->drawImage(target, current_);
}

/**
 * @brief 最新フレームを保存し、GUI スレッドでの取り込みを(未予約なら)予約する。
 */
void VideoSurfaceItem::submitFrame(const QImage &image) {
    {
        std::lock_guard<std::mutex> lock(mutex_);
        pending_ = image;
    }
    if (!applyQueued_.exchange(true)) {
        QMetaObject::invokeMethod(this, &VideoSurfaceItem::applyPending, Qt::QueuedConnection);
    }
}

/**
 * @brief 待機中フレームを current_ に移して再描画する。
 */
void VideoSurfaceItem::applyPending() {
    {
        std::lock_guard<std::mutex> lock(mutex_);
        current_ = std::move(pending_);
        pending_ = QImage();
    }
    applyQueued_ = false;
    if (!hasFrame_ && !current_.isNull()) {
        hasFrame_ = true;
        emit hasFrameChanged();
    }
    update();
}

/**
 * @brief 表示と待機中フレームを破棄する。
 */
void VideoSurfaceItem::clear() {
    {
        std::lock_guard<std::mutex> lock(mutex_);
        pending_ = QImage();
    }
    current_ = QImage();
    if (hasFrame_) {
        hasFrame_ = false;
        emit hasFrameChanged();
    }
    update();
}

} // namespace opencruise
