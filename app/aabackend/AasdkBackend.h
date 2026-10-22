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
#include "StreamSettings.h"
#include "TouchEvent.h"
#include "VehicleSnapshot.h"

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
    /// PCM 音声(16bit)を受信したとき。第1引数は 0=System / 1=Media / 2=Guidance。
    /// 形式は Media が 48kHz/2ch、それ以外は 16kHz/1ch
    std::function<void(int, const std::uint8_t *, std::size_t)> onAudioData;
    /// 音声ストリームが止まったとき（引数は上と同じチャネル番号）
    std::function<void(int)> onAudioStop;
    /// スマートフォンがマイクを開いた(true)/閉じた(false)。セッション終了時は、開いていれば false で通知される
    std::function<void(bool)> onMicrophoneRequest;
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
     * @param settings 映像設定（解像度・fps）。このインスタンスの寿命の間は固定。変更時は作り直す
     */
    explicit AasdkBackend(BackendCallbacks callbacks, StreamSettings settings = {});

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
     * @brief 昼夜モードを設定する。接続中なら Android Auto へ即時に送り、以後の接続にも引き継ぐ。
     *        どのスレッドからでも呼べる。
     */
    void setNightMode(bool night);

    /**
     * @brief 車両の状態を Android Auto へ送る。どのスレッドからでも呼べる。
     *
     * スマートフォンが開始要求を出したセンサー(速度・回転数・燃料・ギア・パーキングブレーキ・位置)だけが送られる。
     * 未接続・センサー開始前は、エラーにせず捨てる。
     */
    void sendVehicleData(const VehicleSnapshot &snapshot);

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

    /**
     * @brief 録音した PCM(16kHz / 16bit / 1ch)を、接続中のスマートフォンへ送る。どのスレッドからでも呼べる。
     *
     * スマートフォンがマイクを開いていない間・未接続・停止中に呼ばれたデータは、エラーにせず捨てる。
     */
    void sendMicrophoneData(const std::uint8_t *data, std::size_t size);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace opencruise::aa
