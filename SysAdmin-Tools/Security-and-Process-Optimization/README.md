## 🛡️ Security and Process Optimization Tools

### 📝 Overview

The **Security and Process Optimization** folder includes a refined suite of **PowerShell scripts** to improve certificate hygiene, file structure compliance, licensing visibility, and privileged access control. These tools enable safe automation of sensitive operations while reducing manual administrative overhead and enhancing security posture.

### 🔑 Key Features

- **Certificate Management**: Clean expired certs and organize shared certificate repositories  
- **Access and Compliance Audits**: Retrieve product keys, elevated accounts, shared folders, and software lists  
- **Storage and File Optimization**: Shorten overly long file names and clean up aged/empty files  
- **Safe Offboarding**: Unjoin and clean computer metadata from AD

---

## 🛠️ Prerequisites

1. **⚙️ PowerShell**
   - Requires PowerShell 5.1 or newer
   - Check version:
     ```powershell
     $PSVersionTable.PSVersion
     ```
2. **🔑 Administrator Access**  
   Most scripts require elevated permissions, especially those accessing system certificates, disk, registry, or AD

3. **📂 Execution Policy**  
   Allow script execution:
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope Process
   ```

---

## 📄 Script Descriptions (Alphabetical Order)

| **Script Name**                                 | **Description**                                                                 |
|-------------------------------------------------|-----------------------------------------------------------------------------|
| **Check-ServicesPort-Connectivity.ps1**         | Checks real-time connectivity status of specified service ports with logs  |
| **Cleanup-CertificateAuthority-Tool.ps1**       | Removes expired certificate data from CA servers                           |
| **Cleanup-Repository-ExpiredCertificates-Tool.ps1** | Scans shared repos and deletes expired certificates                    |
| **Initiate-MultipleRDPSessions.ps1**            | Launches multiple RDP sessions on supported systems                        |
| **Organize-CERTs-Repository.ps1**               | Organizes SSL/TLS certs by issuer or expiration                           |
| **Purge-ExpiredInstalledCertificates-Tool.ps1**  | Cleans expired certificates from local machine store                       |
| **Purge-ExpiredInstalledCertificates-viaGPO.ps1**| GPO-compatible cleanup of expired certs across domain computers            |
| **Remove-EmptyFiles-or-DateRange.ps1**          | Deletes empty/old files for storage hygiene                                |
| **Retrieve-Windows-ProductKey.ps1**             | Extracts local Windows product key for auditing                           |
| **Shorten-LongFileNames-Tool.ps1**              | Shortens long file paths to avoid sync/backup issues                      |
| **Unjoin-ADComputer-and-Cleanup.ps1**           | Unjoins machine from AD and cleans DNS, metadata, resets to Workgroup     |

---

## 🚀 Usage Instructions

1. **Run the Script**: Right-click and select _Run with PowerShell_ or launch via elevated shell  
2. **Provide Inputs**: Use input prompts or set parameters within the script  
3. **Review Results**: Logs and reports saved in `C:\Logs-TEMP` or a custom path

---

## 📝 Logging and Output

- **📄 Logs**: Step-by-step `.log` files saved locally  
- **📊 Reports**: Where applicable, `.csv` exports for audits or inventory

---

## 💡 Tips for Optimization

- **Use GPO-Compatible Scripts**: Automate cleanup actions domain-wide  
- **Schedule Periodic Cleanup**: Use Task Scheduler for unattended tasks  
- **Structure Repositories**: Organize certificate/files to reduce risk
