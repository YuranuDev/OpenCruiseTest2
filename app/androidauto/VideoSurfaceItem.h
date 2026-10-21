/**
 * @file VideoSurfaceItem.h
 * @brief Android Auto の映像を描画し、その上へのタッチ/マウス操作を受け取る QML アイテム。
 */
#pragma once

#include <atomic>
#include <functional>
#include <mutex>

#include <QImage>
#include <QQuickPaintedItem>
#include <QRectF>
#include <QtQml/qqmlregistration.h>

#include "TouchEvent.h"
#include "TouchTracker.h"

class QMouseEvent;
class QTouchEvent;

namespace opencruise {

/**
 * @brief QImage を縦横比を保って中央に描画する。ソフトウェア描画のプロトタイプ実装。
 *
 * submitFrame() は任意のスレッドから呼べる。描画が追いつかない場合は古いフレームを捨て、
 * 常に最新フレームだけを表示する。
 *
 * タッチ(マルチタッチ)とマウス左ボタンの操作を、映像上の位置に合わせて Android Auto の
 * タッチ座標系(aa::kTouchWidth x aa::kTouchHeight)へ変換し、setTouchSink() で登録された
 * 送り先へ渡す。映像が表示されていない間、および映像の外(黒帯)で始まった操作は無視する。
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

    /**
     * @brief タッチ入力の送り先を登録する（GUI スレッドから呼ぶ）。nullptr で解除。
     *
     * 解除・差し替えの時点で触れている指があれば、先に「離した」ことにして古い送り先へ通知する。
     */
    void setTouchSink(TouchTracker::Sink sink);

    /**
     * @brief 映像が実際に描画されている矩形（アイテム座標）。縦横比を保って中央に置いたもの。
     *
     * フレームがまだ無い間は、タッチ座標系と同じ縦横比で見積もる。paint() と座標変換で共通に使う。
     */
    QRectF videoRect() const;

    /**
     * @brief アイテム上の位置を Android Auto のタッチ座標へ変換する。
     * @param position アイテム座標での位置
     * @param allowOutside false なら映像の外（黒帯）の位置は失敗にする。
     *                     true なら映像の端に丸めて成功にする（指が映像の外へ動いた場合用）
     * @param[out] x,y 0..kTouchWidth-1 / 0..kTouchHeight-1 の座標
     * @return 変換できたら true
     */
    bool mapToTouch(const QPointF &position, bool allowOutside, int &x, int &y) const;

signals:
    /** @brief hasFrame が変化したとき。 */
    void hasFrameChanged();

protected:
    /** @brief タッチ操作（複数の指に対応）を受け取る。 */
    void touchEvent(QTouchEvent *event) override;
    /** @brief タッチの取得権を失ったとき、触れている指をすべて離した扱いにする。 */
    void touchUngrabEvent() override;
    /** @brief マウス左ボタンの操作を 1 本の指として扱う。 */
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    /** @brief マウスの取得権を失ったとき、マウスの指を離した扱いにする。 */
    void mouseUngrabEvent() override;

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

    TouchTracker touchTracker_; ///< GUI スレッドでのみ触る
};

} // namespace opencruise
