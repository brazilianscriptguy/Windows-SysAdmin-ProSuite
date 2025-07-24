<#
.SYNOPSIS
    PowerShell Script for Generating an Inventory of AD Domain Computers.

.DESCRIPTION
    This script generates an inventory of all computers within a specified Active Directory 
    (AD) domain, aiding in asset management and tracking.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: November 8, 2024
#>

# Hide the PowerShell console window
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() {
        var handle = GetConsoleWindow();
        ShowWindow(handle, 0); // 0 = SW_HIDE
    }
    public static void Show() {
        var handle = GetConsoleWindow();
        ShowWindow(handle, 5); // 5 = SW_SHOW
    }
}
"@
[Window]::Hide()

# Load necessary assemblies for GUI
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Import-Module ActiveDirectory

# Determine script name and set up file paths dynamically
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

# Set log and CSV paths, allowing dynamic configuration or fallback to defaults
$logDir = if ($env:LOG_PATH -and $env:LOG_PATH -ne "") { $env:LOG_PATH } else { 'C:\Logs-TEMP' }
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -ErrorAction SilentlyContinue
}

# Enhanced logging function
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG", "CRITICAL")]
        [string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$MessageType] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Host "Failed to write to log: $_"
    }
}

# Function to display informational messages
function Show-InfoMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Information', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Log-Message -Message "Info: $message" -MessageType "INFO"
}

# Function to display error messages
function Show-ErrorMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    Log-Message -Message "Error: $message" -MessageType "ERROR"
}

# Function to retrieve all domain FQDNs in the forest
function Get-AllDomainFQDNs {
    try {
        $forest = Get-ADForest
        return $forest.Domains
    } catch {
        Log-Message "Failed to retrieve domain FQDNs: $_" -MessageType "ERROR"
        Show-ErrorMessage "Unable to fetch domain FQDNs from the forest."
        return @()
    }
}

# Function to resolve domain from DistinguishedName and check connectivity
function Get-DomainController {
    param (
        [string]$distinguishedName
    )
    if ($distinguishedName -match '(DC=[^,]+(,DC=[^,]+)+)$') {
        $domain = ($matches[1] -replace 'DC=', '') -replace ',', '.'
        try {
            # Test connectivity to the domain
            $ping = Test-Connection -ComputerName $domain -Count 1 -ErrorAction SilentlyContinue
            if ($ping) {
                return $domain
            } else {
                throw "Domain controller for '${domain}' is unreachable."
            }
        } catch {
            Log-Message "Failed to resolve domain controller for '${domain}': $_" -MessageType "ERROR"
            return $null
        }
    } else {
        Log-Message "Unable to extract domain from DistinguishedName: '${distinguishedName}'" -MessageType "ERROR"
        return $null
    }
}

# Function to retrieve the FQDN of the current domain
function Get-DomainFQDN {
    try {
        $ComputerSystem = Get-WmiObject -Class Win32_ComputerSystem
        $Domain = $ComputerSystem.Domain
        if (-not $Domain) {
            throw "No domain information found."
        }
        return $Domain
    } catch {
        Log-Message -Message "Unable to fetch FQDN automatically: $_" -MessageType "ERROR"
        Show-ErrorMessage "Unable to fetch FQDN automatically."
        return ""
    }
}

# Retrieve the FQDN of the current domain
$currentDomainFQDN = Get-DomainFQDN

# GUI setup
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Report of Domain Computers'
$form.Size = New-Object System.Drawing.Size(420, 300)
$form.StartPosition = 'CenterScreen'

# Domain FQDN label and dropdown
$labelDomain = New-Object System.Windows.Forms.Label
$labelDomain.Location = New-Object System.Drawing.Point(10, 20)
$labelDomain.Size = New-Object System.Drawing.Size(380, 20)
$labelDomain.Text = 'Select Domain FQDN:'
$form.Controls.Add($labelDomain)

$comboBoxDomain = New-Object System.Windows.Forms.ComboBox
$comboBoxDomain.Location = New-Object System.Drawing.Point(10, 40)
$comboBoxDomain.Size = New-Object System.Drawing.Size(380, 20)
$comboBoxDomain.DropDownStyle = 'DropDownList'
$comboBoxDomain.Items.AddRange((Get-AllDomainFQDNs))
if ($comboBoxDomain.Items.Count -gt 0) {
    $comboBoxDomain.SelectedIndex = 0
}
$form.Controls.Add($comboBoxDomain)

# Status label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(10, 120)
$statusLabel.Size = New-Object System.Drawing.Size(380, 20)
$statusLabel.Text = ''
$form.Controls.Add($statusLabel)

# Progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(10, 90)
$progressBar.Size = New-Object System.Drawing.Size(380, 20)
$form.Controls.Add($progressBar)

# Generate report button
$generateButton = New-Object System.Windows.Forms.Button
$generateButton.Location = New-Object System.Drawing.Point(10, 150)
$generateButton.Size = New-Object System.Drawing.Size(180, 30)
$generateButton.Text = 'Generate Report'
$generateButton.Add_Click({
        $domainFQDN = $comboBoxDomain.SelectedItem

        if (![string]::IsNullOrWhiteSpace($domainFQDN)) {
            try {
                $progressBar.Value = 10
                $statusLabel.Text = "Retrieving domain information..."
                $sanitizedDomainFQDN = $domainFQDN -replace "\.", "_"
                $outputFile = "$([Environment]::GetFolderPath('MyDocuments'))\${scriptName}_${sanitizedDomainFQDN}_$timestamp.csv"

                # Retrieve domain controllers
                $progressBar.Value = 40
                $statusLabel.Text = "Retrieving Domain Controllers..."
                $domainControllers = Get-ADComputer -Filter { (OperatingSystem -Like '*Server*') -and (IsDomainController -eq $true) } -Server $domainFQDN -Properties Name, OperatingSystem, OperatingSystemVersion | Select-Object Name, OperatingSystem, OperatingSystemVersion

                # Retrieve domain computers
                $progressBar.Value = 70
                $statusLabel.Text = "Retrieving Domain Computers..."
                $domainComputers = Get-ADComputer -Filter { OperatingSystem -NotLike '*Server*' } -Server $domainFQDN -Properties Name, OperatingSystem, OperatingSystemVersion | Select-Object Name, OperatingSystem, OperatingSystemVersion

                # Export results to CSV
                $progressBar.Value = 90
                $statusLabel.Text = "Exporting to CSV..."
                $result = @($domainControllers; $domainComputers)
                $result | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

                $progressBar.Value = 100
                Show-InfoMessage "Computers exported to `n$outputFile"
                $statusLabel.Text = "Report generated successfully."
                Log-Message -Message "Report generated successfully: $outputFile" -MessageType "INFO"
            } catch {
                Show-ErrorMessage "Error querying Active Directory: $($_.Exception.Message)"
                $statusLabel.Text = "An error occurred."
                Log-Message -Message "Error querying Active Directory: $($_.Exception.Message)" -MessageType "ERROR"
                $progressBar.Value = 0
            }
        } else {
            Show-ErrorMessage 'Please select a valid FQDN of the Domain.'
            $statusLabel.Text = 'Input Error.'
            Log-Message -Message "Input Error: Invalid FQDN." -MessageType "ERROR"
        }
    })
$form.Controls.Add($generateButton)

# Close button
$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Location = New-Object System.Drawing.Point(210, 150)
$closeButton.Size = New-Object System.Drawing.Size(180, 30)
$closeButton.Text = 'Close'
$closeButton.Add_Click({
        $form.Close()
    })
$form.Controls.Add($closeButton)

$form.Add_Shown({ $form.Activate() })

[void]$form.ShowDialog()

# End of script
