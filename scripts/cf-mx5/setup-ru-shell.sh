#!/bin/sh
# CF-MX5: USB メモリなしで RU.efi を使うため、内蔵 ESP に UEFI Shell と RU.efi を置き、
# GRUB から 1 回だけ起動できるようにする(Debian 系)。
#
#   sudo scripts/cf-mx5/setup-ru-shell.sh install              # RU を作者の配布元から自動ダウンロード
#   sudo scripts/cf-mx5/setup-ru-shell.sh install <RU.efi|zip> # 手元のファイルを使う
#   sudo scripts/cf-mx5/setup-ru-shell.sh boot       # 次の 1 回だけ UEFI Shell で起動して再起動
#   sudo scripts/cf-mx5/setup-ru-shell.sh status
#   sudo scripts/cf-mx5/setup-ru-shell.sh uninstall
#
# RU の zip は作者が暗号化して配布しています。パスワードは作者のブログに載っているので、
# 実行中に入力するか、環境変数 RU_PASSWORD で渡してください(sudo -E か sudo RU_PASSWORD=... で)。
set -eu

# RU: 作者 James Wang 氏の配布リポジトリ(github.com/JamesAmiTw/ru-uefi)。正式版 5.40.0433 に固定
RU_VER=5.40.0433
RU_URL=https://raw.githubusercontent.com/JamesAmiTw/ru-uefi/e02838a6fd8886ca275bdf95780fc2fca11cc79f/5.40.0433.zip
RU_SHA256=97c95584046fbbdc436db6a4399d4dc246f8f8c49a95c1075c28481b5d72a0e3
RU_BLOG=http://ruexe.blogspot.com/

SHELL_VER=25H1
SHELL_URL=https://github.com/pbatard/UEFI-Shell/releases/download/$SHELL_VER/shellx64.efi
SHELL_SHA256=fc9e2b45cf0f593d4e5b9268b0cb7c3887a2193643294ef134ff4e8b715ca55e
TOOLS_SUBDIR=EFI/tools
GRUB_SCRIPT=/etc/grub.d/45_cfmx5_uefi_shell
ENTRY="UEFI Shell (RU)"

die() { echo "エラー: $*" >&2; exit 1; }
usage() { echo "使い方: sudo $0 {install [RU.efi|RU.zip]|boot|status|uninstall}" >&2; exit 2; }
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

download() {  # $1=URL $2=保存先 $3=SHA-256
    if command -v curl >/dev/null; then
        curl -fsSL -o "$2" "$1" || die "ダウンロードに失敗しました: $1"
    else
        wget -q -O "$2" "$1" || die "ダウンロードに失敗しました: $1"
    fi
    echo "$3  $2" | sha256sum -c --quiet - || die "SHA-256 が一致しません: $1"
}

# zip から x64 の RU.efi を取り出す(暗号化 zip ならパスワードを使う)。$1=zip $2=保存先
extract_ru() {
    if python3 - "$1" <<'PY'
import sys, zipfile
sys.exit(0 if any(i.flag_bits & 1 for i in zipfile.ZipFile(sys.argv[1]).infolist()) else 1)
PY
    then
        if [ -z "${RU_PASSWORD:-}" ]; then
            [ -t 0 ] || die "RU の zip は暗号化されています。RU_PASSWORD にパスワードを入れて実行してください"
            echo "RU の zip のパスワードを入力してください(作者のブログ $RU_BLOG に載っています)"
            printf 'パスワード: '
            stty -echo; read -r RU_PASSWORD; stty echo; echo
        fi
    fi
    RU_PASSWORD=${RU_PASSWORD:-} python3 - "$1" "$2" <<'PY'
import os, sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
names = [n for n in z.namelist() if n.lower().rsplit('/', 1)[-1] == 'ru.efi']
# 新しい配布物は X64/IA32/AARCH64 に分かれているので X64 を選ぶ
x64 = [n for n in names if n.lower().startswith('x64/')]
pick = (x64 or [n for n in names if '/' not in n])
if not pick:
    sys.exit('zip の中に x64 の RU.efi が見つかりません')
pwd = os.environ.get('RU_PASSWORD', '').encode() or None
try:
    data = z.read(pick[0], pwd=pwd)
except (RuntimeError, zipfile.BadZipFile, Exception):
    sys.exit('パスワードが違います')
open(sys.argv[2], 'wb').write(data)
PY
}

cmd_install() {
    need_root
    command -v update-grub >/dev/null || die "update-grub がありません(GRUB 以外のブートローダーには未対応)"
    find_esp
    TMP=$(mktemp -d)
    trap 'stty echo 2>/dev/null || true; rm -rf "$TMP"' EXIT

    # RU.efi: 引数なしなら作者の配布リポジトリから版固定でダウンロード
    if [ $# -ge 1 ]; then
        SRC=$1
        [ -f "$SRC" ] || die "$SRC がありません"
    else
        echo "RU $RU_VER を作者の配布リポジトリからダウンロード中..."
        SRC=$TMP/ru.zip
        download "$RU_URL" "$SRC" "$RU_SHA256"
    fi
    case "$SRC" in
        *.zip|*.ZIP) extract_ru "$SRC" "$TMP/RU.efi" || die "RU.efi を取り出せませんでした" ;;
        *) cp "$SRC" "$TMP/RU.efi" ;;
    esac
    check_efi_x64 "$TMP/RU.efi"

    # UEFI Shell(バージョン固定 + SHA-256 確認)
    echo "UEFI Shell $SHELL_VER をダウンロード中..."
    download "$SHELL_URL" "$TMP/shellx64.efi" "$SHELL_SHA256"
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
