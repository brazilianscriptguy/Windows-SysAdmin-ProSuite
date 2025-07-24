<#
.SYNOPSIS
    PowerShell Script to Collect and Export WSUS Environment Details.

.DESCRIPTION
    This script gathers WSUS server information, including general details, update statistics,
    computer groups, and log file sizes. It uses the WSUS Administration Assembly to collect data,
    logs all actions, and exports the results to a CSV file. The process is managed through a GUI
    for user interaction.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: November 25, 2024
#>

# Hide the PowerShell console window
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() {
        IntPtr hWnd = GetConsoleWindow();
        ShowWindow(hWnd, 0); // 0 = SW_HIDE
    }
}
"@
[Window]::Hide()

# Load GUI libraries
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
} catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to load required assemblies. $_", "Initialization Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}

# Function to get the FQDN of the current server
function Get-FQDN {
    try {
        $fqdn = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName
        return $fqdn
    } catch {
        try {
            $domain = (Get-CimInstance -ClassName Win32_ComputerSystem).Domain
            if ($domain -and $domain -ne $env:COMPUTERNAME) {
                return "$($env:COMPUTERNAME).$domain"
            } else {
                return $env:COMPUTERNAME
            }
        } catch {
            return $env:COMPUTERNAME
        }
    }
}

$fqdn = Get-FQDN

# Script configuration
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

# Set log and CSV paths, allow dynamic configuration or fallback to defaults
$logDir = if ($env:LOG_PATH -and $env:LOG_PATH -ne "") { $env:LOG_PATH } else { 'C:\Logs-TEMP' }
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName
$csvPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "${scriptName}-${timestamp}.csv"

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to create log directory at ${logDir}. Error: $_", "Logging Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        exit 1
    }
}

# Enhanced logging function
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Type = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Type] $Message"
    try {
        Add-Content -Path $logPath -Value "$logEntry`r`n" -ErrorAction Stop
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to write to log: $_", "Logging Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

# Function to display informational messages
function Show-InfoMessage {
    param ([string]$Message)
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        'Information',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
    Log-Message -Message $Message -Type "INFO"
}

# Function to display error messages
function Show-ErrorMessage {
    param ([string]$Message)
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        'Error',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    Log-Message -Message $Message -Type "ERROR"
}

# Function to test WSUS service and ports
function Test-WSUSService {
    param (
        [Parameter(Mandatory = $true)][string]$Hostname,
        [Parameter(Mandatory = $true)][int[]]$Ports
    )
    $openPorts = @()
    foreach ($port in $Ports) {
        try {
            $connection = Test-NetConnection -ComputerName $Hostname -Port $port -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            if ($connection.TcpTestSucceeded) {
                $openPorts += $port
            }
        } catch {
            # Ignore errors
        }
    }
    if (-not $openPorts) {
        throw "Neither port 8530 (HTTP) nor port 8531 (HTTPS) is open on ${Hostname}. Verify WSUS configuration."
    } else {
        Log-Message -Message "WSUS service is running on ${Hostname} and listening on ports: $($openPorts -join ', ')." -Type "INFO"
    }
}

# Function to gather WSUS details using WSUS Administration Assembly
function Get-WSUSDetails {
    try {
        # Load WSUS Administration assembly
        $wsusApiPath = "C:\Program Files\Update Services\Api\Microsoft.UpdateServices.Administration.dll"
        if (-not ([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq "Microsoft.UpdateServices.Administration" })) {
            if (-not (Test-Path $wsusApiPath)) {
                throw "WSUS Administration API DLL not found at ${wsusApiPath}. Ensure the WSUS Administration Console is installed."
            }
            Add-Type -Path $wsusApiPath -ErrorAction Stop
        }

        # Validate WSUS service and ports
        $hostname = "localhost" # Use localhost to ensure local connectivity
        $ports = @(8530, 8531)
        Test-WSUSService -Hostname $hostname -Ports $ports

        # Connect to WSUS server
        $wsusServer = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($hostname, $false)

        # General WSUS information
        $wsusInfo = [PSCustomObject]@{
            WSUSVersion = $wsusServer.Version.ToString()
            LastSyncResult = $wsusServer.GetSynchronizationStatus().LastSynchronizationResult.ToString()
            LastSyncTime = $wsusServer.GetSynchronizationStatus().LastSynchronizationTime
            NextSyncTime = $wsusServer.GetConfiguration().NextSyncTime
            UpdateLanguages = ($wsusServer.GetConfiguration().EnabledUpdateLanguages -join ", ")
            SyncSource = if ($wsusServer.GetConfiguration().SyncFromMicrosoftUpdate) { "Microsoft Update" } else { "Another WSUS Server" }
        }

        # WSUS computer groups
        $computerGroups = $wsusServer.GetComputerTargetGroups() | ForEach-Object {
            [PSCustomObject]@{
                GroupName = $_.Name
                Computers = $_.GetComputerTargets().Count
            }
        }

        # WSUS update statistics
        $updates = $wsusServer.GetUpdates()
        $updateStats = [PSCustomObject]@{
            TotalUpdates = $updates.Count
            ApprovedUpdates = ($updates | Where-Object { $_.IsApproved }).Count
            DeclinedUpdates = ($updates | Where-Object { $_.IsDeclined }).Count
        }

        # WSUS log size
        $wsusLogDir = "C:\Program Files\Update Services\LogFiles"
        $logSizeMB = if (Test-Path $wsusLogDir) {
            (Get-ChildItem -Path $wsusLogDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
        } else {
            0
        }

        return @{
            GeneralInfo = $wsusInfo
            ComputerGroups = $computerGroups
            UpdateStatistics = $updateStats
            LogSizeInMB = "{0:N2}" -f $logSizeMB
        }
    } catch {
        Log-Message -Message "Error gathering WSUS details: $_" -Type "ERROR"
        Show-ErrorMessage -Message "Failed to retrieve WSUS details. Error: $_"
        return $null
    }
}

# GUI Setup
$form = New-Object System.Windows.Forms.Form
$form.Text = "WSUS Environment Tool"
$form.Size = New-Object Drawing.Size(500, 300)
$form.StartPosition = "CenterScreen"
$form.MaximizeBox = $false

# Button to gather WSUS data
$btnGather = New-Object System.Windows.Forms.Button
$btnGather.Text = "Gather WSUS Data"
$btnGather.Location = New-Object Drawing.Point(10, 10)
$btnGather.Size = New-Object Drawing.Size(150, 30)
$form.Controls.Add($btnGather)

# Status label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Status: Waiting..."
$statusLabel.Location = New-Object Drawing.Point(10, 50)
$statusLabel.Size = New-Object Drawing.Size(460, 20)
$form.Controls.Add($statusLabel)

# Progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object Drawing.Point(10, 80)
$progressBar.Size = New-Object Drawing.Size(460, 20)
$form.Controls.Add($progressBar)

# Event handler for the button
$btnGather.Add_Click({
        $btnGather.Enabled = $false
        $statusLabel.Text = "Gathering WSUS data..."
        $progressBar.Value = 20
        $form.Refresh()

        $wsusDetails = Get-WSUSDetails
        if ($wsusDetails -eq $null) {
            $statusLabel.Text = "Error gathering data."
            $progressBar.Value = 0
            $btnGather.Enabled = $true
            return
        }

        $progressBar.Value = 60
        $statusLabel.Text = "Exporting data..."
        $form.Refresh()

        try {
            # Prepare data for CSV
            $exportData = @()

            # Combine GeneralInfo with ComputerGroups and UpdateStatistics
            foreach ($group in $wsusDetails.ComputerGroups) {
                $dataRow = [PSCustomObject]@{
                    WSUSVersion = $wsusDetails.GeneralInfo.WSUSVersion
                    LastSyncResult = $wsusDetails.GeneralInfo.LastSyncResult
                    LastSyncTime = $wsusDetails.GeneralInfo.LastSyncTime
                    NextSyncTime = $wsusDetails.GeneralInfo.NextSyncTime
                    UpdateLanguages = $wsusDetails.GeneralInfo.UpdateLanguages
                    SyncSource = $wsusDetails.GeneralInfo.SyncSource
                    GroupName = $group.GroupName
                    Computers = $group.Computers
                    TotalUpdates = $wsusDetails.UpdateStatistics.TotalUpdates
                    ApprovedUpdates = $wsusDetails.UpdateStatistics.ApprovedUpdates
                    DeclinedUpdates = $wsusDetails.UpdateStatistics.DeclinedUpdates
                    LogSizeInMB = $wsusDetails.LogSizeInMB
                }
                $exportData += $dataRow
            }

            # Export data to CSV
            $exportData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

            $progressBar.Value = 100
            $statusLabel.Text = "Process complete."
            Show-InfoMessage -Message "WSUS details exported successfully to: ${csvPath}"
            Log-Message -Message "WSUS details exported successfully to: ${csvPath}" -Type "INFO"
        } catch {
            Log-Message -Message "Error exporting data to CSV: $_" -Type "ERROR"
            Show-ErrorMessage -Message "Error exporting data. Verify permissions and file path. Error: $_"
            $statusLabel.Text = "Error exporting data."
            $progressBar.Value = 0
        } finally {
            $btnGather.Enabled = $true
        }
    })

# Show the GUI
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()

# End of script
