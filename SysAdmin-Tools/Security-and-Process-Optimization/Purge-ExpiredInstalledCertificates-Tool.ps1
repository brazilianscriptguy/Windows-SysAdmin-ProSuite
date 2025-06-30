<#
.SYNOPSIS
    PowerShell GUI Tool for Selective Removal of Expired Certificates

.DESCRIPTION
    Lists expired certificates from LocalMachine and CurrentUser stores.
    Allows selective removal via GUI.
    Generates a persistent log and CSV report in C:\ITSM-Logs-WKS.

.AUTHOR
    Luiz Hamilton Silva – @brazilianscriptguy

.VERSION
    Last Updated: June 30, 2025
#>

# Hide console
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

# Load GUI support
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Smart logging setup
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\ITSM-Logs-WKS'
$logPath = Join-Path $logDir "$scriptName.log"
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$csvPath = Join-Path $logDir "$scriptName-Removed-$timestamp.csv"

if (-not (Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to create log directory. Logging disabled.", "Error", 0, 'Error')
        return
    }
}

# Smart Write-Log function
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "[$timestamp] [$Level] $Message" -Encoding Default
}

# Show popup message
function Show-Message {
    param (
        [string]$Message,
        [ValidateSet('Information','Error')][string]$Type
    )
    $icon = if ($Type -eq 'Error') { 'Error' } else { 'Information' }
    [System.Windows.Forms.MessageBox]::Show($Message, $Type, 'OK', $icon)
}

# Get all expired certs from full store (root level)
function Get-ExpiredCertificates {
    param ([string]$StoreLocation)

    try {
        $certs = Get-ChildItem -Path "Cert:\$StoreLocation" -Recurse |
            Where-Object {
                $_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2] -and
                $_.NotAfter -ne $null -and
                $_.NotAfter -lt (Get-Date)
            }
        Write-Log -Message "Found $($certs.Count) expired certificates in '$StoreLocation'"
        return $certs
    } catch {
        Write-Log -Message "Failed to retrieve certificates from '$StoreLocation': $_" -Level "ERROR"
        return @()
    }
}

# Populate GUI with expired certs
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

# Remove certs by thumbprint and export CSV
function Remove-CertificatesByThumbprint {
    param ([string[]]$Thumbprints)

    $removed = @()

    foreach ($thumbprint in $Thumbprints) {
        try {
            $matches = Get-ChildItem -Path Cert:\ -Recurse |
                Where-Object {
                    $_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2] -and
                    $_.Thumbprint -eq $thumbprint.Trim()
                }

            foreach ($cert in $matches) {
                if (Test-Path $cert.PSPath) {
                    Remove-Item -Path $cert.PSPath -Force -ErrorAction Stop
                    Write-Log -Message "Removed certificate: $($cert.Subject) ($($cert.Thumbprint))"
                    $removed += $cert
                } else {
                    Write-Log -Message "PSPath not found for thumbprint: $thumbprint" -Level "WARNING"
                }
            }
        } catch {
            Write-Log -Message "Failed to remove certificate ${thumbprint}: $_" -Level "ERROR"
        }
    }

    if ($removed.Count -gt 0) {
        try {
            $removed | Select-Object Subject, Issuer, NotAfter, Thumbprint, PSPath |
                Export-Csv -Path $csvPath -Encoding UTF8 -NoTypeInformation
            Write-Log -Message "CSV report created: $csvPath"
            Show-Message -Message "Certificates removed. Report saved to:`n$csvPath" -Type "Information"
        } catch {
            Write-Log -Message "Failed to generate CSV report: $_" -Level "ERROR"
        }
    } else {
        Show-Message -Message "No certificates were removed." -Type "Information"
    }

    return $removed.Count
}

# ----------------- GUI -----------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Expired Certificate Cleanup Tool"
$form.Size = '580,440'
$form.StartPosition = 'CenterScreen'

$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Location = '10,50'
$listBox.Size = '540,250'
$listBox.HorizontalScrollbar = $true
$form.Controls.Add($listBox)

$btnLoad = New-Object System.Windows.Forms.Button
$btnLoad.Text = "Load Expired Certificates"
$btnLoad.Location = '10,320'
$btnLoad.Size = '260,30'
$btnLoad.Add_Click({ Display-ExpiredCertificates -ListBox $listBox })
$form.Controls.Add($btnLoad)

$btnRemove = New-Object System.Windows.Forms.Button
$btnRemove.Text = "Remove All Listed"
$btnRemove.Location = '290,320'
$btnRemove.Size = '260,30'
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

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Close"
$btnClose.Location = '10,360'
$btnClose.Size = '540,30'
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)

[void]$form.ShowDialog()

# End of script
