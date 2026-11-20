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
"
SRCREV = "${AUTOREV}"
PV = "0.1.0+git"

# 取り込んだソースとレシピ付属ファイルの置き場所は、Yocto のバージョンで WORKDIR / UNPACKDIR と違うので両方に対応する
OC_UNPACK = "${@d.getVar('UNPACKDIR') or d.getVar('WORKDIR')}"
S = "${OC_UNPACK}/opencruise-src"

# もし「cmake_qt6 が見つからない」と言われたら qt6-cmake に変える(meta-qt6 のバージョンで名前が違う場合)
inherit cmake_qt6 pkgconfig systemd useradd

DEPENDS = "qtbase qtdeclarative qtmultimedia qtshadertools ffmpeg alsa-lib libdrm"

# Android Auto(aasdk)。外すと UI だけのビルドになり、接続は「利用不可」と出る。
# aasdk の protobuf 生成には、ホスト側の protoc(protobuf-native)が要る。Yocto の protobuf は新しく Abseil が要る。
PACKAGECONFIG ??= "aasdk"
PACKAGECONFIG[aasdk] = "-DOPENCRUISE_ENABLE_AASDK=ON,-DOPENCRUISE_ENABLE_AASDK=OFF,boost libusb1 openssl protobuf protobuf-native abseil-cpp"

EXTRA_OECMAKE += " \
    -DCMAKE_BUILD_TYPE=Release \
    -DOPENCRUISE_ENABLE_ALSA=ON \
    -DProtobuf_PROTOC_EXECUTABLE=${STAGING_BINDIR_NATIVE}/protoc \
"

# 実行時に要るもの(QML のモジュールと、権限・電源操作)
RDEPENDS:${PN} += " \
    qtdeclarative-qmlplugins qtmultimedia-qmlplugins qt5compat-qmlplugins \
    alsa-lib ffmpeg polkit \
"

do_install() {
    # app/CMakeLists.txt には実行ファイルの install(TARGETS) が無いので手で入れる。
    # フォントと効果音は、アプリが「実行ファイルの隣の ../share/opencruise/」を探すので、そこへ置く。
    install -d ${D}${bindir}
    install -m 0755 ${B}/app/opencruise ${D}${bindir}/opencruise

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
    for t in sleep suspend hibernate hybrid-sleep suspend-then-hibernate; do
        ln -sf /dev/null ${D}${sysconfdir}/systemd/system/$t.target
    done

    # 電源オフ・再起動(polkit)、Android Auto の USB 権限、バックライトの明るさの書き込み権限
    install -d ${D}${sysconfdir}/polkit-1/rules.d
    install -m 0644 ${OC_UNPACK}/50-opencruise.rules ${D}${sysconfdir}/polkit-1/rules.d/50-opencruise.rules
    install -d ${D}${sysconfdir}/udev/rules.d
    install -m 0644 ${OC_UNPACK}/51-opencruise-android.rules ${D}${sysconfdir}/udev/rules.d/51-opencruise-android.rules
    install -m 0644 ${OC_UNPACK}/91-opencruise-backlight-permission.rules ${D}${sysconfdir}/udev/rules.d/91-opencruise-backlight-permission.rules
}

FILES:${PN} += " \
    ${datadir}/opencruise \
    ${sysconfdir}/opencruise \
    ${nonarch_libdir}/tmpfiles.d \
"
CONFFILES:${PN} += "${sysconfdir}/opencruise/opencruise.env"

SYSTEMD_SERVICE:${PN} = "opencruise.service"
SYSTEMD_AUTO_ENABLE = "enable"

# アプリを動かす専用ユーザー(画面・入力・音・カメラ・USB・シリアルのグループ)
USERADD_PACKAGES = "${PN}"
GROUPADD_PARAM:${PN} = "-r plugdev; -r render; -r input"
USERADD_PARAM:${PN} = "-u 1000 -U -d /home/opencruise -s /bin/sh -G video,audio,input,render,plugdev,dialout opencruise"
