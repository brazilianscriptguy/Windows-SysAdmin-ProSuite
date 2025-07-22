## 🔧 Core Script Library Folder

Welcome to the **Core Script Library repository**, a cornerstone of the `Windows-SysAdmin-ProSuite/Core-ScriptLibrary/` folder. This library includes two subfolders: **Modular-PS1-Scripts** and **Nuget-Package-Publisher**, both offering advanced **PowerShell automation scripts** to streamline administration, optimize workflows, and publish NuGet packages.

---

## 🌟 Key Features

- 🖥️ **User-Friendly Interfaces:** Both modules include intuitive GUIs.  
- 📝 **Detailed Logging:** All executions generate `.log` files for auditing.  
- 📤 **Exportable Outputs:** Generate `.csv` or `.txt` for reports and integrations.

---

## 📁 Introducing the Subfolders

| Subfolder | Purpose | Documentation |
|-----------|---------|----------------|
| **Modular-PS1-Scripts** | PowerShell scaffolds for automating tasks with reusable functions, GUI menus, and centralized logging. | [![Modular Scripts](https://img.shields.io/badge/Modular%20Scripts-README-blue?style=for-the-badge&logo=github)](Modular-PS1-Scripts/README.md) |
| **Nuget-Package-Publisher** | Automates creation and publishing of NuGet packages using `Generate-NuGet-Package.ps1`, complete with GUI. | [![NuGet Publisher](https://img.shields.io/badge/NuGet%20Publisher-README-blue?style=for-the-badge&logo=github)](Nuget-Package-Publisher/README.md) |

---

## 🛠️ Prerequisites

1. 🖥️ **PowerShell 5.1 or Later**  
   ```powershell
   $PSVersionTable.PSVersion
   ```

2. 🔑 **Admin Privileges**  
   Required for filesystem access, package deployment, and service configuration.

3. 🖥️ **RSAT (for Modular-PS1-Scripts)**  
   ```powershell
   Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online
   ```

4. 🔧 **NuGet CLI (for Nuget-Package-Publisher)**  
   Place `nuget.exe` in the script folder or add to PATH.  
   ```powershell
   Test-Path (Join-Path $ScriptDir "nuget.exe")
   ```

5. 🔑 **GitHub PAT (for Nuget-Package-Publisher)**  
   Requires `package:write` scope.

6. ⚙️ **Execution Policy**  
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
   ```

---

## 🚀 Getting Started

```bash
git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
```

1. **Navigate to Core Script Library:**  
   `Windows-SysAdmin-ProSuite/Core-ScriptLibrary/`

2. **Review Documentation:**  
   Each subfolder has a detailed `README.md`.

3. **Run the Scripts:**  
   ```powershell
   .\ScriptName.ps1
   ```

4. **Review Logs and Outputs:**  
   - Logs (`.log`) in script directory or `%LOCALAPPDATA%\NuGetPublisher\Logs`  
   - Artifacts in `artifacts` folder (NuGet)  
   - Reports in `.csv` or `.txt` formats

---

## 📝 Logging and Reporting

- **Logs:**  
  - `Modular-PS1-Scripts`: local `.log` files  
  - `Nuget-Package-Publisher`: `%LOCALAPPDATA%\NuGetPublisher\Logs`

- **Reports:**  
  - `Modular-PS1-Scripts`: `.csv` exports  
  - `Nuget-Package-Publisher`: `NuGetReport_*.txt`

---

## 💡 Optimization Tips

- 🔁 **Automate Deployment:** Use Task Scheduler or remote push (Modular-PS1-Scripts)  
- 🧩 **Customize Templates:** Adapt headers and logic to your enterprise  
- 📁 **Centralize Outputs:** Store logs/reports on a shared directory  
- 📦 **Automate Publishing:** Schedule `Generate-NuGet-Package.ps1`  
- 🧾 **Custom Metadata:** Adjust `config.json` or use GUI  
- 📤 **Centralize Artifacts:** Redirect build paths to shared folders

---

## ❓ Support & Customization

The scripts in this library are designed to be modular and adaptable. For help, check the respective `README.md` files or reach out via the support channels below.

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com)
[![Patreon](https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge&logo=patreon)](https://www.patreon.com/brazilianscriptguy)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-yellow?style=for-the-badge&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20Me-blue?style=for-the-badge&logo=kofi)](https://ko-fi.com/brazilianscriptguy)
[![GoFundMe](https://img.shields.io/badge/GoFundMe-Donate-green?style=for-the-badge&logo=gofundme)](https://gofund.me/4599d3e6)
[![WhatsApp](https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge&logo=whatsapp)](https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c)
[![GitHub Issues](https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/ISSUE_TEMPLATE/CUSTOM_ISSUE_TEMPLATE.md)

---

© 2025 Luiz Hamilton. All rights reserved.
