cmake_minimum_required(VERSION 3.21)
project(OpenCruise VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# OFF にすると aasdk/libusb/boost 無しで UI だけをビルドできる（接続処理はスタブになり「利用不可」と表示される）
option(OPENCRUISE_ENABLE_AASDK "aasdk を使った Android Auto 接続処理をビルドする" OFF)

if(OPENCRUISE_ENABLE_AASDK)
    # 同梱の aasdk をそのままサブプロジェクトとしてビルドする。
    # aasdk の CMake はテスト/ベンチマークや自前 protobuf ビルドの既定値が重いので、システムの protobuf を使う設定にする。
    set(AASDK_TEST OFF CACHE BOOL "OpenCruise: aasdk の単体テストは不要" FORCE)
    set(AASDK_BENCHMARK OFF CACHE BOOL "OpenCruise: aasdk のベンチマークは不要" FORCE)
    set(SKIP_BUILD_PROTOBUF ON CACHE BOOL "システムの protobuf を使う")
    set(SKIP_BUILD_ABSL ON CACHE BOOL "システムの protobuf を使う場合 Abseil は不要")
    add_subdirectory(aasdk EXCLUDE_FROM_ALL)
endif()

add_subdirectory(app)
