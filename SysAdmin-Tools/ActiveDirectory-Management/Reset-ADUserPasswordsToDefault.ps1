<#
.SYNOPSIS
    PowerShell Script for Resetting AD User Passwords to a Default Value.

.DESCRIPTION
    This script resets the passwords for all Active Directory (AD) users within a selected Organizational Unit (OU) in a selected domain to a default value,
    providing an efficient way to manage password policies and quickly reset multiple user accounts.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: October 25, 2024
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

# Import necessary assemblies and modules
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
} catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to load required assemblies. $_", "Initialization Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to import ActiveDirectory module. Please ensure it is installed.", "Module Import Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit
}

# Determine script name and set up logging paths
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -ErrorAction Stop | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to create log directory at $logDir. Logging will not be possible.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
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

# Function to display error messages
function Show-ErrorMessage {
    param ([string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    Log-Message $Message -MessageType "ERROR"
}

# Function to display information messages
function Show-InfoMessage {
    param ([string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, 'Information', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Log-Message $Message -MessageType "INFO"
}

# Function to retrieve all domain names in the current forest
function Get-AllDomains {
    try {
        $forest = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
        return $forest.Domains | ForEach-Object { $_.Name }
    } catch {
        Log-Message "Failed to retrieve domains: $_" -MessageType "ERROR"
        Show-ErrorMessage "Failed to retrieve domains. Please check the log for details."
        return @()
    }
}

# Function to load OUs from the selected domain
function Load-OUs {
    param ([string]$DomainName)
    try {
        $script:allOUs = Get-ADOrganizationalUnit -Server $DomainName -Filter * | Select-Object -ExpandProperty DistinguishedName
        $cmbOUs.Items.Clear()
        $script:allOUs | ForEach-Object { $cmbOUs.Items.Add($_) }
        if ($cmbOUs.Items.Count -gt 0) {
            $cmbOUs.SelectedIndex = 0
        } else {
            $cmbOUs.Text = 'No OUs found'
            Show-InfoMessage "No Organizational Units found in the domain."
        }
    } catch {
        Log-Message "Failed to load OUs: $_" -MessageType "ERROR"
        Show-ErrorMessage "Failed to load Organizational Units. Check the log for details."
    }
}

# Function to reset user passwords in a specific OU within a domain
function Reset-UserPasswords {
    param (
        [Parameter(Mandatory = $true)][string]$DomainName,
        [Parameter(Mandatory = $true)][string]$OU,
        [Parameter(Mandatory = $true)][System.Security.SecureString]$DefaultPassword
    )

    Log-Message "Starting password reset process in OU '$OU' of domain '$DomainName'."

    try {
        $users = Get-ADUser -Filter * -SearchBase $OU -Server $DomainName -Properties SamAccountName

        if ($users.Count -eq 0) {
            Show-InfoMessage "No users found in the selected OU."
            Log-Message "No users found in OU '$OU' of domain '$DomainName'." -MessageType "WARN"
            return
        }

        $progressForm = New-Object System.Windows.Forms.Form
        $progressForm.Text = "Resetting Passwords"
        $progressForm.Size = New-Object System.Drawing.Size(400, 100)
        $progressForm.StartPosition = 'CenterScreen'

        $progressBar = New-Object System.Windows.Forms.ProgressBar
        $progressBar.Location = New-Object System.Drawing.Point(10, 20)
        $progressBar.Size = New-Object System.Drawing.Size(360, 20)
        $progressBar.Minimum = 0
        $progressBar.Maximum = $users.Count
        $progressBar.Step = 1
        $progressForm.Controls.Add($progressBar)

        $progressForm.Show()

        foreach ($user in $users) {
            try {
                Set-ADAccountPassword -Identity $user -Reset -NewPassword $DefaultPassword -Server $DomainName -ErrorAction Stop
                Set-ADUser -Identity $user -ChangePasswordAtLogon $true -Server $DomainName -ErrorAction Stop
                Log-Message "Password reset for $($user.SamAccountName) with 'change at login' enforced."
            } catch {
                Log-Message "Failed to reset password for $($user.SamAccountName): $_" -MessageType "ERROR"
            }
            $progressBar.PerformStep()
            [System.Windows.Forms.Application]::DoEvents()
        }
        $progressForm.Close()
        Show-InfoMessage "Password reset process completed successfully. All users are required to change their password at next login."
    } catch {
        Log-Message "Error encountered during password reset process: $_" -MessageType "ERROR"
        Show-ErrorMessage "Error encountered during password reset process. Check the log for details."
    }
}

# Initialize the form
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Reset User Passwords in Active Directory'
$form.Size = New-Object System.Drawing.Size(500, 400)
$form.StartPosition = 'CenterScreen'

# Label for Domain selection
$labelDomain = New-Object System.Windows.Forms.Label
$labelDomain.Text = 'Select a Domain:'
$labelDomain.Location = New-Object System.Drawing.Point(10, 20)
$labelDomain.AutoSize = $true
$form.Controls.Add($labelDomain)

# ComboBox for displaying domains
$cmbDomains = New-Object System.Windows.Forms.ComboBox
$cmbDomains.Location = New-Object System.Drawing.Point(10, 45)
$cmbDomains.Size = New-Object System.Drawing.Size(460, 25)
$cmbDomains.DropDownStyle = 'DropDownList'
$form.Controls.Add($cmbDomains)

# Button to load domains
$btnLoadDomains = New-Object System.Windows.Forms.Button
$btnLoadDomains.Text = 'Refresh Domains List'
$btnLoadDomains.Location = New-Object System.Drawing.Point(10, 80)
$btnLoadDomains.Size = New-Object System.Drawing.Size(150, 30)
$btnLoadDomains.Add_Click({
        Load-Domains
    })
$form.Controls.Add($btnLoadDomains)

# Label for OU search
$labelOUSearch = New-Object System.Windows.Forms.Label
$labelOUSearch.Text = 'Search for an OU:'
$labelOUSearch.Location = New-Object System.Drawing.Point(10, 130)
$labelOUSearch.AutoSize = $true
$form.Controls.Add($labelOUSearch)

# TextBox for OU search
$txtOUSearch = New-Object System.Windows.Forms.TextBox
$txtOUSearch.Location = New-Object System.Drawing.Point(10, 155)
$txtOUSearch.Size = New-Object System.Drawing.Size(460, 20)
$form.Controls.Add($txtOUSearch)

# ComboBox for displaying OUs
$cmbOUs = New-Object System.Windows.Forms.ComboBox
$cmbOUs.Location = New-Object System.Drawing.Point(10, 185)
$cmbOUs.Size = New-Object System.Drawing.Size(460, 25)
$cmbOUs.DropDownStyle = 'DropDownList'
$form.Controls.Add($cmbOUs)

# Button to load OUs
$btnLoadOUs = New-Object System.Windows.Forms.Button
$btnLoadOUs.Text = 'Refresh OUs List'
$btnLoadOUs.Location = New-Object System.Drawing.Point(10, 220)
$btnLoadOUs.Size = New-Object System.Drawing.Size(150, 30)
$btnLoadOUs.Add_Click({
        $domainName = $cmbDomains.SelectedItem
        if ($null -eq $domainName) {
            Show-ErrorMessage "Please select a domain first."
            return
        }
        Load-OUs -DomainName $domainName
    })
$form.Controls.Add($btnLoadOUs)

# Search functionality for OUs
$txtOUSearch.Add_TextChanged({
        $searchText = $txtOUSearch.Text
        $filteredOUs = $script:allOUs | Where-Object { $_ -like "*$searchText*" }
        $cmbOUs.Items.Clear()
        $filteredOUs | ForEach-Object { $cmbOUs.Items.Add($_) }
        if ($cmbOUs.Items.Count -gt 0) {
            $cmbOUs.SelectedIndex = 0
        } else {
            $cmbOUs.Text = 'No matching OU found'
        }
    })

# Label for Default Password
$labelPassword = New-Object System.Windows.Forms.Label
$labelPassword.Text = 'Enter the default password:'
$labelPassword.Location = New-Object System.Drawing.Point(10, 270)
$labelPassword.AutoSize = $true
$form.Controls.Add($labelPassword)

# TextBox for Default Password input
$textBoxPassword = New-Object System.Windows.Forms.TextBox
$textBoxPassword.Location = New-Object System.Drawing.Point(10, 295)
$textBoxPassword.Size = New-Object System.Drawing.Size(460, 20)
$textBoxPassword.UseSystemPasswordChar = $true
$form.Controls.Add($textBoxPassword)

# Button to execute password reset
$buttonExecute = New-Object System.Windows.Forms.Button
$buttonExecute.Text = 'Reset Passwords'
$buttonExecute.Location = New-Object System.Drawing.Point(10, 330)
$buttonExecute.Size = New-Object System.Drawing.Size(150, 30)
$buttonExecute.Add_Click({
        Log-Message "Reset Passwords button clicked, starting password reset process."
        $domainName = $cmbDomains.SelectedItem
        $ou = $cmbOUs.SelectedItem
        $defaultPassword = $textBoxPassword.Text

        if (![string]::IsNullOrWhiteSpace($domainName) -and ![string]::IsNullOrWhiteSpace($ou) -and ![string]::IsNullOrWhiteSpace($defaultPassword)) {
            # Convert the plain text password to a secure string
            $securePassword = ConvertTo-SecureString -String $defaultPassword -AsPlainText -Force

            # Confirm action
            $confirmResult = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to reset passwords for all users in the selected OU?", "Confirm Password Reset", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($confirmResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                Reset-UserPasswords -DomainName $domainName -OU $ou -DefaultPassword $securePassword
            } else {
                Log-Message "Password reset operation cancelled by user."
            }
        } else {
            Show-ErrorMessage "Please select a valid domain, OU, and provide a default password."
        }
    })
$form.Controls.Add($buttonExecute)

# Function to load domains into the ComboBox
function Load-Domains {
    try {
        $script:allDomains = Get-AllDomains
        $cmbDomains.Items.Clear()
        $script:allDomains | ForEach-Object { $cmbDomains.Items.Add($_) }
        if ($cmbDomains.Items.Count -gt 0) {
            $cmbDomains.SelectedIndex = 0
        } else {
            $cmbDomains.Text = 'No domains found'
            Show-InfoMessage "No domains found in the forest."
        }
    } catch {
        Log-Message "Failed to load domains: $_" -MessageType "ERROR"
        Show-ErrorMessage "Failed to load domains. Check the log for details."
    }
}

# Event handler for domain selection change
$cmbDomains.Add_SelectedIndexChanged({
        $domainName = $cmbDomains.SelectedItem
        if ($null -ne $domainName) {
            Load-OUs -DomainName $domainName
        }
    })

# Load domains on form load
$form.Add_Shown({
        Load-Domains
    })

# Show the form
[void]$form.ShowDialog()

# End of script
