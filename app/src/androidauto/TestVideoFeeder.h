/**
 * @file TestVideoFeeder.h
 * @brief 開発用: H.264 ファイルを Android Auto の映像データの代わりに流し込む。
 *
 * スマートフォンが無くても「デコード → 表示」の経路を確認するためのもの。
 * aasdk を経由しないので、これで映像が出ても aasdk の受信が動作した証明にはならない。
 */
#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <thread>
#include <vector>

#include <QString>

namespace opencruise {

/**
 * @brief AUD(アクセスユニット区切り)入りの Annex-B ファイルを 30fps で繰り返し送出する。
 */
class TestVideoFeeder {
public:
    using Sink = std::function<void(const std::uint8_t *, std::size_t)>;

    /**
     * @brief 送出先を指定する。
     * @param sink 1アクセスユニットごとに呼ばれる（別スレッドから）
     */
    explicit TestVideoFeeder(Sink sink);

    /** @brief 送出スレッドを止める。 */
    ~TestVideoFeeder();

    /**
     * @brief ファイルを読み込み、アクセスユニットに分割して送出を開始する。
     * @param path H.264 Annex-B ファイル（x264 の aud=1 付きで作ったもの）
     * @param[out] error 失敗理由
     * @return 開始できたら true
     */
    bool start(const QString &path, QString &error);

    /** @brief 送出を止める。 */
    void stop();

private:
    Sink sink_;
    std::thread thread_;
    std::atomic<bool> stop_{false};
    std::vector<std::vector<std::uint8_t>> units_;
};

} // namespace opencruise
