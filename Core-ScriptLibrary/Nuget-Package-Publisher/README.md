## 📦 NuGet Package Publisher Suite  
### Packaging Automation · Metadata Validation · GitHub Packages Delivery

![Suite](https://img.shields.io/badge/Suite-NuGet%20Package%20Publisher-004880?style=for-the-badge&logo=nuget&logoColor=white) ![PowerShell](https://img.shields.io/badge/PowerShell-Primary-5391FE?style=for-the-badge&logo=powershell&logoColor=white) ![GitHub](https://img.shields.io/badge/Target-GitHub%20Packages-181717?style=for-the-badge&logo=github&logoColor=white) ![Automation](https://img.shields.io/badge/Automation-GUI%20%7C%20Config-success?style=for-the-badge) ![Outputs](https://img.shields.io/badge/Outputs-LOG%20%7C%20TXT-informational?style=for-the-badge)

---

## 🧭 Overview

The **NuGet Package Publisher Suite** includes a specialized PowerShell tool named **`Generate-NuGet-Package.ps1`** that automates the **creation**, **validation**, and **publication** of NuGet packages to **GitHub Packages**.

It provides a GUI-driven workflow plus reusable components that streamline publishing for Windows administrators and developers.

- 📦 **Package Automation** — Build and publish NuGet packages deterministically  
- 🎛️ **GUI Interface** — Configure metadata and execution parameters interactively  
- 🪵 **Detailed Logging** — Generates `.log` files for full traceability  
- 📊 **Artifact Reports** — Emits `NuGetReport_*.txt` summaries per publish run  

---

## 🛠️ Prerequisites

1. ⚙️ **PowerShell Version**  
   PowerShell **5.1+** is required:
   ```powershell
   $PSVersionTable.PSVersion
   ```

2. 🔑 **Administrator Privileges**  
   Recommended for filesystem and protected path operations.

3. 🔧 **NuGet CLI**  
   Download `nuget.exe` and place it in the folder or add it to `PATH`:
   ```powershell
   Test-Path (Join-Path $PSScriptRoot "nuget.exe")
   ```
   ![Download](https://img.shields.io/badge/Download-nuget.exe-004880?style=for-the-badge&logo=nuget&logoColor=white)

4. 🔐 **GitHub Personal Access Token (PAT)**  
   Must include **`package:write`** scope for GitHub Packages publishing.

5. 🔧 **Execution Policy (Session Scoped)**  
   Enable script execution for the current session:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
   ```

---

## 📂 Folder Structure

Recommended layout under:  
`Windows-SysAdmin-ProSuite/Core-ScriptLibrary/Nuget-Package-Publisher/`

- `Generate-NuGet-Package.ps1` — Main script (GUI + logic)  
- `config.json` (optional) — Stores metadata like ID, version, description, and PAT  
- `artifacts/` — Stores `.nupkg` files and reports such as `NuGetReport_*.txt`  
- `%LOCALAPPDATA%\NuGetPublisher\Logs\` — Execution logs  
- `nuget.exe` (optional) — NuGet CLI binary placed in the root folder  

---

## 📄 Script Description

| Script Name | Description |
|------------|-------------|
| **Generate-NuGet-Package.ps1** | Automates NuGet packaging and publishing with GUI, config options, validation, reporting, and execution logging. |

---

## 🚀 Getting Started

1. **Clone the Repository**
   ```bash
   git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
   ```

2. **Navigate to the Script Folder**
   ```bash
   cd Windows-SysAdmin-ProSuite/Core-ScriptLibrary/Nuget-Package-Publisher
   ```

3. **Install NuGet CLI**
   - Place `nuget.exe` in the folder **or** add it to `PATH`.

4. **Prepare Folder Structure**
   - Ensure `artifacts/` exists  
   - Ensure the log directory is writable

5. **Run the Script**
   ```powershell
   .\Generate-NuGet-Package.ps1
   ```

6. **Review Logs and Output**
   - Logs: `%LOCALAPPDATA%\NuGetPublisher\Logs\`
   - Artifacts: `artifacts\`

---

## 📝 Logging and Output

- 📄 **Logs**
  ```text
  %LOCALAPPDATA%\NuGetPublisher\Logs
  ```

- 📊 **Reports**
  - `NuGetReport_*.txt` inside `artifacts\`

---

## 💡 Optimization Tips

- ⏱️ **Automate Publishing** — Schedule via Task Scheduler for routine publishing  
- ✍️ **Customize Metadata** — Use the GUI or `config.json` to preload IDs, tags, versions, and descriptions  
- 📁 **Centralize Artifacts** — Redirect `artifacts\` to a shared path for collaboration and retention  

---

## ❓ Additional Assistance

The `Generate-NuGet-Package.ps1` tool is designed for customization. You can tailor the GUI behavior or use `config.json` to preload metadata. Refer to inline comments or support channels if needed.

---

## 🤝 Support & Community

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com) [![Patreon](https://img.shields.io/badge/Patreon-Support-red?style=for-the-badge&logo=patreon)](https://patreon.com/brazilianscriptguy) [![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-yellow?style=for-the-badge&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy) [![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-blue?style=for-the-badge&logo=kofi)](https://ko-fi.com/brazilianscriptguy) [![GoFundMe](https://img.shields.io/badge/GoFundMe-Donate-green?style=for-the-badge&logo=gofundme)](https://gofund.me/4599d3e6) [![WhatsApp](https://img.shields.io/badge/WhatsApp-Join%20Us-25D366?style=for-the-badge&logo=whatsapp)](https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c) [![GitHub Issues](https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/issues)

---

© 2026 Luiz Hamilton Silva. All rights reserved.
