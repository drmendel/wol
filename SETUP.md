## Wake-on-LAN (WoL) Setup Guide

### Phase 1: Collect Network Information

1. Open Command Prompt (`cmd`).
2. Run the command:

```cmd
ipconfig /all
```

3. Record and send me the following details for your target machine:

- **Physical Address (MAC Address)**
- **IPv4 Address**
- **Subnet Mask**

---

### Phase 2: Allow Ping Requests in Windows Firewall

1. Press `Win + R`, type `wf.msc`, and press **Enter** to open Windows Defender Firewall.
2. Select **Inbound Rules** from the left panel.
3. Locate **File and Printer Sharing (Echo Request - ICMPv4-In)**.
4. Click **Enable Rule** in the right-hand panel (or right-click the rule and select **Enable Rule**).

---

### Phase 3: Configure Network Adapter Settings

1. Press `Win + X`, then select **Device Manager** (or press `M`).
2. Expand the **Network adapters** category.
3. Right-click your Ethernet adapter and select **Properties**.
4. Under the **Advanced** tab, configure the following:

- **Wake on Magic Packet** $\rightarrow$ `Enabled`
- **Wake on pattern match** $\rightarrow$ `Enabled`

5. Under the **Power Management** tab, check the following options:

- `Allow this device to wake the computer`
- `Only allow a magic packet to wake the computer`

6. Click **OK** to save changes.

---

### Phase 4: Enable Wake-on-LAN in BIOS/UEFI

1. Restart your computer and press the appropriate key during boot to enter BIOS:

- **HP:** `F10`
- **Dell:** `F2`
- **Lenovo:** `F1` or `F2`
- **Asus / Acer:** `F2` or `Delete`

2. Navigate through the settings and adjust the following options:

- **Power On By PCIe Device** (or **Resume by Onboard LAN**): `Enabled`
- **ErP / EuP**: `Disabled` _(allows network card to receive power while off)_

3. Save changes and exit BIOS.
