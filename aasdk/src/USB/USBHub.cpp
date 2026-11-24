// This file is part of aasdk library project.
// Copyright (C) 2018 f1x.studio (Michal Szwaj)
// Copyright (C) 2024 CubeOne (Simon Dean - simon.dean@cubeone.co.uk)
//
// aasdk is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// (at your option) any later version.
//
// aasdk is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with aasdk. If not, see <http://www.gnu.org/licenses/>.

#include <thread>
#include <aasdk/USB/IUSBWrapper.hpp>
#include <aasdk/USB/USBHub.hpp>
#include <aasdk/USB/AccessoryModeQueryChain.hpp>
#include <aasdk/Error/Error.hpp>


namespace aasdk {
  namespace usb {

    USBHub::USBHub(IUSBWrapper &usbWrapper, boost::asio::io_context &ioService,
                   IAccessoryModeQueryChainFactory &queryChainFactory)
        : usbWrapper_(usbWrapper), strand_(ioService), queryChainFactory_(queryChainFactory) {
    }

    void USBHub::start(Promise::Pointer promise) {
      boost::asio::dispatch(strand_, [this, self = this->shared_from_this(), promise = std::move(promise)]() {
        if (hotplugPromise_ != nullptr) {
          hotplugPromise_->reject(error::Error(error::ErrorCode::OPERATION_ABORTED));
          hotplugPromise_.reset();
        }

        hotplugPromise_ = std::move(promise);

        if (self_ == nullptr) {
          self_ = this->shared_from_this();
          hotplugHandle_ = usbWrapper_.hotplugRegisterCallback(LIBUSB_HOTPLUG_EVENT_DEVICE_ARRIVED,
                                                               LIBUSB_HOTPLUG_ENUMERATE, LIBUSB_HOTPLUG_MATCH_ANY,
                                                               LIBUSB_HOTPLUG_MATCH_ANY,
                                                               LIBUSB_HOTPLUG_MATCH_ANY,
                                                               reinterpret_cast<libusb_hotplug_callback_fn>(&USBHub::hotplugEventsHandler),
                                                               reinterpret_cast<void *>(this));
        }
      });
    }

    void USBHub::cancel() {
      boost::asio::dispatch(strand_, [this, self = this->shared_from_this()]() mutable {
        if (hotplugPromise_ != nullptr) {
          hotplugPromise_->reject(error::Error(error::ErrorCode::OPERATION_ABORTED));
          hotplugPromise_.reset();
        }

        std::for_each(queryChainQueue_.begin(), queryChainQueue_.end(),
                      std::bind(&IAccessoryModeQueryChain::cancel, std::placeholders::_1));

        if (self_ != nullptr) {
          hotplugHandle_.reset();
          self_.reset();
        }
      });
    }

    int USBHub::hotplugEventsHandler(libusb_context *usbContext, libusb_device *device, libusb_hotplug_event event,
                                     void *userData) {
      if (event == LIBUSB_HOTPLUG_EVENT_DEVICE_ARRIVED) {
        auto self = reinterpret_cast<USBHub *>(userData)->shared_from_this();
        boost::asio::dispatch(self->strand_, std::bind(&USBHub::handleDevice, self, device));
      }

      return 0;
    }

    bool USBHub::mayBeAndroidDevice(libusb_device *device) {
      libusb_device_descriptor deviceDescriptor;
      if (libusb_get_device_descriptor(device, &deviceDescriptor) != LIBUSB_SUCCESS) {
        return true;   // 分からなければ、これまでどおり試す
      }
      if (deviceDescriptor.bDeviceClass == LIBUSB_CLASS_HUB) {
        return false;
      }
      libusb_config_descriptor *config = nullptr;
      if (libusb_get_active_config_descriptor(device, &config) != LIBUSB_SUCCESS || config == nullptr) {
        config = nullptr;
        if (libusb_get_config_descriptor(device, 0, &config) != LIBUSB_SUCCESS || config == nullptr) {
          return true;
        }
      }
      bool anyInterface = false;
      bool candidate = false;
      for (uint8_t i = 0; i < config->bNumInterfaces; ++i) {
        const libusb_interface &intf = config->interface[i];
        if (intf.num_altsetting < 1) {
          continue;
        }
        const libusb_interface_descriptor &alt = intf.altsetting[0];
        anyInterface = true;
        switch (alt.bInterfaceClass) {
        case LIBUSB_CLASS_AUDIO:                // 音声
        case LIBUSB_CLASS_HID:                  // キーボード・マウス・タッチパネル
        case LIBUSB_CLASS_PRINTER:
        case LIBUSB_CLASS_MASS_STORAGE:         // USB メモリ(アップデートのファイル)
        case LIBUSB_CLASS_HUB:
        case LIBUSB_CLASS_SMART_CARD:
        case LIBUSB_CLASS_VIDEO:                // カメラ(バックカメラ)
        case LIBUSB_CLASS_PERSONAL_HEALTHCARE:
          break;
        case LIBUSB_CLASS_WIRELESS:
          // Bluetooth(サブクラス 1・プロトコル 1)は対象外。RNDIS(USB テザリング)などはスマートフォンかもしれない
          if (!(alt.bInterfaceSubClass == 0x01 && alt.bInterfaceProtocol == 0x01)) {
            candidate = true;
          }
          break;
        default:                                // ベンダー固有(ADB)・MTP/PTP・CDC・その他
          candidate = true;
          break;
        }
      }
      libusb_free_config_descriptor(config);
      return !anyInterface || candidate;
    }

    bool USBHub::isAOAPDevice(const libusb_device_descriptor &deviceDescriptor) const {
      return deviceDescriptor.idVendor == cGoogleVendorId &&
             (deviceDescriptor.idProduct == cAOAPId || deviceDescriptor.idProduct == cAOAPWithAdbId);
    }

    void USBHub::handleDevice(libusb_device *device) {
      if (hotplugPromise_ == nullptr) {
        return;
      }

      libusb_device_descriptor deviceDescriptor;
      if (usbWrapper_.getDeviceDescriptor(device, deviceDescriptor) != 0) {
        return;
      }
      // OpenCruise: スマートフォンではない機器(ハブ・カメラ・Bluetooth など)は開かない(mayBeAndroidDevice)
      if (!this->isAOAPDevice(deviceDescriptor) && !mayBeAndroidDevice(device)) {
        return;
      }

      DeviceHandle handle;
      auto openResult = usbWrapper_.open(device, handle);

      if (openResult != 0) {
        return;
      }

      if (this->isAOAPDevice(deviceDescriptor)) {
        hotplugPromise_->resolve(std::move(handle));
        hotplugPromise_.reset();
      } else {
        // OpenCruise: VMware 向けの 1 秒 sleep は、実機では再接続が毎回 1 秒遅れるだけなので削除した
        queryChainQueue_.emplace_back(queryChainFactory_.create());

        auto queueElementIter = std::prev(queryChainQueue_.end());
        auto queryChainPromise = IAccessoryModeQueryChain::Promise::defer(strand_);
        queryChainPromise->then([this, self = this->shared_from_this(), queueElementIter](DeviceHandle handle) mutable {
                                  queryChainQueue_.erase(queueElementIter);
                                },
                                [this, self = this->shared_from_this(), queueElementIter](
                                    const error::Error &e) mutable {
                                  queryChainQueue_.erase(queueElementIter);
                                });

        queryChainQueue_.back()->start(std::move(handle), std::move(queryChainPromise));
      }
    }

  }
}
