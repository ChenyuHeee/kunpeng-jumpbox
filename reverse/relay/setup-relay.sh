#!/usr/bin/env bash
# kunpeng-jumpbox reverse mode - relay setup
#
# Run as root on 114.55.135.102:
#   ssh hcy 'bash -s' < reverse/relay/setup-relay.sh
#
# It creates a no-shell user with a restricted key that can only bind
# 127.0.0.1:2222 and 127.0.0.1:13389. It does not touch sshd_config.
# Remove with: userdel -r kunpeng-tunnel

set -euo pipefail

TUNNEL_USER="${TUNNEL_USER:-kunpeng-tunnel}"
PORTS="${PORTS:-2222 13389}"
KEYID="kunpeng-jumpbox"

# Public key committed in reverse/keys/tunnel_key.pub. Safe to embed.
PUBKEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKkMR1dZYLZgXywcygetiYxZR+U6A2y41wyP/O/Y1yh1 kunpeng-jumpbox'
# Fingerprint of the relay's ED25519 host key (pinned in reverse/config/known_hosts).
EXPECTED_FP='SHA256:qMMh0rrquyw2egLg3rckRCjBlpkDo18iisNu0hhtY0g'

if [ "$(id -u)" -ne 0 ]; then
    echo "请用 root 运行：ssh hcy 'bash -s' < reverse/relay/setup-relay.sh" >&2
    exit 1
fi

if ! id "$TUNNEL_USER" >/dev/null 2>&1; then
    NOLOGIN="$(command -v nologin || echo /usr/sbin/nologin)"
    useradd --user-group --create-home --shell "$NOLOGIN" \
        --comment "Kunpeng jumpbox tunnel (SSH port forwarding only)" "$TUNNEL_USER"
    echo "[+] 已创建用户 $TUNNEL_USER（无登录 shell）"
else
    echo "[+] 用户 $TUNNEL_USER 已存在，更新 key"
fi

HOME_DIR="$(getent passwd "$TUNNEL_USER" | cut -d: -f6)"
GROUP="$(id -gn "$TUNNEL_USER")"
if [ -z "$HOME_DIR" ]; then
    echo "无法获取 $TUNNEL_USER 的家目录" >&2
    exit 1
fi

install -d -m 0700 -o "$TUNNEL_USER" -g "$GROUP" "$HOME_DIR/.ssh"

RESTRICT="restrict,port-forwarding"
for p in $PORTS; do
    RESTRICT="$RESTRICT,permitlisten=\"127.0.0.1:$p\""
done

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
if [ -f "$HOME_DIR/.ssh/authorized_keys" ]; then
    grep -v "$KEYID" "$HOME_DIR/.ssh/authorized_keys" > "$TMP" || true
fi
printf '%s %s\n' "$RESTRICT" "$PUBKEY" >> "$TMP"
install -m 0600 -o "$TUNNEL_USER" -g "$GROUP" "$TMP" "$HOME_DIR/.ssh/authorized_keys"

if command -v restorecon >/dev/null 2>&1; then
    restorecon -R "$HOME_DIR/.ssh" || true
fi

echo "[+] 已写入受限 key（只允许监听 127.0.0.1:${PORTS// /,127.0.0.1:}）"
grep -n "$KEYID" "$HOME_DIR/.ssh/authorized_keys"

echo
echo "== sshd 策略 =="
if command -v sshd >/dev/null 2>&1; then
    sshd -T 2>/dev/null | grep -E '^(allowtcpforwarding|gatewayports|permitlisten|permitopen)' || true
    if ! sshd -T 2>/dev/null | grep -q '^allowtcpforwarding yes'; then
        echo "[!] 警告：AllowTcpForwarding 不是 yes，反向隧道会失败" >&2
    fi
fi

echo
echo "== host key 指纹 =="
if [ -f /etc/ssh/ssh_host_ed25519_key.pub ]; then
    ACTUAL_FP="$(ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | awk '{print $2}')"
    ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
    if [ -n "$EXPECTED_FP" ] && [ "$ACTUAL_FP" != "$EXPECTED_FP" ]; then
        echo "[!] 警告：host key 与仓库里 pin 的不一致" >&2
        echo "    expected: $EXPECTED_FP" >&2
        echo "    actual:   $ACTUAL_FP" >&2
    fi
fi

echo
echo "完成。Windows 端会连接："
echo "  ssh -N -R 127.0.0.1:2222:10.140.35.70:22 -R 127.0.0.1:13389:127.0.0.1:3389 $TUNNEL_USER@<relay>"
echo
echo "删除账号：userdel -r $TUNNEL_USER"
