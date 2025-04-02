<#
.SYNOPSIS
    Fix Delegation Wizard GUI - Deep DNS and AD Cleanup

.DESCRIPTION
    This tool searches for and removes residual DNS and Active Directory objects related to decommissioned domain controllers
    across all AD Naming Contexts (Domain, Configuration, Schema, DomainDnsZones, ForestDnsZones). It includes full log and CSV export,
    and validates the result using DCDIAG.

.AUTHOR
    Luiz Hamilton - @brazilianscriptguy

.VERSION
    April 2, 2025
#>

# Hide PowerShell console
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() {
        ShowWindow(GetConsoleWindow(), 0); // SW_HIDE
    }
}
"@
[Window]::Hide()

# Load GUI and modules
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
Import-Module DnsServer -ErrorAction SilentlyContinue

# Set environment variables
$defaultDomain = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).Name
$dnsServer = ($env:COMPUTERNAME + "." + $defaultDomain).ToLower()

# Reusable log function
function Log {
    param ([string]$message)
    $global:LogEntries += $message
    $global:LogObjects += [PSCustomObject]@{ Timestamp = (Get-Date); Message = $message }
    $txtOutput.AppendText("$message`r`n")
}

# Cleanup Function
function Remove-DNS-AD-Residuals {
    param ([string]$hostname)

    $timestamp = (Get-Date -Format "yyyy-MM-dd-HHmm")
    $fqdn = "$hostname.$defaultDomain"
    $logFile = "C:\Logs-TEMP\FixDelegation-$hostname-$timestamp.log"
    $csvFile = "$([Environment]::GetFolderPath('MyDocuments'))\FixDelegation-$hostname-$timestamp.csv"

    $global:LogEntries = @()
    $global:LogObjects = @()

    Log "Starting cleanup for: '$hostname'..."
    Log ""

    # --- DNS ZONE CLEANUP ---
    $zones = Get-DnsServerZone -ComputerName $dnsServer -ErrorAction SilentlyContinue
    foreach ($zone in $zones) {
        $records = Get-DnsServerResourceRecord -ZoneName $zone.ZoneName -ComputerName $dnsServer -ErrorAction SilentlyContinue |
            Where-Object {
                $_.HostName -like "*$hostname*" -or
                $_.RecordData.ToString() -like "*$hostname*" -or
                $_.RecordData.ToString() -like "*$fqdn*"
            }

        foreach ($record in $records) {
            try {
                Remove-DnsServerResourceRecord -ZoneName $zone.ZoneName -ComputerName $dnsServer -InputObject $record -Force
                Log "[REMOVED] DNS Record: $($record.HostName) - Type: $($record.RecordType) - Zone: $($zone.ZoneName)"
            } catch {
                Log "[ERROR] Failed to remove DNS record '$($record.HostName)' in zone '$($zone.ZoneName)': $_"
            }
        }

        foreach ($type in @("A", "CNAME", "PTR", "NS")) {
            try {
                Remove-DnsServerResourceRecord -ZoneName $zone.ZoneName -ComputerName $dnsServer -Name $hostname -RRType $type -Force -ErrorAction Stop
                Log "[REMOVED] Direct record ${type}: $hostname in zone $($zone.ZoneName)"
            } catch {
                Log "[INFO] No direct $type record found or already removed in zone $($zone.ZoneName)"
            }
        }
    }

    try {
        Remove-DnsServerZone -Name $fqdn -ComputerName $dnsServer -Force -ErrorAction Stop
        Log "[REMOVED] Delegated zone: $fqdn"
    } catch {
        Log "[INFO] No delegated zone named $fqdn found."
    }

    # --- AD CLEANUP IN ALL NCs ---
    $domainComponents = ($defaultDomain -split "\.").ForEach({ "DC=$_"})
    $baseList = @(
        "$($domainComponents -join ',')",
        "CN=Configuration,$($domainComponents -join ',')",
        "CN=Schema,CN=Configuration,$($domainComponents -join ',')",
        "DC=DomainDnsZones,$($domainComponents -join ',')",
        "DC=ForestDnsZones,$($domainComponents -join ',')"
    )

    foreach ($base in $baseList) {
        try {
            $objects = Get-ADObject -Filter { Name -like "*" } -SearchBase $base -SearchScope Subtree -Properties DistinguishedName |
                Where-Object { $_.DistinguishedName -like "*$hostname*" -or $_.Name -like "*$hostname*" }

            foreach ($obj in $objects) {
                try {
                    Remove-ADObject -Identity $obj.DistinguishedName -Recursive -Confirm:$false
                    Log "[REMOVED] AD Object in ${base}: $($obj.DistinguishedName)"
                } catch {
                    Log "[ERROR] Failed to remove AD object: $($obj.DistinguishedName) - $_"
                }
            }
        } catch {
            Log "[ERROR] Failed during AD cleanup at base ${base}: $_"
        }
    }

    # Export logs
    $global:LogEntries | Out-File -FilePath $logFile -Encoding UTF8
    $global:LogObjects | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8

    Log ""
    Log "[INFO] Log saved to: $logFile"
    Log "[INFO] CSV report saved to: $csvFile"
    Log ""
    Log "Cleanup completed."
}

# Run DCDIAG
function Run-DCDNSDiag {
    Log "Running DCDIAG for DNS validation..."
    $output = & dcdiag /test:DNS /dnsall /s:$dnsServer
    Log ($output -join "`r`n")
    Log "DCDIAG finished."
}

# GUI
$form = New-Object System.Windows.Forms.Form
$form.Text = "Fix Delegation Wizard - Deep DNS & AD Cleanup"
$form.Size = New-Object System.Drawing.Size(720,640)
$form.StartPosition = "CenterScreen"
$form.TopMost = $true

$lblInput = New-Object System.Windows.Forms.Label
$lblInput.Text = "Enter hostname with delegation issue (e.g., DC03-LOCAL):"
$lblInput.Location = New-Object System.Drawing.Point(20,20)
$lblInput.Size = New-Object System.Drawing.Size(400,20)
$form.Controls.Add($lblInput)

$txtHostname = New-Object System.Windows.Forms.TextBox
$txtHostname.Location = New-Object System.Drawing.Point(420, 18)
$txtHostname.Size = New-Object System.Drawing.Size(250,20)
$form.Controls.Add($txtHostname)

$btnFix = New-Object System.Windows.Forms.Button
$btnFix.Text = "Fix Delegation"
$btnFix.Size = New-Object System.Drawing.Size(160,30)
$btnFix.Location = New-Object System.Drawing.Point(20,50)
$form.Controls.Add($btnFix)

$btnDiag = New-Object System.Windows.Forms.Button
$btnDiag.Text = "Run DCDIAG"
$btnDiag.Size = New-Object System.Drawing.Size(160,30)
$btnDiag.Location = New-Object System.Drawing.Point(200,50)
$form.Controls.Add($btnDiag)

$txtOutput = New-Object System.Windows.Forms.TextBox
$txtOutput.Multiline = $true
$txtOutput.ScrollBars = "Vertical"
$txtOutput.Font = 'Consolas,10'
$txtOutput.Size = New-Object System.Drawing.Size(660,460)
$txtOutput.Location = New-Object System.Drawing.Point(20,90)
$form.Controls.Add($txtOutput)

$btnFix.Add_Click({
    $hostname = $txtHostname.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($hostname)) {
        [System.Windows.Forms.MessageBox]::Show("Please enter the hostname to proceed.", "Warning", 'OK', 'Warning')
        return
    }
    $txtOutput.Clear()
    Remove-DNS-AD-Residuals -hostname $hostname
})

$btnDiag.Add_Click({
    Run-DCDNSDiag
})

[void]$form.ShowDialog()

# End of script
