<#
.SYNOPSIS
    PowerShell Logging and Error Handling Framework.

.DESCRIPTION
    A standardized framework for logging and error handling, designed for use in PowerShell scripts. 
    It includes functions for initializing log paths, logging messages with levels, and handling errors gracefully.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: January 10, 2025
#>

# Function for logging messages with different levels
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "ERROR", "WARNING", "DEBUG", "CRITICAL")]
        [string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$MessageType] $Message"

    try {
        # Ensure the log directory exists
        if (-not (Test-Path $global:logDir)) {
            New-Item -Path $global:logDir -ItemType Directory -Force | Out-Null
        }
        # Write the log entry to the log file
        Add-Content -Path $global:logPath -Value $logEntry -ErrorAction Stop
    } catch {
        # Log the failure to the console
        Write-Error "Failed to write to log file: $_"
        Write-Output $logEntry
    }
}

# Function for handling errors and logging them
function Handle-Error {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage
    )
    Log-Message -Message "$ErrorMessage" -MessageType "ERROR"
    [System.Windows.Forms.MessageBox]::Show(
        $ErrorMessage, 
        "Error", 
        [System.Windows.Forms.MessageBoxButtons]::OK, 
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}

# Function for initializing dynamic log paths
function Initialize-ScriptPaths {
    param (
        [string]$DefaultLogDir = 'C:\Logs-TEMP'
    )

    # Get script name and timestamp
    $scriptName = if ($PSCommandPath) {
        [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
    } else {
        "Script"
    }
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

    # Determine log directory
    $logDir = if ($env:LOG_PATH -and $env:LOG_PATH -ne "") { $env:LOG_PATH } else { $DefaultLogDir }
    $logFileName = "${scriptName}_${timestamp}.log"
    $logPath = Join-Path $logDir $logFileName

    return @{
        LogDir     = $logDir
        LogPath    = $logPath
        ScriptName = $scriptName
    }
}

# Example usage demonstrating the logging framework
function Example-Logging {
    # Initialize paths
    $paths = Initialize-ScriptPaths
    $global:logDir = $paths.LogDir
    $global:logPath = $paths.LogPath

    # Log the start of the script
    Log-Message -Message "Starting the script." -MessageType "INFO"

    try {
        # Simulate an operation
        Log-Message -Message "Performing an operation..." -MessageType "DEBUG"
        # Simulate an error
        throw "An example error has occurred."
    } catch {
        Handle-Error -ErrorMessage $_.Exception.Message
    } finally {
        # Log the end of the script
        Log-Message -Message "Script execution finished." -MessageType "INFO"
    }
}

# Call the example function to test logging
Example-Logging
