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

IMAGE_INSTALL += "${QT_APPLIANCE_QT} ${QT_APPLIANCE_BASE} ${QT_APPLIANCE_NET}"
