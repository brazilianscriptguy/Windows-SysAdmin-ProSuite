<#
.SYNOPSIS
    Silent Java Runtime Environment (JRE) installation script for all workstations via Computer GPO.

.DESCRIPTION
    This script verifies if Java JRE 21.0.7 or higher is installed. If not, it silently installs the specified MSI using a machine GPO startup policy.
    Detection is performed using `java.exe -version` and registry fallback via Uninstall keys.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: 2025-07-15
    Version: 2.1
#>

#region Parameters
param (
    [string]$JavaInstallerPath = "\\headq.scriptguy\netlogon\java-package-install\java-package-install.msi",
    [string]$MinimumJavaVersion = "21.0.7"
)
#endregion

#region Globals
$ErrorActionPreference = "Stop"
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = "C:\Logs-TEMP"
$logFile = "${scriptName}.log"
$logPath = Join-Path $logDir $logFile
#endregion

#region Logging
function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $padded = $Level.ToUpper().PadRight(8)
    $entry = "[$timestamp] [$padded] $Message"

    try {
        Add-Content -Path $logPath -Value $entry -ErrorAction Stop
    } catch {
        Write-Warning "Failed to write log entry: $_"
    }

    Write-Output $entry
}
#endregion

#region Environment Check
try {
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        Write-Log "Created log directory: $logDir"
    }

    if (-not (Test-Path $JavaInstallerPath)) {
        Write-Log "Java installer not found at: $JavaInstallerPath" -Level ERROR
        exit 1
    }
} catch {
    Write-Log "Initialization error: $_" -Level ERROR
    exit 1
}
#endregion

#region Version Detection - java.exe
function Get-JavaVersionFromExecutable {
    $javaPath = "${env:ProgramFiles}\Zulu\zulu-21\bin\java.exe"
    if (-not (Test-Path $javaPath)) {
        $javaPath = (Get-Command java.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1)
    }

    if ($javaPath -and (Test-Path $javaPath)) {
        $tempErr = [System.IO.Path]::GetTempFileName()
        try {
            Start-Process -FilePath $javaPath -ArgumentList "-version" -NoNewWindow -RedirectStandardError $tempErr -Wait
            $output = Get-Content $tempErr -ErrorAction SilentlyContinue | Out-String
            Remove-Item $tempErr -Force -ErrorAction SilentlyContinue
            if ($output -match '"(\d+\.\d+\.\d+).*"') {
                return $Matches[1]
            }
        } catch {
            Remove-Item $tempErr -Force -ErrorAction SilentlyContinue
        }
    }

    return $null
}
#endregion

#region Version Detection - Registry
function Get-JavaVersionFromRegistry {
    try {
        $uninstallKeys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )

        foreach ($path in $uninstallKeys) {
            $entry = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                     Where-Object { $_.DisplayName -like "*Zulu*" -and $_.DisplayVersion -match "^\d+\.\d+\.\d+" } |
                     Select-Object -First 1

            if ($entry) {
                return $entry.DisplayVersion
            }
        }
    } catch {
        return $null
    }

    return $null
}
#endregion

#region Combined Version Validation
Write-Log "Checking for installed Java Runtime Environment..."

$installedVersion = Get-JavaVersionFromExecutable
if (-not $installedVersion) {
    $installedVersion = Get-JavaVersionFromRegistry
    if ($installedVersion) {
        Write-Log "Java version detected via registry: $installedVersion"
    }
}

if ($installedVersion) {
    try {
        $installed = [System.Version]$installedVersion
        $required = [System.Version]$MinimumJavaVersion

        if ($installed -ge $required) {
            Write-Log "Java is already installed at compatible version ($installedVersion). Skipping installation."
            exit 0
        } else {
            Write-Log "Java is outdated: Current $installedVersion < Required $MinimumJavaVersion." -Level WARN
        }
    } catch {
        Write-Log "Version comparison error: Installed=$installedVersion, Required=$MinimumJavaVersion" -Level ERROR
    }
} else {
    Write-Log "No Java installation detected. Proceeding with installation."
}
#endregion

#region Installation
try {
    Write-Log "Starting Java JRE installation..."
    $installArgs = "/i `"$JavaInstallerPath`" /qn /norestart"
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        Write-Log "Java JRE installed successfully." -Level SUCCESS
    } else {
        Write-Log "Java installation failed. Exit code: $($process.ExitCode)" -Level ERROR
        exit $process.ExitCode
    }
} catch {
    Write-Log "Installation exception: $_" -Level ERROR
    exit 1
}
#endregion

#region Finalize
Write-Log "Script completed successfully."
exit 0
#endregion

# End of script
