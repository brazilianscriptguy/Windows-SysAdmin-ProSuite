<#
.SYNOPSIS
    Provides a reusable PowerShell script template for administrative automation tasks.

.DESCRIPTION
    This script serves as a customizable template for creating robust PowerShell scripts. It includes
    parameter handling, logging, error management, and a sample task (file creation). It can be adapted
    for various administrative workflows, such as system configuration, reporting, or integration with
    external tools. Use this as a starting point and modify the main logic to suit specific needs.

.FEATURES
    - Reusable Template: A scaffold for building consistent PowerShell scripts.
    - Logging Support: Generates detailed log files for tracking execution.
    - Error Handling: Implements try-catch blocks for robust error management.
    - Parameter Flexibility: Supports configurable inputs for customization.
    - Sample Task: Includes a basic file creation example to demonstrate structure.

.PARAMETERS
    -Path <string>: Specifies the directory path where the sample file will be created. Defaults to the script's directory.
    -FileName <string>: Defines the name of the file to create. Defaults to 'output.txt'.
    -LogPath <string>: Sets the path for log file storage. Defaults to $env:LOCALAPPDATA\ScriptLogs.
    -Verbose <switch>: Enables verbose output for detailed execution tracking.

.AUTHOR
    BrazilianScriptGuy - @brazilianscriptguy

.VERSION
    1.0 - July 17, 2025

.NOTES
    - Requires PowerShell 5.1 or higher.
    - Must be run with Administrator privileges for certain operations.
    - Compatible with PowerShell 7+ for enhanced features.
    - Customize the SAMPLE_TASK region with your specific logic.

.EXAMPLES
    Example 1: Running with custom path and filename
    ```powershell
    .\ScriptTemplate.ps1 -Path "C:\Temp" -FileName "report.txt" -Verbose
    ```

    Example 2: Minimal execution with defaults
    ```powershell
    .\ScriptTemplate.ps1
    ```
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$Path = $PSScriptRoot,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$FileName = "output.txt",

    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path (Split-Path $_ -Parent) -PathType Container })]
    [string]$LogPath = (Join-Path $env:LOCALAPPDATA "ScriptLogs"),

    [Parameter(Mandatory = $false)]
    [switch]$Verbose
)

begin {
    #region --- Initialization ---
    $ScriptName = $MyInvocation.MyCommand.Name
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $LogFile = Join-Path $LogPath "$ScriptName-$Timestamp.log"

    # Ensure log directory exists
    if (-not (Test-Path $LogPath)) {
        try {
            New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
            Write-Verbose "Created log directory: $LogPath"
        } catch {
            Write-Error "Failed to create log directory: $_"
            exit 1
        }
    }

    # Logging function
    function Write-Log {
        param ([string]$Message, [string]$Level = "INFO")
        $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
        Add-Content -Path $LogFile -Value $logEntry -ErrorAction Stop
        if ($Verbose -or $Level -eq "ERROR") {
            Write-Host $logEntry
        }
    }

    Write-Log "Starting $ScriptName (v1.0)"
    Write-Log "Parameters - Path: $Path, FileName: $FileName, LogPath: $LogPath"
    #endregion
}

process {
    try {
        #region --- SAMPLE_TASK ---
        Write-Log "Executing sample task: Creating file $FileName in $Path"
        $fullPath = Join-Path $Path $FileName
        if (Test-Path $fullPath) {
            Write-Log "File $fullPath already exists. Overwriting." -Level "WARNING"
        }
        "This is a sample file created on $(Get-Date)" | Out-File -FilePath $fullPath -Force
        Write-Log "Successfully created file: $fullPath"
        #endregion
    } catch {
        Write-Log "Error occurred: $_" -Level "ERROR"
        throw
    }
}

end {
    Write-Log "Completed $ScriptName execution"
}
