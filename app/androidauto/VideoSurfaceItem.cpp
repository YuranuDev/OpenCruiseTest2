/**
 * @file VideoSurfaceItem.cpp
 * @brief VideoSurfaceItem の実装。
 */
#include "VideoSurfaceItem.h"

#include <algorithm>

#include <QMouseEvent>
#include <QPainter>
#include <QTouchEvent>

namespace opencruise {

namespace {
/// マウスを「1 本の指」として追跡するときの識別子。Qt のタッチ ID は 0 以上なので衝突しない
constexpr int kMouseSourceId = -1;
} // namespace

/**
 * @brief 黒背景で描画するアイテムを作る。
 */
VideoSurfaceItem::VideoSurfaceItem(QQuickItem *parent) : QQuickPaintedItem(parent) {
    setAntialiasing(false);
    setRenderTarget(QQuickPaintedItem::FramebufferObject);
    setAcceptTouchEvents(true);
    setAcceptedMouseButtons(Qt::LeftButton);
}

/**
 * @brief 黒で塗りつぶし、映像があれば縦横比を保って中央に拡大縮小描画する。
 */
void VideoSurfaceItem::paint(QPainter *painter) {
    painter->fillRect(boundingRect(), Qt::black);
    if (current_.isNull()) {
        return;
    }
    painter->setRenderHint(QPainter::SmoothPixmapTransform, true);
    painter->drawImage(videoRect(), current_);
}

/**
 * @brief 縦横比を保ってアイテムの中央に収めた映像の矩形を返す。
 */
QRectF VideoSurfaceItem::videoRect() const {
    const QSizeF source = current_.isNull() ? QSizeF(aa::kTouchWidth, aa::kTouchHeight) : QSizeF(current_.size());
    const QSizeF scaled = source.scaled(size(), Qt::KeepAspectRatio);
    return QRectF(QPointF((width() - scaled.width()) / 2.0, (height() - scaled.height()) / 2.0), scaled);
}

/**
 * @brief 映像矩形の中での相対位置を、タッチ座標系へ変換する。
 */
bool VideoSurfaceItem::mapToTouch(const QPointF &position, bool allowOutside, int &x, int &y) const {
    const QRectF rect = videoRect();
    if (rect.width() <= 0.0 || rect.height() <= 0.0) {
        return false;
    }
    if (!allowOutside && !rect.contains(position)) {
        return false;
    }
    const double nx = std::clamp((position.x() - rect.left()) / rect.width(), 0.0, 1.0);
    const double ny = std::clamp((position.y() - rect.top()) / rect.height(), 0.0, 1.0);
    x = std::min(static_cast<int>(nx * aa::kTouchWidth), aa::kTouchWidth - 1);
    y = std::min(static_cast<int>(ny * aa::kTouchHeight), aa::kTouchHeight - 1);
    return true;
}

/**
 * @brief 送り先を差し替える。触れたままの指は、古い送り先へ先に「離した」と伝える。
 */
void VideoSurfaceItem::setTouchSink(TouchTracker::Sink sink) {
    touchTracker_.releaseAll();
    touchTracker_.setSink(std::move(sink));
}

/**
 * @brief 触れている指の位置更新 → 新しく触れた指 → 離れた指 の順に処理する。
 *
 * 映像が出ていない間と、映像の外で触れ始めた指は無視する（イベントも受け取らない）。
 * 受け取った指があれば accept して、以降の移動・終了も受け取れるようにする。
 */
void VideoSurfaceItem::touchEvent(QTouchEvent *event) {
    if (event->type() == QEvent::TouchCancel) {
        touchTracker_.releaseAll();
        event->accept();
        return;
    }
    if (event->type() != QEvent::TouchBegin && event->type() != QEvent::TouchUpdate &&
        event->type() != QEvent::TouchEnd) {
        QQuickPaintedItem::touchEvent(event);
        return;
    }

    bool handled = false;
    int x = 0;
    int y = 0;
    const auto &points = event->points();

    for (const QEventPoint &point : points) {
        if (point.state() == QEventPoint::Updated && touchTracker_.isActive(point.id()) &&
            mapToTouch(point.position(), true, x, y)) {
            touchTracker_.move(point.id(), x, y);
            handled = true;
        }
    }
    touchTracker_.flush();

    for (const QEventPoint &point : points) {
        if (point.state() == QEventPoint::Pressed && hasFrame_ && mapToTouch(point.position(), false, x, y) &&
            touchTracker_.press(point.id(), x, y)) {
            handled = true;
        }
    }
    for (const QEventPoint &point : points) {
        if (point.state() == QEventPoint::Released && touchTracker_.isActive(point.id())) {
            mapToTouch(point.position(), true, x, y);
            touchTracker_.release(point.id(), x, y);
            handled = true;
        }
    }

    if (handled) {
        event->accept();
    } else {
        event->ignore();
    }
}

/**
 * @brief タッチを他のアイテムに奪われた/取り消されたとき、スマートフォンに触れたままの指を残さない。
 */
void VideoSurfaceItem::touchUngrabEvent() { touchTracker_.releaseAll(); }

/**
 * @brief マウス左ボタンを押した位置が映像上なら、1 本の指が触れたものとして扱う。
 */
void VideoSurfaceItem::mousePressEvent(QMouseEvent *event) {
    int x = 0;
    int y = 0;
    if (event->button() != Qt::LeftButton || !hasFrame_ || touchTracker_.isActive(kMouseSourceId) ||
        !mapToTouch(event->position(), false, x, y) || !touchTracker_.press(kMouseSourceId, x, y)) {
        event->ignore();
        return;
    }
    event->accept();
}

/**
 * @brief 押している間の移動を、指の移動として送る（映像の外へ出たら端に丸める）。
 */
void VideoSurfaceItem::mouseMoveEvent(QMouseEvent *event) {
    int x = 0;
    int y = 0;
    if (!touchTracker_.isActive(kMouseSourceId) || !mapToTouch(event->position(), true, x, y)) {
        event->ignore();
        return;
    }
    touchTracker_.move(kMouseSourceId, x, y);
    touchTracker_.flush();
    event->accept();
}

/**
 * @brief ボタンを離したことを、指が離れたものとして送る。
 */
void VideoSurfaceItem::mouseReleaseEvent(QMouseEvent *event) {
    int x = 0;
    int y = 0;
    if (event->button() != Qt::LeftButton || !touchTracker_.isActive(kMouseSourceId)) {
        event->ignore();
        return;
    }
    mapToTouch(event->position(), true, x, y);
    touchTracker_.release(kMouseSourceId, x, y);
    event->accept();
}

/**
 * @brief マウスの取得権を失ったら、マウスの指を離した扱いにする。
 */
void VideoSurfaceItem::mouseUngrabEvent() { touchTracker_.cancel(kMouseSourceId); }

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
    touchTracker_.releaseAll(); // 映像が消えるのに、スマートフォンに触れたままの指を残さない
    if (hasFrame_) {
        hasFrame_ = false;
        emit hasFrameChanged();
    }
    update();
}

} // namespace opencruise
