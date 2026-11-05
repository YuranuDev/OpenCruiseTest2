/**
 * @file TestVideoFeeder.cpp
 * @brief TestVideoFeeder の実装。
 */
#include "TestVideoFeeder.h"

#include <chrono>

#include <QFile>

namespace opencruise {

/**
 * @brief 送出先を保持する。
 */
TestVideoFeeder::TestVideoFeeder(Sink sink) : sink_(std::move(sink)) {}

/**
 * @brief スレッドを停止する。
 */
TestVideoFeeder::~TestVideoFeeder() { stop(); }

/**
 * @brief ファイルを AUD(NAL type 9) の位置で分割し、30fps で繰り返し送るスレッドを起動する。
 */
bool TestVideoFeeder::start(const QString &path, QString &error) {
    stop();

    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        error = QStringLiteral("Cannot open the test video: ") + path;
        return false;
    }
    const QByteArray bytes = file.readAll();
    const auto *data = reinterpret_cast<const std::uint8_t *>(bytes.constData());
    const std::size_t size = static_cast<std::size_t>(bytes.size());

    // スタートコード(00 00 01)の直後が AUD(NAL type 9) の位置を、アクセスユニットの先頭とみなす
    std::vector<std::size_t> starts;
    for (std::size_t i = 0; i + 3 < size; ++i) {
        if (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1 && (data[i + 3] & 0x1F) == 9) {
            starts.push_back(i > 0 && data[i - 1] == 0 ? i - 1 : i);
        }
    }
    if (starts.empty()) {
        error = QStringLiteral("No AUD found. Use an H.264 file encoded by x264 with aud=1");
        return false;
    }

    units_.clear();
    for (std::size_t n = 0; n < starts.size(); ++n) {
        const std::size_t end = (n + 1 < starts.size()) ? starts[n + 1] : size;
        units_.emplace_back(data + starts[n], data + end);
    }

    stop_ = false;
    thread_ = std::thread([this]() {
        auto next = std::chrono::steady_clock::now();
        while (!stop_) {
            for (const auto &unit : units_) {
                if (stop_) {
                    return;
                }
                sink_(unit.data(), unit.size());
                next += std::chrono::milliseconds(33);
                std::this_thread::sleep_until(next);
            }
        }
    });
    return true;
}

/**
 * @brief スレッドを止めて join する。
 */
void TestVideoFeeder::stop() {
    stop_ = true;
    if (thread_.joinable()) {
        thread_.join();
    }
}

} // namespace opencruise
