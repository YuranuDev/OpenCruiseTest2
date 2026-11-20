# OpenCruise 専用 OS(Yocto)

`scripts/build-os.sh` が、Yocto の取得・設定・ビルド・USB への書き込みまでを質問形式で行います。Yocto を知らなくても使えます。

```
scripts/build-os.sh --check       # ビルドできる PC か確認(何も変えない)
scripts/build-os.sh               # ウィザード(質問に答える → 取得 → 設定 → ビルド)
scripts/build-os.sh --build       # 前の答えのままビルドだけやり直す / 途中から再開
scripts/build-os.sh --flash       # できたイメージを USB メモリ / SSD へ書き込む
scripts/build-os.sh --shell       # bitbake を自分で触るシェル
```

作業フォルダは既定で `~/opencruise-yocto`(100GB 前後の空きが要る。`--workdir` で変更)。初回のビルドは数時間かかります。

## レイヤーの中身(`meta-opencruise/`)

| 場所 | 内容 |
|---|---|
| `conf/distro/opencruise.conf` | OS の方針(systemd、X11/Wayland なし、ALSA のみ) |
| `recipes-core/images/qt-appliance-image.bb` | Qt6 専用機の共通ベース(eglfs・ALSA・USB・UVC カメラ) |
| `recipes-core/images/opencruise-image.bb` | 上のベース + OpenCruise アプリ |
| `recipes-opencruise/opencruise/` | アプリのレシピ、自動起動(systemd)、udev・polkit の権限、専用ユーザー |
| `wic/opencruise-x86.wks.in` | x86 UEFI ディスク(EFI + ルート + /home) |

## 未検証・既知のリスク

実際の bitbake ビルドは未実行です(構文チェックのみ)。初回は、次の点で止まる可能性があります。

- aasdk の protobuf(Yocto の protobuf は新しく Abseil が要る)。止まったらウィザードで Android Auto を「いいえ」にする
- `cmake_qt6` クラス名、meta-qt6 のブランチと Yocto の対応
- wic の `.wks.in` での変数展開、`/home` 用パーティション
- 起動画面(Plymouth)の引き継ぎ、CF-MX5 の AC 投入起動(`scripts/cf-mx5`)は未対応

失敗したら `<作業フォルダ>/logs/` のログを見てください。
