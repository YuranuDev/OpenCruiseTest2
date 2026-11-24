/**
 * @file H264Decoder.cpp
 * @brief H264Decoder の実装(OpenH264 によるソフトウェアデコード)。
 */
#include "H264Decoder.h"

#include <algorithm>
#include <array>
#include <cstring>

#include <wels/codec_api.h>

namespace opencruise {

namespace {

/** OpenH264 が入力の末尾を少し先読みしても安全なように付ける余白(バイト)。 */
constexpr std::size_t kInputPadding = 16;

/**
 * @brief YUV(BT.601・リミテッドレンジ)から RGB への変換表。
 *
 * 以前使っていた libswscale の既定(BT.601・リミテッドレンジ)と同じ係数にしてある。
 * 固定小数点(<<8)で、画素ごとの掛け算を表引きにして、1080p でも負荷を抑える。
 */
struct YuvTables {
    std::array<int, 256> y{};   // 298 * (Y - 16)
    std::array<int, 256> vr{};  // 409 * (V - 128)
    std::array<int, 256> ug{};  // -100 * (U - 128)
    std::array<int, 256> vg{};  // -208 * (V - 128)
    std::array<int, 256> ub{};  // 516 * (U - 128)
    YuvTables() {
        for (int i = 0; i < 256; ++i) {
            y[i] = 298 * (i - 16) + 128; // 丸め用の 128 を含める
            vr[i] = 409 * (i - 128);
            ug[i] = -100 * (i - 128);
            vg[i] = -208 * (i - 128);
            ub[i] = 516 * (i - 128);
        }
    }
};

const YuvTables &tables() {
    static const YuvTables t;
    return t;
}

inline std::uint8_t clamp8(int v) {
    return static_cast<std::uint8_t>(v < 0 ? 0 : (v > 255 ? 255 : v));
}

/**
 * @brief I420(Y・U・V の 3 面)を QImage(Format_RGB32)へ変換する。
 *
 * Format_RGB32 はリトルエンディアンで B,G,R,A の並び。U・V は縦横とも半分の大きさ。
 */
QImage i420ToImage(const std::uint8_t *planeY, const std::uint8_t *planeU, const std::uint8_t *planeV, int width,
                   int height, int strideY, int strideUV) {
    QImage image(width, height, QImage::Format_RGB32);
    if (image.isNull()) {
        return image;
    }
    const YuvTables &t = tables();
    for (int row = 0; row < height; ++row) {
        const std::uint8_t *y = planeY + static_cast<std::ptrdiff_t>(row) * strideY;
        const std::uint8_t *u = planeU + static_cast<std::ptrdiff_t>(row / 2) * strideUV;
        const std::uint8_t *v = planeV + static_cast<std::ptrdiff_t>(row / 2) * strideUV;
        std::uint8_t *dst = image.scanLine(row);
        for (int col = 0; col < width; ++col) {
            const int uu = u[col >> 1];
            const int vv = v[col >> 1];
            const int luma = t.y[y[col]];
            dst[0] = clamp8((luma + t.ub[uu]) >> 8);                  // B
            dst[1] = clamp8((luma + t.ug[uu] + t.vg[vv]) >> 8);       // G
            dst[2] = clamp8((luma + t.vr[vv]) >> 8);                  // R
            dst[3] = 0xFF;                                            // A
            dst += 4;
        }
    }
    return image;
}

} // namespace

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
    return decoder_ != nullptr;
}

/**
 * @brief 初期化失敗の理由。
 */
QString H264Decoder::errorString() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return error_;
}

/**
 * @brief デコーダを作り直して状態(参照フレーム等)を初期化する。
 */
void H264Decoder::reset() {
    std::lock_guard<std::mutex> lock(mutex_);
    closeLocked();
    openLocked();
}

/**
 * @brief OpenH264 のデコーダを作って初期化する。
 *
 * 入力は Annex-B の 1 アクセスユニットずつ。DecodeFrameNoDelay で、入れたアクセスユニットの
 * フレームをその場で出させる(以前の libavcodec の LOW_DELAY・スレッド 1 本と同じ狙い)。
 */
bool H264Decoder::openLocked() {
    ISVCDecoder *decoder = nullptr;
    if (WelsCreateDecoder(&decoder) != 0 || decoder == nullptr) {
        error_ = QStringLiteral("OpenH264 could not create a decoder");
        return false;
    }
    SDecodingParam param;
    std::memset(&param, 0, sizeof(param));
    param.sVideoProperty.eVideoBsType = VIDEO_BITSTREAM_AVC;
    param.uiTargetDqLayer = static_cast<unsigned char>(0xFF);
    param.eEcActiveIdc = ERROR_CON_SLICE_COPY; // 壊れた・欠けたスライスは前のフレームで埋める
    param.bParseOnly = false;
    param.uiCpuLoad = 0;
    if (decoder->Initialize(&param) != 0) {
        error_ = QStringLiteral("OpenH264 decoder initialization failed");
        WelsDestroyDecoder(decoder);
        return false;
    }
    decoder_ = decoder;
    error_.clear();
    return true;
}

/**
 * @brief 確保済みのデコーダを解放する。
 */
void H264Decoder::closeLocked() {
    if (decoder_ != nullptr) {
        decoder_->Uninitialize();
        WelsDestroyDecoder(decoder_);
        decoder_ = nullptr;
    }
}

/**
 * @brief 1アクセスユニットを送り、出てきたフレームを I420→BGRA の QImage に変換して通知する。
 */
void H264Decoder::decode(const std::uint8_t *data, std::size_t size) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (decoder_ == nullptr || data == nullptr || size == 0) {
        return;
    }
    // 入力の末尾に 0 の余白を付けたコピーを渡す(呼び出し側のバッファの余白に頼らない)
    input_.assign(data, data + size);
    input_.insert(input_.end(), kInputPadding, 0);

    std::uint8_t *planes[3] = {nullptr, nullptr, nullptr};
    SBufferInfo info;
    std::memset(&info, 0, sizeof(info));
    const DECODING_STATE state = decoder_->DecodeFrameNoDelay(input_.data(), static_cast<int>(size), planes, &info);
    (void)state; // 壊れたデータ・SPS/PPS 待ちは、フレームが出ないだけ。次のアクセスユニットで回復を試みる
    if (info.iBufferStatus != 1) {
        return; // 出力できるフレームが無い
    }

    const SSysMEMBuffer &buf = info.UsrData.sSystemBuffer;
    if (buf.iFormat != videoFormatI420 || buf.iWidth <= 0 || buf.iHeight <= 0 || planes[0] == nullptr ||
        planes[1] == nullptr || planes[2] == nullptr) {
        return;
    }
    const QImage image = i420ToImage(planes[0], planes[1], planes[2], buf.iWidth, buf.iHeight, buf.iStride[0],
                                     buf.iStride[1]);
    if (!image.isNull() && callback_) {
        callback_(image);
    }
}

} // namespace opencruise
