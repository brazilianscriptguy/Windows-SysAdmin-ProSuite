<#
.SYNOPSIS
    PowerShell Script for Managing Expired and Expiring Certificates.

.DESCRIPTION
    This script detects and removes expired certificates from the certificate repository and lists 
    certificates that are due to expire within a user-specified timeframe, maintaining a secure and 
    up-to-date certificate infrastructure to minimize security vulnerabilities.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: December 06, 2024
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

# Load Windows Forms and Drawing libraries
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Set up logging
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}_$(Get-Date -Format 'yyyyMMddHHmmss').log"
$logPath = Join-Path $logDir $logFileName

# Ensure log directory exists
if (-not (Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    } catch {
        Write-Error "Failed to create log directory: $logDir"
        return
    }
}

# Enhanced logging function
function Write-Log {
    param (
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter()][ValidateSet('INFO', 'ERROR')] [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry
        $logBox.Items.Add($logEntry)
        $logBox.TopIndex = $logBox.Items.Count - 1
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

# Helper function to display messages
function Show-Message {
    param (
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][ValidateSet('Error', 'Information')] [string]$Type
    )
    $icon = if ($Type -eq 'Error') { [System.Windows.Forms.MessageBoxIcon]::Error } else { [System.Windows.Forms.MessageBoxIcon]::Information }
    [System.Windows.Forms.MessageBox]::Show($Message, $Type, [System.Windows.Forms.MessageBoxButtons]::OK, $icon)
}

# Gather certificate files
function Get-CertificateFiles {
    param (
        [Parameter(Mandatory = $true)][string[]]$Directories,
        [string[]]$Extensions = @('*.cer', '*.crl', '*.crt', '*.der', '*.pem', '*.pfx', '*.p12', '*.p7b')
    )
    $certificateFiles = @()
    foreach ($directory in $Directories) {
        if (Test-Path -Path $directory) {
            foreach ($extension in $Extensions) {
                $certificateFiles += Get-ChildItem -Path $directory -Filter $extension -Recurse -ErrorAction SilentlyContinue
            }
        } else {
            Show-Message -Message "Directory not found: $directory" -Type "Error"
        }
    }
    return $certificateFiles
}

# Check if a certificate is expired
function Is-CertificateExpired {
    param ([Parameter(Mandatory = $true)][string]$FilePath)
    try {
        $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $FilePath
        return $certificate.NotAfter -lt (Get-Date)
    } catch {
        Show-Message -Message "Error loading certificate: $FilePath. $_" -Type "Error"
        return $false
    }
}

# List certificates expiring soon and export to CSV
function List-ExpiringCertificates {
    param (
        [Parameter(Mandatory = $true)][string[]]$Files,
        [Parameter()][ValidateRange(1, 24)][int]$Months = 6
    )
    $expiringCertificates = @()
    $cutoffDate = (Get-Date).AddMonths($Months)
    foreach ($file in $Files) {
        try {
            $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $file
            if ($certificate.NotAfter -gt (Get-Date) -and $certificate.NotAfter -le $cutoffDate) {
                $expiringCertificates += [PSCustomObject]@{
                    FilePath = $file
                    Subject = $certificate.Subject
                    NotAfter = $certificate.NotAfter
                }
            }
        } catch {
            Write-Log -Message "Error processing certificate file: $file. $_" -Level "ERROR"
        }
    }

    $csvPath = Join-Path $logDir "ExpiringCertificates_$(Get-Date -Format 'yyyyMMddHHmmss').csv"

    if ($expiringCertificates.Count -gt 0) {
        $expiringCertificates | Export-Csv -Path $csvPath -NoTypeInformation -Force
        Show-Message -Message "Certificates expiring in the next $Months months have been listed in the log and exported to: $csvPath" -Type "Information"
        foreach ($cert in $expiringCertificates) {
            Write-Log -Message "Expiring Certificate: FilePath=$($cert.FilePath), Subject=$($cert.Subject), ExpiryDate=$($cert.NotAfter)" -Level "INFO"
        }
    } else {
        Show-Message -Message "No certificates expiring in the next $Months months found." -Type "Information"
    }
}

# Remove expired certificates
function Remove-ExpiredCertificates {
    param ([Parameter(Mandatory = $true)][string[]]$Files)
    Show-Message -Message "Starting expired certificate cleanup." -Type "Information"
    foreach ($file in $Files) {
        try {
            Remove-Item -Path $file -Force
            Write-Log -Message "Removed expired certificate file: $file" -Level "INFO"
        } catch {
            Show-Message -Message "Error removing certificate: $file. $_" -Type "Error"
        }
    }
    Show-Message -Message "Certificate cleanup completed." -Type "Information"
}

# Cleanup process
function Cleanup-Certificates {
    param ([Parameter(Mandatory = $true)][string]$Path)
    if (!(Test-Path $Path)) {
        Show-Message -Message "Invalid or inaccessible path: $Path" -Type "Error"
        return
    }

    $files = Get-CertificateFiles -Directories @($Path)
    $expiredFiles = $files | Where-Object { Is-CertificateExpired -FilePath $_.FullName }

    if ($expiredFiles.Count -gt 0) {
        Remove-ExpiredCertificates -Files $expiredFiles.FullName
    } else {
        Show-Message -Message "No expired certificates found." -Type "Information"
    }
}

# Folder browser dialog
function Browse-Folder {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select the folder to search for certificates"
    $dialog.ShowNewFolderButton = $false
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    } else {
        return $null
    }
}

# Form setup
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Certificate Management Tool'
$form.Size = New-Object System.Drawing.Size(600, 500)
$form.StartPosition = 'CenterScreen'

# Controls
$label = New-Object System.Windows.Forms.Label
$label.Text = "Enter path or browse for folder:"
$label.Location = New-Object System.Drawing.Point(20, 20)
$label.Size = New-Object System.Drawing.Size(550, 20)
$form.Controls.Add($label)

$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Location = New-Object System.Drawing.Point(20, 50)
$textBox.Size = New-Object System.Drawing.Size(400, 20)
$form.Controls.Add($textBox)

$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = "Browse"
$browseButton.Location = New-Object System.Drawing.Point(430, 50)
$browseButton.Size = New-Object System.Drawing.Size(120, 30)
$browseButton.Add_Click({
        $selectedPath = Browse-Folder
        if ($selectedPath) { $textBox.Text = $selectedPath }
    })
$form.Controls.Add($browseButton)

$monthsLabel = New-Object System.Windows.Forms.Label
$monthsLabel.Text = "Months to Check:"
$monthsLabel.Location = New-Object System.Drawing.Point(20, 100)
$monthsLabel.Size = New-Object System.Drawing.Size(120, 20)
$form.Controls.Add($monthsLabel)

$monthsBox = New-Object System.Windows.Forms.NumericUpDown
$monthsBox.Minimum = 1
$monthsBox.Maximum = 24
$monthsBox.Value = 6
$monthsBox.Location = New-Object System.Drawing.Point(150, 100)
$monthsBox.Size = New-Object System.Drawing.Size(100, 20)
$form.Controls.Add($monthsBox)

$executeButton = New-Object System.Windows.Forms.Button
$executeButton.Text = "Cleanup Repository"
$executeButton.Location = New-Object System.Drawing.Point(20, 150)
$executeButton.Size = New-Object System.Drawing.Size(250, 30)
$executeButton.Add_Click({
        # Validate if the path is provided
        if ([string]::IsNullOrWhiteSpace($textBox.Text)) {
            Show-Message -Message "The path cannot be empty. Please provide a valid directory." -Type "Error"
            return
        }

        # Validate if the path exists
        if (!(Test-Path $textBox.Text)) {
            Show-Message -Message "Invalid path provided. Please select a valid directory." -Type "Error"
            return
        }

        try {
            # Call the Cleanup-Certificates function with the validated path
            Cleanup-Certificates -Path $textBox.Text
        } catch {
            Write-Log -Message "Error during cleanup: $_" -Level "ERROR"
            Show-Message -Message "An unexpected error occurred during cleanup: $_" -Type "Error"
        }
    })
$form.Controls.Add($executeButton)

$listExpiringButton = New-Object System.Windows.Forms.Button
$listExpiringButton.Text = "List Expiring Certificates"
$listExpiringButton.Location = New-Object System.Drawing.Point(300, 150)
$listExpiringButton.Size = New-Object System.Drawing.Size(250, 30)
$listExpiringButton.Add_Click({
        # Validate if the path is provided
        if ([string]::IsNullOrWhiteSpace($textBox.Text)) {
            Show-Message -Message "The path cannot be empty. Please provide a valid directory." -Type "Error"
            return
        }
    
        # Validate if the path exists
        if (!(Test-Path $textBox.Text)) {
            Show-Message -Message "Invalid path provided. Please select a valid directory." -Type "Error"
            return
        }
    
        try {
            $files = Get-CertificateFiles -Directories @($textBox.Text)
            if ($files.Count -eq 0) {
                Show-Message -Message "No certificate files found in the specified directory." -Type "Information"
                return
            }

            List-ExpiringCertificates -Files $files.FullName -Months $monthsBox.Value
        } catch {
            Write-Log -Message "Error during processing: $_" -Level "ERROR"
            Show-Message -Message "An unexpected error occurred: $_" -Type "Error"
        }
    })
$form.Controls.Add($listExpiringButton)

$logBox = New-Object System.Windows.Forms.ListBox
$logBox.Location = New-Object System.Drawing.Point(20, 200)
$logBox.Size = New-Object System.Drawing.Size(550, 250)
$form.Controls.Add($logBox)

# Display the form
[void]$form.ShowDialog()

# End of script
