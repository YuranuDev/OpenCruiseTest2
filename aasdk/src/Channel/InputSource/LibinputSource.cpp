#include "aasdk/src/Channel/InputSource/LibinputSource.hpp"

#include <libinput.h>
#include <fcntl.h>
#include <unistd.h>
#include <iostream>

namespace aasdk::channel::inputsource {

LibinputSource::LibinputSource(boost::asio::io_service::strand &strand, 
                               messenger::IMessenger::Pointer messenger,
                               const std::string &device_path)
    : strand_(strand), messenger_(messenger), device_path_(device_path), running_(false) {
}

LibinputSource::~LibinputSource() {
    stop();
}

void LibinputSource::start() {
    running_ = true;
    thread_ = std::thread(&LibinputSource::run, this);
}

void LibinputSource::stop() {
    running_ = false;
    if (thread_.joinable()) {
        thread_.join();
    }
}

void LibinputSource::run() {
    int fd = open(device_path_.c_str(), O_RDONLY | O_NONBLOCK);
    if (fd < 0) {
        AASDK_LOG(error) << "Failed to open device: " << device_path_;
        return;
    }

    struct libinput_device *dev;
    struct libinput_context *ctx = libinput_context_create();
    
    if (!ctx) {
        AASDK_LOG(error) << "Failed to create libinput context";
        close(fd);
        return;
    }

    // Note: In a real app, we'd map the FD to the device
    // This is a simplified representation of libinput's lifecycle
    // libinput_device* find_dev = ... 

    AASDK_LOG(info) << "Started libinput source on " << device_path_;

    while (running_) {
        // libinput_dispatch / libinput_poll would go here
        // This is where the actual libinput event loop resides
        // For the purpose of this prototype, we simulate the polling
        usleep(10000);
    }

    libinput_context_destroy(ctx);
    close(fd);
}

void LibinputSource::handle_event(int32_t id, int32_t x, int32_t y, 
                                  aap_protobuf::service::inputsource::message::PointerAction action) {
    auto report = std::make_shared<aap_protobuf::service::inputsource::message::InputReport>();
    report->set_timestamp(static_cast<uint64_t>(time(NULL)));

    auto touch_event = std::make_shared<aap_protobuf::service::inputsource::message::TouchEvent>();
    auto* pointer = touch_event->add_pointer_data();
    pointer->set_x(x);
    pointer->set_y(y);
    pointer->set_pointer_id(id);

    touch_event->set_action_index(static_cast<uint32_t>(action));
    touch_event->set_action(action);
    
    *report = std::move(*touch_event);
    
    // Send to messenger
    // Note: we need to wrap the protobuf message into a Messenger message
    // This is a placeholder for the logic that puts the report into the channel_
    AASDK_LOG(info) << "Dispatching TouchEvent: " << x << ", " << y << " Action: " << action;
}

} // namespace aasdk::channel::inputsource
