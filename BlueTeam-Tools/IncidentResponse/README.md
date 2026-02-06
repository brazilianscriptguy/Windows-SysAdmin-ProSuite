## 🔵 BlueTeam-Tools: Incident Response Suite  
### DFIR · Live Response · Evidence Preservation

[![BlueTeam](https://img.shields.io/badge/BlueTeam-Incident%20Response-orange?style=for-the-badge&logo=protonmail&logoColor=white)]() [![PowerShell](https://img.shields.io/badge/PowerShell-Primary-5391FE?style=for-the-badge&logo=powershell&logoColor=white)]() [![Windows](https://img.shields.io/badge/Windows-Server%20%7C%2010%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)]() [![Forensics](https://img.shields.io/badge/Domain-Digital%20Forensics-black?style=for-the-badge)]() [![Security](https://img.shields.io/badge/Domain-Cybersecurity-critical?style=for-the-badge)]()

---

The **IncidentResponse** folder contains focused **PowerShell scripts** designed for real-time **incident response** in **Active Directory** and **Windows Server** environments. These tools support security teams in rapid assessment, cleanup, and documentation — minimizing downtime while preserving forensic data.

- 🧠 **Forensic Precision:** Decodes encoded messages, logs attacker behavior, and sanitizes compromised files.  
- 🛡️ **Rapid Cleanup:** Automates post-incident file removal and data decoding.  
- 📝 **Audit-Friendly:** Generates `.log` and `.csv` for evidence and reports.  
- 🎛️ **GUI-Enhanced:** User-friendly interfaces reduce analyst workload.

---

## 📦 Script Inventory (Alphabetical)

| Script | Description |
|--------|-------------|
| **Decipher-EML-MailMessages-Tool.ps1** | Decodes suspicious email content using ROT13, Caesar, base64, and ASCII shift to expose embedded payloads. |
| **Delete-FilesByExtensionBulk-Tool.ps1** | Bulk deletes files by extension using `Delete-FilesByExtension-List.txt`. Ideal for secure cleanup after an incident. |

---

## 🚀 How to Use

1. **Run the Script**  
   Right-click → `Run with PowerShell` or execute via CLI.

2. **Provide Inputs**  
   Follow prompts or load config files as instructed by each script.

3. **Review Outputs**  
   Check `.log` and `.csv` files for validation and documentation.

---

### 🔬 Example Scenarios

- **🧩 Decipher-EML-MailMessages-Tool.ps1**
  - Decode phishing messages and C2 beacons embedded in email headers or body.
  - Review the log for decoded strings and match results.

- **🧹 Delete-FilesByExtensionBulk-Tool.ps1**
  - Populate `Delete-FilesByExtension-List.txt` with extensions like `.tmp`, `.bak`, `.vbs`.
  - Run the script to remove all matching files post-compromise.

---

## 🛠️ Requirements

- ✅ PowerShell 5.1 or newer  
- 🔐 Administrator rights  
- 🖥️ RSAT installed (for AD-related tools)
  ```powershell
  Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online
  ```
- 📦 Active Directory module:  
  ```powershell
  Import-Module ActiveDirectory
  ```

---

## 📊 Logs and Reports

- `.log`: Execution flow, exceptions, and summary of activities  
- `.csv`: Structured export for incident report inclusion or SIEM ingestion

---

## 💡 Optimization Tips

- 🕓 **Automate Actions:** Use Task Scheduler to schedule regular cleanups  
- 📁 **Centralize Outputs:** Store logs and reports in `\\server\IncidentResponseLogs` for SOC review  
- 🔧 **Customize Templates:** Adjust `.txt` config files for tailored remediation per incident type

---

© 2026 Luiz Hamilton Silva. All rights reserved.
