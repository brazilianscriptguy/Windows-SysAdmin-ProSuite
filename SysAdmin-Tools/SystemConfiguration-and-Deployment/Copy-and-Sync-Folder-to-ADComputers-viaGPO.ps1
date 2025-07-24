<#
.SYNOPSIS
    PowerShell Script for Synchronizing Folders to AD Computers via GPO.

.DESCRIPTION
    This script synchronizes folders from a network location to AD computers, ensuring that only new 
    or updated files are copied while outdated files are removed. It also includes full logging of the operation.

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
    try {
        New-Item -Path $logDir -ItemType Directory -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Failed to create log directory at $logDir. Logging will not be possible."
        return
    }
}

# Enhanced logging function with error handling
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

# Define the source folder path
$sourceFolderPath = "\\forest-logonserver-name\NETLOGON\Source-Folder-Name"

# Get the specific desktop path
$userDesktopPath = 'C:\Users\Administrator\Desktop' # Destination path

# Define the destination folder path on the desktop
$destinationFolderPath = Join-Path -Path $userDesktopPath -ChildPath "Destination-Folder-Name"

# Function to copy files if they are newer or missing and remove older files
function Sync-Folders {
    param (
        [string]$sourceFolder,
        [string]$destinationFolder
    )

    # Ensure the destination directory exists
    if (-not (Test-Path -Path $destinationFolder)) {
        try {
            New-Item -ItemType Directory -Path $destinationFolder | Out-Null
            Log-Message "Created directory: $destinationFolder"
        } catch {
            Log-Message "Failed to create directory: $destinationFolder. Error: $_"
            return
        }
    }

    # Copy new/updated files from source to destination
    Get-ChildItem -Path $sourceFolder -Recurse | ForEach-Object {
        $destinationPath = $_.FullName.Replace($sourceFolder, $destinationFolder)

        if ($_.PSIsContainer) {
            if (-not (Test-Path -Path $destinationPath)) {
                try {
                    New-Item -ItemType Directory -Path $destinationPath | Out-Null
                    Log-Message "Created directory: $destinationPath"
                } catch {
                    Log-Message "Failed to create directory: $destinationPath. Error: $_"
                }
            }
        } else {
            try {
                if ((-not (Test-Path -Path $destinationPath)) -or ($_.LastWriteTime -gt (Get-Item -Path $destinationPath).LastWriteTime)) {
                    Copy-Item -Path $_.FullName -Destination $destinationPath -Force
                    Log-Message "Updated: $destinationPath"
                } else {
                    Log-Message "Skipped: $destinationPath"
                }
            } catch {
                Log-Message "Failed to copy: $destinationPath. Error: $_"
            }
        }
    }

    # Remove files/folders from destination if they don't exist in the source
    Get-ChildItem -Path $destinationFolder -Recurse | ForEach-Object {
        $sourcePath = $_.FullName.Replace($destinationFolder, $sourceFolder)

        if (-not (Test-Path -Path $sourcePath)) {
            try {
                Remove-Item -Path $_.FullName -Recurse -Force
                Log-Message "Removed: $($_.FullName)"
            } catch {
                Log-Message "Failed to remove: $($_.FullName). Error: $_"
            }
        }
    }
}

# Copy the folder to the desktop, only updating files that are newer and removing older files
if (Test-Path -Path $sourceFolderPath) {
    Sync-Folders -sourceFolder $sourceFolderPath -destinationFolder $destinationFolderPath
    Log-Message "Folder successfully synced to $destinationFolderPath with only new/updated files and older files removed."
} else {
    Log-Message "Source folder does not exist: $sourceFolderPath."
}

# End of script
