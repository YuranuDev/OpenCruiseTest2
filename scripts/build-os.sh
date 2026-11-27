#!/usr/bin/env bash
# OpenCruise 専用 OS(Yocto)のビルドウィザード。質問に答えるだけで、PC の準備 → レイヤーの取得 → 設定 → ビルド →
# USB メモリへの書き込みまで行う。Yocto を知らなくても使える。
#
#   scripts/build-os.sh              ウィザード(PC の確認 → 質問 → 取得 → 設定 → ビルド → 書き込み)
#   scripts/build-os.sh --check      ビルドできる PC かを確かめるだけ(何も変えない)
#   scripts/build-os.sh --build      前の答えのまま、取得・設定・ビルドをやり直す(途中からの再開もこれ)
#   scripts/build-os.sh --flash      できたイメージを USB メモリ / SSD へ書き込む(sudo を使う)
#   scripts/build-os.sh --shell      BitBake を自分で触るシェルを開く
#   scripts/build-os.sh --status     今の答え・レイヤーの版・前回のビルドの結果を見る
#   scripts/build-os.sh --release    公開用のビルド(開発用の SSH・パスワードなし root を入れない。ライセンス文とソースを集める)。
#                                    ウィザード・--build のどちらにも付けられる(答えにも「公開用のビルド: yes」と保存される)
#   scripts/build-os.sh --release-pack  できたイメージ・ライセンス一覧・ソース・チェックサムを <作業フォルダ>/release/ にまとめる(公開用でビルドしたあとに使う)
#   scripts/build-os.sh --app-update アプリだけをビルドして、更新ファイル(<作業フォルダ>/updates/opencruise-app-<番号>.ocapp)を作る。
#                                    車へは USB メモリにコピーするか、scripts/update-server.sh で配る(設定 > システム > アップデート)
#
# オプション:
#   --workdir <フォルダ>  作業フォルダ(既定: ~/opencruise-yocto。150GB 前後の空きが要る。リポジトリの外に作る)
#   --config-only         設定を作るところまでで止める(ビルドしない)
#   --update              レイヤーを各ブランチの最新にする(既定は layers.lock に記録した版に固定)
#   --yes                 質問せず、前の答え(無ければおすすめ)で進む
#   --accept-licenses     --yes のとき、OpenH264(H.264)のライセンス区分(commercial)を受け入れたことにする
#   --no-tui              whiptail(画面のダイアログ)を使わず、文字の質問だけで進める
#
# 作業フォルダの中身:
#   sources/            openembedded-core・bitbake・meta-openembedded・meta-qt6・meta-intel
#   build/conf/         bblayers.conf(このスクリプトが作る)/ auto.conf(答えから作る。毎回作り直す)/
#                       local.conf(Yocto のひな形のまま。自分で足したい設定はここへ。auto.conf より後に読まれて優先される)
#   build/tmp/deploy/images/<機種>/   できあがったイメージ
#   downloads/ sstate-cache/          取得したソースとビルド済みの部品(消さなければ 2 回目から速い)
#   opencruise-os.conf  答え(次回の既定)   layers.lock  使ったレイヤーの版(同じ版で作り直せる)
#   logs/               session-*.log(このスクリプト)・build-*.log(bitbake)・failed-*.log(失敗した作業のログの写し)
#
# このリポジトリの yocto/meta-opencruise が OS の中身(イメージ・アプリのレシピ・自動起動)。詳しくは yocto/README.md。
# Yocto は 6.0 "wrynose"(LTS)だけを対象にする(poky は wrynose から無くなったので、openembedded-core と bitbake を別に取る)。
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
LAYER="$REPO/yocto/meta-opencruise"
TITLE="OpenCruise OS ビルド"
ARGS="$*"

# ============================================================================ 固定の構成(確かめた組み合わせ)
RELEASE="${OC_RELEASE:-wrynose}"
URL_OECORE="${OC_URL_OECORE:-https://git.openembedded.org/openembedded-core}"
URL_BITBAKE="${OC_URL_BITBAKE:-https://git.openembedded.org/bitbake}"
URL_METAOE="${OC_URL_METAOE:-https://git.openembedded.org/meta-openembedded}"
URL_QT6="${OC_URL_QT6:-https://code.qt.io/yocto/meta-qt6.git}"
URL_INTEL="${OC_URL_INTEL:-https://git.yoctoproject.org/meta-intel}"

# ============================================================================ 引数
WORKDIR="${OPENCRUISE_OS_WORKDIR:-$HOME/opencruise-yocto}"
MODE=wizard; ASSUME_YES=0; ACCEPT_LICENSES=0; USE_TUI=1; CONFIG_ONLY=0; UPDATE=0; PUBLISH_FLAG=0
while [ $# -gt 0 ]; do
    case "$1" in
        --workdir) WORKDIR="${2:-}"; shift 2 ;;
        --check) MODE=check; shift ;;
        --build) MODE=build; shift ;;
        --flash) MODE=flash; shift ;;
        --shell) MODE=shell; shift ;;
        --status) MODE=status; shift ;;
        --app-update) MODE=appupdate; shift ;;
        --release) PUBLISH_FLAG=1; shift ;;
        --release-pack) MODE=releasepack; shift ;;
        --config-only) CONFIG_ONLY=1; shift ;;
        --update) UPDATE=1; shift ;;
        --yes|-y) ASSUME_YES=1; shift ;;
        --accept-licenses) ACCEPT_LICENSES=1; shift ;;
        --no-tui) USE_TUI=0; shift ;;
        -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "$0"; exit 0 ;;
        *) echo "不明なオプション: $1(--help で使い方)" >&2; exit 2 ;;
    esac
done
[ -n "$WORKDIR" ] || { echo "エラー: --workdir に作業フォルダを指定してください" >&2; exit 2; }
case "$WORKDIR" in /*) ;; *) WORKDIR="$PWD/$WORKDIR" ;; esac
WORKDIR="${WORKDIR%/}"
SOURCES="$WORKDIR/sources"; BUILD="$WORKDIR/build"; LOGS="$WORKDIR/logs"
CONF="$WORKDIR/opencruise-os.conf"; LOCK="$WORKDIR/layers.lock"
CORE="$SOURCES/openembedded-core"

# ============================================================================ 表示・ログ
SESSION_LOG=""
log() { [ -n "$SESSION_LOG" ] && printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$SESSION_LOG"; return 0; }
NG_LIST=()
ok()   { echo "  ✔ $*"; log "OK   $*"; }
ng()   { echo "  ✖ $*"; log "NG   $*"; NG_LIST+=("$*"); }
info() { echo "  ・$*"; log "INFO $*"; }
step() { echo; echo "■ $*"; log "=== $* ==="; }
die()  { echo "エラー: $*" >&2; log "ERROR $*"; exit 1; }
run_logged() { "$@" 2>&1 | tee -a "${SESSION_LOG:-/dev/null}"; return "${PIPESTATUS[0]}"; }

init_log() {
    case "$MODE" in check|shell|status) return 0 ;; esac   # 何も変えないモードではログも作らない
    mkdir -p "$LOGS" 2>/dev/null || return 0
    SESSION_LOG="$LOGS/session-$(date +%Y%m%d-%H%M%S).log"
    { echo "# build-os.sh: $0 $ARGS"
      echo "# $(date '+%F %T %z')  $(id -un)@$(hostname 2>/dev/null)  $( [ -r /etc/os-release ] && . /etc/os-release && echo "${PRETTY_NAME:-?}" )"
      echo "# モード: $MODE  作業フォルダ: $WORKDIR  リポジトリ: $REPO"; } > "$SESSION_LOG" 2>/dev/null || SESSION_LOG=""
}

command -v whiptail >/dev/null 2>&1 || USE_TUI=0
{ [ -t 0 ] && [ -t 1 ]; } || USE_TUI=0
TW=78; TH=22
if command -v tput >/dev/null 2>&1; then
    c=$(tput cols 2>/dev/null || echo 80); l=$(tput lines 2>/dev/null || echo 24)
    [ "$c" -lt 80 ] && TW=$((c - 2)); [ "$l" -lt 24 ] && TH=$((l - 2))
fi

ui_msg() {   # ui_msg 見出し 本文
    if [ "$ASSUME_YES" -eq 1 ]; then printf '\n== %s ==\n%b\n' "$1" "$2"; return; fi
    if [ "$USE_TUI" -eq 1 ]; then whiptail --title "$TITLE: $1" --msgbox "$2" "$TH" "$TW"; return; fi
    printf '\n== %s ==\n%b\n' "$1" "$2"; read -r -p "Enter で次へ " _ </dev/tty
}
ui_yesno() {   # ui_yesno 見出し 本文 [yes|no(既定)] → 0 = はい
    local def="${3:-yes}" a
    if [ "$ASSUME_YES" -eq 1 ]; then [ "$def" = yes ]; return; fi
    if [ "$USE_TUI" -eq 1 ]; then
        local extra=(); [ "$def" = no ] && extra=(--defaultno)
        whiptail --title "$TITLE: $1" "${extra[@]}" --yes-button "はい" --no-button "いいえ" --yesno "$2" "$TH" "$TW"; return
    fi
    printf '\n== %s ==\n%b\n' "$1" "$2"
    read -r -p "$([ "$def" = yes ] && echo '[Y/n]' || echo '[y/N]') " a </dev/tty
    case "${a:-}" in [Yy]*) return 0 ;; [Nn]*) return 1 ;; *) [ "$def" = yes ] ;; esac
}
ui_menu() {   # ui_menu 見出し 本文 既定のタグ タグ 説明 ... → 選んだタグ(やめたら 1)
    local title="$1" text="$2" def="$3" a i=0; shift 3
    if [ "$ASSUME_YES" -eq 1 ]; then echo "$def"; return 0; fi
    if [ "$USE_TUI" -eq 1 ]; then
        whiptail --title "$TITLE: $title" --ok-button "決定" --cancel-button "やめる" --default-item "$def" \
            --menu "$text" "$TH" "$TW" $((TH - 9)) "$@" 3>&1 1>&2 2>&3; return
    fi
    printf '\n== %s ==\n%b\n' "$title" "$text" >&2
    local tags=()
    while [ $# -ge 2 ]; do
        i=$((i + 1)); tags+=("$1")
        printf '  %d) %s%s\n' "$i" "$2" "$([ "$1" = "$def" ] && echo '  ← 今の選択')" >&2; shift 2
    done
    read -r -p "番号(Enter で今の選択): " a </dev/tty
    if [[ "${a:-}" =~ ^[0-9]+$ ]] && [ "$a" -ge 1 ] && [ "$a" -le "${#tags[@]}" ]; then echo "${tags[$((a - 1))]}"; else echo "$def"; fi
}
ui_input() {   # ui_input 見出し 本文 既定値
    local a
    if [ "$ASSUME_YES" -eq 1 ]; then echo "$3"; return 0; fi
    if [ "$USE_TUI" -eq 1 ]; then
        whiptail --title "$TITLE: $1" --ok-button "決定" --cancel-button "やめる" --inputbox "$2" "$TH" "$TW" "$3" 3>&1 1>&2 2>&3; return
    fi
    printf '\n== %s ==\n%b\n' "$1" "$2" >&2; read -r -p "[$3] " a </dev/tty; echo "${a:-$3}"
}

# ============================================================================ 答え(次回の既定)
# (FFMPEG_OK は古い版からの名前。今は OpenH264 のライセンス区分(commercial)を受け入れたかの答えで、保存済みの答えをそのまま使えるように名前は変えない)
KEYS="MACHINE TARGET ROOTFS DEV_MODE AASDK SRC_MODE TIMEZONE RM_WORK FFMPEG_OK PUBLISH"
MACHINE=intel-corei7-64; TARGET=opencruise-image; ROOTFS=rw; DEV_MODE=yes; AASDK=yes; PUBLISH=no
SRC_MODE=local; TIMEZONE=Asia/Tokyo; RM_WORK=yes; FFMPEG_OK=no
load_conf() {   # 知っているキーだけを読む(古い版の答えに入っていた RELEASE・STORAGE なども安全に無視する)
    [ -f "$CONF" ] || return 0
    local k v
    while IFS='=' read -r k v; do
        case " $KEYS STORAGE " in *" $k "*) ;; *) continue ;; esac
        v="${v#\'}"; v="${v%\'}"
        [ "$k" = STORAGE ] && { [ "$v" = ro-home ] && ROOTFS=ro || ROOTFS=rw; continue; }   # 以前の名前
        printf -v "$k" '%s' "$v"
    done < <(grep -E '^[A-Z_]+=' "$CONF")
}
save_conf() {
    mkdir -p "$WORKDIR"
    { echo "# scripts/build-os.sh の答え(次回の既定。消してもよい)"
      local k; for k in $KEYS; do printf '%s=%s\n' "$k" "${!k}"; done; } > "$CONF"
}
show_answers() {
    printf '・機種: %s\n・イメージ: %s\n・ルート: %s\n・開発用の機能: %s\n・公開用のビルド: %s\n・Android Auto: %s\n・アプリのソース: %s\n・タイムゾーン: %s\n・作業ファイルの自動削除: %s\n' \
        "$MACHINE" "$TARGET" "$([ "$ROOTFS" = ro ] && echo '読み取り専用 + /home' || echo '読み書きできる')" \
        "$DEV_MODE" "$PUBLISH" "$AASDK" "$([ "$SRC_MODE" = local ] && echo "このフォルダ($REPO)" || echo 'GitHub の main')" "$TIMEZONE" "$RM_WORK"
}

# ============================================================================ PC の確認と準備
# Yocto 公式の Ubuntu / Debian 用の一覧。「a|b」はどちらかがあればよい(版によって名前が違う)
HOST_PKGS="build-essential chrpath cpio debianutils diffstat file gawk gcc git iputils-ping libacl1 lz4|liblz4-tool locales python3 python3-git python3-jinja2 python3-pexpect python3-pip python3-subunit socat texinfo unzip wget xz-utils zstd"
is_debian() { [ -r /etc/os-release ] && grep -qiE '^ID(_LIKE)?=.*(debian|ubuntu)' /etc/os-release; }
free_gb() { local d="$1"; while [ ! -d "$d" ]; do d="$(dirname "$d")"; done; df -Pk "$d" | awk 'NR==2{printf "%d", $4/1048576}'; }
mem_gb() { awk '/MemTotal/{printf "%d", $2/1048576 + 0.5}' /proc/meminfo; }
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" = "$2" ]; }   # ver_ge 実際 最低 → 0 = 足りる
pkg_installed() { local a; for a in ${1//|/ }; do [ "$(dpkg-query -W -f='${db:Status-Status}' "$a" 2>/dev/null)" = installed ] && return 0; done; return 1; }
pkg_pick() {   # 入れられる最初の名前
    local a c; for a in ${1//|/ }; do
        c="$(apt-cache policy "$a" 2>/dev/null | awk '/Candidate:/{print $2; exit}')"
        [ -n "$c" ] && [ "$c" != "(none)" ] && { echo "$a"; return 0; }
    done; return 1
}
missing_pkgs() { local p; for p in $HOST_PKGS; do pkg_installed "$p" || echo "$p"; done; }
has_locale() { locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; }
# BitBake は作業ごとにネットワークを切るため、ユーザー名前空間を使う。Ubuntu 23.10 以降は AppArmor が普通のプログラムに
# これを禁止していて、許可しないと「User namespaces are not usable by BitBake」で止まる
userns_ok() { command -v unshare >/dev/null 2>&1 && unshare --user --map-root-user --net true 2>/dev/null; }
APPARMOR_PROFILE=/etc/apparmor.d/opencruise-bitbake

do_check() {
    step "この PC でビルドできるか"
    local bad=0 v
    if [ "$(id -u)" -eq 0 ]; then ng "root で実行しています(BitBake は root を拒否します。普通のユーザーで実行してください)"; bad=1; fi
    if is_debian; then ok "OS: $(. /etc/os-release; echo "$PRETTY_NAME")"
    else info "Debian / Ubuntu 以外です。必要なパッケージは Yocto の公式の手順で入れてください(自動では入れません)"; fi
    v="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo 0)"
    if ver_ge "$v" 3.9; then ok "Python $v"; else ng "Python 3.9 以上が要ります(今: $v)"; bad=1; fi
    v="$(gcc -dumpfullversion 2>/dev/null || gcc -dumpversion 2>/dev/null || echo 0)"
    if ver_ge "$v" 10.1; then ok "gcc $v"; else ng "gcc 10.1 以上が要ります(今: $v)"; bad=1; fi
    if is_debian && command -v dpkg-query >/dev/null 2>&1; then
        local miss; miss="$(missing_pkgs | tr '\n' ' ')"
        if [ -z "$miss" ]; then ok "ビルドに要るパッケージはそろっています"; else ng "足りないパッケージ: ${miss//|/ または }"; bad=1; fi
    fi
    if has_locale; then ok "ロケール en_US.UTF-8"; else ng "ロケール en_US.UTF-8 がありません(BitBake が要求します)"; bad=1; fi
    if userns_ok; then ok "ユーザー名前空間が使えます(BitBake の作業のネットワーク分離)"
    elif [ -f "$APPARMOR_PROFILE" ]; then ok "ユーザー名前空間: AppArmor に BitBake 用の許可があります($APPARMOR_PROFILE)"
    else ng "ユーザー名前空間が使えません(Ubuntu 23.10 以降の AppArmor の制限。BitBake が止まります)"; bad=1; fi
    if fs_ok "$WORKDIR"; then ok "作業フォルダのファイルシステム: ${FS_TYPE}(Linux の権限・大文字小文字・リンクが使える)"
    else ng "作業フォルダ $WORKDIR のファイルシステム(${FS_TYPE})は Yocto で使えません(${FS_WHY})。ext4 / xfs / btrfs のフォルダを --workdir で指定してください(共有フォルダ・NTFS・exFAT・FAT は不可)"; bad=1; fi
    v="$(free_gb "$WORKDIR")"
    if [ "$v" -ge 150 ]; then ok "空き容量: ${v}GB($WORKDIR)"
    elif [ "$v" -ge "${OC_MIN_FREE_GB:-90}" ]; then ok "空き容量: ${v}GB(少なめ。作業ファイルの自動削除を「はい」にすると足ります)"
    else ng "空き容量が ${v}GB です(150GB 前後を推奨。--workdir で別のディスクにできます)"; bad=1; fi
    v="$(mem_gb)"
    if [ "$v" -ge 16 ]; then ok "メモリ ${v}GB / CPU $(nproc) コア"
    elif [ "$v" -ge 8 ]; then ok "メモリ ${v}GB / CPU $(nproc) コア(少なめ。並列数を減らして進めます)"
    else ng "メモリが ${v}GB です(8GB 以上が要ります。足りないと Qt のビルドで落ちます。スワップを足してください)"; fi
    if timeout 30 git ls-remote --heads "$URL_OECORE" "$RELEASE" 2>/dev/null | grep -q .; then ok "ネットワーク: $URL_OECORE の $RELEASE に届きます"
    else ng "ネットワーク: $URL_OECORE の $RELEASE に届きません(インターネット・プロキシを確認)"; bad=1; fi
    if [ -f "$LAYER/conf/layer.conf" ]; then ok "OpenCruise のレイヤー: $LAYER"; else ng "レイヤーがありません: $LAYER"; bad=1; fi
    case "$REPO$WORKDIR" in *" "*) ng "リポジトリか作業フォルダのパスに空白があります(BitBake が扱えません)"; bad=1 ;; esac
    return "$bad"
}

# 作業フォルダが Yocto に使えるか(VirtualBox / WSL の共有フォルダ・NTFS・exFAT・FAT・ネットワークドライブは、
# chmod・大文字小文字の区別・シンボリックリンク・ハードリンクのどれかが使えず、git の取得やビルドで止まる)。実際に試して確かめる
FS_TYPE="?"; FS_WHY=""
fs_ok() {
    local d="$1" t r=0
    while [ ! -d "$d" ]; do d="$(dirname "$d")"; done
    FS_TYPE="$(stat -f -c %T "$d" 2>/dev/null || echo '?')"
    case "$FS_TYPE" in vfat|msdos|exfat|ntfs|fuseblk|vboxsf|v9fs|9p|cifs|smb2|smb|nfs|drvfs|prl_fs|vmhgfs|fuse*) FS_WHY="共有・Windows 向けの形式"; return 1 ;; esac
    [ -w "$d" ] || { FS_WHY="書き込めない"; return 1; }
    t="$(mktemp -d "$d/.oc-fscheck.XXXXXX" 2>/dev/null)" || { FS_WHY="書き込めない"; return 1; }
    : > "$t/a"
    chmod 0750 "$t/a" 2>/dev/null && [ "$(stat -c %a "$t/a")" = 750 ] || { FS_WHY="chmod が効かない"; r=1; }
    [ "$r" -eq 0 ] && { : > "$t/A"; [ -e "$t/a" ] && [ "$(ls "$t" | wc -l)" -eq 2 ] || { FS_WHY="大文字と小文字を区別しない"; r=1; }; }
    [ "$r" -eq 0 ] && { ln -s a "$t/s" 2>/dev/null && ln "$t/a" "$t/h" 2>/dev/null || { FS_WHY="リンクが作れない"; r=1; }; }
    rm -rf "$t"
    return "$r"
}

need_sudo() { command -v sudo >/dev/null 2>&1 || { ng "sudo がありません。root で: $1"; return 1; }; sudo -v || { ng "sudo の認証ができませんでした"; return 1; }; }

fix_host() {   # 足りないものを入れる(そろっていれば何もしない)。直したら 0、直せないものがあれば 1
    local rc=0
    if is_debian && command -v dpkg-query >/dev/null 2>&1; then
        local miss=() p pick=() none=()
        while read -r p; do [ -n "$p" ] && miss+=("$p"); done < <(missing_pkgs)
        if [ "${#miss[@]}" -gt 0 ] && ui_yesno "パッケージ" "ビルドに要るパッケージが足りません:\n\n${miss[*]//|/ または }\n\nsudo apt で入れますか?" yes; then
            if need_sudo "apt-get install ${miss[*]//|/ }"; then
                run_logged sudo apt-get update -o DPkg::Lock::Timeout=120 || info "apt-get update が一部失敗しました(続けます)"
                for p in "${miss[@]}"; do if q="$(pkg_pick "$p")"; then pick+=("$q"); else none+=("$p"); fi; done
                [ "${#none[@]}" -eq 0 ] || { ng "この OS に無いパッケージ: ${none[*]//|/ または }"; rc=1; }
                if [ "${#pick[@]}" -gt 0 ]; then
                    run_logged sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -o DPkg::Lock::Timeout=120 "${pick[@]}" \
                        && ok "入れました: ${pick[*]}" || { ng "パッケージを入れられませんでした(ログ: $SESSION_LOG)"; rc=1; }
                fi
            else rc=1; fi
        fi
    fi
    if ! has_locale && is_debian && ui_yesno "ロケール" "ロケール en_US.UTF-8 を作りますか?(sudo を使います)" yes; then
        if need_sudo "locale-gen en_US.UTF-8"; then
            sudo sed -i 's/^# *\(en_US\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
            grep -q '^en_US\.UTF-8 UTF-8' /etc/locale.gen 2>/dev/null || echo 'en_US.UTF-8 UTF-8' | sudo tee -a /etc/locale.gen >/dev/null
            run_logged sudo locale-gen && has_locale && ok "ロケール en_US.UTF-8 を作りました" || { ng "ロケールを作れませんでした"; rc=1; }
        else rc=1; fi
    fi
    if ! userns_ok && [ -d /etc/apparmor.d ] && ui_yesno "AppArmor" "BitBake がユーザー名前空間を使えるよう、AppArmor に BitBake 用の許可を足しますか?\n($APPARMOR_PROFILE を作ります。sudo を使います。ほかのプログラムには影響しません)" yes; then
        if need_sudo "AppArmor のプロファイルを作る"; then
            # Yocto のドキュメントにある方法: bitbake の実行ファイルにだけ userns を許可する
            printf '%s\n' 'abi <abi/4.0>,' 'include <tunables/global>' \
                "profile opencruise-bitbake $SOURCES/bitbake/bin/bitbake flags=(unconfined) {" '  userns,' \
                '  include if exists <local/opencruise-bitbake>' '}' | sudo tee "$APPARMOR_PROFILE" >/dev/null
            if run_logged sudo apparmor_parser -r "$APPARMOR_PROFILE"; then ok "AppArmor に BitBake 用の許可を足しました($APPARMOR_PROFILE)"
            else ng "AppArmor のプロファイルを読み込めませんでした"; rc=1; fi
        else rc=1; fi
    fi
    return "$rc"
}
# AppArmor の許可は bitbake の実行ファイルにだけ効くので、PC 全体の確認(unshare)では見えない。プロファイルの有無で見る
apparmor_ready() { userns_ok || [ -f "$APPARMOR_PROFILE" ]; }

# ============================================================================ 質問
ask_all() {
    ui_msg "はじめに" "OpenCruise 専用の OS(Yocto $RELEASE)を作ります。\n\n・作業フォルダ: $WORKDIR\n・初回のビルドは数時間かかります(Qt6 と OpenH264 を自分でビルドするため)\n・空き容量は 150GB 前後が要ります\n\nわからない質問は Enter(今の選択)で進めて大丈夫です。"
    MACHINE="$(ui_menu "動かす機械" "この OS を動かす機械は?" "$MACHINE" \
        intel-corei7-64 "Intel の x86_64 PC の実機(CF-MX5 など)" \
        qemux86-64 "PC なしで試す(QEMU の仮想マシン)")" || die "やめました"
    TARGET="$(ui_menu "作るもの" "どのイメージを作りますか?" "$TARGET" \
        opencruise-image "OpenCruise 専用(Qt のベース + アプリ + 自動起動)" \
        qt-appliance-image "Qt6 のベースだけ(アプリなし。土台の確認用)")" || die "やめました"
    if [ "$MACHINE" = intel-corei7-64 ]; then
        ROOTFS="$(ui_menu "ルートの書き込み" "車載は電源が急に切れるので、ルートを読み取り専用にして書き込みを /home だけにすると壊れにくくなります。\nまずは「読み書きできる」で動くことを確かめてから切り替えるのがおすすめです。" "$ROOTFS" \
            rw "読み書きできる(まずはこちら)" \
            ro "読み取り専用 + /home は書き込み用(設定・ログ・背景画像)")" || die "やめました"
    else ROOTFS=rw; fi
    if ui_yesno "公開用のビルド" "イメージを人に配る(GitHub のリリースなど)ためのビルドにしますか?\n\n「はい」だと、SSH とパスワードなしの root ログインを入れず、ライセンス文(license.manifest)をイメージに入れ、GPL / LGPL のソースを集めます。\n配る場合は、アプリのソースを「GitHub の main」にして、手元の修正を push してからビルドしてください。" "$PUBLISH"; then PUBLISH=yes; else PUBLISH=no; fi
    if [ "$PUBLISH" = yes ]; then DEV_MODE=no
    else
        DEV_MODE="$(ui_menu "開発用の機能" "SSH とパスワードなしの root ログインを入れますか?(実機で直しながら動かすときに便利。完成品では外します)" "$DEV_MODE" \
            yes "入れる(開発用)" no "入れない(完成品)")" || die "やめました"
    fi
    if ui_yesno "Android Auto" "Android Auto の接続(aasdk)を含めますか?\n\n「いいえ」だと UI だけのビルドになり、接続は「利用不可」と出ます(protobuf まわりで止まるときの逃げ道)。" "$AASDK"; then AASDK=yes; else AASDK=no; fi
    SRC_MODE="$(ui_menu "アプリのソース" "OpenCruise アプリのソースはどこから取りますか?" "$SRC_MODE" \
        local "このフォルダ($REPO)。手元の修正がそのまま入る" \
        git "GitHub の main の最新(手元の修正は入らない)")" || die "やめました"
    TIMEZONE="$(ui_input "タイムゾーン" "OS のタイムゾーン" "$TIMEZONE")" || die "やめました"
    if ui_yesno "ディスクの節約" "ビルドが終わった部品の作業ファイルを自動で消しますか?(rm_work。容量が 1/3 ほどで済みます。失敗の調査はしにくくなります)" "$RM_WORK"; then RM_WORK=yes; else RM_WORK=no; fi
    ask_licenses
    save_conf
}
ask_licenses() {
    [ "$FFMPEG_OK" = yes ] && return 0
    if [ "$ASSUME_YES" -eq 1 ]; then
        [ "$ACCEPT_LICENSES" -eq 1 ] && { FFMPEG_OK=yes; return 0; }
        die "OpenH264(H.264)のライセンス区分(commercial)の受け入れが要ります。--accept-licenses を付けるか、ウィザードで答えてください。"
    fi
    ui_yesno "ライセンス" "OpenCruise は H.264 の映像のデコードに OpenH264 を使います。Yocto では OpenH264 は「commercial」(特許などの配慮が要る)に分類され、受け入れないとビルドできません。\n\nイメージを配布・販売する場合は、H.264 などの特許の扱いを自分で確認してください。\n\n受け入れますか?" no \
        && FFMPEG_OK=yes || die "OpenH264 を受け入れないとアプリをビルドできません。やめました。"
}

# ============================================================================ レイヤーの取得
lock_get() { [ -f "$LOCK" ] && awk -v n="$1" -v f="$2" '$1==n{print (f==1?$2:$3)}' "$LOCK"; }   # lock_get 名前 1=ブランチ/2=版
LOCK_NEW=""
lock_put() { LOCK_NEW+="$1 $2 $(git -C "$3" rev-parse HEAD)"$'\n'; }

# get_layer 名前 URL ブランチ フォルダ: 取得して、ロックの版(--update なら最新)にそろえる
get_layer() {
    local name="$1" url="$2" br="$3" dir="$4" want
    if [ ! -d "$dir/.git" ]; then
        info "$name を取得します($br)"
        run_logged git clone --branch "$br" --single-branch "$url" "$dir" || { ng "$name を取得できませんでした: $url"; return 1; }
    fi
    # 書き換えたファイルがあれば止める(meta-qt6 はブランチを選ぶために --no-checkout で取るので、「無い」ファイルは数えない)
    if [ -n "$(git -C "$dir" diff --name-only --diff-filter=MT HEAD 2>/dev/null)" ]; then
        ng "$name($dir)に手で変更があります。消してよければ git -C $dir checkout . で戻してからやり直してください"; return 1
    fi
    want="$(lock_get "$name" 2)"
    if [ "$UPDATE" -eq 1 ] || [ -z "$want" ] || [ "$(lock_get "$name" 1)" != "$br" ]; then
        run_logged git -C "$dir" fetch --quiet origin "+refs/heads/$br:refs/remotes/origin/$br" || { ng "$name を更新できませんでした"; return 1; }
        want="origin/$br"
    elif ! git -C "$dir" cat-file -e "$want^{commit}" 2>/dev/null; then
        run_logged git -C "$dir" fetch --quiet origin "+refs/heads/$br:refs/remotes/origin/$br"
    fi
    git -C "$dir" checkout --quiet -B "$br" "$want" 2>/dev/null || { ng "$name を $want にできませんでした"; return 1; }
    ok "$name: $br $(git -C "$dir" log -1 --format='%h(%cs)')"
    lock_put "$name" "$br" "$dir"
}

# bitbake のブランチは、openembedded-core が要求する版(meta/conf/sanity.conf の BB_MIN_VERSION)から決める
bitbake_branch() {
    local min mm b
    min="$(sed -n 's/^BB_MIN_VERSION *= *"\([0-9.]*\)".*/\1/p' "$CORE/meta/conf/sanity.conf")"
    [ -n "$min" ] || return 1
    mm="${min%.*}"
    if git ls-remote --exit-code --heads "$URL_BITBAKE" "$mm" >/dev/null 2>&1; then echo "$mm"; return 0; fi
    # 無ければ、要求以上でいちばん古いブランチ
    b="$(git ls-remote --heads "$URL_BITBAKE" | sed 's#.*refs/heads/##' | grep -E '^[0-9]+\.[0-9]+$' | sort -V \
         | while read -r x; do ver_ge "$x" "$mm" && { echo "$x"; break; }; done)"
    [ -n "$b" ] && echo "$b"
}

# meta-qt6 のブランチは、$RELEASE に対応と書かれている 6.x のうちいちばん新しいもの
qt_branch() {
    local dir="$SOURCES/meta-qt6" b
    # この関数の標準出力はブランチ名だけにする(呼び出し側が $(...) で受け取るので、進行状況は標準エラーへ)
    [ -d "$dir/.git" ] || { info "meta-qt6 を取得します(全ブランチ)" >&2; run_logged git clone --no-checkout "$URL_QT6" "$dir" >&2 || return 1; }
    [ "$UPDATE" -eq 1 ] && run_logged git -C "$dir" fetch --quiet origin >&2
    for b in $(git -C "$dir" for-each-ref --format='%(refname:strip=3)' refs/remotes/origin | grep -E '^6\.[0-9]+$' | sort -Vr); do
        git -C "$dir" show "origin/$b:conf/layer.conf" 2>/dev/null | grep 'LAYERSERIES_COMPAT' | grep -qw "$RELEASE" && { echo "$b"; return 0; }
    done
    return 1
}

do_fetch() {
    step "レイヤーの取得(Yocto $RELEASE)"
    mkdir -p "$SOURCES"
    fs_ok "$WORKDIR" || { ng "作業フォルダ $WORKDIR のファイルシステム(${FS_TYPE})は Yocto で使えません(${FS_WHY})。ext4 などのフォルダを --workdir で指定してください"; return 1; }
    LOCK_NEW=""
    get_layer openembedded-core "$URL_OECORE" "$RELEASE" "$CORE" || return 1
    local bb; bb="$(lock_get bitbake 1)"
    { [ "$UPDATE" -eq 1 ] || [ -z "$bb" ]; } && bb="$(bitbake_branch)"
    [[ "$bb" =~ ^[0-9]+\.[0-9]+$ ]] || { ng "openembedded-core に合う bitbake のブランチが分かりません"; return 1; }
    get_layer bitbake "$URL_BITBAKE" "$bb" "$SOURCES/bitbake" || return 1
    get_layer meta-openembedded "$URL_METAOE" "$RELEASE" "$SOURCES/meta-openembedded" || return 1
    local qb; qb="$(lock_get meta-qt6 1)"
    { [ "$UPDATE" -eq 1 ] || [ -z "$qb" ]; } && qb="$(qt_branch)"
    [[ "$qb" =~ ^6\.[0-9]+$ ]] || { ng "meta-qt6 に $RELEASE 対応のブランチが見つかりません"; return 1; }
    get_layer meta-qt6 "$URL_QT6" "$qb" "$SOURCES/meta-qt6" || return 1
    if [ "$MACHINE" = intel-corei7-64 ]; then
        get_layer meta-intel "$URL_INTEL" "$RELEASE" "$SOURCES/meta-intel" || return 1
    fi
    { echo "# scripts/build-os.sh が使ったレイヤーの版(名前 ブランチ コミット)。--update で最新にすると書き換わる"
      printf '%s' "$LOCK_NEW"; } > "$LOCK"
    ok "レイヤーの版を記録しました: $LOCK"
}

# ============================================================================ 設定
# oe-init-build-env を読み込んだ状態でコマンドを実行する(初回は Yocto のひな形から build/conf を作る)
in_env() {
    bash -c 'set +u; cd "$1" || exit 1; TEMPLATECONF="$2/meta/conf/templates/default" . "$2/oe-init-build-env" "$3" >/dev/null || exit 1; shift 3; exec "$@"' \
        _ "$WORKDIR" "$CORE" "$BUILD" "$@"
}

write_bblayers() {
    local lconf d
    lconf="$(sed -n 's/^LCONF_VERSION *= *"\([0-9]*\)".*/\1/p' "$CORE/meta/conf/templates/default/bblayers.conf.sample")"
    {
        echo "# scripts/build-os.sh が作った(作り直すと上書きされる)"
        echo "LCONF_VERSION = \"${lconf:-7}\""
        echo 'BBPATH = "${TOPDIR}"'
        echo 'BBFILES ?= ""'
        echo 'BBLAYERS ?= " \'
        for d in "$CORE/meta" "$SOURCES/meta-openembedded/meta-oe" "$SOURCES/meta-openembedded/meta-python" \
                 "$SOURCES/meta-openembedded/meta-networking" "$SOURCES/meta-openembedded/meta-multimedia" \
                 "$SOURCES/meta-qt6" $([ "$MACHINE" = intel-corei7-64 ] && echo "$SOURCES/meta-intel") "$LAYER"; do
            echo "  $d \\"
        done
        echo '  "'
    } > "$BUILD/conf/bblayers.conf"
}

write_auto() {
    local cpus mg bbt pm heavy p
    cpus="$(nproc)"; mg="$(mem_gb)"
    # 並列数はメモリで決める。以前は make の並列数を CPU の数いっぱいにしていたため、llvm-native と qtbase-native の
    # コンパイルが重なったときに llvm-tblgen などが 1 つ 1〜3GB 使い、メモリが尽きて Killed(終了コード 137)になった。
    #   同時に走る作業の数   : メモリ 3GB に 1 つ(多くの作業は configure やパッケージ作りで軽い)
    #   1 つの作業の make 並列: メモリ 1.5GB に 1 つ(CPU の数まで)
    #   特に重いレシピ(LLVM・Qt): メモリ 4GB に 1 つ(重いもの同士が重なっても足りるように。ここは緩めない)
    # 変えたいときは local.conf に BB_NUMBER_THREADS / PARALLEL_MAKE を書く(auto.conf より優先される)
    bbt=$((mg / 3)); [ "$bbt" -lt 2 ] && bbt=2; [ "$bbt" -gt "$cpus" ] && bbt="$cpus"
    pm=$((mg * 2 / 3)); [ "$pm" -lt 2 ] && pm=2; [ "$pm" -gt "$cpus" ] && pm="$cpus"
    heavy=$((mg / 4)); [ "$heavy" -lt 2 ] && heavy=2; [ "$heavy" -gt "$pm" ] && heavy="$pm"
    {
        echo "# scripts/build-os.sh がウィザードの答えから作った(実行のたびに作り直される)。"
        echo "# 自分で変えたい設定は local.conf の末尾に書く(local.conf はこのファイルより後に読まれて優先される)。"
        echo "MACHINE = \"$MACHINE\""
        echo 'DISTRO = "opencruise-os"'
        echo "DL_DIR = \"$WORKDIR/downloads\""
        echo "SSTATE_DIR = \"$WORKDIR/sstate-cache\""
        echo 'BB_HASHSERVE_DB_DIR = "${SSTATE_DIR}"'
        echo "BB_NUMBER_THREADS = \"$bbt\""
        echo "PARALLEL_MAKE = \"-j $pm\""
        echo "# メモリを特に多く使うレシピ(LLVM の llvm-tblgen・Qt の C++)は並列数をさらに抑える"
        for p in llvm llvm-native qtbase qtbase-native qtdeclarative qtdeclarative-native; do
            echo "PARALLEL_MAKE:pn-$p = \"-j $heavy\""
        done
        echo 'PACKAGE_CLASSES = "package_ipk"'
        echo "DEFAULT_TIMEZONE = \"$TIMEZONE\""
        echo 'LICENSE_FLAGS_ACCEPTED:append = " commercial"'
        echo
        echo '# Qt の画面は eglfs(DRM/KMS 直描画)。Qt Multimedia は GStreamer を使う(音は ALSA のみで PulseAudio / PipeWire が無いため)'
        echo '# Qt 6.12 の Qt Multimedia の FFmpeg バックエンドは Linux では PulseAudio か PipeWire が必須で、ALSA だけだと do_configure が失敗する。'
        echo '# meta-qt6 の qtmultimedia は LICENSE_FLAGS_ACCEPTED に commercial があると ffmpeg を自動で足すので、ここで外す。'
        echo '# (アプリの H.264 デコードは FFmpeg を使わず、opencruise レシピが openh264 を直接使う。FFmpeg はイメージに入れない)'
        echo 'PACKAGECONFIG:append:pn-qtbase = " eglfs kms gbm libinput fontconfig"'
        echo 'PACKAGECONFIG:remove:pn-qtmultimedia = "ffmpeg pulseaudio pipewire"'
        echo 'PACKAGECONFIG:append:pn-qtmultimedia = " gstreamer alsa"'
        if [ "$DEV_MODE" = yes ] && [ "$PUBLISH" != yes ]; then
            echo '# 開発用: SSH・パスワードなしの root ログイン(完成品では外す)'
            echo 'EXTRA_IMAGE_FEATURES:append = " ssh-server-openssh allow-root-login allow-empty-password empty-root-password post-install-logging"'
        fi
        if [ "$PUBLISH" = yes ]; then
            echo '# 公開用: 開発用の SSH・パスワードなし root は入れない(上の開発用の設定は出さない)。'
            echo '# イメージに license.manifest とパッケージごとのライセンス文を入れ(/usr/share/common-licenses)、GPL / LGPL のソースを deploy/sources に集める'
            echo 'COPY_LIC_MANIFEST = "1"'
            echo 'COPY_LIC_DIRS = "1"'
            echo 'INHERIT += "archiver"'
            echo 'ARCHIVER_MODE[src] = "original"'
            echo 'ARCHIVER_MODE[recipe] = "1"'
            echo 'COPYLEFT_LICENSE_INCLUDE = "GPL* LGPL* AGPL*"'
            echo 'COPYLEFT_LICENSE_EXCLUDE = "CLOSED Proprietary*"'
            echo 'COPYLEFT_RECIPE_TYPES = "target"'
        fi
        [ "$AASDK" = no ] && echo 'PACKAGECONFIG:remove:pn-opencruise = "aasdk"'
        if [ "$ROOTFS" = ro ]; then
            echo 'OPENCRUISE_READONLY_ROOTFS = "1"'
            echo 'OPENCRUISE_CMDLINE:append = " ro"'
        fi
        if [ "$MACHINE" = intel-corei7-64 ]; then
            echo '# x86 実機: UEFI(GRUB)のディスクイメージ(meta-opencruise/files/wic/opencruise-x86.wks.in)。GPU と Intel の Wi-Fi のファームウェアも入れる'
            echo 'EFI_PROVIDER = "grub-efi"'
            echo 'WKS_FILE = "opencruise-x86.wks.in"'
            echo 'IMAGE_FSTYPES = "wic wic.bmap"'
            echo 'IMAGE_INSTALL:append = " linux-firmware-i915 linux-firmware-iwlwifi-7265d linux-firmware-iwlwifi-8000c linux-firmware-iwlwifi-8265"'
        fi
        if [ "$SRC_MODE" = local ]; then
            echo '# アプリのソースは、このリポジトリのフォルダをそのまま使う(手元の修正がすぐ入る)'
            echo 'INHERIT += "externalsrc"'
            echo "EXTERNALSRC:pn-opencruise = \"$REPO\""
            echo 'EXTERNALSRC_BUILD:pn-opencruise = "${WORKDIR}/build"'
        fi
        if [ "$RM_WORK" = yes ]; then
            echo 'INHERIT += "rm_work"'
            echo 'RM_WORK_EXCLUDE += "opencruise"'
        fi
    } > "$BUILD/conf/auto.conf"
}

do_config() {
    step "設定の作成"
    mkdir -p "$BUILD/conf"
    if [ "$PUBLISH" = yes ]; then
        info "公開用のビルドです(SSH・パスワードなし root は入れません。ライセンス文を入れ、GPL / LGPL のソースを集めます)"
        if [ "$SRC_MODE" = local ]; then
            info "注意: アプリのソースが「このフォルダ」です。配るイメージは GitHub の main から作る(答えを「GitHub の main」にする)と、配布するソースとイメージの中身が一致します"
            if [ -n "$(git -C "$REPO" status --porcelain 2>/dev/null)" ]; then info "注意: このフォルダには push していない変更があります。配る前に commit と push をしてください"; fi
        fi
    fi
    # 以前の版のこのスクリプトが作った local.conf は、答えを auto.conf より強く上書きしてしまうので、ひな形に戻す
    if [ -f "$BUILD/conf/local.conf" ] && grep -q 'scripts/build-os.sh が作った' "$BUILD/conf/local.conf"; then
        mv "$BUILD/conf/local.conf" "$BUILD/conf/local.conf.old-$(date +%Y%m%d%H%M%S)"
        info "以前の版が作った local.conf を退避しました(ひな形から作り直します)"
    fi
    # 以前の版のレイヤーにあった wic/ は、wrynose では files/wic/ でないとエラーになる(中身は files/wic/ に移してある)
    if [ -d "$LAYER/wic" ] && [ -f "$LAYER/files/wic/opencruise-x86.wks.in" ]; then
        if [ "$(ls -A "$LAYER/wic")" = "opencruise-x86.wks.in" ]; then
            rm -f "$LAYER/wic/opencruise-x86.wks.in" && rmdir "$LAYER/wic" && info "古い $LAYER/wic/ を消しました(files/wic/ に移してあります)"
        else
            ng "$LAYER/wic/ に知らないファイルがあります。files/wic/ へ移してください(wrynose は wic/ を読みません)"; return 1
        fi
    fi
    in_env true || { ng "build フォルダを作れませんでした(oe-init-build-env)"; return 1; }
    write_bblayers; write_auto
    ok "設定を書きました: $BUILD/conf/(bblayers.conf・auto.conf。local.conf はひな形のまま)"
    if in_env bitbake-layers show-layers > "$LOGS/layers.log" 2>&1; then ok "レイヤーの構成を確認しました"
    else ng "レイヤーの構成でエラーです: $LOGS/layers.log"; grep -E 'ERROR|error' "$LOGS/layers.log" | head -n 8 | sed 's/^/      /'; return 1; fi
}

# ============================================================================ ビルド
image_file() { ls -t "$BUILD/tmp/deploy/images/$MACHINE/$TARGET-$MACHINE"*.wic 2>/dev/null | head -n 1; }

# 失敗したときに、エラーの行と、失敗した作業のログ(写し)を出す
report_failure() {
    local log="$1" f n=0
    echo; echo "  ---- エラー(bitbake の出力から)"
    grep -E '^ERROR:' "$log" | grep -v 'Logfile of failure' | head -n 12 | sed 's/^/  /'
    while read -r f; do
        [ -f "$f" ] || continue
        n=$((n + 1)); cp "$f" "$LOGS/failed-$(date +%H%M%S)-$n-$(basename "$(dirname "$(dirname "$f")")")-$(basename "$f").log" 2>/dev/null
        # QA の「installed but not shipped」は、ファイルの一覧が ERROR 行の続き(字下げ行)として出る。
        # 上の grep '^ERROR:' では 1 行目しか拾えず、どのファイルが漏れたのか分からなくなるので、失敗ログから一覧ごと出す
        if grep -q 'installed but not shipped in any package' "$f" 2>/dev/null; then
            echo "  ---- パッケージに入らなかったファイル(installed-vs-shipped): $f"
            grep -A 40 'installed but not shipped in any package' "$f" | sed -n '1,/installed and not shipped files/p' | head -n 60 | sed 's/^/  | /'
        fi
        echo "  ---- 失敗した作業のログの終わり: $f"
        tail -n 25 "$f" | sed 's/^/  | /'
    done < <(sed -n 's/.*Logfile of failure stored in: \([^ ]*\).*/\1/p' "$log" | sort -u | head -n 3)
    [ "$n" -gt 0 ] && echo "  失敗した作業のログの写しを $LOGS/failed-*.log に置きました"
    # 終了コード 137 / Killed は、ほぼメモリ不足でカーネルにプロセスを止められたもの
    if grep -qE 'exit code 137|FAILED: \[code=137\]|^\| Killed$' "$log"; then
        echo "  ---- メモリ不足でコンパイラが止められたようです(終了コード 137 / Killed)"
        echo "  対処: $BUILD/conf/local.conf の末尾に並列数を小さく書いて、--build で再開してください。例:"
        echo "    BB_NUMBER_THREADS = \"2\""
        echo "    PARALLEL_MAKE = \"-j 4\""
        echo "  またはスワップを増やしてください(今のメモリ: $(mem_gb)GB)"
    fi
}

do_build() {
    step "ビルド"
    [ -f "$BUILD/conf/auto.conf" ] || { ng "設定がありません。先にウィザードを実行してください"; return 1; }
    if ! apparmor_ready; then ng "ユーザー名前空間が使えないままです(AppArmor)。--build の前にウィザードで許可を足してください"; return 1; fi
    local stamp log rc; stamp="$(date +%Y%m%d-%H%M%S)"; log="$LOGS/build-$stamp.log"
    info "レシピを読み込んで確かめます(bitbake -p)"
    in_env bitbake -p > "$LOGS/parse.log" 2>&1; rc=$?
    if [ "$rc" -ne 0 ]; then ng "レシピの確認に失敗しました: $LOGS/parse.log"; report_failure "$LOGS/parse.log"; return 1; fi
    ok "レシピの確認ができました"
    app_source_banner
    info "bitbake $TARGET を始めます。初回は数時間かかります(止めても --build で続きから再開できます)。ログ: $log"
    in_env bitbake "$TARGET" 2>&1 | tee "$log"; rc="${PIPESTATUS[0]}"
    if [ "$rc" -ne 0 ]; then ng "ビルドに失敗しました(終了コード $rc)。ログ: $log"; report_failure "$log"; return 1; fi
    ok "ビルドしました: $TARGET"
    local img; img="$(image_file)"
    if [ -n "$img" ]; then ok "ディスクイメージ: $img"
    elif [ "$MACHINE" = qemux86-64 ]; then info "QEMU で試す: $0 --shell を開いて  runqemu qemux86-64 $TARGET slirp nographic"
    else info "成果物: $BUILD/tmp/deploy/images/$MACHINE/"; fi
}

# ============================================================================ 書き込み
do_flash() {
    step "USB メモリ / SSD へ書き込み"
    [ "$ASSUME_YES" -eq 0 ] || die "書き込みは --yes では行いません(消してよいかを手で確かめる必要があります)"
    local img; img="$(image_file)"
    [ -n "$img" ] || { ng "書き込むイメージ(.wic)がありません。先にビルドしてください(--build)"; return 1; }
    img="$(readlink -f "$img")"
    info "イメージ: $img($(du -h "$img" | cut -f1))"
    local root items=() NAME SIZE TRAN RM MODEL line
    root="$(lsblk -no PKNAME "$(findmnt -no SOURCE / 2>/dev/null)" 2>/dev/null | head -n 1)"
    while read -r line; do
        NAME=""; SIZE=0; TRAN=""; RM=0; MODEL=""; eval "$line"
        [ -n "$NAME" ] && [ "$(basename "$NAME")" != "$root" ] || continue
        { [ "$TRAN" = usb ] || [ "$RM" = 1 ]; } || continue
        items+=("$NAME" "$((SIZE / 1000000000))GB ${MODEL:-?} (${TRAN:-?})")
    done < <(lsblk -dnpb -P -o NAME,SIZE,TRAN,RM,MODEL 2>/dev/null)
    [ "${#items[@]}" -gt 0 ] || { ng "書き込める USB メモリ / 外付けディスクが見つかりません(いまの OS のディスクは出しません)"; return 1; }
    local dev typed; dev="$(ui_menu "書き込み先" "書き込み先を選んでください。\n【警告】選んだディスクの中身はすべて消えます。" "${items[0]}" "${items[@]}")" || return 1
    [ -b "$dev" ] || { ng "選んだ機器がありません: $dev"; return 1; }
    read -r -p "$dev の中身はすべて消えます。続けるなら、もう一度 $dev と入力: " typed </dev/tty
    [ "$typed" = "$dev" ] || { info "入力が違うのでやめました"; return 1; }
    log "FLASH $img -> $dev"
    need_sudo "書き込み" || return 1
    local p; for p in $(lsblk -lnpo NAME "$dev" | tail -n +2) "$dev"; do sudo umount "$p" 2>/dev/null; done
    local bmap="${img}.bmap"; [ -f "$bmap" ] || bmap="${img%.wic}.wic.bmap"
    if command -v bmaptool >/dev/null 2>&1 && [ -f "$bmap" ]; then
        run_logged sudo bmaptool copy --bmap "$bmap" "$img" "$dev" || { ng "書き込みに失敗しました"; return 1; }
    else
        run_logged sudo dd if="$img" of="$dev" bs=4M conv=fsync status=progress || { ng "書き込みに失敗しました"; return 1; }
    fi
    sync
    ok "書き込みました: $dev(外して対象の PC につなぎ、UEFI の起動メニューで USB を選んで起動)"
}

# ============================================================================ アプリのソースの表示
# アプリのソースがどこから来るかを、bitbake が実際に読む設定(EXTERNALSRC)から調べて、はっきり表示する。
#   手元のフォルダ(externalsrc): git からは取得せず、いまのファイルをそのままビルドする
#   GitHub の main: bitbake が git で取得(AUTOREV = main の先頭のコミット)してビルドする。手元の push していない変更は入らない
APP_GIT_URL="$(sed -n 's|^.*git://\([^;]*\);.*|https://\1|p' "$REPO/yocto/meta-opencruise/recipes-opencruise/opencruise/opencruise_git.bb" 2>/dev/null | head -n 1)"
app_source_banner() {
    local ext head ahead
    ext="$(in_env bitbake-getvar -r opencruise --value -q EXTERNALSRC 2>/dev/null | tail -n 1)"
    if [ -n "$ext" ] && [ -d "$ext" ]; then
        info "アプリのソース: ★手元のフォルダ★ $ext(git からは取得しません。いまのファイルをそのままビルドします)"
        info "  いちばん新しいコミット: $(git -C "$ext" log -1 --format='%h %s' 2>/dev/null || echo 'git の情報なし')"
        [ -n "$(git -C "$ext" status --porcelain 2>/dev/null)" ] && info "  commit していない変更も入ります"
    else
        info "アプリのソース: ★GitHub の main から git で取得★ ${APP_GIT_URL:-(URL 不明)}"
        head="$(GIT_TERMINAL_PROMPT=0 timeout 15 git ls-remote "$APP_GIT_URL" refs/heads/main 2>/dev/null | cut -c1-10)"
        if [ -n "$head" ]; then info "  ビルドされるコミット(いまの main の先頭): $head"
        else info "  main の先頭を確認できませんでした(ネットワーク?)。bitbake が取得した最新のものをビルドします"; fi
        ahead="$(git -C "$REPO" rev-list --count '@{u}..HEAD' 2>/dev/null)"
        [ "${ahead:-0}" -gt 0 ] && info "  注意: 手元に push していないコミットが $ahead 件あります(ビルドには入りません)"
        [ -n "$(git -C "$REPO" status --porcelain 2>/dev/null)" ] && info "  注意: 手元に commit していない変更があります(ビルドには入りません)"
    fi
    return 0
}
# ビルドが終わったあと、実際にビルドされたソースを表示する(レシピが image に書く source-info)
app_source_built() {
    local si="$1/usr/share/opencruise/source-info" k v mode="" commit="" branch="" dirty="" subject=""
    [ -f "$si" ] || { info "ビルドされたソース: 記録がありません(古いレシピ)"; return 0; }
    while IFS='=' read -r k v; do
        case "$k" in source) mode="$v" ;; commit) commit="$v" ;; branch) branch="$v" ;; dirty) dirty="$v" ;; subject) subject="$v" ;; esac
    done < "$si"
    if [ "$mode" = github ]; then ok "ビルドされたソース: GitHub の $branch ${commit:0:10}($subject)"
    else ok "ビルドされたソース: 手元のフォルダ $branch ${commit:0:10}($subject)$([ "$dirty" = yes ] && echo ' + commit していない変更')"; fi
    return 0
}

# ============================================================================ アプリの更新ファイル
# bitbake opencruise でアプリだけをビルドし、インストール先(image。rm_work の対象外)から更新ファイルを作る(scripts/make-app-update.sh)
do_app_update() {
    step "アプリの更新ファイル"
    [ -f "$BUILD/conf/auto.conf" ] || { ng "設定がありません。先にウィザードを実行してください"; return 1; }
    apparmor_ready || { ng "ユーザー名前空間が使えないままです(AppArmor)"; return 1; }
    local log rc img
    app_source_banner
    log="$LOGS/app-update-$(date +%Y%m%d-%H%M%S).log"
    info "bitbake opencruise(アプリだけ)。ログ: $log"
    in_env bitbake opencruise 2>&1 | tee "$log"; rc="${PIPESTATUS[0]}"
    [ "$rc" -eq 0 ] || { ng "アプリのビルドに失敗しました"; report_failure "$log"; return 1; }
    img="$(in_env bitbake-getvar -r opencruise --value -q D 2>/dev/null | tail -n 1)"
    [ -x "$img/usr/bin/opencruise" ] || { ng "ビルドしたアプリが見つかりません($img)"; return 1; }
    app_source_built "$img"
    mkdir -p "$WORKDIR/updates"
    bash "$HERE/make-app-update.sh" "$img" "$WORKDIR/updates" || { ng "更新ファイルを作れませんでした"; return 1; }
    ok "更新ファイル: $WORKDIR/updates/(USB メモリの直下か opencruise-update/ にコピー、または scripts/update-server.sh $WORKDIR/updates)"
}

# ============================================================================ 公開用ファイルのまとめ
# 公開用(--release)でビルドしたあとに、配るものを <作業フォルダ>/release/<機種>-<日付>/ に集める。
do_release_pack() {
    step "公開用ファイルをまとめる"
    [ "$PUBLISH" = yes ] || { ng "公開用でビルドしていません。--release を付けて --build をやり直してください(開発用の SSH・パスワードなし root が入ったイメージは配れません)"; return 1; }
    local dep="$BUILD/tmp/deploy" imgdir="$BUILD/tmp/deploy/images/$MACHINE" out img f lm n
    [ -d "$imgdir" ] || { ng "イメージがありません($imgdir)。先に --build を実行してください"; return 1; }
    out="$WORKDIR/release/$MACHINE-$(date +%Y%m%d)"
    rm -rf "$out"; mkdir -p "$out" || { ng "$out を作れません"; return 1; }
    command -v zstd >/dev/null 2>&1 || { ng "zstd がありません(sudo apt install zstd)"; return 1; }

    # イメージ(実体のファイルだけ。シンボリックリンクは除く。wic は大きいので zstd で圧縮する)
    img="$(image_file)"
    if [ -n "$img" ] && [ -f "$img" ]; then
        info "圧縮しています: $(basename "$img")"
        zstd -T0 -q -f "$img" -o "$out/$(basename "$img").zst" || { ng "圧縮に失敗しました"; return 1; }
        [ -f "$img.bmap" ] && cp -f "$img.bmap" "$out/"
        ok "イメージ: $(basename "$img").zst"
    else
        n=0
        while IFS= read -r f; do cp -f "$f" "$out/"; n=$((n+1)); done < <(find "$imgdir" -maxdepth 1 -type f \( -name "$TARGET-$MACHINE*.ext4*" -o -name 'bzImage*' -o -name "$TARGET-$MACHINE*.qemuboot.conf" \) 2>/dev/null)
        if [ "$n" -gt 0 ]; then ok "イメージ: $n ファイル"; else ng "イメージのファイルが見つかりません($imgdir)"; return 1; fi
    fi

    # ライセンス一覧(イメージに入っている部品とそのライセンス)・ライセンス文
    lm="$(ls -t "$dep"/licenses/"$TARGET-$MACHINE"*/license.manifest 2>/dev/null | head -n 1)"
    if [ -n "$lm" ]; then cp -f "$lm" "$out/license.manifest"; ok "ライセンス一覧: license.manifest"
    else ng "license.manifest が見つかりません($dep/licenses)"; return 1; fi
    if tar -C "$dep" -cJf "$out/licenses.tar.xz" licenses; then ok "ライセンス文: licenses.tar.xz"; else ng "licenses.tar.xz を作れませんでした"; return 1; fi

    # GPL / LGPL のソース(archiver が集めたもの)
    if [ -d "$dep/sources" ] && [ -n "$(ls -A "$dep/sources" 2>/dev/null)" ]; then
        if tar -C "$dep" -cf "$out/sources.tar" sources; then ok "ソース: sources.tar($(du -h "$out/sources.tar" | cut -f1))"; else ng "sources.tar を作れませんでした"; return 1; fi
    else ng "ソースが見つかりません($dep/sources)。公開用(--release)で --build をやり直してください"; return 1; fi

    # 再現に要る情報(使ったレイヤーの版)と、このリポジトリのライセンス・出典
    [ -f "$LOCK" ] && cp -f "$LOCK" "$out/layers.lock"
    for f in LICENSE THIRD-PARTY-NOTICES.md; do [ -f "$REPO/$f" ] && cp -f "$REPO/$f" "$out/"; done
    if ( cd "$out" && find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort | xargs sha256sum > SHA256SUMS ); then ok "チェックサム: SHA256SUMS"; fi
    echo
    ok "公開用の一式: $out"
    info "このあとの手順: README に「検証専用・公開ネットワークにつながない」などの注意を書き、このフォルダのファイルをリリースに添付します"
    ls -lh "$out" | sed 's/^/  /'
}

# ============================================================================ シェル・状態
do_shell() {
    [ -f "$CORE/oe-init-build-env" ] || die "まだレイヤーがありません。先にウィザードを実行してください"
    echo "BitBake のシェルを開きます。例:  bitbake $TARGET  /  bitbake -c cleansstate opencruise  /  bitbake-layers show-layers"
    echo "出るときは exit。"
    exec bash --rcfile <(printf '[ -f ~/.bashrc ] && . ~/.bashrc\ncd %q && TEMPLATECONF=%q . %q %q >/dev/null\n' \
        "$WORKDIR" "$CORE/meta/conf/templates/default" "$CORE/oe-init-build-env" "$BUILD") -i
}
do_status() {
    echo "■ 答え($CONF)"; show_answers | sed 's/^/  /'
    echo "■ レイヤー($LOCK)"; [ -f "$LOCK" ] && grep -v '^#' "$LOCK" | sed 's/^/  /' || echo "  (まだ取得していません)"
    local last; last="$(ls -t "$LOGS"/build-*.log 2>/dev/null | head -n 1)"
    echo "■ 前回のビルド"
    if [ -n "$last" ]; then echo "  $last"; tail -n 3 "$last" | sed 's/^/  | /'; else echo "  (まだビルドしていません)"; fi
    local img; img="$(image_file)"; [ -n "$img" ] && echo "■ イメージ: $img"
    return 0
}

print_summary() {
    echo; echo "■ 結果"
    if [ "${#NG_LIST[@]}" -eq 0 ]; then echo "  問題はありませんでした"
    else printf '  ✖ %s\n' "${NG_LIST[@]}"; fi
    [ -n "$SESSION_LOG" ] && echo "  ログ: $SESSION_LOG"
    return 0
}

# ============================================================================ 本体
load_conf
[ "$PUBLISH_FLAG" -eq 1 ] && PUBLISH=yes
[ "$PUBLISH" = yes ] && DEV_MODE=no
init_log
[ -t 1 ] && [ "${TERM:-}" = linux ] && echo "注意: Linux のコンソール(tty)では日本語が表示されません。SSH かデスクトップの端末から実行してください。" >&2
[ "$(id -u)" -ne 0 ] || [ "$MODE" = check ] || die "root では実行できません(BitBake は root を拒否します)。普通のユーザーで実行してください。必要なところだけ sudo を使います。"

case "$MODE" in
    check)  do_check; rc=$?; print_summary; exit "$rc" ;;
    status) do_status ;;
    appupdate) do_app_update; rc=$?; print_summary; exit "$rc" ;;
    releasepack) do_release_pack; rc=$?; print_summary; exit "$rc" ;;
    shell)  do_shell ;;
    flash)  do_flash; rc=$?; print_summary; exit "$rc" ;;
    build)
        [ -f "$CONF" ] || die "まだ答えがありません。先にウィザード(オプションなし)を実行してください"
        [ "$FFMPEG_OK" = yes ] || ask_licenses
        do_fetch && do_config && do_build; rc=$?; print_summary; exit "$rc" ;;
    wizard)
        if ! do_check; then
            fix_host
            NG_LIST=(); info "もう一度確かめます"
            if ! do_check; then
                ui_yesno "確認" "上に ✖ が残っています。このまま続けますか?(足りないものがあると途中で止まります)" no || { print_summary; exit 1; }
            fi
            NG_LIST=()
        fi
        ask_all
        ui_msg "確認" "この内容で進めます。\n\n$(show_answers)\n・Yocto: $RELEASE\n・作業フォルダ: $WORKDIR"
        do_fetch && do_config || { print_summary; exit 1; }
        if [ "$CONFIG_ONLY" -eq 1 ]; then echo; echo "設定までで止めました。ビルドは: $0 --build"; print_summary; exit 0; fi
        if ui_yesno "ビルド" "ビルドを始めますか?(初回は数時間。途中で止めても --build で続きから再開できます)" yes; then
            do_build || { print_summary; exit 1; }
            if [ -n "$(image_file)" ] && [ "$ASSUME_YES" -eq 0 ] && ui_yesno "書き込み" "できたイメージを USB メモリ / SSD へ書き込みますか?" no; then do_flash; fi
        else
            echo; echo "ビルドは後から: $0 --build"
        fi
        print_summary ;;
esac
