<#
.SYNOPSIS
    PowerShell script to synchronize folders from a network share to Active Directory computers via GPO.

.DESCRIPTION
    This script synchronizes a folder from a network location (e.g., NETLOGON share)
    to the local Administrator's desktop on AD workstations. It copies only new or updated files
    and removes obsolete files and folders that no longer exist in the source.
    Intended for use as a machine-level GPO startup script.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Updated: August 6, 2025 - Enhanced for PSSA compliance and state safety
#>

param (
    [string]$LogDirectory = "C:\Logs-TEMP"
)

# === LOGGING SETUP ===
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logPath = Join-Path $LogDirectory "$scriptName.log"

if (-not (Test-Path $LogDirectory)) {
    try {
        New-Item -Path $LogDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Failed to create log directory at $LogDirectory. Logging disabled."
        exit 1
    }
}

function Write-Log {
    param (
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO", "ERROR", "WARNING")] [string]$Severity = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Severity] $Message"

    try {
        Add-Content -Path $logPath -Value $entry -Encoding UTF8
    } catch {
        Write-Error "Logging failed: $_"
    }
}

# === PATH SETUP ===
$sourceFolderPath     = "\\forest-logonserver-name\NETLOGON\Source-Folder-Name"
$adminProfilePath     = "$env:SystemDrive\Users\Administrator"
$adminDesktopPath     = Join-Path $adminProfilePath "Desktop"
$destinationFolderPath = Join-Path $adminDesktopPath "Destination-Folder-Name"

if (-not (Test-Path $adminDesktopPath)) {
    Write-Log "Administrator desktop path not found: $adminDesktopPath" -Severity "ERROR"
    exit 1
}

# === SYNC FUNCTION ===
function Sync-Folders {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory)][string]$sourceFolder,
        [Parameter(Mandatory)][string]$destinationFolder
    )

    # Create destination folder if needed
    if (-not (Test-Path $destinationFolder)) {
        if ($PSCmdlet.ShouldProcess($destinationFolder, "Create destination folder")) {
            try {
                New-Item -ItemType Directory -Path $destinationFolder -Force -ErrorAction Stop | Out-Null
                Write-Log "Created destination folder: $destinationFolder"
            } catch {
                Write-Log "Failed to create destination folder: $destinationFolder. $_" -Severity "ERROR"
                return
            }
        }
    }

    # Sync files and folders
    $sourceItems = Get-ChildItem -Path $sourceFolder -Recurse -Force
    foreach ($item in $sourceItems) {
        $relativePath = $item.FullName.Substring($sourceFolder.Length).TrimStart('\')
        $destPath = Join-Path $destinationFolder $relativePath

        if ($item.PSIsContainer) {
            if (-not (Test-Path $destPath)) {
                if ($PSCmdlet.ShouldProcess($destPath, "Create directory")) {
                    try {
                        New-Item -ItemType Directory -Path $destPath -Force -ErrorAction Stop | Out-Null
                        Write-Log "Created directory: $destPath"
                    } catch {
                        Write-Log "Failed to create directory: $destPath. $_" -Severity "ERROR"
                    }
                }
            }
        } else {
            try {
                $destItem = Get-Item -Path $destPath -ErrorAction SilentlyContinue
                if ((-not $destItem) -or ($item.LastWriteTime -gt $destItem.LastWriteTime)) {
                    if ($PSCmdlet.ShouldProcess($destPath, "Copy file")) {
                        Copy-Item -Path $item.FullName -Destination $destPath -Force -ErrorAction Stop
                        Write-Log "Copied/Updated: $destPath"
                    }
                } else {
                    Write-Log "Skipped (up-to-date): $destPath"
                }
            } catch {
                Write-Log "Failed to copy: $destPath. $_" -Severity "ERROR"
            }
        }
    }

    # Remove orphaned files/folders
    $destItems = Get-ChildItem -Path $destinationFolder -Recurse -Force
    foreach ($item in $destItems) {
        $relativePath = $item.FullName.Substring($destinationFolder.Length).TrimStart('\')
        $sourcePath = Join-Path $sourceFolder $relativePath

        if (-not (Test-Path $sourcePath)) {
            if ($PSCmdlet.ShouldProcess($item.FullName, "Remove obsolete item")) {
                try {
                    Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
                    Write-Log "Removed obsolete: $($item.FullName)"
                } catch {
                    Write-Log "Failed to remove obsolete: $($item.FullName). $_" -Severity "ERROR"
                }
            }
        }
    }
}

# === EXECUTION ===
if (Test-Path $sourceFolderPath) {
    Sync-Folders -sourceFolder $sourceFolderPath -destinationFolder $destinationFolderPath
    Write-Log "Synchronization completed to $destinationFolderPath"
} else {
    Write-Log "Source folder missing: $sourceFolderPath" -Severity "ERROR"
}
