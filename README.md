<h1 align="center">🚀 Complete PowerShell and VBScript Toolkit</h1>
<h3 align="center">ITSM Compliance for Windows 10/11 and Windows Server 2019/2022</h3>

<p align="center">
  <em>Enterprise-grade scripts with GUI, automation, audit logging, and secure ITSM templates.</em>
</p>

---

<p align="justify">
Welcome to the <strong>PowerShell Toolset for Windows Server Administration and VBScript Repository</strong> — a curated collection of scripts developed by <code>@brazilianscriptguy</code> for advanced systems administration. This toolkit centralizes automation, security, and forensic readiness for domain-joined environments, aligning with industry-grade ITSM and compliance standards.
</p>

<p align="justify">
✨ All scripts offer intuitive <strong>graphical user interfaces (GUI)</strong>, generate structured <code>.log</code> files, and many export data as <code>.csv</code> reports for auditing and dashboards.
</p>

---

## 🛠️ Repository Structure

Each folder serves a distinct operational area:

| Folder | Badge | Purpose |
|--------|-------|---------|
| [`BlueTeam-Tools`](./BlueTeam-Tools) | ![BlueTeam](https://img.shields.io/badge/Forensics-orange?style=flat-square&logo=security) | Incident response, memory capture, log triage |
| [`Core-ScriptLibrary`](./Core-ScriptLibrary) | ![Core](https://img.shields.io/badge/ScriptLibrary-red?style=flat-square&logo=visualstudiocode) | Reusable scriptlets, templates, and utility classes |
| [`ITSM-Templates-SVR`](./ITSM-Templates-SVR) | ![Server](https://img.shields.io/badge/SVR%20Hardening-purple?style=flat-square&logo=server) | Windows Server roles, GPOs, hardening |
| [`ITSM-Templates-WKS`](./ITSM-Templates-WKS) | ![WKS](https://img.shields.io/badge/WKS%20Templates-green?style=flat-square&logo=windows) | Workstation compliance, layout, cleanup |
| [`SysAdmin-Tools`](./SysAdmin-Tools) | ![SysAdmin](https://img.shields.io/badge/SysAdmin-blue?style=flat-square&logo=windows) | AD, DHCP, WSUS, CA, GPO automation |

---

## 💻 Core Features

- ![GUI](https://img.shields.io/badge/GUI--Based-yellow?style=flat-square&logo=windowsterminal) **Intuitive Interfaces**  
  Easily navigable tools designed for admins, with graphical controls and dialogs.

- ![Logging](https://img.shields.io/badge/Structured%20Logging-orange?style=flat-square&logo=notepadplusplus) **Traceable Logs**  
  Every script generates structured `.log` files and `.csv` exports.

- ![Automation](https://img.shields.io/badge/PowerShell%20Modules-red?style=flat-square&logo=powershell) **PowerShell-Driven**  
  Modular and scalable functions with reusability in mind.

- ![Hardening](https://img.shields.io/badge/Security%20Hardening-purple?style=flat-square&logo=windowsdefender) **Compliance & Security**  
  Hardened scripts to apply GPO baselines, DNS lockdowns, WSUS cleanup, etc.

- ![Forensics](https://img.shields.io/badge/Forensics--Ready-orange?style=flat-square&logo=cyberdefenders) **Incident Response**  
  Memory dumps, credential audits, and unauthorized access detection modules.

---

## 🚀 Getting Started

1. **Clone this repository:**
   ```bash
   git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
   ```

2. **Explore the folders:**
   - `BlueTeam-Tools/`
   - `Core-ScriptLibrary/`
   - `ITSM-Templates-SVR/`
   - `ITSM-Templates-WKS/`
   - `SysAdmin-Tools/`

3. **Run a script:**
   - **PowerShell (.ps1):** Right-click → *Run with PowerShell*
   - **VBScript (.vbs):** Right-click → *Open with Command Prompt*

4. **Check logs and exports:**
   - `C:\Logs-TEMP\`
   - `C:\ITSM-Logs-WKS\` or `C:\ITSM-Logs-SVR\`
   - Look for `.log` and `.csv` files

---

## 📦 Automation & CI/CD Status

[![Latest Release](https://img.shields.io/github/v/release/brazilianscriptguy/Windows-SysAdmin-ProSuite?style=for-the-badge&label=Latest%20Release&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/releases)
[![Release Workflow](https://img.shields.io/github/actions/workflow/status/brazilianscriptguy/Windows-SysAdmin-ProSuite/build-github-releases.yml?branch=main&label=Build%20&%20Zip&style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/actions/workflows/build-github-releases.yml)
[![NuGet Publishing](https://img.shields.io/github/actions/workflow/status/brazilianscriptguy/Windows-SysAdmin-ProSuite/push-github-nuget-packages.yml?branch=main&label=NuGet%20Packages&style=for-the-badge&logo=nuget)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/actions/workflows/push-github-nuget-packages.yml)
[![Changelog Automation](https://img.shields.io/github/actions/workflow/status/brazilianscriptguy/Windows-SysAdmin-ProSuite/update-toolset-changelog.yml?branch=main&label=Changelog&style=for-the-badge&logo=gitbook)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/actions/workflows/update-toolset-changelog.yml)
[![Linting](https://img.shields.io/github/actions/workflow/status/brazilianscriptguy/Windows-SysAdmin-ProSuite/lint-powershell.yml?branch=main&label=PSScriptAnalyzer&style=for-the-badge&logo=powershell)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/actions/workflows/lint-powershell.yml)
![Scripts Count](https://img.shields.io/badge/Scripts%20Total-142-blue?style=for-the-badge&logo=windows)
[![Download ZIP](https://img.shields.io/badge/⬇️%20Download-Full%20Repo%20ZIP-blue?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/releases)

---

## 🤝 Support This Project

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com)
[![Patreon](https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge&logo=patreon)](https://www.patreon.com/brazilianscriptguy)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-yellow?style=for-the-badge&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-blue?style=for-the-badge&logo=kofi)](https://ko-fi.com/brazilianscriptguy)
[![GoFundMe](https://img.shields.io/badge/GoFundMe-green?style=for-the-badge&logo=gofundme)](https://www.gofundme.com/f/brazilianscriptguy)
[![WhatsApp](https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge&logo=whatsapp)](https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c)

---

<p align="center"><strong>💼 Thank you for using <code>Windows-SysAdmin-ProSuite</code> — your all-in-one platform for secure automation.</strong></p>

<p align="center">© 2025 Luiz Hamilton. All rights reserved.</p>
