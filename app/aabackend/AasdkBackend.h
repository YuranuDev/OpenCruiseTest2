/**
 * @file AasdkBackend.h
 * @brief aasdk を使った Android Auto 接続処理の公開インターフェース。
 *
 * このヘッダは Qt にも aasdk/boost にも依存しない。UI 側 (androidauto/) はこのクラスだけを
 * 見ればよく、aasdk が使えない環境ではスタブ実装 (AasdkBackendStub.cpp) に差し替わる。
 */
#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>

#include "LinkState.h"
#include "TouchEvent.h"

namespace opencruise::aa {

/**
 * @brief 接続層から UI 側へ通知するコールバック群。
 *
 * @warning すべて接続層のワーカースレッドから呼ばれる（UI スレッドではない）。
 *          受け取り側でスレッドを跨いで処理すること。
 */
struct BackendCallbacks {
    /// 接続状態が変わったとき。第2引数は人が読める詳細メッセージ
    std::function<void(LinkState, const std::string &)> onStateChanged;
    /// 映像データ（H.264 Annex-B の 1 アクセスユニット）を受信したとき
    std::function<void(const std::uint8_t *, std::size_t)> onVideoData;
    /// 診断ログ
    std::function<void(const std::string &)> onLog;
};

/**
 * @brief Android Auto 接続処理（USB 検出 → AOAP → セッション確立 → 映像受信）の窓口。
 */
class AasdkBackend {
public:
    /**
     * @brief コールバックを登録してインスタンスを作る。まだ何も開始しない。
     * @param callbacks 通知先
     */
    explicit AasdkBackend(BackendCallbacks callbacks);

    /**
     * @brief 実行中なら停止してから破棄する。
     */
    ~AasdkBackend();

    AasdkBackend(const AasdkBackend &) = delete;
    AasdkBackend &operator=(const AasdkBackend &) = delete;

    /**
     * @brief スマートフォンの接続待ちを開始する。
     * @param[out] errorMessage 失敗時の理由（人が読める文字列）
     * @return 開始できたら true。false の場合でもアプリ全体は動作を続けられる
     */
    bool start(std::string &errorMessage);

    /**
     * @brief 接続待ち・セッションを停止し、スレッドと USB リソースを解放する。
     */
    void stop();

    /**
     * @brief start() 済みで stop() されていなければ true。
     */
    bool isRunning() const;

    /**
     * @brief タッチ入力を、接続中のスマートフォンへ送る。
     *
     * 座標は kTouchWidth x kTouchHeight の座標系で渡すこと。UI スレッドなど任意のスレッドから呼べる。
     * 停止中・未接続・入力チャネルの準備前に呼ばれた入力は、エラーにせず捨てる。
     * @param event タッチ入力
     */
    void sendTouch(const TouchEvent &event);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace opencruise::aa
