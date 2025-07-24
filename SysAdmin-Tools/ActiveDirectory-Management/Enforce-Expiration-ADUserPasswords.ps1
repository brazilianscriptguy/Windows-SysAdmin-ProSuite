<#
.SYNOPSIS
    PowerShell Script for Enforcing Password Expiration in AD Users.

.DESCRIPTION
    This script forces password expiration for users within a specified Organizational Unit (OU), 
    ensuring compliance with security policies by requiring regular password updates.

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

# Import necessary assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Import-Module ActiveDirectory

# Function to get the FQDN of the domain name
function Get-DomainFQDN {
    try {
        $ComputerSystem = Get-WmiObject Win32_ComputerSystem
        $Domain = $ComputerSystem.Domain
        return $Domain
    } catch {
        Write-Warning "Unable to fetch FQDN automatically."
        return "YourDomainHere"
    }
}

# Determine the script name and set up logging path
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$domainFQDN = Get-DomainFQDN
$sanitizedDomainFQDN = $domainFQDN -replace '[^a-zA-Z0-9.-]', '_'
$logFileName = "${scriptName}-${sanitizedDomainFQDN}_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

# Log a starting message
Log-Message "Starting the script to force expire passwords in the specified domain."

# Function to force expire passwords
function Force-ExpirePasswords {
    param ([string]$ouDN, [string]$domainFQDN)

    try {
        $users = Get-ADUser -Filter * -SearchBase $ouDN -Server $domainFQDN
        Log-Message "Starting to process users in OU: $ouDN in domain: $domainFQDN" "INFO"

        foreach ($user in $users) {
            try {
                Set-ADUser -Identity $user -ChangePasswordAtLogon $true
                Log-Message "Set ChangePasswordAtLogon to true for user: $($user.SamAccountName)" "INFO"
            } catch {
                $errorMsg = "Failed to set ChangePasswordAtLogon for user: $($user.SamAccountName) - Error: $($_.Exception.Message)"
                Log-Message $errorMsg "ERROR"
                [System.Windows.Forms.MessageBox]::Show("An error occurred for user $($user.SamAccountName): $($_.Exception.Message)", "User Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        }

        Log-Message "Completed processing users in OU: $ouDN in domain: $domainFQDN" "INFO"
        [System.Windows.Forms.MessageBox]::Show("All user passwords in '$ouDN' within '$domainFQDN' have been set to expire.", "Operation Completed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        $errorMsg = "An error occurred while processing OU: $ouDN in domain: $domainFQDN - Error: $($_.Exception.Message)"
        Log-Message $errorMsg "ERROR"
        [System.Windows.Forms.MessageBox]::Show("An error occurred while processing the OU '$ouDN': $($_.Exception.Message)", "OU Processing Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

# GUI setup
$form = New-Object System.Windows.Forms.Form
$form.Text = "Force Expire Passwords in Domain"
$form.Size = New-Object Drawing.Size(500, 320)
$form.StartPosition = 'CenterScreen'

# Domain FQDN label and textbox
$labelDomain = New-Object System.Windows.Forms.Label
$labelDomain.Text = "FQDN of the target domain:"
$labelDomain.Location = New-Object Drawing.Point(20, 20)
$labelDomain.AutoSize = $true
$form.Controls.Add($labelDomain)

$textBoxDomain = New-Object System.Windows.Forms.TextBox
$textBoxDomain.Location = New-Object Drawing.Point(20, 50)
$textBoxDomain.Size = New-Object Drawing.Size(450, 20)
$textBoxDomain.Text = $domainFQDN
$form.Controls.Add($textBoxDomain)

# OU Label and TextBox for Search
$labelOU = New-Object System.Windows.Forms.Label
$labelOU.Text = "Parent OU DN where passwords should expire:"
$labelOU.Location = New-Object Drawing.Point(20, 80)
$labelOU.AutoSize = $true
$form.Controls.Add($labelOU)

$txtOUSearch = New-Object System.Windows.Forms.TextBox
$txtOUSearch.Location = New-Object Drawing.Point(20, 110)
$txtOUSearch.Size = New-Object System.Drawing.Size(450, 20)
$txtOUSearch.Text = "Search OU..."
$txtOUSearch.ForeColor = [System.Drawing.Color]::Gray
$txtOUSearch.Add_Enter({
        if ($txtOUSearch.Text -eq "Search OU...") {
            $txtOUSearch.Text = ''
            $txtOUSearch.ForeColor = [System.Drawing.Color]::Black
        }
    })
$txtOUSearch.Add_Leave({
        if ($txtOUSearch.Text -eq '') {
            $txtOUSearch.Text = "Search OU..."
            $txtOUSearch.ForeColor = [System.Drawing.Color]::Gray
        }
    })
$form.Controls.Add($txtOUSearch)

# ComboBox for OU selection
$cmbOU = New-Object System.Windows.Forms.ComboBox
$cmbOU.Location = New-Object System.Drawing.Point(20, 140)
$cmbOU.Size = New-Object Drawing.Size(450, 20)
$cmbOU.DropDownStyle = 'DropDownList'
$form.Controls.Add($cmbOU)

# Retrieve and store all OUs initially
try {
    $allOUs = Get-ADOrganizationalUnit -Filter 'Name -like "Users*"' | Select-Object -ExpandProperty DistinguishedName
} catch {
    $errorMsg = "Failed to retrieve organizational units from the Active Directory: $($_.Exception.Message)"
    Log-Message $errorMsg "ERROR"
    [System.Windows.Forms.MessageBox]::Show($errorMsg, "Active Directory Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    return
}

# Function to populate the OU ComboBox
function Populate-OUComboBox {
    param ([Windows.Forms.ComboBox]$comboBox, [string]$filter = "")

    $filteredOUs = if ($filter -ne "") {
        $allOUs | Where-Object { $_ -like "*$filter*" } | ForEach-Object { $_ }  # Ensure it's not null
    } else {
        $allOUs
    }

    if (-not $filteredOUs) {
        $filteredOUs = @()
    }

    $comboBox.Items.Clear()
    $comboBox.Items.AddRange($filteredOUs)
}

# Populate the OU ComboBox initially
Populate-OUComboBox -comboBox $cmbOU

# Add search filter event
$txtOUSearch.Add_TextChanged({
        Populate-OUComboBox -comboBox $cmbOU -filter $txtOUSearch.Text
    })

# Create OK button
$okButton = New-Object System.Windows.Forms.Button
$okButton.Text = "OK"
$okButton.Location = New-Object Drawing.Point(20, 180)
$okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
$form.Controls.Add($okButton)
$form.AcceptButton = $okButton

# Create Cancel button
$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = "Cancel"
$cancelButton.Location = New-Object Drawing.Point(120, 180)
$cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.Controls.Add($cancelButton)

# Show the form and wait for user input
$result = $form.ShowDialog()

if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    $domainFQDN = $textBoxDomain.Text
    $ouDN = $cmbOU.Text
    if (![string]::IsNullOrWhiteSpace($domainFQDN) -and ![string]::IsNullOrWhiteSpace($ouDN)) {
        try {
            Force-ExpirePasswords $ouDN $domainFQDN
        } catch {
            $errorMsg = "An error occurred while processing OU: $ouDN in domain: $domainFQDN - Error: $($_.Exception.Message)"
            Log-Message $errorMsg "ERROR"
            [System.Windows.Forms.MessageBox]::Show($errorMsg, "Operation Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    } else {
        $errorMsg = "Please enter a valid domain FQDN and OU DN."
        Log-Message $errorMsg "ERROR"
        [System.Windows.Forms.MessageBox]::Show($errorMsg, "Invalid Input", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    }
} else {
    [System.Windows.Forms.MessageBox]::Show("Operation canceled. No changes were made.", "Operation Canceled", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Log-Message "Operation was canceled by the user" "INFO"
}

# End of script
