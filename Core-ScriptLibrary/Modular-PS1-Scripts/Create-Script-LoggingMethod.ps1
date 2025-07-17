# Logging function based on PS1 Script model
function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )

    $LogPath = Join-Path $env:LOCALAPPDATA "NuGetPublisher\Logs"
    $ScriptName = $MyInvocation.MyCommand.Name
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $LogFile = Join-Path $LogPath "$ScriptName-$Timestamp.log"

    if (-not (Test-Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }

    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Add-Content -Path $LogFile -Value $logEntry -ErrorAction Stop
    if ($Level -eq "ERROR") {
        Write-Error $logEntry
    } elseif ($VerbosePreference -eq 'Continue') {
        Write-Verbose $logEntry
    }
}

# Example usage
$VerbosePreference = 'Continue'
Write-Log "Script started"
Write-Log "Processing task" -Level "INFO"
Write-Log "Critical error occurred" -Level "ERROR"
