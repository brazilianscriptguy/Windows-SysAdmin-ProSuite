<#
.SYNOPSIS
    PowerShell Script for Moving AD Computer Accounts Between OUs.

.DESCRIPTION
    This script allows administrators to relocate Active Directory (AD) computer accounts 
    between Organizational Units (OUs), simplifying organizational structure adjustments.
    It provides two functionalities:
    1. Move computers listed in a TXT file to a target OU.
    2. Move all computers from a source OU to a target OU.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: November 27, 2024
#>

# Hide PowerShell console window
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
}
"@
[Window]::Hide()

# Import required modules
try {
    Add-Type -AssemblyName System.Windows.Forms
} catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to load System.Windows.Forms assembly. $_", "Initialization Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to import ActiveDirectory module. Please ensure it is installed.", "Module Import Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit
}

# Determine the script name and set up logging path
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logPath = Join-Path $logDir "${scriptName}.log"

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to create log directory at $logDir. Logging will not be possible.", "Logging Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

# Enhanced logging function with error handling
function Log-Message {
    param (
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $false)][ValidateSet("INFO", "WARN", "ERROR")][string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$MessageType] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to write to log: $_", "Logging Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

# Function to display informational messages
function Show-InfoMessage {
    param ([string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, 'Information', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Log-Message $Message -MessageType "INFO"
}

# Function to display error messages
function Show-ErrorMessage {
    param ([string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    Log-Message $Message -MessageType "ERROR"
}

# Function to retrieve all domains in the forest
function Get-AllDomainFQDNs {
    try {
        $forest = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
        return $forest.Domains | ForEach-Object { $_.Name }
    } catch {
        Log-Message "Failed to retrieve domains: $_" -MessageType "ERROR"
        Show-ErrorMessage "Failed to retrieve domains. Check the log for details."
        return @()
    }
}

# Function to retrieve OUs for a specific domain
function Get-OUsForDomain {
    param (
        [Parameter(Mandatory = $true)][string]$DomainFQDN
    )
    try {
        return Get-ADOrganizationalUnit -Filter * -Server $DomainFQDN | Select-Object -ExpandProperty DistinguishedName
    } catch {
        Log-Message "Failed to retrieve OUs for domain ${DomainFQDN}: $_" -MessageType "ERROR"
        Show-ErrorMessage "Failed to retrieve OUs for domain $DomainFQDN. Check the log for details."
        return @()
    }
}

# Function to update ComboBox items based on search text and available OUs
function Update-OUComboBox {
    param (
        [string]$SearchText,
        [System.Windows.Forms.ComboBox]$ComboBox,
        [array]$OUs
    )
    $ComboBox.Items.Clear()
    $filteredOUs = $OUs | Where-Object { $_ -like "*$SearchText*" }
    foreach ($ou in $filteredOUs) {
        $ComboBox.Items.Add($ou)
    }
    if ($ComboBox.Items.Count -gt 0) {
        $ComboBox.SelectedIndex = 0
    } else {
        $ComboBox.Text = 'No matching OU found'
    }
}

# Function to move computers from a TXT file to a target OU
function Move-ComputersFromTXT {
    param (
        [Parameter(Mandatory = $true)][string]$TargetOU,
        [Parameter(Mandatory = $true)][string]$DomainFQDN,
        [Parameter(Mandatory = $true)][string]$ComputerListFile,
        [System.Windows.Forms.ProgressBar]$ProgressBar
    )

    if (-not (Test-Path $ComputerListFile)) {
        Show-ErrorMessage "Computer list file not found: $ComputerListFile"
        Log-Message "Computer list file not found: $ComputerListFile" -MessageType "ERROR"
        return
    }

    try {
        $computers = @(Get-Content -Path $ComputerListFile -ErrorAction Stop)
        $totalComputers = ($computers | Measure-Object).Count
        if ($totalComputers -eq 0) {
            Show-InfoMessage "Computer list file is empty."
            Log-Message "Computer list file is empty: $ComputerListFile" -MessageType "WARN"
            return
        }

        $ProgressBar.Minimum = 0
        $ProgressBar.Maximum = $totalComputers
        $completedComputers = 0

        Log-Message "Starting to move computers from TXT file. Total count: $totalComputers"

        foreach ($computerName in $computers) {
            $computerName = $computerName.Trim()
            if ([string]::IsNullOrWhiteSpace($computerName)) {
                continue
            }

            try {
                # Use -Identity to search across the entire domain
                $computer = Get-ADComputer -Identity $computerName -Server $DomainFQDN -ErrorAction Stop
                if ($computer) {
                    Move-ADObject -Identity $computer.DistinguishedName -TargetPath $TargetOU -Server $DomainFQDN -ErrorAction Stop
                    Log-Message "Moved computer '$computerName' to '$TargetOU'"
                } else {
                    Log-Message "Computer '$computerName' not found in the domain '$DomainFQDN'" -MessageType "WARN"
                }
            } catch {
                Log-Message "Error moving computer '$computerName' to '$TargetOU': $_" -MessageType "ERROR"
            }
            $completedComputers++
            $ProgressBar.Value = $completedComputers
            [System.Windows.Forms.Application]::DoEvents()
        }

        Log-Message "Completed moving computers from TXT file."
        Show-InfoMessage "Computers moved successfully from TXT file."
    } catch {
        Log-Message "Error processing computer list: $_" -MessageType "ERROR"
        Show-ErrorMessage "An error occurred while processing the computer list. Check the log for details."
    }
}

# Function to move all computers from a source OU to a target OU
function Move-ComputersFromOUToOU {
    param (
        [Parameter(Mandatory = $true)][string]$SourceOU,
        [Parameter(Mandatory = $true)][string]$TargetOU,
        [Parameter(Mandatory = $true)][string]$DomainFQDN,
        [System.Windows.Forms.ProgressBar]$ProgressBar
    )

    try {
        $computers = @(Get-ADComputer -Filter * -SearchBase $SourceOU -Server $DomainFQDN -ErrorAction Stop)
        $totalComputers = ($computers | Measure-Object).Count
        if ($totalComputers -eq 0) {
            Show-InfoMessage "No computers found in the source OU."
            Log-Message "No computers found in the source OU: $SourceOU" -MessageType "WARN"
            return
        }

        $ProgressBar.Minimum = 0
        $ProgressBar.Maximum = $totalComputers
        $completedComputers = 0

        Log-Message "Starting to move $totalComputers computers from '$SourceOU' to '$TargetOU' in domain '$DomainFQDN'."

        foreach ($computer in $computers) {
            $computerName = $computer.Name
            try {
                Move-ADObject -Identity $computer.DistinguishedName -TargetPath $TargetOU -Server $DomainFQDN -ErrorAction Stop
                Log-Message "Moved computer '$computerName' from '$SourceOU' to '$TargetOU'"
            } catch {
                Log-Message "Error moving computer '$computerName' from '$SourceOU' to '$TargetOU': $_" -MessageType "ERROR"
            }
            $completedComputers++
            $ProgressBar.Value = $completedComputers
            [System.Windows.Forms.Application]::DoEvents()
        }

        Log-Message "Completed moving computers from '$SourceOU' to '$TargetOU'."
        Show-InfoMessage "All computers have been moved successfully from '$SourceOU' to '$TargetOU'."
    } catch {
        Log-Message "Error retrieving or moving computers from source OU: $_" -MessageType "ERROR"
        Show-ErrorMessage "An error occurred while moving computers from the source OU. Check the log for details."
    }
}

# Function to show the main form
function Show-MoveComputersForm {
    # Initialize the form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Move Computers Between OUs"
    $form.Size = New-Object System.Drawing.Size(620, 500)
    $form.StartPosition = "CenterScreen"

    # Create TabControl
    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Size = New-Object System.Drawing.Size(580, 420)
    $tabControl.Location = New-Object System.Drawing.Point(10, 10)
    $form.Controls.Add($tabControl)

    # Create TabPage for "Move from TXT file"
    $tabPageTXT = New-Object System.Windows.Forms.TabPage
    $tabPageTXT.Text = "Move from TXT file"
    $tabControl.Controls.Add($tabPageTXT)

    # Create TabPage for "Move OU to OU"
    $tabPageOU = New-Object System.Windows.Forms.TabPage
    $tabPageOU.Text = "Move OU to OU"
    $tabControl.Controls.Add($tabPageOU)

    ##############################
    # Controls for "Move from TXT file" Tab
    ##############################

    # Label for Domain selection
    $labelDomainTXT = New-Object System.Windows.Forms.Label
    $labelDomainTXT.Text = "Select Domain FQDN:"
    $labelDomainTXT.Location = New-Object System.Drawing.Point(10, 20)
    $labelDomainTXT.AutoSize = $true
    $tabPageTXT.Controls.Add($labelDomainTXT)

    # ComboBox for Domain selection
    $comboBoxDomainTXT = New-Object System.Windows.Forms.ComboBox
    $comboBoxDomainTXT.Location = New-Object System.Drawing.Point(10, 45)
    $comboBoxDomainTXT.Size = New-Object System.Drawing.Size(550, 25)
    $comboBoxDomainTXT.DropDownStyle = 'DropDownList'
    $tabPageTXT.Controls.Add($comboBoxDomainTXT)

    # Label and TextBox for Target OU search
    $labelTargetOUSearchTXT = New-Object System.Windows.Forms.Label
    $labelTargetOUSearchTXT.Text = "Search Target OU:"
    $labelTargetOUSearchTXT.Location = New-Object System.Drawing.Point(10, 80)
    $labelTargetOUSearchTXT.AutoSize = $true
    $tabPageTXT.Controls.Add($labelTargetOUSearchTXT)

    $textBoxTargetOUSearchTXT = New-Object System.Windows.Forms.TextBox
    $textBoxTargetOUSearchTXT.Location = New-Object System.Drawing.Point(10, 105)
    $textBoxTargetOUSearchTXT.Size = New-Object System.Drawing.Size(550, 20)
    $tabPageTXT.Controls.Add($textBoxTargetOUSearchTXT)

    # ComboBox for Target OU selection
    $comboBoxTargetOU_TXT = New-Object System.Windows.Forms.ComboBox
    $comboBoxTargetOU_TXT.Location = New-Object System.Drawing.Point(10, 130)
    $comboBoxTargetOU_TXT.Size = New-Object System.Drawing.Size(550, 25)
    $comboBoxTargetOU_TXT.DropDownStyle = 'DropDownList'
    $tabPageTXT.Controls.Add($comboBoxTargetOU_TXT)

    # Label and TextBox for Computer List File path
    $labelComputerListTXT = New-Object System.Windows.Forms.Label
    $labelComputerListTXT.Text = "Path to Computer List File:"
    $labelComputerListTXT.Location = New-Object System.Drawing.Point(10, 170)
    $labelComputerListTXT.AutoSize = $true
    $tabPageTXT.Controls.Add($labelComputerListTXT)

    $textBoxComputerListTXT = New-Object System.Windows.Forms.TextBox
    $textBoxComputerListTXT.Location = New-Object System.Drawing.Point(10, 195)
    $textBoxComputerListTXT.Size = New-Object System.Drawing.Size(450, 20)
    $tabPageTXT.Controls.Add($textBoxComputerListTXT)

    # Button to browse for Computer List File
    $buttonBrowseTXT = New-Object System.Windows.Forms.Button
    $buttonBrowseTXT.Text = "Browse"
    $buttonBrowseTXT.Location = New-Object System.Drawing.Point(470, 193)
    $buttonBrowseTXT.Size = New-Object System.Drawing.Size(90, 25)
    $buttonBrowseTXT.Add_Click({
            $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $openFileDialog.Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
            if ($openFileDialog.ShowDialog() -eq 'OK') {
                $textBoxComputerListTXT.Text = $openFileDialog.FileName
            }
        })
    $tabPageTXT.Controls.Add($buttonBrowseTXT)

    # Progress bar for TXT file move
    $progressBarTXT = New-Object System.Windows.Forms.ProgressBar
    $progressBarTXT.Location = New-Object System.Drawing.Point(10, 230)
    $progressBarTXT.Size = New-Object System.Drawing.Size(550, 25)
    $tabPageTXT.Controls.Add($progressBarTXT)

    # Button to execute the move from TXT file
    $buttonExecuteTXT = New-Object System.Windows.Forms.Button
    $buttonExecuteTXT.Text = "Move Computers"
    $buttonExecuteTXT.Location = New-Object System.Drawing.Point(10, 270)
    $buttonExecuteTXT.Size = New-Object System.Drawing.Size(550, 30)
    $buttonExecuteTXT.Add_Click({
            $domain = $comboBoxDomainTXT.SelectedItem
            $targetOU = $comboBoxTargetOU_TXT.SelectedItem
            $filePath = $textBoxComputerListTXT.Text

            if ([string]::IsNullOrWhiteSpace($domain) -or [string]::IsNullOrWhiteSpace($targetOU) -or [string]::IsNullOrWhiteSpace($filePath)) {
                Show-ErrorMessage "Please provide all required inputs in 'Move from TXT file' tab."
                return
            }

            if (-not (Test-Path $filePath)) {
                Show-ErrorMessage "Computer list file not found: $filePath"
                return
            }

            # Confirm action
            $confirmResult = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to move the specified computers to the target OU?", "Confirm Move", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($confirmResult -eq [System.Windows.Forms.DialogResult]::No) {
                Log-Message "Move operation cancelled by user in 'Move from TXT file' tab."
                return
            }

            Log-Message "Starting move operation from TXT file to '$targetOU' in domain '$domain'."

            # Disable the execute button to prevent multiple clicks
            $buttonExecuteTXT.Enabled = $false

            Move-ComputersFromTXT -TargetOU $targetOU -DomainFQDN $domain -ComputerListFile $filePath -ProgressBar $progressBarTXT

            # Re-enable the execute button
            $buttonExecuteTXT.Enabled = $true
        })
    $tabPageTXT.Controls.Add($buttonExecuteTXT)

    ##############################
    # Controls for "Move OU to OU" Tab
    ##############################

    # Label for Domain selection
    $labelDomainOU = New-Object System.Windows.Forms.Label
    $labelDomainOU.Text = "Select Domain FQDN:"
    $labelDomainOU.Location = New-Object System.Drawing.Point(10, 20)
    $labelDomainOU.AutoSize = $true
    $tabPageOU.Controls.Add($labelDomainOU)

    # ComboBox for Domain selection
    $comboBoxDomainOU = New-Object System.Windows.Forms.ComboBox
    $comboBoxDomainOU.Location = New-Object System.Drawing.Point(10, 45)
    $comboBoxDomainOU.Size = New-Object System.Drawing.Size(550, 25)
    $comboBoxDomainOU.DropDownStyle = 'DropDownList'
    $tabPageOU.Controls.Add($comboBoxDomainOU)

    # Label and TextBox for Source OU search
    $labelSourceOUSearchOU = New-Object System.Windows.Forms.Label
    $labelSourceOUSearchOU.Text = "Search Source OU:"
    $labelSourceOUSearchOU.Location = New-Object System.Drawing.Point(10, 80)
    $labelSourceOUSearchOU.AutoSize = $true
    $tabPageOU.Controls.Add($labelSourceOUSearchOU)

    $textBoxSourceOUSearchOU = New-Object System.Windows.Forms.TextBox
    $textBoxSourceOUSearchOU.Location = New-Object System.Drawing.Point(10, 105)
    $textBoxSourceOUSearchOU.Size = New-Object System.Drawing.Size(550, 20)
    $tabPageOU.Controls.Add($textBoxSourceOUSearchOU)

    # ComboBox for Source OU selection
    $comboBoxSourceOU_OU = New-Object System.Windows.Forms.ComboBox
    $comboBoxSourceOU_OU.Location = New-Object System.Drawing.Point(10, 130)
    $comboBoxSourceOU_OU.Size = New-Object System.Drawing.Size(550, 25)
    $comboBoxSourceOU_OU.DropDownStyle = 'DropDownList'
    $tabPageOU.Controls.Add($comboBoxSourceOU_OU)

    # Label and TextBox for Target OU search
    $labelTargetOUSearchOU = New-Object System.Windows.Forms.Label
    $labelTargetOUSearchOU.Text = "Search Target OU:"
    $labelTargetOUSearchOU.Location = New-Object System.Drawing.Point(10, 170)
    $labelTargetOUSearchOU.AutoSize = $true
    $tabPageOU.Controls.Add($labelTargetOUSearchOU)

    $textBoxTargetOUSearchOU = New-Object System.Windows.Forms.TextBox
    $textBoxTargetOUSearchOU.Location = New-Object System.Drawing.Point(10, 195)
    $textBoxTargetOUSearchOU.Size = New-Object System.Drawing.Size(550, 20)
    $tabPageOU.Controls.Add($textBoxTargetOUSearchOU)

    # ComboBox for Target OU selection
    $comboBoxTargetOU_OU = New-Object System.Windows.Forms.ComboBox
    $comboBoxTargetOU_OU.Location = New-Object System.Drawing.Point(10, 220)
    $comboBoxTargetOU_OU.Size = New-Object System.Drawing.Size(550, 25)
    $comboBoxTargetOU_OU.DropDownStyle = 'DropDownList'
    $tabPageOU.Controls.Add($comboBoxTargetOU_OU)

    # Progress bar for OU to OU move
    $progressBarOU = New-Object System.Windows.Forms.ProgressBar
    $progressBarOU.Location = New-Object System.Drawing.Point(10, 260)
    $progressBarOU.Size = New-Object System.Drawing.Size(550, 25)
    $tabPageOU.Controls.Add($progressBarOU)

    # Button to execute the move from OU to OU
    $buttonExecuteOU = New-Object System.Windows.Forms.Button
    $buttonExecuteOU.Text = "Move Computers"
    $buttonExecuteOU.Location = New-Object System.Drawing.Point(10, 300)
    $buttonExecuteOU.Size = New-Object System.Drawing.Size(550, 30)
    $buttonExecuteOU.Add_Click({
            $domain = $comboBoxDomainOU.SelectedItem
            $sourceOU = $comboBoxSourceOU_OU.SelectedItem
            $targetOU = $comboBoxTargetOU_OU.SelectedItem

            if ([string]::IsNullOrWhiteSpace($domain) -or [string]::IsNullOrWhiteSpace($sourceOU) -or [string]::IsNullOrWhiteSpace($targetOU)) {
                Show-ErrorMessage "Please provide all required inputs in 'Move OU to OU' tab."
                return
            }

            # Confirm action
            $confirmResult = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to move all computers from the source OU to the target OU?", "Confirm Move", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($confirmResult -eq [System.Windows.Forms.DialogResult]::No) {
                Log-Message "Move operation cancelled by user in 'Move OU to OU' tab."
                return
            }

            Log-Message "Starting move operation from '$sourceOU' to '$targetOU' in domain '$domain'."

            # Disable the execute button to prevent multiple clicks
            $buttonExecuteOU.Enabled = $false

            Move-ComputersFromOUToOU -SourceOU $sourceOU -TargetOU $targetOU -DomainFQDN $domain -ProgressBar $progressBarOU

            # Re-enable the execute button
            $buttonExecuteOU.Enabled = $true
        })
    $tabPageOU.Controls.Add($buttonExecuteOU)

    # Variables to store OUs
    $script:allOUs_TXT = @()
    $script:allOUs_OU = @()

    # Load domains into the ComboBoxes
    $script:allDomains = Get-AllDomainFQDNs
    $comboBoxDomainTXT.Items.AddRange($script:allDomains)
    $comboBoxDomainOU.Items.AddRange($script:allDomains)
    if ($comboBoxDomainTXT.Items.Count -gt 0) {
        $comboBoxDomainTXT.SelectedIndex = 0
    }
    if ($comboBoxDomainOU.Items.Count -gt 0) {
        $comboBoxDomainOU.SelectedIndex = 0
    }

    # Event handler for domain selection change in TXT tab
    $comboBoxDomainTXT.Add_SelectedIndexChanged({
            $selectedDomain = $comboBoxDomainTXT.SelectedItem
            if ($null -ne $selectedDomain) {
                $script:allOUs_TXT = Get-OUsForDomain -DomainFQDN $selectedDomain
                Update-OUComboBox -SearchText $textBoxTargetOUSearchTXT.Text -ComboBox $comboBoxTargetOU_TXT -OUs $script:allOUs_TXT
            }
        })

    # Event handler for domain selection change in OU to OU tab
    $comboBoxDomainOU.Add_SelectedIndexChanged({
            $selectedDomain = $comboBoxDomainOU.SelectedItem
            if ($null -ne $selectedDomain) {
                $script:allOUs_OU = Get-OUsForDomain -DomainFQDN $selectedDomain
                Update-OUComboBox -SearchText $textBoxSourceOUSearchOU.Text -ComboBox $comboBoxSourceOU_OU -OUs $script:allOUs_OU
                Update-OUComboBox -SearchText $textBoxTargetOUSearchOU.Text -ComboBox $comboBoxTargetOU_OU -OUs $script:allOUs_OU
            }
        })

    # Real-time OU filtering for Target OU in TXT tab
    $textBoxTargetOUSearchTXT.Add_TextChanged({
            Update-OUComboBox -SearchText $textBoxTargetOUSearchTXT.Text -ComboBox $comboBoxTargetOU_TXT -OUs $script:allOUs_TXT
        })

    # Real-time OU filtering for Source OU in OU to OU tab
    $textBoxSourceOUSearchOU.Add_TextChanged({
            Update-OUComboBox -SearchText $textBoxSourceOUSearchOU.Text -ComboBox $comboBoxSourceOU_OU -OUs $script:allOUs_OU
        })

    # Real-time OU filtering for Target OU in OU to OU tab
    $textBoxTargetOUSearchOU.Add_TextChanged({
            Update-OUComboBox -SearchText $textBoxTargetOUSearchOU.Text -ComboBox $comboBoxTargetOU_OU -OUs $script:allOUs_OU
        })

    # Show the form
    [void]$form.ShowDialog()
}

# Execute the function to show the form
Show-MoveComputersForm

# End of script
