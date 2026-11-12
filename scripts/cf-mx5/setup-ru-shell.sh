#!/bin/sh
# CF-MX5: USB メモリなしで RU.efi を使うため、内蔵 ESP に UEFI Shell と RU.efi を置き、
# GRUB から 1 回だけ起動できるようにする(Debian 系)。
#
#   sudo scripts/cf-mx5/setup-ru-shell.sh install <RU.efi または RU の zip>
#   sudo scripts/cf-mx5/setup-ru-shell.sh boot       # 次の 1 回だけ UEFI Shell で起動して再起動
#   sudo scripts/cf-mx5/setup-ru-shell.sh status
#   sudo scripts/cf-mx5/setup-ru-shell.sh uninstall
#
# RU.efi は配布元(作者 James Wang 氏のブログ ruexe.blogspot.com)から自分でダウンロードしてください。
set -eu

SHELL_VER=25H1
SHELL_URL=https://github.com/pbatard/UEFI-Shell/releases/download/$SHELL_VER/shellx64.efi
SHELL_SHA256=fc9e2b45cf0f593d4e5b9268b0cb7c3887a2193643294ef134ff4e8b715ca55e
TOOLS_SUBDIR=EFI/tools
GRUB_SCRIPT=/etc/grub.d/45_cfmx5_uefi_shell
ENTRY="UEFI Shell (RU)"

die() { echo "エラー: $*" >&2; exit 1; }
usage() { echo "使い方: sudo $0 {install <RU.efi|RU.zip>|boot|status|uninstall}" >&2; exit 2; }
need_root() { [ "$(id -u)" -eq 0 ] || die "sudo で実行してください"; }

find_esp() {
    for m in /boot/efi /efi; do
        if [ "$(findmnt -n -o FSTYPE "$m" 2>/dev/null)" = "vfat" ]; then ESP=$m; return; fi
    done
    die "ESP(vfat)が /boot/efi にも /efi にもマウントされていません"
}

# x86-64 の EFI アプリか確認する(MZ ヘッダー → PE ヘッダー → Machine 0x8664 → Subsystem 10)
check_efi_x64() {
    python3 - "$1" <<'PY' || die "$1 は x86-64 の EFI アプリではありません"
import struct, sys
d = open(sys.argv[1], 'rb').read()
assert d[:2] == b'MZ'
pe = struct.unpack_from('<I', d, 0x3C)[0]
assert d[pe:pe+4] == b'PE\0\0'
assert struct.unpack_from('<H', d, pe+4)[0] == 0x8664
assert struct.unpack_from('<H', d, pe+24+68)[0] == 10   # IMAGE_SUBSYSTEM_EFI_APPLICATION
PY
}

cmd_install() {
    need_root
    [ $# -ge 1 ] || usage
    SRC=$1
    [ -f "$SRC" ] || die "$SRC がありません"
    command -v update-grub >/dev/null || die "update-grub がありません(GRUB 以外のブートローダーには未対応)"
    find_esp
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT

    # RU.efi(zip ならその中から取り出す)
    case "$SRC" in
        *.zip|*.ZIP)
            python3 - "$SRC" "$TMP/RU.efi" <<'PY' || die "zip の中に RU.efi が見つかりません"
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
names = [n for n in z.namelist() if n.lower().rsplit('/', 1)[-1] == 'ru.efi']
assert names, 'no RU.efi'
open(sys.argv[2], 'wb').write(z.read(names[0]))
PY
            ;;
        *) cp "$SRC" "$TMP/RU.efi" ;;
    esac
    check_efi_x64 "$TMP/RU.efi"

    # UEFI Shell(バージョン固定 + SHA-256 確認)
    echo "UEFI Shell $SHELL_VER をダウンロード中..."
    if command -v curl >/dev/null; then
        curl -fsSL -o "$TMP/shellx64.efi" "$SHELL_URL" || die "ダウンロードに失敗しました"
    else
        wget -q -O "$TMP/shellx64.efi" "$SHELL_URL" || die "ダウンロードに失敗しました"
    fi
    echo "$SHELL_SHA256  $TMP/shellx64.efi" | sha256sum -c --quiet - \
        || die "UEFI Shell の SHA-256 が一致しません"
    check_efi_x64 "$TMP/shellx64.efi"

    mkdir -p "$ESP/$TOOLS_SUBDIR"
    cp "$TMP/shellx64.efi" "$ESP/$TOOLS_SUBDIR/shellx64.efi"
    cp "$TMP/RU.efi" "$ESP/$TOOLS_SUBDIR/RU.efi"
    sync

    cat > "$GRUB_SCRIPT" <<'EOF'
#!/bin/sh
# CF-MX5: RU.efi 用の UEFI Shell(scripts/cf-mx5/setup-ru-shell.sh が作成)
cat <<'GRUB'
menuentry "UEFI Shell (RU)" --id cfmx5-uefi-shell {
    insmod part_gpt
    insmod fat
    insmod chain
    search --no-floppy --file --set=root /EFI/tools/shellx64.efi
    chainloader /EFI/tools/shellx64.efi
}
GRUB
EOF
    chmod 755 "$GRUB_SCRIPT"
    update-grub

    echo "配置しました: $ESP/$TOOLS_SUBDIR/{shellx64.efi,RU.efi}"
    echo "次: sudo $0 boot"
}

cmd_boot() {
    need_root
    find_esp
    [ -f "$ESP/$TOOLS_SUBDIR/shellx64.efi" ] && [ -f "$ESP/$TOOLS_SUBDIR/RU.efi" ] \
        || die "まだ配置されていません(先に install)"
    CFG=/boot/grub/grub.cfg
    grep -q 'cfmx5-uefi-shell' "$CFG" || die "$CFG に項目がありません(sudo update-grub を実行)"
    grep -q 'next_entry' "$CFG" \
        || die "$CFG が 1 回だけの起動(grub-reboot)に対応していません。/etc/default/grub を GRUB_DEFAULT=saved にして update-grub してください"
    grub-reboot cfmx5-uefi-shell
    echo "次の 1 回だけ UEFI Shell で起動します。Shell では:  fs0:  →  cd EFI\\tools  →  RU.efi"
    echo "(fs0: に EFI\\tools がなければ fs1: など)。10 秒後に再起動します。Ctrl+C で中止"
    sleep 10
    systemctl reboot
}

cmd_status() {
    find_esp
    for f in shellx64.efi RU.efi; do
        if [ -f "$ESP/$TOOLS_SUBDIR/$f" ]; then echo "$ESP/$TOOLS_SUBDIR/$f: あり"; else echo "$ESP/$TOOLS_SUBDIR/$f: なし"; fi
    done
    if [ -e "$GRUB_SCRIPT" ]; then echo "$GRUB_SCRIPT: あり"; else echo "$GRUB_SCRIPT: なし"; fi
    if grep -qs 'cfmx5-uefi-shell' /boot/grub/grub.cfg; then echo "grub.cfg: 項目あり"; else echo "grub.cfg: 項目なし"; fi
}

cmd_uninstall() {
    need_root
    find_esp
    rm -f "$ESP/$TOOLS_SUBDIR/shellx64.efi" "$ESP/$TOOLS_SUBDIR/RU.efi"
    rmdir "$ESP/$TOOLS_SUBDIR" 2>/dev/null || true
    rm -f "$GRUB_SCRIPT"
    command -v update-grub >/dev/null && update-grub
    grub-editenv - unset next_entry 2>/dev/null || true
    echo "UEFI Shell / RU.efi と GRUB の項目を削除しました"
}

case "${1:-}" in
    install) shift; cmd_install "$@" ;;
    boot) cmd_boot ;;
    status) cmd_status ;;
    uninstall) cmd_uninstall ;;
    *) usage ;;
esac
