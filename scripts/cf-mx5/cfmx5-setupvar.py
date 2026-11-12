#!/usr/bin/env python3
"""CF-MX5 の隠し BIOS 設定(UEFI 変数 "Setup")を 1 項目ずつ読み書きする。

対象: Panasonic CF-MX5 (CFMX5-3) / BIOS V3.00L25
オフセットは BIOS V3.00L25 の Setup IFR から取り出した値。
他の機種・BIOS 版では位置が違う可能性があるので、既定では書き込みを拒否する。

使い方:
  sudo ./cfmx5-setupvar.py list
  sudo ./cfmx5-setupvar.py get state-after-g3
  sudo ./cfmx5-setupvar.py set state-after-g3 s0 [--dry-run]
  sudo ./cfmx5-setupvar.py restore /var/backups/cfmx5-setup/Setup-YYYYmmdd-HHMMSS.bin
"""

import argparse
import datetime
import fcntl
import os
import struct
import sys

SETUP_GUID = "ec87d643-eba4-4bb5-a1e5-3f3e36b20da9"
DEFAULT_VAR_PATH = f"/sys/firmware/efi/efivars/Setup-{SETUP_GUID}"
SETUP_DATA_SIZE = 0xF2B          # IFR の VarStore "Setup" のサイズ
ATTR_SIZE = 4                    # efivarfs のファイル先頭 4 バイトは属性
BACKUP_DIR = "/var/backups/cfmx5-setup"

EXPECTED_PRODUCT = "CFMX5"
EXPECTED_BIOS = "V3.00L25"

# 名前: (Setup 内オフセット, {値の名前: 値}, 既定値, 説明)
ITEMS = {
    "state-after-g3": (0x41, {"s0": 0, "s5": 1}, 1,
                       "State After G3: AC 復帰時に起動する(s0) / 起動しない(s5)"),
    "power-on-ac": (0x97C, {"disabled": 0, "enabled": 1}, 0,
                    "Power On AC (Panasonic 独自。機種が非対応なら効かない)"),
    "power-on-ac-visible": (0x97D, {"hidden": 0, "shown": 1}, 0,
                            "Power On AC を Setup 画面に表示するフラグ(BIOS が起動時に戻す可能性あり)"),
    "lid-switch": (0x97E, {"disabled": 0, "enabled": 1}, 1,
                   "LID Switch: 蓋の開閉を検知するか"),
    "power-on-by-lan": (0x8F8, {"deny": 0, "allow": 1}, 0,
                        "Power On by LAN: LAN 起動時にパスワード入力を飛ばすのを許可するか"),
    "wake-on-lan": (0x34, {"disabled": 0, "enabled": 1}, 1,
                    "Wake on LAN (PCH)"),
}

FS_IOC_GETFLAGS = 0x80086601
FS_IOC_SETFLAGS = 0x40086602
FS_IMMUTABLE_FL = 0x00000010


def die(msg):
    print(f"エラー: {msg}", file=sys.stderr)
    sys.exit(1)


def read_dmi(name):
    try:
        with open(f"/sys/class/dmi/id/{name}") as f:
            return f.read().strip()
    except OSError:
        return ""


def check_machine(force):
    product = read_dmi("product_name")
    bios = read_dmi("bios_version")
    if EXPECTED_PRODUCT in product and bios == EXPECTED_BIOS:
        return
    msg = (f"想定外の機種/BIOS です(product_name={product!r}, bios_version={bios!r})。"
           f"想定: {EXPECTED_PRODUCT}* / {EXPECTED_BIOS}")
    if not force:
        die(msg + " --force で無視できますが、オフセットが違うと別の設定を壊します。")
    print(f"警告: {msg}(--force 指定のため続行)", file=sys.stderr)


def load(path):
    try:
        with open(path, "rb") as f:
            raw = f.read()
    except FileNotFoundError:
        die(f"{path} がありません(UEFI 起動でない / GUID が違う / efivarfs が未マウント)")
    except PermissionError:
        die("読み取り権限がありません。sudo で実行してください")
    if len(raw) != ATTR_SIZE + SETUP_DATA_SIZE:
        die(f"Setup 変数のサイズが想定と違います({len(raw)} バイト、想定 {ATTR_SIZE + SETUP_DATA_SIZE})")
    return raw


def set_immutable(path, on):
    fd = os.open(path, os.O_RDONLY)
    try:
        buf = fcntl.ioctl(fd, FS_IOC_GETFLAGS, struct.pack("i", 0))
        flags = struct.unpack("i", buf)[0]
        new = (flags | FS_IMMUTABLE_FL) if on else (flags & ~FS_IMMUTABLE_FL)
        if new != flags:
            fcntl.ioctl(fd, FS_IOC_SETFLAGS, struct.pack("i", new))
        return bool(flags & FS_IMMUTABLE_FL)
    except OSError:
        return None  # 通常ファイル(テスト時)など
    finally:
        os.close(fd)


def backup(raw):
    os.makedirs(BACKUP_DIR, exist_ok=True)
    stamp = datetime.datetime.now().strftime("Setup-%Y%m%d-%H%M%S")
    dst = os.path.join(BACKUP_DIR, stamp + ".bin")
    n = 1
    while os.path.exists(dst):  # 同じ秒の別バックアップを上書きしない
        dst = os.path.join(BACKUP_DIR, f"{stamp}-{n}.bin")
        n += 1
    with open(dst, "xb") as f:
        f.write(raw)
    return dst


def write_var(path, new_raw):
    was_immutable = set_immutable(path, False)
    try:
        fd = os.open(path, os.O_WRONLY)
        try:
            # efivarfs は 1 回の write() で属性+データ全体を受け取る
            n = os.write(fd, new_raw)
        finally:
            os.close(fd)
        if n != len(new_raw):
            die(f"書き込みが途中で終わりました({n}/{len(new_raw)} バイト)")
    except PermissionError:
        die("書き込みが拒否されました(ファームウェアが Setup 変数をロックしている可能性)。"
            "EFI シェルの RU.efi で書き換えてください")
    finally:
        if was_immutable:
            set_immutable(path, True)


def value_name(item, v):
    for k, x in ITEMS[item][1].items():
        if x == v:
            return k
    return f"不明(0x{v:02X})"


def parse_value(item, text):
    choices = ITEMS[item][1]
    t = text.lower()
    if t in choices:
        return choices[t]
    try:
        v = int(text, 0)
    except ValueError:
        die(f"{item} の値は {', '.join(choices)} または {', '.join(map(str, choices.values()))} です")
    if v not in choices.values():
        die(f"{item} に {v} は設定できません(許可: {sorted(choices.values())})")
    return v


def get_item(raw, item):
    return raw[ATTR_SIZE + ITEMS[item][0]]


def cmd_list(args):
    raw = load(args.var_path)
    for item, (off, choices, default, desc) in ITEMS.items():
        v = get_item(raw, item)
        mark = "" if v == default else "  ← 既定値から変更"
        print(f"{item:<20} 0x{off:03X} = {v} ({value_name(item, v)}){mark}")
        print(f"{'':<20} {desc}")


def cmd_get(args):
    raw = load(args.var_path)
    v = get_item(raw, args.item)
    print(f"{args.item} = {v} ({value_name(args.item, v)})")


def cmd_set(args):
    check_machine(args.force)
    raw = load(args.var_path)
    item = args.item
    off = ITEMS[item][0]
    new_v = parse_value(item, args.value)
    cur = get_item(raw, item)
    if cur not in ITEMS[item][1].values():
        die(f"現在値 0x{cur:02X} が想定外です。オフセットがずれている可能性があるので中止します")
    if cur == new_v:
        print(f"{item} はすでに {new_v} ({value_name(item, new_v)}) です。変更なし")
        return
    new_raw = bytearray(raw)
    new_raw[ATTR_SIZE + off] = new_v
    print(f"{item} (0x{off:03X}): {cur} ({value_name(item, cur)}) → {new_v} ({value_name(item, new_v)})")
    if args.dry_run:
        print("--dry-run のため書き込みません")
        return
    print(f"バックアップ: {backup(raw)}")
    write_var(args.var_path, bytes(new_raw))
    after = load(args.var_path)
    if after != bytes(new_raw):
        die("書き込み後の読み直しが一致しません。バックアップから restore してください")
    print("書き込み完了。再起動後に反映されます")


def cmd_restore(args):
    check_machine(args.force)
    raw = load(args.var_path)
    with open(args.file, "rb") as f:
        bk = f.read()
    if len(bk) != len(raw) or bk[:ATTR_SIZE] != raw[:ATTR_SIZE]:
        die("バックアップのサイズ/属性が現在の Setup 変数と一致しません")
    diff = [i - ATTR_SIZE for i in range(ATTR_SIZE, len(raw)) if raw[i] != bk[i]]
    print(f"差分 {len(diff)} バイト: " + ", ".join(f"0x{o:03X}" for o in diff[:16])
          + (" ..." if len(diff) > 16 else ""))
    if not diff:
        return
    if args.dry_run:
        print("--dry-run のため書き込みません")
        return
    print(f"現在の内容のバックアップ: {backup(raw)}")
    write_var(args.var_path, bk)
    if load(args.var_path) != bk:
        die("書き戻し後の読み直しが一致しません")
    print("書き戻し完了。再起動後に反映されます")


def main():
    p = argparse.ArgumentParser(description="CF-MX5 の隠し BIOS 設定を 1 項目ずつ読み書きする")
    p.add_argument("--var-path", default=DEFAULT_VAR_PATH, help=argparse.SUPPRESS)
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list", help="全項目の現在値を表示")

    g = sub.add_parser("get", help="1 項目の現在値を表示")
    g.add_argument("item", choices=ITEMS)

    s = sub.add_parser("set", help="1 項目だけ書き換える")
    s.add_argument("item", choices=ITEMS)
    s.add_argument("value")
    s.add_argument("--dry-run", action="store_true", help="変更内容の表示だけ")
    s.add_argument("--force", action="store_true", help="機種/BIOS 版の確認を飛ばす")

    r = sub.add_parser("restore", help="バックアップを書き戻す")
    r.add_argument("file")
    r.add_argument("--dry-run", action="store_true")
    r.add_argument("--force", action="store_true")

    args = p.parse_args()
    {"list": cmd_list, "get": cmd_get, "set": cmd_set, "restore": cmd_restore}[args.cmd](args)


if __name__ == "__main__":
    main()
