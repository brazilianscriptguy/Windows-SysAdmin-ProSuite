<#
.SYNOPSIS
    PowerShell Script for Removing Expired Certificate Authorities (CAs) via Group Policy.

.DESCRIPTION
    This script automates the identification and removal of expired Certificate Authorities (CAs) to enhance 
    security posture and maintain a consistent certificate infrastructure across domain-joined machines. 
    Intended for execution through Group Policy (GPO) in both workstation and server environments.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: June 12, 2025
#>

# --- Logging Configuration ---
$scriptName = if ($MyInvocation.MyCommand.Name) {
    [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
} else {
    "ExpiredCertCleanup"
}
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName


# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    } catch {
        Write-Error "Failed to create the log directory at $logDir. Script execution aborted."
        exit 1
    }
}

# --- Logging Function ---
function Write-Log {
    param (
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter()][ValidateSet('INFO', 'ERROR', 'WARNING')] [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry
    } catch {
        Write-Error "Unable to write to the log file: $($_.Exception.Message)"
    }
}

# --- Function: Get-ExpiredCertificates ---
function Get-ExpiredCertificates {
    param (
        [Parameter(Mandatory = $true)][string]$StoreLocation
    )
    try {
        $storePath = "Cert:\$StoreLocation"
        if (-not (Test-Path $storePath)) {
            Write-Log -Message "The certificate store path '$storePath' does not exist." -Level "WARNING"
            return @()
        }

        $certificates = Get-ChildItem -Path $storePath -Recurse -ErrorAction Stop | Where-Object {
            $_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2] -and
            $_.NotAfter -lt (Get-Date) -and
            $_.Thumbprint
        }

        if ($certificates.Count -eq 0) {
            Write-Log -Message "No expired certificates found in store: $StoreLocation" -Level "INFO"
        } else {
            Write-Log -Message "Found $($certificates.Count) expired certificate(s) in store: $StoreLocation" -Level "INFO"
        }

        return $certificates
    } catch {
        Write-Log -Message "Failed to retrieve certificates from store '$StoreLocation': $($_.Exception.Message)" -Level "ERROR"
        return @()
    }
}

# --- Function: Remove-CertificatesByThumbprint ---
function Remove-CertificatesByThumbprint {
    param (
        [Parameter(Mandatory = $true)][string[]]$Thumbprints
    )
    Write-Log -Message "Initiating removal of expired certificates..." -Level "INFO"

    $removedCount = 0
    $failedCount = 0

    foreach ($thumbprint in $Thumbprints) {
        try {
            $certs = Get-ChildItem -Path Cert:\ -Recurse -ErrorAction Stop | Where-Object {
                $_.Thumbprint -eq $thumbprint.Trim()
            }

            if ($certs.Count -eq 0) {
                Write-Log -Message "No certificate found with thumbprint: $thumbprint" -Level "WARNING"
                $failedCount++
                continue
            }

            foreach ($cert in $certs) {
                if (Test-Path -Path $cert.PSPath) {
                    Remove-Item -Path $cert.PSPath -Force -ErrorAction Stop
                    Write-Log -Message "Successfully removed certificate with thumbprint: $thumbprint" -Level "INFO"
                    $removedCount++
                } else {
                    Write-Log -Message "Path not found for certificate with thumbprint: $thumbprint" -Level "WARNING"
                    $failedCount++
                }
            }
        } catch {
            Write-Log -Message "Failed to remove certificate with thumbprint: $thumbprint. Error: $($_.Exception.Message)" -Level "ERROR"
            $failedCount++
        }
    }

    Write-Log -Message "Removal summary: $removedCount removed, $failedCount failed." -Level "INFO"
    return @{Removed = $removedCount; Failed = $failedCount}
}

# --- Main Execution Block ---
Write-Log -Message "========== BEGIN: Expired Certificate Cleanup ==========" -Level "INFO"

$totalRemoved = 0
$totalFailed = 0
$locations = @('LocalMachine', 'CurrentUser')

foreach ($location in $locations) {
    Write-Log -Message "Processing certificate store: $location"
    $certificates = Get-ExpiredCertificates -StoreLocation $location
    if ($certificates.Count -gt 0) {
        $thumbprints = $certificates | ForEach-Object { $_.Thumbprint }
        $result = Remove-CertificatesByThumbprint -Thumbprints $thumbprints
        $totalRemoved += $result.Removed
        $totalFailed += $result.Failed
    }
}

Write-Log -Message "========== SUMMARY ==========" -Level "INFO"
Write-Log -Message "Total certificates removed: $totalRemoved" -Level "INFO"
Write-Log -Message "Total removal failures: $totalFailed" -Level "INFO"
Write-Log -Message "========== END OF SCRIPT ==========" -Level "INFO"

# End of script
