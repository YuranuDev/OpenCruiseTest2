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

## 確認済み・未確認

- 確認済み: 実際の wrynose のレイヤーで、取得 → 設定 → `bitbake -p`(全レシピの読み込み)→ `bitbake -n opencruise-image`(依存関係の解決)がエラー・警告なしで通る(intel-corei7-64 / qemux86-64、Android Auto あり・なし、読み取り専用ルート)
- 確認済み(アプリの更新): 更新ファイルの作成、USB とネット(HTTP)からの取り込み・sha256 の確認・展開・切り替え、
  `opencruise-launch` の版の選択と 3 回失敗したときの戻し(PC 上で、ダミーのアプリで)
- 未確認: 実際のコンパイル(数時間かかる)と実機での起動、GRUB での起動、Wi-Fi・USB の自動マウントの実機での動作

失敗したら `<作業フォルダ>/logs/`(`build-*.log` と、失敗した作業のログの写し `failed-*.log`)を見てください。
