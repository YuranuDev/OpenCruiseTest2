/**
 * @file LinkState.h
 * @brief Android Auto 接続状態の定義（Qt・aasdk のどちらにも依存しない）。
 *
 * 接続層 (aabackend) と Qt 側 (androidauto) の間で共有する唯一の型。
 */
#pragma once

namespace opencruise::aa {

/**
 * @brief Android Auto との接続状態。
 */
enum class LinkState {
    Unavailable, ///< 接続処理自体が使えない（aasdk 無効ビルド、libusb 初期化失敗など）
    Waiting,     ///< スマートフォンの接続待ち（待機状態）
    Connecting,  ///< スマートフォンを検出し、ハンドシェイク/サービス探索中
    Connected,   ///< 制御チャネルの確立完了。映像はまだ来ていない
    Streaming    ///< 映像データを受信中
};

} // namespace opencruise::aa
