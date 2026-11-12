# CF-MX5 の隠し BIOS 設定(AC 投入で自動起動など)

Panasonic CF-MX5 の BIOS Setup に表示されない設定を、Linux から 1 項目ずつ読み書きするスクリプトです。
車載 PC を ACC 連動の給電だけで起動させる(State After G3 = S0)のが主な目的です。

BIOS のフラッシュには書き込まず、NVRAM の UEFI 変数 `Setup`(GUID `EC87D643-EBA4-4BB5-A1E5-3F3E36B20DA9`)の 1 バイトだけを変えます。

## AC 投入で自動起動(おすすめ: install-afterg3.sh)

実機では `Setup` 変数が OS(Linux / Windows)から隠されていて、下の `cfmx5-setupvar.py` では書き換えられませんでした。
代わりに、PCH の AFTERG3_EN(PMC `00:1f.2` の `0xA4` bit0)を、起動時とシャットダウン時に systemd で 0 にします。
BIOS にも NVRAM にも触りません。

```
sudo scripts/cf-mx5/install-afterg3.sh install    # 入れる(AC 投入で起動する)
sudo scripts/cf-mx5/install-afterg3.sh status     # 状態を見る
sudo scripts/cf-mx5/install-afterg3.sh uninstall  # 外す(bit0 を 1 に戻す = 起動しない)
```

- `install` は `/etc/systemd/system/afterg3.service` を作って有効にし、その場で bit0 を 0 にします。
- `00:1f.2` が Sunrise Point-LP の PMC(8086:9d21)でなければ何もしません。
- 確認: `sudo poweroff` → AC を抜いて 10 秒 → 挿して起動すれば成功。
- 正常にシャットダウンしなかった場合も、直前の起動時に 0 を書いているので通常は問題ありません。

## RU.efi を USB メモリなしで使う(setup-ru-shell.sh)

バッテリーが付いたままだと AFTERG3_EN は効かない(AC を抜いても G3 にならない)ので、
Panasonic 独自の Power On AC(Setup の 0x97C)を RU.efi で書き換えるときに使います。
内蔵 ESP の `EFI/tools/` に UEFI Shell(pbatard/UEFI-Shell 25H1、SHA-256 固定)と RU.efi を置き、GRUB に項目を足します。

```
# RU.efi は配布元(ruexe.blogspot.com)から自分でダウンロードしておく
sudo scripts/cf-mx5/setup-ru-shell.sh install ~/Downloads/RU.zip   # RU.efi 単体でも可
sudo scripts/cf-mx5/setup-ru-shell.sh boot        # 次の 1 回だけ UEFI Shell で起動
sudo scripts/cf-mx5/setup-ru-shell.sh status
sudo scripts/cf-mx5/setup-ru-shell.sh uninstall   # ESP のファイルと GRUB の項目を消す
```

Shell では `fs0:` → `cd EFI\tools` → `RU.efi`。Alt+= で変数一覧を開き、`Setup`(GUID **EC87D643-…**。80E1202E-… ではない)を選びます。
現在値を確かめてから `0x97C` を `00`→`01`(Power On AC)、必要なら `0x41` を `01`→`00`(State After G3)に変え、Ctrl+W で保存します。

## 対象(cfmx5-setupvar.py)

- 機種: CF-MX5(DMI product_name `CFMX5-3`)
- BIOS: V3.00L25 のみ(オフセットはこの版の Setup IFR から取り出したもの)
- それ以外では書き込みを拒否します(`--force` で無視できますが、オフセットが違えば別の設定を壊します)

## 項目

| 名前 | オフセット | 値 | 既定 | 内容 |
|---|---|---|---|---|
| `state-after-g3` | 0x41 | `s0` / `s5` | s5 | AC 復帰時に起動する(s0)か。**自動起動はこれ** |
| `power-on-ac` | 0x97C | `enabled` / `disabled` | disabled | Panasonic 独自の Power On AC。機種が非対応だと効かない |
| `power-on-ac-visible` | 0x97D | `shown` / `hidden` | hidden | 上の項目を Setup 画面に出すフラグ。BIOS が起動時に戻す可能性あり |
| `lid-switch` | 0x97E | `enabled` / `disabled` | enabled | 蓋の開閉を検知するか |
| `power-on-by-lan` | 0x8F8 | `allow` / `deny` | deny | LAN 起動時のパスワード入力省略を許可するか |
| `wake-on-lan` | 0x34 | `enabled` / `disabled` | enabled | Wake on LAN (PCH) |

## 使い方

```
sudo scripts/cf-mx5/cfmx5-setupvar.py list                         # 全項目の現在値
sudo scripts/cf-mx5/cfmx5-setupvar.py set state-after-g3 s0 --dry-run
sudo scripts/cf-mx5/cfmx5-setupvar.py set state-after-g3 s0
sudo reboot
sudo setpci -s 00:1f.2 0xa4.b                                       # 08 なら AFTERG3_EN=0(自動起動)
```

- 書き込む前に `/var/backups/cfmx5-setup/Setup-日時.bin` へ変数全体をバックアップします。
- 戻すとき: `sudo scripts/cf-mx5/cfmx5-setupvar.py restore /var/backups/cfmx5-setup/Setup-日時.bin`
  BIOS Setup で既定値を読み込んでも元に戻ります。
- 現在値が想定外(項目の選択肢にない値)のときは、オフセットがずれているとみなして中止します。
- 書き込みが拒否される場合は、ファームウェアが変数をロックしています。EFI シェルの RU.efi で同じ GUID の変数を書き換えてください。

## 注意

- 互換 AC アダプターの起動時警告(キー待ち)が出る構成では、自動で電源が入っても警告画面で止まります。
