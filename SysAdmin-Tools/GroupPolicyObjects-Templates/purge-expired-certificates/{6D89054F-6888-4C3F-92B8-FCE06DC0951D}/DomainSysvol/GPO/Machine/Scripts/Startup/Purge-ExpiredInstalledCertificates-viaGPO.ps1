<#
.SYNOPSIS
    PowerShell Script for Removing Expired Certificate Authorities (CAs) via Group Policy.

.DESCRIPTION
    This script automates the removal of expired Certificate Authorities (CAs) to enhance 
    security and maintain a consistent certificate infrastructure across domain machines. 
    Designed for execution via Group Policy (GPO).

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: December 6, 2024
#>

# Configure logging
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Failed to create log directory at $logDir. The script will terminate."
        exit
    }
}

# Function for logging
function Write-Log {
    param (
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter()][ValidateSet('INFO', 'ERROR')] [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

# Function to retrieve expired certificates
function Get-ExpiredCertificates {
    param (
        [Parameter(Mandatory = $true)][string]$StoreLocation
    )
    try {
        $certificates = Get-ChildItem -Path "Cert:\$StoreLocation" -Recurse |
            Where-Object { 
                ($_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2]) -and 
                ($_.NotAfter -lt (Get-Date)) -and 
                (Test-Path $_.PSPath)
            }
        if ($certificates.Count -eq 0) {
            Write-Log -Message "No expired certificates found in '$StoreLocation' store." -Level "INFO"
        } else {
            Write-Log -Message "Expired certificates found in '$StoreLocation': $($certificates.Count)" -Level "INFO"
        }
        return $certificates
    } catch {
        Write-Log -Message "Failed to retrieve expired certificates from '$StoreLocation': $_" -Level "ERROR"
        return @()
    }
}

# Function to remove certificates by thumbprint
function Remove-CertificatesByThumbprint {
    param (
        [Parameter(Mandatory = $true)][string[]]$Thumbprints
    )

    Write-Log -Message "Starting removal of selected certificates." -Level "INFO"
    $removedCount = 0
    $failedCount = 0

    foreach ($thumbprint in $Thumbprints) {
        try {
            # Search for certificates matching the thumbprint
            $certificates = Get-ChildItem -Path Cert:\ -Recurse | Where-Object { $_.Thumbprint -eq $thumbprint.Trim() }

            if ($certificates.Count -eq 0) {
                Write-Log -Message "No certificates found with thumbprint: $thumbprint" -Level "INFO"
                $failedCount++
                continue
            }

            foreach ($certificate in $certificates) {
                # Verify the path exists before removing
                if (Test-Path -Path $certificate.PSPath) {
                    Remove-Item -Path $certificate.PSPath -Force -ErrorAction Stop
                    Write-Log -Message "Successfully removed certificate with thumbprint: $thumbprint" -Level "INFO"
                    $removedCount++
                } else {
                    Write-Log -Message "Certificate path not found: $certificate.PSPath for thumbprint: $thumbprint" -Level "INFO"
                    $failedCount++
                }
            }
        } catch {
            Write-Log -Message "Failed to remove certificate with thumbprint: $thumbprint - $_" -Level "ERROR"
            $failedCount++
        }
    }

    Write-Log -Message "Certificate removal completed: $removedCount removed, $failedCount failed." -Level "INFO"
    return @{Removed = $removedCount; Failed = $failedCount }
}

# Execution
Write-Log -Message "Starting the process of removing expired certificates." -Level "INFO"

# Variables for summary
$totalRemoved = 0
$totalFailed = 0

# Process each store location
$locations = @('LocalMachine', 'CurrentUser')
foreach ($location in $locations) {
    $certificates = Get-ExpiredCertificates -StoreLocation $location
    if ($certificates.Count -gt 0) {
        $thumbprints = $certificates | ForEach-Object { $_.Thumbprint }
        $result = Remove-CertificatesByThumbprint -Thumbprints $thumbprints
        $totalRemoved += $result.Removed
        $totalFailed += $result.Failed
    }
}

# Final summary
Write-Log -Message "Summary: Total certificates removed: $totalRemoved, Total failures: $totalFailed." -Level "INFO"
Write-Log -Message "Script completed successfully." -Level "INFO"

# End of script
