<#
.SYNOPSIS
    PowerShell Script to Identify Short Active Directory Computer Names.

.DESCRIPTION
    This script identifies AD computer names that are shorter than a specified length, 
    helping ensure adherence to organizational naming conventions and policies.

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

# Add necessary assemblies for GUI
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Determine the script name and set up logging path
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Failed to create log directory at ${logDir}. Logging will not be possible."
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
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

# Function to display information messages
function Show-InfoMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Information', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Log-Message "$message" -LogLevel "INFO"
}

# Function to display error messages
function Show-ErrorMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    Log-Message "$message" -LogLevel "ERROR"
}

# Function to get the FQDN of the current domain
function Get-CurrentDomainFQDN {
    try {
        $ComputerSystem = Get-WmiObject -Class Win32_ComputerSystem
        $Domain = $ComputerSystem.Domain
        if ($Domain) {
            return $Domain
        } else {
            throw "Domain information not found."
        }
    } catch {
        Show-ErrorMessage "Unable to fetch current domain FQDN automatically."
        return ""
    }
}

# Log the start of the script
Log-Message "Starting AD Workstation Search script."

# Function to search Active Directory for workstation computers with names shorter than 15 characters
function Search-ADComputers {
    param (
        [System.Windows.Forms.ListView]$listView,
        [string]$searchScope,
        [string]$specificDomain = ""
    )
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    } catch {
        Show-ErrorMessage "ActiveDirectory module is not available. Please ensure RSAT tools are installed."
        return
    }

    $results = @()
    $domains = @()

    switch ($searchScope) {
        'Current Domain' {
            $currentDomain = Get-CurrentDomainFQDN
            if ([string]::IsNullOrWhiteSpace($currentDomain)) {
                Show-ErrorMessage "Current domain could not be determined."
                return
            }
            $domains += $currentDomain
        }
        'Specific Domain' {
            if ([string]::IsNullOrWhiteSpace($specificDomain)) {
                Show-ErrorMessage "Please select a valid specific domain FQDN."
                return
            }
            $domains += $specificDomain
        }
        'All Domains in Forest' {
            try {
                $forest = Get-ADForest -ErrorAction Stop
                $domains = $forest.Domains
            } catch {
                Show-ErrorMessage "Failed to retrieve domains in the forest. Ensure you have the necessary permissions."
                return
            }
        }
        default {
            Show-ErrorMessage "Invalid search scope selected."
            return
        }
    }

    $listView.Items.Clear()
    foreach ($domain in $domains) {
        Log-Message "Searching in domain ${domain}"
        try {
            $filter = "OperatingSystem -notlike '*Server*' -and Enabled -eq '$true'"
            $computers = Get-ADComputer -Filter $filter -Property Name, DNSHostName -Server $domain -ErrorAction Stop
            $filteredComputers = $computers | Where-Object { $_.Name.Length -lt 15 }
            foreach ($comp in $filteredComputers) {
                $item = New-Object System.Windows.Forms.ListViewItem($comp.DNSHostName)
                $item.SubItems.Add($comp.Name.Length.ToString())
                $item.SubItems.Add($domain)
                $listView.Items.Add($item)

                $obj = [PSCustomObject]@{
                    CharactersLength = $comp.Name.Length
                    WorkstationFQDN = $comp.DNSHostName
                    DomainFQDN = $domain
                }
                $results += $obj
            }
            Log-Message "Found $($filteredComputers.Count) workstations in domain ${domain} with names shorter than 15 characters."
        } catch {
            Log-Message "Error searching domain ${domain}: $_" -LogLevel "ERROR"
            Show-ErrorMessage "Error searching domain ${domain}. Check logs for details."
        }
    }

    $global:exportData = $results
    $totalCount = $results.Count
    if ($totalCount -gt 0) {
        Show-InfoMessage "Search completed. Found ${totalCount} workstations with names shorter than 15 characters."
    } else {
        Show-InfoMessage "No workstations found with names shorter than 15 characters."
    }
}

# --------------------------- GUI Setup --------------------------- #

# Main Form
$mainForm = New-Object System.Windows.Forms.Form
$mainForm.Text = 'Search ADDS Workstations'
$mainForm.Size = New-Object System.Drawing.Size(600, 600)
$mainForm.StartPosition = 'CenterScreen'

# Search Scope Label
$lblScope = New-Object System.Windows.Forms.Label
$lblScope.Location = New-Object System.Drawing.Point(30, 30)
$lblScope.Size = New-Object System.Drawing.Size(100, 20)
$lblScope.Text = 'Search Scope:'
$mainForm.Controls.Add($lblScope)

# Search Scope ComboBox
$cmbScope = New-Object System.Windows.Forms.ComboBox
$cmbScope.Location = New-Object System.Drawing.Point(150, 30)
$cmbScope.Size = New-Object System.Drawing.Size(200, 20)
$cmbScope.DropDownStyle = 'DropDownList'
$cmbScope.Items.AddRange(@('Current Domain', 'Specific Domain', 'All Domains in Forest'))
$cmbScope.SelectedIndex = 0
$mainForm.Controls.Add($cmbScope)

# Specific Domain ComboBox
$cmbDomain = New-Object System.Windows.Forms.ComboBox
$cmbDomain.Location = New-Object System.Drawing.Point(150, 70)
$cmbDomain.Size = New-Object System.Drawing.Size(300, 20)
$cmbDomain.DropDownStyle = 'DropDownList'
$cmbDomain.Enabled = $false
$mainForm.Controls.Add($cmbDomain)

# Search Button
$btnSearch = New-Object System.Windows.Forms.Button
$btnSearch.Location = New-Object System.Drawing.Point(470, 30)
$btnSearch.Size = New-Object System.Drawing.Size(80, 25)
$btnSearch.Text = 'Search'
$btnSearch.Add_Click({
        $searchScope = $cmbScope.SelectedItem
        $specificDomain = $cmbDomain.SelectedItem
        Search-ADComputers -listView $listView -searchScope $searchScope -specificDomain $specificDomain
    })
$mainForm.Controls.Add($btnSearch)

# List View to display results
$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(30, 110)
$listView.Size = New-Object System.Drawing.Size(520, 350)
$listView.View = [System.Windows.Forms.View]::Details
$listView.FullRowSelect = $true
$listView.GridLines = $true
$listView.Columns.Add("Workstation FQDN", 250)
$listView.Columns.Add("Characters Length", 120)
$listView.Columns.Add("Domain FQDN", 150)
$mainForm.Controls.Add($listView)

# Export Button
$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Location = New-Object System.Drawing.Point(30, 480)
$btnExport.Size = New-Object System.Drawing.Size(120, 30)
$btnExport.Text = 'Export to CSV'
$btnExport.Add_Click({
        if ($global:exportData -and $global:exportData.Count -gt 0) {
            $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
            $saveFileDialog.Filter = "CSV files (*.csv)|*.csv"
            $saveFileDialog.Title = "Save Exported Data"
            $saveFileDialog.FileName = "${scriptName}_$($cmbScope.SelectedItem.Replace(' ', '_'))_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            if ($saveFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                try {
                    $global:exportData | Export-Csv -Path $saveFileDialog.FileName -NoTypeInformation -Delimiter ';' -Encoding UTF8
                    Show-InfoMessage "Data successfully exported to ${saveFileDialog.FileName}"
                } catch {
                    Show-ErrorMessage "Failed to export data: $_"
                }
            }
        } else {
            Show-InfoMessage "No data available to export."
        }
    })
$mainForm.Controls.Add($btnExport)

# Close Button
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Location = New-Object System.Drawing.Point(160, 480)
$btnClose.Size = New-Object System.Drawing.Size(100, 30)
$btnClose.Text = 'Close'
$btnClose.Add_Click({ $mainForm.Close() })
$mainForm.Controls.Add($btnClose)

# Explanation Label
$lblExplanation = New-Object System.Windows.Forms.Label
$lblExplanation.Location = New-Object System.Drawing.Point(30, 530)
$lblExplanation.Size = New-Object System.Drawing.Size(520, 40)
$lblExplanation.Text = "Note: This script searches for workstation computers with names shorter than 15 characters, which is the default maximum length for NetBIOS names."
$mainForm.Controls.Add($lblExplanation)

# Event Handler for Search Scope Change
$cmbScope.Add_SelectedIndexChanged({
        switch ($cmbScope.SelectedItem) {
            'Specific Domain' {
                try {
                    $forest = Get-ADForest
                    $cmbDomain.Items.Clear()
                    $forest.Domains | ForEach-Object { $cmbDomain.Items.Add($_) }
                    $cmbDomain.Enabled = $true
                } catch {
                    Show-ErrorMessage "Failed to retrieve domains from the forest. Ensure you have the necessary permissions."
                }
            }
            default {
                $cmbDomain.Enabled = $false
                $cmbDomain.Items.Clear()
                $cmbDomain.Text = ""
            }
        }
    })

# Show GUI
[void]$mainForm.ShowDialog()

Log-Message "AD Workstation Search script finished."

# End of script
