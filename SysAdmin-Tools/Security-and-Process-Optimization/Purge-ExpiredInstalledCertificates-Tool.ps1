<#
.SYNOPSIS
    PowerShell GUI Tool for Selective Removal of Expired Certificates

.DESCRIPTION
    Lists expired certificates from LocalMachine and CurrentUser stores.
    Allows selective removal via GUI.
    Generates audit log and CSV report.

.AUTHOR
    Luiz Hamilton Silva – @brazilianscriptguy

.VERSION
    Last Updated: June 17, 2025
#>

# Hide PowerShell console
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

# Load Windows Forms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Logging setup
$scriptName = "SelectiveCertCleanup"
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$logDir = "C:\Logs-TEMP"
$logFile = Join-Path $logDir "$scriptName-$timestamp.log"
$csvFile = Join-Path $logDir "$scriptName-Removed-$timestamp.csv"

if (-not (Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to create log directory. Logging disabled.", "Error", 0, 'Error')
        return
    }
}

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet('INFO','ERROR')][string]$Level = 'INFO'
    )
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Write-Output $entry
    Add-Content -Path $logFile -Value $entry -ErrorAction SilentlyContinue
}

function Show-Message {
    param (
        [string]$Message,
        [ValidateSet('Information','Error')][string]$Type
    )
    $icon = if ($Type -eq 'Error') { 'Error' } else { 'Information' }
    [System.Windows.Forms.MessageBox]::Show($Message, $Type, 'OK', $icon)
}

function Get-ExpiredCertificates {
    param ([string]$StoreLocation)

    try {
        $certs = Get-ChildItem -Path "Cert:\$StoreLocation" -Recurse |
            Where-Object {
                $_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2] -and
                $_.NotAfter -ne $null -and
                $_.NotAfter -lt (Get-Date)
            }
        Write-Log -Message "Found $($certs.Count) expired certificates in '$StoreLocation'" -Level 'INFO'
        return $certs
    } catch {
        Write-Log -Message "Failed to retrieve certificates from '$StoreLocation': $_" -Level 'ERROR'
        return @()
    }
}

function Display-ExpiredCertificates {
    param ([System.Windows.Forms.ListBox]$ListBox)

    $ListBox.Items.Clear()
    $expired = @()
    $expired += Get-ExpiredCertificates -StoreLocation 'LocalMachine'
    $expired += Get-ExpiredCertificates -StoreLocation 'CurrentUser'

    foreach ($cert in $expired) {
        $thumb = $cert.Thumbprint
        $subject = if ($cert.Subject) { $cert.Subject } else { "No Subject" }
        $exp = if ($cert.NotAfter) { $cert.NotAfter.ToString("yyyy-MM-dd") } else { "N/A" }
        $display = "$thumb | $subject | Exp: $exp"
        $ListBox.Items.Add($display)
    }

    if ($ListBox.Items.Count -eq 0) {
        Show-Message -Message "No expired certificates found." -Type "Information"
    } else {
        Show-Message -Message "Expired certificates loaded." -Type "Information"
    }

    Write-Log -Message "Displayed $($ListBox.Items.Count) expired certificates in GUI."
}

function Remove-CertificatesByThumbprint {
    param ([string[]]$Thumbprints)

    $removed = @()

    foreach ($thumbprint in $Thumbprints) {
        try {
            $matches = Get-ChildItem -Path Cert:\ -Recurse |
                Where-Object { $_.Thumbprint -eq $thumbprint.Trim() }

            foreach ($cert in $matches) {
                if (Test-Path $cert.PSPath) {
                    Remove-Item -Path $cert.PSPath -Force -ErrorAction Stop
                    Write-Log -Message "Removed certificate: $($cert.Subject) ($($cert.Thumbprint))"
                    $removed += $cert
                } else {
                    Write-Log -Message "PSPath not found for thumbprint: $thumbprint"
                }
            }
        } catch {
            Write-Log -Message "Failed to remove certificate ${thumbprint}: $_" -Level 'ERROR'
        }
    }

    # Export CSV
    if ($removed.Count -gt 0) {
        try {
            $removed | Select-Object Subject, Issuer, NotAfter, Thumbprint, PSPath |
                Export-Csv -Path $csvFile -Encoding UTF8 -NoTypeInformation
            Write-Log -Message "CSV report created: $csvFile"
            Show-Message -Message "Certificates removed. Report saved to:`n$csvFile" -Type "Information"
        } catch {
            Write-Log -Message "Failed to generate CSV: $_" -Level 'ERROR'
        }
    } else {
        Show-Message -Message "No certificates were removed." -Type "Information"
    }

    return $removed.Count
}

# --- GUI Layout ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "Expired Certificate Cleanup Tool"
$form.Size = '550,420'
$form.StartPosition = 'CenterScreen'

$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Location = '10,50'
$listBox.Size = '510,230'
$listBox.HorizontalScrollbar = $true
$form.Controls.Add($listBox)

# Load Button
$btnLoad = New-Object System.Windows.Forms.Button
$btnLoad.Text = "Load Expired Certificates"
$btnLoad.Location = '10,290'
$btnLoad.Size = '250,30'
$btnLoad.Add_Click({ Display-ExpiredCertificates -ListBox $listBox })
$form.Controls.Add($btnLoad)

# Remove Button
$btnRemove = New-Object System.Windows.Forms.Button
$btnRemove.Text = "Remove All Listed"
$btnRemove.Location = '270,290'
$btnRemove.Size = '250,30'
$btnRemove.Add_Click({
    if ($listBox.Items.Count -eq 0) {
        Show-Message -Message "No certificates listed to remove." -Type "Error"
        return
    }

    $thumbs = @($listBox.Items | ForEach-Object { $_.Split('|')[0].Trim() })
    Remove-CertificatesByThumbprint -Thumbprints $thumbs
    $listBox.Items.Clear()
})
$form.Controls.Add($btnRemove)

# Close Button
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Close"
$btnClose.Location = '10,330'
$btnClose.Size = '510,30'
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)

# Run GUI
[void]$form.ShowDialog()

# End of script
