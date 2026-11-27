#!/bin/bash
# Raspberry Pi setup for the WoL isolation test (CHECKLIST.md section 5).
#
#   sudo ./setup.sh <PC_MAC|auto> [PC_IP[/prefix]] [UDP_PORT]
#
#   PC_MAC   MAC address of the PC to wake, or "auto": learned from the DHCP lease
#            the first time the PC is awake on the cable
#   PC_IP    optional: give the PC exactly this IP (e.g. the one it has on the company
#            network). The DHCP pool is shrunk to this single address and the Pi's eth0
#            address is derived from it (first free host of the same subnet, default /24).
#            Omit it and the PC gets an automatic address; wol-test reads it from the lease.
#   UDP_PORT optional: magic-packet port, default 9 (UpSnap default)
#
# Re-run any time to change the values. Wi-Fi (for SSH) is not touched.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"
MAC=${1:?usage: setup.sh <PC_MAC|auto> [PC_IP[/prefix]] [UDP_PORT]}
PCIP=${2:-}
PORT=${3:-9}
IFACE=eth0
DIR=$(cd "$(dirname "$0")" && pwd)

if [ "$MAC" != auto ]; then
  [[ $MAC =~ ^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$ ]] || { echo "invalid MAC: $MAC"; exit 1; }
  MAC=$(tr 'A-F-' 'a-f:' <<<"$MAC")
fi

echo "==> Installing packages"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq wakeonlan etherwake tcpdump nmap dnsmasq-base >/dev/null

echo "==> Installing wol-test"
if [ -f "$DIR/wol-test" ]; then install -m755 "$DIR/wol-test" /usr/local/bin/wol-test
else curl -fsSL https://raw.githubusercontent.com/drmendel/wol/main/pi/wol-test -o /usr/local/bin/wol-test && chmod 755 /usr/local/bin/wol-test; fi

echo "==> eth0: NetworkManager 'shared' profile (DHCP server for the directly cabled PC)"
nmcli con delete wol-direct >/dev/null 2>&1 || true
ADDR=()
rm -f /etc/NetworkManager/dnsmasq-shared.d/wol-test.conf
if [ -n "$PCIP" ]; then
  PIADDR=$(python3 - "$PCIP" <<'EOF'
import ipaddress, sys
pc = ipaddress.ip_interface(sys.argv[1] if "/" in sys.argv[1] else sys.argv[1] + "/24")
hosts = list(pc.network.hosts())
pi = hosts[0] if hosts[0] != pc.ip else hosts[-1]
print(f"{pi}/{pc.network.prefixlen}")
EOF
)
  PCIP=${PCIP%/*}
  # single-address pool: whatever PC is on the direct cable gets exactly $PCIP
  ADDR=(ipv4.addresses "$PIADDR" ipv4.shared-dhcp-range "$PCIP,$PCIP" ipv4.shared-dhcp-lease-time 300)
  if [ "$MAC" != auto ]; then
    mkdir -p /etc/NetworkManager/dnsmasq-shared.d
    echo "dhcp-host=$MAC,$PCIP" > /etc/NetworkManager/dnsmasq-shared.d/wol-test.conf
  fi
  echo "    Pi eth0 = $PIADDR, PC gets $PCIP (MAC: $MAC)"
else
  echo "    automatic subnet; the PC's IP is read from the DHCP lease"
fi
nmcli con add type ethernet ifname "$IFACE" con-name wol-direct autoconnect yes \
  connection.autoconnect-priority 100 ipv4.method shared "${ADDR[@]}" ipv6.method disabled >/dev/null

cat > /etc/wol-test.conf <<EOF
MAC=$MAC
IP=$PCIP
PORT=$PORT
IFACE=$IFACE
WAIT=120
EOF

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

echo
echo "Done. Plug the cable into the PC, wake it once, put it to sleep, then later run: wol-test run"
echo "Before plugging this Pi into a real network: sudo nmcli con down wol-direct  (it serves DHCP on eth0)"
