# 🔵 BlueTeam-Tools Suite  
### DFIR · Forensic Readiness · Security Visibility

[![Parent](https://img.shields.io/badge/Parent-Windows--SysAdmin--ProSuite-181717?style=for-the-badge&logo=github)](../)
[![BlueTeam](https://img.shields.io/badge/BlueTeam-DFIR-orange?style=for-the-badge)]()
[![Forensics](https://img.shields.io/badge/Domain-Digital%20Forensics-black?style=for-the-badge)]()
[![Security](https://img.shields.io/badge/Domain-Cybersecurity-critical?style=for-the-badge)]()
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-5391FE?style=for-the-badge&logo=powershell&logoColor=white)]()
[![Windows](https://img.shields.io/badge/Windows-Server%20%7C%2010%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)]()

---

## 🧭 Overview

[![Purpose](https://img.shields.io/badge/Purpose-Forensic%20Operations-blue?style=for-the-badge)]()
[![Design](https://img.shields.io/badge/Design-Auditable-success?style=for-the-badge)]()
[![Execution](https://img.shields.io/badge/Execution-Deterministic-6A5ACD?style=for-the-badge)]()

The **BlueTeam-Tools Suite** is a **forensic-grade PowerShell toolkit** designed for **Blue Team**, **DFIR**, and **Cybersecurity Operations** within Windows enterprise and public-sector environments.

It provides **repeatable**, **auditable**, and **incident-ready** tooling to support:

- Live-response operations  
- Event correlation and threat hunting  
- Evidence collection and forensic readiness  
- Security posture validation and audit support  

All tools follow the same engineering principles applied across **Windows-SysAdmin-ProSuite**:  
**deterministic execution, structured logging, and governance alignment**.

---

## 🧪 Core Capabilities

[![Forensics](https://img.shields.io/badge/Forensics-Ready-black?style=for-the-badge)]()
[![Logging](https://img.shields.io/badge/Logging-Structured-success?style=for-the-badge)]()
[![Reports](https://img.shields.io/badge/Reports-CSV%20%7C%20LOG-informational?style=for-the-badge)]()
[![GUI](https://img.shields.io/badge/GUI-Available-blueviolet?style=for-the-badge)]()

- 🔍 **Forensic Automation**  
  Extraction of Windows Event Logs, registry artifacts, network sessions, user activity, and volatile system state.

- 🛡️ **Incident Response Support**  
  Live-response data capture, evidence preservation, and correlation during active or post-incident scenarios.

- 📊 **Security Visibility & Auditability**  
  Policy validation, configuration auditing, and exportable `.csv` / `.log` artifacts suitable for compliance and investigations.

---

## 🧩 Script Categories & Architecture

[![Architecture](https://img.shields.io/badge/Architecture-Modular-008080?style=for-the-badge)]()
[![Integration](https://img.shields.io/badge/Integration-IR%20Pipelines-4B0082?style=for-the-badge)]()
[![Structure](https://img.shields.io/badge/Structure-Folder%20Based-2F4F4F?style=for-the-badge)]()

| Component | Purpose | Documentation |
|---------|---------|---------------|
| **EventLogMonitoring** | Security-focused analysis of Windows Event Logs, including authentication failures, privilege escalation, lateral movement indicators, and policy violations. | [![Docs](https://img.shields.io/badge/View-README-0A66C2?style=for-the-badge&logo=github)](EventLogMonitoring/README.md) |
| **IncidentResponse** | Live-response and post-incident utilities for volatile artifacts, active sessions, system metadata, and threat indicators. | [![Docs](https://img.shields.io/badge/View-README-0A66C2?style=for-the-badge&logo=github)](IncidentResponse/README.md) |

> Folder structure reflects **operational separation**, not execution order.

---

## 🏛️ Scope & Target Audience

[![Audience](https://img.shields.io/badge/Audience-Blue%20Team-orange?style=for-the-badge)]()
[![Audience](https://img.shields.io/badge/Audience-DFIR-darkred?style=for-the-badge)]()
[![Audience](https://img.shields.io/badge/Audience-Public%20Sector-0047AB?style=for-the-badge)]()
[![Audience](https://img.shields.io/badge/Audience-Enterprise%20SOC-2E8B57?style=for-the-badge)]()

Designed for professionals operating in:

- Security Operations Centers (SOC)
- Digital Forensics & Incident Response (DFIR)
- Identity & Access Management investigations
- Compliance, audit, and governance workflows
- Public-sector and regulated environments

---

## ⚙️ Requirements & Environment

[![PS](https://img.shields.io/badge/PowerShell-Minimum%205.1-5391FE?style=for-the-badge&logo=powershell)]()
[![Privileges](https://img.shields.io/badge/Privileges-Administrator-critical?style=for-the-badge)]()
[![Compatibility](https://img.shields.io/badge/Compatibility-Windows%20Native-success?style=for-the-badge)]()

- **PowerShell**  
  Minimum **5.1** (PowerShell 7+ supported)

```powershell
$PSVersionTable.PSVersion
```

- **Administrative Privileges**  
  Required to access protected system artifacts.

- **RSAT (when applicable)**

```powershell
Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online
```

- **Execution Policy (session-scoped)**

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
```

- **Optional Modules**  
  `ActiveDirectory`, `Defender`, `DHCPServer`

---

## 🚀 Getting Started

[![Clone](https://img.shields.io/badge/Access-Git%20Clone-181717?style=for-the-badge&logo=github)]()
[![Workflow](https://img.shields.io/badge/Workflow-Review%20→%20Execute-blue?style=for-the-badge)]()

```powershell
git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
cd Windows-SysAdmin-ProSuite/BlueTeam-Tools
```

**Recommended workflow:**

1. Select the appropriate category  
2. Review the local `README.md`  
3. Execute the script  
4. Review generated `.log` and `.csv` artifacts  

> ⚠️ Always validate execution context before running in production or investigative environments.

---

## 🔗 Integration & Interoperability

[![Integration](https://img.shields.io/badge/Integration-GPO-blue?style=for-the-badge)]()
[![Integration](https://img.shields.io/badge/Integration-Scheduled%20Tasks-4682B4?style=for-the-badge)]()
[![Integration](https://img.shields.io/badge/Integration-SIEM-informational?style=for-the-badge)]()

BlueTeam tools are designed to integrate with:

- Incident response playbooks  
- GPO-based execution models  
- Scheduled forensic snapshots  
- SIEM ingestion pipelines  
- Compliance and audit evidence chains  

---

## 🤝 Support & Community

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com)
[![Patreon](https://img.shields.io/badge/Support-Patreon-red?style=for-the-badge&logo=patreon)](https://patreon.com/brazilianscriptguy)
[![BuyMeACoffee](https://img.shields.io/badge/Support-Buy%20Me%20a%20Coffee-yellow?style=for-the-badge&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy)
[![Ko-fi](https://img.shields.io/badge/Support-Ko--fi-blue?style=for-the-badge&logo=kofi)](https://ko-fi.com/brazilianscriptguy)
[![GoFundMe](https://img.shields.io/badge/Support-GoFundMe-green?style=for-the-badge&logo=gofundme)](https://gofundme.com/f/brazilianscriptguy)

---

> 🛡️ _BlueTeam-Tools Suite is engineered for environments where **forensics, response, governance, and auditability converge**._

© 2026 Luiz Hamilton Silva. All rights reserved.
