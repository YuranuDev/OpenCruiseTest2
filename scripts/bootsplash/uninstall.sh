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

if [ -d /usr/share/plymouth/themes/opencruise ]; then
    say "起動画面のテーマを外します(Debian の既定に戻します)"
    plymouth-set-default-theme -r 2>/dev/null || plymouth-set-default-theme text 2>/dev/null || true
    rm -rf /usr/share/plymouth/themes/opencruise
    update-initramfs -u
fi
say "完了しました(/etc/initramfs-tools/modules に足した画面のドライバーはそのままです)"
