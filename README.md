# Complete PowerShell and VBScript Toolkit for Managing Windows Servers and Workstations with ITSM Compliance on Windows 10/11 Workstations and Windows Server 2019/2022

Welcome to the **PowerShell Toolset for Windows Server Administration and VBScript Repository**—a meticulously curated collection of scripts tailored for advanced Windows Server and Windows 10/11 workstation management. Developed by `@brazilianscriptguy`, this repository offers a comprehensive suite of tools designed to **streamline Windows Server administration, including Active Directory functions**, while optimizing workstation management, configuration, and ITSM compliance across both servers and workstations.

✨ **All scripts include a graphical user interface (GUI)** to simplify user interaction. Each script **generates detailed `.log` files** for operational tracking, with some scripts also **exporting results to `.csv` files** for seamless integration with reporting tools. This collection ensures Windows Server and workstation management is more intuitive, efficient, and user-friendly.

--- 

# 🛠️ Introduction

This repository is a powerful collection of tools and scripts meticulously crafted to streamline the management of Windows Server environments and Windows 10/11 workstations. Whether you're optimizing system performance, enhancing security, or simplifying administrative workflows, the tools in the **BlueTeam-Tools**, **Core-ScriptLibrary**, **ITSM-Templates-SVR**, **ITSM-Templates-WKS**, and **SysAdmin-Tools** folders are designed to meet your IT management needs effectively and efficiently.

---

## 🚀 Features

This repository is organized into five comprehensive sections, each focusing on distinct aspects of IT management and compliance:

### **1. BlueTeam-Tools**
   - Specialized tools for forensic analysis and system monitoring, empowering Blue Teams to detect, analyze, and resolve security threats effectively.
   - **Integration with Log Parser Utility** enhances log querying and in-depth data analysis, supporting audits, threat detection, and forensic investigations.
   - Modules for **incident response**, enabling administrators to gather critical information during and after security breaches.

### **2. Core-ScriptLibrary**
   - Foundational PowerShell scripts for creating and managing **custom script libraries** with dynamic user interfaces, automation, and core functionality.
   - Templates for automating routine administrative tasks, enabling faster and more efficient IT operations.
   - Perfect for developing complex **PowerShell-based solutions** tailored to specific IT environments.

### **3. ITSM-Templates-SVR**
   - Templates and scripts focused on **IT Service Management (ITSM)** for servers, emphasizing hardening, configuration, and automation.
   - Includes GPO management, deployment strategies, and compliance tools to ensure high-security standards and operational excellence.

### **4. ITSM-Templates-WKS**
   - Templates and scripts for **ITSM compliance** on workstations, emphasizing hardening, configuration, and automation.
   - Includes deployment strategies and audit tools to maintain ITSM compliance across Windows 10/11 environments.

### **5. SysAdmin-Tools**
   - Automates essential **Active Directory management tasks**, such as user, group, and OU administration.  
   - Includes tools for **Group Policy Object (GPO) management**, including exporting, importing, and applying templates through scripts like `Export-n-Import-GPOsTool.ps1`.  
   - Provides scripts for **network and infrastructure management**, including DNS, DHCP, and site synchronization.  
   - Contains **security and process optimization tools**, such as certificate cleanup and automated optimization scripts.  
   - Supports **system configuration and deployment** with tools for application management, deployment, and uninstallation.  
   - Streamlines operations across servers and workstations, ensuring consistency, security, and compliance within Windows environments.

---

## 🌟 Key Highlights

- **GUI-Driven Solutions**: Intuitive graphical interfaces make these tools accessible to users at all skill levels.
- **Advanced Logging**: Detailed `.log` files provide operational transparency, and `.csv` files offer actionable reporting.
- **Customizable**: Scripts are highly configurable, allowing adjustments to parameters, paths, and execution behaviors to align with your organization's specific requirements.

---

## 💻 Getting Started

### Steps to Begin:

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
   ```

2. **Organize the Scripts**: Arrange the scripts into directories for easier access and management.

3. **Explore the Folders**:
   - `BlueTeam-Tools`
   - `Core-ScriptLibrary`
   - `ITSM-Templates-SVR`
   - `ITSM-Templates-WKS`
   - `SysAdmin-Tools`

4. **Run the Scripts**:
   - **PowerShell Scripts (`.ps1`)**: Right-click and select `Run with PowerShell`.
   - **VBScript Files (`.vbs`)**: Right-click and select `Run with Command Prompt`.

---

## 🛠️ Prerequisites

Ensure your environment meets the following requirements before running these scripts:

- **PowerShell Version**: Version 5.1 or later.
- **Administrative Rights**: Most scripts require elevated permissions.
- **RSAT Tools**: Install `Remote Server Administration Tools (RSAT)` for managing Active Directory and other server roles.
- **Log Parser Utility**: Download and install [Microsoft Log Parser 2.2](https://www.microsoft.com/en-us/download/details.aspx?id=24659) for enhanced log analysis in **BlueTeam-Tools**.
- **ITSM-Templates-WKS**: Ensure workstations are running **Windows 10 (1507 or later)** or **Windows 11**.

---

## 🔧 Installation Guides

### **Installing RSAT on Windows 10/11**

1. Navigate to **Settings** > **Apps** > **Optional Features**.  
2. Click **Add a Feature** and search for `RSAT`.  
3. Install the required tools, such as Active Directory, DNS, and DHCP management utilities.

### **Installing Log Parser Utility**

1. **Download**: Visit the [Log Parser page](https://www.microsoft.com/en-us/download/details.aspx?id=24659).  
2. **Install**: Run the `.msi` installer and complete the setup wizard.  
3. **Verify**: Run `LogParser.exe` in Command Prompt to confirm installation.  
4. **Optional PATH Setup**: Add the installation path (e.g., `C:\Program Files (x86)\Log Parser 2.2\`) to your system’s PATH for easier access.

---

## ⚙️ Customization

Tailor the scripts to suit your specific IT environment:

- **Configuration Files**: Modify the provided configuration files to customize script behaviors.  
- **Script Parameters**: Adjust parameters such as AD OU paths, domain targets, and compliance rules to meet organizational policies.

---

## 🤝 Support and Contributions

For support or to report issues, contact via [email](mailto:luizhamilton.lhr@gmail.com) or join the [Windows-SysAdmin-ProSuite WhatsApp channel](https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c).  

Support the project on [Patreon](https://patreon.com/brazilianscriptguy) to access exclusive content and updates.  

Stay informed about updates and releases at the [Windows-SysAdmin-ProSuite Release](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/releases/tag/Windows-SysAdmin-ProSuite).

---

Thank you for choosing the **Windows-SysAdmin-ProSuite** to enhance your IT administration workflow. These tools are crafted to boost your productivity and improve system efficiency. 
