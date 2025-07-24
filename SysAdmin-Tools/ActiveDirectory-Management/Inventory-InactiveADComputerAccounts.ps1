<#
.SYNOPSIS
    PowerShell Script for Identifying Inactive AD Computer Accounts.

.DESCRIPTION
    This script identifies inactive computer accounts within Active Directory, helping administrators 
    maintain a clean and secure directory by removing outdated accounts.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: November 8, 2024
#>

# Avoid duplicate type definition
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
    }
"@
}
[Window]::Hide()

# Import necessary modules and assemblies
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

# Set up script variables
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = 'C:\Logs-TEMP'
$logPath = Join-Path $logDir "${scriptName}.log"

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -ErrorAction SilentlyContinue
}

# Logging function
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
$form.Text = "Report Inactive Computer Accounts"
$form.Size = New-Object System.Drawing.Size(420, 300)
$form.StartPosition = "CenterScreen"

# Domain selection dropdown
$labelDomain = New-Object System.Windows.Forms.Label
$labelDomain.Location = New-Object System.Drawing.Point(10, 20)
$labelDomain.Size = New-Object System.Drawing.Size(380, 20)
$labelDomain.Text = "Select Domain FQDN:"
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

# Days input
$labelDays = New-Object System.Windows.Forms.Label
$labelDays.Location = New-Object System.Drawing.Point(10, 80)
$labelDays.Size = New-Object System.Drawing.Size(380, 20)
$labelDays.Text = "Enter number of inactivity days:"
$form.Controls.Add($labelDays)

$textboxDays = New-Object System.Windows.Forms.TextBox
$textboxDays.Location = New-Object System.Drawing.Point(10, 110)
$textboxDays.Size = New-Object System.Drawing.Size(360, 20)
$form.Controls.Add($textboxDays)

# Progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(10, 140)
$progressBar.Size = New-Object System.Drawing.Size(360, 20)
$form.Controls.Add($progressBar)

# Generate report button
$generateButton = New-Object System.Windows.Forms.Button
$generateButton.Location = New-Object System.Drawing.Point(10, 180)
$generateButton.Size = New-Object System.Drawing.Size(360, 30)
$generateButton.Text = "Generate Report"
$generateButton.Add_Click({
        $domainFQDN = $comboBoxDomain.SelectedItem
        $days = $null
        $isValidDays = [int]::TryParse($textboxDays.Text, [ref]$days)

        if (![string]::IsNullOrWhiteSpace($domainFQDN) -and $isValidDays -and $days -gt 0) {
            $progressBar.Value = 10
            $form.Refresh()

            $currentDateTime = Get-Date -Format "yyyyMMdd_HHmmss"
            $exportPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "${scriptName}_$domainFQDN-${days}_$currentDateTime.csv"

            try {
                $inactiveComputers = Search-ADAccount -ComputersOnly -AccountInactive -TimeSpan ([timespan]::FromDays($days)) -Server $domainFQDN
                $progressBar.Value = 60
                $inactiveComputers | Select-Object Name, DNSHostName, LastLogonDate | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
                $progressBar.Value = 100

                Log-Message -Message "Report generated successfully: $exportPath" -MessageType "INFO"
                [System.Windows.Forms.MessageBox]::Show(
                    "Report generated successfully:`n$exportPath",
                    "Report Successful",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
            } catch {
                Log-Message -Message "Error generating report: $_" -MessageType "ERROR"
                [System.Windows.Forms.MessageBox]::Show(
                    "An error occurred: $_",
                    "Error",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
            }
        } else {
            Log-Message -Message "Input Error: Invalid domain FQDN or inactivity days." -MessageType "WARNING"
            [System.Windows.Forms.MessageBox]::Show(
                "Please select a valid domain and number of inactivity days.",
                "Input Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
        }
    })
$form.Controls.Add($generateButton)

# Close button
$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Location = New-Object System.Drawing.Point(10, 220)
$closeButton.Size = New-Object System.Drawing.Size(360, 30)
$closeButton.Text = "Close"
$closeButton.Add_Click({ $form.Close() })
$form.Controls.Add($closeButton)

# Show the form
[void]$form.ShowDialog()

# End of script
