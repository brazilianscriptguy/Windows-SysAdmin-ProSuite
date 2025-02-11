<#
.SYNOPSIS
    PowerShell Script for Verifying Service Port Connectivity in Real-Time.

.DESCRIPTION
    This script checks the connectivity of specific service ports in real-time, ensuring 
    that critical network services are reachable and configured correctly. It helps to 
    maintain service availability and troubleshooting connectivity issues.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: February 11, 2025
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

# Import necessary libraries for GUI
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Determine the script name and set up logging path
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    $null = New-Item -Path $logDir -ItemType Directory -ErrorAction SilentlyContinue
    if (-not (Test-Path $logDir)) {
        Write-Error "Failed to create log directory at $logDir. Logging will not be possible."
        return
    }
}

# Enhanced logging function
function Log-Message {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [Parameter(Mandatory=$false)]
        [string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$MessageType] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Show-ErrorMessage "Failed to write to log: $_"
    }
}

# Function to display error messages
function Show-ErrorMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    Log-Message "Error: $message" -MessageType "ERROR"
}

# Function to display informational messages
function Show-InfoMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Information', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Log-Message "Info: $message" -MessageType "INFO"
}

# Define services and ports to test
$services = @(
    [PSCustomObject]@{ Name = "AD Replication - Ports: 135"; Ports = "135"; Optional = $false },
    [PSCustomObject]@{ Name = "AD Web Services - Ports: 9389"; Ports = "9389"; Optional = $false },
    [PSCustomObject]@{ Name = "DFS Namespace and DFS Replication - Ports: 135, 445, 80, 443"; Ports = "135,445,80,443"; Optional = $false },
    [PSCustomObject]@{ Name = "DFSR (SYSVOL Replication) - RPC - Ports: 5722"; Ports = "5722"; Optional = $false },
    [PSCustomObject]@{ Name = "DHCP - Ports: 67, 68"; Ports = "67,68"; Optional = $false },
    [PSCustomObject]@{ Name = "Direct Printing - Ports: 9100"; Ports = "9100"; Optional = $false },
    [PSCustomObject]@{ Name = "DNS - Ports: 53"; Ports = "53"; Optional = $false },
    [PSCustomObject]@{ Name = "ElasticSearch - Ports: 9200, 9300"; Ports = "9200,9300"; Optional = $true },
    [PSCustomObject]@{ Name = "Exchange Services - Ports: 25, 587, 110, 995, 143, 993, 80, 443"; Ports = "25,587,110,995,143,993,80,443"; Optional = $true },
    [PSCustomObject]@{ Name = "Federation Services (ADFS) - Ports: 443, 49443"; Ports = "443,49443"; Optional = $true },
    [PSCustomObject]@{ Name = "Global Catalog - Ports: 3268"; Ports = "3268"; Optional = $false },
    [PSCustomObject]@{ Name = "Global Catalog SSL - Ports: 3269"; Ports = "3269"; Optional = $false },
    [PSCustomObject]@{ Name = "HTTP - Ports: 80"; Ports = "80"; Optional = $false },
    [PSCustomObject]@{ Name = "HTTPS - Ports: 443"; Ports = "443"; Optional = $false },
    [PSCustomObject]@{ Name = "IPP - Ports: 631"; Ports = "631"; Optional = $false },
    [PSCustomObject]@{ Name = "IPSec IKE - Ports: 500"; Ports = "500"; Optional = $true },
    [PSCustomObject]@{ Name = "IPSec NAT-T - Ports: 4500"; Ports = "4500"; Optional = $true },
    [PSCustomObject]@{ Name = "Kerberos - Ports: 88"; Ports = "88"; Optional = $false },
    [PSCustomObject]@{ Name = "Kerberos Password Change - Ports: 464"; Ports = "464"; Optional = $false },
    [PSCustomObject]@{ Name = "LDAP - Ports: 389"; Ports = "389"; Optional = $false },
    [PSCustomObject]@{ Name = "LDAPS - Ports: 636"; Ports = "636"; Optional = $false },
    [PSCustomObject]@{ Name = "LPD Service - Ports: 515"; Ports = "515"; Optional = $false },
    [PSCustomObject]@{ Name = "Microsoft Identity Manager/Synchronization Service - Ports: 5725"; Ports = "5725"; Optional = $true },
    [PSCustomObject]@{ Name = "MongoDB - Ports: 27017"; Ports = "27017"; Optional = $true },
    [PSCustomObject]@{ Name = "MSSQL Analysis Services - Ports: 2383"; Ports = "2383"; Optional = $true },
    [PSCustomObject]@{ Name = "MSSQL Reporting Services - Ports: 80, 443"; Ports = "80,443"; Optional = $true },
    [PSCustomObject]@{ Name = "MySQL - Ports: 3306"; Ports = "3306"; Optional = $true },
    [PSCustomObject]@{ Name = "NetBIOS - Ports: 137, 138"; Ports = "137,138"; Optional = $false },
    [PSCustomObject]@{ Name = "Network Discovery - Ports: 3702, 5355, 1900, 5357, 5358"; Ports = "3702,5355,1900,5357,5358"; Optional = $false },
    [PSCustomObject]@{ Name = "NTP - Ports: 123"; Ports = "123"; Optional = $false },
    [PSCustomObject]@{ Name = "Oracle Database - Ports: 1521"; Ports = "1521"; Optional = $true },
    [PSCustomObject]@{ Name = "RADIUS - Ports: 1812, 1813"; Ports = "1812,1813"; Optional = $true },
    [PSCustomObject]@{ Name = "RD Gateway - Ports: 3391"; Ports = "3391"; Optional = $false },
    [PSCustomObject]@{ Name = "Redis - Ports: 6379"; Ports = "6379"; Optional = $true },
    [PSCustomObject]@{ Name = "Remote Desktop - Ports: 3389"; Ports = "3389"; Optional = $false },
    [PSCustomObject]@{ Name = "RPC - Ports: 135"; Ports = "135"; Optional = $false },
    [PSCustomObject]@{ Name = "RabbitMQ - Ports: 5672"; Ports = "5672"; Optional = $true },
    [PSCustomObject]@{ Name = "SharePoint - Ports: 80, 443"; Ports = "80,443"; Optional = $true },
    [PSCustomObject]@{ Name = "SMB - Ports: 445"; Ports = "445"; Optional = $false },
    [PSCustomObject]@{ Name = "SNMP - Ports: 161, 162"; Ports = "161, 162"; Optional = $false },
    [PSCustomObject]@{ Name = "SQL Server - Ports: 1433"; Ports = "1433"; Optional = $true },
    [PSCustomObject]@{ Name = "WinRM - HTTP - Ports: 5985"; Ports = "5985"; Optional = $true },
    [PSCustomObject]@{ Name = "WinRM - HTTPS - Ports: 5986"; Ports = "5986"; Optional = $true },
    [PSCustomObject]@{ Name = "WSUS - Ports: 8530, 8531"; Ports = "8530,8531"; Optional = $false }
)

# Initialize the main form
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Host Network Port Tester'
$form.Size = New-Object System.Drawing.Size(730, 640)
$form.StartPosition = 'CenterScreen'

# Server name label and textbox
$labelMachine = New-Object System.Windows.Forms.Label
$labelMachine.Location = New-Object System.Drawing.Point(10, 20)
$labelMachine.Size = New-Object System.Drawing.Size(160, 20)
$labelMachine.Text = 'Machine Name or IP Address:'
$form.Controls.Add($labelMachine)

# Textbox for machine name or IP with a placeholder
$textboxMachine = New-Object System.Windows.Forms.TextBox
$textboxMachine.Location = New-Object System.Drawing.Point(170, 20)
$textboxMachine.Size = New-Object System.Drawing.Size(530, 20)
$textboxMachine.ForeColor = [System.Drawing.Color]::Gray
$textboxMachine.Text = 'e.g., 172.16.20.10 or wsus-server.com'
$form.Controls.Add($textboxMachine)

# Event to clear the placeholder when the user starts typing
$textboxMachine.Add_GotFocus({
    if ($textboxMachine.ForeColor -eq [System.Drawing.Color]::Gray) {
        $textboxMachine.Text = ''
        $textboxMachine.ForeColor = [System.Drawing.Color]::Black
    }
})

# Event to restore the placeholder if the textbox is left empty
$textboxMachine.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($textboxMachine.Text)) {
        $textboxMachine.Text = 'e.g., 172.16.20.10 or wsus-server.com'
        $textboxMachine.ForeColor = [System.Drawing.Color]::Gray
    }
})

# Results textbox
$textboxResults = New-Object System.Windows.Forms.TextBox
$textboxResults.Location = New-Object System.Drawing.Point(10, 450)
$textboxResults.Size = New-Object System.Drawing.Size(690, 140)
$textboxResults.Multiline = $true
$textboxResults.ScrollBars = 'Vertical'
$form.Controls.Add($textboxResults)

# Test button
$buttonTest = New-Object System.Windows.Forms.Button
$buttonTest.Location = New-Object System.Drawing.Point(10, 420)
$buttonTest.Size = New-Object System.Drawing.Size(120, 23)
$buttonTest.Text = 'Test Connectivity'
$form.Controls.Add($buttonTest)

# Export button
$buttonExport = New-Object System.Windows.Forms.Button
$buttonExport.Location = New-Object System.Drawing.Point(140, 420)
$buttonExport.Size = New-Object System.Drawing.Size(120, 23)
$buttonExport.Text = 'Export Results'
$buttonExport.Enabled = $false
$form.Controls.Add($buttonExport)

# Service selection CheckedListBox
$checkedListBox = New-Object System.Windows.Forms.CheckedListBox
$checkedListBox.Location = New-Object System.Drawing.Point(10, 50)
$checkedListBox.Size = New-Object System.Drawing.Size(690, 360)
$checkedListBox.CheckOnClick = $true
foreach ($service in $services) {
    [void]$checkedListBox.Items.Add($service.Name)
}
$form.Controls.Add($checkedListBox)

# Global variable to store successful tests
$global:successfulTests = @()

# Function to test port connectivity
function Test-PortConnectivity {
    param (
        [string]$Machine,
        [string]$Port
    )

    try {
        $testResult = Test-NetConnection -ComputerName $Machine -Port $Port -ErrorAction SilentlyContinue -InformationLevel Quiet
        return $testResult
    } catch {
        Log-Message "Error during port testing: $_" -MessageType "ERROR"
        return $false
    }
}

# Function to export results to CSV
function Export-Results {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Server,
        [Parameter(Mandatory=$true)]
        [Array]$Results
    )
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $documentsFolder = [Environment]::GetFolderPath('MyDocuments')
    $ServerSafe = $Server -replace "[:]", "-" # Replace any illegal characters with hyphens
    $csvFileName = "$ServerSafe-$scriptName-$timestamp.csv"
    $csvPath = Join-Path $documentsFolder $csvFileName
    $Results | Export-Csv -Path $csvPath -NoTypeInformation
    Show-InfoMessage "Results exported to: $csvPath"
}

# Test Connectivity Button Click Event
$buttonTest.Add_Click({
    $textboxResults.Clear()
    $global:successfulTests.Clear()
    $MachineInput = $textboxMachine.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($MachineInput)) {
        Show-ErrorMessage "Please enter a machine name or IP address."
        return
    }

    $textboxResults.AppendText("Starting connectivity test for machine: $MachineInput`n`n")
    foreach ($index in $checkedListBox.CheckedIndices) {
        $selectedService = $services[$index]
        $portsToTest = $selectedService.Ports

        foreach ($port in ($portsToTest -split ',')) {
            $testResult = Test-PortConnectivity -Machine $MachineInput -Port $port
            if ($testResult) {
                $resultObj = [PSCustomObject]@{
                    ServerName   = $MachineInput
                    ServiceName  = $selectedService.Name
                    Port         = $port
                    Result       = "Success"
                }
                $global:successfulTests += $resultObj
                $textboxResults.AppendText("Success: $($selectedService.Name) on port $port`n")
                Log-Message "Success: $($selectedService.Name) on port $port for machine $MachineInput"
            } else {
                $textboxResults.AppendText("Failed: $($selectedService.Name) on port $port`n")
                Log-Message "Failed: $($selectedService.Name) on port $port for machine $MachineInput" -MessageType "ERROR"
            }
        }
    }

    if ($global:successfulTests.Count -gt 0) {
        $textboxResults.AppendText("`nConnectivity tests completed successfully.")
        $buttonExport.Enabled = $true
    } else {
        $textboxResults.AppendText("`nNo successful connections were made.")
        Log-Message "No successful connections were made." -MessageType "WARNING"
        $buttonExport.Enabled = $false
    }
})

# Export Results Button Click Event
$buttonExport.Add_Click({
    $Machine = $textboxMachine.Text.Trim()
    if ($global:successfulTests.Count -gt 0) {
        Export-Results -Server $Machine -Results $global:successfulTests
    } else {
        Show-ErrorMessage "No results to export. Log file located at: $logPath"
    }
})

# Show the form
$form.ShowDialog()

# End of script
