/**
 * @file AasdkBackendStub.cpp
 * @brief aasdk 無効ビルド (OPENCRUISE_ENABLE_AASDK=OFF) 用の何もしない実装。
 *
 * これにより aasdk / libusb / boost が無い環境でも UI だけをビルド・起動できる。
 */
#include "AasdkBackend.h"

namespace opencruise::aa {

struct AasdkBackend::Impl {
    BackendCallbacks callbacks;
};

/**
 * @brief コールバックを保持するだけ。
 */
AasdkBackend::AasdkBackend(BackendCallbacks callbacks, StreamSettings)
    : impl_(std::make_unique<Impl>(Impl{std::move(callbacks)})) {}

/**
 * @brief 何もしない。
 */
AasdkBackend::~AasdkBackend() = default;

/**
 * @brief 常に失敗を返す（aasdk が組み込まれていないため）。
 */
bool AasdkBackend::start(std::string &errorMessage) {
    errorMessage = "aasdk なしでビルドされています (OPENCRUISE_ENABLE_AASDK=OFF)";
    return false;
}

/**
 * @brief 何もしない。
 */
void AasdkBackend::stop() {}

void AasdkBackend::setNightMode(bool) {}

void AasdkBackend::sendVehicleData(const VehicleSnapshot &) {}

/**
 * @brief 常に false。
 */
bool AasdkBackend::isRunning() const { return false; }

/**
 * @brief 何もしない（送る相手がいない）。
 */
void AasdkBackend::sendTouch(const TouchEvent &) {}

} // namespace opencruise::aa
