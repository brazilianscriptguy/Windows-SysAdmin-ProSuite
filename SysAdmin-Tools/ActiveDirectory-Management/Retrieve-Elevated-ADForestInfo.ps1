<#
.SYNOPSIS
    PowerShell Script for Gathering Elevated Account Information in AD Forest.

.DESCRIPTION
    This script gathers information on elevated accounts and privileged groups across 
    the AD forest to assist in monitoring privileged users and maintaining security 
    compliance.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: October 22, 2024
#>

# Hide the PowerShell console window for a cleaner UI
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

# Import necessary modules
if (-not (Get-Module -Name ActiveDirectory)) {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to import ActiveDirectory module. Ensure it's installed and you have the necessary permissions.", "Module Import Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        exit
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Determine the script name for logging and exporting .csv files
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

# Log and CSV paths
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName
$csvPath = [Environment]::GetFolderPath('MyDocuments') + "\${scriptName}-$timestamp.csv"

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    $null = New-Item -Path $logDir -ItemType Directory -ErrorAction SilentlyContinue
    if (-not (Test-Path $logDir)) {
        [System.Windows.Forms.MessageBox]::Show("Failed to create log directory at $logDir. Logging will not be possible.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }
}

# Global Variables Initialization
$global:logBox = New-Object System.Windows.Forms.ListBox
$global:results = @{}  # Initialize a hashtable to store results
$global:selectedDomain = ""

# Centralized logging function
function Write-Log {
    param (
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $false)][ValidateSet("INFO", "ERROR", "WARNING")][string]$Type = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Type] $Message"
    try {
        Add-Content -Path $logPath -Value "$logEntry`r`n" -ErrorAction Stop
        if ($global:logBox -ne $null) {
            $global:logBox.Invoke([Action] {
                    $global:logBox.Items.Add($logEntry)
                    $global:logBox.TopIndex = $global:logBox.Items.Count - 1
                })
        }
    } catch {
        Write-Error "Failed to write to log: $_"
    }
    Write-Output $logEntry
}

# Unified error handling
function Handle-Error {
    param (
        [Parameter(Mandatory = $true)][string]$ErrorMessage
    )
    Write-Log -Message "ERROR: $ErrorMessage" -Type "ERROR"
    [System.Windows.Forms.MessageBox]::Show($ErrorMessage, "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

# Function to create the GUI
function Create-GUI {
    # Create the form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "AD Forest Elevated Accounts Info"
    $form.Size = New-Object System.Drawing.Size(800, 600)
    $form.StartPosition = "CenterScreen"

    # Create a textbox for displaying results
    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Multiline = $true
    $textBox.ScrollBars = "Vertical"
    $textBox.Size = New-Object System.Drawing.Size(760, 300)
    $textBox.Location = New-Object System.Drawing.Point(10, 10)
    $textBox.ReadOnly = $true
    $form.Controls.Add($textBox)

    # Label to instruct domain selection
    $domainLabel = New-Object System.Windows.Forms.Label
    $domainLabel.Text = "Choose the DOMAIN name from the list:"
    $domainLabel.Location = New-Object System.Drawing.Point(10, 320)
    $domainLabel.Size = New-Object System.Drawing.Size(300, 20)
    $form.Controls.Add($domainLabel)

    # Combo box to select domain
    $comboDomain = New-Object System.Windows.Forms.ComboBox
    $comboDomain.Location = New-Object System.Drawing.Point(10, 345)
    $comboDomain.Size = New-Object System.Drawing.Size(300, 30)
    $comboDomain.DropDownStyle = "DropDownList"

    # Try to set the current domain, but handle it gracefully if it can't be determined
    try {
        $global:selectedDomain = (Get-ADDomain).DNSRoot
        $comboDomain.Items.Add($global:selectedDomain)
        $comboDomain.SelectedIndex = 0
    } catch {
        Write-Log -Message "Unable to determine the current domain. Please select a domain manually." -Type "WARNING"
    }

    # Populate with other domains from the forest
    try {
        $forest = Get-ADForest -ErrorAction Stop
        $domains = $forest.Domains
        foreach ($domain in $domains) {
            if ($domain -ne $global:selectedDomain) {
                $comboDomain.Items.Add($domain)
            }
        }
    } catch {
        Handle-Error "Failed to retrieve AD Forest domains: $_"
    }

    # Add event for domain change
    $comboDomain.add_SelectedIndexChanged({
            $global:selectedDomain = $comboDomain.SelectedItem
            Write-Log -Message "Domain changed to: $global:selectedDomain" -Type "INFO"
        })

    $form.Controls.Add($comboDomain)

    # Initialize logBox
    $global:logBox.Size = New-Object System.Drawing.Size(760, 100)
    $global:logBox.Location = New-Object System.Drawing.Point(10, 385)
    $form.Controls.Add($global:logBox)

    # Create a button to start the process
    $buttonStart = New-Object System.Windows.Forms.Button
    $buttonStart.Text = "Start"
    $buttonStart.Size = New-Object System.Drawing.Size(100, 30)
    $buttonStart.Location = New-Object System.Drawing.Point(10, 500)
    $form.Controls.Add($buttonStart)

    # Create a button to save the results to CSV
    $buttonSave = New-Object System.Windows.Forms.Button
    $buttonSave.Text = "Save to CSV"
    $buttonSave.Size = New-Object System.Drawing.Size(100, 30)
    $buttonSave.Location = New-Object System.Drawing.Point(120, 500)
    $buttonSave.Enabled = $false
    $form.Controls.Add($buttonSave)

    # Event handler for the Start button
    $buttonStart.Add_Click({
            if (-not $global:selectedDomain) {
                [System.Windows.Forms.MessageBox]::Show("Please select a valid domain.", "Invalid Domain", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                return
            }

            $buttonStart.Enabled = $false
            $buttonSave.Enabled = $false
            $textBox.Clear()
            $textBox.Text = "Gathering information for domain: $global:selectedDomain, please wait..."

            try {
                $global:results = Get-ADForestInfo -SelectedDomain $global:selectedDomain
                if ($global:results -eq $null) {
                    throw "No results were returned."
                }

                $displayResults = $global:results.GetEnumerator() | ForEach-Object {
                    "$($_.Key): $($_.Value -join ', ')"
                }
                $textBox.Text = $displayResults -join "`r`n"
                $buttonSave.Enabled = $true
                Write-Log -Message "Information gathering completed successfully for domain '$global:selectedDomain'." -Type "INFO"
            } catch {
                Handle-Error "An error occurred during information gathering: $_"
            } finally {
                $buttonStart.Enabled = $true
            }
        })

    # Event handler for the Save to CSV button
    $buttonSave.Add_Click({
            if ($null -eq $global:results -or $global:results.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show("No data to save. Please ensure the information gathering process has completed successfully.", "No Data", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                return
            }

            try {
                # Prepare the CSV data
                $csvData = @()

                foreach ($category in $global:results.Keys) {
                    # Create a new object with dynamic properties based on the domains
                    $row = New-Object PSObject
                    $row | Add-Member -MemberType NoteProperty -Name "Category" -Value $category

                    foreach ($domain in $global:results[$category].Keys) {
                        $domainName = $domain.Replace('.', '_')  # Replace dots in domain names with underscores
                        $row | Add-Member -MemberType NoteProperty -Name $domainName -Value ($global:results[$category][$domain] -join ', ')
                    }

                    $csvData += $row
                }

                $csvData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
                [System.Windows.Forms.MessageBox]::Show("Results saved to " + $csvPath, "Save Successful", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                Write-Log -Message "Results saved to CSV file: $csvPath" -Type "INFO"
            } catch {
                Handle-Error "Failed to save results to CSV: $_"
            }
        })

    # Show the form
    $form.ShowDialog()
}

# Function to gather AD Forest information
function Get-ADForestInfo {
    param (
        [string]$SelectedDomain
    )

    $results = @{}

    try {
        $domainInfo = Get-ADDomain -Identity $SelectedDomain -ErrorAction Stop
    } catch {
        Handle-Error "Failed to retrieve information for domain '$SelectedDomain': $_"
        return $null
    }

    $categories = @("Admins Groups", "Administrators Users Accounts into Admins Groups", "Services Accounts", "InetOrgPerson", "Builtin Admins Groups", "Service Group")

    foreach ($category in $categories) {
        $results[$category] = @{}
        $results[$category][$SelectedDomain] = @()

        switch ($category) {
            "Admins Groups" {
                $results[$category][$SelectedDomain] = Get-AdminsGroups -Server $SelectedDomain | ForEach-Object { $_.Name }
            }
            "Administrators Users Accounts into Admins Groups" {
                $results[$category][$SelectedDomain] = Get-AdminsUsersRecursive -Server $SelectedDomain | ForEach-Object { $_.SamAccountName }
            }
            "Services Accounts" {
                $results[$category][$SelectedDomain] = Get-ServiceAccountsAndGroups -Server $SelectedDomain | Where-Object { $_.Type -eq "Service Account" } | ForEach-Object { $_.Name }
            }
            "InetOrgPerson" {
                $results[$category][$SelectedDomain] = Get-InetOrgPersons -Server $SelectedDomain | ForEach-Object { $_.SamAccountName }
            }
            "Builtin Admins Groups" {
                $results[$category][$SelectedDomain] = Get-BuiltinAdminsGroups -Server $SelectedDomain | ForEach-Object { $_.Name }
            }
            "Service Group" {
                $results[$category][$SelectedDomain] = Get-ServiceAccountsAndGroups -Server $SelectedDomain | Where-Object { $_.Type -eq "Service Group" } | ForEach-Object { $_.Name }
            }
            default {
                Write-Log -Message "Unknown category: $category" -Type "WARNING"
            }
        }
    }

    return $results
}

# Function to gather all Builtin Admins groups and their members
function Get-BuiltinAdminsGroups {
    param ($Server)
    try {
        $builtinAdminsGroups = Get-ADGroup -Filter { Name -like "Administrators" -or Name -like "Admins" -or Name -like "*Admin*" } -Server $Server -Properties Member | 
            Select-Object Name, DistinguishedName, @{Name = "Member"; Expression = { ($_ | Get-ADGroupMember -Recursive -Server $Server | Where-Object { $_.objectClass -eq "user" }).SamAccountName } }
        return $builtinAdminsGroups
    } catch {
        Handle-Error "Failed to retrieve Builtin Admins Groups from '$Server': $_"
        return @()
    }
}

# Function to gather all Admins groups and their members, including nested groups
function Get-AdminsGroups {
    param ($Server)
    try {
        $adminGroups = Get-ADGroup -Filter { Name -like "*Admin*" -or Name -like "*Admins*" -or Name -like "Administrators" } -Server $Server -Properties Member |
            Select-Object Name, DistinguishedName, @{Name = "Member"; Expression = { ($_ | Get-ADGroupMember -Recursive -Server $Server | Where-Object { $_.objectClass -eq "user" }).SamAccountName } }
        return $adminGroups
    } catch {
        Handle-Error "Failed to retrieve Admins Groups from '$Server': $_"
        return @()
    }
}

# Function to gather all Admins user accounts, including those in nested groups
function Get-AdminsUsersRecursive {
    param ($Server)
    try {
        $adminsGroups = Get-ADGroup -Filter { Name -like "*Admin*" -or Name -like "*Admins*" -or Name -like "Administrators" } -Server $Server
        $adminsUsers = @()

        foreach ($group in $adminsGroups) {
            $members = Get-ADGroupMember -Identity $group.DistinguishedName -Recursive -Server $Server | Where-Object { $_.objectClass -eq "user" }
            foreach ($member in $members) {
                $adminsUsers += [PSCustomObject]@{
                    SamAccountName = $member.SamAccountName
                    DistinguishedName = $member.DistinguishedName
                }
            }
        }

        return $adminsUsers
    } catch {
        Handle-Error "Failed to retrieve Admins Users from '$Server': $_"
        return @()
    }
}

# Function to gather all InetOrgPerson objects
function Get-InetOrgPersons {
    param ($Server)
    try {
        $inetOrgPersons = Get-ADObject -Filter { ObjectClass -eq "inetOrgPerson" } -Server $Server -Properties SamAccountName, DistinguishedName |
            Select-Object SamAccountName, DistinguishedName
        return $inetOrgPersons
    } catch {
        Handle-Error "Failed to retrieve InetOrgPerson objects from '$Server': $_"
        return @()
    }
}

# Function to gather AD accounts and groups with 'services' or 'service' in the name or description
function Get-ServiceAccountsAndGroups {
    param ($Server)
    $serviceAccountsAndGroups = @()

    try {
        # ADUser accounts with 'services' or 'service' in the name or description
        $accounts = Get-ADUser -Filter {
            (SamAccountName -like "*service*") -or 
            (Description -like "*service*") -or 
            (SamAccountName -like "*services*") -or 
            (Description -like "*services*")
        } -Server $Server -Properties SamAccountName, DistinguishedName

        $serviceAccountsAndGroups += $accounts | ForEach-Object {
            [PSCustomObject]@{
                Type = "Service Account"
                Name = $_.SamAccountName
                DistinguishedName = $_.DistinguishedName
            }
        }

        # ADGroup accounts with 'services' or 'service' in the name or description
        $groups = Get-ADGroup -Filter {
            (SamAccountName -like "*service*") -or 
            (Description -like "*service*") -or 
            (SamAccountName -like "*services*") -or 
            (Description -like "*services*")
        } -Server $Server -Properties SamAccountName, DistinguishedName

        $serviceAccountsAndGroups += $groups | ForEach-Object {
            [PSCustomObject]@{
                Type = "Service Group"
                Name = $_.SamAccountName
                DistinguishedName = $_.DistinguishedName
            }
        }
    } catch {
        Handle-Error "Failed to retrieve Service Accounts and Groups from '$Server': $_"
    }

    return $serviceAccountsAndGroups
}

# Run the GUI
Create-GUI

# End of script
