<#
.SYNOPSIS
    PowerShell Script for Moving AD User Accounts Between OUs.

.DESCRIPTION
    This script allows administrators to relocate Active Directory (AD) user accounts 
    between Organizational Units (OUs), simplifying organizational structure adjustments.
    It provides two functionalities:
    1. Move users listed in a TXT file to a target OU.
    2. Move all users from a source OU to a target OU.

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

# Import required modules with error handling
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
        exit
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

# Function to retrieve all domain FQDNs in the current forest
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

# Function to move users from a TXT file to a target OU
function Move-UsersFromTXT {
    param (
        [Parameter(Mandatory = $true)][string]$TargetOU,
        [Parameter(Mandatory = $true)][string]$DomainFQDN,
        [Parameter(Mandatory = $true)][string]$UserListFile,
        [System.Windows.Forms.ProgressBar]$ProgressBar
    )

    if (-not (Test-Path $UserListFile)) {
        Show-ErrorMessage "User list file not found: $UserListFile"
        Log-Message "User list file not found: $UserListFile" -MessageType "ERROR"
        return
    }

    try {
        $users = @(Get-Content -Path $UserListFile -ErrorAction Stop)
        $totalUsers = ($users | Measure-Object).Count
        if ($totalUsers -eq 0) {
            Show-InfoMessage "User list file is empty."
            Log-Message "User list file is empty: $UserListFile" -MessageType "WARN"
            return
        }

        $ProgressBar.Minimum = 0
        $ProgressBar.Maximum = $totalUsers
        $completedUsers = 0

        Log-Message "Starting to move users from TXT file. Total count: $totalUsers"

        foreach ($userName in $users) {
            $userName = $userName.Trim()
            if ([string]::IsNullOrWhiteSpace($userName)) {
                continue
            }

            try {
                # Use -Identity to search across the entire domain
                $user = Get-ADUser -Identity $userName -Server $DomainFQDN -ErrorAction Stop
                if ($user) {
                    Move-ADObject -Identity $user.DistinguishedName -TargetPath $TargetOU -Server $DomainFQDN -ErrorAction Stop
                    Log-Message "Moved user '$userName' to '$TargetOU'"
                } else {
                    Log-Message "User '$userName' not found in the domain '$DomainFQDN'" -MessageType "WARN"
                }
            } catch {
                Log-Message "Error moving user '$userName' to '$TargetOU': $_" -MessageType "ERROR"
            }
            $completedUsers++
            $ProgressBar.Value = $completedUsers
            [System.Windows.Forms.Application]::DoEvents()
        }

        Log-Message "Completed moving users from TXT file."
        Show-InfoMessage "Users moved successfully from TXT file."
    } catch {
        Log-Message "Error processing user list: $_" -MessageType "ERROR"
        Show-ErrorMessage "An error occurred while processing the user list. Check the log for details."
    }
}

# Function to move all users from a source OU to a target OU
function Move-UsersFromOUToOU {
    param (
        [Parameter(Mandatory = $true)][string]$SourceOU,
        [Parameter(Mandatory = $true)][string]$TargetOU,
        [Parameter(Mandatory = $true)][string]$DomainFQDN,
        [System.Windows.Forms.ProgressBar]$ProgressBar
    )

    try {
        $users = @(Get-ADUser -Filter * -SearchBase $SourceOU -Server $DomainFQDN -ErrorAction Stop)
        $totalUsers = ($users | Measure-Object).Count
        if ($totalUsers -eq 0) {
            Show-InfoMessage "No users found in the source OU."
            Log-Message "No users found in the source OU: $SourceOU" -MessageType "WARN"
            return
        }

        $ProgressBar.Minimum = 0
        $ProgressBar.Maximum = $totalUsers
        $completedUsers = 0

        Log-Message "Starting to move $totalUsers users from '$SourceOU' to '$TargetOU' in domain '$DomainFQDN'."

        foreach ($user in $users) {
            $userName = $user.SamAccountName
            try {
                Move-ADObject -Identity $user.DistinguishedName -TargetPath $TargetOU -Server $DomainFQDN -ErrorAction Stop
                Log-Message "Moved user '$userName' from '$SourceOU' to '$TargetOU'"
            } catch {
                Log-Message "Error moving user '$userName' from '$SourceOU' to '$TargetOU': $_" -MessageType "ERROR"
            }
            $completedUsers++
            $ProgressBar.Value = $completedUsers
            [System.Windows.Forms.Application]::DoEvents()
        }

        Log-Message "Completed moving users from '$SourceOU' to '$TargetOU'."
        Show-InfoMessage "All users have been moved successfully from '$SourceOU' to '$TargetOU'."
    } catch {
        Log-Message "Error retrieving or moving users from source OU: $_" -MessageType "ERROR"
        Show-ErrorMessage "An error occurred while moving users from the source OU. Check the log for details."
    }
}

# Function to show the main form
function Show-MoveUsersForm {
    # Initialize the form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Move Users Between OUs"
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

    # Label and TextBox for User List File path
    $labelUserListTXT = New-Object System.Windows.Forms.Label
    $labelUserListTXT.Text = "Path to User List File:"
    $labelUserListTXT.Location = New-Object System.Drawing.Point(10, 170)
    $labelUserListTXT.AutoSize = $true
    $tabPageTXT.Controls.Add($labelUserListTXT)

    $textBoxUserListTXT = New-Object System.Windows.Forms.TextBox
    $textBoxUserListTXT.Location = New-Object System.Drawing.Point(10, 195)
    $textBoxUserListTXT.Size = New-Object System.Drawing.Size(450, 20)
    $tabPageTXT.Controls.Add($textBoxUserListTXT)

    # Button to browse for User List File
    $buttonBrowseTXT = New-Object System.Windows.Forms.Button
    $buttonBrowseTXT.Text = "Browse"
    $buttonBrowseTXT.Location = New-Object System.Drawing.Point(470, 193)
    $buttonBrowseTXT.Size = New-Object System.Drawing.Size(90, 25)
    $buttonBrowseTXT.Add_Click({
            $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $openFileDialog.Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
            if ($openFileDialog.ShowDialog() -eq 'OK') {
                $textBoxUserListTXT.Text = $openFileDialog.FileName
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
    $buttonExecuteTXT.Text = "Move Users"
    $buttonExecuteTXT.Location = New-Object System.Drawing.Point(10, 270)
    $buttonExecuteTXT.Size = New-Object System.Drawing.Size(550, 30)
    $buttonExecuteTXT.Add_Click({
            $domain = $comboBoxDomainTXT.SelectedItem
            $targetOU = $comboBoxTargetOU_TXT.SelectedItem
            $filePath = $textBoxUserListTXT.Text

            if ([string]::IsNullOrWhiteSpace($domain) -or [string]::IsNullOrWhiteSpace($targetOU) -or [string]::IsNullOrWhiteSpace($filePath)) {
                Show-ErrorMessage "Please provide all required inputs in 'Move from TXT file' tab."
                return
            }

            if (-not (Test-Path $filePath)) {
                Show-ErrorMessage "User list file not found: $filePath"
                return
            }

            # Confirm action
            $confirmResult = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to move the specified users to the target OU?", "Confirm Move", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($confirmResult -eq [System.Windows.Forms.DialogResult]::No) {
                Log-Message "Move operation cancelled by user in 'Move from TXT file' tab."
                return
            }

            Log-Message "Starting move operation from TXT file to '$targetOU' in domain '$domain'."

            # Disable the execute button to prevent multiple clicks
            $buttonExecuteTXT.Enabled = $false

            Move-UsersFromTXT -TargetOU $targetOU -DomainFQDN $domain -UserListFile $filePath -ProgressBar $progressBarTXT

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
    $buttonExecuteOU.Text = "Move Users"
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
            $confirmResult = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to move all users from the source OU to the target OU?", "Confirm Move", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($confirmResult -eq [System.Windows.Forms.DialogResult]::No) {
                Log-Message "Move operation cancelled by user in 'Move OU to OU' tab."
                return
            }

            Log-Message "Starting move operation from '$sourceOU' to '$targetOU' in domain '$domain'."

            # Disable the execute button to prevent multiple clicks
            $buttonExecuteOU.Enabled = $false

            Move-UsersFromOUToOU -SourceOU $sourceOU -TargetOU $targetOU -DomainFQDN $domain -ProgressBar $progressBarOU

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
            $selectedDomain = $comboBoxDomainTXT.SelectedItem
            if ($null -ne $selectedDomain) {
                $currentOUs = Get-OUsForDomain -DomainFQDN $selectedDomain
                Update-OUComboBox -SearchText $textBoxTargetOUSearchTXT.Text -ComboBox $comboBoxTargetOU_TXT -OUs $currentOUs
            }
        })

    # Real-time OU filtering for Source OU in OU to OU tab
    $textBoxSourceOUSearchOU.Add_TextChanged({
            $selectedDomain = $comboBoxDomainOU.SelectedItem
            if ($null -ne $selectedDomain) {
                $currentOUs = Get-OUsForDomain -DomainFQDN $selectedDomain
                Update-OUComboBox -SearchText $textBoxSourceOUSearchOU.Text -ComboBox $comboBoxSourceOU_OU -OUs $currentOUs
            }
        })

    # Real-time OU filtering for Target OU in OU to OU tab
    $textBoxTargetOUSearchOU.Add_TextChanged({
            $selectedDomain = $comboBoxDomainOU.SelectedItem
            if ($null -ne $selectedDomain) {
                $currentOUs = Get-OUsForDomain -DomainFQDN $selectedDomain
                Update-OUComboBox -SearchText $textBoxTargetOUSearchOU.Text -ComboBox $comboBoxTargetOU_OU -OUs $currentOUs
            }
        })

    # Show the form
    [void]$form.ShowDialog()
}

# Execute the function to show the form
Show-MoveUsersForm

# End of script
