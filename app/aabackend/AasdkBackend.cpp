/**
 * @file AasdkBackend.cpp
 * @brief aasdk 実装版の接続層。USB 基盤を持ち、「待機 → 接続 → 切断 → 待機」を繰り返す。
 *
 * 構成:
 *  - libusb_context と、そのイベントループ専用スレッド（USBWrapper::handleEvents はタイムアウト無しで
 *    ブロックし停止できないため、libusb のイベント処理は自前のループで回す）
 *  - boost::asio::io_service と ioスレッド群（aasdk の Promise/Messenger が使う）
 *  - USBHub: ホットプラグ検出 → AOAP 切替 → AOAP 済み DeviceHandle の取得
 *  - AasdkSession: 接続ごとに生成する使い捨てセッション
 *
 * USBHub は待機のたびに作り直す。理由: ホットプラグ通知の列挙(ENUMERATE)は登録時にしか行われず、
 * 「すでに接続されたままのスマートフォン」を再検出するには再登録が必要なため。
 * (再登録の前提となる cancel() でコールバックが解除されない aasdk のバグは patches/ の修正で対処)
 */
#include "AasdkBackend.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <thread>
#include <vector>

#include <boost/asio.hpp>
#include <libusb.h>

#include <aasdk/Error/Error.hpp>
#include <aasdk/USB/AOAPDevice.hpp>
#include <aasdk/USB/AccessoryModeQueryChainFactory.hpp>
#include <aasdk/USB/AccessoryModeQueryFactory.hpp>
#include <aasdk/USB/IUSBHub.hpp>
#include <aasdk/USB/USBHub.hpp>
#include <aasdk/USB/USBWrapper.hpp>

#include <cstdio>

#include "AasdkConfig.h"
#include "AasdkSession.h"

namespace opencruise::aa {

/**
 * @brief 接続層の内部状態。公開インターフェース(AasdkBackend)から pimpl で隠している。
 *
 * 接続状態に関わるメンバ(hub, session)は strand_ 上でのみ触る。
 */
struct AasdkBackend::Impl {
    /**
     * @brief コールバックを保持する。
     */
    Impl(BackendCallbacks cb, StreamSettings s) : callbacks(std::move(cb)), settings(s.sanitized()) {}

    /**
     * @brief 破棄時に確実に停止する。
     */
    ~Impl() { stop(); }

    /**
     * @brief libusb と各スレッドを起動し、接続待ちを開始する。
     * @param[out] error 失敗理由
     * @return 成功なら true
     */
    bool start(std::string &error) {
        if (running_) {
            return true;
        }

        const int rc = libusb_init(&usbContext_);
        if (rc != LIBUSB_SUCCESS) {
            usbContext_ = nullptr;
            error = std::string("libusb の初期化に失敗: ") + libusb_error_name(rc);
            return false;
        }
        if (!libusb_has_capability(LIBUSB_CAP_HAS_HOTPLUG)) {
            libusb_exit(usbContext_);
            usbContext_ = nullptr;
            error = "この環境の libusb はホットプラグ検出に対応していません";
            return false;
        }

        usbWrapper_ = std::make_unique<aasdk::usb::USBWrapper>(usbContext_);
        queryFactory_ = std::make_unique<aasdk::usb::AccessoryModeQueryFactory>(*usbWrapper_, ioService_);
        chainFactory_ =
            std::make_unique<aasdk::usb::AccessoryModeQueryChainFactory>(*usbWrapper_, ioService_, *queryFactory_);
        strand_ = std::make_unique<boost::asio::io_service::strand>(ioService_);
        retryTimer_ = std::make_unique<boost::asio::steady_timer>(ioService_);
        rescanTimer_ = std::make_unique<boost::asio::steady_timer>(ioService_);
        workGuard_ = std::make_unique<WorkGuard>(boost::asio::make_work_guard(ioService_));

        stopping_ = false;
        running_ = true;
        usbEventStop_ = false;
        usbEventThread_ = std::thread([this]() { runUsbEvents(); });
        for (int i = 0; i < config::kIoThreadCount; ++i) {
            ioThreads_.emplace_back([this]() { runIo(); });
        }

        strand_->post([this]() { beginWaiting(); });
        return true;
    }

    /**
     * @brief セッションと USB 基盤を停止して解放する。何度呼んでもよい。
     *
     * 手順: 停止要求を strand に投げる → セッション終了通知(ByeBye 送信→応答待ち→終了)を最大2.5秒待つ →
     * io スレッドを終了 → USB イベントスレッドを終了 → libusb 解放。
     * 終了待ちは「上限つきのベストエフォート」。
     */
    void stop() {
        if (!running_.exchange(false)) {
            return;
        }
        stopping_ = true;

        strand_->post([this]() {
            retryTimer_->cancel();
            rescanTimer_->cancel();
            if (hub_) {
                hub_->cancel();
                hub_.reset();
            }
            if (session_) {
                session_->stop(); // 完了は onSessionFinished で通知される
            } else {
                notifySessionGone();
            }
        });

        {
            std::unique_lock<std::mutex> lock(goneMutex_);
            goneCv_.wait_for(lock, std::chrono::milliseconds(2500), [this]() { return sessionGone_; });
        }
        // USB 転送のキャンセル完了通知(libusb スレッド→io)が流れる時間を少し与える
        std::this_thread::sleep_for(std::chrono::milliseconds(100));

        // 終了していないハンドラがあっても io スレッドが必ず戻るよう、猶予後に強制停止してから join する
        ioService_.stop();
        workGuard_.reset();
        for (auto &thread : ioThreads_) {
            thread.join();
        }
        ioThreads_.clear();

        usbEventStop_ = true;
        usbEventThread_.join();

        session_.reset();
        currentHandle_.reset(); // libusb_exit の前に USB ハンドルを閉じる
        hub_.reset();
        chainFactory_.reset();
        queryFactory_.reset();
        usbWrapper_.reset();
        if (usbContext_ != nullptr) {
            libusb_exit(usbContext_);
            usbContext_ = nullptr;
        }
    }

    /**
     * @brief タッチ入力を strand 経由で現在のセッションへ渡す。セッションが無ければ捨てる。
     */
    void sendTouch(const TouchEvent &event) {
        if (!running_ || stopping_) {
            return;
        }
        strand_->post([this, event]() {
            if (session_) {
                session_->sendTouch(event);
            }
        });
    }

    /**
     * @brief 録音データを strand 経由で現在のセッションへ渡す。セッションが無ければ捨てる。
     */
    void sendMicrophoneData(const std::uint8_t *data, std::size_t size) {
        if (!running_ || stopping_ || data == nullptr || size == 0) {
            return;
        }
        std::vector<std::uint8_t> copy(data, data + size);
        strand_->post([this, copy = std::move(copy)]() mutable {
            if (session_) {
                session_->sendMicrophoneData(std::move(copy));
            }
        });
    }

    /**
     * @brief 現在の USB デバイス一覧をログに出す（スマートフォンが見えているかの確認用）。
     */
    void logUsbDevices() {
        libusb_device **list = nullptr;
        const ssize_t count = libusb_get_device_list(usbContext_, &list);
        if (count < 0) {
            log(std::string("[backend] USB デバイス一覧の取得に失敗: ") +
                libusb_error_name(static_cast<int>(count)));
            return;
        }

        std::string summary = "[backend] USB デバイス " + std::to_string(count) + " 台:";
        for (ssize_t i = 0; i < count; ++i) {
            libusb_device_descriptor descriptor{};
            if (libusb_get_device_descriptor(list[i], &descriptor) != LIBUSB_SUCCESS) {
                summary += " (不明)";
                continue;
            }
            char buffer[32]{};
            std::snprintf(buffer, sizeof(buffer), " %04x:%04x", descriptor.idVendor, descriptor.idProduct);
            summary += buffer;
        }
        libusb_free_device_list(list, 1);
        log(summary);
    }

    /**
     * @brief USB デバイスの検出待ちを開始する（strand 上で実行）。
     */
    void beginWaiting() {
        if (stopping_) {
            return;
        }
        log("[backend] USB 検出待ちを開始します: " + waitingDetail_);
        logUsbDevices();
        hub_ = std::make_shared<aasdk::usb::USBHub>(*usbWrapper_, ioService_, *chainFactory_);

        auto promise = aasdk::usb::IUSBHub::Promise::defer(*strand_);
        promise->then([this](aasdk::usb::DeviceHandle handle) { onDeviceFound(std::move(handle)); },
                      [this](const aasdk::error::Error &e) { onHubError(e); });
        // 注意: hotplug 登録時の既存デバイス列挙(ENUMERATE)は、この呼び出しの中で同期的に処理される。
        // OS 側がデバイスの切替中で open() が遅いと、ここで長く止まる。所要時間をログに残す。
        const auto hubStart = std::chrono::steady_clock::now();
        hub_->start(std::move(promise));
        log("[backend] USB 検出の開始処理に " +
            std::to_string(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - hubStart).count()) +
            " ms かかりました");

        report(LinkState::Waiting, waitingDetail_);
        armRescan();
    }

    /**
     * @brief 待機中に一定時間デバイスが見つからなければ、検出を作り直して再列挙する（strand 上）。
     *
     * 切断直後に挿し直した場合など、デバイスが一度 open に失敗するとホットプラグ通知だけでは
     * 二度と拾えないため、定期的に ENUMERATE をやり直す。
     */
    void armRescan() {
        rescanTimer_->expires_after(std::chrono::seconds(10));
        rescanTimer_->async_wait([this](const boost::system::error_code &ec) {
            if (ec) {
                return;
            }
            strand_->post([this]() {
                if (stopping_ || session_ || !hub_) {
                    return;
                }
                log("[backend] デバイスが見つからないため、USB 検出をやり直します");
                hub_->cancel();
                hub_.reset();
                beginWaiting();
            });
        });
    }

    /**
     * @brief スマートフォン側が切断を認識できていない可能性のある終了か。
     *
     * 正規の ByeBye 手順を経た終了(スマートフォン発の切断要求・こちら発への応答受信)以外は true。
     */
    static bool needsUsbReset(const std::string &reason) {
        return reason.rfind("スマートフォンからの切断要求", 0) != 0 && reason.rfind("切断応答を受信", 0) != 0;
    }

    /**
     * @brief AOAP 済みのスマートフォンが見つかったので、セッションを作って開始する（strand 上）。
     */
    void onDeviceFound(aasdk::usb::DeviceHandle handle) {
        if (stopping_) {
            return;
        }
        if (session_) {
            return; // 再列挙で二重に見つかった場合は、接続中のセッションを優先する
        }
        rescanTimer_->cancel();
        currentHandle_ = handle; // 切断後の USB リセット用に控えておく
        report(LinkState::Connecting, "スマートフォンを検出しました。接続処理中です");
        log("[backend] AOAP デバイスを検出しました → セッションを生成します");

        try {
            auto aoapDevice = aasdk::usb::AOAPDevice::create(*usbWrapper_, ioService_, std::move(handle));

            SessionCallbacks sessionCallbacks;
            sessionCallbacks.onStateChanged = callbacks.onStateChanged;
            sessionCallbacks.onVideoData = callbacks.onVideoData;
            sessionCallbacks.onAudioData = callbacks.onAudioData;
            sessionCallbacks.onAudioStop = callbacks.onAudioStop;
            sessionCallbacks.onMicrophoneRequest = callbacks.onMicrophoneRequest;
            sessionCallbacks.onLog = callbacks.onLog;
            sessionCallbacks.onFinished = [this](const std::string &reason) {
                strand_->post([this, reason]() { onSessionFinished(reason); });
            };

            session_ = std::make_shared<AasdkSession>(ioService_, std::move(aoapDevice), std::move(sessionCallbacks), settings);
            session_->setNightMode(nightMode_);
            session_->start();
        } catch (const aasdk::error::Error &e) {
            session_.reset();
            onSessionFinished(std::string("USB デバイスの初期化に失敗: ") + e.what());
        } catch (const std::exception &e) {
            session_.reset();
            onSessionFinished(std::string("セッション生成に失敗: ") + e.what());
        }
    }

    /**
     * @brief USBHub が失敗を返した場合。中断(OPERATION_ABORTED)以外は待機を再試行する。
     */
    void onHubError(const aasdk::error::Error &e) {
        if (stopping_ || e == aasdk::error::ErrorCode::OPERATION_ABORTED) {
            return;
        }
        log(std::string("[backend] USBHub エラー: ") + e.what());
        hub_.reset();
        waitingDetail_ = std::string("USB 検出エラーのため再試行します: ") + e.what();
        report(LinkState::Waiting, waitingDetail_);
        scheduleRetry();
    }

    /**
     * @brief セッションが終了した。リソースを捨てて待機状態へ戻る（strand 上）。
     */
    void onSessionFinished(const std::string &reason) {
        session_.reset();
        // 正規の切断手順を経ていない場合、スマートフォンは前の接続が続いていると思い込んだままになり得る。
        // USB をリセットして再列挙させ、次の接続で無応答にならないようにする。
        if (currentHandle_ && needsUsbReset(reason)) {
            const int rc = libusb_reset_device(currentHandle_.get());
            log(std::string("[backend] 異常終了のため USB デバイスをリセットしました: ") + libusb_error_name(rc));
        }
        currentHandle_.reset();
        if (hub_) {
            hub_->cancel(); // 修正済みの hotplug 解除により、次の beginWaiting で再列挙できる
            hub_.reset();
        }
        if (stopping_) {
            notifySessionGone();
            return;
        }
        log("[backend] セッション終了 → 待機へ復帰: " + reason);
        waitingDetail_ = "切断: " + reason;
        report(LinkState::Waiting, waitingDetail_);
        scheduleRetry();
    }

    /**
     * @brief 一定時間後に待機を再開するタイマーをセットする。
     */
    void scheduleRetry() {
        retryTimer_->expires_after(std::chrono::milliseconds(config::kRetryDelayMs));
        retryTimer_->async_wait([this](const boost::system::error_code &ec) {
            if (!ec) {
                strand_->post([this]() { beginWaiting(); });
            }
        });
    }

    /**
     * @brief stop() 側へ「セッションが無くなった」ことを知らせる。
     */
    void notifySessionGone() {
        std::lock_guard<std::mutex> lock(goneMutex_);
        sessionGone_ = true;
        goneCv_.notify_all();
    }

    /**
     * @brief io_service を回すスレッド本体。ハンドラからの例外でスレッドが落ちないよう再開する。
     */
    void runIo() {
        while (true) {
            try {
                ioService_.run();
                return;
            } catch (const std::exception &e) {
                log(std::string("[backend] io ハンドラで例外: ") + e.what());
            }
        }
    }

    /**
     * @brief libusb のイベントを処理し続けるスレッド本体。100ms ごとに停止フラグを確認する。
     */
    void runUsbEvents() {
        while (!usbEventStop_) {
            timeval timeout{0, 100000};
            const int rc = libusb_handle_events_timeout_completed(usbContext_, &timeout, nullptr);
            if (rc != LIBUSB_SUCCESS && rc != LIBUSB_ERROR_TIMEOUT && rc != LIBUSB_ERROR_INTERRUPTED) {
                log(std::string("[backend] libusb イベント処理エラー: ") + libusb_error_name(rc));
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
            }
        }
    }

    /**
     * @brief 状態を列挙名にする（ログ用）。
     */
    static const char *stateName(LinkState state) {
        switch (state) {
        case LinkState::Unavailable: return "unavailable";
        case LinkState::Waiting: return "waiting";
        case LinkState::Connecting: return "connecting";
        case LinkState::Connected: return "connected";
        case LinkState::Streaming: return "streaming";
        }
        return "unknown";
    }

    /**
     * @brief 状態をコールバックへ通知する。通知自体もログに残す。
     */
    void report(LinkState state, const std::string &detail) {
        log(std::string("[backend] 状態通知: ") + stateName(state) + " - " + detail);
        if (callbacks.onStateChanged) {
            callbacks.onStateChanged(state, detail);
        }
    }

    /**
     * @brief ログをコールバックへ流す。
     */
    void log(const std::string &message) {
        if (callbacks.onLog) {
            callbacks.onLog(message);
        }
    }

    using WorkGuard = boost::asio::executor_work_guard<boost::asio::io_context::executor_type>;

    BackendCallbacks callbacks;
    StreamSettings settings;
    std::atomic<bool> running_{false};
    std::atomic<bool> nightMode_{false};

    /// 昼夜モードを保存し、接続中のセッションへ反映する
    void setNightMode(bool night) {
        nightMode_ = night;
        if (strand_) {
            strand_->post([this, night]() {
                if (session_) {
                    session_->setNightMode(night);
                }
            });
        }
    }

    /// 車両の状態を、接続中のセッションへ渡す(未接続なら捨てる)
    void sendVehicleData(const VehicleSnapshot &snapshot) {
        if (strand_) {
            strand_->post([this, snapshot]() {
                if (session_) {
                    session_->sendVehicleData(snapshot);
                }
            });
        }
    }
    std::atomic<bool> stopping_{false};
    std::string waitingDetail_ = "スマートフォンの接続を待っています";

    libusb_context *usbContext_ = nullptr;
    std::unique_ptr<aasdk::usb::USBWrapper> usbWrapper_;
    std::unique_ptr<aasdk::usb::AccessoryModeQueryFactory> queryFactory_;
    std::unique_ptr<aasdk::usb::AccessoryModeQueryChainFactory> chainFactory_;

    boost::asio::io_service ioService_;
    std::unique_ptr<WorkGuard> workGuard_;
    std::unique_ptr<boost::asio::io_service::strand> strand_;
    std::unique_ptr<boost::asio::steady_timer> retryTimer_;
    std::unique_ptr<boost::asio::steady_timer> rescanTimer_;
    aasdk::usb::DeviceHandle currentHandle_; ///< 接続中の USB デバイス（切断後のリセット用。strand_ 上でのみ触る）
    std::vector<std::thread> ioThreads_;
    std::thread usbEventThread_;
    std::atomic<bool> usbEventStop_{false};

    aasdk::usb::IUSBHub::Pointer hub_;      ///< strand_ 上でのみ触る
    std::shared_ptr<AasdkSession> session_; ///< strand_ 上でのみ触る

    std::mutex goneMutex_;
    std::condition_variable goneCv_;
    bool sessionGone_ = false;
};

/**
 * @brief 内部実装を生成する。
 */
AasdkBackend::AasdkBackend(BackendCallbacks callbacks, StreamSettings settings)
    : impl_(std::make_unique<Impl>(std::move(callbacks), settings)) {}

/**
 * @brief 停止してから破棄する（Impl のデストラクタが stop を呼ぶ）。
 */
AasdkBackend::~AasdkBackend() = default;

/**
 * @brief 接続待ちを開始する。
 */
bool AasdkBackend::start(std::string &errorMessage) { return impl_->start(errorMessage); }

/**
 * @brief 停止する。
 */
void AasdkBackend::stop() { impl_->stop(); }

void AasdkBackend::setNightMode(bool night) { impl_->setNightMode(night); }

void AasdkBackend::sendVehicleData(const VehicleSnapshot &snapshot) { impl_->sendVehicleData(snapshot); }

/**
 * @brief 動作中か。
 */
bool AasdkBackend::isRunning() const { return impl_->running_; }

/**
 * @brief タッチ入力を送る。
 */
void AasdkBackend::sendTouch(const TouchEvent &event) { impl_->sendTouch(event); }

/**
 * @brief 録音データを送る。
 */
void AasdkBackend::sendMicrophoneData(const std::uint8_t *data, std::size_t size) {
    impl_->sendMicrophoneData(data, size);
}

} // namespace opencruise::aa
