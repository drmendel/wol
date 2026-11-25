# Windows Wake-on-LAN (WoL) Diagnostics & Fix

PowerShell utilities to audit and configure Windows sleep states (S3/S5), Fast Startup, wake-armed devices, and network adapter Wake-on-LAN settings.

> **Note:** Open **PowerShell as Administrator** before running either command.

## Check Configuration

Run a read-only diagnostic check of your sleep state, Fast Startup status, wake-armed devices, and NIC WoL properties:

```powershell
irm "https://raw.githubusercontent.com/drmendel/wol/main/check" | iex
```

## Fix Configuration (Interactive)

Audit each setting and interactively prompt (`y/n`) before applying changes:

```powershell
irm "https://raw.githubusercontent.com/drmendel/wol/main/fix" | iex
```

## Requirements & Notes

- **Administrator privileges:** Required to query/modify `root\wmi` power classes, `powercfg`, and adapter properties.
- **S5 (Shutdown) WoL:** Requires Fast Startup to be disabled in Windows, plus **Wake on LAN / Power On By PCI-E** enabled (and **ErP** disabled) in your motherboard's UEFI/BIOS.
