/**
 * @file AlbumArtProvider.h
 * @brief 再生中の曲のジャケット画像を QML に渡す画像プロバイダー(image://albumart/<番号>)。
 *
 * PhoneStatus が受け取った画像を、QML の Image が指定した大きさ(sourceSize)の正方形に、中央で切り抜いて返す。
 * 角は丸める(半径は一辺の 14%。再生中ウィジェットのタイルと同じ)。角の外側は透明。
 * 番号は画像が変わるたびに PhoneStatus が増やすだけで、中身には使わない(QML に読み直させるため)。
 */
#pragma once

#include <QQuickImageProvider>

namespace opencruise {

class PhoneStatus;

class AlbumArtProvider : public QQuickImageProvider {
public:
    explicit AlbumArtProvider(const PhoneStatus *status);

    /** @brief 画像の読み込みスレッドから呼ばれる。画像が無ければ空の QImage を返す。 */
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;

private:
    const PhoneStatus *status_;
};

} // namespace opencruise
