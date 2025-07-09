<#
.SYNOPSIS
    GUI Script to Export AD Computer Names and Their OU Paths from All Domains in the Forest

.DESCRIPTION
    This script discovers all domains in the forest and allows the admin to select one domain or all. 
    It queries all computer accounts and extracts their distinguished names (OU path), exports to CSV, 
    and logs all activities.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.LASTUPDATED
    Last Updated: July 9, 2025
#>

# Hide Console Window
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
        ShowWindow(handle, 0);
    }
}
"@
[Window]::Hide()

# Required Modules
Import-Module ActiveDirectory
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Setup Logging
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir     = 'C:\Logs-TEMP'
$logPath    = Join-Path $logDir "$scriptName.log"

if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory | Out-Null
}

function Log-Message {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")]
        [string]$MessageType = "INFO"
    )
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$stamp] [$MessageType] $Message"
    Add-Content -Path $logPath -Value $entry -Encoding UTF8
    Write-Host $entry
}

function Get-AllDomainFQDNs {
    try {
        $domains = (Get-ADForest).Domains
        Log-Message "Discovered domains: $($domains -join ', ')" "DEBUG"
        return $domains
    } catch {
        Log-Message "Error retrieving forest domains: $_" "ERROR"
        return @()
    }
}

function Export-ComputersFromDomain {
    param (
        [string]$DomainFQDN,
        [string]$OutputPath,
        [string]$ComputerTypeFilter
    )
    try {
        Log-Message "Querying computers in domain: $DomainFQDN with filter: $ComputerTypeFilter" "INFO"
        $domainDn = (Get-ADDomain -Server $DomainFQDN).DistinguishedName
        $computers = Get-ADComputer -Filter * -SearchBase $domainDn -Server $DomainFQDN -Properties DistinguishedName, OperatingSystem

        # Apply OS filter
        $filteredComputers = switch ($ComputerTypeFilter) {
            "Workstations" { $computers | Where-Object { $_.OperatingSystem -match "Windows (XP|Vista|7|8|10|11)(\s|$)" } }
            "Servers"      { $computers | Where-Object { $_.OperatingSystem -match "Windows.*Server" } }
            "All"          { $computers }
        }

        if ($filteredComputers.Count -eq 0) {
            Log-Message "No matching computers found in $DomainFQDN with filter '$ComputerTypeFilter'" "WARNING"
            return $false
        }

        $data = $filteredComputers | Select-Object `
            @{Name = "ComputerName";     Expression = { $_.Name }},
            @{Name = "OUPath";           Expression = { $_.DistinguishedName }},
            @{Name = "OperatingSystem";  Expression = { $_.OperatingSystem }},
            @{Name = "Domain";           Expression = { $DomainFQDN }}

        $data | Export-Csv -Path $OutputPath -Append -NoTypeInformation -Encoding UTF8

        Log-Message "Exported $($data.Count) computers from $DomainFQDN to $OutputPath" "INFO"
        return $true
    } catch {
        Log-Message "Failed to export computers from ${DomainFQDN}: $_" "ERROR"
        return $false
    }
}

function Show-ComputerExportForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Export AD Computers with OU Paths'
    $form.Size = New-Object System.Drawing.Size(420, 360)
    $form.StartPosition = 'CenterScreen'

    # Domain selector
    $labelDomain = New-Object System.Windows.Forms.Label
    $labelDomain.Text = "Select Domain:"
    $labelDomain.Location = '10,30'; $labelDomain.Size = '380,20'
    $form.Controls.Add($labelDomain)

    $comboBoxDomain = New-Object System.Windows.Forms.ComboBox
    $comboBoxDomain.Location = '10,50'; $comboBoxDomain.Size = '380,20'
    $comboBoxDomain.DropDownStyle = 'DropDownList'
    $comboBoxDomain.Items.Add("ALL DOMAINS")
    $comboBoxDomain.Items.AddRange((Get-AllDomainFQDNs))
    $comboBoxDomain.SelectedIndex = 0
    $form.Controls.Add($comboBoxDomain)

    # Computer type selector
    $labelType = New-Object System.Windows.Forms.Label
    $labelType.Text = "Computer Type Filter:"
    $labelType.Location = '10,90'; $labelType.Size = '380,20'
    $form.Controls.Add($labelType)

    $comboBoxType = New-Object System.Windows.Forms.ComboBox
    $comboBoxType.Location = '10,110'; $comboBoxType.Size = '380,20'
    $comboBoxType.DropDownStyle = 'DropDownList'
    $comboBoxType.Items.AddRange(@("All", "Workstations", "Servers"))
    $comboBoxType.SelectedIndex = 0
    $form.Controls.Add($comboBoxType)

    # Progress label
    $labelProgress = New-Object System.Windows.Forms.Label
    $labelProgress.Text = "Progress:"
    $labelProgress.Location = '10,150'; $labelProgress.Size = '380,20'
    $form.Controls.Add($labelProgress)

    # Progress bar
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = '10,170'; $progressBar.Size = '380,20'
    $progressBar.Minimum = 0
    $progressBar.Step = 1
    $form.Controls.Add($progressBar)

    # Export button
    $buttonExport = New-Object System.Windows.Forms.Button
    $buttonExport.Text = 'Export Computers'
    $buttonExport.Location = '10,210'; $buttonExport.Size = '180,30'
    $buttonExport.Add_Click({
        $selectedDomain = $comboBoxDomain.SelectedItem
        $selectedType = $comboBoxType.SelectedItem
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $output = "$([Environment]::GetFolderPath('MyDocuments'))\ComputersWithOU_${timestamp}_${selectedType}.csv"

        $domainsToQuery = if ($selectedDomain -eq "ALL DOMAINS") { Get-AllDomainFQDNs } else { @($selectedDomain) }

        $progressBar.Maximum = $domainsToQuery.Count
        $progressBar.Value = 0

        $success = $false
        foreach ($domain in $domainsToQuery) {
            $labelProgress.Text = "Processing: $domain"
            $form.Refresh()

            $exported = Export-ComputersFromDomain -DomainFQDN $domain -OutputPath $output -ComputerTypeFilter $selectedType
            if ($exported) { $success = $true }

            $progressBar.PerformStep()
        }

        $labelProgress.Text = "Completed!"

        if ($success) {
            [System.Windows.Forms.MessageBox]::Show("Export completed successfully.`nSaved to: $output")
        } else {
            [System.Windows.Forms.MessageBox]::Show("No computers exported. Check log for details.")
        }
    })
    $form.Controls.Add($buttonExport)

    # Close button
    $buttonClose = New-Object System.Windows.Forms.Button
    $buttonClose.Text = 'Close'
    $buttonClose.Location = '210,210'; $buttonClose.Size = '180,30'
    $buttonClose.Add_Click({ $form.Close() })
    $form.Controls.Add($buttonClose)

    [void]$form.ShowDialog()
}

# Launch GUI
Show-ComputerExportForm

# End of script
