<#
.SYNOPSIS
    PowerShell Script for Retrieving Last Logon Times of AD Users.

.DESCRIPTION
    This script provides insights into the last logon times of Active Directory users, 
    aiding in identifying potentially inactive accounts and improving resource management.

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

# Import necessary assemblies and modules
Add-Type -AssemblyName System.Windows.Forms
Import-Module ActiveDirectory

# Determine script name and set up logging and file paths
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -ErrorAction SilentlyContinue
}

# Logging function
function Log-Message {
    param (
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")][string]$MessageType = "INFO"
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
    param ([string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, 'Information', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Log-Message -Message "$Message" -MessageType "INFO"
}

# Function to display error messages
function Show-ErrorMessage {
    param ([string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    Log-Message -Message "$Message" -MessageType "ERROR"
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

# Function to generate the AD user last logon report
function Generate-ADUserLastLogonReport {
    param (
        [string]$DomainFQDN,
        [int]$Days
    )
    $currentDateTime = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputPath = "$([Environment]::GetFolderPath('MyDocuments'))\Report-ADUserLastLogon_${DomainFQDN}_${Days}_$currentDateTime.csv"

    try {
        Log-Message -Message "Generating report for domain $DomainFQDN for inactive users within $Days days."
        $users = Search-ADAccount -UsersOnly -AccountInactive -TimeSpan ([TimeSpan]::FromDays($Days)) -Server $DomainFQDN
        $users | Select-Object Name, SamAccountName, LastLogonDate | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
        Log-Message -Message "Report generated successfully: $outputPath" -MessageType "INFO"
        Show-InfoMessage -Message "Report generated successfully. File saved at:`n$outputPath"
        return $outputPath
    } catch {
        Log-Message -Message "Error generating report: $_" -MessageType "ERROR"
        Show-ErrorMessage -Message "An error occurred while generating the report. Check logs for details."
        return $null
    }
}

# Main GUI setup
$form = New-Object System.Windows.Forms.Form
$form.Text = 'AD User Last Logon Report'
$form.Size = New-Object System.Drawing.Size(420, 300)
$form.StartPosition = 'CenterScreen'

# Domain selection
$labelDomain = New-Object System.Windows.Forms.Label
$labelDomain.Text = 'Select Domain FQDN:'
$labelDomain.Location = New-Object System.Drawing.Point(10, 20)
$labelDomain.AutoSize = $true
$form.Controls.Add($labelDomain)

$comboBoxDomain = New-Object System.Windows.Forms.ComboBox
$comboBoxDomain.Location = New-Object System.Drawing.Point(10, 50)
$comboBoxDomain.Size = New-Object System.Drawing.Size(380, 20)
$comboBoxDomain.DropDownStyle = 'DropDownList'
$comboBoxDomain.Items.AddRange((Get-AllDomainFQDNs))
if ($comboBoxDomain.Items.Count -gt 0) {
    $comboBoxDomain.SelectedIndex = 0
}
$form.Controls.Add($comboBoxDomain)

# Days since last logon input
$labelDays = New-Object System.Windows.Forms.Label
$labelDays.Text = 'Enter number of inactivity days:'
$labelDays.Location = New-Object System.Drawing.Point(10, 90)
$labelDays.AutoSize = $true
$form.Controls.Add($labelDays)

$textBoxDays = New-Object System.Windows.Forms.TextBox
$textBoxDays.Location = New-Object System.Drawing.Point(10, 120)
$textBoxDays.Size = New-Object System.Drawing.Size(380, 20)
$form.Controls.Add($textBoxDays)

# Progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(10, 150)
$progressBar.Size = New-Object System.Drawing.Size(380, 20)
$form.Controls.Add($progressBar)

# Buttons
$buttonGenerate = New-Object System.Windows.Forms.Button
$buttonGenerate.Text = 'Generate Report'
$buttonGenerate.Location = New-Object System.Drawing.Point(10, 180)
$buttonGenerate.Size = New-Object System.Drawing.Size(180, 30)
$buttonGenerate.Add_Click({
        $domainFQDN = $comboBoxDomain.SelectedItem
        $days = $null
        $isValidDays = [int]::TryParse($textBoxDays.Text, [ref]$days)

        if (![string]::IsNullOrWhiteSpace($domainFQDN) -and $isValidDays -and $days -gt 0) {
            $progressBar.Value = 50
            $reportPath = Generate-ADUserLastLogonReport -DomainFQDN $domainFQDN -Days $days

            if ($reportPath) {
                $progressBar.Value = 100
            } else {
                $progressBar.Value = 0
            }
        } else {
            Show-ErrorMessage -Message 'Please provide a valid domain and number of days.'
        }
    })
$form.Controls.Add($buttonGenerate)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Text = 'Close'
$buttonClose.Location = New-Object System.Drawing.Point(210, 180)
$buttonClose.Size = New-Object System.Drawing.Size(180, 30)
$buttonClose.Add_Click({ $form.Close() })
$form.Controls.Add($buttonClose)

# Display the form
$form.ShowDialog()

# End of script
