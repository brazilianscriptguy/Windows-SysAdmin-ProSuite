
## 📂 Modular PS1 Scripts Suite  
### Modular Automation · Reusable Components · GUI Templates

![Suite](https://img.shields.io/badge/Suite-Modular%20PS1%20Scripts-FF6F00?style=for-the-badge&logo=code&logoColor=white) ![PowerShell](https://img.shields.io/badge/PowerShell-Primary-5391FE?style=for-the-badge&logo=powershell&logoColor=white) ![Windows](https://img.shields.io/badge/Platform-Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white) ![Architecture](https://img.shields.io/badge/Architecture-Modular-008080?style=for-the-badge) ![Outputs](https://img.shields.io/badge/Outputs-LOG%20%7C%20CSV-success?style=for-the-badge)

---

## 🧭 Overview

The **Modular-PS1-Scripts** directory provides foundational **PowerShell templates** that serve as building blocks for reusable modules and GUI-based tools. These scripts are designed to accelerate development, enforce consistency, and standardize operational execution across Windows environments.

- 📦 **Reusable Components** — Modular functions and standardized script scaffolds  
- 🎛️ **Dynamic Menus** — GUI launchers for faster navigation and execution  
- 🪵 **Unified Logging** — Deterministic `.log` generation for audit and troubleshooting  
- 📊 **Export Reports** — Structured `.csv` outputs for pipelines and documentation  

---

## 🛠️ Prerequisites

1. ⚙️ **PowerShell Version**  
   Ensure PowerShell **5.1+** is available:
   ```powershell
   $PSVersionTable.PSVersion
   ```

2. 🔑 **Administrator Privileges**  
   Required for scripts that modify system settings or protected resources.

3. 🖥️ **RSAT Tools**  
   Required when templates interact with **AD / DNS / DHCP**:
   ```powershell
   Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online
   ```

4. 🔧 **Execution Policy (Session Scoped)**  
   Enable script execution for the current PowerShell session:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
   ```

---

## 📄 Script Inventory (Alphabetical)

| Script Name | Description |
|------------|-------------|
| **Create-Script-HeaderModel.ps1** | Generates standardized PowerShell script headers with metadata and comment-based help blocks. |
| **Create-Script-LoggingMethod.ps1** | Implements a reusable, universal logging method for consistent audit trails and error tracking. |
| **Create-Script-MainCodeStructure-Body.ps1** | Builds a clean, structured script body scaffold aligned with PowerShell best practices. |
| **Export-MarkdownCompilationReport.ps1** | Recursively collects `.md` files into a normalized compilation report with a table of contents. |
| **Extract-Script-TextHeaders.ps1** | Extracts comment-based header blocks from `.ps1` files and exports them to plain text. |
| **Launch-Script-AutomaticMenu.ps1** | GUI-based script launcher with tabbed navigation, search, and execution controls. |

---

## 🚀 Getting Started

1. **Clone the Repository**
   ```bash
   git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
   ```

2. **Navigate to Folder**
   ```bash
   cd Windows-SysAdmin-ProSuite/Core-ScriptLibrary/Modular-PS1-Scripts
   ```

3. **Review Documentation**  
   Each tool includes usage notes in its local `README.md`.

4. **Run Scripts**
   ```powershell
   .\ScriptName.ps1
   ```

5. **Check Logs and Outputs**  
   Review generated `.log` and `.csv` artifacts for traceability and reporting.

---

## 📝 Logging and Output

- 📄 **Logs** — Runtime flow, warnings, user actions, and errors (`.log`)  
- 📊 **Reports** — Structured data exports (`.csv`) where applicable  

---

## 💡 Optimization Tips

- ⏲️ **Automate** — Use Task Scheduler or remote execution to trigger scripts  
- 🧩 **Customize** — Adapt scaffolds to match internal coding standards  
- 📁 **Centralize Logs** — Store `.log` and `.csv` artifacts in shared folders for audit and SOC visibility  

---

## ❓ Additional Assistance

These templates are designed for adaptation. Customize header formats, logging behavior, and GUI layout to match your environment.  
Refer to each tool’s local `README.md` for detailed usage guidance.

---

© 2026 Luiz Hamilton Silva. All rights reserved.
