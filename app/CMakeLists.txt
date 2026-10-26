find_package(Qt6 6.4 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Multimedia)
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
        aabackend/AasdkVideoHandler.cpp
        aabackend/AasdkSensorHandler.cpp
        aabackend/AasdkInputHandler.cpp
        aabackend/AasdkSystemAudioHandler.cpp
        aabackend/AasdkMicrophoneHandler.cpp
        aabackend/AasdkPhoneHandler.cpp)

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
    core/AppInfo.cpp
    core/AppSettings.cpp
    core/AudioSettings.cpp
    core/BrightnessController.cpp
    core/BootManager.cpp
    core/ClockModel.cpp
    core/DisplaySettings.cpp
    core/DrmDisplay.cpp
    core/Log.cpp
    core/NotificationManager.cpp
    core/NotificationHistoryModel.cpp
    core/SystemSound.cpp
    core/VehicleDataManager.cpp
    core/SystemStats.cpp
    core/PhoneStatus.cpp
    core/AlbumArtProvider.cpp
    core/WidgetStore.cpp
    androidauto/AndroidAutoController.cpp
    androidauto/AudioPlayer.cpp
    androidauto/MicrophoneInput.cpp
    androidauto/H264Decoder.cpp
    androidauto/TestVideoFeeder.cpp)

set_source_files_properties(qml/Theme.qml qml/widgets/WidgetRegistry.qml qml/widgets/WarningAlarm.qml
    qml/widgets/VehicleHistory.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

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
        qml/SettingsCategory.qml
        qml/SettingsCategoryButton.qml
        qml/SettingsPage.qml
        qml/SettingsSection.qml
        qml/SettingsRow.qml
        qml/SettingsChoice.qml
        qml/SettingsSwitch.qml
        qml/SettingsInfoRow.qml
        qml/SettingsNote.qml
        qml/SettingsPageGeneral.qml
        qml/SettingsPageDisplay.qml
        qml/SettingsPagePower.qml
        qml/SettingsPageAudio.qml
        qml/SettingsSlider.qml
        qml/SettingsDeviceList.qml
        qml/SettingsPageAndroidAuto.qml
        qml/SettingsPageNotifications.qml
        qml/SettingsPageVehicle.qml
        qml/SettingsPageSystem.qml
        qml/SettingsPageAbout.qml
        qml/CanPanel.qml
        qml/StatCard.qml
        qml/SystemStatsStrip.qml
        qml/ConnectionBadge.qml
        qml/OsdBar.qml
        qml/VolumeOsd.qml
        qml/BrightnessOsd.qml
        qml/ActionButton.qml
        qml/MaterialIcon.qml
        qml/MdiCodes.js
        qml/SplashScreen.qml
        qml/LauncherScreen.qml
        qml/LauncherTile.qml
        qml/NotificationPopup.qml
        qml/NotificationBell.qml
        qml/AlarmClearButton.qml
        qml/NotificationHistoryPanel.qml
        qml/widgets/WidgetRegistry.qml
        qml/widgets/WarningAlarm.qml
        qml/widgets/VehicleHistory.qml
        qml/widgets/WidgetPages.qml
        qml/widgets/PageBar.qml
        qml/widgets/PageMenu.qml
        qml/widgets/GraphWidget.qml
        qml/widgets/GraphSettings.qml
        qml/widgets/WidgetBase.qml
        qml/widgets/WidgetHost.qml
        qml/widgets/WidgetArea.qml
        qml/widgets/WidgetSettingsBase.qml
        qml/widgets/WidgetSettingsGroup.qml
        qml/widgets/WidgetSettingsDialog.qml
        qml/widgets/WidgetPicker.qml
        qml/widgets/WSStepper.qml
        qml/widgets/WSTextField.qml
        qml/widgets/SettingsColorPalette.qml
        qml/widgets/ClockWidget.qml
        qml/widgets/ClockSettings.qml
        qml/widgets/GreetingWidget.qml
        qml/widgets/GreetingSettings.qml
        qml/widgets/GaugeWidget.qml
        qml/widgets/GaugeSettings.qml
        qml/widgets/PhoneStatusWidget.qml
        qml/widgets/PhoneStatusSettings.qml
        qml/widgets/PhoneNoticeWidget.qml
        qml/widgets/PhoneNoticeSettings.qml
        qml/widgets/PhoneCallWidget.qml
        qml/widgets/PhoneCallSettings.qml
        qml/widgets/NowPlayingWidget.qml
        qml/widgets/NowPlayingSettings.qml
        qml/widgets/MarqueeText.qml
        qml/widgets/NavigationWidget.qml
        qml/widgets/NavigationSettings.qml
    RESOURCES
        fonts/MaterialIcons-Regular.ttf
        fonts/materialdesignicons-webfont.ttf
        sounds/click/Click.wav
        sounds/start/Start.wav
        sounds/alert/Beep.wav
        sounds/caution/Caution.wav)

target_include_directories(opencruise PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/androidauto
    ${CMAKE_CURRENT_SOURCE_DIR}/aabackend)
target_link_libraries(opencruise PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::Multimedia
    opencruise_aa
    PkgConfig::FFMPEG)
if(OPENCRUISE_ENABLE_AASDK)
    target_compile_definitions(opencruise PRIVATE OPENCRUISE_WITH_AASDK)
endif()
# eglfs(DRM/KMS)で外部モニターへミラーするのに使う(無ければミラー機能なしでビルドする。sudo apt install libdrm-dev)
pkg_check_modules(LIBDRM QUIET IMPORTED_TARGET libdrm)
if(LIBDRM_FOUND)
    target_link_libraries(opencruise PRIVATE PkgConfig::LIBDRM)
    target_compile_definitions(opencruise PRIVATE OPENCRUISE_WITH_DRM)
    message(STATUS "libdrm ${LIBDRM_VERSION}: eglfs の外部モニターへのミラーを有効にします")
else()
    message(STATUS "libdrm が見つかりません: eglfs の外部モニターへのミラーは無効です")
endif()
target_compile_options(opencruise PRIVATE -Wall -Wextra)

# ---------------------------------------------------------------------------
# 同梱フォント(Noto Sans JP / Noto Sans CJK JP / IBM Plex Sans JP。いずれも SIL OFL 1.1)。
# 合計 170MB 超でリソース(qrc)に埋め込むとビルドが極端に重くなるため、実行ファイルの隣の fonts/ へコピーし、
# 起動時に AppSettings が読み込む。ライセンス文は各フォルダの OFL.txt。詳細は fonts/README-FONTS.md。
# ---------------------------------------------------------------------------
set(OPENCRUISE_BUNDLED_FONT_DIRS NotoSansJP NotoSansCJKjp IBMPlexSansJP)
foreach(font_dir IN LISTS OPENCRUISE_BUNDLED_FONT_DIRS)
    add_custom_command(TARGET opencruise POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            ${CMAKE_CURRENT_SOURCE_DIR}/fonts/${font_dir}
            $<TARGET_FILE_DIR:opencruise>/fonts/${font_dir}
        COMMENT "フォントをコピー: ${font_dir}")
    install(DIRECTORY fonts/${font_dir} DESTINATION share/opencruise/fonts)
endforeach()
install(FILES fonts/README-FONTS.md DESTINATION share/opencruise/fonts)

# ---------------------------------------------------------------------------
# 効果音(カテゴリごとのフォルダ: sounds/click = 操作音、sounds/start = 起動音、sounds/alert = 警告音、sounds/caution = 注意音。
# WAV のみ。起動音だけは MP3 も使える)。
# 実行ファイルの隣の sounds/ へコピーし、設定「サウンド」の一覧に出す(SystemSound が読む)。
# 既定の Click.wav / Start.wav は、フォルダが無い環境でも鳴らせるようリソースにも埋め込む(上の RESOURCES)。
# ---------------------------------------------------------------------------
add_custom_command(TARGET opencruise POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${CMAKE_CURRENT_SOURCE_DIR}/sounds
        $<TARGET_FILE_DIR:opencruise>/sounds
    COMMENT "効果音をコピー")
install(DIRECTORY sounds/ DESTINATION share/opencruise/sounds)
