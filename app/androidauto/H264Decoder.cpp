/**
 * @file H264Decoder.cpp
 * @brief H264Decoder の実装。
 */
#include "H264Decoder.h"

#include <cstring>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
}

namespace opencruise {

/**
 * @brief コーデックを開く。
 */
H264Decoder::H264Decoder(FrameCallback callback) : callback_(std::move(callback)) {
    std::lock_guard<std::mutex> lock(mutex_);
    openLocked();
}

/**
 * @brief リソースを解放する。
 */
H264Decoder::~H264Decoder() {
    std::lock_guard<std::mutex> lock(mutex_);
    closeLocked();
}

/**
 * @brief デコーダが使えるか。
 */
bool H264Decoder::isReady() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return context_ != nullptr;
}

/**
 * @brief 初期化失敗の理由。
 */
QString H264Decoder::errorString() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return error_;
}

/**
 * @brief コーデックを開き直して状態を初期化する。
 */
void H264Decoder::reset() {
    std::lock_guard<std::mutex> lock(mutex_);
    closeLocked();
    openLocked();
}

/**
 * @brief libavcodec の H.264 デコーダを低遅延設定で開く。
 */
bool H264Decoder::openLocked() {
    const AVCodec *codec = avcodec_find_decoder(AV_CODEC_ID_H264);
    if (codec == nullptr) {
        error_ = QStringLiteral("FFmpeg has no H.264 decoder");
        return false;
    }
    context_ = avcodec_alloc_context3(codec);
    frame_ = av_frame_alloc();
    packet_ = av_packet_alloc();
    if (context_ == nullptr || frame_ == nullptr || packet_ == nullptr) {
        error_ = QStringLiteral("FFmpeg memory allocation failed");
        closeLocked();
        return false;
    }
    context_->flags |= AV_CODEC_FLAG_LOW_DELAY;
    context_->thread_count = 1; // フレームスレッドは遅延が増えるので使わない
    if (avcodec_open2(context_, codec, nullptr) < 0) {
        error_ = QStringLiteral("Could not open the H.264 decoder");
        closeLocked();
        return false;
    }
    error_.clear();
    return true;
}

/**
 * @brief 確保済みの FFmpeg オブジェクトをすべて解放する。
 */
void H264Decoder::closeLocked() {
    if (scaler_ != nullptr) {
        sws_freeContext(scaler_);
        scaler_ = nullptr;
    }
    av_packet_free(&packet_);
    av_frame_free(&frame_);
    avcodec_free_context(&context_);
}

/**
 * @brief 1アクセスユニットを送り、出てきたフレームを BGRA→QImage に変換して通知する。
 */
void H264Decoder::decode(const std::uint8_t *data, std::size_t size) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (context_ == nullptr || size == 0) {
        return;
    }
    // av_new_packet はパディング付きで確保するため、入力バッファの余白を気にしなくてよい
    if (av_new_packet(packet_, static_cast<int>(size)) < 0) {
        return;
    }
    std::memcpy(packet_->data, data, size);
    const int sendResult = avcodec_send_packet(context_, packet_);
    av_packet_unref(packet_);
    if (sendResult < 0 && sendResult != AVERROR(EAGAIN)) {
        return; // 壊れたデータ。次のアクセスユニットで回復を試みる
    }

    while (avcodec_receive_frame(context_, frame_) == 0) {
        const int width = frame_->width;
        const int height = frame_->height;
        scaler_ = sws_getCachedContext(scaler_, width, height, static_cast<AVPixelFormat>(frame_->format), width,
                                       height, AV_PIX_FMT_BGRA, SWS_FAST_BILINEAR, nullptr, nullptr, nullptr);
        if (scaler_ != nullptr) {
            QImage image(width, height, QImage::Format_RGB32); // リトルエンディアンで BGRA と同じ並び
            std::uint8_t *dst[4] = {image.bits(), nullptr, nullptr, nullptr};
            int dstStride[4] = {static_cast<int>(image.bytesPerLine()), 0, 0, 0};
            sws_scale(scaler_, frame_->data, frame_->linesize, 0, height, dst, dstStride);
            if (callback_) {
                callback_(image);
            }
        }
        av_frame_unref(frame_);
    }
}

} // namespace opencruise
