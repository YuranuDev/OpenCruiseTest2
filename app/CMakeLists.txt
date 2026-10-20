find_package(Qt6 6.4 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2)
find_package(PkgConfig REQUIRED)
find_package(Threads REQUIRED)
pkg_check_modules(FFMPEG REQUIRED IMPORTED_TARGET libavcodec libavutil libswscale)

qt_standard_project_setup()

# ---------------------------------------------------------------------------
# 接続層 (Qt 非依存)。aasdk 有効時は実装、無効時はスタブをビルドする。
# ---------------------------------------------------------------------------
add_library(opencruise_aa STATIC)
target_include_directories(opencruise_aa PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/aabackend)
target_link_libraries(opencruise_aa PUBLIC Threads::Threads)

if(OPENCRUISE_ENABLE_AASDK)
    find_package(Boost REQUIRED COMPONENTS system)
    pkg_check_modules(LIBUSB REQUIRED IMPORTED_TARGET libusb-1.0)

    target_sources(opencruise_aa PRIVATE
        aabackend/AasdkBackend.cpp
        aabackend/AasdkSession.cpp
        aabackend/AasdkVideoHandler.cpp)

    # aasdk の include ディレクトリは aasdk 側ではターゲット属性でなくディレクトリ属性で設定されているため、ここで明示する
    target_include_directories(opencruise_aa PRIVATE
        ${PROJECT_SOURCE_DIR}/aasdk/include
        ${PROJECT_BINARY_DIR}/aasdk/include)
    # aasdk 側が -DBOOST_ALL_DYN_LINK を付けてビルドしているので揃える (Boost.Log の ABI 整合のため)
    target_compile_definitions(opencruise_aa PRIVATE BOOST_ALL_DYN_LINK)
    target_link_libraries(opencruise_aa PRIVATE aasdk Boost::system PkgConfig::LIBUSB)
else()
    target_sources(opencruise_aa PRIVATE aabackend/AasdkBackendStub.cpp)
endif()

target_compile_options(opencruise_aa PRIVATE -Wall -Wextra)

# ---------------------------------------------------------------------------
# Qt アプリ本体
# ---------------------------------------------------------------------------
qt_add_executable(opencruise
    main.cpp
    core/ClockModel.cpp
    core/DummyCanModel.cpp
    androidauto/AndroidAutoController.cpp
    androidauto/H264Decoder.cpp
    androidauto/TestVideoFeeder.cpp)

set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(opencruise
    URI OpenCruise
    VERSION 1.0
    SOURCES
        androidauto/VideoSurfaceItem.h
        androidauto/VideoSurfaceItem.cpp
    QML_FILES
        qml/Main.qml
        qml/Theme.qml
        qml/HomeScreen.qml
        qml/SettingsScreen.qml
        qml/CanPanel.qml
        qml/ConnectionBadge.qml
        qml/ActionButton.qml)

target_include_directories(opencruise PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/androidauto
    ${CMAKE_CURRENT_SOURCE_DIR}/aabackend)
target_link_libraries(opencruise PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2
    opencruise_aa
    PkgConfig::FFMPEG)
if(OPENCRUISE_ENABLE_AASDK)
    target_compile_definitions(opencruise PRIVATE OPENCRUISE_WITH_AASDK)
endif()
target_compile_options(opencruise PRIVATE -Wall -Wextra)
