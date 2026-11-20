#!/bin/bash
# OpenCruise 専用 OS(Yocto)のビルドウィザード。Yocto を知らなくても、質問に答えるだけで OS イメージまで作れる。
#
#   scripts/build-os.sh                ウィザード: 質問に答える → レイヤーを取得 → 設定を作る → ビルド → (USB メモリへ書き込み)
#   scripts/build-os.sh --check        ビルドできる PC かを確かめるだけ(何も変えない)
#   scripts/build-os.sh --build        前に答えた内容のまま、ビルドだけやり直す(途中から再開もこれ)
#   scripts/build-os.sh --flash        できあがったイメージを USB メモリ / SSD へ書き込む(sudo を使う)
#   scripts/build-os.sh --shell        Yocto(bitbake)を自分で触るためのシェルを開く
#
# オプション:
#   --workdir <フォルダ>   作業フォルダ(既定: ~/opencruise-yocto。100GB 以上の空きが要る。リポジトリの外に作る)
#   --config-only          設定を作るところまでで止める(ビルドしない)
#   --update               取得済みのレイヤーも最新にする
#   --yes                  質問せず、前の答え(無ければおすすめ)で進む
#   --accept-licenses      --yes のとき、FFmpeg のライセンス区分(commercial)を受け入れたことにする
#   --no-tui               whiptail(画面のダイアログ)を使わず、文字の質問だけで進める
#
# 作るもの:
#   <作業フォルダ>/sources/   Yocto 本体(OpenEmbedded-Core / BitBake)・meta-openembedded・meta-qt6・機種のレイヤー
#   <作業フォルダ>/build/     ビルドの設定(conf/local.conf, conf/bblayers.conf)と成果物(tmp/deploy/images/<機種>/)
#   <作業フォルダ>/opencruise-os.conf   ウィザードの答え(次回の既定になる)
# このリポジトリの yocto/meta-opencruise が、OS の中身(イメージ・アプリのレシピ・自動起動など)。詳しくは yocto/README.md。
#
# 注意: 初回のビルドは数時間かかる(Qt6 と FFmpeg を自分でビルドするため)。2 回目からは sstate-cache が効いて速い。
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
LAYER="$REPO/yocto/meta-opencruise"
TITLE="OpenCruise OS ビルドウィザード"

WORKDIR="${OPENCRUISE_OS_WORKDIR:-$HOME/opencruise-yocto}"
MODE=wizard
ASSUME_YES=0
ACCEPT_LICENSES=0
USE_TUI=1
CONFIG_ONLY=0
UPDATE=0

# 取得元(環境変数で差し替えられる。社内ミラーや試験用)
URL_POKY="${OC_URL_POKY:-https://git.yoctoproject.org/poky}"
URL_OECORE="${OC_URL_OECORE:-https://git.openembedded.org/openembedded-core}"
URL_BITBAKE="${OC_URL_BITBAKE:-https://git.openembedded.org/bitbake}"
URL_METAOE="${OC_URL_METAOE:-https://git.openembedded.org/meta-openembedded}"
URL_QT6="${OC_URL_QT6:-https://code.qt.io/yocto/meta-qt6.git}"
URL_INTEL="${OC_URL_INTEL:-https://git.yoctoproject.org/meta-intel}"

while [ $# -gt 0 ]; do
    case "$1" in
        --workdir) WORKDIR="${2:-}"; shift 2 ;;
        --check) MODE=check; shift ;;
        --build) MODE=build; shift ;;
        --flash) MODE=flash; shift ;;
        --shell) MODE=shell; shift ;;
        --config-only) CONFIG_ONLY=1; shift ;;
        --update) UPDATE=1; shift ;;
        --yes|-y) ASSUME_YES=1; shift ;;
        --accept-licenses) ACCEPT_LICENSES=1; shift ;;
        --no-tui) USE_TUI=0; shift ;;
        -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
        *) echo "不明なオプション: $1(--help で使い方)" >&2; exit 2 ;;
    esac
done

die() { echo "エラー: $*" >&2; exit 1; }
[ "$(id -u)" -ne 0 ] || die "root では実行できません(BitBake は root を拒否します)。普通のユーザーで実行してください。必要なところだけ sudo を使います。"
[ -n "$WORKDIR" ] || die "--workdir に作業フォルダを指定してください"
case "$WORKDIR" in /*) ;; *) WORKDIR="$PWD/$WORKDIR" ;; esac

SOURCES="$WORKDIR/sources"
BUILD="$WORKDIR/build"
CONF="$WORKDIR/opencruise-os.conf"
LOGS="$WORKDIR/logs"

command -v whiptail >/dev/null 2>&1 || USE_TUI=0
[ -t 0 ] && [ -t 1 ] || USE_TUI=0
if [ "${TERM:-}" = linux ]; then
    echo "注意: Linux のコンソール(tty)では日本語が表示されません。SSH かデスクトップの端末から実行してください。" >&2
fi

# ============================================================================ 画面(whiptail / 文字だけ。scripts/install.sh と同じ作り)
TW=78; TH=22
if command -v tput >/dev/null 2>&1; then
    c=$(tput cols 2>/dev/null || echo 80); l=$(tput lines 2>/dev/null || echo 24)
    [ "$c" -lt 80 ] && TW=$((c - 2)); [ "$l" -lt 24 ] && TH=$((l - 2))
fi
LH=$((TH - 9))

ui_msg() {   # ui_msg 見出し 本文
    if [ "$ASSUME_YES" -eq 1 ]; then printf '\n== %s ==\n%b\n' "$1" "$2"; return; fi
    if [ "$USE_TUI" -eq 1 ]; then whiptail --title "$TITLE: $1" --msgbox "$2" "$TH" "$TW"; return; fi
    printf '\n== %s ==\n%b\n' "$1" "$2"
    read -r -p "Enter で次へ " _ </dev/tty
}
ui_yesno() {   # ui_yesno 見出し 本文 [既定 yes|no] → 0 = はい
    local def="${3:-yes}"
    if [ "$ASSUME_YES" -eq 1 ]; then [ "$def" = yes ]; return; fi
    if [ "$USE_TUI" -eq 1 ]; then
        if [ "$def" = no ]; then whiptail --title "$TITLE: $1" --defaultno --yes-button "はい" --no-button "いいえ" --yesno "$2" "$TH" "$TW"
        else whiptail --title "$TITLE: $1" --yes-button "はい" --no-button "いいえ" --yesno "$2" "$TH" "$TW"; fi
        return
    fi
    local hint="[Y/n]"; [ "$def" = no ] && hint="[y/N]"
    printf '\n== %s ==\n%b\n' "$1" "$2"
    local a; read -r -p "$hint " a </dev/tty
    case "${a:-}" in [Yy]*) return 0 ;; [Nn]*) return 1 ;; *) [ "$def" = yes ] ;; esac
}
# ui_menu 見出し 本文 既定のタグ タグ 説明 ... → 選んだタグ(やめたときは何も出さず 1 を返す)
ui_menu() {
    local title="$1" text="$2" def="$3"; shift 3
    if [ "$ASSUME_YES" -eq 1 ]; then echo "$def"; return 0; fi
    if [ "$USE_TUI" -eq 1 ]; then
        whiptail --title "$TITLE: $title" --ok-button "決定" --cancel-button "やめる" --default-item "$def" \
            --menu "$text" "$TH" "$TW" "$LH" "$@" 3>&1 1>&2 2>&3
        return
    fi
    printf '\n== %s ==\n%b\n' "$title" "$text" >&2
    local tags=() i=0 a
    while [ $# -ge 2 ]; do
        i=$((i + 1)); tags+=("$1")
        printf '  %2d) %s%s\n' "$i" "$2" "$([ "$1" = "$def" ] && echo '  ← おすすめ')" >&2
        shift 2
    done
    read -r -p "番号(Enter でおすすめ): " a </dev/tty
    if [[ "${a:-}" =~ ^[0-9]+$ ]] && [ "$a" -ge 1 ] && [ "$a" -le "${#tags[@]}" ]; then echo "${tags[$((a - 1))]}"; else echo "$def"; fi
}
ui_input() {   # ui_input 見出し 本文 既定値 → 入力された文字
    local def="$3"
    if [ "$ASSUME_YES" -eq 1 ]; then echo "$def"; return 0; fi
    if [ "$USE_TUI" -eq 1 ]; then
        whiptail --title "$TITLE: $1" --ok-button "決定" --cancel-button "やめる" --inputbox "$2" "$TH" "$TW" "$def" 3>&1 1>&2 2>&3
        return
    fi
    printf '\n== %s ==\n%b\n' "$1" "$2" >&2
    local a; read -r -p "[$def] " a </dev/tty
    echo "${a:-$def}"
}

RESULTS="$(mktemp)"
trap 'rm -f "$RESULTS"' EXIT
ok()   { echo "  ✔ $*"; echo "OK|$*" >> "$RESULTS"; }
ng()   { echo "  ✖ $*"; echo "NG|$*" >> "$RESULTS"; }
info() { echo "  ・$*"; }
step() { echo; echo "■ $*"; }

# ============================================================================ 答えの保存
SAVED_KEYS="RELEASE MACHINE EXTRA_MACHINE_LAYER_URL TARGET STORAGE DEV_MODE AASDK SRC_MODE TIMEZONE RM_WORK FFMPEG_OK QT_BRANCH BITBAKE_BRANCH CORE_KIND"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"
: "${RELEASE:=wrynose}" "${MACHINE:=intel-corei7-64}" "${EXTRA_MACHINE_LAYER_URL:=}" "${TARGET:=opencruise-image}"
: "${STORAGE:=ro-home}" "${DEV_MODE:=yes}" "${AASDK:=yes}" "${SRC_MODE:=local}" "${TIMEZONE:=Asia/Tokyo}"
: "${RM_WORK:=yes}" "${FFMPEG_OK:=no}" "${QT_BRANCH:=}" "${BITBAKE_BRANCH:=}" "${CORE_KIND:=}"
save_conf() {
    mkdir -p "$WORKDIR"
    { echo "# scripts/build-os.sh の答え(次回の既定。消してもよい)"
      local k; for k in $SAVED_KEYS; do printf '%s=%q\n' "$k" "${!k}"; done; } > "$CONF"
}

# ============================================================================ 調べる
HOST_PKGS="build-essential chrpath cpio debianutils diffstat file gawk gcc git iputils-ping libacl1 liblz4-tool locales python3 python3-git python3-jinja2 python3-pexpect python3-pip python3-subunit socat texinfo unzip wget xz-utils zstd"
is_debian() { [ -r /etc/os-release ] && grep -qiE '^ID(_LIKE)?=.*(debian|ubuntu)' /etc/os-release; }
free_gb() { local d="$1"; while [ ! -d "$d" ]; do d="$(dirname "$d")"; done; df -Pk "$d" | awk 'NR==2{printf "%d", $4/1024/1024}'; }
mem_gb() { awk '/MemTotal/{printf "%d", $2/1024/1024}' /proc/meminfo; }
has_branch() { git ls-remote --exit-code --heads "$1" "$2" >/dev/null 2>&1; }
list_branches() { git ls-remote --heads "$1" 2>/dev/null | sed 's#.*refs/heads/##'; }
series_bitbake() { case "$1" in scarthgap) echo 2.8 ;; styhead) echo 2.10 ;; walnascar) echo 2.12 ;; whinlatter) echo 2.14 ;; wrynose) echo 2.16 ;; *) echo "" ;; esac; }

do_check() {
    step "この PC がビルドできるか"
    local fails=0
    if is_debian; then ok "OS: $(. /etc/os-release; echo "$PRETTY_NAME")"; else ng "Debian / Ubuntu 以外です。Yocto の公式の手順で必要なパッケージを入れてください(ここでは自動で入れません)"; fi
    local missing=() p
    if is_debian && command -v dpkg >/dev/null 2>&1; then
        for p in $HOST_PKGS; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
        if [ "${#missing[@]}" -gt 0 ]; then ng "足りないパッケージ: ${missing[*]}"; fails=$((fails + 1)); else ok "ビルドに要るパッケージ(${HOST_PKGS%% *} ほか)はそろっています"; fi
    fi
    if locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; then ok "ロケール en_US.UTF-8 があります"
    else ng "ロケール en_US.UTF-8 がありません(BitBake が要求します): sudo locale-gen en_US.UTF-8 && sudo update-locale"; fails=$((fails + 1)); fi
    local fg; fg="$(free_gb "$WORKDIR")"
    if [ "$fg" -ge 100 ]; then ok "空き容量: ${fg}GB($WORKDIR)"
    elif [ "$fg" -ge 60 ]; then ok "空き容量: ${fg}GB(足りますが少なめです。rm_work(作業ファイルの自動削除)を使うと収まります)"
    else ng "空き容量が ${fg}GB しかありません(100GB 以上を推奨。作業フォルダは --workdir で別のディスクにできます)"; fails=$((fails + 1)); fi
    local mg; mg="$(mem_gb)"
    if [ "$mg" -ge 8 ]; then ok "メモリ: ${mg}GB / CPU: $(nproc) コア"; else ng "メモリが ${mg}GB です(8GB 以上を推奨。足りないとビルドが途中で落ちます。スワップを足してください)"; fi
    if timeout 20 git ls-remote --heads "$URL_OECORE" >/dev/null 2>&1; then ok "ネットワーク: $URL_OECORE に届きます"
    else ng "ネットワーク: $URL_OECORE に届きません(インターネット・プロキシを確認)"; fails=$((fails + 1)); fi
    if [ -d "$LAYER" ]; then ok "OpenCruise のレイヤー: $LAYER"; else ng "レイヤーがありません: $LAYER"; fails=$((fails + 1)); fi
    return "$fails"
}

install_host_packages() {
    is_debian || return 0
    local missing=() p
    for p in $HOST_PKGS; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
    [ "${#missing[@]}" -eq 0 ] && return 0
    if ui_yesno "パッケージ" "ビルドに要るパッケージが足りません:\n\n${missing[*]}\n\nsudo apt で入れますか?" yes; then
        sudo apt-get update -q && sudo apt-get install -y "${missing[@]}" && ok "パッケージを入れました" || { ng "パッケージを入れられませんでした"; return 1; }
    else
        ng "必要なパッケージが足りないまま進みます(ビルドで止まる場合があります)"
    fi
}

# ============================================================================ 質問
ask_all() {
    ui_msg "はじめに" "OpenCruise 専用の OS(Yocto)を作ります。\n\n・作業フォルダ: $WORKDIR\n・初回のビルドは数時間かかります(Qt6 や FFmpeg を自分でビルドするため)\n・必要な空き容量は 100GB 前後です\n\nわからない質問は Enter(おすすめ)で進めて大丈夫です。"

    RELEASE="$(ui_menu "Yocto のバージョン" "Yocto のどの版で作りますか?(LTS = 長く保守される版)" "$RELEASE" \
        wrynose "wrynose (6.0 LTS) 新しい。おすすめ" \
        scarthgap "scarthgap (5.0 LTS) 実績がある。このレイヤーでは未検証")" || die "やめました"

    MACHINE="$(ui_menu "動かす機械" "この OS を動かす機械は?" "$( [ "$MACHINE" = qemux86-64 ] && echo qemux86-64 || { [ "$MACHINE" = intel-corei7-64 ] && echo intel-corei7-64 || echo custom; } )" \
        intel-corei7-64 "Intel の x86_64 PC の実機(CF-MX5 など)。おすすめ" \
        qemux86-64 "PC なしで試す(QEMU の仮想マシン)" \
        custom "そのほか(機種の名前と、必要ならそのレイヤーを自分で指定)")" || die "やめました"
    if [ "$MACHINE" = custom ]; then
        MACHINE="$(ui_input "機種の名前" "Yocto の MACHINE 名を入力してください(例: raspberrypi4-64)。" "raspberrypi4-64")" || die "やめました"
        EXTRA_MACHINE_LAYER_URL="$(ui_input "機種のレイヤー" "その機種の BSP レイヤーの git の URL を入力してください(例: https://git.yoctoproject.org/meta-raspberrypi)。\n要らないときは空のままにします。" "$EXTRA_MACHINE_LAYER_URL")" || die "やめました"
    else
        EXTRA_MACHINE_LAYER_URL=""
    fi

    TARGET="$(ui_menu "作るもの" "どのイメージを作りますか?" "$TARGET" \
        opencruise-image "OpenCruise 専用(Qt のベース + OpenCruise アプリ + 自動起動)。おすすめ" \
        qt-appliance-image "Qt6 のベースだけ(ほかの Qt アプリを載せる土台)")" || die "やめました"

    if [ "$MACHINE" = intel-corei7-64 ]; then
        STORAGE="$(ui_menu "ディスクの使い方" "車載は電源が急に切れるので、ルートを読み取り専用にして、書き込みを /home だけにすると壊れにくくなります。" "$STORAGE" \
            ro-home "ルートは読み取り専用 + /home は書き込み用(設定・ログ・背景画像)。おすすめ" \
            rw "普通の読み書きできるルート(試すとき・うまく動かないとき)")" || die "やめました"
    else
        STORAGE=rw
    fi

    DEV_MODE="$(ui_menu "開発用の機能" "SSH とパスワードなしの root ログインを入れますか?(実機で動かしながら直すときに便利。安全のため、完成品では外します)" "$DEV_MODE" \
        yes "入れる(開発用。おすすめ)" \
        no "入れない(完成品)")" || die "やめました"

    if ui_yesno "Android Auto" "Android Auto の接続(aasdk)を OS に含めますか?\n\n「いいえ」だと UI だけのビルドで、接続は「利用不可」と表示されます(protobuf まわりでビルドが止まるときの逃げ道にもなります)。" "$([ "$AASDK" = yes ] && echo yes || echo no)"; then AASDK=yes; else AASDK=no; fi

    SRC_MODE="$(ui_menu "アプリのソース" "OpenCruise アプリのソースはどこから取りますか?" "$SRC_MODE" \
        local "このフォルダ($REPO)の中身。手元の修正がそのまま入る。おすすめ" \
        git "GitHub の main の最新(手元の修正は入らない)")" || die "やめました"

    TIMEZONE="$(ui_input "タイムゾーン" "OS のタイムゾーンを入力してください。" "$TIMEZONE")" || die "やめました"

    if ui_yesno "ディスクの節約" "ビルドが終わった部品の作業ファイルを自動で消しますか?(rm_work。空き容量が 1/3 ほどで済みます。ビルドが失敗したときの調査はしにくくなります)" "$([ "$RM_WORK" = yes ] && echo yes || echo no)"; then RM_WORK=yes; else RM_WORK=no; fi

    ask_licenses
    save_conf
}

ask_licenses() {
    if [ "$FFMPEG_OK" = yes ]; then return 0; fi
    if [ "$ASSUME_YES" -eq 1 ]; then
        if [ "$ACCEPT_LICENSES" -eq 1 ]; then FFMPEG_OK=yes; return 0; fi
        die "FFmpeg のライセンス区分(commercial)の受け入れが要ります。--accept-licenses を付けるか、ウィザードで答えてください。"
    fi
    if ui_yesno "ライセンス" "OpenCruise は H.264 の映像のデコードに FFmpeg を使います。\nYocto では FFmpeg は「commercial」(特許などの配慮が要る)に分類されていて、受け入れないとビルドできません。\n\nこのイメージを配布・販売する場合は、H.264 などの特許の扱いを自分で確認してください。\n\nlocal.conf に LICENSE_FLAGS_ACCEPTED = \"commercial commercial_ffmpeg\" を書いてよいですか?" no; then
        FFMPEG_OK=yes
    else
        die "FFmpeg を受け入れないと、アプリがビルドできません(映像のデコードに必要です)。やめました。"
    fi
}

# ============================================================================ 取得
CORE_DIR=""; CORE_LAYER=""; INIT=""

fetch_layer() {   # fetch_layer 名前 URL ブランチ フォルダ [full]
    local name="$1" url="$2" br="$3" dir="$4" full="${5:-}"
    if [ -d "$dir/.git" ]; then
        if [ "$UPDATE" -eq 1 ]; then
            info "$name を更新します"
            git -C "$dir" fetch --quiet origin "$br" && git -C "$dir" checkout --quiet "$br" 2>/dev/null; git -C "$dir" merge --quiet --ff-only "origin/$br" 2>/dev/null || ng "$name を更新できませんでした(手元に変更があるかもしれません)"
        else
            info "$name は取得済みです($(git -C "$dir" rev-parse --abbrev-ref HEAD) $(git -C "$dir" rev-parse --short HEAD))"
        fi
        return 0
    fi
    info "$name を取得します(ブランチ $br)"
    local args=(--quiet --branch "$br")
    [ -z "$full" ] && args+=(--single-branch --depth 1)
    if git clone "${args[@]}" "$url" "$dir"; then ok "$name を取得しました"; else ng "$name を取得できませんでした: $url"; return 1; fi
}

# 取得先のブランチを確かめる。無ければ一覧から選んでもらう
resolve_branch() {   # resolve_branch 名前 URL 既定ブランチ → 使うブランチ(標準出力)
    local name="$1" url="$2" want="$3" br
    if has_branch "$url" "$want"; then echo "$want"; return 0; fi
    info "$name に '$want' というブランチがありません。一覧から選びます" >&2
    local items=() b
    while read -r b; do [ -n "$b" ] && items+=("$b" "$b"); done < <(list_branches "$url" | sort -Vr | head -n 15)
    [ "${#items[@]}" -gt 0 ] || { echo "エラー: $url のブランチ一覧を取れませんでした" >&2; return 1; }
    ui_menu "$name のブランチ" "'$want' が無いので、使うブランチを選んでください。" "${items[0]}" "${items[@]}"
}

pick_qt_branch() {   # pick_qt_branch フォルダ シリーズ名 → 使う meta-qt6 のブランチ
    local dir="$1" series="$2" b
    local all=() match=() other=()
    while read -r b; do all+=("$b"); done < <({ git -C "$dir" for-each-ref --format='%(refname:strip=3)' refs/remotes/origin | grep -E '^6\.[0-9]+$' | sort -Vr
                                                   git -C "$dir" for-each-ref --format='%(refname:strip=3)' refs/remotes/origin | grep -x 'dev'; })
    for b in "${all[@]}"; do
        if git -C "$dir" show "origin/$b:conf/layer.conf" 2>/dev/null | grep 'LAYERSERIES_COMPAT' | grep -qw "$series"; then match+=("$b"); else other+=("$b"); fi
    done
    [ "${#all[@]}" -gt 0 ] || { echo "エラー: meta-qt6 のブランチが見つかりません" >&2; return 1; }
    local items=() def=""
    for b in "${match[@]}"; do items+=("$b" "$b($series に対応)"); done
    for b in "${other[@]}"; do items+=("$b" "$b(対応の記載なし)"); done
    if [ "${#match[@]}" -gt 0 ]; then def="${match[0]}"; else def="${all[0]}"; echo "  ・注意: meta-qt6 に $series 対応と書かれたブランチが見つかりません。$def で試します" >&2; fi
    if [ -n "$QT_BRANCH" ] && printf '%s\n' "${all[@]}" | grep -qx "$QT_BRANCH"; then def="$QT_BRANCH"; fi
    ui_menu "Qt のバージョン" "meta-qt6 のブランチ(= Qt のバージョン)を選んでください。$series に対応と書かれているものがおすすめです。" "$def" "${items[@]}"
}

do_fetch() {
    step "レイヤーの取得"
    mkdir -p "$SOURCES" "$LOGS"
    # 1) Yocto 本体。poky に release のブランチがあれば poky、無ければ openembedded-core + bitbake(wrynose 以降はこちら)
    if [ -z "$CORE_KIND" ] || [ ! -d "$SOURCES/$([ "$CORE_KIND" = poky ] && echo poky || echo openembedded-core)/.git" ]; then
        if has_branch "$URL_POKY" "$RELEASE"; then CORE_KIND="poky"; else CORE_KIND="split"; fi
    fi
    if [ "$CORE_KIND" = poky ]; then
        fetch_layer poky "$URL_POKY" "$RELEASE" "$SOURCES/poky" || return 1
        CORE_DIR="$SOURCES/poky"; CORE_LAYER="$CORE_DIR/meta"
    else
        local oecb; oecb="$(resolve_branch openembedded-core "$URL_OECORE" "$RELEASE")" || return 1
        fetch_layer openembedded-core "$URL_OECORE" "$oecb" "$SOURCES/openembedded-core" || return 1
        [ -n "$BITBAKE_BRANCH" ] || BITBAKE_BRANCH="$(series_bitbake "$RELEASE")"
        BITBAKE_BRANCH="$(resolve_branch bitbake "$URL_BITBAKE" "${BITBAKE_BRANCH:-master}")" || return 1
        fetch_layer bitbake "$URL_BITBAKE" "$BITBAKE_BRANCH" "$SOURCES/bitbake" || return 1
        CORE_DIR="$SOURCES/openembedded-core"; CORE_LAYER="$CORE_DIR/meta"
    fi
    INIT="$CORE_DIR/oe-init-build-env"
    [ -f "$INIT" ] || { ng "oe-init-build-env が見つかりません: $INIT"; return 1; }

    # 2) meta-openembedded(リリース名のブランチ)
    local moeb; moeb="$(resolve_branch meta-openembedded "$URL_METAOE" "$RELEASE")" || return 1
    fetch_layer meta-openembedded "$URL_METAOE" "$moeb" "$SOURCES/meta-openembedded" || return 1

    # 3) meta-qt6(Qt のバージョンのブランチ。全ブランチを取って、$RELEASE 対応のものを探す)
    fetch_layer meta-qt6 "$URL_QT6" dev "$SOURCES/meta-qt6" full || fetch_layer meta-qt6 "$URL_QT6" "$(list_branches "$URL_QT6" | head -n 1)" "$SOURCES/meta-qt6" full || return 1
    [ "$UPDATE" -eq 1 ] && git -C "$SOURCES/meta-qt6" fetch --quiet origin
    QT_BRANCH="$(pick_qt_branch "$SOURCES/meta-qt6" "$RELEASE")" || return 1
    git -C "$SOURCES/meta-qt6" checkout --quiet "$QT_BRANCH" 2>/dev/null || git -C "$SOURCES/meta-qt6" checkout --quiet -B "$QT_BRANCH" "origin/$QT_BRANCH" || { ng "meta-qt6 を $QT_BRANCH にできませんでした"; return 1; }
    [ "$UPDATE" -eq 1 ] && git -C "$SOURCES/meta-qt6" merge --quiet --ff-only "origin/$QT_BRANCH" 2>/dev/null
    ok "meta-qt6: $QT_BRANCH"

    # 4) 機種のレイヤー
    EXTRA_LAYER_DIRS=()
    case "$MACHINE" in
        intel-corei7-64)
            local intb; intb="$(resolve_branch meta-intel "$URL_INTEL" "$RELEASE")" || return 1
            fetch_layer meta-intel "$URL_INTEL" "$intb" "$SOURCES/meta-intel" || return 1
            EXTRA_LAYER_DIRS+=("$SOURCES/meta-intel") ;;
        qemux86-64) ;;
        *)
            if [ -n "$EXTRA_MACHINE_LAYER_URL" ]; then
                local nm; nm="$(basename "$EXTRA_MACHINE_LAYER_URL" .git)"
                local exb; exb="$(resolve_branch "$nm" "$EXTRA_MACHINE_LAYER_URL" "$RELEASE")" || return 1
                fetch_layer "$nm" "$EXTRA_MACHINE_LAYER_URL" "$exb" "$SOURCES/$nm" || return 1
                EXTRA_LAYER_DIRS+=("$SOURCES/$nm")
            fi ;;
    esac
    save_conf
}

# ============================================================================ 設定(bblayers.conf / local.conf)
gen_bblayers() {
    {
        echo "# scripts/build-os.sh が作った(作り直すと上書きされる。手で変えたいときは local.conf の末尾に足す)"
        echo 'POKY_BBLAYERS_CONF_VERSION = "2"'
        echo 'BBPATH = "${TOPDIR}"'
        echo 'BBFILES ?= ""'
        echo 'BBLAYERS ?= " \'
        echo "  $CORE_LAYER \\"
        echo "  $SOURCES/meta-openembedded/meta-oe \\"
        echo "  $SOURCES/meta-qt6 \\"
        local d; for d in "${EXTRA_LAYER_DIRS[@]}"; do echo "  $d \\"; done
        echo "  $LAYER \\"
        echo '"'
    } > "$BUILD/conf/bblayers.conf"
}

gen_local() {
    local cpus mg jobs
    cpus="$(nproc)"; mg="$(mem_gb)"
    jobs=$((mg / 2)); [ "$jobs" -lt 1 ] && jobs=1; [ "$jobs" -gt "$cpus" ] && jobs="$cpus"
    {
        echo "# scripts/build-os.sh が作った(作り直すと上書きされる。手で変えたいときはこのファイルの末尾に足す)"
        echo "# 用語: MACHINE = 動かす機械 / DISTRO = OS の方針 / sstate-cache = ビルド済み部品の保管庫(2 回目から速くなる)"
        echo "MACHINE = \"$MACHINE\""
        echo 'DISTRO = "opencruise"'
        echo 'CONF_VERSION = "2"'
        echo
        echo "# ダウンロードとビルド済み部品は、ビルドをやり直しても残るよう作業フォルダの直下に置く"
        echo "DL_DIR = \"$WORKDIR/downloads\""
        echo "SSTATE_DIR = \"$WORKDIR/sstate-cache\""
        echo
        echo "# 並列数(メモリ 2GB につき 1 つ。Qt のビルドはメモリを食うので、落ちるときはここを減らす)"
        echo "BB_NUMBER_THREADS = \"$jobs\""
        echo "PARALLEL_MAKE = \"-j $jobs\""
        echo
        echo "# FFmpeg(H.264 のデコード)は commercial 区分。ウィザードで受け入れた"
        echo 'LICENSE_FLAGS_ACCEPTED:append = " commercial commercial_ffmpeg"'
        echo
        echo "# イメージ・タイムゾーン"
        echo "DEFAULT_TIMEZONE = \"$TIMEZONE\""
        echo 'PACKAGE_CLASSES = "package_ipk"'
        echo
        echo "# Qt の画面は eglfs(DRM/KMS 直描画)。Qt Multimedia は FFmpeg を使う"
        echo 'PACKAGECONFIG:append:pn-qtbase = " eglfs kms gbm libinput fontconfig"'
        echo 'PACKAGECONFIG:append:pn-qtmultimedia = " ffmpeg"'
        echo
        if [ "$DEV_MODE" = yes ]; then
            echo "# 開発用: SSH・パスワードなし root ログイン・ログ(完成品では外す)"
            echo 'EXTRA_IMAGE_FEATURES:append = " ssh-server-openssh allow-root-login allow-empty-password empty-root-password post-install-logging"'
        else
            echo "# 完成品: SSH も root ログインも入れない"
        fi
        echo
        if [ "$AASDK" = no ]; then
            echo "# Android Auto(aasdk)を含めない"
            echo 'PACKAGECONFIG:remove:pn-opencruise = "aasdk"'
            echo
        fi
        if [ "$STORAGE" = ro-home ]; then
            echo "# ルートは読み取り専用、書き込みは /home だけ(wic/opencruise-x86.wks.in)"
            echo 'OPENCRUISE_READONLY_ROOTFS = "1"'
            echo 'OPENCRUISE_CMDLINE:append = " ro"'
        fi
        if [ "$MACHINE" = intel-corei7-64 ]; then
            echo "# x86 実機: UEFI(systemd-boot)のディスクイメージを作る。GPU(i915)のファームウェアも入れる"
            echo 'EFI_PROVIDER = "systemd-boot"'
            echo 'WKS_FILE = "opencruise-x86.wks.in"'
            echo 'IMAGE_FSTYPES = "wic wic.bmap"'
            echo 'IMAGE_INSTALL:append = " linux-firmware-i915"'
        fi
        echo
        if [ "$SRC_MODE" = local ]; then
            echo "# アプリのソースは、このリポジトリの手元のフォルダをそのまま使う(修正がすぐ反映される)"
            echo 'INHERIT += "externalsrc"'
            echo "EXTERNALSRC:pn-opencruise = \"$REPO\""
            echo 'EXTERNALSRC_BUILD:pn-opencruise = "${WORKDIR}/build"'
            echo
        fi
        if [ "$RM_WORK" = yes ]; then
            echo "# ビルドが終わった部品の作業ファイルを消して、ディスクを節約する"
            echo 'INHERIT += "rm_work"'
            echo 'RM_WORK_EXCLUDE += "opencruise"'
        fi
    } > "$BUILD/conf/local.conf"
}

in_env() {   # in_env コマンド... : oe-init-build-env を読み込んだ状態でコマンドを実行する
    bash -c 'cd "$1" || exit 1; set +u; . "$2" "$3" >/dev/null || exit 1; shift 3; exec "$@"' _ "$WORKDIR" "$INIT" "$BUILD" "$@"
}

do_config() {
    step "設定の作成"
    mkdir -p "$BUILD/conf"
    gen_bblayers; gen_local
    ok "設定を書きました: $BUILD/conf/{bblayers,local}.conf"
    if in_env bitbake-layers show-layers > "$LOGS/layers.log" 2>&1; then
        ok "レイヤーの構成を確認しました(bitbake-layers show-layers)"
    else
        ng "レイヤーの構成でエラーです。内容: $LOGS/layers.log"
        sed -n '1,15p' "$LOGS/layers.log" | sed 's/^/      /'
        return 1
    fi
}

# ============================================================================ ビルド
image_file() {
    local dir="$BUILD/tmp/deploy/images/$MACHINE"
    ls -t "$dir/$TARGET"-*.wic "$dir"/*.wic 2>/dev/null | head -n 1
}

do_build() {
    step "ビルド"
    [ -f "$BUILD/conf/local.conf" ] || { ng "設定がありません。先にウィザードを実行してください"; return 1; }
    mkdir -p "$LOGS"
    local log; log="$LOGS/build-$(date +%Y%m%d-%H%M%S).log"
    info "レシピの確認(bitbake -p)。ここで落ちるときは、レシピ・レイヤーの設定の問題です"
    if ! in_env bitbake -p 2>&1 | tee "$LOGS/parse.log" | tail -n 5; [ "${PIPESTATUS[0]}" -eq 0 ]; then
        ng "レシピの確認に失敗しました。ログ: $LOGS/parse.log(エラー行を調べてください)"; return 1
    fi
    ok "レシピの確認ができました"
    info "bitbake $TARGET を始めます。数時間かかります(止めても --build で続きから再開できます)。ログ: $log"
    in_env bitbake "$TARGET" 2>&1 | tee "$log"
    local rc="${PIPESTATUS[0]}"
    if [ "$rc" -ne 0 ]; then
        ng "ビルドに失敗しました(終了コード $rc)。ログ: $log"
        echo "      失敗した部品は上の ERROR: 行に出ています。直したあと --build で続きから再開できます。" >&2
        return 1
    fi
    ok "ビルドしました: $TARGET"
    local img; img="$(image_file)"
    if [ -n "$img" ]; then ok "ディスクイメージ: $img"
    elif [ "$MACHINE" = qemux86-64 ]; then
        info "試すとき(QEMU): $0 --shell を開いて  runqemu qemux86-64 $TARGET slirp  を実行"
    else info "成果物のフォルダ: $BUILD/tmp/deploy/images/$MACHINE/"; fi
}

# ============================================================================ 書き込み
do_flash() {
    step "USB メモリ / SSD へ書き込み"
    local img; img="$(image_file)"
    [ -n "$img" ] && [ -f "$img" ] || { ng "書き込むイメージ(.wic)がありません。先にビルドしてください(--build)"; return 1; }
    info "イメージ: $img($(du -h "$(readlink -f "$img")" | cut -f1))"
    command -v lsblk >/dev/null 2>&1 || { ng "lsblk がありません"; return 1; }
    local rootdisk; rootdisk="$(lsblk -no PKNAME "$(findmnt -no SOURCE / 2>/dev/null)" 2>/dev/null | head -n 1)"
    local items=() NAME SIZE TRAN RM MODEL line
    while read -r line; do
        eval "$line"
        [ -n "${NAME:-}" ] || continue
        [ "$(basename "$NAME")" = "$rootdisk" ] && continue
        [ "${TRAN:-}" = usb ] || [ "${RM:-0}" = 1 ] || continue
        items+=("$NAME" "$((SIZE / 1000 / 1000 / 1000))GB ${MODEL:-?} (${TRAN:-?})")
    done < <(lsblk -dnpb -P -o NAME,SIZE,TRAN,RM,MODEL 2>/dev/null)
    [ "${#items[@]}" -gt 0 ] || { ng "書き込める USB メモリが見つかりません(いまの OS が入っているディスクは出しません)。差し込んでからやり直してください"; return 1; }
    local dev; dev="$(ui_menu "書き込み先" "書き込み先を選んでください。\n【警告】選んだディスクの中身は全部消えます。" "${items[0]}" "${items[@]}")" || { info "やめました"; return 1; }
    [ -b "$dev" ] || { ng "選んだ機器がありません: $dev"; return 1; }
    local typed
    if [ "$ASSUME_YES" -eq 1 ]; then die "書き込みは --yes では行いません(消してよいか、手で確認が要ります)"; fi
    read -r -p "$dev の中身は全部消えます。続けるなら、そのデバイス名($dev)をもう一度入力: " typed </dev/tty
    [ "$typed" = "$dev" ] || { info "入力が違うのでやめました"; return 1; }
    sudo umount "$dev"* 2>/dev/null || true
    local bmap="${img%.wic}.wic.bmap"
    [ -f "$bmap" ] || bmap="$(readlink -f "$img").bmap"
    if command -v bmaptool >/dev/null 2>&1 && [ -f "$bmap" ]; then
        sudo bmaptool copy --bmap "$bmap" "$img" "$dev" || { ng "書き込みに失敗しました"; return 1; }
    else
        sudo dd if="$img" of="$dev" bs=4M conv=fsync status=progress || { ng "書き込みに失敗しました"; return 1; }
    fi
    sync
    ok "書き込みました: $dev(外して、対象の PC につないで起動してください。UEFI の起動順で USB を選ぶ)"
}

# ============================================================================ シェル
do_shell() {
    [ -f "$CONF" ] || die "まだ設定がありません。先にウィザードを実行してください"
    [ "$CORE_KIND" = poky ] && CORE_DIR="$SOURCES/poky" || CORE_DIR="$SOURCES/openembedded-core"
    INIT="$CORE_DIR/oe-init-build-env"
    [ -f "$INIT" ] || die "oe-init-build-env が見つかりません: $INIT"
    echo "BitBake のシェルを開きます。例:  bitbake $TARGET  /  bitbake -c cleansstate opencruise  /  bitbake-layers show-layers"
    echo "出るときは exit。"
    exec bash --rcfile <(echo "[ -f ~/.bashrc ] && . ~/.bashrc; cd '$WORKDIR'; . '$INIT' '$BUILD' >/dev/null") -i
}

# ============================================================================ まとめ
print_summary() {
    echo; echo "■ 結果"
    local n_ok n_ng
    n_ok="$(grep -c '^OK|' "$RESULTS" || true)"; n_ng="$(grep -c '^NG|' "$RESULTS" || true)"
    grep '^NG|' "$RESULTS" | sed 's/^NG|/  ✖ /'
    echo "  成功 $n_ok / 失敗 $n_ng"
}

# ============================================================================ 本体
case "$MODE" in
    check)
        do_check; rc=$?; print_summary; exit "$rc" ;;
    shell)
        do_shell ;;
    flash)
        [ -f "$CONF" ] || die "まだ設定がありません。先にウィザードを実行してください"
        do_flash; rc=$?; print_summary; exit "$rc" ;;
    build)
        [ -f "$CONF" ] || die "まだ設定がありません。先にウィザードを実行してください"
        do_fetch && do_config && do_build; rc=$?; print_summary; exit "$rc" ;;
    wizard)
        do_check; pre=$?
        if [ "$pre" -gt 0 ]; then
            install_host_packages
            if ! ui_yesno "確認" "上に ✖ が出ています。このまま続けますか?(足りないものがあると途中で止まります)" no; then exit 1; fi
        fi
        ask_all
        ui_msg "確認" "この内容で進めます。\n\n・Yocto: $RELEASE\n・機械: $MACHINE${EXTRA_MACHINE_LAYER_URL:+ ($EXTRA_MACHINE_LAYER_URL)}\n・イメージ: $TARGET\n・ディスク: $STORAGE\n・開発用機能: $DEV_MODE\n・Android Auto: $AASDK\n・アプリのソース: $SRC_MODE\n・作業フォルダ: $WORKDIR"
        do_fetch && do_config || { print_summary; exit 1; }
        if [ "$CONFIG_ONLY" -eq 1 ]; then
            echo; echo "設定までで止めました。ビルドは: $0 --build"; print_summary; exit 0
        fi
        if ui_yesno "ビルド" "ビルドを始めますか?(数時間かかります。途中で止めても --build で続きから再開できます)" yes; then
            do_build || { print_summary; exit 1; }
            if [ "$MACHINE" != qemux86-64 ] && [ -n "$(image_file)" ] && [ "$ASSUME_YES" -eq 0 ]; then
                ui_yesno "書き込み" "できあがったイメージを、いま USB メモリ / SSD へ書き込みますか?" no && do_flash
            fi
        else
            echo; echo "ビルドは後から: $0 --build"
        fi
        print_summary ;;
esac
