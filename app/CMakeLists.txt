find_package(Qt6 6.4 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Multimedia)
find_package(PkgConfig REQUIRED)
find_package(Threads REQUIRED)
pkg_check_modules(FFMPEG REQUIRED IMPORTED_TARGET libavcodec libavutil libswscale)

qt_standard_project_setup()

# ---------------------------------------------------------------------------
# 接続層 (Qt 非依存)。aasdk 有効時は実装、無効時はスタブをビルドする。
# ---------------------------------------------------------------------------
add_library(opencruise_aa STATIC)
target_include_directories(opencruise_aa PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(opencruise_aa PUBLIC Threads::Threads)

if(OPENCRUISE_ENABLE_AASDK)
    find_package(Boost REQUIRED COMPONENTS system)
    pkg_check_modules(LIBUSB REQUIRED IMPORTED_TARGET libusb-1.0)

    target_sources(opencruise_aa PRIVATE
        src/aabackend/AasdkBackend.cpp
        src/aabackend/AasdkSession.cpp
        src/aabackend/AasdkVideoHandler.cpp
        src/aabackend/AasdkSensorHandler.cpp
        src/aabackend/AasdkInputHandler.cpp
        src/aabackend/AasdkSystemAudioHandler.cpp
        src/aabackend/AasdkMicrophoneHandler.cpp
        src/aabackend/AasdkPhoneHandler.cpp)

    # aasdk の include ディレクトリは aasdk 側ではターゲット属性でなくディレクトリ属性で設定されているため、ここで明示する
    target_include_directories(opencruise_aa PRIVATE
        ${PROJECT_SOURCE_DIR}/aasdk/include
        ${PROJECT_BINARY_DIR}/aasdk/include)
    # aasdk 側が -DBOOST_ALL_DYN_LINK を付けてビルドしているので揃える (Boost.Log の ABI 整合のため)
    target_compile_definitions(opencruise_aa PRIVATE BOOST_ALL_DYN_LINK)
    target_link_libraries(opencruise_aa PRIVATE aasdk Boost::system PkgConfig::LIBUSB)
else()
    target_sources(opencruise_aa PRIVATE src/aabackend/AasdkBackendStub.cpp)
endif()

target_compile_options(opencruise_aa PRIVATE -Wall -Wextra)

# ---------------------------------------------------------------------------
# Qt アプリ本体
# ---------------------------------------------------------------------------
qt_add_executable(opencruise
    src/main.cpp
    src/core/AppInfo.cpp
    src/core/AppSettings.cpp
    src/ui/ThemeSettings.cpp
    src/vehicle/ReverseCamera.cpp
    src/audio/AudioSettings.cpp
    src/display/BrightnessController.cpp
    src/core/BootManager.cpp
    src/ui/ClockModel.cpp
    src/display/DisplaySettings.cpp
    src/display/DrmDisplay.cpp
    src/core/Log.cpp
    src/notification/NotificationManager.cpp
    src/notification/NotificationHistoryModel.cpp
    src/audio/SystemSound.cpp
    src/vehicle/VehicleDataManager.cpp
    src/system/SystemStats.cpp
    src/system/ShutdownManager.cpp
    src/androidauto/PhoneStatus.cpp
    src/ui/AlbumArtProvider.cpp
    src/ui/WidgetStore.cpp
    src/androidauto/AndroidAutoController.cpp
    src/androidauto/AudioPlayer.cpp
    src/androidauto/MicrophoneInput.cpp
    src/androidauto/H264Decoder.cpp
    src/androidauto/TestVideoFeeder.cpp)

set_source_files_properties(qml/theme/Theme.qml qml/widgets/framework/WidgetRegistry.qml qml/services/WarningAlarm.qml
    qml/services/VehicleHistory.qml qml/widgets/decoration/DecorationEffects.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(opencruise
    URI OpenCruise
    VERSION 1.0
    SOURCES
        src/androidauto/VideoSurfaceItem.h
        src/androidauto/VideoSurfaceItem.cpp
    QML_FILES
        qml/Main.qml
        qml/theme/Theme.qml
        qml/screens/HomeScreen.qml
        qml/screens/SettingsScreen.qml
        qml/settings/SettingsCategory.qml
        qml/settings/SettingsCategoryButton.qml
        qml/settings/SettingsPage.qml
        qml/settings/SettingsSection.qml
        qml/settings/SettingsRow.qml
        qml/settings/SettingsChoice.qml
        qml/settings/SettingsSwitch.qml
        qml/settings/SettingsInfoRow.qml
        qml/settings/SettingsNote.qml
        qml/settings/pages/SettingsPageGeneral.qml
        qml/settings/pages/SettingsPageDisplay.qml
        qml/settings/pages/SettingsPagePower.qml
        qml/settings/pages/SettingsPageAudio.qml
        qml/settings/SettingsSlider.qml
        qml/settings/SettingsColorBar.qml
        qml/settings/SettingsColorPicker.qml
        qml/settings/SettingsDeviceList.qml
        qml/settings/pages/SettingsPageAndroidAuto.qml
        qml/settings/pages/SettingsPageNotifications.qml
        qml/settings/pages/SettingsPageVehicle.qml
        qml/settings/pages/SettingsPageCamera.qml
        qml/screens/ReverseCameraView.qml
        qml/screens/ShutdownScreen.qml
        qml/screens/ReverseCameraVideo.qml
        qml/settings/pages/SettingsPageSystem.qml
        qml/settings/pages/SettingsPageAbout.qml
        qml/components/StatCard.qml
        qml/components/SystemStatsStrip.qml
        qml/components/ConnectionBadge.qml
        qml/osd/OsdBar.qml
        qml/osd/VolumeOsd.qml
        qml/osd/BrightnessOsd.qml
        qml/components/ActionButton.qml
        qml/components/Panel.qml
        qml/theme/ThemeBackground.qml
        qml/components/MaterialIcon.qml
        qml/components/MdiCodes.js
        qml/screens/SplashScreen.qml
        qml/screens/LauncherScreen.qml
        qml/components/LauncherTile.qml
        qml/osd/NotificationPopup.qml
        qml/osd/NotificationBell.qml
        qml/osd/AlarmClearButton.qml
        qml/osd/NotificationHistoryPanel.qml
        qml/widgets/framework/WidgetRegistry.qml
        qml/services/WarningAlarm.qml
        qml/services/VehicleHistory.qml
        qml/widgets/framework/WidgetPages.qml
        qml/widgets/framework/PageBar.qml
        qml/widgets/framework/PageMenu.qml
        qml/widgets/graph/GraphWidget.qml
        qml/widgets/graph/GraphSettings.qml
        qml/widgets/framework/WidgetBase.qml
        qml/widgets/framework/WidgetHost.qml
        qml/widgets/framework/WidgetArea.qml
        qml/widgets/framework/WidgetEditBar.qml
        qml/widgets/decoration/DecorationStore.qml
        qml/widgets/decoration/DecorationLayer.qml
        qml/widgets/decoration/DecorationEditor.qml
        qml/widgets/decoration/DecorationPanel.qml
        qml/widgets/decoration/DecorationPicker.qml
        qml/widgets/decoration/DecorationPanelLayer.qml
        qml/widgets/decoration/DecorationEffects.qml
        qml/widgets/framework/WidgetSettingsBase.qml
        qml/widgets/framework/WidgetSettingsGroup.qml
        qml/widgets/framework/WidgetSettingsDialog.qml
        qml/widgets/framework/WidgetPicker.qml
        qml/settings/WSStepper.qml
        qml/settings/WSTextField.qml
        qml/settings/SettingsColorPalette.qml
        qml/widgets/clock/ClockWidget.qml
        qml/widgets/clock/ClockSettings.qml
        qml/widgets/greeting/GreetingWidget.qml
        qml/widgets/greeting/GreetingSettings.qml
        qml/widgets/gauge/GaugeWidget.qml
        qml/widgets/gauge/GaugeSettings.qml
        qml/widgets/phonestatus/PhoneStatusWidget.qml
        qml/widgets/phonestatus/PhoneStatusSettings.qml
        qml/widgets/phonenotice/PhoneNoticeWidget.qml
        qml/widgets/phonenotice/PhoneNoticeSettings.qml
        qml/widgets/phonecall/PhoneCallWidget.qml
        qml/widgets/phonecall/PhoneCallSettings.qml
        qml/widgets/nowplaying/NowPlayingWidget.qml
        qml/widgets/nowplaying/NowPlayingSettings.qml
        qml/components/MarqueeText.qml
        qml/components/NumberText.qml
        qml/widgets/navigation/NavigationWidget.qml
        qml/widgets/navigation/NavigationSettings.qml
    RESOURCES
        resources/images/YuranuDev_Brush_Script_Logo.png
        resources/fonts/MaterialIcons-Regular.ttf
        resources/fonts/materialdesignicons-webfont.ttf)

target_include_directories(opencruise PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    # qt_add_qml_module が生成する型登録コードは SOURCES のヘッダをファイル名だけで #include するため、
    # VideoSurfaceItem.h のあるフォルダも含める(自前のコードは src/ からの相対パスで #include する)
    ${CMAKE_CURRENT_SOURCE_DIR}/src/androidauto)
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
# 音を ALSA の機器へ直接出す・録る(PulseAudio / PipeWire を通さない。アプリ内の音はアプリ内で混ぜる。src/audio/AlsaAudio)。
# libasound が無いとき(Windows など)は、これまでどおり Qt の音声入出力を使う(sudo apt install libasound2-dev)
# Linux では既定で必須にする(気づかないまま Qt の音声でビルドされないように)。使わないときは -DOPENCRUISE_ENABLE_ALSA=OFF
if(UNIX AND NOT APPLE)
    option(OPENCRUISE_ENABLE_ALSA "ALSA の機器へ直接音を出す(libasound が必要)" ON)
else()
    option(OPENCRUISE_ENABLE_ALSA "ALSA の機器へ直接音を出す(libasound が必要)" OFF)
endif()
if(OPENCRUISE_ENABLE_ALSA)
    pkg_check_modules(ALSA QUIET IMPORTED_TARGET alsa)
    if(NOT ALSA_FOUND)
        message(FATAL_ERROR "ALSA(libasound)が見つかりません。開発用パッケージを入れてください"
                            "(Debian / Ubuntu: sudo apt install libasound2-dev)。"
                            "ALSA を使わずにビルドするときは -DOPENCRUISE_ENABLE_ALSA=OFF")
    endif()
endif()
if(OPENCRUISE_ENABLE_ALSA AND ALSA_FOUND)
    target_sources(opencruise PRIVATE src/audio/AlsaAudio.cpp src/audio/AlsaSoundEffect.cpp)
    target_link_libraries(opencruise PRIVATE PkgConfig::ALSA)
    target_compile_definitions(opencruise PRIVATE OPENCRUISE_WITH_ALSA)
    message(STATUS "ALSA ${ALSA_VERSION}: 音を ALSA の機器へ直接出します")
else()
    message(STATUS "ALSA を使いません(OPENCRUISE_ENABLE_ALSA=OFF): 音は Qt の音声入出力で出します")
endif()
target_compile_options(opencruise PRIVATE -Wall -Wextra)

# ---------------------------------------------------------------------------
# 同梱フォント(Noto Sans JP / LINE Seed JP / IBM Plex Sans JP。いずれも SIL OFL 1.1)。
# 合計 80MB ほどあり、リソース(qrc)に埋め込むとビルドが極端に重くなるため、実行ファイルの隣の fonts/ へコピーし、
# 起動時に AppSettings が読み込む。ライセンス文は各フォルダの OFL.txt。詳細は resources/fonts/README-FONTS.md。
# ---------------------------------------------------------------------------
set(OPENCRUISE_BUNDLED_FONT_DIRS NotoSansJP LINESeedJP IBMPlexSansJP)
foreach(font_dir IN LISTS OPENCRUISE_BUNDLED_FONT_DIRS)
    add_custom_command(TARGET opencruise POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            ${CMAKE_CURRENT_SOURCE_DIR}/resources/fonts/${font_dir}
            $<TARGET_FILE_DIR:opencruise>/fonts/${font_dir}
        COMMENT "フォントをコピー: ${font_dir}")
    install(DIRECTORY resources/fonts/${font_dir} DESTINATION share/opencruise/fonts)
endforeach()
install(FILES resources/fonts/README-FONTS.md DESTINATION share/opencruise/fonts)

# ---------------------------------------------------------------------------
# 効果音(カテゴリごとのフォルダ: sounds/click = 操作音、sounds/start = 起動音、sounds/alert = 警告音、sounds/caution = 注意音。
# WAV のみ。起動音だけは MP3 も使える)。
# 実行ファイルの隣の sounds/ へコピーし、設定「サウンド」の一覧に出す(SystemSound が読む)。
# 既定の Click.wav / Start.wav は、フォルダが無い環境でも鳴らせるようリソースにも埋め込む(上の RESOURCES)。
# ---------------------------------------------------------------------------
add_custom_command(TARGET opencruise POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${CMAKE_CURRENT_SOURCE_DIR}/resources/sounds
        $<TARGET_FILE_DIR:opencruise>/sounds
    COMMENT "効果音をコピー")
install(DIRECTORY resources/sounds/ DESTINATION share/opencruise/sounds)
