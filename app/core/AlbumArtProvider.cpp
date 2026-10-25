/**
 * @file AlbumArtProvider.cpp
 * @brief ジャケット画像の画像プロバイダーの実装。
 */
#include "AlbumArtProvider.h"

#include "PhoneStatus.h"

#include <QPainter>
#include <QPainterPath>

#include <algorithm>

namespace opencruise {

AlbumArtProvider::AlbumArtProvider(const PhoneStatus *status)
    : QQuickImageProvider(QQuickImageProvider::Image), status_(status) {}

QImage AlbumArtProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize) {
    Q_UNUSED(id)
    const QImage src = status_ ? status_->albumArt() : QImage();
    if (src.isNull()) {
        if (size) {
            *size = QSize();
        }
        return QImage();
    }

    // 出す大きさ: 指定があればその長いほうの辺、無ければ元画像の短いほうの辺(どちらも 1024 px まで)
    int side = requestedSize.isValid() && !requestedSize.isEmpty()
                   ? std::max(requestedSize.width(), requestedSize.height())
                   : std::min(src.width(), src.height());
    side = std::clamp(side, 1, 1024);

    // 中央の正方形を切り抜く
    const int crop = std::min(src.width(), src.height());
    const QRect srcRect((src.width() - crop) / 2, (src.height() - crop) / 2, crop, crop);

    QImage out(side, side, QImage::Format_ARGB32_Premultiplied);
    out.fill(Qt::transparent);
    {
        QPainter p(&out);
        p.setRenderHint(QPainter::Antialiasing, true);
        p.setRenderHint(QPainter::SmoothPixmapTransform, true);
        QPainterPath clip;
        const qreal radius = side * 0.14;
        clip.addRoundedRect(QRectF(0, 0, side, side), radius, radius);
        p.setClipPath(clip);
        p.drawImage(QRect(0, 0, side, side), src, srcRect);
    }
    if (size) {
        *size = out.size();
    }
    return out;
}

} // namespace opencruise
