## 📂 NuGet Package Publisher Suite

### 📝 Overview

The **NuGet Package Publisher Suite** includes a specialized PowerShell script named `Generate-NuGet-Package.ps1` that automates the creation, validation, and publication of NuGet packages to GitHub Packages. The tool includes a GUI and reusable components that streamline the publishing process for Windows administrators and developers.

- 📦 **Package Automation** — Dynamically build and publish NuGet packages  
- 🎛️ **GUI Interface** — Interactive interface for configuring metadata and execution  
- 🪵 **Detailed Logging** — Saves `.log` files with full traceability  
- 📊 **Artifact Reports** — Outputs `.txt` reports for each published package

---

## 🛠️ Prerequisites

1. ⚙️ **PowerShell Version**  
   PowerShell 5.1 or later is required.  
   ```powershell
   $PSVersionTable.PSVersion
   ```

2. 🔑 **Administrator Privileges**  
   Required for file handling and publishing rights.

3. 🔧 **NuGet CLI**  
   Download [`nuget.exe`](https://www.nuget.org/downloads) and place it in the folder or add to `PATH`.  
   ```powershell
   Test-Path (Join-Path $ScriptDir "nuget.exe")
   ```

4. 🔐 **GitHub Personal Access Token (PAT)**  
   Must include `package:write` scope for GitHub Packages publishing.

5. 🔧 **Execution Policy**  
   Enable script execution:  
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope Process
   ```

---

## 📂 Folder Structure

Recommended layout for the script under `Windows-SysAdmin-ProSuite/Core-ScriptLibrary/Nuget-Package-Publisher/`:

- `Generate-NuGet-Package.ps1` — Main script with GUI and logic  
- `config.json` (optional) — Stores metadata like ID, version, description, and PAT  
- `artifacts/` — Stores `.nupkg` files and reports like `NuGetReport_*.txt`  
- `$env:LOCALAPPDATA\NuGetPublisher\Logs/` — Logs for execution runs  
- `nuget.exe` (optional) — NuGet CLI binary, can be placed in root folder

---

## 📄 Script Description

| Script Name | Description |
|-------------|-------------|
| **Generate-NuGet-Package.ps1** | Automates NuGet packaging and publishing with GUI, config options, logging, and validation support |

---

## 🚀 Getting Started

1. **Clone the Repository**
   ```bash
   git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
   ```

2. **Navigate to the Script Folder**
   ```
   Windows-SysAdmin-ProSuite/Core-ScriptLibrary/Nuget-Package-Publisher/
   ```

3. **Install NuGet CLI**
   Download and place `nuget.exe` in the script folder or configure system PATH

4. **Set Up Folder Structure**
   Ensure `artifacts/` exists and that log directory is writable

5. **Run the Script**
   ```powershell
   .\Generate-NuGet-Package.ps1
   ```

6. **Review Logs and Output**
   - Logs: `$env:LOCALAPPDATA\NuGetPublisher\Logs`
   - Artifacts: `artifacts/` directory in root

---

## 📝 Logging and Output

- 📄 **Logs** — Execution and error logs are saved under:  
  ```text
  %LOCALAPPDATA%\NuGetPublisher\Logs
  ```

- 📊 **Reports** — Package info saved as `NuGetReport_*.txt` inside the `artifacts/` folder

---

## 💡 Optimization Tips

- ⏱️ **Automate Publishing**  
  Schedule this script via Task Scheduler for routine publishing

- ✍️ **Customize Metadata**  
  Use GUI or `config.json` to edit tags, versions, descriptions, etc.

- 📁 **Centralize Artifacts**  
  Move your `artifacts/` folder to a shared path for collaboration

---

## ❓ Additional Assistance

The `Generate-NuGet-Package.ps1` script is highly customizable. You can tailor the GUI interface or provide a `config.json` to preload metadata. Refer to inline comments or reach out for support if needed.

---

## 📬 Support and Contribution

<div align="center">

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com)
[![Patreon](https://img.shields.io/badge/Patreon-Support-red?style=for-the-badge&logo=patreon)](https://patreon.com/brazilianscriptguy)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-yellow?style=for-the-badge&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-blue?style=for-the-badge&logo=kofi)](https://ko-fi.com/brazilianscriptguy)
[![GoFundMe](https://img.shields.io/badge/GoFundMe-Donate-green?style=for-the-badge&logo=gofundme)](https://gofund.me/4599d3e6)
[![WhatsApp](https://img.shields.io/badge/WhatsApp-Join%20Us-25D366?style=for-the-badge&logo=whatsapp)](https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c)
[![GitHub Issues](https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/issues)

</div>
