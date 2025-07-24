<#
.SYNOPSIS
    PowerShell Script for Renaming Disk Volumes via GPO.

.DESCRIPTION
    This script renames disk volumes uniformly across workstations using Group Policy (GPO), 
    simplifying disk management and improving consistency across the network.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: October 22, 2024
#>

# Determines the script name and sets up the log path
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\ITSM-Logs'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Ensures the log directory exists
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory | Out-Null
}

# Logging function
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    Add-Content -Path $logPath -Value $logEntry
}

# Function to rename the volumes of disks C: and D:
function RenameVolume {
    param (
        [Parameter(Mandatory = $true)]
        [string]$VolumePath,

        [Parameter(Mandatory = $true)]
        [string]$NewName
    )

    $currentLabel = (Get-Volume -DriveLetter $VolumePath[0]).FileSystemLabel
    if ($currentLabel -eq $NewName) {
        Log-Message "The volume ${VolumePath} is already named $NewName."
        return
    }

    try {
        Set-Volume -DriveLetter $VolumePath[0] -NewFileSystemLabel $NewName
        Log-Message "The name of volume ${VolumePath} was changed to $NewName."
    } catch {
        Log-Message "Error renaming volume ${VolumePath}: $($_.Exception.Message)"
    }
}

# Checks if the name of volume C: is the same as described in the hostname of the station
$NewNameC = $env:COMPUTERNAME
# Sets the new name for disk D: as 'Personal-Files' (adjust as needed)
$NewNameD = "Personal-Files"

# Assumes that the drive letters are C: and D:; adjust as needed
$VolumeCPath = "C"
$VolumeDPath = "D"

# Execution of functions to rename volumes C: and D:
RenameVolume -VolumePath $VolumeCPath -NewName $NewNameC
RenameVolume -VolumePath $VolumeDPath -NewName $NewNameD

# End of script
