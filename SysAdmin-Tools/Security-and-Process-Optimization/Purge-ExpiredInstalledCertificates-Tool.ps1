<#
.SYNOPSIS
    PowerShell GUI Tool for Selective Removal of Expired Certificate Authorities (CAs).

.DESCRIPTION
    This script displays expired certificates from both LocalMachine and CurrentUser stores, 
    allowing the user to selectively remove them via a graphical interface. 
    Logging is provided for auditing and troubleshooting purposes.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: Updated June 12, 2025
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

# Load necessary assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# --- Logging Configuration ---
$scriptName = if ($MyInvocation.MyCommand.Name) {
    [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
} else {
    "SelectiveCertCleanup"
}
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}_$(Get-Date -Format 'yyyyMMddHHmmss').log"
$logPath = Join-Path $logDir $logFileName

if (-not (Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    } catch {
        Write-Error "Failed to create log directory at $logDir. Logging will not be possible."
        return
    }
}

function Write-Log {
    param (
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter()][ValidateSet('INFO', 'ERROR')] [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

function Show-Message {
    param (
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][ValidateSet('Error', 'Information')] [string]$Type
    )
    $icon = if ($Type -eq 'Error') { [System.Windows.Forms.MessageBoxIcon]::Error } else { [System.Windows.Forms.MessageBoxIcon]::Information }
    [System.Windows.Forms.MessageBox]::Show($Message, $Type, [System.Windows.Forms.MessageBoxButtons]::OK, $icon)
}

function Get-ExpiredCertificates {
    param (
        [Parameter(Mandatory = $true)][string]$StoreLocation
    )
    try {
        $certs = Get-ChildItem -Path "Cert:\$StoreLocation" -Recurse |
                 Where-Object {
                    $_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2] -and
                    $_.NotAfter -lt (Get-Date)
                 }
        Write-Log -Message "Found $($certs.Count) expired certificates in '$StoreLocation' store." -Level "INFO"
        return $certs
    } catch {
        Write-Log -Message "Failed to retrieve expired certificates from '$StoreLocation': $_" -Level "ERROR"
        return @()
    }
}

function Display-ExpiredCertificates {
    param (
        [Parameter(Mandatory = $true)][System.Windows.Forms.ListBox]$ListBox
    )

    $certsMachine = Get-ExpiredCertificates -StoreLocation 'LocalMachine'
    $certsUser = Get-ExpiredCertificates -StoreLocation 'CurrentUser'
    $allCerts = $certsMachine + $certsUser

    $ListBox.Items.Clear()
    foreach ($cert in $allCerts) {
        $ListBox.Items.Add("$($cert.Thumbprint) | Expires: $($cert.NotAfter.ToString('yyyy-MM-dd'))")
    }

    Write-Log -Message "Displayed expired certificates in the ListBox." -Level "INFO"
    Show-Message -Message "Expired certificates have been displayed." -Type "Information"
}

function Remove-CertificatesByThumbprint {
    param (
        [Parameter(Mandatory = $true)][string[]]$Thumbprints
    )

    Write-Log -Message "Starting certificate removal process." -Level "INFO"

    foreach ($thumbprint in $Thumbprints) {
        try {
            $certs = Get-ChildItem -Path Cert:\ -Recurse | Where-Object { $_.Thumbprint -eq $thumbprint.Trim() }
            foreach ($cert in $certs) {
                if (Test-Path $cert.PSPath) {
                    Remove-Item -Path $cert.PSPath -Force -ErrorAction Stop
                    Write-Log -Message "Removed certificate with thumbprint: $thumbprint" -Level "INFO"
                } else {
                    Write-Log -Message "Certificate PSPath not found for thumbprint: $thumbprint" -Level "INFO"
                }
            }
        } catch {
            Write-Log -Message "Failed to remove certificate with thumbprint: $thumbprint - $_" -Level "ERROR"
        }
    }

    Write-Log -Message "Certificate removal completed." -Level "INFO"
    Show-Message -Message "Selected certificates have been removed." -Type "Information"
}

# GUI Setup
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Selective Certificate Cleanup Tool'
$form.Size = New-Object System.Drawing.Size(500, 400)
$form.StartPosition = 'CenterScreen'

$listBoxCertificates = New-Object System.Windows.Forms.ListBox
$listBoxCertificates.Location = New-Object System.Drawing.Point(10, 50)
$listBoxCertificates.Size = New-Object System.Drawing.Size(460, 200)
$listBoxCertificates.HorizontalScrollbar = $true
$form.Controls.Add($listBoxCertificates)

$form.Controls.Add((New-Object System.Windows.Forms.Button -Property @{
    Text = "Display Expired Certificates"
    Location = New-Object System.Drawing.Point(10, 260)
    Size = New-Object System.Drawing.Size(200, 30)
    Add_Click = { Display-ExpiredCertificates -ListBox $listBoxCertificates }
}))

$form.Controls.Add((New-Object System.Windows.Forms.Button -Property @{
    Text = "Remove Certificates"
    Location = New-Object System.Drawing.Point(220, 260)
    Size = New-Object System.Drawing.Size(200, 30)
    Add_Click = {
        $thumbprints = @($listBoxCertificates.Items | ForEach-Object { $_.Split('|')[0].Trim() })
        if ($thumbprints.Count -eq 0) {
            Show-Message -Message "No certificates selected for removal." -Type "Error"
        } else {
            Remove-CertificatesByThumbprint -Thumbprints $thumbprints
            $listBoxCertificates.Items.Clear()
        }
    }
}))

$form.Controls.Add((New-Object System.Windows.Forms.Button -Property @{
    Text = "Close"
    Location = New-Object System.Drawing.Point(10, 310)
    Size = New-Object System.Drawing.Size(460, 30)
    Add_Click = { $form.Close() }
}))

[void]$form.ShowDialog()

# End of Script
