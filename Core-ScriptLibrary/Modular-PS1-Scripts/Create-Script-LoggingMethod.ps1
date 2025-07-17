# Generalized logging function for script execution tracking
function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")]
        [string]$Level = "INFO",
        [Parameter(Mandatory = $false)]
        [string]$LogDirectory = (Join-Path $env:LOCALAPPDATA "ScriptLogs"),
        [Parameter(Mandatory = $false)]
        [switch]$ShowProgress
    )

    $ScriptName = $MyInvocation.MyCommand.Name
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $LogFile = Join-Path $LogDirectory "$ScriptName-$Timestamp.log"

    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }

    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Add-Content -Path $LogFile -Value $logEntry -ErrorAction Stop
    if ($ShowProgress) {
        Write-Progress -Activity "Processing" -Status $Message -PercentComplete 0
    }
    switch ($Level) {
        "ERROR" { Write-Error $logEntry }
        "WARNING" { Write-Warning $logEntry }
        "DEBUG" { if ($VerbosePreference -eq 'Continue' -or $PSCmdlet.MyInvocation.BoundParameters["Verbose"]) { Write-Verbose $logEntry } }
        "INFO" { if ($VerbosePreference -eq 'Continue') { Write-Verbose $logEntry } }
    }
}

# Error handling function for structured error logging and feedback
function Handle-Error {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage,
        [Parameter(Mandatory = $false)]
        [switch]$ShowMessageBox
    )
    Write-Log -Message $ErrorMessage -Level "ERROR"
    if ($ShowMessageBox -and $PSVersionTable.Platform -eq "Win32NT") {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($ErrorMessage, "Error", "OK", "Error") | Out-Null
    }
}

# Example usage
$VerbosePreference = 'Continue'
Write-Log "Script execution started" -LogDirectory (Join-Path $env:LOCALAPPDATA "CustomLogs")
Write-Log "Processing task" -Level "INFO" -ShowProgress
Write-Log "Debugging variable" -Level "DEBUG"
Handle-Error "Test error occurred" -ShowMessageBox
