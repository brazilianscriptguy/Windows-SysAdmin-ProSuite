## 🖥️ Efficient Workstation Management, Configuration, and ITSM Compliance for Windows 10 & 11

Welcome to the **ITSM-Templates-WKS** repository — a standardized toolkit of **PowerShell, VBScript, and .REG automation files** designed for the configuration, standardization, and compliance enforcement of Windows 10 and 11 workstations across institutional environments.

📘 **Official Guide:**  
**JUNE-19-2025-ITSM-Templates Application Guide for Windows 10 and 11.pdf**  
This document includes step-by-step procedures across nine units: domain preparation, OS image deployment, printer and workstation configuration, registry and GPO compliance, hostname conventions, and removal of decommissioned assets.

---

## 🌟 Key Features

- 🖼️ **GUI Interfaces:** Designed for L1 and L2 Service Desk staff.
- 📝 **Structured Logging:** Logs saved to `C:\ITSM-Logs-WKS\` in `.log` format.
- 📊 **CSV Reporting:** Inventory and configuration reports generated in `.csv` format.
- 🔒 **Built-in Microsoft Tools Only:** No 3rd-party dependencies — all operations use native Windows features.
- 📦 **Sysprep & Image Readiness:** Ensures cloned OS has unique SIDs, WSUS compliance, and domain readiness.

---

## 📄 Script Overview

### Folder: `/BeforeJoinDomain/`

| **Script Name**                   | Purpose                                                                                                       |
|------------------------------|---------------------------------------------------------------------------------------------------------------|
| **ITSM-BeforeJoinDomain.hta** | Executes 20 critical pre-join configurations: 10 VBScript actions + 10 Registry/Theme setups. Ensures WSUS, firewall, profile, UI, and theme standards are in place before AD join. |

### Folder: `/AfterJoinDomain/`

| **Script Name**                  | Purpose                                                                                                       |
|-----------------------------|---------------------------------------------------------------------------------------------------------------|
| **ITSM-AfterJoinDomain.hta** | Post-join automation: registers DNS, refreshes GPOs, updates profile metadata, and triggers domain logon caching via three login cycles. |

### Folder: `/Assets/AdditionalSupportScripts/`

| **Script Name**                            | Purpose                                                                                                   |
|----------------------------------------|-----------------------------------------------------------------------------------------------------------|
| **ActivateAllAdminShare.ps1**          | Enables Admin shares, activates RDP, disables Windows Firewall and Defender.                             |
| **ExportCustomThemesFiles.ps1**        | Extracts and packages local Windows themes, wallpapers, and layout.                                       |
| **FixPrinterDriverIssues.ps1**         | Flushes Print Spooler and clears faulty printer driver data.                                              |
| **GetSID.bat**                         | Retrieves the system SID using Sysinternals `psgetsid.exe`.                                               |
| **InventoryInstalledSoftwareList.ps1** | Generates software inventory in CSV format.                                                              |
| **LegacyWorkstationIngress.ps1**       | Enables legacy OSes to meet domain join policies.                                                         |
| **RenameDiskVolumes.ps1**              | Renames `C:` to match hostname and `D:` to "Personal-Files".                                              |
| **SystemMaintenanceWorkstations.ps1**  | Runs SFC, DISM, GPO sync, WSUS resync, and schedules reboot via GUI.                                     |
| **UnjoinADComputer-and-Cleanup.ps1**   | GUI tool for leaving the domain and cleaning residual AD/DNS metadata.                                    |
| **Update-KasperskyAgent.ps1**          | Updates Kaspersky client configuration and root certificates.                                             |
| **WorkStationConfigReport.ps1**        | Collects BIOS, OS, and network metadata into a structured .CSV.                                           |
| **WorkstationTimeSync.ps1**            | Syncs system clock, NTP source, and time zone using GUI automation.                                       |

### Folder: `/Assets/Certificates/`

| Certificate Name         | Purpose                                                                                      |
|--------------------------|----------------------------------------------------------------------------------------------|
| **ADCS-Server.cer**      | Root CA certificate for ADCS infrastructure.                                                 |
| **RDS-Server.cer**       | RDP trust certificate for Remote Desktop access.                                             |
| **WSUS-Server.cer**      | SSL certificate for WSUS communication.                                                      |

### Folder: `/Assets/CustomImages/`

| File/Asset Name           | Purpose                                                                 |
|---------------------------|-------------------------------------------------------------------------|
| **UserProfileImages/**     | Institutional photos for user profiles.                                |
| **DesktopThemeImages/**    | Default wallpaper and lock screen branding.                            |

### Folder: `/Assets/MainDocs/`

| Document Name                   | Purpose                                                                                                     |
|--------------------------------|-------------------------------------------------------------------------------------------------------------|
| **CheckListOrigin.docx**       | Editable version of the official ITSM procedure.                                                           |
| **DefaultUsersAccountImages/** | Default avatars and a hardened `hosts` file that blocks known malicious addresses.                         |

### Folder: `/Assets/ModifyReg/AllGeneralConfigs/`

| **Script Name**               | Purpose                                                             |
|---------------------------|---------------------------------------------------------------------|
| **GeneralConfigScripts/** | Disables Windows Firewall, UAC, sets default pages, and adjusts ownership metadata. |

### Folder: `/Assets/ModifyReg/DefaultBackground/`

| **Script Name**              | Purpose                                                                 |
|--------------------------|-------------------------------------------------------------------------|
| **BackgroundConfig.ps1** | Applies logon and wallpaper images.                                     |
| **HostsFileSetup.ps1**   | Overwrites `hosts` file with security-enhanced entries.                 |

### Folder: `/Assets/ModifyReg/UserDesktopFolders/`

| **Script Name**                        | Purpose                                                                 |
|-----------------------------------|-------------------------------------------------------------------------|
| **CopyInstitutionalShortcuts.ps1** | Creates desktop folders and institutional shortcuts for all users.      |

### Folder: `/Assets/ModifyReg/UserDesktopTheme/`

| **Script Name**                   | Purpose                                                                 |
|-------------------------------|-------------------------------------------------------------------------|
| **ApplyInstitutionalTheme.ps1** | Applies full `.deskthemepack`, classic mode UI, and branding.           |

---

## 🧭 Execution Order Summary

1. **Prepare system:** OOBE with Sysprep, enable built-in Administrator, and remove local accounts.
2. **Apply Windows Updates:** Use `WSUS Offline` or centralized update repository.
3. **Execute `ITSM-BeforeJoinDomain.hta`:** Applies 20 pre-join configs (scripts + registry).
4. **Rename drives:** `C:` = hostname, `D:` = Personal-Files.
5. **Join the Domain:** Manual or automated, authenticated using delegated account.
6. **Execute `ITSM-AfterJoinDomain.hta`:** Applies post-join fixes and logs in DNS/GPOs.
7. **Mandatory login cycles:** Perform 3x (Logon → Logoff → Reboot) under domain account.
8. **Validate logs:** In `C:\ITSM-Logs-WKS\` and `C:\Scripts-LOGS\`.

---

## 🏷️ Hostname Format

```

<LOC><EQUIP><UNIT><ASSET>
Example: MIADSALESO11704

````

| Component  | Meaning                                  |
|------------|------------------------------------------|
| LOC        | 3-letter location (e.g., MIA, BOS, NYC)  |
| EQUIP      | D = Desktop, L = Laptop, P = Printer     |
| UNIT       | Division/Section code (e.g., SALESO)     |
| ASSET      | Unique asset ID number                   |

Drive C label = hostname  
Drive D label = `Personal-Files`

---

## 📠 Printer Compliance Steps

- Enable DHCP, configure hostname, and reserve MAC/IP.
- Access via Embedded Web Server (EWS).
- Update firmware and restrict protocols.
- Enable SNMP v2/v3.
- Sync time with `ntp1.company`.
- Assign user-friendly display name:
  `PRINTER-ATL-L14510`, `PRINTER-TPA-HPCOLOR`

---

## 🧹 Domain Removal (Unjoin)

Use GUI tool `UnjoinADComputer-and-Cleanup.ps1`:

1. **Leave Domain** → reboot
2. **Post-Cleanup** → removes DNS, cached metadata
3. Confirm system is no longer resolvable via DNS

---

## 🚀 Getting Started

```bash
git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
````

```powershell
cd Windows-SysAdmin-ProSuite/ITSM-Templates-WKS/
.\ScriptName.ps1
```

Logs are saved to `C:\ITSM-Logs-WKS\`
Reports to `.csv` files within the same structure

---

## 📝 Logging & Reporting

* **Logs:** Stored in `C:\ITSM-Logs-WKS\` and `C:\Scripts-LOGS\`
* **Reports:** CSV summaries of config states, SID, BIOS, updates, apps, etc.

---

## 💡 Optimization Tips

* 🔁 Schedule with Task Scheduler or enforce via GPO
* 🗂️ Centralize logs to network share
* 🧩 Customize scripts to match institutional policy

---

## 📁 Log File Paths

```plaintext
C:\ITSM-Logs-WKS\
C:\Scripts-LOGS\
```

Includes:

* `ITSM-BeforeJoinDomain.log`
* `ITSM-AfterJoinDomain.log`
* `gpos-synch-and-sysmaint.log`
* `libreoffice-fullpackage-install.log`
* `kes-antivirus-install.log`
* and more...

---

## 📌 Document Classification

**RESTRICTED:** Internal use only. Confidential to IT management teams.

© 2025 Luiz Hamilton. All rights reserved.

---

## ❓ Need Help?

Check each folder’s `README.md` or contact support:

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge\&logo=gmail)](mailto:luizhamilton.lhr@gmail.com)
[![Patreon](https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge\&logo=patreon)](https://www.patreon.com/brazilianscriptguy)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Support-yellow?style=for-the-badge\&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20Me-blue?style=for-the-badge\&logo=kofi)](https://ko-fi.com/brazilianscriptguy)
[![WhatsApp](https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge\&logo=whatsapp)](https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c)
[![GitHub Issues](https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge\&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/issues)
