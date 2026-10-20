/**
 * @file AasdkConfig.h
 * @brief Android Auto に対して車載機として申告する設定値。
 *
 * 値は暫定。実機での挙動確認後に調整する前提で、1か所にまとめている。
 */
#pragma once

#include <cstdint>

namespace opencruise::aa::config {

/// 車載機のメーカー名（ServiceDiscoveryResponse の headunit_info に設定）
inline constexpr const char *kHeadUnitMake = "OpenCruise";
/// 車載機のモデル名
inline constexpr const char *kHeadUnitModel = "OpenCruise Prototype";
/// 車載機のソフトウェアバージョン
inline constexpr const char *kHeadUnitSoftwareVersion = "0.1.0";
/// 車載機のソフトウェアビルド
inline constexpr const char *kHeadUnitSoftwareBuild = "1";
/// 車両の年式 / 識別子（OpenAuto と同様に申告する）
inline constexpr const char *kVehicleYear = "2018";
inline constexpr const char *kVehicleId = "OpenCruise-0001";
/// スマートフォン側に表示される名称
inline constexpr const char *kDisplayName = "OpenCruise";

/// 映像の画素密度(dpi)。800x480 向けの暫定値（実機未検証）
inline constexpr std::uint32_t kVideoDensityDpi = 140;

/// 映像チャネルの未ACK許容数。1 にして 1フレームごとに ACK を返す
inline constexpr std::uint32_t kVideoMaxUnacked = 1;

/// 同時に走らせる aasdk 用 io スレッド数（USBHub の sleep 対策で 2 本以上にする）
inline constexpr int kIoThreadCount = 2;

/// セッション終了後に待機を再開するまでの待ち時間（ミリ秒）。即時再接続ループの抑止用
inline constexpr int kRetryDelayMs = 2000;

} // namespace opencruise::aa::config
