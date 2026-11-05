/**
 * @file TouchEvent.h
 * @brief タッチ入力を UI 側から接続層へ渡すための型（Qt・aasdk のどちらにも依存しない）。
 *
 * 座標は Android Auto のタッチ座標系 (kTouchWidth x kTouchHeight) で表す。
 * この大きさは Service Discovery でスマートフォンへ申告するタッチ領域であり、
 * 映像サービス (VIDEO_800x480) の解像度と一致させている。
 * Qt 側(VideoSurfaceItem)が画面上の位置をこの座標系へ変換してから渡す。
 */
#pragma once

#include <cstdint>
#include <vector>

namespace opencruise::aa {

/// タッチ領域の幅(画素)。映像解像度と一致させる
inline constexpr std::int32_t kTouchWidth = 800;
/// タッチ領域の高さ(画素)。映像解像度と一致させる
inline constexpr std::int32_t kTouchHeight = 480;

/**
 * @brief タッチ操作の種類（Android の MotionEvent に対応する）。
 */
enum class TouchAction {
    Down,        ///< 最初の指が触れた
    Up,          ///< 最後の指が離れた
    Move,        ///< 指が動いた
    PointerDown, ///< 2 本目以降の指が触れた
    PointerUp    ///< 2 本目以降の指が離れた(まだ他の指は触れている)
};

/**
 * @brief 1 本の指の状態。
 */
struct TouchPoint {
    std::uint32_t id; ///< 指の識別子（触れている間は変わらない）
    std::int32_t x;   ///< 0 .. kTouchWidth-1
    std::int32_t y;   ///< 0 .. kTouchHeight-1
};

/**
 * @brief 1 回のタッチ通知。
 *
 * points には、この時点で触れているすべての指を入れる。Up / PointerUp の場合は、
 * 離れる指もその最後の位置で points に含める（Android の MotionEvent と同じ）。
 */
struct TouchEvent {
    TouchAction action = TouchAction::Move;
    std::uint32_t actionIndex = 0; ///< 状態が変化した指の points 内での位置
    std::vector<TouchPoint> points;
};

} // namespace opencruise::aa
