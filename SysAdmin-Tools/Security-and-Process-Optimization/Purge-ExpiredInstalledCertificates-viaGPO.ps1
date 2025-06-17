<#
.SYNOPSIS
    PowerShell script to remove expired certificates from Windows certificate stores.

.DESCRIPTION
    Identifies and removes expired certificates from both LocalMachine and CurrentUser stores,
    targeting sub-stores like My, Root, CA, AuthRoot, and TrustedPublisher.

    Generates a log and a CSV audit report. Designed for use with Group Policy (GPO)
    in enterprise workstation and server environments.

.AUTHOR
    Luiz Hamilton Silva - Updated by Widenex Assistant

.VERSION
    Last Updated: June 17, 2025
#>

# --- Logging Setup ---
$scriptName = if ($MyInvocation.MyCommand.Name) {
    [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
} else {
    "ExpiredCertCleanup"
}
$logDir = 'C:\Logs-TEMP'
$logFileName = "$scriptName.log"
$logPath = Join-Path $logDir $logFileName
$csvPath = Join-Path $logDir "$scriptName-expired.csv"

# Ensure log directory exists
if (-not (Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    } catch {
        Write-Error "Failed to create log directory at '$logDir'. Script aborted."
        exit 1
    }
}

# --- Logging Function ---
function Write-Log {
    param (
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR')] [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$timestamp] [$Level] $Message"
    Write-Output $entry
    try {
        Add-Content -Path $logPath -Value $entry
    } catch {
        Write-Warning "Unable to write to log: $($_.Exception.Message)"
    }
}

# --- Function: Get Expired Certificates ---
function Get-ExpiredCertificates {
    param (
        [Parameter(Mandatory)][string]$StoreLocation
    )

    $expired = @()
    $storeFolders = @("My", "Root", "CA", "AuthRoot", "TrustedPublisher")

    foreach ($folder in $storeFolders) {
        $path = "Cert:\$StoreLocation\$folder"
        if (-not (Test-Path $path)) {
            Write-Log -Message "Store path not found: $path" -Level "WARNING"
            continue
        }

        try {
            $certs = Get-ChildItem -Path $path -Recurse -ErrorAction Stop |
                Where-Object {
                    $_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2] -and
                    $_.NotAfter -lt (Get-Date) -and
                    $_.Thumbprint
                }

            if ($certs.Count -gt 0) {
                Write-Log -Message "Found $($certs.Count) expired certificate(s) in $path"
                $expired += $certs
            } else {
                Write-Log -Message "No expired certificates found in $path"
            }
        } catch {
            Write-Log -Message "Error accessing '$path': $($_.Exception.Message)" -Level "ERROR"
        }
    }

    return $expired
}

# --- Function: Remove Certificates by PSPath ---
function Remove-Certificates {
    param (
        [Parameter(Mandatory)][System.Security.Cryptography.X509Certificates.X509Certificate2[]]$Certificates
    )

    $removed = 0
    $failed = 0
    $removedList = @()

    foreach ($cert in $Certificates) {
        try {
            if (Test-Path $cert.PSPath) {
                Remove-Item -Path $cert.PSPath -Force -ErrorAction Stop
                Write-Log -Message "Successfully removed certificate: $($cert.Thumbprint)"
                $removed++
                $removedList += $cert
            } else {
                Write-Log -Message "PSPath not found for certificate: $($cert.Thumbprint)" -Level "WARNING"
                $failed++
            }
        } catch {
            Write-Log -Message "Failed to remove certificate ($($cert.Thumbprint)): $($_.Exception.Message)" -Level "ERROR"
            $failed++
        }
    }

    Write-Log -Message "Removal summary: $removed removed, $failed failed."
    return @{ Removed = $removed; Failed = $failed; Details = $removedList }
}

# --- Main Execution Block ---
Write-Log -Message "========= SCRIPT START: Expired Certificate Cleanup ========="

$totalRemoved = 0
$totalFailed = 0
$reportList = @()
$locations = @('LocalMachine', 'CurrentUser')

foreach ($location in $locations) {
    Write-Log -Message "Scanning certificate stores under: $location"
    $expiredCerts = Get-ExpiredCertificates -StoreLocation $location

    if ($expiredCerts.Count -gt 0) {
        $result = Remove-Certificates -Certificates $expiredCerts
        $totalRemoved += $result.Removed
        $totalFailed += $result.Failed
        $reportList += $result.Details
    }
}

# --- CSV Report ---
if ($reportList.Count -gt 0) {
    try {
        $reportList | Select-Object Subject, Issuer, NotAfter, Thumbprint, PSPath |
            Export-Csv -Path $csvPath -Encoding UTF8 -NoTypeInformation
        Write-Log -Message "CSV audit report generated: $csvPath"
    } catch {
        Write-Log -Message "Failed to write CSV report: $($_.Exception.Message)" -Level "ERROR"
    }
} else {
    Write-Log -Message "No expired certificates were removed. No report generated."
}

# --- Final Summary ---
Write-Log -Message "=========== SUMMARY ==========="
Write-Log -Message "Total certificates removed: $totalRemoved"
Write-Log -Message "Total failures: $totalFailed"
Write-Log -Message "=========== SCRIPT END =========="

exit 0

# # --- End of script ---
