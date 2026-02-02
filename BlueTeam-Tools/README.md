## 🔵 BlueTeam-Tools Suite

### 📌 Overview

The **BlueTeam-Tools Suite** is a curated collection of forensic-grade PowerShell utilities designed for **Cybersecurity Analysts**, **Blue Team operators**, and **Incident Responders**. These tools support real-time threat detection, anomaly investigation, and security policy enforcement across Windows environments.

- 🔍 **Forensics Automation:** Extract event logs, registry data, network sessions, user activity, and volatile system states.  
- 🛡️ **Incident Response:** Assist in evidence collection, log correlation, and secure reporting during live attacks.  
- 📈 **Security Visibility:** Ensure policy compliance, audit system configurations, and generate actionable CSV reports.

---

## 🧩 Script Categories & Structure

| 📂 Category | Description | Link |
|-------------|-------------|------|
| **EventLogMonitoring** | Audit security logs and monitor high-risk system events (e.g., login failures, privilege escalations). | [![EventLogMonitoring](https://img.shields.io/badge/View%20Docs-EventLogMonitoring-blue?style=for-the-badge&logo=github)](EventLogMonitoring/README.md) |
| **IncidentResponse**   | Capture and analyze volatile artifacts: active sessions, system metadata, threat indicators. | [![IncidentResponse](https://img.shields.io/badge/View%20Docs-IncidentResponse-blue?style=for-the-badge&logo=github)](IncidentResponse/README.md) |

---

## 🛠️ Requirements

- ⚙️ **PowerShell:** Version 5.1 or later (`$PSVersionTable.PSVersion`)  
- 🖥️ **RSAT Tools:** Required for AD, DNS, DHCP support  
  ```powershell
  Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online
  ```
- 🔐 **Admin Rights:** Most scripts require elevated privileges  
- 🧾 **Execution Policy:**  
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
  ```
- 📦 **Required Modules:** `ActiveDirectory`, `Defender`, `DHCPServer` (where applicable)

---

## 🚀 Getting Started

```bash
git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
```

1. **Navigate to BlueTeam Suite:**  
   ```bash
   cd Windows-SysAdmin-ProSuite/BlueTeam-Tools/
   ```

2. **Explore Script Categories:**  
   Open the relevant folder and review its `README.md` for specific guidance.

3. **Run the Script:**  
   ```powershell
   .\Your-Script-Name.ps1
   ```

4. **Review Output:**  
   Each script generates `.log` and `.csv` files for traceability and analysis.

---

## 📦 Features at a Glance

- 📂 **Organized Logs:** All scripts output to structured folders with timestamped logs.  
- 🧠 **Intelligent Filters:** Reduce noise using regex, event selectors, and known IOCs.  
- 🎛️ **GUI-Ready:** Several scripts include Windows Forms interfaces.  
- 🔗 **Interoperable:** Chainable into IR pipelines, GPOs, or scheduled tasks.

---

## 📬 Contact & Support

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com)
[![Patreon](https://img.shields.io/badge/Support-Patreon-red?style=for-the-badge&logo=patreon)](https://patreon.com/brazilianscriptguy)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-yellow?style=for-the-badge&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-blue?style=for-the-badge&logo=kofi)](https://ko-fi.com/brazilianscriptguy)
[![GoFundMe](https://img.shields.io/badge/GoFundMe-Donate-green?style=for-the-badge&logo=gofundme)](https://gofundme.com/f/brazilianscriptguy)
[![GitHub Issues](https://img.shields.io/badge/Report%20Issue-GitHub-blue?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/issues)
[![WhatsApp](https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge&logo=whatsapp)](https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c)

---

💼 Thank you for using **BlueTeam-Tools Suite** — empowering secure, forensic-grade Windows administration.

© 2026 Luiz Hamilton. All rights reserved.
