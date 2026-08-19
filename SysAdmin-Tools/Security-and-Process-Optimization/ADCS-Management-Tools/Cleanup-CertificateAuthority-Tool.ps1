<#
.SYNOPSIS
    PowerShell Script for Managing Expired Certificates in a Windows Certificate Authority.

.DESCRIPTION
    This script automates listing, revoking, and removing expired certificates 
    in a Windows Certificate Authority. It handles large volumes efficiently with batch processing.
    It expects the user to enter a date in dd/MM/yyyy format.

.PARAMETER Until
    A DateTime up to which certificates are considered expired. Defaults to the current date if not provided.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: December 23, 2024

.NOTES
    - Requires administrative privileges.
    - Adjust date formats if you use a different locale (e.g., dd/MM/yyyy).
    - Tested in a Portuguese-BR environment where certutil includes "Cadeia de caracteres de config:".
#>

# Hide PowerShell Console
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

# Add Windows Forms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Logging Setup
$logDir = 'C:\Logs-TEMP'
$logFileName = "CA_Management_$(Get-Date -Format 'yyyyMMddHHmmss').log"
$logPath = Join-Path $logDir $logFileName

# Ensure Log Directory Exists
if (-not (Test-Path -Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

# Log Function
function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "ERROR")]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logPath -Value $logEntry
}

# Message Display
function Show-Message {
    param (
        [string]$Message,
        [ValidateSet("Error", "Information")]$Type
    )
    $icon = if ($Type -eq 'Error') { [System.Windows.Forms.MessageBoxIcon]::Error } else { [System.Windows.Forms.MessageBoxIcon]::Information }
    [System.Windows.Forms.MessageBox]::Show($Message, $Type, [System.Windows.Forms.MessageBoxButtons]::OK, $icon)
}

# --- NEW: Retrieve the Current CA Name and strip "Cadeia de caracteres de config:" ---
function Get-CurrentCAName {
    Write-Log "Attempting to retrieve local CA configuration via 'certutil -getconfig'..." -Level "INFO"
    try {
        $configLines = certutil -getconfig 2>&1
        # Usually we need the first non-empty line
        $firstLine = ($configLines | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1).Trim()

        if (-not $firstLine) {
            Write-Log "No CA config detected. certutil returned empty output." -Level "ERROR"
            return $null
        }

        # For Portuguese-BR, it might look like:
        # Cadeia de caracteres de config: "ADCS01-TJAP.SEDE.TJAP\SEDE-ADCS01-TJAP-CA"
        # Let's remove that prefix and quotes using a regex capture
        $regex = '^Cadeia de caracteres de config:\s+"([^"]+)"$'
        if ($firstLine -match $regex) {
            $caName = $matches[1]
            Write-Log "Current CA Name extracted: $caName" -Level "INFO"
            return $caName
        }
        else {
            # If the line doesn't match the Portuguese prefix, maybe it's an English environment or another format
            Write-Log "Current CA Name: $firstLine" -Level "INFO"
            return $firstLine
        }
    }
    catch {
        Write-Log "Error retrieving CA Name: $_" -Level "ERROR"
        return $null
    }
}

# Helper function to parse dd/MM/yyyy or default to today
function Parse-CustomDate {
    param([string]$strDate)

    if ([string]::IsNullOrWhiteSpace($strDate)) {
        return Get-Date
    }
    else {
        try {
            # Force parse as dd/MM/yyyy
            return [datetime]::ParseExact($strDate, 'dd/MM/yyyy', $null)
        }
        catch {
            Show-Message -Message "Invalid date format. Please use dd/MM/yyyy." -Type "Error"
            return $null
        }
    }
}

# Retrieve Expired Certificates
function Get-ExpiredCertificates {
    param(
        [Parameter(Mandatory = $false)]
        [DateTime]$Until = (Get-Date),
        [Parameter(Mandatory = $true)]
        [string]$CAName
    )

    if (-not $CAName) {
        Write-Log "No CA name provided, cannot proceed with certificate listing." -Level "ERROR"
        return @()
    }

    # certutil expects an American style date string (MM/dd/yyyy) for NotAfter filters
    $dateString = $Until.ToString("MM/dd/yyyy")
    Write-Log "Fetching expired certificates (up to $Until) from CA '$CAName' using date string $dateString." -Level "INFO"

    try {
        $cmd = "certutil -config `"$CAName`" -view -restrict `"Disposition=20,NotAfter<=$dateString`""
        Write-Log "Running command: $cmd" -Level "INFO"

        $output = certutil -config "$CAName" -view -restrict "Disposition=20,NotAfter<=$dateString" | Out-String
        $lines = $output -split "`r?`n"
        $expiredCertificates = @()

        foreach ($line in $lines) {
            # Example lines from certutil output:
            # Request ID: 123
            # Certificate Expiration Date: 12/31/2024 23:59:59
            if ($line -match "Request ID: (\d+).*Certificate Expiration Date: (\d{1,2}\/\d{1,2}\/\d{4} \d{1,2}:\d{2}:\d{2})") {
                $requestID = $matches[1]
                $expirationDate = [datetime]$matches[2]
                if ($expirationDate -le $Until) {
                    $expiredCertificates += [PSCustomObject]@{
                        RequestID = $requestID
                        ExpirationDate = $expirationDate
                    }
                }
            }
        }
        Write-Log "Retrieved $($expiredCertificates.Count) expired certificates from CA '$CAName'." -Level "INFO"
        return $expiredCertificates
    } catch {
        Write-Log "Error fetching expired certificates from CA '$CAName': $_" -Level "ERROR"
        return @()
    }
}

# Revoke Expired Certificates
function Revoke-ExpiredCertificates {
    param(
        [Parameter(Mandatory = $false)]
        [DateTime]$Until = (Get-Date),
        [Parameter(Mandatory = $true)]
        [string]$CAName
    )

    $expiredCertificates = Get-ExpiredCertificates -Until $Until -CAName $CAName
    if ($expiredCertificates.Count -eq 0) {
        Show-Message -Message "No expired certificates to revoke for CA '$CAName'." -Type "Information"
        return
    }

    $total = $expiredCertificates.Count
    $counter = 0
    Write-Log "Starting certificate revocation for $total certificate(s) on CA '$CAName'." -Level "INFO"

    foreach ($cert in $expiredCertificates) {
        try {
            certutil -config "$CAName" -revoke $cert.RequestID | Out-Null
            $counter++
            Write-Log "Revoked certificate RequestID: $($cert.RequestID)" -Level "INFO"
        } catch {
            Write-Log "Error revoking certificate RequestID: $($cert.RequestID) on CA '$CAName': $_" -Level "ERROR"
        }
    }
    Show-Message -Message "$counter of $total expired certificates revoked on CA '$CAName'." -Type "Information"
}

# Remove Revoked Certificates
function Remove-RevokedCertificates {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CAName
    )

    try {
        certutil -config "$CAName" -deleterow 20 | Out-Null
        Write-Log "All revoked certificates removed successfully from CA '$CAName'." -Level "INFO"
        Show-Message -Message "All revoked certificates removed from CA '$CAName'." -Type "Information"
    } catch {
        Write-Log "Error removing revoked certificates from CA '$CAName': $_" -Level "ERROR"
    }
}

# Compact CA Database
function Compact-CADatabase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CAName
    )

    try {
        certutil -config "$CAName" -compactdb | Out-Null
        Write-Log "CA database compacted successfully for '$CAName'." -Level "INFO"
        Show-Message -Message "CA database compacted successfully for '$CAName'." -Type "Information"
    } catch {
        Write-Log "Error compacting CA database for '$CAName': $_" -Level "ERROR"
    }
}

# =========== GUI Design =============

$form = New-Object System.Windows.Forms.Form
$form.Text = "CA Management Tool"
$form.Size = New-Object System.Drawing.Size(600, 450)
$form.StartPosition = 'CenterScreen'

# Retrieve the local CA name at the start
$currentCA = Get-CurrentCAName
if (-not $currentCA) {
    Show-Message -Message "Unable to detect the current CA. Please verify certutil is available and you are an admin." -Type "Error"
    return
}

# Label for date input (dd/MM/yyyy)
$dateLabel = New-Object System.Windows.Forms.Label
$dateLabel.Text = "Enter expiration date (dd/MM/yyyy):"
$dateLabel.Location = New-Object System.Drawing.Point(10, 10)
$dateLabel.Size = New-Object System.Drawing.Size(250, 20)
$form.Controls.Add($dateLabel)

$dateText = New-Object System.Windows.Forms.TextBox
$dateText.Location = New-Object System.Drawing.Point(270, 10)
$dateText.Size = New-Object System.Drawing.Size(300, 20)
$form.Controls.Add($dateText)

# Helper to get a [DateTime] or $null from user input
function Get-UntilDateFromText() {
    $parsed = Parse-CustomDate $dateText.Text
    return $parsed
}

$form.Controls.Add((New-Object System.Windows.Forms.Button -Property @{
            Text = "List Expired Certificates"
            Location = New-Object System.Drawing.Point(10, 50)
            Size = New-Object System.Drawing.Size(560, 40)
            Add_Click = {
                $untilDate = Get-UntilDateFromText
                if ($untilDate -eq $null) { return }

                $certs = Get-ExpiredCertificates -Until $untilDate -CAName $currentCA
                Show-Message -Message "$($certs.Count) expired certificate(s) found on CA '$currentCA'. Check the log for details." -Type "Information"
            }
        }))

$form.Controls.Add((New-Object System.Windows.Forms.Button -Property @{
            Text = "Revoke Expired Certificates"
            Location = New-Object System.Drawing.Point(10, 100)
            Size = New-Object System.Drawing.Size(560, 40)
            Add_Click = {
                $untilDate = Get-UntilDateFromText
                if ($untilDate -eq $null) { return }
                Revoke-ExpiredCertificates -Until $untilDate -CAName $currentCA
            }
        }))

$form.Controls.Add((New-Object System.Windows.Forms.Button -Property @{
            Text = "Remove Revoked Certificates"
            Location = New-Object System.Drawing.Point(10, 150)
            Size = New-Object System.Drawing.Size(560, 40)
            Add_Click = {
                Remove-RevokedCertificates -CAName $currentCA
            }
        }))

$form.Controls.Add((New-Object System.Windows.Forms.Button -Property @{
            Text = "Compact CA Database"
            Location = New-Object System.Drawing.Point(10, 200)
            Size = New-Object System.Drawing.Size(560, 40)
            Add_Click = {
                Compact-CADatabase -CAName $currentCA
            }
        }))

$form.Controls.Add((New-Object System.Windows.Forms.Button -Property @{
            Text = "Close"
            Location = New-Object System.Drawing.Point(10, 250)
            Size = New-Object System.Drawing.Size(560, 40)
            Add_Click = {
                $form.Close()
            }
        }))

# Show the GUI
[void]$form.ShowDialog()

# End of script
