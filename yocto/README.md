# OpenCruise 専用 OS(Yocto 6.0 "wrynose")

`scripts/build-os.sh` が、PC の準備・レイヤーの取得・設定・ビルド・USB への書き込みまでを質問形式で行います。

```
scripts/build-os.sh --check       # ビルドできる PC か確認(何も変えない)
scripts/build-os.sh               # ウィザード(PC の準備 → 質問 → 取得 → 設定 → ビルド → 書き込み)
scripts/build-os.sh --build       # 前の答えのままやり直す / 途中から再開
scripts/build-os.sh --flash       # できたイメージを USB メモリ / SSD へ書き込む
scripts/build-os.sh --shell       # bitbake を自分で触るシェル
scripts/build-os.sh --status      # 答え・レイヤーの版・前回のビルド結果
```

作業フォルダは既定で `~/opencruise-yocto`(150GB 前後の空き。`--workdir` で変更)。普通のユーザーで実行します(必要なところだけ sudo)。

## 構成

- poky は wrynose から無いので、openembedded-core(wrynose)+ bitbake(oe-core の `BB_MIN_VERSION` から決めるブランチ。今は 2.18)を別に取る
- meta-openembedded(meta-oe・meta-python)、meta-qt6(wrynose 対応の最新 6.x。今は 6.12)、meta-intel(x86 実機のみ)
- 使った版は `<作業フォルダ>/layers.lock` に記録し、次回も同じ版を使う。最新にするのは `--update`
- `build/conf/auto.conf` にウィザードの答えを書く(毎回作り直す)。`local.conf` は Yocto のひな形のままで、自分の設定はここに足す(auto.conf より優先)
- Ubuntu 23.10 以降は AppArmor が BitBake のユーザー名前空間を止めるので、ウィザードが `/etc/apparmor.d/opencruise-bitbake` を足す

## レイヤーの中身(`meta-opencruise/`)

| 場所 | 内容 |
|---|---|
| `conf/distro/opencruise-os.conf` | OS の方針(systemd、X11/Wayland なし、ALSA のみ)。名前はアプリのレシピ `opencruise` と別にする(同名だと OVERRIDES と衝突してエラー) |
| `recipes-core/images/qt-appliance-image.bb` | Qt6 専用機の共通ベース(eglfs・ALSA・USB・UVC カメラ) |
| `recipes-core/images/opencruise-image.bb` | 上のベース + OpenCruise アプリ |
| `recipes-opencruise/opencruise/` | アプリのレシピ(qt6-cmake)、自動起動、udev・polkit の権限、専用ユーザー |
| `files/wic/opencruise-x86.wks.in` | x86 UEFI ディスク(systemd-boot + ルート + /home)。wrynose は `files/wic/` しか探さない |

## 確認済み・未確認

- 確認済み: 実際の wrynose のレイヤーで、取得 → 設定 → `bitbake -p`(全レシピの読み込み)→ `bitbake -n opencruise-image`(依存関係の解決)がエラー・警告なしで通る(intel-corei7-64 / qemux86-64、Android Auto あり・なし、読み取り専用ルート)
- 未確認: 実際のコンパイル(数時間かかる)と実機での起動

失敗したら `<作業フォルダ>/logs/`(`build-*.log` と、失敗した作業のログの写し `failed-*.log`)を見てください。
