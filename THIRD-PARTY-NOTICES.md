# 使用しているもののライセンス

OpenCruise 自体のライセンスは、リポジトリ直下の [LICENSE](LICENSE)(GNU General Public License バージョン 3 またはそれ以降)です。
このファイルは、このリポジトリに入っている他者のコード・素材と、OS イメージに入る主な部品のライセンスをまとめたものです。

イメージに入る全部品のライセンスの一覧は、公開用ビルドの `license.manifest`(イメージの `/usr/share/common-licenses/` と、リリースに添付)にあります。

## このリポジトリに入っているもの

| もの | 場所 | ライセンス | 著作権・出典 |
|---|---|---|---|
| aasdk(Android Auto 接続ライブラリ) | `aasdk/`(全文は `aasdk/LICENSE`)。本アプリの修正は `patches/aasdk-usb-hotplug-handle.patch` | GPL-3.0-or-later | Copyright (C) 2018 f1x.studio (Michal Szwaj) / (C) 2024 CubeOne (Simon Dean)(ソースの先頭の表記による) |
| Noto Sans JP | `app/resources/fonts/NotoSansJP/` | SIL OFL 1.1(`OFL.txt`) | © 2014-2021 Adobe |
| LINE Seed JP | `app/resources/fonts/LINESeedJP/` | SIL OFL 1.1(`OFL.txt`) | © LY Corporation |
| IBM Plex Sans JP | `app/resources/fonts/IBMPlexSansJP/` | SIL OFL 1.1(`OFL.txt`) | Copyright © 2017 IBM Corp. |
| Material Icons | `app/resources/fonts/`(`LICENSE-MaterialIcons.txt`) | Apache-2.0 | Google |
| Material Design Icons | `app/resources/fonts/`(`LICENSE-MaterialDesignIcons.txt`) | Apache-2.0 | Pictogrammers |
| 効果音 | `app/resources/sounds/` | CC BY 4.0 | OtoLogic (https://otologic.jp)。`caution/Caution.wav` はこのプロジェクトで合成した音 |
| 読み上げ音声 | `app/resources/sounds/start/` | 生成に使ったモデル(コハク)のライセンス ACML 1.0 に従う | AivisSpeech (https://aivis-project.com) で作成 |

フォントと音の詳しい出典は `app/resources/fonts/README-FONTS.md` と `app/resources/sounds/CREDITS.md` にあります。

## OS イメージに入る主な部品

(バージョンと正確なライセンス表記は、ビルドで作られる `license.manifest` が正です。)

| 部品 | ライセンス | 補足 |
|---|---|---|
| Qt 6(qtbase・qtdeclarative・qtmultimedia など) | LGPL-3.0(Qt Company の商用ライセンスは使っていません) | 共有ライブラリとして使っています。ソースは https://download.qt.io/ と、リリースに添付の `sources.tar` |
| OpenH264 | BSD-2-Clause | ソースからビルドしたもので、Cisco のビルド済みバイナリではありません。H.264 の特許の許諾は含まれません(非商用・自己責任。README の「H.264 の特許について」を参照) |
| libusb | LGPL-2.1-or-later | |
| ALSA(alsa-lib) | LGPL-2.1-only など | |
| protobuf | BSD-3-Clause | |
| abseil-cpp | Apache-2.0 | |
| mpg123 | LGPL-2.1-only | |
| Linux カーネル | GPL-2.0-only(syscall note つき) | ソースはリリースに添付の `sources.tar` |
| systemd、bash、tar、gzip など | GPL / LGPL | ソースはリリースに添付の `sources.tar` |

GPL / LGPL の部品のソースは、公開用ビルド(`scripts/build-os.sh --release`)が集め、`--release-pack` でリリース用にまとめます。

## 商標

Android、Android Auto は Google LLC の商標です。このプロジェクトは Google LLC と提携・承認の関係にありません。
