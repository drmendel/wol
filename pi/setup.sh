#!/bin/bash
# Raspberry Pi setup for the WoL isolation test (CHECKLIST.md section 5).
#
#   sudo ./setup.sh [<profile> | <ip/prefix> <mac>]
#
# Installs the tools, the eth0 profile "wol-direct" (DHCP server for the directly
# cabled PC) and the sleep/wake monitor. Safe to re-run: existing config is kept.
# Targets are managed afterwards with wol-test:
#
#   wol-test profile add home 192.168.50.4/24 AA-BB-CC-DD-EE-FF
#   wol-test use home          # point eth0 + DHCP at that PC
#   wol-test run home          # or switch and test in one go
#
# Optional arguments are passed to "wol-test use". Wi-Fi (for SSH) is not touched.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"
IFACE=eth0
DIR=$(cd "$(dirname "$0")" && pwd)

echo "==> Installing packages"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq wakeonlan etherwake tcpdump nmap dnsmasq-base python3 >/dev/null

echo "==> Installing wol-test"
if [ -f "$DIR/wol-test" ]; then install -m755 "$DIR/wol-test" /usr/local/bin/wol-test
else curl -fsSL https://raw.githubusercontent.com/drmendel/wol/main/pi/wol-test -o /usr/local/bin/wol-test && chmod 755 /usr/local/bin/wol-test; fi

echo "==> Profiles: /etc/wol-test/profiles"
mkdir -p /etc/wol-test
[ -f /etc/wol-test/profiles ] || echo "# <name> <ip/prefix> <mac>   (add with: wol-test profile add ...)" > /etc/wol-test/profiles

echo "==> eth0: NetworkManager 'shared' profile wol-direct (DHCP for the directly cabled PC)"
if nmcli -g connection.id con show wol-direct >/dev/null 2>&1; then
  echo "    exists, kept"
else
  nmcli con add type ethernet ifname "$IFACE" con-name wol-direct autoconnect yes \
    connection.autoconnect-priority 100 ipv4.method shared ipv6.method disabled >/dev/null
  echo "    created (target set with: wol-test use ...)"
fi

echo "==> Monitor service (logs when the PC sleeps / wakes)"
cat > /etc/systemd/system/wol-monitor.service <<'EOF'
[Unit]
Description=WoL test: track PC sleep/wake on eth0
After=NetworkManager.service
[Service]
ExecStart=/usr/local/bin/wol-test monitor
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable wol-monitor >/dev/null 2>&1
systemctl restart wol-monitor

[ $# -gt 0 ] && /usr/local/bin/wol-test use "$@"

echo
echo "Done. Next:"
echo "  wol-test profile add <name> <ip/prefix> <mac>    save a PC"
echo "  wol-test use <name>                              before the PC goes to sleep"
echo "  wol-test run <name>                              after the wait"
echo "Before plugging this Pi into a real network: sudo nmcli con down wol-direct  (it serves DHCP on eth0)"
