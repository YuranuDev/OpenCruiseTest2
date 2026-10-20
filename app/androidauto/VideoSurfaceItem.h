/**
 * @file VideoSurfaceItem.h
 * @brief Android Auto の映像を描画する QML アイテム。
 */
#pragma once

#include <atomic>
#include <mutex>

#include <QImage>
#include <QQuickPaintedItem>
#include <QtQml/qqmlregistration.h>

namespace opencruise {

/**
 * @brief QImage を縦横比を保って中央に描画する。ソフトウェア描画のプロトタイプ実装。
 *
 * submitFrame() は任意のスレッドから呼べる。描画が追いつかない場合は古いフレームを捨て、
 * 常に最新フレームだけを表示する。
 */
class VideoSurfaceItem : public QQuickPaintedItem {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool hasFrame READ hasFrame NOTIFY hasFrameChanged)

public:
    /**
     * @brief アイテムを作る。
     * @param parent 親アイテム
     */
    explicit VideoSurfaceItem(QQuickItem *parent = nullptr);

    /**
     * @brief 現在のフレームを描画する（QQuickPaintedItem の描画フック）。
     * @param painter 描画先
     */
    void paint(QPainter *painter) override;

    /**
     * @brief 新しいフレームを渡す。スレッドセーフ。
     * @param image 表示する画像
     */
    void submitFrame(const QImage &image);

    /**
     * @brief 表示中のフレームを消す。GUI スレッドから呼ぶこと。
     */
    Q_INVOKABLE void clear();

    /** @brief 1枚でもフレームを表示しているか。 */
    bool hasFrame() const { return hasFrame_; }

signals:
    /** @brief hasFrame が変化したとき。 */
    void hasFrameChanged();

private:
    /**
     * @brief 待機中の最新フレームを表示用に取り込み、再描画を要求する（GUI スレッド）。
     */
    void applyPending();

    std::mutex mutex_;
    QImage pending_;                      ///< 他スレッドから渡された最新フレーム
    std::atomic<bool> applyQueued_{false}; ///< applyPending が投げ済みか
    QImage current_;                      ///< GUI スレッドで描画中のフレーム
    bool hasFrame_ = false;
};

} // namespace opencruise
