<#
.SYNOPSIS
    PowerShell Script for Listing AD Users with Non-Expiring Passwords.

.DESCRIPTION
    This script lists Active Directory users with non-expiring passwords, helping administrators 
    enforce password expiration policies and improve security.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: November 8, 2024
#>

# Check if the type 'Window' already exists to avoid redefinition errors
if (-not ([System.Management.Automation.PSTypeName]'Window').Type) {
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class Window {
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll", SetLastError = true)]
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
}
[Window]::Hide()

# Import Necessary Modules
Add-Type -AssemblyName System.Windows.Forms
Import-Module ActiveDirectory -ErrorAction Stop

# Check if the Active Directory module is available
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Active Directory module is not available.",
        "Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    return
}

# Define script variables
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = 'C:\Logs-TEMP'
$logPath = Join-Path $logDir "${scriptName}.log"

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -ErrorAction SilentlyContinue
}

# Enhanced logging function
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR")]
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

# Function to retrieve all domain FQDNs in the forest
function Get-AllDomainFQDNs {
    try {
        $forest = Get-ADForest
        return $forest.Domains
    } catch {
        Log-Message -Message "Failed to retrieve domain FQDNs: $_" -MessageType "ERROR"
        return @()
    }
}

# GUI setup
$form = New-Object System.Windows.Forms.Form
$form.Text = "Export AD Users with Non-Expiring Passwords"
$form.Size = New-Object System.Drawing.Size(400, 300)
$form.StartPosition = "CenterScreen"

# Domain FQDN dropdown
$labelDomain = New-Object System.Windows.Forms.Label
$labelDomain.Location = New-Object System.Drawing.Point(10, 20)
$labelDomain.Size = New-Object System.Drawing.Size(380, 20)
$labelDomain.Text = "Select the Domain FQDN:"
$form.Controls.Add($labelDomain)

$comboBoxDomain = New-Object System.Windows.Forms.ComboBox
$comboBoxDomain.Location = New-Object System.Drawing.Point(10, 50)
$comboBoxDomain.Size = New-Object System.Drawing.Size(360, 20)
$comboBoxDomain.DropDownStyle = 'DropDownList'
$domains = Get-AllDomainFQDNs
if ($domains.Count -gt 0) {
    $comboBoxDomain.Items.AddRange($domains)
    $comboBoxDomain.SelectedIndex = 0
}
$form.Controls.Add($comboBoxDomain)

# Export button
$exportButton = New-Object System.Windows.Forms.Button
$exportButton.Location = New-Object System.Drawing.Point(10, 100)
$exportButton.Size = New-Object System.Drawing.Size(360, 30)
$exportButton.Text = "Export to CSV"
$exportButton.Add_Click({
        $domainFQDN = $comboBoxDomain.SelectedItem
        if (![string]::IsNullOrWhiteSpace($domainFQDN)) {
            try {
                $csvPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "${scriptName}-${domainFQDN}-${timestamp}.csv"

                $neverExpireUsers = Get-ADUser -Filter { PasswordNeverExpires -eq $true } -Properties PasswordNeverExpires -Server $domainFQDN |
                    Select-Object Name, SamAccountName, DistinguishedName

                if ($neverExpireUsers.Count -gt 0) {
                    $neverExpireUsers | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
                    Log-Message -Message "Report exported to: $csvPath" -MessageType "INFO"
                    [System.Windows.Forms.MessageBox]::Show(
                        "Report exported to:`n$csvPath",
                        "Export Successful",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Information
                    )
                } else {
                    Log-Message -Message "No users with 'Password Never Expires' found in $domainFQDN." -MessageType "INFO"
                    [System.Windows.Forms.MessageBox]::Show(
                        "No users with 'Password Never Expires' found in $domainFQDN.",
                        "No Data Found",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Information
                    )
                }
            } catch {
                Log-Message -Message "An error occurred during export: $_" -MessageType "ERROR"
                [System.Windows.Forms.MessageBox]::Show(
                    "An error occurred: $_",
                    "Error",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
            }
        } else {
            Log-Message -Message "Input Error: Domain FQDN is empty or invalid." -MessageType "WARNING"
            [System.Windows.Forms.MessageBox]::Show(
                "Please select a valid domain FQDN.",
                "Input Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
        }
    })
$form.Controls.Add($exportButton)

# Close button
$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Location = New-Object System.Drawing.Point(10, 150)
$closeButton.Size = New-Object System.Drawing.Size(360, 30)
$closeButton.Text = "Close"
$closeButton.Add_Click({
        $form.Close()
    })
$form.Controls.Add($closeButton)

# Show the GUI
[void]$form.ShowDialog()

# End of script
