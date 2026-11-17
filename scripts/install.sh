#!/bin/bash
# OpenCruise のインストーラー(ウィザード形式。Debian 系)。sudo で実行する。
#
#   sudo scripts/install.sh               ウィザード: 入れるものを選んで、質問に答えて、まとめて入れる
#   sudo scripts/install.sh --check       今の状態(とくに権限)を確かめるだけ(何も変えない)
#   sudo scripts/install.sh --uninstall   このインストーラーが入れた設定を外す
#
# オプション:
#   --user <名前>   アプリを動かすユーザー(既定: sudo したユーザー)
#   --yes           質問せず、おすすめの項目をおすすめの答えで入れる(SSH から一気に入れるとき)
#   --no-tui        whiptail(画面のダイアログ)を使わず、文字の質問だけで進める
#
# 入れられるもの(ウィザードで選ぶ):
#   パッケージ      ビルド・実行に要るもの(この Debian に無いものは飛ばして知らせる)
#   ビルド          アプリをビルドする(build/app/opencruise)
#   権限            ユーザーのグループ(画面・入力・音・カメラ・USB・シリアル)、電源を切る・再起動・電源モードの許可(polkit)、
#                   バックライトの明るさの書き込み、蓋を閉じても・放っておいてもスリープしない
#   Android Auto    スマホの USB を開ける権限(udev)
#   タッチパネル    タッチパネルの向きの補正(udev。libinput の補正)と、触って試す
#   音              ALSA へ直接出す準備(PipeWire / PulseAudio を止める)と、音を出して試す
#   起動画面        起動画面(Plymouth)と自動起動(scripts/bootsplash/install.sh を呼ぶ)
#   CF-MX5          AC を挿したら起動する(scripts/cf-mx5/install-afterg3.sh を呼ぶ。CF-MX5 のときだけ出す)
#
# 入れたものは /etc/opencruise/install.state に記録し、--uninstall で外す。ログは /var/log/opencruise-install.log。
# グループの変更は、次にログインしたとき(自動起動ならアプリの次の起動・再起動のあと)から効く。
# 日本語を出すので、SSH かデスクトップの端末から実行する(Linux のコンソール(tty)では文字化けする)。
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
APP="$REPO/build/app/opencruise"
STATE_DIR=/etc/opencruise
STATE="$STATE_DIR/install.state"
LOG=/var/log/opencruise-install.log
TITLE="OpenCruise インストーラー"

# このインストーラーが作るファイル
RULE_USB=/etc/udev/rules.d/51-opencruise-android.rules
RULE_BACKLIGHT=/etc/udev/rules.d/91-opencruise-backlight-permission.rules
RULE_TOUCH=/etc/udev/rules.d/92-opencruise-touch.rules
POLKIT_RULE=/etc/polkit-1/rules.d/50-opencruise.rules
POLKIT_PKLA=/etc/polkit-1/localauthority/50-local.d/50-opencruise.pkla
LOGIND_CONF=/etc/systemd/logind.conf.d/opencruise.conf
SLEEP_TARGETS="sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target"
AUDIO_UNITS="pipewire.socket pipewire.service pipewire-pulse.socket pipewire-pulse.service wireplumber.service pulseaudio.socket pulseaudio.service"
GROUPS_WANTED="video render input audio plugdev dialout"

RUN_USER="${SUDO_USER:-}"
MODE=install
ASSUME_YES=0
USE_TUI=1

while [ $# -gt 0 ]; do
    case "$1" in
        --user) RUN_USER="${2:-}"; shift 2 ;;
        --check) MODE=check; shift ;;
        --uninstall) MODE=uninstall; shift ;;
        --yes|-y) ASSUME_YES=1; shift ;;
        --no-tui) USE_TUI=0; shift ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "不明なオプション: $1(--help で使い方)" >&2; exit 2 ;;
    esac
done

die() { echo "エラー: $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "sudo で実行してください: sudo $0"
[ -n "$RUN_USER" ] && [ "$RUN_USER" != root ] || die "アプリを動かすユーザーを --user で指定してください(root 以外)"
id "$RUN_USER" >/dev/null 2>&1 || die "ユーザーがいません: $RUN_USER"

if [ "${TERM:-}" = linux ]; then
    echo "注意: Linux のコンソール(tty)では日本語が表示されません。SSH かデスクトップの端末から実行してください。" >&2
fi
command -v whiptail >/dev/null 2>&1 || USE_TUI=0
[ -t 0 ] && [ -t 1 ] || USE_TUI=0

# ============================================================================ 画面(whiptail / 文字だけ)
TW=78; TH=22
if command -v tput >/dev/null 2>&1; then
    c=$(tput cols 2>/dev/null || echo 80); l=$(tput lines 2>/dev/null || echo 24)
    [ "$c" -lt 80 ] && TW=$((c - 2)); [ "$l" -lt 24 ] && TH=$((l - 2))
fi
LH=$((TH - 9))   # 一覧の行数

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
# ui_checklist 見出し 本文 タグ 説明 on|off ... → 選んだタグを 1 行ずつ出す
ui_checklist() {
    local title="$1" text="$2"; shift 2
    if [ "$ASSUME_YES" -eq 1 ]; then
        while [ $# -ge 3 ]; do [ "$3" = on ] && echo "$1"; shift 3; done; return 0
    fi
    if [ "$USE_TUI" -eq 1 ]; then
        whiptail --title "$TITLE: $title" --separate-output --ok-button "決定" --cancel-button "やめる" \
            --checklist "$text\n(スペースで選ぶ・外す、Enter で決定)" "$TH" "$TW" "$LH" "$@" 3>&1 1>&2 2>&3
        return
    fi
    printf '\n== %s ==\n%b\n' "$title" "$text" >&2
    local tags=() i=0 a
    while [ $# -ge 3 ]; do
        i=$((i + 1)); tags+=("$1")
        printf '  %2d) [%s] %s\n' "$i" "$([ "$3" = on ] && echo x || echo ' ')" "$2" >&2
        [ "$3" = on ] && a="${a:-} $i"
        shift 3
    done
    local picked; read -r -p "番号をスペース区切りで(Enter で [x] のもの): " picked </dev/tty
    [ -z "$picked" ] && picked="${a:-}"
    for n in $picked; do
        [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#tags[@]}" ] && echo "${tags[$((n - 1))]}"
    done
}
# ui_menu 見出し 本文 既定のタグ タグ 説明 ... → 選んだタグ
ui_menu() {
    local title="$1" text="$2" def="$3"; shift 3
    if [ "$ASSUME_YES" -eq 1 ]; then echo "$def"; return 0; fi
    if [ "$USE_TUI" -eq 1 ]; then
        whiptail --title "$TITLE: $title" --ok-button "決定" --cancel-button "戻る" --default-item "$def" \
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
has() { case " $SELECTED " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
sel() { case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# ============================================================================ 記録
state_set() {   # state_set キー 値(同じキーは上書き)
    mkdir -p "$STATE_DIR"
    touch "$STATE"
    sed -i "/^$1=/d" "$STATE"
    echo "$1=$2" >> "$STATE"
}
state_get() { [ -f "$STATE" ] && sed -n "s/^$1=//p" "$STATE" | tail -n 1; }
RESULTS="$(mktemp)"
trap 'rm -f "$RESULTS"' EXIT
ok()   { echo "  ✔ $*"; echo "OK|$*" >> "$RESULTS"; }
ng()   { echo "  ✖ $*"; echo "NG|$*" >> "$RESULTS"; }
info() { echo "  ・$*"; }
step() { echo; echo "■ $*"; }

# ============================================================================ 調べる
# タッチパネル: "デバイス|名前|安定したパス" を 1 行ずつ
list_touchscreens() {
    local dev name stable link
    for dev in /dev/input/event*; do
        [ -e "$dev" ] || continue
        udevadm info -q property -n "$dev" 2>/dev/null | grep -qx 'ID_INPUT_TOUCHSCREEN=1' || continue
        name="$(cat "/sys/class/input/$(basename "$dev")/device/name" 2>/dev/null || echo "?")"
        stable="$dev"
        for link in /dev/input/by-id/* /dev/input/by-path/*; do
            [ -e "$link" ] && [ "$(readlink -f "$link")" = "$dev" ] && { stable="$link"; break; }
        done
        echo "$dev|$name|$stable"
    done
}
# 音の機器: "カード番号|名前"
list_sound_cards() {
    [ -r /proc/asound/cards ] || return 0
    sed -n 's/^ *\([0-9]\+\) \[[^]]*\]: \(.*\)$/\1|\2/p' /proc/asound/cards
}
is_cfmx5() { grep -q '^CFMX5' /sys/class/dmi/id/product_name 2>/dev/null; }
polkit_new() {   # JavaScript のルール(rules.d)が使えるか(polkit 0.106 以上)
    local v; v="$(pkaction --version 2>/dev/null | grep -o '[0-9.]\+' | head -n 1)"
    [ -z "$v" ] && return 0
    [ "$(printf '%s\n0.106\n' "$v" | sort -V | head -n 1)" = 0.106 ]
}
desktop_running() { loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}' | while read -r s; do
    t="$(loginctl show-session "$s" -p Type --value 2>/dev/null)"; [ "$t" = x11 ] || [ "$t" = wayland ] && echo yes; done | grep -q yes; }

# ============================================================================ 入れる: パッケージ
PKGS_BUILD="build-essential cmake ninja-build pkg-config git
qt6-base-dev qt6-declarative-dev qt6-multimedia-dev qt6-qpa-plugins
qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts qml6-module-qtquick-window
qml6-module-qtquick-templates qml6-module-qtqml qml6-module-qtqml-workerscript qml6-module-qtmultimedia
qml6-module-qtquick-effects qml6-module-qt5compat-graphicaleffects qml6-module-qtquick-shapes
libavcodec-dev libavutil-dev libswscale-dev libdrm-dev libasound2-dev
libboost-system-dev libboost-log-dev libprotobuf-dev protobuf-compiler libusb-1.0-0-dev libssl-dev"
PKGS_RUN="fonts-noto-cjk alsa-utils v4l-utils pciutils power-profiles-daemon libinput-tools
polkitd pkexec udev whiptail"

do_packages() {
    step "パッケージ"
    info "パッケージの一覧を更新します"
    apt-get update -q || { ng "apt-get update に失敗しました(ネットワークを確認)"; return; }
    local want=() missing=() p
    for p in $PKGS_BUILD $PKGS_RUN; do
        if apt-cache show "$p" >/dev/null 2>&1; then want+=("$p"); else missing+=("$p"); fi
    done
    [ "${#missing[@]}" -gt 0 ] && info "この Debian に無いので飛ばします: ${missing[*]}"
    if DEBIAN_FRONTEND=noninteractive apt-get install -y "${want[@]}"; then
        ok "パッケージを入れました(${#want[@]} 個)"
    else
        ng "パッケージを入れられませんでした(上のエラーを確認)"
    fi
}

# ============================================================================ 入れる: ビルド
do_build() {
    step "ビルド"
    local args=(-G Ninja -S "$REPO" -B "$REPO/build" -DCMAKE_BUILD_TYPE=Release)
    [ "$ANS_AASDK" = no ] && args+=(-DOPENCRUISE_ENABLE_AASDK=OFF)
    # リポジトリの持ち主として(root のファイルを作らないように)ビルドする
    local owner; owner="$(stat -c %U "$REPO")"
    info "$owner としてビルドします(初回は aasdk を含むので数分〜十数分)"
    if sudo -u "$owner" cmake "${args[@]}" && sudo -u "$owner" ninja -C "$REPO/build"; then
        ok "ビルドしました: $APP"
    else
        ng "ビルドに失敗しました(上のエラーを確認)"
    fi
}

# ============================================================================ 入れる: 権限
do_groups() {
    local g added=()
    for g in $GROUPS_WANTED; do
        getent group "$g" >/dev/null || { info "グループ $g はこの OS に無いので飛ばします"; continue; }
        id -nG "$RUN_USER" | tr ' ' '\n' | grep -qx "$g" && continue
        usermod -aG "$g" "$RUN_USER" && added+=("$g")
    done
    [ "${#added[@]}" -gt 0 ] && state_set groups_added "$(echo "$(state_get groups_added) ${added[*]}" | xargs -n1 | sort -u | xargs)"
    ok "グループ: $(id -nG "$RUN_USER" | tr ' ' '\n' | grep -xE "$(echo $GROUPS_WANTED | tr ' ' '|')" | xargs)$([ "${#added[@]}" -gt 0 ] && echo "(足した: ${added[*]})")"
}
POWER_ACTIONS="org.freedesktop.login1.power-off org.freedesktop.login1.power-off-multiple-sessions
org.freedesktop.login1.power-off-ignore-inhibit org.freedesktop.login1.reboot
org.freedesktop.login1.reboot-multiple-sessions org.freedesktop.login1.reboot-ignore-inhibit
org.freedesktop.login1.halt org.freedesktop.login1.halt-multiple-sessions
net.hadess.PowerProfiles.switch-profile net.hadess.PowerProfiles.hold-profile
org.freedesktop.UPower.PowerProfiles.switch-profile org.freedesktop.UPower.PowerProfiles.hold-profile"
do_polkit() {
    if polkit_new; then
        mkdir -p "$(dirname "$POLKIT_RULE")"
        {
            echo "// OpenCruise(scripts/install.sh が作る): アプリのユーザーに、パスワードなしで"
            echo "// 電源を切る・再起動(ACC OFF の終了処理)と、電源モードの切り替え(設定 > 電源管理)を許可する"
            echo "polkit.addRule(function (action, subject) {"
            echo "    if (subject.user !== \"$RUN_USER\") return polkit.Result.NOT_HANDLED;"
            echo "    var allowed = [$(for a in $POWER_ACTIONS; do printf '\n        "%s",' "$a"; done | sed '$ s/,$//')"
            echo "    ];"
            echo "    return allowed.indexOf(action.id) >= 0 ? polkit.Result.YES : polkit.Result.NOT_HANDLED;"
            echo "});"
        } > "$POLKIT_RULE"
        chmod 0644 "$POLKIT_RULE"
        state_set polkit "$POLKIT_RULE"
    else
        mkdir -p "$(dirname "$POLKIT_PKLA")"
        cat > "$POLKIT_PKLA" <<EOF
# OpenCruise(scripts/install.sh が作る): 電源を切る・再起動と、電源モードの切り替えを許可する
[OpenCruise]
Identity=unix-user:$RUN_USER
Action=$(echo $POWER_ACTIONS | tr ' ' ';')
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF
        state_set polkit "$POLKIT_PKLA"
    fi
    systemctl try-reload-or-restart polkit.service 2>/dev/null || true
    ok "電源を切る・再起動・電源モードの切り替えを許可しました(polkit)"
}
do_backlight_permission() {
    cat > "$RULE_BACKLIGHT" <<'EOF'
# OpenCruise(scripts/install.sh が作る): バックライトの明るさを video グループから書けるようにする
# (アプリが /sys/class/backlight/*/brightness に直接書く。設定 > 表示 の明るさ・Ctrl+Shift+K / L)
SUBSYSTEM=="backlight", ACTION=="add", RUN+="/bin/chgrp video /sys%p/brightness", RUN+="/bin/chmod g+w /sys%p/brightness"
EOF
    state_set backlight_rule "$RULE_BACKLIGHT"
    local d n=0
    for d in /sys/class/backlight/*; do
        [ -e "$d/brightness" ] || continue
        chgrp video "$d/brightness" && chmod g+w "$d/brightness" && n=$((n + 1))
    done
    if [ "$n" -gt 0 ]; then ok "バックライトの明るさを書き込めるようにしました($n 個)"
    else ok "バックライトの規則を入れました(今はバックライトの機器が見つかりません。外部モニターだけのときは暗幕方式になります)"; fi
}
do_nosleep() {
    mkdir -p "$(dirname "$LOGIND_CONF")"
    cat > "$LOGIND_CONF" <<'EOF'
# OpenCruise(scripts/install.sh が作る): 車載 PC なので、蓋を閉じても・放っておいてもスリープしない
# (電源は ACC に合わせてアプリと外部マイコンが切る)
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
IdleAction=ignore
EOF
    state_set logind "$LOGIND_CONF"
    # shellcheck disable=SC2086
    systemctl mask $SLEEP_TARGETS >/dev/null 2>&1 && state_set sleep_masked yes
    ok "蓋を閉じても・放っておいてもスリープしないようにしました(蓋の設定は再起動から)"
}

# ============================================================================ 入れる: Android Auto(USB)
# スマホの主なメーカー(AOAP へ切り替える前)と Google(切り替えた後の 18d1)
USB_VENDORS="18d1 04e8 1004 22b8 0bb4 0fce 12d1 2717 2a70 22d9 0b05 17ef 19d2 04dd 0482 04c5 2e04 2d95 2ae5 05c6 1ebf 2916 0e8d 109b 2b4c 04da 0409"
do_usb() {
    step "Android Auto(USB)"
    {
        echo "# OpenCruise(scripts/install.sh が作る): Android Auto のスマホを、アプリ(aasdk)が USB で開けるようにする。"
        echo "# 権限が無いと aasdk はエラーを出さずに無視するので、「待機中」のまま進まない。"
        echo "# plugdev グループ + 画面の前のユーザー(uaccess)に読み書きを許可する。"
        if [ "$ANS_USB" = all ]; then
            echo "# すべての USB 機器(メーカーを問わない)"
            echo 'SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", MODE="0664", GROUP="plugdev", TAG+="uaccess"'
        else
            echo "# 18d1 = Google(AOAP に切り替えた後)。ほかは主なスマホのメーカー(切り替えの要求を送るために開く)"
            local v
            for v in $USB_VENDORS; do
                echo "SUBSYSTEM==\"usb\", ENV{DEVTYPE}==\"usb_device\", ATTR{idVendor}==\"$v\", MODE=\"0664\", GROUP=\"plugdev\", TAG+=\"uaccess\""
            done
        fi
    } > "$RULE_USB"
    state_set usb_rule "$RULE_USB"
    getent group plugdev >/dev/null || groupadd --system plugdev
    id -nG "$RUN_USER" | tr ' ' '\n' | grep -qx plugdev || { usermod -aG plugdev "$RUN_USER"; state_set groups_added "$(echo "$(state_get groups_added) plugdev" | xargs -n1 | sort -u | xargs)"; }
    udevadm control --reload-rules && udevadm trigger --subsystem-match=usb --action=change
    ok "スマホの USB を開けるようにしました($([ "$ANS_USB" = all ] && echo すべての USB 機器 || echo 主なメーカー))。挿してあるスマホは挿し直してください"
}

# ============================================================================ 入れる: タッチパネル
touch_matrix() {
    case "$1" in
        90) echo "0 -1 1 1 0 0" ;;
        180) echo "-1 0 1 0 -1 1" ;;
        270) echo "0 1 0 -1 0 1" ;;
        flipx) echo "-1 0 1 0 1 0" ;;
        flipy) echo "1 0 0 0 -1 1" ;;
        *) echo "" ;;
    esac
}
do_touch() {
    step "タッチパネル"
    if [ -z "$ANS_TOUCH_DEV" ]; then info "タッチパネルが見つからなかったので飛ばしました"; return; fi
    local name; name="$(cat "/sys/class/input/$(basename "$ANS_TOUCH_DEV")/device/name" 2>/dev/null || true)"
    local matrix; matrix="$(touch_matrix "$ANS_TOUCH_ROT")"
    if [ -n "$matrix" ]; then
        {
            echo "# OpenCruise(scripts/install.sh が作る): タッチパネルの向きの補正(libinput が読む)"
            echo "# 「$name」: $ANS_TOUCH_ROT"
            echo "ACTION==\"add|change\", SUBSYSTEM==\"input\", KERNEL==\"event*\", ENV{ID_INPUT_TOUCHSCREEN}==\"1\", ATTRS{name}==\"$name\", ENV{LIBINPUT_CALIBRATION_MATRIX}=\"$matrix\""
        } > "$RULE_TOUCH"
        state_set touch_rule "$RULE_TOUCH"
        udevadm control --reload-rules && udevadm trigger --subsystem-match=input --action=change
        ok "タッチパネル「$name」の向きを補正しました($ANS_TOUCH_ROT)。アプリの次の起動から効きます"
    else
        rm -f "$RULE_TOUCH"
        ok "タッチパネル「$name」はそのままの向きで使います(補正なし)"
    fi
    id -nG "$RUN_USER" | tr ' ' '\n' | grep -qx input || { usermod -aG input "$RUN_USER"; state_set groups_added "$(echo "$(state_get groups_added) input" | xargs -n1 | sort -u | xargs)"; }
}
touch_test() {   # 触って試す(10 秒)。画面に座標を出す
    local dev="$1"
    if ! command -v libinput >/dev/null 2>&1; then
        ui_msg "タッチを試す" "libinput-tools が入っていないので試せません(パッケージの手順で入ります)。"
        return
    fi
    clear 2>/dev/null || true
    echo "10 秒間、画面の 左上 → 右上 → 右下 → 左下 の順に触ってください。触った位置(画面の幅・高さに対する %)が出ます。"
    echo "左上で 横 0 / 縦 0 付近、右下で 横 100 / 縦 100 付近になれば向きは合っています。"
    # libinput debug-events の TOUCH_DOWN の行の「横/縦」(0〜100)を取り出す(補正の規則を入れた後なら、補正した位置)
    timeout 10 libinput debug-events --device "$dev" 2>/dev/null | grep --line-buffered 'TOUCH_DOWN' \
        | sed -u 's#/ *#/#g' \
        | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9.]+\/[0-9.]+$/) { split($i, a, "/"); printf "  触った: 横 %3.0f %%  縦 %3.0f %%\n", a[1], a[2]; fflush(); break } }' || true
    echo; read -r -p "Enter で戻る " _ </dev/tty
}

# ============================================================================ 入れる: 音
do_audio() {
    step "音"
    id -nG "$RUN_USER" | tr ' ' '\n' | grep -qx audio || { usermod -aG audio "$RUN_USER"; state_set groups_added "$(echo "$(state_get groups_added) audio" | xargs -n1 | sort -u | xargs)"; }
    if [ "$ANS_AUDIO_STOP" = yes ]; then
        # すべてのユーザーのサービスとして止める(アプリが ALSA の機器を直接使えるように)
        local u masked=()
        for u in $AUDIO_UNITS; do
            [ -n "$(systemctl --global list-unit-files "$u" --no-legend 2>/dev/null)" ] || [ -e "/usr/lib/systemd/user/$u" ] || continue
            systemctl --global mask "$u" >/dev/null 2>&1 && masked+=("$u")
        done
        # 今動いている分も止める
        systemctl --machine="$RUN_USER@.host" --user stop $AUDIO_UNITS >/dev/null 2>&1 || true
        if [ "${#masked[@]}" -gt 0 ]; then
            state_set audio_masked "${masked[*]}"
            ok "PipeWire / PulseAudio を止めました(${masked[*]})。アプリが ALSA の機器を直接使います"
        else
            ok "PipeWire / PulseAudio は入っていません(ALSA を直接使います)"
        fi
    fi
    ok "音のグループ(audio)に入れました"
}
audio_test() {   # 音を出して試す
    local card="$1"
    command -v speaker-test >/dev/null 2>&1 || { ui_msg "音を試す" "alsa-utils が入っていないので試せません。"; return; }
    clear 2>/dev/null || true
    echo "カード $card から、左右の順に「ピー」という音を出します(約 4 秒)。"
    sudo -u "$RUN_USER" timeout 6 speaker-test -D "plughw:$card" -c 2 -t sine -f 440 -l 1 -s 1 >/dev/null 2>&1
    sudo -u "$RUN_USER" timeout 6 speaker-test -D "plughw:$card" -c 2 -t sine -f 440 -l 1 -s 2 >/dev/null 2>&1
    local rc=$?
    [ "$rc" -ne 0 ] && echo "音を出せませんでした(機器を使っているほかのアプリが無いか、PipeWire / PulseAudio を止めたか確認してください)"
    read -r -p "Enter で戻る " _ </dev/tty
}

# ============================================================================ 入れる: 起動画面・自動起動 / CF-MX5
do_boot() {
    step "起動画面と自動起動"
    [ -x "$APP" ] || { ng "アプリがビルドされていません($APP)。ビルドしてからもう一度選んでください"; return; }
    local args=(--user "$RUN_USER" --app "$APP")
    [ "$ANS_BOOT_AUTOSTART" = no ] && args+=(--no-autostart)
    [ "$ANS_BOOT_GRUB" = no ] && args+=(--no-grub)
    [ "$ANS_BOOT_BACKLIGHT" = no ] && args+=(--no-backlight)
    if bash "$REPO/scripts/bootsplash/install.sh" "${args[@]}"; then
        state_set bootsplash yes
        ok "起動画面$([ "$ANS_BOOT_AUTOSTART" = yes ] && echo "と自動起動")を入れました"
    else
        ng "起動画面を入れられませんでした(上のエラーを確認)"
    fi
}
do_cfmx5() {
    step "CF-MX5: AC を挿したら起動する"
    if sh "$REPO/scripts/cf-mx5/install-afterg3.sh" install; then
        state_set cfmx5_afterg3 yes
        ok "AC を挿したら起動するようにしました(確認: poweroff → AC を抜いて 10 秒 → 挿す)"
    else
        ng "CF-MX5 の設定に失敗しました(上のエラーを確認)"
    fi
}

# ============================================================================ 確かめる(--check と、入れた後)
check_access() {   # check_access 説明 r|w|rw パス...(ユーザーとして試す)
    local what="$1" mode="$2"; shift 2
    local p any=0 bad=()
    for p in "$@"; do
        [ -e "$p" ] || continue
        any=1
        case "$mode" in
            r) sudo -u "$RUN_USER" test -r "$p" || bad+=("$p") ;;
            w) sudo -u "$RUN_USER" test -w "$p" || bad+=("$p") ;;
            rw) { sudo -u "$RUN_USER" test -r "$p" && sudo -u "$RUN_USER" test -w "$p"; } || bad+=("$p") ;;
        esac
    done
    if [ "$any" -eq 0 ]; then info "$what: 機器がありません(つないでいない)"
    elif [ "${#bad[@]}" -eq 0 ]; then ok "$what: 使えます"
    else ng "$what: 使えません(${bad[*]})"; fi
}
check_polkit() {   # check_polkit 説明 アクション
    local what="$1" action="$2"
    if ! pkaction --action-id "$action" >/dev/null 2>&1; then info "$what: この OS にありません($action)"; return; fi
    if sudo -u "$RUN_USER" sh -c "pkcheck --action-id '$action' --process \$\$ >/dev/null 2>&1"; then ok "$what: パスワードなしでできます"
    else ng "$what: パスワードが要ります(権限の「電源の操作」を入れてください)"; fi
}
do_check() {
    : > "$RESULTS"
    step "ユーザー: $RUN_USER"
    local g have; have=" $(id -nG "$RUN_USER") "
    for g in $GROUPS_WANTED; do
        getent group "$g" >/dev/null || continue
        case "$have" in *" $g "*) ok "グループ $g" ;; *) ng "グループ $g に入っていません" ;; esac
    done
    step "機器の権限(このユーザーとして試す。グループを足した直後は、ここでは使えるが、アプリは次の起動から)"
    check_access "画面(DRM)" rw /dev/dri/card*
    check_access "画面(描画)" rw /dev/dri/renderD*
    check_access "入力(タッチ・キーボード)" r /dev/input/event*
    check_access "音(ALSA)" rw /dev/snd/controlC* /dev/snd/pcm*
    check_access "カメラ(V4L2)" rw /dev/video*
    check_access "シリアル(外部マイコン)" rw /dev/ttyACM* /dev/ttyUSB*
    check_access "バックライト" w /sys/class/backlight/*/brightness
    step "電源の操作(polkit)"
    check_polkit "電源を切る" org.freedesktop.login1.power-off
    check_polkit "再起動" org.freedesktop.login1.reboot
    if pkaction --action-id org.freedesktop.UPower.PowerProfiles.switch-profile >/dev/null 2>&1; then
        check_polkit "電源モードの切り替え" org.freedesktop.UPower.PowerProfiles.switch-profile
    else
        check_polkit "電源モードの切り替え" net.hadess.PowerProfiles.switch-profile
    fi
    command -v powerprofilesctl >/dev/null 2>&1 || info "powerprofilesctl がありません(電源モードを使うなら power-profiles-daemon を入れる)"
    step "設定"
    [ -f "$RULE_USB" ] && ok "Android Auto の USB の規則($RULE_USB)" || ng "Android Auto の USB の規則がありません(スマホが「待機中」のまま進まない原因になります)"
    [ -f "$RULE_TOUCH" ] && ok "タッチパネルの向きの補正($RULE_TOUCH)" || info "タッチパネルの向きの補正: なし(そのままの向き)"
    if [ -f "$LOGIND_CONF" ]; then ok "蓋を閉じてもスリープしない($LOGIND_CONF)"; else info "蓋を閉じるとスリープします(権限の「スリープしない」で変えられます)"; fi
    local playing=""
    for u in pipewire.service pulseaudio.service; do
        [ "$(systemctl --global is-enabled "$u" 2>/dev/null)" = masked ] || [ -e "/usr/lib/systemd/user/$u" ] || continue
        [ "$(systemctl --global is-enabled "$u" 2>/dev/null)" = masked ] || playing="$playing ${u%.service}"
    done
    [ -z "$playing" ] && ok "PipeWire / PulseAudio は止まっています(ALSA を直接使えます)" || ng "止めていません:$playing(機器を先に使ってしまい、アプリが ALSA の機器を使えないことがあります)"
    step "アプリ"
    [ -x "$APP" ] && ok "アプリ: $APP" || ng "アプリがビルドされていません: $APP"
    if systemctl is-enabled opencruise.service >/dev/null 2>&1; then ok "自動起動: 有効(今: $(systemctl is-active opencruise.service 2>/dev/null))"
    else info "自動起動: 入っていません"; fi
    if is_cfmx5; then
        [ -f /etc/systemd/system/afterg3.service ] && ok "CF-MX5: AC を挿したら起動する" || info "CF-MX5: AC を挿しても起動しません(CF-MX5 の手順で入れられます)"
    fi
}

# ============================================================================ 外す
do_uninstall() {
    local items=() f
    [ -f "$RULE_USB" ] && items+=(usb "Android Auto の USB の規則" on)
    [ -f "$RULE_TOUCH" ] && items+=(touch "タッチパネルの向きの補正" on)
    [ -f "$RULE_BACKLIGHT" ] && items+=(backlight "バックライトの書き込みの規則" on)
    { [ -f "$POLKIT_RULE" ] || [ -f "$POLKIT_PKLA" ]; } && items+=(polkit "電源の操作の許可(polkit)" on)
    [ -f "$LOGIND_CONF" ] && items+=(nosleep "スリープしない設定" on)
    [ -n "$(state_get audio_masked)" ] && items+=(audio "止めた PipeWire / PulseAudio を戻す" on)
    { [ -f /etc/systemd/system/opencruise.service ] || [ -d /usr/share/plymouth/themes/opencruise ]; } && items+=(boot "起動画面と自動起動" on)
    [ -f /etc/systemd/system/afterg3.service ] && items+=(cfmx5 "CF-MX5: AC を挿したら起動する" off)
    [ -n "$(state_get groups_added)" ] && items+=(groups "足したグループから外す($(state_get groups_added))" off)
    if [ "${#items[@]}" -eq 0 ]; then ui_msg "外す" "このインストーラーが入れた設定はありません。"; exit 0; fi
    local picked; picked="$(ui_checklist "外す" "外すものを選んでください。" "${items[@]}")" || exit 0
    picked="$(echo "$picked" | xargs)"
    [ -n "$picked" ] || exit 0
    {
        sel usb "$picked" && { rm -f "$RULE_USB"; sed -i '/^usb_rule=/d' "$STATE" 2>/dev/null; ok "Android Auto の USB の規則を外しました"; }
        sel touch "$picked" && { rm -f "$RULE_TOUCH"; sed -i '/^touch_rule=/d' "$STATE" 2>/dev/null; ok "タッチパネルの補正を外しました"; }
        sel backlight "$picked" && { rm -f "$RULE_BACKLIGHT"; sed -i '/^backlight_rule=/d' "$STATE" 2>/dev/null; ok "バックライトの規則を外しました(再起動で元の権限に戻ります)"; }
        sel polkit "$picked" && { rm -f "$POLKIT_RULE" "$POLKIT_PKLA"; sed -i '/^polkit=/d' "$STATE" 2>/dev/null
                                  systemctl try-reload-or-restart polkit.service 2>/dev/null; ok "電源の操作の許可を外しました"; }
        if sel nosleep "$picked"; then
            rm -f "$LOGIND_CONF"; sed -i '/^logind=/d' "$STATE" 2>/dev/null
            # shellcheck disable=SC2086
            [ "$(state_get sleep_masked)" = yes ] && systemctl unmask $SLEEP_TARGETS >/dev/null 2>&1 && sed -i '/^sleep_masked=/d' "$STATE"
            ok "スリープしない設定を外しました(再起動から)"
        fi
        if sel audio "$picked"; then
            # shellcheck disable=SC2046
            systemctl --global unmask $(state_get audio_masked) >/dev/null 2>&1; sed -i '/^audio_masked=/d' "$STATE"
            ok "PipeWire / PulseAudio を戻しました(次のログインから)"
        fi
        sel boot "$picked" && { bash "$REPO/scripts/bootsplash/uninstall.sh" && sed -i '/^bootsplash=/d' "$STATE" 2>/dev/null; ok "起動画面と自動起動を外しました"; }
        sel cfmx5 "$picked" && { sh "$REPO/scripts/cf-mx5/install-afterg3.sh" uninstall && sed -i '/^cfmx5_afterg3=/d' "$STATE" 2>/dev/null; ok "CF-MX5 の自動起動を外しました"; }
        if sel groups "$picked"; then
            for f in $(state_get groups_added); do gpasswd -d "$RUN_USER" "$f" >/dev/null 2>&1; done
            sed -i '/^groups_added=/d' "$STATE"; ok "足したグループから外しました"
        fi
        udevadm control --reload-rules 2>/dev/null || true
    } 2>&1 | tee -a "$LOG"
    ui_msg "外す" "外しました。再起動すると、すべて元に戻ります。"
}

# ============================================================================ ここから
mkdir -p "$(dirname "$LOG")"
echo "===== $(date '+%F %T') $MODE (user: $RUN_USER) =====" >> "$LOG"

if [ "$MODE" = check ]; then
    do_check 2>&1 | tee -a "$LOG"
    grep -q '^NG|' "$RESULTS" && exit 1 || exit 0
fi
[ "$MODE" = uninstall ] && { do_uninstall; exit 0; }

# ---- 1. ようこそ ----
ui_msg "ようこそ" "OpenCruise を、この PC で動かすための設定をまとめて入れます。\n\n\
  アプリを動かすユーザー: $RUN_USER\n  リポジトリ: $REPO\n\n\
このあと、入れるものを選び、いくつか質問に答えると、最後にまとめて入れます。\n\
途中でやめても、何も変わりません(入れるのは最後の確認のあと)。\n\
外すときは: sudo scripts/install.sh --uninstall" || exit 0

# ---- 2. 入れるものを選ぶ ----
APP_STATE="$([ -x "$APP" ] && echo "ビルド済み" || echo "まだ")"
ITEMS=(
    packages "パッケージ(ビルド・実行に要るもの)" on
    build    "アプリをビルドする(今: $APP_STATE)" "$([ -x "$APP" ] && echo off || echo on)"
    perm     "権限(グループ・電源の操作・明るさ・スリープしない)" on
    usb      "Android Auto のスマホを USB で使う権限" on
    touch    "タッチパネル(向きの補正・試す)" on
    audio    "音(ALSA を直接使う・試す)" on
    boot     "起動画面と自動起動" on
)
is_cfmx5 && ITEMS+=(cfmx5 "CF-MX5: AC を挿したら起動する" on)
SELECTED="$(ui_checklist "入れるもの" "入れるものを選んでください。とくに「権限」は、アプリの多くの機能に要ります。" "${ITEMS[@]}" | xargs)" || exit 0
[ -n "$SELECTED" ] || { echo "何も選ばれなかったので終わります"; exit 0; }

# ---- 3. 質問 ----
ANS_AASDK=yes
if has build; then
    ui_yesno "ビルド" "Android Auto の接続(aasdk)もビルドしますか?\n\nいいえ にすると画面だけのビルドになり、早く終わります(Android Auto は使えません)。" yes || ANS_AASDK=no
fi

PERM_ITEMS=""
if has perm; then
    PERM_ITEMS="$(ui_checklist "権限" "入れる権限を選んでください(どれもおすすめです)。" \
        groups "グループ: 画面・入力・音・カメラ・USB・シリアル($GROUPS_WANTED)" on \
        power "電源の操作: 電源を切る・再起動・電源モードをパスワードなしで(polkit)" on \
        backlight "画面の明るさ: バックライトに直接書き込める(udev)" on \
        nosleep "スリープしない: 蓋を閉じても・放っておいても(車載 PC 向け)" on | xargs)" || exit 0
fi

ANS_USB=vendors
if has usb; then
    ANS_USB="$(ui_menu "Android Auto(USB)" "どの USB 機器を開けるようにしますか?\n\
アプリ(aasdk)は、権限が無いスマホをエラーを出さずに無視するので、ここが無いと「待機中」のまま進みません。" vendors \
        vendors "主なスマホのメーカーだけ(Google・Samsung・Sony・Sharp・Xiaomi など。おすすめ)" \
        all "すべての USB 機器(メーカーが一覧に無いスマホでもつながる)")" || exit 0
fi

ANS_TOUCH_DEV=""; ANS_TOUCH_ROT=none
if has touch; then
    mapfile -t TOUCHES < <(list_touchscreens)
    if [ "${#TOUCHES[@]}" -eq 0 ]; then
        ui_msg "タッチパネル" "タッチパネルが見つかりませんでした(USB のタッチパネルなら、つないでからもう一度実行してください)。\n\nタッチパネルの手順は飛ばします。"
    else
        if [ "${#TOUCHES[@]}" -eq 1 ]; then
            ANS_TOUCH_DEV="${TOUCHES[0]%%|*}"
        else
            args=(); for t in "${TOUCHES[@]}"; do IFS='|' read -r d n _ <<<"$t"; args+=("$d" "$n"); done
            ANS_TOUCH_DEV="$(ui_menu "タッチパネル" "使うタッチパネルを選んでください。" "${TOUCHES[0]%%|*}" "${args[@]}")" || exit 0
        fi
        TNAME="$(cat "/sys/class/input/$(basename "$ANS_TOUCH_DEV")/device/name" 2>/dev/null)"
        while :; do
            ANS_TOUCH_ROT="$(ui_menu "タッチパネル" "タッチパネル「$TNAME」($ANS_TOUCH_DEV)\n\n\
触った位置と画面の位置がずれる(回転・反転している)ときは、向きを選んでください。\n\
分からないときは「触って試す」で確かめられます。" none \
                none "そのまま(補正しない)" \
                90 "時計回りに 90° 回す" \
                180 "180° 回す(上下左右が逆)" \
                270 "反時計回りに 90° 回す" \
                flipx "左右を反転" \
                flipy "上下を反転" \
                test "触って試す(10 秒)")" || exit 0
            [ "$ANS_TOUCH_ROT" = test ] && { touch_test "$ANS_TOUCH_DEV"; continue; }
            break
        done
    fi
fi

ANS_AUDIO_STOP=no
if has audio; then
    AUDIO_FOUND=""
    for u in $AUDIO_UNITS; do [ -e "/usr/lib/systemd/user/$u" ] && AUDIO_FOUND="$AUDIO_FOUND ${u%%.*}"; done
    AUDIO_FOUND="$(echo "$AUDIO_FOUND" | xargs -n1 2>/dev/null | sort -u | xargs)"
    if [ -n "$AUDIO_FOUND" ]; then
        ui_yesno "音" "アプリは音を ALSA の機器へ直接出します(アプリの中の音はアプリの中で混ぜます)。\n\n\
この PC には $AUDIO_FOUND が入っていて、機器を先に使ってしまうことがあります\n\
(出力先の一覧に機器が出ない・音が出ない原因になります)。\n\n\
止めますか?(すべてのユーザーで止まります。--uninstall で戻せます)" yes && ANS_AUDIO_STOP=yes
    fi
    mapfile -t CARDS < <(list_sound_cards)
    if [ "${#CARDS[@]}" -gt 0 ] && [ "$ASSUME_YES" -eq 0 ]; then
        while :; do
            args=(); for c in "${CARDS[@]}"; do args+=("${c%%|*}" "${c#*|}"); done
            pick="$(ui_menu "音を試す" "音を出して試しますか?(PipeWire などを止める前は、出ないことがあります)" skip \
                skip "試さずに次へ" "${args[@]}")" || break
            [ "$pick" = skip ] && break
            audio_test "$pick"
        done
    fi
fi

ANS_BOOT_AUTOSTART=yes; ANS_BOOT_GRUB=yes; ANS_BOOT_BACKLIGHT=yes
if has boot; then
    BOOT_OPTS="$(ui_checklist "起動画面と自動起動" "電源を入れてからアプリの画面までを、アプリの起動画面と同じ見た目でつなぎます。" \
        autostart "アプリを自動起動する(tty1。ログイン画面は出さない)" on \
        grub "起動中のメッセージを隠す(GRUB の設定を変える)" on \
        backlight "起動中は画面を最大の明るさにする" on | xargs)" || exit 0
    sel autostart "$BOOT_OPTS" || ANS_BOOT_AUTOSTART=no
    sel grub "$BOOT_OPTS" || ANS_BOOT_GRUB=no
    sel backlight "$BOOT_OPTS" || ANS_BOOT_BACKLIGHT=no
    if desktop_running; then
        ui_msg "起動画面と自動起動" "デスクトップ(X11 / Wayland)が動いています。\n\
起動画面の画像はアプリで画面に描いて作るので、デスクトップが画面を使っていると失敗します。\n\
失敗したときは、SSH からもう一度実行してください。"
    fi
fi

# ---- 4. 確認 ----
SUMMARY=""
has packages && SUMMARY+="・パッケージを入れる\n"
has build && SUMMARY+="・ビルドする($([ "$ANS_AASDK" = yes ] && echo "Android Auto を含む" || echo "画面だけ"))\n"
if has perm; then
    sel groups "$PERM_ITEMS" && SUMMARY+="・グループに追加: $GROUPS_WANTED\n"
    sel power "$PERM_ITEMS" && SUMMARY+="・電源を切る・再起動・電源モードを許可(polkit)\n"
    sel backlight "$PERM_ITEMS" && SUMMARY+="・バックライトに書き込めるようにする\n"
    sel nosleep "$PERM_ITEMS" && SUMMARY+="・スリープしないようにする\n"
fi
has usb && SUMMARY+="・スマホの USB を開けるようにする($([ "$ANS_USB" = all ] && echo すべての USB 機器 || echo 主なメーカー))\n"
has touch && [ -n "$ANS_TOUCH_DEV" ] && SUMMARY+="・タッチパネル: $([ "$ANS_TOUCH_ROT" = none ] && echo "補正しない" || echo "向きの補正 $ANS_TOUCH_ROT")\n"
has audio && SUMMARY+="・音: audio グループ$([ "$ANS_AUDIO_STOP" = yes ] && echo "、PipeWire / PulseAudio を止める")\n"
has boot && SUMMARY+="・起動画面$(sel autostart "$BOOT_OPTS" && echo "・自動起動")$(sel grub "$BOOT_OPTS" && echo "・メッセージを隠す")$(sel backlight "$BOOT_OPTS" && echo "・起動中は最大の明るさ")\n"
has cfmx5 && SUMMARY+="・CF-MX5: AC を挿したら起動する\n"
ui_yesno "確認" "次のものを入れます。よろしいですか?\n\n$SUMMARY" yes || { echo "やめました(何も変えていません)"; exit 0; }

# ---- 5. 入れる ----
: > "$RESULTS"
{
    has packages && do_packages
    has build && do_build
    if has perm; then
        step "権限"
        sel groups "$PERM_ITEMS" && do_groups
        sel power "$PERM_ITEMS" && do_polkit
        sel backlight "$PERM_ITEMS" && { udevadm control --reload-rules 2>/dev/null; do_backlight_permission; }
        sel nosleep "$PERM_ITEMS" && do_nosleep
    fi
    has usb && do_usb
    has touch && do_touch
    has audio && do_audio
    has boot && do_boot
    has cfmx5 && do_cfmx5
    cp "$RESULTS" "$RESULTS.install"
    echo
    echo "================ 確かめる ================"
    do_check
} 2>&1 | tee -a "$LOG"

# ---- 6. 終わり ----
# 入れるときに失敗したもの / 入れた後の確認で、まだ使えないもの(選ばなかった項目の分も出る)
NG_LIST="$(grep '^NG|' "$RESULTS.install" 2>/dev/null | cut -d'|' -f2- | sed 's/^/・/')"
CHECK_NG="$(grep '^NG|' "$RESULTS" | cut -d'|' -f2- | sed 's/^/・/')"
rm -f "$RESULTS.install"
if [ -n "$NG_LIST" ]; then
    ui_msg "終わり(うまくいかなかったものがあります)" "次のものを確かめてください(詳しくは $LOG):\n\n$NG_LIST\n\n\
グループは、次にログインしたとき(自動起動ならアプリの次の起動・再起動のあと)から効きます。"
else
    ui_msg "終わり" "選んだものをすべて入れました(記録: $LOG)。\n\n\
グループ・タッチパネル・スリープの設定は、再起動すると確実に効きます。\n\
あとで状態を確かめるときは: sudo scripts/install.sh --check"
fi
[ -n "$CHECK_NG" ] && ui_msg "まだ使えないもの" "確認で、次のものがまだ使えません(選ばなかった項目の分も含みます):\n\n$CHECK_NG"
if [ "$ASSUME_YES" -eq 0 ] && ui_yesno "再起動" "今すぐ再起動しますか?" no; then
    systemctl reboot
fi
exit 0
