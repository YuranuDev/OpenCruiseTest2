#pragma once

#include <memory>
#include <string>
#include <vector>
#include <thread>
#include <atomic>
#include <boost/asio.hpp>

#include <aap_protobuf/service/inputsource/message/InputReport.pb.h>
#include <aap_protobuf/service/inputsource/message/TouchEvent.pb.h>
#include <aap_protobuf/service/inputsource/message/PointerAction.pb.h>

#include <aasdk/Messenger/Messenger.hpp>
#include <aasdk/Common/Log.hpp>

namespace aasdk::channel::inputsource {

class LibinputSource {
public:
    LibinputSource(boost::asio::io_service::strand &strand, 
                   messenger::IMessenger::Pointer messenger,
                   const std::string &device_path);
    ~LibinputSource();

    void start();
    void stop();

private:
    void run();
    void handle_event(int32_t id, int32_t x, int32_t y, 
                       aap_protobuf::service::inputsource::message::PointerAction action);

    boost::asio::io_service::strand &strand_;
    messenger::IMessenger::Pointer messenger_;
    std::string device_path_;
    
    std::thread thread_;
    std::atomic<bool> running_;
};

} // namespace aasdk::channel::inputsource
