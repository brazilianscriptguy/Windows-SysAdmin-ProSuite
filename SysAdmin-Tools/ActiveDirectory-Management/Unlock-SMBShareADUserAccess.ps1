<#
.SYNOPSIS
    PowerShell Script for Restoring SMB Share Access for AD Users.

.DESCRIPTION
    This script resolves issues with SMB share access for Active Directory (AD) users, 
    restoring access to shared resources and ensuring proper permissions are applied.

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

# Load Windows Forms and drawing libraries
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Configure error handling
$ErrorActionPreference = "Stop"

# Determine the script name and set up logging path
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logPath = Join-Path $logDir "$scriptName.log"

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -ErrorAction Stop
    } catch {
        Write-Error "Failed to create log directory at $logDir. Logging will not be possible."
        return
    }
}

# Logging function with error handling
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

# Function to display error messages
function Show-ErrorMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    Log-Message "Error: $message"
}

# Function to create a control element (label, combobox, etc.)
function Create-Control {
    param (
        [string]$type,
        [string]$text = '',
        [array]$location,
        [array]$size,
        [scriptblock]$onClick = $null,
        [array]$items = $null
    )
    $control = New-Object ("System.Windows.Forms.$type")
    $control.Text = $text
    $control.Location = New-Object System.Drawing.Point($location[0], $location[1])
    $control.Size = New-Object System.Drawing.Size($size[0], $size[1])

    if ($type -eq 'ComboBox') {
        $control.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        if ($items) { $control.Items.AddRange($items) }
    } elseif ($type -eq 'Button' -and $onClick) {
        $control.Add_Click($onClick)
    }
    return $control
}

# Function to gather DFS namespaces
function Get-DFSNamespaces {
    try {
        Get-SmbShare | Where-Object { $_.Special -eq $false } | Select-Object -ExpandProperty Name
    } catch {
        Show-ErrorMessage "Failed to retrieve DFS Namespaces: $_"
        return @()
    }
}

# Function to gather all permissions for a specific user
function Get-UserPermissions {
    param (
        [string]$username
    )
    try {
        $shares = Get-SmbShare
        $permissions = @()

        foreach ($share in $shares) {
            $access = Get-SmbShareAccess -Name $share.Name | Where-Object { $_.AccountName -eq $username }
            if ($access) {
                $permissions += $access
            }
        }
        return $permissions
    } catch {
        Show-ErrorMessage "Failed to retrieve permissions for user: $username"
        return @()
    }
}

# Function to unlock selected users
function Unlock-Users {
    param (
        [string]$shareName,
        [array]$selectedUsers
    )
    if ([string]::IsNullOrWhiteSpace($shareName) -or $selectedUsers.Count -eq 0) {
        Show-ErrorMessage 'Please select a DFS Share and at least one locked user.'
    } else {
        foreach ($username in $selectedUsers) {
            try {
                Unblock-SmbShareAccess -Name $shareName -AccountName $username -Force
                Show-ErrorMessage "User $username successfully unlocked in DFS Share: $shareName."
                Log-Message "User $username successfully unlocked in DFS Share: $shareName."
            } catch {
                Show-ErrorMessage "Failed to unlock user ${username}: $_"
            }
        }
    }
}

# Function to create CheckedListBox for locked users
function CreateCheckedListBox {
    param (
        [array]$location,
        [array]$size
    )
    $checkedListBox = New-Object System.Windows.Forms.CheckedListBox
    $checkedListBox.Location = New-Object System.Drawing.Point($location[0], $location[1])
    $checkedListBox.Size = New-Object System.Drawing.Size($size[0], $size[1])
    return $checkedListBox
}

# Main form setup
$main_form = New-Object System.Windows.Forms.Form
$main_form.Text = 'Manage DFS Permissions and Unlock Users'
$main_form.Size = New-Object System.Drawing.Size(500, 520)  # Increased height
$main_form.StartPosition = 'CenterScreen'

# Create TabControl to organize features
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Size = New-Object System.Drawing.Size(480, 400)  # Adjusted height for content
$tabControl.Location = New-Object System.Drawing.Point(10, 10)

# Tab 1: Manage Locked Users
$tabPage1 = New-Object System.Windows.Forms.TabPage
$tabPage1.Text = "Manage Locked Users"
$tabPage2 = New-Object System.Windows.Forms.TabPage
$tabPage2.Text = "User Permissions"

# Auto-populate DFS Shares
$dfsShares = Get-DFSNamespaces

# --- Tab 1: Manage Locked Users ---
$tabPage1.Controls.Add((Create-Control -type 'Label' -text 'Select the DFS Share:' -location @(10, 20) -size @(440, 20)))
$comboBox_share = Create-Control -type 'ComboBox' -location @(10, 50) -size @(440, 20) -items $dfsShares
$tabPage1.Controls.Add($comboBox_share)

# Locked users CheckedListBox
$tabPage1.Controls.Add((Create-Control -type 'Label' -text 'Locked Users:' -location @(10, 90) -size @(440, 20)))
$checkedListBox_lockedUsers = CreateCheckedListBox @(10, 120) @(440, 120)
$tabPage1.Controls.Add($checkedListBox_lockedUsers)

# Button to load locked users into CheckedListBox
$load_button = Create-Control -type 'Button' -text 'Load Locked Users' -location @(10, 260) -size @(440, 30) -onClick {
    $shareName = $comboBox_share.SelectedItem
    if ([string]::IsNullOrWhiteSpace($shareName)) {
        Show-ErrorMessage 'Please select a DFS Share.'
    } else {
        try {
            $lockedUsers = Get-SmbShareAccess -Name $shareName | Where-Object { $_.AccessControlType -eq 'Deny' } | Select-Object -ExpandProperty AccountName
            if ($lockedUsers.Count -gt 0) {
                $checkedListBox_lockedUsers.Items.Clear()
                $checkedListBox_lockedUsers.Items.AddRange($lockedUsers)
                Log-Message "Locked users loaded successfully for share: $shareName."
            } else {
                Show-ErrorMessage "No locked users found for the share: $shareName."
            }
        } catch {
            Show-ErrorMessage "Failed to load locked users: $_"
        }
    }
}
$tabPage1.Controls.Add($load_button)

# Unlock Users Button
$unblock_button = Create-Control -type 'Button' -text 'Unlock Selected Users' -location @(10, 300) -size @(440, 30) -onClick {
    $shareName = $comboBox_share.SelectedItem
    $selectedUsers = $checkedListBox_lockedUsers.CheckedItems
    Unlock-Users -shareName $shareName -selectedUsers $selectedUsers
}
$tabPage1.Controls.Add($unblock_button)

# --- Tab 2: User Permissions ---
$tabPage2.Controls.Add((Create-Control -type 'Label' -text 'Enter User to Manage Permissions:' -location @(10, 20) -size @(440, 20)))
$textbox_user = New-Object System.Windows.Forms.TextBox
$textbox_user.Location = New-Object System.Drawing.Point(10, 50)
$textbox_user.Size = New-Object System.Drawing.Size(440, 20)
$tabPage2.Controls.Add($textbox_user)

# ListBox to show all DFS permissions of the specified user
$tabPage2.Controls.Add((Create-Control -type 'Label' -text 'User Permissions on DFS Shares:' -location @(10, 80) -size @(440, 20)))
$listbox_permissions = New-Object System.Windows.Forms.ListBox
$listbox_permissions.Location = New-Object System.Drawing.Point(10, 110)
$listbox_permissions.Size = New-Object System.Drawing.Size(440, 120)
$tabPage2.Controls.Add($listbox_permissions)

# Button to load all permissions for the specified user
$load_permissions_button = Create-Control -type 'Button' -text 'Load User Permissions' -location @(10, 250) -size @(440, 30) -onClick {
    $username = $textbox_user.Text
    if ([string]::IsNullOrWhiteSpace($username)) {
        Show-ErrorMessage 'Please enter a username to load permissions.'
    } else {
        $permissions = Get-UserPermissions -username $username
        if ($permissions.Count -gt 0) {
            $listbox_permissions.Items.Clear()
            $permissions | ForEach-Object {
                $listbox_permissions.Items.Add("Share: $($_.Name) | Access: $($_.AccessControlType)")
            }
            Log-Message "Permissions loaded successfully for user: $username."
        } else {
            Show-ErrorMessage "No permissions found for user: $username."
        }
    }
}
$tabPage2.Controls.Add($load_permissions_button)

# Add tabs to TabControl
$tabControl.Controls.Add($tabPage1)
$tabControl.Controls.Add($tabPage2)

# Add TabControl to the main form
$main_form.Controls.Add($tabControl)

# Close Button
$close_button = Create-Control -type 'Button' -text 'Close' -location @(10, 430) -size @(460, 30) -onClick {
    $main_form.Close()
}
$main_form.Controls.Add($close_button)

[void]$main_form.ShowDialog()

# End of script
