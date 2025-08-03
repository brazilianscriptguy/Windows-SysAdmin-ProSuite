<#
.SYNOPSIS
    Interactive PowerShell GUI to Collect System, Network, and User Information from Remote Workstations. 

.DESCRIPTION
    This script uses CIM (or fallback to WMI) to collect OS, BIOS, user, and network details
    from a list of workstations input by the user. It features GUI interaction, console hiding,
    structured logging, CSV export, and a responsive progress bar for user feedback.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: August 01, 2025
#>

# Hide PowerShell console
if (-not ("Window" -as [type])) {
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
            ShowWindow(handle, 0); // SW_HIDE
        }
    }
"@
}
[Window]::Hide()

# Required GUI assembly
Add-Type -AssemblyName System.Windows.Forms

# Define paths
$scriptName = "WorkstationInventory"
$logDir = "C:\Logs-TEMP"
$logFile = Join-Path $logDir "$scriptName.log"
$outputCsv = "C:\AD_Workstation_Inventory.csv"

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Log-Message {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR")] [string]$Type = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Type] $Message"
    Add-Content -Path $logFile -Value $entry
}

function Show-InfoMessage {
    param([string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, "Information", 'OK', 'Information') | Out-Null
    Log-Message -Message $Message -Type "INFO"
}

function Show-ErrorMessage {
    param([string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, "Error", 'OK', 'Error') | Out-Null
    Log-Message -Message $Message -Type "ERROR"
}

function Get-ComputerListFromText ($inputText) {
    return $inputText -split "[\r\n]+" | Where-Object { $_ -and $_.Trim() -ne "" }
}

function Collect-Inventory {
    param (
        [string[]]$Computers,
        [System.Windows.Forms.ProgressBar]$ProgressBar
    )
    $Results = @()
    $count = 0
    $total = $Computers.Count

    foreach ($Computer in $Computers) {
        $count++
        $percent = [math]::Round(($count / $total) * 100)
        $ProgressBar.Value = [math]::Min($percent, 100)

        try {
            Log-Message -Message "Querying $Computer..."
            if (Test-Connection -ComputerName $Computer -Count 2 -Quiet) {
                try {
                    $OS = Get-CimInstance -Class Win32_OperatingSystem -ComputerName $Computer -ErrorAction Stop
                    $BIOS = Get-CimInstance -Class Win32_BIOS -ComputerName $Computer -ErrorAction Stop
                    $Net = Get-CimInstance -Class Win32_NetworkAdapterConfiguration -ComputerName $Computer -ErrorAction Stop | Where-Object { $_.IPEnabled -eq $true }
                    $User = Get-CimInstance -Class Win32_ComputerSystem -ComputerName $Computer -ErrorAction Stop
                } catch {
                    Log-Message -Message "Falling back to WMI for $Computer..." -Type "WARNING"
                    $OS = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $Computer
                    $BIOS = Get-WmiObject -Class Win32_BIOS -ComputerName $Computer
                    $Net = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -ComputerName $Computer | Where-Object { $_.IPEnabled -eq $true }
                    $User = Get-WmiObject -Class Win32_ComputerSystem -ComputerName $Computer
                }

                $Results += [PSCustomObject]@{
                    Hostname = $Computer
                    LoggedUser = $User.UserName
                    OperatingSystem = $OS.Caption
                    OSVersion = $OS.Version
                    LastBootTime = ([Management.ManagementDateTimeConverter]::ToDateTime($OS.LastBootUpTime))
                    IPAddress = $Net.IPAddress -join ', '
                    MACAddress = $Net.MACAddress
                    DefaultGateway = $Net.DefaultIPGateway -join ', '
                    AdapterName = $Net.Description
                    Domain = $User.Domain
                    BIOSManufacturer = $BIOS.Manufacturer
                    SerialNumber = $BIOS.SerialNumber
                }
            } else {
                Log-Message -Message "$Computer is unreachable." -Type "WARNING"
                $Results += [PSCustomObject]@{
                    Hostname = $Computer
                    LoggedUser = "Unavailable"
                    OperatingSystem = "Unreachable"
                    OSVersion = "N/A"
                    LastBootTime = "N/A"
                    IPAddress = "N/A"
                    MACAddress = "N/A"
                    DefaultGateway = "N/A"
                    AdapterName = "N/A"
                    Domain = "N/A"
                    BIOSManufacturer = "N/A"
                    SerialNumber = "N/A"
                }
            }
        } catch {
            Log-Message -Message ("Error querying ${Computer}: $($_.Exception.Message)") -Type "ERROR"
        }
    }

    try {
        $Results | Export-Csv -Path $outputCsv -NoTypeInformation -Encoding UTF8
        Show-InfoMessage -Message "Report generated successfully.\nSaved to: $outputCsv"
    } catch {
        Show-ErrorMessage -Message "Error exporting to CSV: $($_.Exception.Message)"
    }

    $ProgressBar.Value = 100
}

# GUI - Input for hostnames
$form = New-Object System.Windows.Forms.Form
$form.Text = "Workstation Inventory Collector"
$form.Size = New-Object System.Drawing.Size(500, 420)
$form.StartPosition = "CenterScreen"

$label = New-Object System.Windows.Forms.Label
$label.Text = "Enter hostnames or IPs (one per line):"
$label.Location = '10,10'
$label.AutoSize = $true
$form.Controls.Add($label)

$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Multiline = $true
$textBox.ScrollBars = 'Vertical'
$textBox.Location = '10,40'
$textBox.Size = '460,220'
$form.Controls.Add($textBox)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = '10,270'
$progressBar.Size = '460,20'
$progressBar.Style = 'Continuous'
$form.Controls.Add($progressBar)

$buttonRun = New-Object System.Windows.Forms.Button
$buttonRun.Text = "Run Inventory"
$buttonRun.Location = '10,310'
$buttonRun.Size = '220,40'
$buttonRun.Add_Click({
        $computers = Get-ComputerListFromText -inputText $textBox.Text
        if ($computers.Count -gt 0) {
            $progressBar.Value = 0
            Collect-Inventory -Computers $computers -ProgressBar $progressBar
        } else {
            Show-ErrorMessage -Message "Please provide at least one valid hostname or IP."
        }
    })
$form.Controls.Add($buttonRun)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Text = "Close"
$buttonClose.Location = '250,310'
$buttonClose.Size = '220,40'
$buttonClose.Add_Click({ $form.Close() })
$form.Controls.Add($buttonClose)

$form.Topmost = $true
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
