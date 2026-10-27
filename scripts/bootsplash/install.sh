#!/bin/bash
# OpenCruise を Linux の起動画面から途切れずに起動するための設定(Debian 系)。sudo で実行する。
#
#   sudo scripts/bootsplash/install.sh [オプション]
#
# 行うこと:
#  1. Plymouth(起動画面)を入れ、アプリの起動画面と同じ見た目のテーマ「opencruise」を作って使う
#     (画像はアプリの --export-splash で、この PC の画面の大きさと、起動画面の固定配色(Theme.qml の boot*)で書き出す)
#  2. 起動時のメッセージを抑える(GRUB のメニューを隠し、カーネルの引数に quiet splash loglevel=3 など)
#  2b. 起動中の画面が暗くならないよう、バックライトを起動時に最大にする(udev のルール + systemd-backlight の復元を止める)
#  3. アプリを tty1 で自動起動する systemd サービス(opencruise.service)を入れる(--no-autostart で行わない)
#     アプリは起動時に Plymouth を消さずに終わらせて画面を引き継ぐので、起動画面がそのままアプリの起動画面になる
#
# オプション:
#  --user <名前>       アプリを動かすユーザー(既定: sudo したユーザー)
#  --app <パス>        アプリの実行ファイル(既定: リポジトリの build/app/opencruise)
#  --touch <デバイス>  タッチパネル(QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS。例: /dev/input/event1)
#  --image-dir <dir>   書き出し済みの画像(--export-splash の出力)を使う(アプリでの書き出しを飛ばす)
#  --no-autostart      自動起動を入れない(起動画面とメッセージの抑制だけ)
#  --no-grub           GRUB の設定を変えない
#  --no-backlight      起動時にバックライトを最大にする設定を入れない
#
# 元に戻す: sudo scripts/bootsplash/uninstall.sh
# アプリの起動画面のレイアウトや固定配色(Theme.qml の boot*)を変えたら、もう一度実行すると画像を作り直す。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
THEME_DIR=/usr/share/plymouth/themes/opencruise
SERVICE=/etc/systemd/system/opencruise.service

RUN_USER="${SUDO_USER:-}"
APP="$REPO/build/app/opencruise"
TOUCH=""
IMAGE_DIR=""
AUTOSTART=1
GRUB=1
BACKLIGHT=1

while [ $# -gt 0 ]; do
    case "$1" in
        --user) RUN_USER="$2"; shift 2 ;;
        --app) APP="$2"; shift 2 ;;
        --touch) TOUCH="$2"; shift 2 ;;
        --image-dir) IMAGE_DIR="$2"; shift 2 ;;
        --no-autostart) AUTOSTART=0; shift ;;
        --no-grub) GRUB=0; shift ;;
        --no-backlight) BACKLIGHT=0; shift ;;
        -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
        *) echo "不明なオプション: $1" >&2; exit 2 ;;
    esac
done

say() { echo "[opencruise-bootsplash] $*"; }
die() { echo "[opencruise-bootsplash] エラー: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "sudo で実行してください"
[ -n "$RUN_USER" ] || die "--user でアプリを動かすユーザーを指定してください"
id "$RUN_USER" >/dev/null 2>&1 || die "ユーザーがいません: $RUN_USER"
APP="$(readlink -f "$APP")"
[ -x "$APP" ] || die "アプリの実行ファイルがありません: $APP (先にビルドするか --app で指定)"

# ---- 1. Plymouth ----
if ! command -v plymouth-set-default-theme >/dev/null 2>&1 || ! ls /usr/lib/*/plymouth/script.so >/dev/null 2>&1; then
    say "Plymouth を入れます"
    apt-get install -y plymouth plymouth-themes
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
if [ -n "$IMAGE_DIR" ]; then
    cp "$IMAGE_DIR"/background.png "$IMAGE_DIR"/progress-fill.png "$IMAGE_DIR"/splash.conf "$WORK"/
else
    say "アプリの起動画面を書き出します(数秒、画面にアプリの起動画面が出ます)"
    # 自動起動中のアプリが画面を使っていると書き出せないので、止めておく(最後に入れ直す)
    systemctl stop opencruise.service 2>/dev/null || true
    chown "$RUN_USER" "$WORK"
    RUN_UID="$(id -u "$RUN_USER")"
    if ! sudo -u "$RUN_USER" env QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-eglfs}" XDG_RUNTIME_DIR="/run/user/$RUN_UID" \
            OPENCRUISE_SPLASH_HANDOFF=0 "$APP" --export-splash "$WORK" >"$WORK/export.log" 2>&1; then
        tail -n 20 "$WORK/export.log" >&2
        die "起動画面を書き出せませんでした(ほかのアプリが画面を使っていないか確認してください)"
    fi
fi
[ -s "$WORK/background.png" ] && [ -s "$WORK/splash.conf" ] || die "書き出した画像が見つかりません"

# splash.conf(key=value)を読む
declare -A CONF
while IFS='=' read -r key value; do
    [ -n "$key" ] && CONF["$key"]="$value"
done < "$WORK/splash.conf"
for key in width height bar_x bar_y bar_w bar_h background_rgb text_rgb; do
    [ -n "${CONF[$key]:-}" ] || die "splash.conf に $key がありません"
done
comma() { echo "$1" | sed 's/ \+/, /g'; }

say "テーマを作ります: $THEME_DIR (${CONF[width]} x ${CONF[height]})"
mkdir -p "$THEME_DIR"
install -m 0644 "$WORK/background.png" "$WORK/progress-fill.png" "$THEME_DIR"/
sed -e "s|@THEME_DIR@|$THEME_DIR|g" "$HERE/opencruise.plymouth.in" > "$THEME_DIR/opencruise.plymouth"
sed -e "s|@WIDTH@|${CONF[width]}|g" -e "s|@HEIGHT@|${CONF[height]}|g" \
    -e "s|@BAR_X@|${CONF[bar_x]}|g" -e "s|@BAR_Y@|${CONF[bar_y]}|g" \
    -e "s|@BAR_W@|${CONF[bar_w]}|g" -e "s|@BAR_H@|${CONF[bar_h]}|g" \
    -e "s|@BG_RGB_COMMA@|$(comma "${CONF[background_rgb]}")|g" \
    -e "s|@TEXT_RGB_COMMA@|$(comma "${CONF[text_rgb]}")|g" \
    "$HERE/opencruise.script.in" > "$THEME_DIR/opencruise.script"

# 画面のドライバーを早めに読み込む(Plymouth が最初から本来の解像度で出せるように。切り替えのちらつきを防ぐ)
DRM_DRIVER="$(basename "$(readlink -f /sys/class/drm/card0/device/driver 2>/dev/null)" 2>/dev/null || true)"
case "$DRM_DRIVER" in
    i915|amdgpu|radeon|nouveau)
        if ! grep -qx "$DRM_DRIVER" /etc/initramfs-tools/modules 2>/dev/null; then
            say "起動の初めから $DRM_DRIVER を読み込むようにします"
            echo "$DRM_DRIVER" >> /etc/initramfs-tools/modules
        fi ;;
esac

# 起動中(アプリが保存済みの明るさを書き込むまで)の画面を最大の明るさにする。
# - udev のルール: バックライトの機器が現れたときに最大にする(initramfs の中でも動くようフックで入れる)
# - systemd-backlight: 前回終了時の(暗い)明るさを起動のたびに復元するので止める。明るさの保存と復元はアプリが行う
if [ "$BACKLIGHT" -eq 1 ]; then
    say "起動時にバックライトを最大にする設定を入れます"
    install -m 0644 "$HERE/90-opencruise-backlight.rules" /etc/udev/rules.d/90-opencruise-backlight.rules
    mkdir -p /etc/initramfs-tools/hooks
    install -m 0755 "$HERE/opencruise-backlight.hook" /etc/initramfs-tools/hooks/opencruise-backlight
    mkdir -p /etc/systemd/system/systemd-backlight@.service.d
    install -m 0644 "$HERE/systemd-backlight-opencruise.conf" /etc/systemd/system/systemd-backlight@.service.d/opencruise.conf
    systemctl daemon-reload
    # 今すぐも最大にする(再起動を待たない。アプリが動いていれば、アプリが保存済みの明るさに戻す)
    for dir in /sys/class/backlight/*; do
        [ -r "$dir/max_brightness" ] && cat "$dir/max_brightness" > "$dir/brightness" 2>/dev/null || true
    done
fi

say "テーマを有効にします(initramfs を作り直すので少し時間がかかります)"
plymouth-set-default-theme opencruise
update-initramfs -u

# ---- 2. 起動時のメッセージを抑える ----
if [ "$GRUB" -eq 1 ] && [ -f /etc/default/grub ]; then
    [ -f /etc/default/grub.opencruise-backup ] || cp /etc/default/grub /etc/default/grub.opencruise-backup
    say "GRUB の設定を変えます(元の設定: /etc/default/grub.opencruise-backup)"
    python3 - /etc/default/grub <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
# カーネルの引数: 足りないものだけ足す(ほかの引数はそのまま)
want = ["quiet", "splash", "loglevel=3", "rd.udev.log_level=3", "vt.global_cursor_default=0",
        "systemd.show_status=auto", "rd.systemd.show_status=auto"]
m = re.search(r'^GRUB_CMDLINE_LINUX_DEFAULT="([^"]*)"', text, re.M)
args = m.group(1).split() if m else []
keys = {a.split("=")[0] for a in args}
for w in want:
    if w.split("=")[0] not in keys:
        args.append(w)
line = 'GRUB_CMDLINE_LINUX_DEFAULT="%s"' % " ".join(args)
text = re.sub(r'^GRUB_CMDLINE_LINUX_DEFAULT=.*$', line, text, flags=re.M) if m else text + "\n" + line + "\n"
# メニューは隠す(起動中に Esc か Shift を押すと出る)。GRUB の画面の解像度をそのまま使う(切り替えのちらつきを防ぐ)
def setvar(text, key, value):
    pat = re.compile(r'^#?\s*%s=.*$' % key, re.M)
    return pat.sub('%s=%s' % (key, value), text, count=1) if pat.search(text) else text + "%s=%s\n" % (key, value)
text = setvar(text, "GRUB_TIMEOUT_STYLE", "hidden")
text = setvar(text, "GRUB_TIMEOUT", "1")
text = setvar(text, "GRUB_GFXPAYLOAD_LINUX", "keep")
open(path, "w").write(text)
PY
    update-grub
fi

# ---- 3. 自動起動 ----
if [ "$AUTOSTART" -eq 1 ]; then
    say "自動起動のサービスを入れます: $SERVICE (ユーザー: $RUN_USER)"
    TOUCH_ENV=""
    [ -n "$TOUCH" ] && TOUCH_ENV="Environment=QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS=$TOUCH"
    sed -e "s|@USER@|$RUN_USER|g" -e "s|@UID@|$(id -u "$RUN_USER")|g" -e "s|@APP@|$APP|g" -e "s|@WORKDIR@|$REPO|g" -e "s|@TOUCH_ENV@|$TOUCH_ENV|g" \
        "$HERE/opencruise.service.in" > "$SERVICE"
    install -m 0644 "$HERE/opencruise-splash-fallback.service" /etc/systemd/system/
    install -m 0644 "$HERE/opencruise-splash-fallback.timer" /etc/systemd/system/
    systemctl daemon-reload
    # 起動画面はアプリが引き継いで消すので、起動の終わりに自動で消す処理は止める(消すと一瞬コンソールが見える)。
    # アプリが起動できなかったときは、opencruise-splash-fallback.timer が少し後に消す
    systemctl mask plymouth-quit.service
    # tty1 のログイン画面は出さない(アプリが tty1 を使う)。ほかの画面(Ctrl+Alt+F2 など)と SSH は今まで通り
    systemctl disable getty@tty1.service 2>/dev/null || true
    systemctl enable opencruise.service opencruise-splash-fallback.timer
fi

say "完了しました。再起動すると反映されます"
[ "$AUTOSTART" -eq 1 ] && say "アプリを手で起動するときは、先に: sudo systemctl stop opencruise"
exit 0
