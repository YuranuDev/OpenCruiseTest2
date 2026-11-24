SUMMARY = "OpenCruise 車載システム(Qt Quick + aasdk)"
DESCRIPTION = "Android Auto の映像・メーター・バックカメラなどを表示する車載システムのアプリ。"
HOMEPAGE = "https://github.com/YuranuDev/OpenCruiseTest2"
LICENSE = "CLOSED"

# 取り込み元。scripts/build-os.sh で「このフォルダの中身を使う」を選ぶと、local.conf の externalsrc がこの SRC_URI より優先される。
SRC_URI = " \
    git://github.com/YuranuDev/OpenCruiseTest2.git;protocol=https;branch=main;destsuffix=opencruise-src \
    file://opencruise.service \
    file://opencruise.env \
    file://opencruise-tmpfiles.conf \
    file://opencruise-logind.conf \
    file://50-opencruise.rules \
    file://51-opencruise-android.rules \
    file://91-opencruise-backlight-permission.rules \
    file://opencruise-launch \
    file://opencruise-usb-mount \
    file://opencruise-usb-mount@.service \
    file://80-opencruise-usb.rules \
"
SRCREV = "${AUTOREV}"
PV = "0.1.0+git"

# 取り込んだソースとレシピ付属ファイルの置き場所は、Yocto のバージョンで WORKDIR / UNPACKDIR と違うので両方に対応する
OC_UNPACK = "${@d.getVar('UNPACKDIR') or d.getVar('WORKDIR')}"
S = "${OC_UNPACK}/opencruise-src"

# meta-qt6 6.11 / 6.12(wrynose 対応の版)には cmake_qt6 は無く、アプリも qt6-cmake を使う
inherit qt6-cmake pkgconfig systemd useradd

DEPENDS = "qtbase qtdeclarative qtdeclarative-native qtmultimedia qtshadertools openh264 alsa-lib libdrm"

# Android Auto(aasdk)。外すと UI だけのビルドになり、接続は「利用不可」と出る。
# aasdk の protobuf 生成には、ホスト側の protoc(protobuf-native)が要る。Yocto の protobuf は新しく Abseil が要る。
# ターゲット用の protobuf は protoc を作らない(CMake の設定に protobuf::protoc が無い)ので、Protobuf_PROTOC_EXECUTABLE で
# ホスト側の protoc を渡す(aasdk/protobuf/CMakeLists.txt がそれで protobuf::protoc を作る)。
PACKAGECONFIG ??= "aasdk"
PACKAGECONFIG[aasdk] = "-DOPENCRUISE_ENABLE_AASDK=ON,-DOPENCRUISE_ENABLE_AASDK=OFF,boost libusb1 openssl protobuf protobuf-native abseil-cpp"

# CMAKE_POLICY_VERSION_MINIMUM: wrynose の CMake は 4.x で、aasdk の cmake_modules/gitversion.cmake(cmake_minimum_required 3.0)を
# そのままでは受け付けないため
EXTRA_OECMAKE += " \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DOPENCRUISE_ENABLE_ALSA=ON \
    -DProtobuf_PROTOC_EXECUTABLE=${STAGING_BINDIR_NATIVE}/protoc \
"

# 実行時に要るもの(QML のモジュールと、権限・電源操作。アプリの更新の展開に tar・gzip、Wi-Fi の設定に nmcli)
RDEPENDS:${PN} += " \
    qtdeclarative-qmlplugins qtmultimedia-qmlplugins qt5compat-qmlplugins \
    alsa-lib openh264 polkit \
    tar gzip networkmanager-nmcli \
"

do_install() {
    # app/CMakeLists.txt には実行ファイルの install(TARGETS) が無いので手で入れる。
    # フォントと効果音は、アプリが「実行ファイルの隣の ../share/opencruise/」を探すので、そこへ置く。
    install -d ${D}${bindir}
    install -m 0755 ${B}/app/opencruise ${D}${bindir}/opencruise

    # 同梱の aasdk は Linux では共有ライブラリ(libaasdk.so.* / libaap_protobuf.so.*)になり、アプリはそれを実行時に読む。
    # install(TARGETS) は aasdk 側も EXCLUDE_FROM_ALL で使えないので、版付きの実体と soname のリンクだけを手で入れる
    # (開発用の libaasdk.so は入れない)。aasdk を使わない構成(PACKAGECONFIG から aasdk を外す)ではファイルが無いので飛ばす。
    if ${@bb.utils.contains('PACKAGECONFIG', 'aasdk', 'true', 'false', d)}; then
        install -d ${D}${libdir}
        for f in ${B}/aasdk/lib/libaasdk.so.* ${B}/aasdk/lib/libaap_protobuf.so.*; do
            cp -P "$f" ${D}${libdir}/
        done
    fi

    install -d ${D}${datadir}/opencruise/fonts
    for d in NotoSansJP LINESeedJP IBMPlexSansJP; do
        cp -r ${S}/app/resources/fonts/$d ${D}${datadir}/opencruise/fonts/
    done
    install -m 0644 ${S}/app/resources/fonts/README-FONTS.md ${D}${datadir}/opencruise/fonts/

    install -d ${D}${datadir}/opencruise/sounds
    cp -r ${S}/app/resources/sounds/. ${D}${datadir}/opencruise/sounds/

    # 自動起動(systemd)と環境ファイル(タッチパネルなどはここで指定する)
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${OC_UNPACK}/opencruise.service ${D}${systemd_system_unitdir}/opencruise.service
    install -d ${D}${sysconfdir}/opencruise
    install -m 0644 ${OC_UNPACK}/opencruise.env ${D}${sysconfdir}/opencruise/opencruise.env

    # /home が空の書き込み領域でも、ユーザーのフォルダを起動時に作る
    install -d ${D}${nonarch_libdir}/tmpfiles.d
    install -m 0644 ${OC_UNPACK}/opencruise-tmpfiles.conf ${D}${nonarch_libdir}/tmpfiles.d/opencruise.conf

    # 車載 PC なので、蓋を閉じても・放っておいてもスリープしない
    install -d ${D}${sysconfdir}/systemd/logind.conf.d
    install -m 0644 ${OC_UNPACK}/opencruise-logind.conf ${D}${sysconfdir}/systemd/logind.conf.d/opencruise.conf
    install -d ${D}${sysconfdir}/systemd/system
    for t in sleep suspend hibernate hybrid-sleep suspend-then-hibernate; do
        ln -sf /dev/null ${D}${sysconfdir}/systemd/system/$t.target
    done

    # 電源オフ・再起動(polkit)、Android Auto の USB 権限、バックライトの明るさの書き込み権限
    install -d ${D}${sysconfdir}/polkit-1/rules.d
    install -m 0644 ${OC_UNPACK}/50-opencruise.rules ${D}${sysconfdir}/polkit-1/rules.d/50-opencruise.rules
    install -d ${D}${sysconfdir}/udev/rules.d
    install -m 0644 ${OC_UNPACK}/51-opencruise-android.rules ${D}${sysconfdir}/udev/rules.d/51-opencruise-android.rules
    install -m 0644 ${OC_UNPACK}/91-opencruise-backlight-permission.rules ${D}${sysconfdir}/udev/rules.d/91-opencruise-backlight-permission.rules

    # アプリの更新: 起動する版を選ぶ起動スクリプト(opencruise.service の ExecStart)と、ビルド番号
    # (更新ファイルと比べて新しいかを決める。scripts/make-app-update.sh も同じファイルを読む)
    install -m 0755 ${OC_UNPACK}/opencruise-launch ${D}${bindir}/opencruise-launch
    date -u +%Y%m%d%H%M%S > ${D}${datadir}/opencruise/build-id

    # USB メモリを挿したら読み取り専用でつなぐ(更新ファイルを USB から入れる)
    install -d ${D}${libexecdir}
    install -m 0755 ${OC_UNPACK}/opencruise-usb-mount ${D}${libexecdir}/opencruise-usb-mount
    install -m 0644 ${OC_UNPACK}/opencruise-usb-mount@.service ${D}${systemd_system_unitdir}/opencruise-usb-mount@.service
    install -m 0644 ${OC_UNPACK}/80-opencruise-usb.rules ${D}${sysconfdir}/udev/rules.d/80-opencruise-usb.rules
}

# opencruise-usb-mount@.service は udev(80-opencruise-usb.rules)から USB メモリごとに起動するテンプレートなので、
# SYSTEMD_SERVICE には入れない(有効化しない)。systemd.bbclass は SYSTEMD_SERVICE のユニットしか自動で入れないので、ここで入れる
FILES:${PN} += " \
    ${datadir}/opencruise \
    ${sysconfdir}/opencruise \
    ${nonarch_libdir}/tmpfiles.d \
    ${systemd_system_unitdir}/opencruise-usb-mount@.service \
"
CONFFILES:${PN} += "${sysconfdir}/opencruise/opencruise.env"

SYSTEMD_SERVICE:${PN} = "opencruise.service"
SYSTEMD_AUTO_ENABLE = "enable"

# アプリを動かす専用ユーザー(画面・入力・音・カメラ・USB・シリアルのグループ)
USERADD_PACKAGES = "${PN}"
GROUPADD_PARAM:${PN} = "-r plugdev; -r render; -r input"
USERADD_PARAM:${PN} = "-u 1000 -U -d /home/opencruise -s /bin/sh -G video,audio,input,render,plugdev,dialout opencruise"
