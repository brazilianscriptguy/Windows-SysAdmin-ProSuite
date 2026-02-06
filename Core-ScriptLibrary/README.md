## 🔧 Core Script Library  
### Modular Automation · Reusable Components · Packaging Engine

![Core](https://img.shields.io/badge/Core-Script%20Library-red?style=for-the-badge&logo=visualstudiocode&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-Primary-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![Windows](https://img.shields.io/badge/Platform-Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white)
![Architecture](https://img.shields.io/badge/Architecture-Modular-008080?style=for-the-badge)
![Packaging](https://img.shields.io/badge/NuGet-Packaging-004880?style=for-the-badge&logo=nuget&logoColor=white)

---

## 🧭 Overview

The **Core Script Library** is a foundational component of the  
`Windows-SysAdmin-ProSuite/Core-ScriptLibrary/` directory.

It provides **enterprise-grade PowerShell building blocks** used across the entire repository, enabling:

- Reusable script scaffolding  
- GUI-driven administrative tools  
- Centralized logging and reporting  
- Automated NuGet packaging and publishing  

All components are designed with **determinism**, **auditability**, and **reuse** as first‑class principles.

---

## 🌟 Key Capabilities

- 🧩 **Modular Architecture** — Reusable functions, helpers, and UI components  
- 🎛️ **GUI-Ready Templates** — Windows Forms–based execution models  
- 📝 **Structured Logging** — Deterministic `.log` generation  
- 📊 **Exportable Outputs** — `.csv` and `.txt` artifacts  
- 📦 **Packaging Engine** — Automated NuGet creation and publishing  

---

## 📁 Repository Structure

| Subfolder | Purpose | Documentation |
|----------|---------|---------------|
| **Modular-PS1-Scripts** | PowerShell scaffolds for reusable automation, GUI menus, standardized headers, and centralized logging. | [![Docs](https://img.shields.io/badge/README-Modular%20Scripts-blue?style=for-the-badge&logo=github)](Modular-PS1-Scripts/README.md) |
| **Nuget-Package-Publisher** | End‑to‑end automation for building and publishing NuGet packages using PowerShell and GUI workflows. | [![Docs](https://img.shields.io/badge/README-NuGet%20Publisher-blue?style=for-the-badge&logo=github)](Nuget-Package-Publisher/README.md) |

---

## 🛠️ Requirements & Environment

### 1️⃣ PowerShell

```powershell
$PSVersionTable.PSVersion
```

- Minimum: **PowerShell 5.1**  
- Recommended: **PowerShell 7+**

---

### 2️⃣ Administrative Privileges

Administrator rights are required for:

- File system access  
- Service interaction  
- Package publishing  
- Registry and system configuration  

---

### 3️⃣ RSAT (Required for Modular-PS1-Scripts)

```powershell
Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online
```

RSAT is required when scripts interact with:

- Active Directory  
- DNS / DHCP  
- Group Policy Objects  

---

### 4️⃣ NuGet CLI (Nuget-Package-Publisher)

- Place `nuget.exe` in the script directory **or** ensure it is available in `PATH`.

```powershell
Test-Path (Join-Path $PSScriptRoot "nuget.exe")
```

---

### 5️⃣ GitHub Personal Access Token (PAT)

Required for publishing packages:

- Scope: `package:write`  
- Used by the NuGet publishing workflow  

---

### 6️⃣ Execution Policy (Session Scoped)

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
```

---

## 🚀 Getting Started

```bash
git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
```

```bash
cd Windows-SysAdmin-ProSuite/Core-ScriptLibrary
```

### Recommended Workflow

1. Review the README of the target subfolder  
2. Customize templates or configuration files  
3. Execute the script:

```powershell
.\ScriptName.ps1
```

4. Review generated logs and artifacts  

---

## 📝 Logging & Outputs

- **Logs**
  - `Modular-PS1-Scripts`: Local `.log` files
  - `Nuget-Package-Publisher`: `%LOCALAPPDATA%\NuGetPublisher\Logs`

- **Reports & Artifacts**
  - `.csv` exports
  - `.txt` execution summaries
  - `.nupkg` and `.snupkg` files

---

## 💡 Operational Best Practices

- 🔁 Schedule executions via **Task Scheduler**
- 📁 Centralize logs on shared storage for audits
- 🧪 Validate scripts in test environments first
- 🧾 Maintain standardized headers and metadata
- 📦 Automate package publishing via CI/CD

---

## 🤝 Support & Community

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com) [![Patreon](https://img.shields.io/badge/Support-Patreon-red?style=for-the-badge&logo=patreon)](https://www.patreon.com/brazilianscriptguy) [![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-yellow?style=for-the-badge&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy) [![Ko-fi](https://img.shields.io/badge/Ko--fi-blue?style=for-the-badge&logo=kofi)](https://ko-fi.com/brazilianscriptguy) [![GoFundMe](https://img.shields.io/badge/GoFundMe-green?style=for-the-badge&logo=gofundme)](https://gofund.me/4599d3e6) [![GitHub Issues](https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/issues)

---

© 2026 Luiz Hamilton Silva. All rights reserved.
