<#
.SYNOPSIS
    PowerShell script to remove expired certificates from Windows certificate stores.

.DESCRIPTION
    Identifies and removes expired certificates from "My", "Root", "CA", "AuthRoot", and "TrustedPublisher"
    stores under both LocalMachine and CurrentUser contexts. Generates an execution log and a CSV report
    with details of removed certificates. Designed for use in GPO Startup scripts on Windows systems.

.AUTHOR
    Luiz Hamilton Silva – @brazilianscriptguy

.VERSION
    Last Updated: June 17, 2025
#>

# --- Script Setup ---
$scriptName = "GPO-Purge-ExpiredInstalledCertificates"
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$logDir = "C:\Logs-TEMP"
$logFile = Join-Path $logDir "$scriptName.log"
$csvFile = Join-Path $logDir "$scriptName-expired.csv"

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
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Write-Output $entry
    try {
        Add-Content -Path $logFile -Value $entry
    } catch {
        Write-Warning "Unable to write to log: $($_.Exception.Message)"
    }
}

# --- Get Expired Certificates Safely ---
function Get-ExpiredCertificates {
    param ([string]$StoreLocation)

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
                    $_.NotAfter -ne $null -and
                    $_.NotAfter -lt (Get-Date)
                }

            if ($certs.Count -gt 0) {
                Write-Log -Message "Found $($certs.Count) expired certificate(s) in $path"
                $expired += $certs
            } else {
                Write-Log -Message "No expired certificates found in $path"
            }
        } catch {
            Write-Log -Message "Error accessing ${path}: $($_.Exception.Message)" -Level "ERROR"
        }
    }

    return $expired | Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2] }
}

# --- Remove Certificates ---
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
                Write-Log -Message "Removed certificate: $($cert.Subject) ($($cert.Thumbprint))"
                $removedList += $cert
                $removed++
            } else {
                Write-Log -Message "PSPath not found for certificate: $($cert.Thumbprint)" -Level "WARNING"
                $failed++
            }
        } catch {
            Write-Log -Message "Failed to remove certificate ${cert.Thumbprint}: $($_.Exception.Message)" -Level "ERROR"
            $failed++
        }
    }

    Write-Log -Message "Removal summary: $removed removed, $failed failed."
    return @{ Removed = $removed; Failed = $failed; Details = $removedList }
}

# --- Main Execution ---
Write-Log -Message "========= SCRIPT START: Expired Certificate Cleanup ========="

$totalRemoved = 0
$totalFailed = 0
$reportList = @()
$locations = @('LocalMachine', 'CurrentUser')

foreach ($location in $locations) {
    Write-Log -Message "Scanning certificate stores under: $location"
    $expiredCerts = Get-ExpiredCertificates -StoreLocation $location

    $certOnly = $expiredCerts | Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2] }

    if ($certOnly.Count -gt 0) {
        $result = Remove-Certificates -Certificates $certOnly
        $totalRemoved += $result.Removed
        $totalFailed += $result.Failed
        $reportList += $result.Details
    } else {
        Write-Log -Message "No expired certificates to remove in $location"
    }
}

# --- Export CSV Report ---
if ($reportList.Count -gt 0) {
    try {
        $reportList | Select-Object Subject, Issuer, NotAfter, Thumbprint, PSPath |
            Export-Csv -Path $csvFile -Encoding UTF8 -NoTypeInformation
        Write-Log -Message "CSV audit report generated: $csvFile"
    } catch {
        Write-Log -Message "Failed to generate CSV report: $($_.Exception.Message)" -Level "ERROR"
    }
} else {
    Write-Log -Message "No certificates removed. No report generated."
}

# --- Final Summary ---
Write-Log -Message "=========== SUMMARY ==========="
Write-Log -Message "Total certificates removed: $totalRemoved"
Write-Log -Message "Total failures: $totalFailed"
Write-Log -Message "=========== SCRIPT END =========="

exit 0

# --- End of script ---
