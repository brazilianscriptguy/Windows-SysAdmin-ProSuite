## 🖥️ Efficient Workstation Management, Configuration, and ITSM Compliance for Windows 10 & 11

Welcome to the **ITSM-Templates-WKS** repository — a curated suite of **PowerShell and VBScript automation tools** for managing and standardizing Windows 10 and 11 workstations. These scripts help IT teams automate tasks, enforce ITSM policies, and streamline configuration workflows.

📘 For full reference, see:  
**JUNE-19-2025-ITSM-Templates Application Guide for Windows 10 and 11.pdf**  
This guide includes step-by-step procedures across nine units, covering domain prep, workstation standardization, printer setup, and naming conventions.

---

## 🌟 Key Features

- 🖼️ **Graphical Interfaces (GUI):** Designed for use by Level 1 and Level 2 support.  
- 📝 **Structured Logging:** Logs generated in `.log` format with standardized naming.  
- 📊 **CSV Reporting:** Exportable `.csv` reports for documentation and audits.

---

## 📄 Script Overview

### Folder: `/BeforeJoinDomain/`

| Script Name | Purpose |
|-------------|---------|
| **ITSM-BeforeJoinDomain.hta** | Automates 20 pre-domain actions: registry, network reset, profile prep, WSUS certs, and security compliance for domain readiness. |

### Folder: `/AfterJoinDomain/`

| Script Name | Purpose |
|-------------|---------|
| **ITSM-AfterJoinDomain.hta** | Finalizes domain config: DNS registration, GPO refresh, profile imprint, offline login setup — ensuring full domain integration. |

---

## 🚀 Getting Started

```bash
git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
```

1. **Navigate to:**  
   `Windows-SysAdmin-ProSuite/ITSM-Templates-WKS/`

2. **Read Instructions:**  
   Each subfolder has a `README.md` with usage guidance.

3. **Run the Script:**  
   ```powershell
   .\ScriptName.ps1
   ```

4. **Review Outputs:**  
   Logs (`.log`) and reports (`.csv`) are saved in designated folders.

---

## 📝 Logging & Reporting

- **Logs:**  
  All actions are logged in `.log` format for troubleshooting and audit trails.

- **Reports:**  
  Workstation actions are summarized in `.csv` files.

---

## 💡 Optimization Tips

- 🔁 **Automate Execution:** Schedule via Task Scheduler or enforce via GPO.  
- 🗂️ **Centralize Logs:** Redirect outputs to shared folders for compliance.  
- 🧩 **Customize Scripts:** Modify templates to match your IT governance model.

---

## 📁 Log File Paths

All logs are saved to:

```plaintext
C:\ITSM-Logs-WKS\
```

This includes:
- Domain ingress activity logs  
- DNS registration logs  
- User profile imprint logs

---

## ❓ Need Help?

This project is modular and adaptable. For help, check each folder's `README.md` or use the support links below:

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com)
[![Patreon](https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge&logo=patreon)](https://www.patreon.com/brazilianscriptguy)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Support-yellow?style=for-the-badge&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20Me-blue?style=for-the-badge&logo=kofi)](https://ko-fi.com/brazilianscriptguy)
[![GoFundMe](https://img.shields.io/badge/GoFundMe-Donate-green?style=for-the-badge&logo=gofundme)](https://gofund.me/4599d3e6)
[![WhatsApp](https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge&logo=whatsapp)](https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c)
[![GitHub Issues](https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/ISSUE_TEMPLATE/CUSTOM_ISSUE_TEMPLATE.md)

---

## 📌 Document Classification

**RESTRICTED:** This documentation is intended for internal use within the organization only.

© 2025 Luiz Hamilton. All rights reserved.
