<#
.SYNOPSIS
    PowerShell Script for Retrieving Shared Folders from AD Computers.

.DESCRIPTION
    This script scans Active Directory computers for shared folders, logging the results 
    to ensure that only authorized shares are in place. It aids in monitoring shared 
    resources across the domain.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: October 22, 2024
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

# Import necessary assemblies for GUI
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Determine the script name and set up the logging path
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

# Enhanced logging function with error handling
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$LogLevel = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$LogLevel] $Message"
    try {
        Add-Content -Path $logPath -Value "$logEntry`r`n" -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

# Function to display information messages
function Show-InfoMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Information', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Log-Message "Info: $message" -LogLevel "INFO"
}

# Function to display error messages
function Show-ErrorMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    Log-Message "Error: $message" -LogLevel "ERROR"
}

# Function to get the FQDN of the domain name
function Get-DomainFQDN {
    try {
        $ComputerSystem = Get-WmiObject Win32_ComputerSystem
        $Domain = $ComputerSystem.Domain
        return $Domain
    } catch {
        Show-ErrorMessage "Unable to fetch FQDN automatically."
        return "YourDomainHere"
    }
}

# Log the start of the script
Log-Message "Starting AD Workstation Search script."

# Function to get shared folders and printers on a remote computer
function Get-SharedResources {
    param (
        [string]$ComputerName
    )
    
    try {
        # Check shared folders on the remote computer
        $shares = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            Get-WmiObject -Class Win32_Share
        } -ErrorAction Stop

        # Check shared printers on the remote computer
        $printers = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            Get-WmiObject -Query "SELECT * FROM Win32_Printer WHERE Shared = True"
        } -ErrorAction Stop

        $resources = @()
        if ($shares) {
            $resources += $shares | Select-Object @{Name = 'ComputerName'; Expression = { $ComputerName } }, Name, Path, Description, Status
        }
        if ($printers) {
            $resources += $printers | Select-Object @{Name = 'ComputerName'; Expression = { $ComputerName } }, Name, @{Name = 'Path'; Expression = { "Printer" } }, Description, @{Name = 'Status'; Expression = { "Shared Printer" } }
        }

        return $resources
    } catch {
        Log-Message "Could not connect to $ComputerName. Error: $_" -LogLevel "ERROR"
        return $null
    }
}

# Function to search for shared resources on workstations in the AD domain
function Search-SharedResources {
    param (
        [System.Windows.Forms.ListBox]$listBox,
        [string]$domainFQDN
    )
    Import-Module ActiveDirectory

    $computers = Get-ADComputer -Filter { OperatingSystem -like '*Windows*Workstation*' } -Property Name -Server $domainFQDN

    $listBox.Items.Clear()
    $results = @()

    foreach ($computer in $computers) {
        $computerName = $computer.Name
        Log-Message "Checking shared resources on $computerName..."
        $sharedResources = Get-SharedResources -ComputerName $computerName
        if ($sharedResources) {
            $results += $sharedResources
            foreach ($resource in $sharedResources) {
                $listBox.Items.Add("$($resource.ComputerName): $($resource.Name) - $($resource.Status)")
            }
        }
    }

    $global:exportData = $results
    Log-Message "Found $($results.Count) shared resources."
    if ($results.Count -eq 0) {
        Show-InfoMessage "No shared resources found on the workstations."
    }
}

# Main Form
$mainForm = New-Object System.Windows.Forms.Form
$mainForm.Text = 'Search ADDS Shared Resources'
$mainForm.Size = New-Object System.Drawing.Size(500, 500)
$mainForm.StartPosition = 'CenterScreen'

# Panel for Domain Input and Buttons
$panelTop = New-Object System.Windows.Forms.Panel
$panelTop.Size = New-Object System.Drawing.Size(480, 100)
$panelTop.Location = New-Object System.Drawing.Point(10, 10)
$mainForm.Controls.Add($panelTop)

# Domain FQDN Label
$lblDomain = New-Object System.Windows.Forms.Label
$lblDomain.Location = New-Object System.Drawing.Point(10, 10)
$lblDomain.Size = New-Object System.Drawing.Size(120, 20)
$lblDomain.Text = 'Domain FQDN:'
$panelTop.Controls.Add($lblDomain)

# Domain FQDN Text Box
$txtDomain = New-Object System.Windows.Forms.TextBox
$txtDomain.Location = New-Object System.Drawing.Point(140, 10)
$txtDomain.Size = New-Object System.Drawing.Size(220, 20)
$txtDomain.Text = Get-DomainFQDN
$panelTop.Controls.Add($txtDomain)

# Search Button
$btnSearch = New-Object System.Windows.Forms.Button
$btnSearch.Location = New-Object System.Drawing.Point(370, 10)
$btnSearch.Size = New-Object System.Drawing.Size(90, 23)
$btnSearch.Text = 'Search'
$btnSearch.Add_Click({
        $domainFQDN = if ($txtDomain.Text) { $txtDomain.Text } else { "YourDomainHere" }
        Search-SharedResources -listBox $listBox -domainFQDN $domainFQDN
    })
$panelTop.Controls.Add($btnSearch)

# List Box to display results
$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Location = New-Object System.Drawing.Point(10, 120)
$listBox.Size = New-Object System.Drawing.Size(460, 300)
$mainForm.Controls.Add($listBox)

# Panel for Export and Close Buttons
$panelBottom = New-Object System.Windows.Forms.Panel
$panelBottom.Size = New-Object System.Drawing.Size(480, 40)
$panelBottom.Location = New-Object System.Drawing.Point(10, 430)
$mainForm.Controls.Add($panelBottom)

# Export Button
$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Location = New-Object System.Drawing.Point(10, 10)
$btnExport.Size = New-Object System.Drawing.Size(140, 23)
$btnExport.Text = 'Export to CSV'
$btnExport.Add_Click({
        if ($global:exportData -and $global:exportData.Count -gt 0) {
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $csvPath = [Environment]::GetFolderPath('MyDocuments') + "\${scriptName}_${txtDomain.Text}_$timestamp.csv"
            $global:exportData | Select-Object ComputerName, Name, Path, Description, Status | Export-Csv -Path $csvPath -NoTypeInformation -Delimiter ';' -Encoding UTF8
            Show-InfoMessage "Data exported to $csvPath"
        } else {
            Show-InfoMessage "No data available to export."
        }
    })
$panelBottom.Controls.Add($btnExport)

# Close Button
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Location = New-Object System.Drawing.Point(160, 10)
$btnClose.Size = New-Object System.Drawing.Size(90, 23)
$btnClose.Text = 'Close'
$btnClose.Add_Click({ $mainForm.Close() })
$panelBottom.Controls.Add($btnClose)

# Show GUI
[void]$mainForm.ShowDialog()

Log-Message "AD Workstation Search script finished."

# End of script
