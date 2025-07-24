<#
.SYNOPSIS
    PowerShell Script for Resetting and Synchronizing Domain GPOs.

.DESCRIPTION
    This script resets and re-synchronizes all domain Group Policy Objects (GPOs), ensuring 
    compliance and consistent application of policies across workstations.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: October 22, 2024
#>

# Determine the script name and set up logging path
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    $null = New-Item -Path $logDir -ItemType Directory -ErrorAction SilentlyContinue
    if (-not (Test-Path $logDir)) {
        Write-Error "Failed to create log directory at $logDir. Logging will not be possible."
        return
    }
}

# Enhanced logging function with error handling
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

# Function to delete directories where the GPOs are stored
function Remove-GPODirectory {
    param (
        [string]$DirectoryPath
    )

    if (Test-Path -Path $DirectoryPath) {
        Remove-Item -Path $DirectoryPath -Recurse -Force -ErrorAction SilentlyContinue
        Log-Message "GPO directory deleted: $DirectoryPath"
    }
}

# Function to reset all GPOs
function Reset-AllGPOs {
    try {
        # Logging the start of GPO reset process
        Log-Message "Start of GPO reset process."

        # Resetting GPOs using "setup security.inf"
        Log-Message "Resetting GPOs using setup security.inf..."
        $command = "secedit /configure /db reset.sdb /cfg `"C:\Windows\security\templates\setup security.inf`" /overwrite /quiet"
        Invoke-Expression $command
        Log-Message "GPOs reset using setup security.inf"

        # Resetting GPOs using "defltbase.inf"
        Log-Message "Resetting GPOs using defltbase.inf..."
        $cfgPath = Join-Path -Path $env:windir -ChildPath "inf\defltbase.inf"
        $command = "secedit /configure /db reset.sdb /cfg `"$cfgPath`" /areas USER_POLICY MACHINE_POLICY SECURITYPOLICY /overwrite /quiet"
        Invoke-Expression $command
        Log-Message "GPOs reset using defltbase.inf"

        # Deleting the registry key where current GPO settings reside
        Log-Message "Deleting GPO registry key..."
        Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy" -Recurse -Force -ErrorAction SilentlyContinue
        Log-Message "Registry key of GPOs deleted."

        # Removing Group Policy directories
        Log-Message "Removing Group Policy directories..."
        Remove-GPODirectory -DirectoryPath "$env:windir\System32\GroupPolicy"
        Remove-GPODirectory -DirectoryPath "$env:windir\System32\GroupPolicyUsers"
        Remove-GPODirectory -DirectoryPath "$env:windir\SysWOW64\GroupPolicy"
        Remove-GPODirectory -DirectoryPath "$env:windir\SysWOW64\GroupPolicyUsers"
        Log-Message "Group Policy directories removed."

        # Logging the successful completion of GPO reset process
        Log-Message "GPO reset process completed successfully."

        # Scheduling system reboot after 15 seconds
        Start-Sleep -Seconds 15
        Restart-Computer -Force
    } catch {
        # Logging any error that occurs during GPO reset process
        Log-Message "An error occurred during the GPO reset process: $($_.Exception.Message)" -MessageType "ERROR"
    }
}

# Start execution of Reset-AllGPOs
Reset-AllGPOs

# End of script
