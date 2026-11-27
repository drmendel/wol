# Wake-on-LAN Troubleshooting Checklist

Work through it top to bottom. Each section narrows down **where** the problem is: the PC, the switch port, or the routing between subnets.

---

## 0. Know the symptom

| Symptom | Most likely area |
|---|---|
| Wakes if sent 1–2 min after shutdown, fails later | Switch MAC table / router ARP aging (§6–§7), or NIC losing power (§1, §4) |
| Never wakes from shutdown, wakes from sleep | Fast Startup or BIOS S5 settings (§1, §2) |
| Network LED goes dark after shutdown | NIC unpowered: BIOS ErP / Deep Sleep (§1) |
| Works over a direct cable, fails on the corporate network | Switch port: 802.1X, speed, EEE, storm control (§7) |
| Works on the same VLAN, fails from another subnet | Expected; needs a relay, static ARP or directed broadcast (§8) |

---

## 1. BIOS / UEFI

- [ ] **Wake on LAN** / **Power On By PCI-E** / **Resume by Onboard LAN** → `Enabled`
- [ ] WoL mode is **not** "Disabled in S5" or "Sleep only" (should be "LAN" or "LAN with PXE boot")
- [ ] **ErP / EuP** → `Disabled`
- [ ] **Deep Sleep** (Dell: *Deep Sleep Control*) → `Disabled`
- [ ] **Fast Boot** / **Ultra Fast Boot** → `Disabled` (at least while testing)
- [ ] **AC Recovery** set as desired (not WoL-related, but avoids confusion after power cuts)
- [ ] Saved and exited (F10), then one **full** power-on

## 2. Windows power settings

Run [`check`](check) (read-only) and [`fix`](fix) (interactive) from an **admin PowerShell**, see [README](README.md).

- [ ] **Fast Startup** off: Control Panel → Power Options → *Choose what the power buttons do*
- [ ] Hibernation off (`powercfg /h off`) if you don't need it
- [ ] NIC appears in `powercfg /devicequery wake_armed`
- [ ] Shutdown done via **Start → Shut down** (not by holding the power button or pulling the plug)
- [ ] After changing settings: one full shutdown → power-on cycle before testing

## 3. Network adapter (Device Manager → adapter → Properties)

**Power Management tab**
- [ ] *Allow this device to wake the computer* ✔
- [ ] *Only allow a magic packet to wake the computer* ✔

**Advanced tab** (names vary by vendor)
- [ ] *Wake on Magic Packet* → `Enabled`
- [ ] *Shutdown Wake-On-LAN* / *Wake from power off state* → `Enabled` (Realtek / Intel)
- [ ] *Wake on Pattern Match* → `Disabled` (prevents random wake-ups; not needed for magic packets)
- [ ] *Energy-Efficient Ethernet* / *Green Ethernet* / *EEE* → `Disabled`
- [ ] *Reduce speed during standby* / *Wake on Link Settings*: note the value, because WoL often links at **10/100 Mbit** when off (see §7)
- [ ] Latest NIC driver from the **chipset vendor** (Intel / Realtek), not only the Windows Update one

## 4. Physical check while the PC is off

- [ ] Shut down and wait **at least 1–2 hours**
- [ ] NIC link LED on the PC **still lit** (often amber / slow)
- [ ] Switch port LED still lit (ask the admin to confirm the port is *up* and at what speed)

> LED dark → the NIC has no power or no link → back to §1. Nothing on the network side can fix that.

## 5. Isolation test: Raspberry Pi with a direct cable

This removes the corporate network from the picture. No switch is needed; the Pi 4 auto-crosses a normal Ethernet cable. Tooling: [`pi/`](pi).

**Setup (once)**: the Pi joins your phone hotspot / Wi-Fi for SSH; `eth0` gets a DHCP server for the PC.

```bash
git clone https://github.com/drmendel/wol && sudo wol/pi/setup.sh
wol-test profile add home 192.168.50.4/24 AA-BB-CC-DD-EE-FF   # save each PC: name, ip/prefix, MAC
```

`wol-test use <profile>` points the Pi at a PC: Pi `eth0` takes the first free host of the PC's subnet and the DHCP server hands out exactly the PC's IP, so the PC keeps the address it has on its real network. `run`, `status` and the single shots also take `<profile>` or `<ip/prefix> <mac>` directly, e.g. `wol-test run 192.168.50.4/24 AA-BB-CC-DD-EE-FF`.

**Find the Pi** from the laptop (on the same hotspot), whatever subnet the hotspot uses:

```bash
nmap -p22 --open "$(ip -4 route show dev "$(ip route show default | awk '{print $5; exit}')" scope link | awk '{print $1; exit}')"
ssh <user>@<pi-ip>
```

**Run**

- [ ] PC asleep / shut down (for as long as it takes to fail with UpSnap, even days), LED still lit
- [ ] Pi `eth0` cabled **directly** to the PC. The PC does **not** need to be switched on: IP and MAC come from the profile
- [ ] Optional: `wol-test use <profile>` while the PC is still awake lets the Pi time the sleep (`wol-test status`)
- [ ] `wol-test run <profile>` sends, in order, and stops at the first one that wakes the PC:

| Shot | What is sent | Woke the PC → conclusion |
|---|---|---|
| `unicast` | UDP magic packet to the PC's IP (what UpSnap does) | PC fine, no ARP problem on this path |
| `static` | same packet, ARP entry pinned (`ip neigh … nud permanent`) | **PC fine, expired ARP entry is the problem** → §8 |
| `raw` | `etherwake`, raw Ethernet (EtherType 0x0842) | PC fine, problem is on the UDP/ARP path → §6–§8 |
| none, link up | | **PC configuration** is still wrong → §1–§4 |

> **Why three shots?** A sleeping PC doesn't answer ARP. Once the sender's ARP entry expires, a *unicast* magic packet never leaves the sender; the kernel drops it after the unanswered `who-has`. That happens on the Pi too, so a failed plain unicast alone doesn't prove the PC is at fault. Each shot logs the neighbour entry and a pcap of what actually went on the wire (`wol-test report` for the summary table, `wol-test log`, `/var/log/wol-test/*.pcap`): bring that to the admin.

If `eth0` has no link while the PC is off, `wol-test` stops: the NIC is unpowered (§1, §4) and no packet can help.

> Before plugging the Pi into a real network (§6): `sudo nmcli con down wol-direct`, because it serves DHCP on `eth0`.

## 6. Same-VLAN test on the real network

- [ ] Pi plugged into the **same VLAN** as the PC (ideally the same access switch)
- [ ] Sniffer running to prove the packet arrives:
  ```bash
  sudo tcpdump -i eth0 -e -n 'ether proto 0x0842 or udp port 9 or udp port 7'
  ```
- [ ] Find the **failure threshold**: send `etherwake` after the PC has been off for 2, 5, 10, 30 min, 1 h, 4 h

| Starts failing after | Likely cause |
|---|---|
| ~5 min, unicast only | Switch MAC address-table aging (default 300 s). Broadcast should still work |
| Minutes, **broadcast fails too** | **802.1X / NAC**: unauthorized port drops all egress traffic |
| Any time, broadcast fails | Port speed forced to 1G, EEE, storm control, port-security |
| ~4 h, only from another subnet | Router ARP timeout (Cisco default 4 h) |

## 7. Switch port (for the network admin)

- [ ] Port status while PC is off: **up/down**, negotiated **speed**
- [ ] Speed/duplex on **auto** (not forced 1000), so the 10/100 WoL link can come up
- [ ] **802.1X / MAB**: unidirectional control enabled
  (Cisco: `authentication control-direction in`; older IOS: `dot1x control-direction in`)
- [ ] EEE (`no power efficient-ethernet auto`) off on the port if the link drops
- [ ] Storm control isn't dropping broadcasts on that VLAN
- [ ] Port-security / sticky MAC not shutting the port when the MAC disappears
- [ ] Dynamic VLAN assignment: PC lands in the **same VLAN** when unauthenticated

## 8. Permanent fix for waking across subnets

A powered-off PC doesn't answer ARP, so a routed unicast magic packet is **dropped by design** once the ARP entry expires. Choose one:

- [ ] **WoL relay on the same VLAN**: the Raspberry Pi stays on the PC's VLAN; SSH in (VPN / Tailscale) and run `etherwake`
- [ ] **Static ARP entry** on the router for the PC's (DHCP-reserved) IP → MAC
- [ ] **Subnet-directed broadcast** allowed on the VLAN interface, restricted by ACL to UDP/9 from the trusted source
  (Cisco: `ip directed-broadcast <acl>` on the SVI)

---

### What to bring to the admin

1. Result of §5 (direct cable: wakes / doesn't wake)
2. The failure threshold from §6
3. The tcpdump output showing the packet reaches the VLAN
4. The specific request from §7 / §8
