<#
.SYNOPSIS
    PowerShell Script for Cleaning Up Inactive AD Computer Accounts.

.DESCRIPTION
    This script identifies and removes inactive workstation accounts in Active Directory, 
    enhancing security by ensuring that outdated or unused accounts are properly managed and removed.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: July 17, 2025
    Version: 2.1 (Improved forest domain gathering)
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

# Determine the script name and set up logging path
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    try {
        $null = New-Item -Path $logDir -ItemType Directory -ErrorAction Stop
        Log-Message "Log directory created at $logDir."
    } catch {
        Write-Error "Failed to create log directory at $logDir. Logging will not be possible."
        return
    }
}

# Enhanced logging function with error handling
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$MessageType] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

# Function to display error messages
function Show-ErrorMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    Log-Message "Error: $message" -MessageType "ERROR"
}

# Function to display information messages
function Show-InfoMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Information', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Log-Message "Info: $message" -MessageType "INFO"
}

# Function to get all FQDN Domain Names in the Forest with improved handling
function Get-FQDNDomainNames {
    try {
        Log-Message "Attempting to retrieve forest information" -MessageType "INFO"
        $forest = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
        $domains = @()
        
        foreach ($domain in $forest.Domains) {
            try {
                Log-Message "Processing domain: $($domain.Name)" -MessageType "INFO"
                $domains += $domain.Name
            } catch {
                Log-Message "Failed to process domain $($domain.Name): $_" -MessageType "WARN"
            }
        }
        
        if ($domains.Count -eq 0) {
            Log-Message "No domains retrieved from forest" -MessageType "WARN"
            Show-InfoMessage "No domains found in the forest. Check connectivity or permissions."
        } else {
            Log-Message "FQDN Domain Names fetched: $($domains -join ', ')" -MessageType "INFO"
        }
        return $domains
    } catch {
        Log-Message "Failed to retrieve forest domains: $_" -MessageType "ERROR"
        Show-ErrorMessage "Unable to fetch FQDN Domain Names. Check connectivity, permissions, or AD configuration."
        return @()
    }
}

# Function to find old workstation accounts based on inactivity days
function Find-OldWorkstationAccounts {
    param (
        [string]$DCName,
        [int]$InactiveDays
    )
    $InactiveTimeSpan = [TimeSpan]::FromDays($InactiveDays)
    $CutOffDate = (Get-Date).Add(-$InactiveTimeSpan)
    Log-Message "Searching for workstations inactive since $($CutOffDate.ToShortDateString())"
    $oldComputers = Get-ADComputer -Server $DCName -Filter { LastLogonDate -lt $CutOffDate -and Enabled -eq $true } -Properties LastLogonDate, DistinguishedName, OperatingSystem | Where-Object { $_.OperatingSystem -notlike "*Server*" }

    Log-Message "Found $($oldComputers.Count) old workstations."
    return $oldComputers
}

# Function to remove selected workstation computer accounts and return details
function Remove-SelectedWorkstationAccounts {
    param (
        [System.Collections.ObjectModel.Collection[System.Object]]$SelectedComputers,
        [string]$DCName
    )
    $RemovedComputers = @()
    foreach ($computer in $SelectedComputers) {
        try {
            # Check if the computer object has child objects
            $hasChildren = Get-ADObject -Filter { ParentDistinguishedName -eq $computer.DistinguishedName } -SearchBase $computer.DistinguishedName -Server $DCName

            if ($hasChildren.Count -gt 0) {
                Log-Message "Skipped removal of computer: $($computer.Name) - DN: $($computer.DistinguishedName) because it contains child objects."
                Write-Warning "Skipped removal of computer: $($computer.Name) - DN: $($computer.DistinguishedName) because it contains child objects."
            } else {
                Remove-ADComputer -Identity $computer.DistinguishedName -Confirm:$false -Server $DCName
                $RemovedComputers += $computer
                Log-Message "Removed computer: $($computer.Name) - DN: $($computer.DistinguishedName)"
            }
        } catch {
            Log-Message "Failed to remove computer with DN: $($computer.DistinguishedName). Error: $_" -MessageType "ERROR"
            Write-Warning "Failed to remove computer with DN: $($computer.DistinguishedName). Error: $_"
        }
    }

    if ($RemovedComputers.Count -gt 0) {
        $MyDocuments = [Environment]::GetFolderPath("MyDocuments")
        $TimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $FileName = "${ScriptName}_${DCName}-${TimeStamp}.csv"
        $FilePath = Join-Path -Path $MyDocuments -ChildPath $FileName
        $RemovedComputers | Select-Object @{Name = 'Name'; Expression = { $_.Name } }, @{Name = 'DistinguishedName'; Expression = { $_.DistinguishedName } } | Export-Csv -Path $FilePath -NoTypeInformation -Force
        Show-InfoMessage "$($RemovedComputers.Count) workstation(s) removed. Details exported to '$FilePath'."
        Log-Message "Removed $($RemovedComputers.Count) workstations. Details exported to '$FilePath'."
    }
}

# Main function to run the GUI
function Show-GUI {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Cleanup Inactive ADComputer Accounts"
    $form.Size = New-Object System.Drawing.Size(710, 520)
    $form.StartPosition = "CenterScreen"

    # Fetch all FQDN Domain Names in the Forest
    $fqdnDomains = Get-FQDNDomainNames

    # Dropdown List for Domain Controller names input
    $comboBoxDC = New-Object System.Windows.Forms.ComboBox
    $comboBoxDC.Location = New-Object System.Drawing.Point(190, 10)
    $comboBoxDC.Size = New-Object System.Drawing.Size(200, 20)
    $comboBoxDC.Items.AddRange($fqdnDomains)
    if ($fqdnDomains.Count -gt 0) { $comboBoxDC.SelectedIndex = 0 } else { $comboBoxDC.Items.Add("No Domains Found") }
    $form.Controls.Add($comboBoxDC)

    # Label for Domain Controller name input
    $labelDC = New-Object System.Windows.Forms.Label
    $labelDC.Location = New-Object System.Drawing.Point(10, 10)
    $labelDC.Size = New-Object System.Drawing.Size(180, 20)
    $labelDC.Text = "Domain Controller FQDN:"
    $form.Controls.Add($labelDC)

    # Label for Inactive Days input
    $labelDays = New-Object System.Windows.Forms.Label
    $labelDays.Location = New-Object System.Drawing.Point(10, 40)
    $labelDays.Size = New-Object System.Drawing.Size(180, 20)
    $labelDays.Text = "Inactive Days Threshold:"
    $form.Controls.Add($labelDays)

    # TextBox for Inactive Days input (default to 180 days)
    $textBoxDays = New-Object System.Windows.Forms.TextBox
    $textBoxDays.Location = New-Object System.Drawing.Point(190, 40)
    $textBoxDays.Size = New-Object System.Drawing.Size(200, 20)
    $textBoxDays.Text = "180"
    $form.Controls.Add($textBoxDays)

    # ListView for displaying old workstations
    $listView = New-Object System.Windows.Forms.ListView
    $listView.Location = New-Object System.Drawing.Point(10, 70)
    $listView.Size = New-Object System.Drawing.Size(670, 350)
    $listView.View = [System.Windows.Forms.View]::Details
    $listView.CheckBoxes = $true
    $listView.FullRowSelect = $true
    $listView.Columns.Add("Name", 150)
    $listView.Columns.Add("Distinguished Name", 500)
    $form.Controls.Add($listView)

    # Button to find and list old workstations
    $buttonFind = New-Object System.Windows.Forms.Button
    $buttonFind.Location = New-Object System.Drawing.Point(400, 10)
    $buttonFind.Size = New-Object System.Drawing.Size(150, 50)
    $buttonFind.Text = "Find Old Workstations"
    $buttonFind.Add_Click({
            $DCName = $comboBoxDC.SelectedItem
            $InactiveDays = $textBoxDays.Text
            if ([string]::IsNullOrWhiteSpace($DCName) -or ![int]::TryParse($textBoxDays.Text, [ref]$InactiveDays)) {
                Show-ErrorMessage "Please provide both Domain Controller FQDN and a valid number for Inactive Days Threshold."
                return
            }
            $oldComputers = Find-OldWorkstationAccounts -DCName $DCName -InactiveDays $InactiveDays
            $listView.Items.Clear()
            foreach ($computer in $oldComputers) {
                $item = New-Object System.Windows.Forms.ListViewItem($computer.Name)
                $item.SubItems.Add($computer.DistinguishedName)
                $item.Tag = $computer
                $listView.Items.Add($item)
            }
            Show-InfoMessage "Found $($oldComputers.Count) old workstation(s) with an inactive threshold of $InactiveDays day(s)."
        })
    $form.Controls.Add($buttonFind)

    # Checkbox to select/deselect all workstations
    $checkboxSelectAll = New-Object System.Windows.Forms.CheckBox
    $checkboxSelectAll.Location = New-Object System.Drawing.Point(10, 430)
    $checkboxSelectAll.Size = New-Object System.Drawing.Size(150, 20)
    $checkboxSelectAll.Text = "Select/Deselect All"
    $checkboxSelectAll.Add_CheckedChanged({
            $isChecked = $checkboxSelectAll.Checked
            foreach ($item in $listView.Items) {
                $item.Checked = $isChecked
            }
        })
    $form.Controls.Add($checkboxSelectAll)

    # Button to remove selected workstations and export details to CSV
    $buttonRemove = New-Object System.Windows.Forms.Button
    $buttonRemove.Location = New-Object System.Drawing.Point(200, 430)
    $buttonRemove.Size = New-Object System.Drawing.Size(480, 40)
    $buttonRemove.Text = "Remove Selected Workstations and Export to CSV"
    $buttonRemove.Add_Click({
            $selectedItems = $listView.CheckedItems
            if ($selectedItems.Count -eq 0) {
                Show-ErrorMessage "No workstations selected for removal."
                return
            }

            $DCName = $comboBoxDC.SelectedItem
            if ([string]::IsNullOrWhiteSpace($DCName)) {
                Show-ErrorMessage "Domain Controller FQDN is missing."
                return
            }

            $selectedComputers = $selectedItems | ForEach-Object { $_.Tag }
            Remove-SelectedWorkstationAccounts -SelectedComputers $selectedComputers -DCName $DCName
        })
    $form.Controls.Add($buttonRemove)

    $form.ShowDialog() | Out-Null
}

# Call the Show-GUI function to display the GUI and start the script
Show-GUI

# End of script
