<#
.SYNOPSIS
    PowerShell Script for Broadcasting Logon Messages via GPO.

.DESCRIPTION
    This script displays customizable warning messages to users upon login via Group Policy, 
    enabling broad communication in managed environments and enhancing organizational messaging.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: October 22, 2024
#>

# Enhanced error handling
$ErrorActionPreference = "SilentlyContinue"

# Define the log path for recording execution details
$logDir = 'C:\Logs-TEMP'
$logFileName = "BroadcastUserLogonMessage.log"
$logPath = Join-Path $logDir $logFileName

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    $null = New-Item -Path $logDir -ItemType Directory -ErrorAction SilentlyContinue
    if (-not (Test-Path $logDir)) {
        Write-Error "Failed to create log directory at $logDir. Logging will not be possible."
        return
    }
}

# Enhanced logging function
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$MessageType] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

# Function to display the post-logon message
function Display-LogonMessage {
    param (
        [string]$messageFilePath
    )

    try {
        # Check if the logon message file exists
        if (Test-Path $messageFilePath -PathType Leaf) {
            Log-Message "Message file found at: $messageFilePath. Executing the script."

            # Create a shell object to run the Windows Script Host
            $shell = New-Object -ComObject WScript.Shell

            # Execute the message file in a hidden window
            $exitCode = $shell.Run($messageFilePath, 0, $true)

            # Log the success or failure of the execution
            if ($exitCode -eq 0) {
                Log-Message "Post-logon message executed successfully."
            } else {
                Log-Message "Post-logon message execution failed with exit code: $exitCode" -MessageType "ERROR"
            }
        } else {
            Log-Message "Post-logon message file not found at: $messageFilePath" -MessageType "ERROR"
        }
    } catch {
        Log-Message "An error occurred while attempting to execute the post-logon message: $_" -MessageType "ERROR"
    }
}

# Define the path to the post-logon message file located on the network share
$messagePath = "\\forest-logonserver-name\netlogon\broadcast-logonmessage\Broadcast-UserLogonMessageViaGPO.hta"

# Execute the logon message display
Display-LogonMessage -messageFilePath $messagePath

# End of the script
