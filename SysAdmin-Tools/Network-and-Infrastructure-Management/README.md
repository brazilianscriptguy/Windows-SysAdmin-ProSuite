## 🌐 Network and Infrastructure Management Tools  
### DNS · DHCP · WSUS · Infrastructure Automation

![Suite](https://img.shields.io/badge/Suite-Network%20%26%20Infrastructure-0A66C2?style=for-the-badge&logo=windows&logoColor=white) ![Services](https://img.shields.io/badge/Services-DNS%20%7C%20DHCP%20%7C%20WSUS-informational?style=for-the-badge) ![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207.x-5391FE?style=for-the-badge&logo=powershell&logoColor=white) ![Focus](https://img.shields.io/badge/Focus-Availability%20%7C%20Compliance-critical?style=for-the-badge)

---

## 🧭 Overview

The **Network and Infrastructure Management** suite provides a collection of **PowerShell automation tools** focused on managing and maintaining critical Windows infrastructure services such as **DNS**, **DHCP**, **WSUS**, and core network components.

These tools are designed to help administrators ensure **service availability**, **configuration accuracy**, and **operational efficiency**, while producing **audit-ready logs and reports** suitable for enterprise and public-sector environments.

---

## 🌟 Key Features

- 🖼️ **GUI-Enabled Scripts** — User-friendly interfaces for selected tools  
- 📝 **Detailed Logging** — Structured `.log` files for traceability and troubleshooting  
- 📊 **Exportable Reports** — `.csv` outputs for reporting, documentation, and audits  
- ⚙️ **Infrastructure Automation** — Covers DHCP migration, DNS cleanup, WSUS auditing, and diagnostics  

---

## 🛠️ Prerequisites

- **⚙️ PowerShell** — Version **5.1 or later** (PowerShell 7.x supported)  
  ```powershell
  $PSVersionTable.PSVersion
  ```

- **🔑 Administrative Privileges** — Required for system-level and network configuration tasks  

- **🖥️ RSAT Tools** — Required for DNS, DHCP, and WSUS administration  
  ```powershell
  Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online
  ```

- **🔧 Execution Policy** — Session-scoped execution  
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
  ```

- **📦 Required Modules**
  - `ActiveDirectory`
  - `DnsServer`
  - `DhcpServer` (when applicable)

---

## 📄 Script Catalog (Alphabetical)

| Script Name | Description |
|------------|-------------|
| **Check-ServicesPort-Connectivity.ps1** | Tests network connectivity for service ports across target hosts |
| **Create-NewDHCPReservations.ps1** | GUI-based creation of DHCP reservations using hostname, MAC, and IP |
| **Discovery-Network-ADComputers.ps1** | Discovers AD computers, resolves IPv4 addresses, and exports results |
| **Inventory-WSUSConfigs-Tool.ps1** | Collects WSUS configuration, patch status, and repository metrics |
| **Restart-NetworkAdapter.ps1** | Safely restarts local or remote network adapters |
| **Restart-SpoolerPoolServices.ps1** | Restarts print spooler services with structured logging |
| **Retrieve-DHCPReservations.ps1** | Audits DHCP reservations and detects duplicate MAC or IP assignments |
| **Retrieve-Empty-DNSReverseLookupZone.ps1** | Identifies unused or empty reverse DNS lookup zones |
| **Retrieve-ServersDiskSpace.ps1** | Retrieves disk usage information from multiple servers |
| **Synchronize-ADComputerTime.ps1** | Forces time synchronization with domain controllers |
| **Transfer-DHCPScopes.ps1** | Transfers DHCP scopes between Windows DHCP servers |
| **Update-DNS-and-Sites-Services.ps1** | Updates DNS records and AD Sites/Subnets using DHCP data |

---

## 🚀 Usage Instructions

1. Run scripts using **Run with PowerShell** or from an **elevated PowerShell console**  
2. Provide required parameters or interact via GUI (script-dependent)  
3. Review generated outputs  

### 📂 Logs and Reports Locations

| Path | Purpose |
|------|---------|
| `C:\Scripts-LOGS\` | GPO synchronization, agents, and security tooling logs |
| `C:\Logs-TEMP\` | General-purpose, transient, and legacy script outputs |
| `%USERPROFILE%\Documents\` | CSV and exported reports for compliance, audits, and analysis |

---

## 💡 Optimization Tips

- 🔁 Schedule recurring tasks using **Task Scheduler** or orchestration tools  
- 🧠 Customize script logic to reflect enterprise policies and naming standards  
- 🗂️ Centralize logs and reports to shared storage or SIEM pipelines  

---

© 2026 Luiz Hamilton Silva. All rights reserved.
