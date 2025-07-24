## 🌐 Network and Infrastructure Management Tools

### 📝 Overview

The **Network and Infrastructure Management** folder provides a set of **PowerShell scripts** that automate and streamline administrative tasks related to network services such as **DNS, DHCP, WSUS**, and **infrastructure diagnostics**. These tools help IT administrators ensure service availability, accurate configurations, and efficient operations.

### 🔑 Key Features

- **User-Friendly GUI**: Intuitive interfaces for selected scripts to simplify execution and data input.  
- **Detailed Logging**: Generates `.log` files to assist with execution traceability and troubleshooting.  
- **Exportable Reports**: Provides `.csv` outputs for reporting, documentation, and audits.  
- **Automated Infrastructure Tasks**: Scripts cover use cases like DHCP migration, DNS cleanup, WSUS audits, and more.

---

## 🛠️ Prerequisites

1. **⚙️ PowerShell**
   - Ensure **PowerShell 5.1 or later** is installed and enabled.
   - Check version:
     ```powershell
     $PSVersionTable.PSVersion
     ```
2. **🔑 Administrator Privileges**  
   Most scripts require elevated permissions to access system-level and network configurations.

3. **🖥️ Remote Server Administration Tools (RSAT)**  
   Install RSAT features to support DNS, DHCP, and WSUS roles:
   ```powershell
   Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online
   ```

4. **⚙️ Execution Policy**  
   Allow script execution in the current session:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
   ```

5. **Required Modules**
   - `ActiveDirectory`
   - `DNSServer`

---

## 📄 Script Descriptions (Alphabetical Order)

| **Script Name**                            | **Description**                                                                 |
|-------------------------------------------|-----------------------------------------------------------------------------|
| **Check-ServicesPort-Connectivity.ps1**   | Verifies connectivity of service ports across endpoints.                   |
| **Create-NewDHCPReservations.ps1**        | Creates DHCP reservations via GUI input for hostname, MAC, and IP.         |
| **Inventory-WSUSConfigs-Tool.ps1**        | Collects WSUS stats, patch activity, and repo size.                        |
| **Restart-NetworkAdapter.ps1**            | Restarts local or remote network adapters.                                 |
| **Restart-SpoolerPoolServices.ps1**       | Restarts print services with logging.                                      |
| **Retrieve-DHCPReservations.ps1**         | Exports DHCP reservations; supports filtering.                             |
| **Retrieve-Empty-DNSReverseLookupZone.ps1**| Detects and lists unused reverse DNS zones.                                |
| **Retrieve-ServersDiskSpace.ps1**         | Queries disk usage across multiple servers.                                |
| **Synchronize-ADComputerTime.ps1**        | Forces time sync from computers to domain controller.                      |
| **Transfer-DHCPScopes.ps1**               | Transfers DHCP scopes between servers.                                     |
| **Update-DNS-and-Sites-Services.ps1**     | Updates DNS and Sites/Subnets based on DHCP data.                          |

---

## 🚀 Usage Instructions

1. **Run the Script**: Right-click the `.ps1` file → _Run with PowerShell_  
2. **Provide Inputs**: Enter data via GUI or prompts  
3. **Review Outputs**: Logs and `.csv` files are saved to default directories

---

## 📝 Logging and Output

- **📄 Logs**: `.log` files at `C:\Logs-TEMP` or `C:\ITSM-Logs-WKS`  
- **📊 Reports**: Exported `.csv` files for documentation and audits

---

## 💡 Tips for Optimization

- **🗓️ Automate Execution**: Schedule recurring tasks using Task Scheduler  
- **🧠 Customize Filters**: Adapt script logic for enterprise policies  
- **📁 Centralize Output**: Store results in shared folders or log systems
