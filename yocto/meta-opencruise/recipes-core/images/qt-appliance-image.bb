SUMMARY = "Qt6 アプライアンス用の共通ベースイメージ(eglfs・ALSA・USB・カメラ)"
DESCRIPTION = "Qt Quick(QML)アプリを 1 つ全画面で動かす専用機のための土台。OpenCruise 以外の Qt アプリもこの上に載せられる。"
LICENSE = "MIT"

inherit core-image

IMAGE_FEATURES += "${@oe.utils.conditional('OPENCRUISE_READONLY_ROOTFS', '1', 'read-only-rootfs', '', d)}"
IMAGE_LINGUAS = ""

# Qt6(meta-qt6): 画面は eglfs。QML のモジュール(Quick Controls・Multimedia・Qt5Compat など)も実行時に要る。
QT_APPLIANCE_QT = " \
    qtbase qtbase-plugins \
    qtdeclarative qtdeclarative-qmlplugins \
    qtmultimedia qtmultimedia-plugins qtmultimedia-qmlplugins \
    qtshadertools \
    qt5compat qt5compat-qmlplugins \
"

# Qt Multimedia のバックエンドは GStreamer(ALSA だけの構成では FFmpeg バックエンドが使えない: Qt 6.12 は Linux で PulseAudio / PipeWire が必須)。
# バックカメラ(UVC。QCamera)は v4l2src と、MJPEG 用の jpeg デコーダ、色変換・拡縮が実行時に要る。
# MP3 の効果音・起動音(AlsaSoundEffect が QAudioDecoder で読む。Qt 6.12 の中身は playbin3 → appsink)には、
# MPEG 音声の切り出し(audioparsers の mpegaudioparse)・デコーダ(mpg123)・ID3 タグの読み飛ばし(id3demux)が要る。
# 同梱の resources/sounds/start/Bell*.mp3 はどれも ID3 タグ付きで、id3demux が無いと「プラグインが無い」で読めない。
QT_APPLIANCE_GST = " \
    gstreamer1.0 \
    gstreamer1.0-plugins-base gstreamer1.0-plugins-base-playback gstreamer1.0-plugins-base-typefindfunctions \
    gstreamer1.0-plugins-base-videoconvertscale gstreamer1.0-plugins-base-videorate \
    gstreamer1.0-plugins-base-audioconvert gstreamer1.0-plugins-base-audioresample gstreamer1.0-plugins-base-alsa \
    gstreamer1.0-plugins-base-app \
    gstreamer1.0-plugins-good-video4linux2 gstreamer1.0-plugins-good-jpeg \
    gstreamer1.0-plugins-good-audioparsers gstreamer1.0-plugins-good-mpg123 gstreamer1.0-plugins-good-id3demux \
"

# 音は ALSA 直(アプリが機器を占有して中で混ぜる)・USB・カメラ(UVC)・タッチ入力
QT_APPLIANCE_BASE = " \
    mesa libdrm libinput \
    fontconfig ttf-dejavu-sans \
    alsa-utils alsa-plugins \
    v4l-utils usbutils evtest \
    kernel-modules \
    tzdata \
"

# ネットワーク: NetworkManager(Wi-Fi・有線 LAN・USB テザリング。アプリの Wi-Fi 設定は nmcli を使う)。
# avahi + nss-mdns: 「opencruise-dev.local」のような名前で開発 PC を探す(ネット経由のアプリ更新)
QT_APPLIANCE_NET = " \
    networkmanager networkmanager-nmcli networkmanager-wifi wpa-supplicant \
    avahi-daemon avahi-libnss-mdns \
"

IMAGE_INSTALL += "${QT_APPLIANCE_QT} ${QT_APPLIANCE_GST} ${QT_APPLIANCE_BASE} ${QT_APPLIANCE_NET}"
