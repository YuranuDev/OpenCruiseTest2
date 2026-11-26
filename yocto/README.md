# OpenCruise 専用 OS(Yocto 6.0 "wrynose")

`scripts/build-os.sh` が、PC の準備・レイヤーの取得・設定・ビルド・USB への書き込みまでを質問形式で行います。

```
scripts/build-os.sh --check       # ビルドできる PC か確認(何も変えない)
scripts/build-os.sh               # ウィザード(PC の準備 → 質問 → 取得 → 設定 → ビルド → 書き込み)
scripts/build-os.sh --build       # 前の答えのままやり直す / 途中から再開
scripts/build-os.sh --flash       # できたイメージを USB メモリ / SSD へ書き込む
scripts/build-os.sh --shell       # bitbake を自分で触るシェル
scripts/build-os.sh --status      # 答え・レイヤーの版・前回のビルド結果
scripts/build-os.sh --app-update  # アプリだけビルドして更新ファイル(.ocapp)を作る(下の「アプリの更新」)
```

作業フォルダは既定で `~/opencruise-yocto`(150GB 前後の空き。`--workdir` で変更)。普通のユーザーで実行します(必要なところだけ sudo)。

## 構成

- poky は wrynose から無いので、openembedded-core(wrynose)+ bitbake(oe-core の `BB_MIN_VERSION` から決めるブランチ。今は 2.18)を別に取る
- meta-openembedded(meta-oe・meta-python・meta-networking)、meta-qt6(wrynose 対応の最新 6.x。今は 6.12)、meta-intel(x86 実機のみ)
- 使った版は `<作業フォルダ>/layers.lock` に記録し、次回も同じ版を使う。最新にするのは `--update`
- `build/conf/auto.conf` にウィザードの答えを書く(毎回作り直す)。`local.conf` は Yocto のひな形のままで、自分の設定はここに足す(auto.conf より優先)
- Ubuntu 23.10 以降は AppArmor が BitBake のユーザー名前空間を止めるので、ウィザードが `/etc/apparmor.d/opencruise-bitbake` を足す

## レイヤーの中身(`meta-opencruise/`)

| 場所 | 内容 |
|---|---|
| `conf/distro/opencruise-os.conf` | OS の方針(systemd、X11/Wayland なし、ALSA のみ)。名前はアプリのレシピ `opencruise` と別にする(同名だと OVERRIDES と衝突してエラー) |
| `recipes-core/images/qt-appliance-image.bb` | Qt6 専用機の共通ベース(eglfs・ALSA・USB・UVC カメラ・NetworkManager(Wi-Fi)・avahi(mDNS)) |
| `recipes-core/images/opencruise-image.bb` | 上のベース + OpenCruise アプリ |
| `recipes-opencruise/opencruise/` | アプリのレシピ(qt6-cmake)、自動起動(`opencruise-launch` が版を選ぶ)、USB メモリの読み取り専用マウント、udev・polkit の権限、専用ユーザー |
| `files/wic/opencruise-x86.wks.in` | x86 UEFI ディスク(GRUB + ルート + /home 2GB)。wrynose は `files/wic/` しか探さない |

## アプリの更新(USB メモリ・ネット)

OS を書き込み直さずに、OpenCruise アプリだけを入れ替えられます(設定 > システム > アップデート)。

1. ビルド PC で `scripts/build-os.sh --app-update` → `<作業フォルダ>/updates/opencruise-app-<ビルド番号>.ocapp`
2. 車へ渡す
   - USB: USB メモリの直下か `opencruise-update/` にコピーして挿す(読み取り専用で自動マウントされ、設定画面に出る)
   - ネット: `scripts/update-server.sh <作業フォルダ>/updates` を動かし、車から「確認」。車は `http://opencruise-dev.local:8765` を探すので、
     この PC のホスト名を `opencruise-dev` にする(仮想マシンの中なら、ポート 8765 を外へ転送し、外側の PC のホスト名を opencruise-dev にする)。
     車は Wi-Fi(設定 > ネットワーク)・有線 LAN・USB テザリングでつなぐ
3. 「更新する」→「今すぐ再起動」。新しい版は `/home/opencruise/app/versions/` に入り、`opencruise-launch` が起動する
   - 新しい版が 3 回続けて起動できなければ、前の版(無ければ OS に入っている版)へ自動で戻る
   - 設定画面の「前の版に戻す」で手でも戻せる
- `.ocapp` は tar(`manifest.json` + `payload.tar.gz`)。入れる前に sha256 で壊れていないかを確かめる(署名は無い)
- 更新できるのはアプリ(実行ファイル・フォント・効果音)だけ。OS・ライブラリ・udev や polkit の設定を変えたときは OS を書き込み直す
  (OS の A/B 更新は次の段階で入れる予定)

## 公開用のビルド(イメージを配るとき)

開発用のビルドは、SSH とパスワードなしの root ログインが入っていて、そのまま配ると誰でも root で入れてしまいます。配るイメージは、次の手順で作ります。

```
scripts/build-os.sh --release          # 公開用のビルド(ウィザードで「公開用のビルド: はい」でも同じ)
scripts/build-os.sh --release-pack     # 配るものを <作業フォルダ>/release/<機種>-<日付>/ に集める
```

- **公開用のビルドでの違い**: SSH・パスワードなしの root を入れません。`license.manifest` とパッケージごとのライセンス文をイメージの `/usr/share/common-licenses/` に入れ、GPL / LGPL のソースを `build/tmp/deploy/sources/` に集めます(`archiver`)。
- **アプリのソース**: 配るイメージは、アプリのソースを「GitHub の main」にして作ってください(push していない手元の変更が入らず、配るソースとイメージの中身が一致します)。
- **まとめるもの**: イメージ(`.wic` は zstd で圧縮)、`license.manifest`、`licenses.tar.xz`、`sources.tar`、`layers.lock`(使ったレイヤーの版)、`LICENSE`、`THIRD-PARTY-NOTICES.md`、`SHA256SUMS`。これをそのままリリースに添付します。
- **まだ手でやること**: README に「検証専用・公開ネットワークにつながない」などの注意を書く。H.264 の特許(`openh264`)と、効果音・音声・画像(`extras/`)の権利を確認する。`linux-firmware` を使うものだけに絞る(今は多くのファームウェアが入ります)。

## タッチが効かないとき

ゲストに入って(SSH か、シリアルコンソールから root で)、上から順に確かめます。どこで止まるかで原因が分かります。

```
ls -l /dev/input/                       # event* があるか。group が input で mode が 660 か
cat /proc/bus/input/devices             # タッチパネルが「入力デバイス」として見えているか(名前・Handlers=eventN)
libinput list-devices                   # libinput が「タッチスクリーン(Capabilities: touch)」として認識しているか
systemctl stop opencruise               # アプリを止めてから、指で触りながら次を実行して、TOUCH_DOWN が出るか見る
libinput debug-events
evtest /dev/input/eventN                # libinput を通さない生のイベント(N は上の番号)
```

- **`/proc/bus/input/devices` に無い**: カーネルがタッチパネルを認識していません。`lsusb` で見えるか、`dmesg | grep -i -E 'hid|touch|i2c'` を見ます。I²C 接続のものは、そのドライバ(`i2c-hid` など)が要ります。
- **`event*` が root:root や 600 で、group が input でない**: udev の規則が効いていません。アプリは `input` グループで動くので、権限があるか `ls -l` と `id opencruise` で確かめます。
- **`libinput list-devices` に出ない、`debug-events` で何も出ない**: libinput が権限か udev の情報(`udevadm info -q property -n /dev/input/eventN` の `ID_INPUT_TOUCHSCREEN=1`)で認識できていません。
- **`debug-events` では出るのに、アプリで効かない**: Qt 側の問題です。`/etc/opencruise/opencruise.env` の `QT_LOGGING_RULES=qt.qpa.input=true` を有効にして `systemctl restart opencruise` し、`journalctl -u opencruise` を見ます。それでも直らなければ、`QT_QPA_EGLFS_NO_LIBINPUT=1` と `QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS=/dev/input/eventN` を有効にして evdev に切り替えて試します。
- **触った位置がずれる・向きが違う**: `/etc/udev/rules.d/` に `LIBINPUT_CALIBRATION_MATRIX` の規則を入れます(`scripts/install.sh` が Debian 用に作るものと同じ書き方です)。
- **一覧にタッチパネルが無い(カーネルが認識していない)**: 内蔵のタッチパネルは I²C 接続のことが多く、`files/kernel/opencruise-touch.cfg`(`i2c-hid`・`hid-multitouch`・Intel の LPSS と GPIO のドライバ)を、レイヤーがカーネルに足します。カーネルの作り直し(数十分)が要ります。入ったかは、実機で `zcat /proc/config.gz | grep -E 'I2C_HID|HID_MULTITOUCH|PINCTRL_SUNRISEPOINT'` で確かめます。
- **QEMU で試すとき**: `-device usb-tablet` は「タッチスクリーン」ではなく、絶対位置のマウスとして見えます。タップやドラッグは効きますが、`Capabilities: touch` にはなりません。タッチ専用の処理(マルチタッチなど)の確認は実機でします。

## 確認済み・未確認

- 確認済み: 実際の wrynose のレイヤーで、取得 → 設定 → `bitbake -p`(全レシピの読み込み)→ `bitbake -n opencruise-image`(依存関係の解決)がエラー・警告なしで通る(intel-corei7-64 / qemux86-64、Android Auto あり・なし、読み取り専用ルート)
- 確認済み(アプリの更新): 更新ファイルの作成、USB とネット(HTTP)からの取り込み・sha256 の確認・展開・切り替え、
  `opencruise-launch` の版の選択と 3 回失敗したときの戻し(PC 上で、ダミーのアプリで)
- 未確認: 実際のコンパイル(数時間かかる)と実機での起動、GRUB での起動、Wi-Fi・USB の自動マウントの実機での動作

失敗したら `<作業フォルダ>/logs/`(`build-*.log` と、失敗した作業のログの写し `failed-*.log`)を見てください。
