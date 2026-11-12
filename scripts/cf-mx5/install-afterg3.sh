#!/bin/sh
# CF-MX5: AC 投入で自動起動させる systemd サービス(afterg3.service)の入れ外し。
# PMC (00:1f.2) の GEN_PMCON_B (0xA4) bit0 = AFTERG3_EN を、起動時とシャットダウン時に 0 にする。
#
#   sudo scripts/cf-mx5/install-afterg3.sh install    # 入れる(自動起動 ON)
#   sudo scripts/cf-mx5/install-afterg3.sh uninstall  # 外す(自動起動 OFF に戻す)
#   sudo scripts/cf-mx5/install-afterg3.sh status     # 状態を見る
set -eu

UNIT=afterg3.service
UNIT_PATH=/etc/systemd/system/$UNIT
PMC=00:1f.2
PMC_ID=9d218086   # 8086:9d21 Sunrise Point-LP PMC

die() { echo "エラー: $*" >&2; exit 1; }

usage() {
    echo "使い方: sudo $0 {install|uninstall|status}" >&2
    exit 2
}

need_root() { [ "$(id -u)" -eq 0 ] || die "sudo で実行してください"; }

need_setpci() {
    SETPCI=$(command -v setpci) || die "setpci がありません(sudo apt install pciutils)"
}

check_pmc() {
    ID=$(setpci -s "$PMC" 0x00.l 2>/dev/null) || die "$PMC が見つかりません"
    [ "$ID" = "$PMC_ID" ] || die "$PMC が想定の PMC (8086:9d21) ではありません(読み取り値: $ID)"
}

read_reg() { setpci -s "$PMC" 0xa4.b; }

# $1 = 0(AC 投入で起動) / 1(起動しない)
write_bit0() {
    "$SETPCI" -s "$PMC" 0xa4.b=0x0$1:0x01 \
        || die "書き込みに失敗しました(cat /sys/kernel/security/lockdown を確認)"
    [ $((0x$(read_reg) & 1)) -eq "$1" ] || die "bit0 が $1 になりません(読み取り値: $(read_reg))"
}

describe() {
    if [ $((0x$1 & 1)) -eq 0 ]; then echo "AC 投入で起動する"; else echo "AC 投入では起動しない"; fi
}

cmd_install() {
    need_root; need_setpci; check_pmc
    BEFORE=$(read_reg)
    write_bit0 0
    AFTER=$(read_reg)

    cat > "$UNIT_PATH" <<EOF
[Unit]
Description=Power on after AC restore (CF-MX5, AFTERG3_EN=0)

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$SETPCI -s $PMC 0xa4.b=0x00:0x01
ExecStop=$SETPCI -s $PMC 0xa4.b=0x00:0x01

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now "$UNIT"

    echo "GEN_PMCON_B: 0x$BEFORE → 0x$AFTER($(describe "$AFTER"))"
    echo "$UNIT を入れました。確認: sudo poweroff → AC を抜いて 10 秒 → 挿す"
}

cmd_uninstall() {
    need_root; need_setpci; check_pmc
    if [ -e "$UNIT_PATH" ]; then
        # 先に止めないと ExecStop が bit0 を 0 に書き戻してしまう
        systemctl disable "$UNIT" 2>/dev/null || true
        systemctl stop "$UNIT" 2>/dev/null || true
        rm -f "$UNIT_PATH"
        systemctl daemon-reload
        echo "$UNIT を外しました"
    else
        echo "$UNIT は入っていません"
    fi
    write_bit0 1
    echo "GEN_PMCON_B: 0x$(read_reg)($(describe "$(read_reg)"))"
}

cmd_status() {
    if [ -e "$UNIT_PATH" ]; then
        echo "$UNIT: 入っている($(systemctl is-enabled "$UNIT" 2>/dev/null || echo 不明) / $(systemctl is-active "$UNIT" 2>/dev/null || echo 不明))"
    else
        echo "$UNIT: 入っていない"
    fi
    if command -v setpci >/dev/null && REG=$(setpci -s "$PMC" 0xa4.b 2>/dev/null); then
        echo "GEN_PMCON_B: 0x$REG($(describe "$REG"))"
    else
        echo "GEN_PMCON_B: 読めません(sudo で実行してください)"
    fi
}

case "${1:-}" in
    install) cmd_install ;;
    uninstall) cmd_uninstall ;;
    status) cmd_status ;;
    *) usage ;;
esac
