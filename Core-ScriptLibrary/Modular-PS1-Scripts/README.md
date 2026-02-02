## 📂 Modular PS1 Scripts Suite

### 📝 Overview

The **Modular-PS1-Scripts** directory provides foundational **PowerShell scripts** that act as building blocks for reusable modules and GUI-based tools. These templates help automate IT tasks, enforce consistency, and accelerate tool development.

- 📦 **Reusable Components** — Modular patterns with standardized headers and code structure  
- 🎛️ **Dynamic Menus** — GUI-based launchers simplify script discovery and execution  
- 🪵 **Unified Logging** — Consistent `.log` outputs for auditability and troubleshooting  
- 📊 **Export Reports** — Structured exports (e.g., `.csv` / `.txt`) where applicable for pipelines and documentation  

---

## 🛠️ Prerequisites

1. ⚙️ **PowerShell Version**  
   Ensure PowerShell 5.1+ is installed:  
   ```powershell
   $PSVersionTable.PSVersion
````

2. 🔑 **Administrator Privileges**
   Required for scripts that modify system settings or protected resources.

3. 🖥️ **RSAT Tools**
   Required for AD/DNS/DHCP tooling in other templates:

   ```powershell
   Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online
   ```

4. 🔧 **Execution Policy**
   Enable script execution in-process:

   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope Process
   ```

---

## 📄 Script Descriptions (Alphabetical)

| Script                                       | Description                                                                                                                        |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| **Create-Script-HeaderModel.ps1**            | Generates standard script headers with metadata for consistency                                                                    |
| **Create-Script-LoggingMethod.ps1**          | Implements universal logging across modules for auditability and error tracking                                                    |
| **Create-Script-MainCodeStructure-Body.ps1** | Creates a script scaffold with structured logic blocks (guards, try/catch/finally, core flow)                                      |
| **Export-MarkdownCompilationReport.ps1**     | Recursively aggregates all `.md` files into a single structured report with metadata, table of contents, and content normalization |
| **Extract-Script-TextHeaders.ps1**           | Extracts header blocks from `.ps1` files and documents them to `.txt`                                                              |
| **Launch-Script-AutomaticMenu.ps1**          | GUI-based script launcher with folder-tabbed menus, real-time search, and execution workflow                                       |

---

## 🚀 Getting Started

1. **Clone the Repository**

   ```bash
   git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
   ```

2. **Navigate to Folder**
   `Windows-SysAdmin-ProSuite/Modular-PS1-Scripts/`

3. **Review Documentation**
   Each folder includes a `README.md` with usage notes.

4. **Run Scripts**

   ```powershell
   .\ScriptName.ps1
   ```

5. **Check Logs and Outputs**
   Inspect generated `.log` and exported reports (`.csv`, `.txt`) where applicable.

---

## 📝 Logging and Output

* 📄 **Logs** — Store runtime info, user actions, and errors in `.log` format
* 📊 **Reports** — Where applicable, structured exports (`.csv` / `.txt`) for downstream analysis

---

## 💡 Optimization Tips

* ⏲️ **Automate** — Use Task Scheduler or remote agents to trigger scripts
* 🧩 **Customize** — Adjust headers, logging, and GUI behavior to match your environment
* 📁 **Centralize Logs** — Store `.log` / exports in a shared directory for audit and review

---

## ❓ Additional Assistance

These scripting templates are designed for adaptation. Customize header formats, logging behavior, and GUI presentation to match your environment.
Refer to local `README.md` files in each directory for detailed usage instructions.

---

## 📬 Support and Contribution

<div align="center">

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge\&logo=gmail)](mailto:luizhamilton.lhr@gmail.com)
[![Patreon](https://img.shields.io/badge/Patreon-Support-red?style=for-the-badge\&logo=patreon)](https://patreon.com/brazilianscriptguy)
[![BuyMeACoffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-yellow?style=for-the-badge\&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-blue?style=for-the-badge\&logo=kofi)](https://ko-fi.com/brazilianscriptguy)
[![GoFundMe](https://img.shields.io/badge/GoFundMe-Donate-green?style=for-the-badge\&logo=gofundme)](https://gofund.me/4599d3e6)
[![WhatsApp](https://img.shields.io/badge/WhatsApp-Join%20Us-25D366?style=for-the-badge\&logo=whatsapp)](https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c)
[![GitHub Issues](https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge\&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/issues)

</div>
