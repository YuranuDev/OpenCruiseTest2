#!/bin/bash
# install.sh の設定を元に戻す。sudo で実行する。
#   sudo scripts/bootsplash/uninstall.sh
set -euo pipefail
say() { echo "[opencruise-bootsplash] $*"; }
[ "$(id -u)" -eq 0 ] || { echo "sudo で実行してください" >&2; exit 1; }

say "自動起動を外します"
systemctl disable --now opencruise.service opencruise-splash-fallback.timer 2>/dev/null || true
rm -f /etc/systemd/system/opencruise.service /etc/systemd/system/opencruise-splash-fallback.service \
      /etc/systemd/system/opencruise-splash-fallback.timer
systemctl unmask plymouth-quit.service 2>/dev/null || true
systemctl enable getty@tty1.service 2>/dev/null || true
systemctl daemon-reload

if [ -f /etc/default/grub.opencruise-backup ]; then
    say "GRUB の設定を戻します"
    cp /etc/default/grub.opencruise-backup /etc/default/grub
    rm -f /etc/default/grub.opencruise-backup
    update-grub
fi

REBUILD_INITRAMFS=0
if [ -f /etc/udev/rules.d/90-opencruise-backlight.rules ] || [ -f /etc/initramfs-tools/hooks/opencruise-backlight ] \
   || [ -f /etc/systemd/system/systemd-backlight@.service.d/opencruise.conf ]; then
    say "起動時にバックライトを最大にする設定を外します"
    rm -f /etc/udev/rules.d/90-opencruise-backlight.rules /etc/initramfs-tools/hooks/opencruise-backlight
    rm -f /etc/systemd/system/systemd-backlight@.service.d/opencruise.conf
    rmdir /etc/systemd/system/systemd-backlight@.service.d 2>/dev/null || true
    systemctl daemon-reload
    REBUILD_INITRAMFS=1
fi

if [ -d /usr/share/plymouth/themes/opencruise ]; then
    say "起動画面のテーマを外します(Debian の既定に戻します)"
    plymouth-set-default-theme -r 2>/dev/null || plymouth-set-default-theme text 2>/dev/null || true
    rm -rf /usr/share/plymouth/themes/opencruise
    REBUILD_INITRAMFS=1
fi
[ "$REBUILD_INITRAMFS" -eq 1 ] && update-initramfs -u
say "完了しました(/etc/initramfs-tools/modules に足した画面のドライバーはそのままです)"
