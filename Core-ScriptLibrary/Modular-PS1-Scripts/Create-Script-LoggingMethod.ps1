# Generalized logging function for script execution tracking
function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO",
        [Parameter(Mandatory = $false)]
        [string]$LogDirectory = (Join-Path $env:LOCALAPPDATA "ScriptLogs")
    )

    $ScriptName = $MyInvocation.MyCommand.Name
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $LogFile = Join-Path $LogDirectory "$ScriptName-$Timestamp.log"

    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
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
Write-Log "Script execution started" -LogDirectory (Join-Path $env:LOCALAPPDATA "CustomLogs")
Write-Log "Processing task" -Level "INFO"
Write-Log "An error occurred" -Level "ERROR"
