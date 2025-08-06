<#
.SYNOPSIS
    PowerShell script to synchronize folders from a network share to Active Directory computers via GPO. 

.DESCRIPTION
    This script synchronizes a folder from a network location (e.g. NETLOGON share)
    to the local Administrator's desktop on AD workstations. It copies only new or updated files,
    and removes obsolete files and folders that are no longer in the source.
    Intended for use as a machine-level GPO startup script.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Updated: August 5, 2025 - Refactored for GPO startup context and system execution.
#>

param (
    [string]$LogDirectory = "C:\Logs-TEMP"
)

# Get the script name and define the full log path
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logFileName = "${scriptName}.log"
$logPath = Join-Path $LogDirectory $logFileName

# Ensure the log directory exists
if (-not (Test-Path $LogDirectory)) {
    try {
        New-Item -Path $LogDirectory -ItemType Directory -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Error "Failed to create log directory at $LogDirectory. Logging will be disabled."
        exit 1
    }
}

# Logging function with timestamp and severity
function Write-Log {
    param (
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Severity = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Severity] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to write to log: $_"
    }
}

# === CONFIGURATION ===

# Source network folder (change as needed)
$sourceFolderPath = "\\forest-logonserver-name\NETLOGON\Source-Folder-Name"

# Determine Administrator profile path
$adminProfilePath = "$env:SystemDrive\Users\Administrator"
$adminDesktopPath = Join-Path $adminProfilePath "Desktop"

# Check if desktop path exists
if (-not (Test-Path -Path $adminDesktopPath)) {
    Write-Log "Administrator desktop not found at: $adminDesktopPath" -Severity "ERROR"
    exit 1
}

# Define destination folder under Administrator desktop
$destinationFolderPath = Join-Path -Path $adminDesktopPath -ChildPath "Destination-Folder-Name"

# === FOLDER SYNC FUNCTION ===

function Sync-Folders {
    param (
        [string]$sourceFolder,
        [string]$destinationFolder
    )

    # Create destination folder if it doesn't exist
    if (-not (Test-Path -Path $destinationFolder)) {
        try {
            New-Item -ItemType Directory -Path $destinationFolder -ErrorAction Stop | Out-Null
            Write-Log "Created destination folder: $destinationFolder"
        }
        catch {
            Write-Log "Failed to create destination folder: $destinationFolder. Error: $_" -Severity "ERROR"
            return
        }
    }

    # Copy new or updated files from source to destination
    $sourceItems = Get-ChildItem -Path $sourceFolder -Recurse -Force
    foreach ($item in $sourceItems) {
        $relativePath = $item.FullName.Substring($sourceFolder.Length).TrimStart('\')
        $destinationPath = Join-Path $destinationFolder $relativePath

        if ($item.PSIsContainer) {
            if (-not (Test-Path -Path $destinationPath)) {
                try {
                    New-Item -ItemType Directory -Path $destinationPath -ErrorAction Stop | Out-Null
                    Write-Log "Created directory: $destinationPath"
                }
                catch {
                    Write-Log "Failed to create directory: $destinationPath. Error: $_" -Severity "ERROR"
                }
            }
        }
        else {
            try {
                $destItem = Get-Item -Path $destinationPath -ErrorAction SilentlyContinue
                if ((-not $destItem) -or ($item.LastWriteTime -gt $destItem.LastWriteTime)) {
                    Copy-Item -Path $item.FullName -Destination $destinationPath -Force -ErrorAction Stop
                    Write-Log "Copied/Updated file: $destinationPath"
                }
                else {
                    Write-Log "Skipped (already up-to-date): $destinationPath"
                }
            }
            catch {
                Write-Log "Failed to copy file: $destinationPath. Error: $_" -Severity "ERROR"
            }
        }
    }

    # Remove obsolete files/folders in destination that don't exist in source
    $destItems = Get-ChildItem -Path $destinationFolder -Recurse -Force
    foreach ($item in $destItems) {
        $relativePath = $item.FullName.Substring($destinationFolder.Length).TrimStart('\')
        $sourcePath = Join-Path $sourceFolder $relativePath

        if (-not (Test-Path -Path $sourcePath)) {
            try {
                Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
                Write-Log "Removed obsolete item: $($item.FullName)"
            }
            catch {
                Write-Log "Failed to remove obsolete item: $($item.FullName). Error: $_" -Severity "ERROR"
            }
        }
    }
}

# === EXECUTION ===

if (Test-Path -Path $sourceFolderPath) {
    Sync-Folders -sourceFolder $sourceFolderPath -destinationFolder $destinationFolderPath
    Write-Log "Synchronization completed successfully to $destinationFolderPath."
}
else {
    Write-Log "Source folder not found: $sourceFolderPath" -Severity "ERROR"
}

# End of script
