/**
 * @file StreamSettings.h
 * @brief Android Auto へ申告する映像設定（解像度・fps）。Qt / aasdk 非依存。
 */
#pragma once

#include <cstdint>

#include "AasdkConfig.h"

namespace opencruise::aa {

/// 選択可能な解像度の数
inline constexpr int kResolutionCount = 3;

/**
 * @brief 映像設定。resolution は 0=800x480 / 1=1280x720 / 2=1920x1080、fps は 30 か 60。
 */
struct StreamSettings {
    int resolution = 0;
    int fps = 30;

    /// 範囲外の値を既定値へ丸めた設定を返す
    StreamSettings sanitized() const {
        StreamSettings s = *this;
        if (s.resolution < 0 || s.resolution >= kResolutionCount) s.resolution = 0;
        if (s.fps != 60) s.fps = 30;
        return s;
    }
    /// 映像の幅(画素)。タッチ座標系の幅も同じ値にする
    std::int32_t width() const {
        switch (sanitized().resolution) {
        case 1: return 1280;
        case 2: return 1920;
        default: return 800;
        }
    }
    /// 映像の高さ(画素)
    std::int32_t height() const {
        switch (sanitized().resolution) {
        case 1: return 720;
        case 2: return 1080;
        default: return 480;
        }
    }
    /// 解像度に合わせた画素密度(dpi)。暫定値（実機未検証）
    std::uint32_t densityDpi() const {
        switch (sanitized().resolution) {
        case 1: return 160;
        case 2: return 240;
        default: return config::kVideoDensityDpi;
        }
    }
    bool operator==(const StreamSettings &o) const { return resolution == o.resolution && fps == o.fps; }
    bool operator!=(const StreamSettings &o) const { return !(*this == o); }
};

} // namespace opencruise::aa
