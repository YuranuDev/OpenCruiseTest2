/**
 * @file H264Decoder.h
 * @brief OpenH264(libopenh264) による H.264 デコーダ。
 *
 * aasdk は H.264 のデコードを提供しない。Android Auto から受け取る映像データ
 * (Annex-B 形式の 1 アクセスユニット) を QImage に変換するために必要。
 */
#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <mutex>
#include <vector>

#include <QImage>
#include <QString>

class ISVCDecoder; // OpenH264(wels/codec_api.h)。ヘッダを公開しないため前方宣言だけにする

namespace opencruise {

/**
 * @brief 1アクセスユニットずつ入力し、デコードできたフレームをコールバックで返す。
 *
 * 入力は「1回の decode() = 1アクセスユニット」を前提とする（パーサは使わない）。
 * パーサ経由だと次フレームの先頭が来るまで出力が保留され、画面が静止している間
 * 最後の更新が表示されない問題が出るため。スレッドセーフ(内部ミューテックス)。
 */
class H264Decoder {
public:
    using FrameCallback = std::function<void(const QImage &)>;

    /**
     * @brief デコーダを初期化する。失敗しても例外は投げず isReady() が false になる。
     * @param callback フレームがデコードされるたびに呼ばれる（decode() を呼んだスレッドで、ロック中に）
     */
    explicit H264Decoder(FrameCallback callback);

    /** @brief OpenH264 のデコーダを解放する。 */
    ~H264Decoder();

    H264Decoder(const H264Decoder &) = delete;
    H264Decoder &operator=(const H264Decoder &) = delete;

    /** @brief デコーダが使える状態か。 */
    bool isReady() const;

    /** @brief 初期化失敗時の理由。 */
    QString errorString() const;

    /**
     * @brief 新しいセッション開始時に呼び、内部状態（参照フレーム等）を破棄する。
     */
    void reset();

    /**
     * @brief 1アクセスユニットをデコードする。壊れたデータは無視して継続する。
     * @param data Annex-B 形式のデータ
     * @param size バイト数
     */
    void decode(const std::uint8_t *data, std::size_t size);

private:
    /** @brief コーデックを開く（ロック済みで呼ぶ）。 */
    bool openLocked();
    /** @brief コーデックを閉じる（ロック済みで呼ぶ）。 */
    void closeLocked();

    mutable std::mutex mutex_;
    FrameCallback callback_;
    ISVCDecoder *decoder_ = nullptr;
    std::vector<std::uint8_t> input_; // OpenH264 に渡す入力(末尾に余白を付けて渡す)
    QString error_;
};

} // namespace opencruise
