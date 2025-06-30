<#
.SYNOPSIS
    PowerShell script to remove expired certificates from Windows certificate stores.

.DESCRIPTION
    Identifies and removes expired certificates from "My", "Root", "CA", "AuthRoot", and "TrustedPublisher"
    stores under both LocalMachine and CurrentUser contexts. Generates a log and CSV report.
    Designed for GPO Startup/Logon scripts.

.AUTHOR
    Luiz Hamilton Silva – @brazilianscriptguy

.VERSION
    Last Updated: June 30, 2025
#>

# ------------------- Setup -------------------
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$logDir = "C:\Logs-TEMP"
$logPath = Join-Path $logDir "$scriptName.log"
$csvPath = Join-Path $logDir "$scriptName-ExpiredRemoved-$timestamp.csv"

# Ensure log folder exists
if (-not (Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    } catch {
        Write-Error "Cannot create log directory at '$logDir'. Script aborted."
        [System.Environment]::Exit(1)
    }
}

# ------------------- Logging -------------------
function Write-Log {
    param (
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR')] [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    try {
        Add-Content -Path $logPath -Value $entry -Encoding Default
    } catch {
        Write-Warning "Unable to write log entry: $entry"
    }
}

# ------------------- Certificate Scanner -------------------
function Get-ExpiredCertificates {
    param ([Parameter(Mandatory)][string]$StoreLocation)

    $expired = @()
    $storeFolders = @("My", "Root", "CA", "AuthRoot", "TrustedPublisher")

    foreach ($folder in $storeFolders) {
        $path = "Cert:\$StoreLocation\$folder"

        if (-not (Test-Path $path)) {
            Write-Log -Message "Store not found: $path" -Level "WARNING"
            continue
        }

        try {
            $certs = Get-ChildItem -Path $path -Recurse -ErrorAction Stop | Where-Object {
                $_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2] -and
                $_.NotAfter -ne $null -and
                $_.NotAfter -lt (Get-Date)
            }

            if ($certs.Count -gt 0) {
                Write-Log -Message "Found $($certs.Count) expired certificate(s) in $path"
                $expired += $certs
            } else {
                Write-Log -Message "No expired certificates in $path"
            }
        } catch {
            Write-Log -Message "Error accessing ${path}: $($_.Exception.Message)" -Level "ERROR"
        }
    }

    return $expired
}

# ------------------- Certificate Remover -------------------
function Remove-Certificates {
    param (
        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2[]]$Certificates
    )

    $removed = 0
    $failed = 0
    $removedList = @()

    foreach ($cert in $Certificates) {
        try {
            if ($cert.PSPath -and (Test-Path $cert.PSPath)) {
                Remove-Item -Path $cert.PSPath -Force -ErrorAction Stop
                Write-Log -Message "Removed: $($cert.Subject) [$($cert.Thumbprint)]"
                $removedList += $cert
                $removed++
            } else {
                Write-Log -Message "PSPath not found for certificate: $($cert.Thumbprint)" -Level "WARNING"
                $failed++
            }
        } catch {
            Write-Log -Message "Failed to remove certificate $($cert.Thumbprint): $($_.Exception.Message)" -Level "ERROR"
            $failed++
        }
    }

    Write-Log -Message "Removal summary: $removed removed, $failed failed."
    return @{
        Removed = $removed
        Failed = $failed
        Details = $removedList
    }
}

# ------------------- Main Logic -------------------
Write-Log -Message "========= SCRIPT START: GPO Expired Certificate Cleanup ========="

$totalRemoved = 0
$totalFailed = 0
$allRemoved = @()
$contexts = @("LocalMachine", "CurrentUser")

foreach ($context in $contexts) {
    Write-Log -Message "Checking expired certificates under: $context"
    $expired = Get-ExpiredCertificates -StoreLocation $context

    if ($expired.Count -gt 0) {
        $result = Remove-Certificates -Certificates $expired
        $totalRemoved += $result.Removed
        $totalFailed += $result.Failed
        $allRemoved += $result.Details
    } else {
        Write-Log -Message "No expired certificates to remove in $context"
    }
}

# ------------------- CSV Report -------------------
if ($allRemoved.Count -gt 0) {
    try {
        $allRemoved | Select-Object Subject, Issuer, NotAfter, Thumbprint, PSPath |
            Export-Csv -Path $csvPath -Encoding UTF8 -NoTypeInformation
        Write-Log -Message "CSV report saved to: $csvPath"
    } catch {
        Write-Log -Message "Failed to export CSV: $($_.Exception.Message)" -Level "ERROR"
    }
} else {
    Write-Log -Message "No certificates were removed. No CSV report created."
}

# ------------------- Final Summary -------------------
Write-Log -Message "=========== SUMMARY ==========="
Write-Log -Message "Total certificates removed: $totalRemoved"
Write-Log -Message "Total removal failures: $totalFailed"
Write-Log -Message "=========== SCRIPT END =========="
[System.Environment]::Exit(0)

# End of script
