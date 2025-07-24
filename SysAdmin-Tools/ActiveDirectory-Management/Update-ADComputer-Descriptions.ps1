<#
.SYNOPSIS
    PowerShell Script for Updating AD Computer Descriptions via GUI.

.DESCRIPTION
    This script allows administrators to update Active Directory computer descriptions via a GUI, 
    simplifying the management of workstation information and improving accuracy in directory records.

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

# Import necessary libraries for GUI
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Import-Module ActiveDirectory

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
        Write-Error "Failed to create log directory at $logDir. Logging will not be possible."
        return
    }
}

# Initialize the CancelRequested variable
$CancelRequested = $false

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

# Function to display informational messages
function Show-InfoMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Information', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Log-Message "Info: $message" -MessageType "INFO"
}

# Function to retrieve all domains in the current forest
function Get-AllDomains {
    try {
        $forest = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
        return $forest.Domains | ForEach-Object { $_.Name }
    } catch {
        Show-ErrorMessage "Failed to retrieve domains: ${_}"
        return @()
    }
}

# Function to search for workstations (exclude servers)
function Get-Workstations {
    param (
        [string]$Domain
    )
    
    try {
        # Filters workstations based on OperatingSystem containing "Windows 10" or "Windows 11"
        $workstations = Get-ADComputer -Server $Domain -Filter { OperatingSystem -like "*Windows 10*" -or OperatingSystem -like "*Windows 11*" } -Properties OperatingSystem
        return $workstations
    } catch {
        Show-ErrorMessage "Failed to retrieve workstations from domain ${Domain}: ${_}"
        return @()
    }
}

# Function to update workstation descriptions and site information
function Update-WorkstationDescriptionsAndSite {
    param (
        [string]$DC,
        [string]$DefaultDesc,
        [string]$Site,
        [System.Windows.Forms.CheckedListBox]$Workstations,
        [System.Windows.Forms.ProgressBar]$ProgressBar,
        [System.Windows.Forms.Label]$StatusLabel,
        [System.Windows.Forms.Button]$ExecuteButton,
        [System.Windows.Forms.Button]$CancelButton,
        [ref]$CancelRequested
    )

    try {
        Log-Message "Starting update operation."
        $StatusLabel.Text = "Starting updates..."
        $ProgressBar.Value = 0

        $Credential = Get-Credential -Message "Enter admin credentials"
        $TotalWorkstations = $Workstations.CheckedItems.Count
        $CurrentCount = 0

        foreach ($Workstation in $Workstations.CheckedItems) {
            if ($CancelRequested.Value) {
                Log-Message "Update process canceled by user."
                $StatusLabel.Text = "Update process canceled."
                $ProgressBar.Value = 0
                return
            }

            $WorkstationName = $Workstation
            try {
                # Replace 'Info' with 'physicalDeliveryOfficeName' or any other appropriate attribute if needed
                Set-ADComputer -Server $DC -Identity $WorkstationName -Description $DefaultDesc -Replace @{Info = $Site } -Credential $Credential -ErrorAction Stop
                Log-Message "Updated ${WorkstationName} with description '${DefaultDesc}' and site '${Site}'"
            } catch {
                Show-ErrorMessage "Failed to update ${WorkstationName}: ${_}"
                Log-Message "Failed to update ${WorkstationName}: ${_}" -MessageType "ERROR"
            }

            $CurrentCount++
            $ProgressBar.Value = [math]::Round(($CurrentCount / $TotalWorkstations) * 100)
            $StatusLabel.Text = "Updating ${WorkstationName} ($CurrentCount of $TotalWorkstations)"
        }

        $ProgressBar.Value = 100
        Start-Sleep -Seconds 2
        Show-InfoMessage "Update operation completed successfully."
        Log-Message "Update operation completed successfully."
    } catch {
        $ErrorMsg = "Error encountered: ${_}"
        Show-ErrorMessage $ErrorMsg
        $ProgressBar.Value = 0
    } finally {
        $ExecuteButton.Enabled = $true
        $CancelButton.Enabled = $false
    }
}

# Initialize form components
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Update Workstation Descriptions and Site Information'
$form.Size = New-Object System.Drawing.Size(750, 600)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false

# Domain label and combo box
$labelDomain = New-Object System.Windows.Forms.Label
$labelDomain.Text = 'Select Domain:'
$labelDomain.Location = New-Object System.Drawing.Point(10, 20)
$labelDomain.Size = New-Object System.Drawing.Size(120, 20)
$form.Controls.Add($labelDomain)

$comboBoxDomain = New-Object System.Windows.Forms.ComboBox
$comboBoxDomain.Location = New-Object System.Drawing.Point(140, 20)
$comboBoxDomain.Size = New-Object System.Drawing.Size(580, 20)
$comboBoxDomain.DropDownStyle = 'DropDownList'
$form.Controls.Add($comboBoxDomain)

# Populate domains in the combo box
$domains = Get-AllDomains
foreach ($domain in $domains) {
    $comboBoxDomain.Items.Add($domain)
}

if ($comboBoxDomain.Items.Count -gt 0) {
    $comboBoxDomain.SelectedIndex = 0
}

# Description label and textbox
$labelDesc = New-Object System.Windows.Forms.Label
$labelDesc.Text = 'Default Workstation Description:'
$labelDesc.Location = New-Object System.Drawing.Point(10, 60)
$labelDesc.Size = New-Object System.Drawing.Size(200, 20)
$form.Controls.Add($labelDesc)

$textBoxDesc = New-Object System.Windows.Forms.TextBox
$textBoxDesc.Location = New-Object System.Drawing.Point(220, 60)
$textBoxDesc.Size = New-Object System.Drawing.Size(500, 20)
$form.Controls.Add($textBoxDesc)

# Site Information label and textbox
$labelSite = New-Object System.Windows.Forms.Label
$labelSite.Text = 'Site Information:'
$labelSite.Location = New-Object System.Drawing.Point(10, 100)
$labelSite.Size = New-Object System.Drawing.Size(200, 20)
$form.Controls.Add($labelSite)

$textBoxSite = New-Object System.Windows.Forms.TextBox
$textBoxSite.Location = New-Object System.Drawing.Point(220, 100)
$textBoxSite.Size = New-Object System.Drawing.Size(500, 20)
$form.Controls.Add($textBoxSite)

# Workstations ListBox label
$labelWorkstations = New-Object System.Windows.Forms.Label
$labelWorkstations.Text = 'Select Workstations to Update:'
$labelWorkstations.Location = New-Object System.Drawing.Point(10, 140)
$labelWorkstations.Size = New-Object System.Drawing.Size(200, 20)
$form.Controls.Add($labelWorkstations)

# Workstations ListBox
$listBoxWorkstations = New-Object System.Windows.Forms.CheckedListBox
$listBoxWorkstations.Location = New-Object System.Drawing.Point(10, 160)
$listBoxWorkstations.Size = New-Object System.Drawing.Size(710, 200)
$listBoxWorkstations.CheckOnClick = $true
$form.Controls.Add($listBoxWorkstations)

# Select All checkbox for workstations
$chkSelectAll = New-Object System.Windows.Forms.CheckBox
$chkSelectAll.Text = "Select All"
$chkSelectAll.Location = New-Object System.Drawing.Point(10, 370)
$chkSelectAll.Size = New-Object System.Drawing.Size(100, 20)
$form.Controls.Add($chkSelectAll)

# Function to handle Select All checkbox with optimization to prevent freezing
$chkSelectAll.Add_CheckedChanged({
        $listBoxWorkstations.BeginUpdate()
        if ($chkSelectAll.Checked) {
            for ($i = 0; $i -lt $listBoxWorkstations.Items.Count; $i++) {
                $listBoxWorkstations.SetItemChecked($i, $true)
            }
        } else {
            for ($i = 0; $i -lt $listBoxWorkstations.Items.Count; $i++) {
                $listBoxWorkstations.SetItemChecked($i, $false)
            }
        }
        $listBoxWorkstations.EndUpdate()
    })

# Panel to hold buttons at the bottom
$panelButtons = New-Object System.Windows.Forms.Panel
$panelButtons.Location = New-Object System.Drawing.Point(0, 420)
$panelButtons.Size = New-Object System.Drawing.Size(750, 60)
$panelButtons.Anchor = 'Bottom, Left, Right'
$form.Controls.Add($panelButtons)

# Search Workstations button (now moved to the bottom panel)
$buttonSearchWorkstations = New-Object System.Windows.Forms.Button
$buttonSearchWorkstations.Text = 'Search Workstations'
$buttonSearchWorkstations.Size = New-Object System.Drawing.Size(150, 30)
$buttonSearchWorkstations.Location = New-Object System.Drawing.Point(20, 15)
$buttonSearchWorkstations.Add_Click({
        $selectedDomain = $comboBoxDomain.SelectedItem
        if (-not $selectedDomain) {
            Show-ErrorMessage "Please select a domain."
            return
        }

        $workstations = Get-Workstations -Domain $selectedDomain
        $listBoxWorkstations.Items.Clear()

        if ($workstations.Count -gt 0) {
            $listBoxWorkstations.BeginUpdate()
            foreach ($workstation in $workstations) {
                $listBoxWorkstations.Items.Add($workstation.Name)
            }
            $listBoxWorkstations.EndUpdate()
            Show-InfoMessage "$($workstations.Count) workstations found."
            $executeButton.Enabled = $true
        } else {
            Show-InfoMessage "No workstations found in the domain ${selectedDomain}."
            $executeButton.Enabled = $false
        }
    })
$panelButtons.Controls.Add($buttonSearchWorkstations)

# Execute button
$executeButton = New-Object System.Windows.Forms.Button
$executeButton.Text = 'Execute'
$executeButton.Size = New-Object System.Drawing.Size(100, 30)
$executeButton.Location = New-Object System.Drawing.Point(200, 15)
$executeButton.Enabled = $false
$executeButton.Add_Click({
        $selectedDomain = $comboBoxDomain.SelectedItem
        $defaultDesc = $textBoxDesc.Text.Trim()
        $siteInfo = $textBoxSite.Text.Trim()
        $selectedWorkstations = $listBoxWorkstations.CheckedItems

        # Input validation
        if (-not $selectedDomain) {
            Show-ErrorMessage "Please select a domain."
            return
        }

        if ([string]::IsNullOrWhiteSpace($defaultDesc)) {
            Show-ErrorMessage "Please enter a default workstation description."
            return
        }

        if ([string]::IsNullOrWhiteSpace($siteInfo)) {
            Show-ErrorMessage "Please enter site information."
            return
        }

        if ($selectedWorkstations.Count -eq 0) {
            Show-ErrorMessage "Please select at least one workstation to update."
            return
        }

        $executeButton.Enabled = $false
        $cancelButton.Enabled = $true
        $CancelRequested = $false

        Update-WorkstationDescriptionsAndSite -DC $selectedDomain `
            -DefaultDesc $defaultDesc `
            -Site $siteInfo `
            -Workstations $listBoxWorkstations `
            -ProgressBar $progressBar `
            -StatusLabel $statusLabel `
            -ExecuteButton $executeButton `
            -CancelButton $cancelButton `
            -CancelRequested ([ref]$CancelRequested)
    })
$panelButtons.Controls.Add($executeButton)

# Cancel button
$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = 'Cancel'
$cancelButton.Size = New-Object System.Drawing.Size(100, 30)
$cancelButton.Location = New-Object System.Drawing.Point(320, 15)
$cancelButton.Enabled = $false
$cancelButton.Add_Click({
        $confirm = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to cancel the update?", "Cancel Confirmation", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
            $CancelRequested.Value = $true
            Log-Message "User requested to cancel the update."
            $statusLabel.Text = "Canceling update..."
        }
    })
$panelButtons.Controls.Add($cancelButton)

# Close button
$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = 'Close'
$closeButton.Size = New-Object System.Drawing.Size(100, 30)
$closeButton.Location = New-Object System.Drawing.Point(440, 15)
$closeButton.Add_Click({ $form.Close() })
$panelButtons.Controls.Add($closeButton)

# Progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 500)
$progressBar.Size = New-Object System.Drawing.Size(710, 20)
$progressBar.Style = 'Continuous'
$form.Controls.Add($progressBar)

# Status label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(20, 530)
$statusLabel.Size = New-Object System.Drawing.Size(710, 20)
$form.Controls.Add($statusLabel)

# Enable Execute button when workstations are selected
$listBoxWorkstations.Add_ItemCheck({
        # Delay the execution to allow the item check to update
        Start-Sleep -Milliseconds 100
        if ($listBoxWorkstations.CheckedItems.Count -gt 0) {
            $executeButton.Enabled = $true
        } else {
            $executeButton.Enabled = $false
        }
    })

# Show the form
$form.Add_Shown({
        $form.Activate()
    })

[void]$form.ShowDialog()

# End of script
