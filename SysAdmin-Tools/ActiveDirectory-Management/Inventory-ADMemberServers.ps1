<#
.SYNOPSIS
    PowerShell Script for Generating Reports on AD Member Servers.

.DESCRIPTION
    This script provides detailed reports on member servers within an Active Directory domain,
    simplifying server management and oversight for administrators.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: November 8, 2024
#>

# Hide PowerShell console window
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
}
"@
[Window]::Hide()

# Import necessary assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Import-Module ActiveDirectory

# Determine the script name and dynamic file paths
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logDir = if ($env:LOG_PATH -and $env:LOG_PATH -ne "") { $env:LOG_PATH } else { 'C:\Logs-TEMP' }
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -ErrorAction SilentlyContinue
}

# Logging function
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

# GUI utility functions
function Show-InfoMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Information', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Log-Message -Message "$message" -MessageType "INFO"
}

function Show-ErrorMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    Log-Message -Message "$message" -MessageType "ERROR"
}

# Function to retrieve all domain FQDNs in the forest
function Get-AllDomainFQDNs {
    try {
        $forest = Get-ADForest
        return $forest.Domains
    } catch {
        Log-Message -Message "Failed to retrieve domain FQDNs: $_" -MessageType "ERROR"
        Show-ErrorMessage "Unable to fetch domain FQDNs from the forest."
        return @()
    }
}

# GUI setup
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Generate Report of Member Servers'
$form.Size = New-Object System.Drawing.Size(400, 300)
$form.StartPosition = 'CenterScreen'

# Domain FQDN dropdown
$labelDomain = New-Object System.Windows.Forms.Label
$labelDomain.Location = New-Object System.Drawing.Point(10, 20)
$labelDomain.Size = New-Object System.Drawing.Size(380, 20)
$labelDomain.Text = 'Select the FQDN of the Domain:'
$form.Controls.Add($labelDomain)

$comboBoxDomain = New-Object System.Windows.Forms.ComboBox
$comboBoxDomain.Location = New-Object System.Drawing.Point(10, 50)
$comboBoxDomain.Size = New-Object System.Drawing.Size(360, 20)
$comboBoxDomain.DropDownStyle = 'DropDownList'
$comboBoxDomain.Items.AddRange((Get-AllDomainFQDNs))
if ($comboBoxDomain.Items.Count -gt 0) {
    $comboBoxDomain.SelectedIndex = 0
}
$form.Controls.Add($comboBoxDomain)

# Progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(10, 100)
$progressBar.Size = New-Object System.Drawing.Size(360, 20)
$form.Controls.Add($progressBar)

# Status label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(10, 130)
$statusLabel.Size = New-Object System.Drawing.Size(360, 20)
$statusLabel.Text = ''
$form.Controls.Add($statusLabel)

# Generate report button
$generateButton = New-Object System.Windows.Forms.Button
$generateButton.Location = New-Object System.Drawing.Point(10, 160)
$generateButton.Size = New-Object System.Drawing.Size(360, 30)
$generateButton.Text = 'Generate Report'
$generateButton.Add_Click({
        $domainFQDN = $comboBoxDomain.SelectedItem

        if (![string]::IsNullOrWhiteSpace($domainFQDN)) {
            $progressBar.Value = 10
            $statusLabel.Text = "Retrieving server information..."
            try {
                $sanitizedDomainFQDN = $domainFQDN -replace "\.", "_"
                $outputFilePath = "$([Environment]::GetFolderPath('MyDocuments'))\${scriptName}_${sanitizedDomainFQDN}_${timestamp}.csv"

                # Retrieve member servers
                $progressBar.Value = 50
                $servers = Get-ADComputer -Filter { OperatingSystem -Like '*Server*' } -Server $domainFQDN -Properties Name, IPv4Address, OperatingSystem, OperatingSystemVersion | Select-Object Name, IPv4Address, OperatingSystem, OperatingSystemVersion

                # Export results to CSV
                $progressBar.Value = 90
                $servers | Export-Csv -Path $outputFilePath -NoTypeInformation -Encoding UTF8

                $progressBar.Value = 100
                Show-InfoMessage "Report exported successfully to:`n$outputFilePath"
                $statusLabel.Text = "Report generated successfully."
                Log-Message -Message "Report generated and exported to $outputFilePath" -MessageType "INFO"
            } catch {
                Show-ErrorMessage "Error querying Active Directory: $_"
                Log-Message -Message "Error querying Active Directory: $_" -MessageType "ERROR"
                $progressBar.Value = 0
                $statusLabel.Text = "Error occurred during report generation."
            }
        } else {
            Show-ErrorMessage 'Please select a valid FQDN of the Domain.'
            $statusLabel.Text = 'Input Error.'
            Log-Message -Message "Invalid FQDN input by user." -MessageType "ERROR"
        }
    })
$form.Controls.Add($generateButton)

# Close button
$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Location = New-Object System.Drawing.Point(10, 200)
$closeButton.Size = New-Object System.Drawing.Size(360, 30)
$closeButton.Text = 'Close'
$closeButton.Add_Click({
        $form.Close()
    })
$form.Controls.Add($closeButton)

$form.Add_Shown({ $form.Activate() })

[void]$form.ShowDialog()

# End of script
