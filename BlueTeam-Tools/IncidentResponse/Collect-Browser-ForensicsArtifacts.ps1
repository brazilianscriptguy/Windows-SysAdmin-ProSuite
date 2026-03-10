<#
.SYNOPSIS
Browser Field Triage Collector v3.5 - requires -Version 5.1

.DESCRIPTION
Enterprise-style browser forensic triage collector with GUI, browser selection,
date/time range filtering, ZIP packaging, hashing, timeline generation, and
Google Forms indicator detection.

Designed for field acquisition on Windows hosts.

Key capabilities:
- Browser selection: Chrome, Edge, Firefox, Brave, Opera
- Current user only or all local user profiles
- Date/time range filtering for high-volume artifact directories
- Full-copy acquisition for core browser databases
- SQLite sidecar preservation (-wal, -shm, -journal)
- Google Forms-focused collection
- DNS cache + Prefetch collection
- Timeline, manifest, hashes, summary
- Automatic ZIP packaging

.NOTES
The date/time filter is intentionally applied only to high-volume folders
(Cache, Network, Service Worker, IndexedDB, etc.). Core DB files are copied
in full to preserve evidentiary completeness.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    3.5.0 - March 10, 2026
#>

[CmdletBinding()]
param(
    [switch]$ShowConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

# ------------------------------------------------------------
# Console visibility
# ------------------------------------------------------------
try {
    Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @"
using System;
using System.Runtime.InteropServices;
public static class NativeMethods {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
}
catch {
    # Ignore if already loaded
}

function Set-ConsoleVisibility {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Visible
    )

    try {
        $consolePtr = [Win32.NativeMethods]::GetConsoleWindow()
        if ($consolePtr -ne [IntPtr]::Zero) {
            # 5 = Show, 0 = Hide
            [void][Win32.NativeMethods]::ShowWindow($consolePtr, $(if ($Visible) { 5 } else { 0 }))
        }
    }
    catch {
        # Ignore
    }
}

if (-not $ShowConsole) {
    Set-ConsoleVisibility -Visible $false
}

# ------------------------------------------------------------
# Global state
# ------------------------------------------------------------
$script:CaseFolder = $null
$script:LogFile = $null
$script:Summary = New-Object System.Collections.Generic.List[object]

# ------------------------------------------------------------
# Utility helpers
# ------------------------------------------------------------
function Get-ScriptName {
    try {
        if ($MyInvocation.MyCommand.Name) {
            return [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
        }
        return 'Browser-Field-Triage-Collector-v3_5'
    }
    catch {
        return 'Browser-Field-Triage-Collector-v3_5'
    }
}

function Initialize-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        [void](New-Item -Path $Path -ItemType Directory -Force)
    }
}

function Show-InfoMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$Title = 'Browser Field Triage Collector'
    )

    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
}

function Show-WarningMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$Title = 'Browser Field Triage Collector'
    )

    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
}

function Show-ErrorMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$Title = 'Browser Field Triage Collector'
    )

    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    try {
        if (-not $script:LogFile) {
            return
        }

        $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    }
    catch {
        # Never let logging crash the tool
    }
}

function Add-SummaryRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$Item,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [string]$Details = ''
    )

    $script:Summary.Add([pscustomobject]@{
        Timestamp = Get-Date
        Category  = $Category
        Item      = $Item
        Status    = $Status
        Details   = $Details
    })
}

function Test-IsWindows {
    try {
        return $env:OS -eq 'Windows_NT'
    }
    catch {
        return $true
    }
}

function Test-IsAdministrator {
    try {
        $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($currentIdentity)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Resolve-LocalUserProfiles {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$CurrentUserOnly
    )

    $profiles = New-Object System.Collections.Generic.List[object]

    if ($CurrentUserOnly) {
        try {
            $currentProfilePath = [Environment]::GetFolderPath('UserProfile')
            if ($currentProfilePath -and (Test-Path -LiteralPath $currentProfilePath)) {
                $profiles.Add([pscustomobject]@{
                    UserName    = Split-Path -Path $currentProfilePath -Leaf
                    ProfilePath = $currentProfilePath
                })
            }
        }
        catch {
            Write-Log "Failed to resolve current user profile. $($_.Exception.Message)" 'ERROR'
        }

        return $profiles
    }

    try {
        $excluded = @(
            'All Users',
            'Default',
            'Default User',
            'Public',
            'defaultuser0',
            'WDAGUtilityAccount'
        )

        $items = Get-ChildItem -Path 'C:\Users' -Directory -ErrorAction SilentlyContinue |
            Where-Object { $excluded -notcontains $_.Name }

        foreach ($item in $items) {
            $profiles.Add([pscustomobject]@{
                UserName    = $item.Name
                ProfilePath = $item.FullName
            })
        }
    }
    catch {
        Write-Log "Failed to enumerate local user profiles. $($_.Exception.Message)" 'ERROR'
    }

    return $profiles
}

function Get-RelativePathSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$ChildPath
    )

    try {
        $normalizedRoot = (Resolve-Path -LiteralPath $RootPath).Path
        $normalizedChild = (Resolve-Path -LiteralPath $ChildPath).Path

        if ($normalizedChild.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $normalizedChild.Substring($normalizedRoot.Length).TrimStart('\')
        }

        return [IO.Path]::GetFileName($ChildPath)
    }
    catch {
        return [IO.Path]::GetFileName($ChildPath)
    }
}

function Copy-FileSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    try {
        if (-not (Test-Path -LiteralPath $Source)) {
            Write-Log "Source file not found: $Source" 'WARN'
            Add-SummaryRecord -Category 'CopyFile' -Item $Source -Status 'Missing'
            return $false
        }

        $destParent = Split-Path -Path $Destination -Parent
        Initialize-Directory -Path $destParent

        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
        Write-Log "Copied file: $Source -> $Destination"
        Add-SummaryRecord -Category 'CopyFile' -Item $Source -Status 'Copied'
        return $true
    }
    catch {
        Write-Log "Failed to copy file '$Source'. $($_.Exception.Message)" 'ERROR'
        Add-SummaryRecord -Category 'CopyFile' -Item $Source -Status 'Failed' -Details $_.Exception.Message
        return $false
    }
}

function Copy-SidecarFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFile,

        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )

    $sidecars = @(
        "$SourceFile-wal",
        "$SourceFile-shm",
        "$SourceFile-journal"
    )

    foreach ($sidecar in $sidecars) {
        if (Test-Path -LiteralPath $sidecar) {
            $destFile = Join-Path $DestinationFolder ([IO.Path]::GetFileName($sidecar))
            [void](Copy-FileSafe -Source $sidecar -Destination $destFile)
        }
    }
}

function Copy-DirectoryFilesByDate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDir,

        [Parameter(Mandatory = $true)]
        [string]$DestinationDir,

        [Parameter(Mandatory = $true)]
        [datetime]$StartDate,

        [Parameter(Mandatory = $true)]
        [datetime]$EndDate
    )

    try {
        if (-not (Test-Path -LiteralPath $SourceDir)) {
            Write-Log "Source directory not found: $SourceDir" 'WARN'
            Add-SummaryRecord -Category 'CopyDirectoryByDate' -Item $SourceDir -Status 'Missing'
            return
        }

        $sourceRoot = (Resolve-Path -LiteralPath $SourceDir).Path
        $files = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object {
                $_.LastWriteTime -ge $StartDate -and $_.LastWriteTime -le $EndDate
            })

        foreach ($file in $files) {
            $relativePath = Get-RelativePathSafe -RootPath $sourceRoot -ChildPath $file.FullName
            $destPath = Join-Path $DestinationDir $relativePath
            $destParent = Split-Path -Path $destPath -Parent
            Initialize-Directory -Path $destParent
            Copy-Item -LiteralPath $file.FullName -Destination $destPath -Force -ErrorAction SilentlyContinue
        }

        Write-Log "Date-filtered copy completed: $SourceDir. Files copied: $($files.Count)"
        Add-SummaryRecord -Category 'CopyDirectoryByDate' -Item $SourceDir -Status 'Completed' -Details ("FilesCopied={0}" -f $files.Count)
    }
    catch {
        Write-Log "Failed date-filtered copy for '$SourceDir'. $($_.Exception.Message)" 'ERROR'
        Add-SummaryRecord -Category 'CopyDirectoryByDate' -Item $SourceDir -Status 'Failed' -Details $_.Exception.Message
    }
}

function Copy-DirectoryFull {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDir,

        [Parameter(Mandatory = $true)]
        [string]$DestinationDir
    )

    try {
        if (-not (Test-Path -LiteralPath $SourceDir)) {
            Write-Log "Source directory not found: $SourceDir" 'WARN'
            Add-SummaryRecord -Category 'CopyDirectoryFull' -Item $SourceDir -Status 'Missing'
            return
        }

        Copy-Item -LiteralPath $SourceDir -Destination $DestinationDir -Recurse -Force -ErrorAction Stop
        Write-Log "Full directory copy completed: $SourceDir -> $DestinationDir"
        Add-SummaryRecord -Category 'CopyDirectoryFull' -Item $SourceDir -Status 'Completed'
    }
    catch {
        Write-Log "Failed full copy for '$SourceDir'. $($_.Exception.Message)" 'ERROR'
        Add-SummaryRecord -Category 'CopyDirectoryFull' -Item $SourceDir -Status 'Failed' -Details $_.Exception.Message
    }
}

function Export-HostContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputCsv
    )

    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $bios = Get-CimInstance Win32_BIOS
        $cs = Get-CimInstance Win32_ComputerSystem

        $context = [pscustomobject]@{
            ComputerName        = $env:COMPUTERNAME
            CurrentUser         = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            CollectionTime      = Get-Date
            OSCaption           = $os.Caption
            OSVersion           = $os.Version
            BuildNumber         = $os.BuildNumber
            TimeZone            = (Get-TimeZone).Id
            Manufacturer        = $cs.Manufacturer
            Model               = $cs.Model
            BIOSSerialNumber    = $bios.SerialNumber
            IsAdministrator     = Test-IsAdministrator
            PowerShellVersion   = $PSVersionTable.PSVersion.ToString()
        }

        $context | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8
        Write-Log "Host context exported: $OutputCsv"
        Add-SummaryRecord -Category 'HostContext' -Item $OutputCsv -Status 'Exported'
    }
    catch {
        Write-Log "Failed to export host context. $($_.Exception.Message)" 'ERROR'
        Add-SummaryRecord -Category 'HostContext' -Item $OutputCsv -Status 'Failed' -Details $_.Exception.Message
    }
}

function Collect-DNSCache {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputFile
    )

    try {
        ipconfig /displaydns | Out-File -LiteralPath $OutputFile -Encoding UTF8
        Write-Log "DNS cache captured: $OutputFile"
        Add-SummaryRecord -Category 'SystemArtifact' -Item 'DNS Cache' -Status 'Captured'
    }
    catch {
        Write-Log "Failed to capture DNS cache. $($_.Exception.Message)" 'ERROR'
        Add-SummaryRecord -Category 'SystemArtifact' -Item 'DNS Cache' -Status 'Failed' -Details $_.Exception.Message
    }
}

function Collect-Prefetch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationDir
    )

    try {
        Initialize-Directory -Path $DestinationDir

        if (-not (Test-Path -LiteralPath 'C:\Windows\Prefetch')) {
            Write-Log 'Prefetch directory not present.' 'WARN'
            Add-SummaryRecord -Category 'SystemArtifact' -Item 'Prefetch' -Status 'Missing'
            return
        }

        $patterns = @(
            '*CHROME*.pf',
            '*MSEDGE*.pf',
            '*FIREFOX*.pf',
            '*BRAVE*.pf',
            '*OPERA*.pf'
        )

        $count = 0
        foreach ($pattern in $patterns) {
            $matches = @(Get-ChildItem -Path 'C:\Windows\Prefetch' -Filter $pattern -File -ErrorAction SilentlyContinue)
            foreach ($match in $matches) {
                Copy-Item -LiteralPath $match.FullName -Destination (Join-Path $DestinationDir $match.Name) -Force -ErrorAction SilentlyContinue
                $count++
            }
        }

        Write-Log "Prefetch collection completed. Files copied: $count"
        Add-SummaryRecord -Category 'SystemArtifact' -Item 'Prefetch' -Status 'Captured' -Details ("FilesCopied={0}" -f $count)
    }
    catch {
        Write-Log "Failed to collect Prefetch files. $($_.Exception.Message)" 'ERROR'
        Add-SummaryRecord -Category 'SystemArtifact' -Item 'Prefetch' -Status 'Failed' -Details $_.Exception.Message
    }
}

function Get-ChromiumProfileDirectories {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    $result = New-Object System.Collections.Generic.List[object]

    try {
        if (-not (Test-Path -LiteralPath $BasePath)) {
            return $result
        }

        $dirs = @(Get-ChildItem -LiteralPath $BasePath -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^(Default|Profile \d+|Guest Profile)$'
            })

        foreach ($dir in $dirs) {
            $result.Add($dir)
        }
    }
    catch {
        Write-Log "Failed to enumerate Chromium profiles at $BasePath. $($_.Exception.Message)" 'ERROR'
    }

    return $result
}

function Get-OperaProfileBasePaths {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OperaRoot
    )

    $result = New-Object System.Collections.Generic.List[object]

    try {
        if (-not (Test-Path -LiteralPath $OperaRoot)) {
            return $result
        }

        $dirs = @(Get-ChildItem -LiteralPath $OperaRoot -Directory -ErrorAction SilentlyContinue)
        foreach ($dir in $dirs) {
            $result.Add([pscustomobject]@{
                Label    = $dir.Name
                BasePath = $dir.FullName
            })
        }
    }
    catch {
        Write-Log "Failed to enumerate Opera roots at $OperaRoot. $($_.Exception.Message)" 'ERROR'
    }

    return $result
}

function Collect-ChromiumBrowser {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BrowserLabel,

        [Parameter(Mandatory = $true)]
        [string]$UserName,

        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [datetime]$StartDate,

        [Parameter(Mandatory = $true)]
        [datetime]$EndDate,

        [Parameter(Mandatory = $true)]
        [bool]$FullHighVolumeCollection
    )

    if (-not (Test-Path -LiteralPath $BasePath)) {
        Write-Log "$BrowserLabel base path not found for user ${UserName}: $BasePath" 'WARN'
        Add-SummaryRecord -Category 'Browser' -Item "$BrowserLabel / $UserName" -Status 'NotPresent'
        return
    }

    Write-Log "$BrowserLabel detected for user $UserName at $BasePath"
    Add-SummaryRecord -Category 'Browser' -Item "$BrowserLabel / $UserName" -Status 'Detected'

    $browserDest = Join-Path $script:CaseFolder (('{0}_{1}' -f $BrowserLabel, $UserName) -replace '[\\/:*?"<>|]', '_')
    Initialize-Directory -Path $browserDest

    $profileDirs = Get-ChromiumProfileDirectories -BasePath $BasePath
    foreach ($profile in $profileDirs) {
        $profileDest = Join-Path $browserDest $profile.Name
        Initialize-Directory -Path $profileDest

        Write-Log "Processing $BrowserLabel profile: $($profile.FullName)"

        # Core DB / profile files - always copy in full
        $coreFiles = @(
            'History',
            'History Provider Cache',
            'Cookies',
            'Login Data',
            'Web Data',
            'Favicons',
            'Bookmarks',
            'Preferences',
            'Secure Preferences',
            'Current Session',
            'Current Tabs',
            'Last Session',
            'Last Tabs',
            'Top Sites',
            'Visited Links',
            'Network Persistent State'
        )

        foreach ($fileName in $coreFiles) {
            $sourceFile = Join-Path $profile.FullName $fileName
            if (Test-Path -LiteralPath $sourceFile) {
                $destFile = Join-Path $profileDest ($fileName -replace '[\\/:*?"<>|]', '_')
                if (Copy-FileSafe -Source $sourceFile -Destination $destFile) {
                    Copy-SidecarFiles -SourceFile $sourceFile -DestinationFolder $profileDest
                }
            }
        }

        # High-volume / app-state directories
        $highVolumeDirs = @(
            'Cache',
            'Code Cache',
            'GPUCache',
            'Service Worker',
            'Session Storage',
            'Local Storage',
            'IndexedDB',
            'Network',
            'Storage',
            'blob_storage'
        )

        foreach ($dirName in $highVolumeDirs) {
            $srcDir = Join-Path $profile.FullName $dirName
            $dstDir = Join-Path $profileDest $dirName

            if ($FullHighVolumeCollection) {
                Copy-DirectoryFull -SourceDir $srcDir -DestinationDir $dstDir
            }
            else {
                Copy-DirectoryFilesByDate -SourceDir $srcDir -DestinationDir $dstDir -StartDate $StartDate -EndDate $EndDate
            }
        }
    }
}

function Collect-Firefox {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName,

        [Parameter(Mandatory = $true)]
        [string]$ProfilesPath,

        [Parameter(Mandatory = $true)]
        [datetime]$StartDate,

        [Parameter(Mandatory = $true)]
        [datetime]$EndDate,

        [Parameter(Mandatory = $true)]
        [bool]$FullHighVolumeCollection
    )

    if (-not (Test-Path -LiteralPath $ProfilesPath)) {
        Write-Log "Firefox profiles path not found for user ${UserName}: $ProfilesPath" 'WARN'
        Add-SummaryRecord -Category 'Browser' -Item "Firefox / $UserName" -Status 'NotPresent'
        return
    }

    Write-Log "Firefox detected for user $UserName at $ProfilesPath"
    Add-SummaryRecord -Category 'Browser' -Item "Firefox / $UserName" -Status 'Detected'

    $browserDest = Join-Path $script:CaseFolder ("Firefox_{0}" -f $UserName)
    Initialize-Directory -Path $browserDest

    $profiles = @(Get-ChildItem -LiteralPath $ProfilesPath -Directory -ErrorAction SilentlyContinue)

    foreach ($profile in $profiles) {
        $profileDest = Join-Path $browserDest $profile.Name
        Initialize-Directory -Path $profileDest

        Write-Log "Processing Firefox profile: $($profile.FullName)"

        $coreFiles = @(
            'places.sqlite',
            'cookies.sqlite',
            'formhistory.sqlite',
            'favicons.sqlite',
            'permissions.sqlite',
            'content-prefs.sqlite',
            'logins.json',
            'key4.db',
            'sessionstore.jsonlz4',
            'prefs.js',
            'addons.json'
        )

        foreach ($fileName in $coreFiles) {
            $sourceFile = Join-Path $profile.FullName $fileName
            if (Test-Path -LiteralPath $sourceFile) {
                $destFile = Join-Path $profileDest $fileName
                if (Copy-FileSafe -Source $sourceFile -Destination $destFile) {
                    Copy-SidecarFiles -SourceFile $sourceFile -DestinationFolder $profileDest
                }
            }
        }

        $highVolumeDirs = @(
            'storage',
            'cache2',
            'sessionstore-backups'
        )

        foreach ($dirName in $highVolumeDirs) {
            $srcDir = Join-Path $profile.FullName $dirName
            $dstDir = Join-Path $profileDest $dirName

            if ($FullHighVolumeCollection) {
                Copy-DirectoryFull -SourceDir $srcDir -DestinationDir $dstDir
            }
            else {
                Copy-DirectoryFilesByDate -SourceDir $srcDir -DestinationDir $dstDir -StartDate $StartDate -EndDate $EndDate
            }
        }
    }
}

function Test-TextFileCandidate {
    param(
        [Parameter(Mandatory = $true)]
        [IO.FileInfo]$File
    )

    $interestingExtensions = @(
        '.txt', '.json', '.log', '.html', '.htm', '.csv', '.xml', '.js', '.ldb', '.sqlite', '.db'
    )

    if ($interestingExtensions -contains $File.Extension.ToLowerInvariant()) {
        return $true
    }

    if ($File.Name -match 'History|Cookies|Web Data|Preferences|session|form|network|index|cache') {
        return $true
    }

    return $false
}

function Detect-GoogleFormsIndicators {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputCsv
    )

    $patterns = @(
        'docs\.google\.com/forms',
        'forms\.gle',
        'formResponse',
        'Your response has been recorded',
        'google form',
        'google forms',
        'upload\.googleusercontent\.com',
        'docs\.googleusercontent\.com',
        'drive\.google\.com',
        'AccountChooser',
        'signin',
        'draftResponse',
        'fileUpload',
        'upload',
        'response has been recorded'
    )

    $results = New-Object System.Collections.Generic.List[object]

    try {
        $files = @(Get-ChildItem -LiteralPath $RootPath -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { Test-TextFileCandidate -File $_ } |
            Where-Object { $_.Length -le 50MB })

        foreach ($file in $files) {
            try {
                $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
                if ([string]::IsNullOrWhiteSpace($content)) {
                    continue
                }

                foreach ($pattern in $patterns) {
                    if ($content -match $pattern) {
                        $results.Add([pscustomobject]@{
                            FilePath      = $file.FullName
                            FileName      = $file.Name
                            Indicator     = $pattern
                            LastWriteTime = $file.LastWriteTime
                            SizeBytes     = $file.Length
                        })
                    }
                }
            }
            catch {
                # Ignore unreadable files
            }
        }

        $results |
            Sort-Object FilePath, Indicator -Unique |
            Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8

        Write-Log "Google Forms indicator scan completed: $OutputCsv"
        Add-SummaryRecord -Category 'Report' -Item 'GoogleForms_Indicator_Hits.csv' -Status 'Generated'
    }
    catch {
        Write-Log "Failed to scan for Google Forms indicators. $($_.Exception.Message)" 'ERROR'
        Add-SummaryRecord -Category 'Report' -Item 'GoogleForms_Indicator_Hits.csv' -Status 'Failed' -Details $_.Exception.Message
    }
}

function Build-Timeline {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputCsv
    )

    try {
        Get-ChildItem -LiteralPath $RootPath -Recurse -Force -ErrorAction SilentlyContinue |
            Select-Object FullName, Name, Length, CreationTime, LastWriteTime |
            Sort-Object LastWriteTime, FullName |
            Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8

        Write-Log "Timeline exported: $OutputCsv"
        Add-SummaryRecord -Category 'Report' -Item 'Timeline_Reconstructed.csv' -Status 'Generated'
    }
    catch {
        Write-Log "Failed to build timeline. $($_.Exception.Message)" 'ERROR'
        Add-SummaryRecord -Category 'Report' -Item 'Timeline_Reconstructed.csv' -Status 'Failed' -Details $_.Exception.Message
    }
}

function Export-Manifest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputCsv
    )

    try {
        Get-ChildItem -LiteralPath $RootPath -Recurse -Force -ErrorAction SilentlyContinue |
            Select-Object FullName, Name, PSIsContainer, Length, CreationTime, LastWriteTime |
            Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8

        Write-Log "Manifest exported: $OutputCsv"
        Add-SummaryRecord -Category 'Report' -Item 'manifest.csv' -Status 'Generated'
    }
    catch {
        Write-Log "Failed to export manifest. $($_.Exception.Message)" 'ERROR'
        Add-SummaryRecord -Category 'Report' -Item 'manifest.csv' -Status 'Failed' -Details $_.Exception.Message
    }
}

function Export-Hashes {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputCsv,

        [Parameter(Mandatory = $true)]
        [string[]]$ExcludePaths
    )

    try {
        $excludeSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($path in $ExcludePaths) {
            if ([string]::IsNullOrWhiteSpace($path)) {
                continue
            }

            try {
                if (Test-Path -LiteralPath $path) {
                    [void]$excludeSet.Add((Resolve-Path -LiteralPath $path).Path)
                }
                else {
                    [void]$excludeSet.Add($path)
                }
            }
            catch {
                [void]$excludeSet.Add($path)
            }
        }

        $hashResults = foreach ($file in @(Get-ChildItem -LiteralPath $RootPath -Recurse -File -Force -ErrorAction SilentlyContinue)) {
            $fullPath = $file.FullName

            if ($excludeSet.Contains($fullPath)) {
                continue
            }

            try {
                $hash = Get-FileHash -LiteralPath $fullPath -Algorithm SHA256 -ErrorAction Stop
                [pscustomobject]@{
                    FilePath      = $fullPath
                    SizeBytes     = $file.Length
                    LastWriteTime = $file.LastWriteTime
                    SHA256        = $hash.Hash
                }
            }
            catch {
                Write-Log "Hash failed for '$fullPath'. $($_.Exception.Message)" 'WARN'
            }
        }

        $hashResults | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8
        Write-Log "Hashes exported: $OutputCsv"
        Add-SummaryRecord -Category 'Report' -Item 'hashes.csv' -Status 'Generated'
    }
    catch {
        Write-Log "Failed to export hashes. $($_.Exception.Message)" 'ERROR'
        Add-SummaryRecord -Category 'Report' -Item 'hashes.csv' -Status 'Failed' -Details $_.Exception.Message
    }
}

function Export-CollectionSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputFile,

        [Parameter(Mandatory = $true)]
        [string[]]$SelectedBrowsers,

        [Parameter(Mandatory = $true)]
        [bool]$CurrentUserOnly,

        [Parameter(Mandatory = $true)]
        [datetime]$StartDate,

        [Parameter(Mandatory = $true)]
        [datetime]$EndDate,

        [Parameter(Mandatory = $true)]
        [bool]$FullHighVolumeCollection,

        [Parameter(Mandatory = $true)]
        [bool]$CreateZip
    )

    try {
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add(('=' * 72))
        $lines.Add('BROWSER FIELD TRIAGE COLLECTOR - COLLECTION SUMMARY')
        $lines.Add(('=' * 72))
        $lines.Add(('Collection Time      : {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
        $lines.Add(('Computer Name        : {0}' -f $env:COMPUTERNAME))
        $lines.Add(('Current User         : {0}' -f [System.Security.Principal.WindowsIdentity]::GetCurrent().Name))
        $lines.Add(('Selected Browsers    : {0}' -f ($SelectedBrowsers -join ', ')))
        $lines.Add(('Scope                : {0}' -f $(if ($CurrentUserOnly) { 'Current User Only' } else { 'All Local Profiles' })))
        $lines.Add(('Start Date/Time      : {0}' -f $StartDate))
        $lines.Add(('End Date/Time        : {0}' -f $EndDate))
        $lines.Add(('Full High-Volume     : {0}' -f $FullHighVolumeCollection))
        $lines.Add(('Create ZIP           : {0}' -f $CreateZip))
        $lines.Add(('Output Folder        : {0}' -f $script:CaseFolder))
        $lines.Add('')

        $lines.Add('Summary Records')
        $lines.Add(('-' * 72))

        foreach ($item in $script:Summary) {
            $lines.Add(('[{0}] {1} | {2} | {3} | {4}' -f
                (Get-Date $item.Timestamp -Format 'yyyy-MM-dd HH:mm:ss'),
                $item.Category,
                $item.Item,
                $item.Status,
                $item.Details
            ))
        }

        $lines | Out-File -LiteralPath $OutputFile -Encoding UTF8
        Write-Log "Collection summary exported: $OutputFile"
        Add-SummaryRecord -Category 'Report' -Item 'collection_summary.txt' -Status 'Generated'
    }
    catch {
        Write-Log "Failed to export collection summary. $($_.Exception.Message)" 'ERROR'
        Add-SummaryRecord -Category 'Report' -Item 'collection_summary.txt' -Status 'Failed' -Details $_.Exception.Message
    }
}

function Create-ZipPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )

    try {
        $zipPath = '{0}.zip' -f $SourceFolder

        if (Test-Path -LiteralPath $zipPath) {
            Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        }

        [System.IO.Compression.ZipFile]::CreateFromDirectory($SourceFolder, $zipPath)
        Write-Log "ZIP package created: $zipPath"
        Add-SummaryRecord -Category 'Packaging' -Item $zipPath -Status 'Created'
        return $zipPath
    }
    catch {
        Write-Log "Failed to create ZIP package. $($_.Exception.Message)" 'ERROR'
        Add-SummaryRecord -Category 'Packaging' -Item $SourceFolder -Status 'Failed' -Details $_.Exception.Message
        return $null
    }
}

function Start-Collection {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$SelectedBrowsers,

        [Parameter(Mandatory = $true)]
        [bool]$CurrentUserOnly,

        [Parameter(Mandatory = $true)]
        [datetime]$StartDate,

        [Parameter(Mandatory = $true)]
        [datetime]$EndDate,

        [Parameter(Mandatory = $true)]
        [bool]$FullHighVolumeCollection,

        [Parameter(Mandatory = $true)]
        [bool]$CreateZip
    )

    try {
        if (-not (Test-IsWindows)) {
            throw 'This tool is designed for Windows only.'
        }

        if ($EndDate -lt $StartDate) {
            throw 'End Date/Time must be greater than or equal to Start Date/Time.'
        }

        if (@($SelectedBrowsers).Count -eq 0) {
            throw 'Select at least one browser.'
        }

        $caseName = 'BrowserTriage_{0}' -f (Get-Date -Format 'yyyyMMdd_HHmmss')
        $script:CaseFolder = Join-Path 'C:\' $caseName
        Initialize-Directory -Path $script:CaseFolder

        $script:LogFile = Join-Path $script:CaseFolder 'collection.log'
        [void](New-Item -Path $script:LogFile -ItemType File -Force)

        Write-Log 'Collection started.'
        Write-Log ('SelectedBrowsers = {0}' -f ($SelectedBrowsers -join ', '))
        Write-Log ('CurrentUserOnly  = {0}' -f $CurrentUserOnly)
        Write-Log ('StartDate        = {0}' -f $StartDate)
        Write-Log ('EndDate          = {0}' -f $EndDate)
        Write-Log ('FullHighVolume   = {0}' -f $FullHighVolumeCollection)
        Write-Log ('CreateZip        = {0}' -f $CreateZip)

        Export-HostContext -OutputCsv (Join-Path $script:CaseFolder 'host_context.csv')

        $profiles = Resolve-LocalUserProfiles -CurrentUserOnly $CurrentUserOnly

        foreach ($profile in $profiles) {
            $userName = $profile.UserName
            $profilePath = $profile.ProfilePath

            if ($SelectedBrowsers -contains 'Chrome') {
                Collect-ChromiumBrowser `
                    -BrowserLabel 'Chrome' `
                    -UserName $userName `
                    -BasePath (Join-Path $profilePath 'AppData\Local\Google\Chrome\User Data') `
                    -StartDate $StartDate `
                    -EndDate $EndDate `
                    -FullHighVolumeCollection $FullHighVolumeCollection
            }

            if ($SelectedBrowsers -contains 'Edge') {
                Collect-ChromiumBrowser `
                    -BrowserLabel 'Edge' `
                    -UserName $userName `
                    -BasePath (Join-Path $profilePath 'AppData\Local\Microsoft\Edge\User Data') `
                    -StartDate $StartDate `
                    -EndDate $EndDate `
                    -FullHighVolumeCollection $FullHighVolumeCollection
            }

            if ($SelectedBrowsers -contains 'Brave') {
                Collect-ChromiumBrowser `
                    -BrowserLabel 'Brave' `
                    -UserName $userName `
                    -BasePath (Join-Path $profilePath 'AppData\Local\BraveSoftware\Brave-Browser\User Data') `
                    -StartDate $StartDate `
                    -EndDate $EndDate `
                    -FullHighVolumeCollection $FullHighVolumeCollection
            }

            if ($SelectedBrowsers -contains 'Opera') {
                $operaRoot = Join-Path $profilePath 'AppData\Roaming\Opera Software'
                $operaBases = Get-OperaProfileBasePaths -OperaRoot $operaRoot

                foreach ($operaBase in $operaBases) {
                    Collect-ChromiumBrowser `
                        -BrowserLabel 'Opera' `
                        -UserName ('{0}_{1}' -f $userName, $operaBase.Label) `
                        -BasePath $operaBase.BasePath `
                        -StartDate $StartDate `
                        -EndDate $EndDate `
                        -FullHighVolumeCollection $FullHighVolumeCollection
                }
            }

            if ($SelectedBrowsers -contains 'Firefox') {
                Collect-Firefox `
                    -UserName $userName `
                    -ProfilesPath (Join-Path $profilePath 'AppData\Roaming\Mozilla\Firefox\Profiles') `
                    -StartDate $StartDate `
                    -EndDate $EndDate `
                    -FullHighVolumeCollection $FullHighVolumeCollection
            }
        }

        # System artifacts
        $systemDir = Join-Path $script:CaseFolder 'System'
        Initialize-Directory -Path $systemDir

        Collect-DNSCache -OutputFile (Join-Path $systemDir 'dns_cache.txt')
        Collect-Prefetch -DestinationDir (Join-Path $systemDir 'Prefetch')

        # Reports
        $googleFormsCsv = Join-Path $script:CaseFolder 'GoogleForms_Indicator_Hits.csv'
        $timelineCsv    = Join-Path $script:CaseFolder 'Timeline_Reconstructed.csv'
        $manifestCsv    = Join-Path $script:CaseFolder 'manifest.csv'
        $hashesCsv      = Join-Path $script:CaseFolder 'hashes.csv'
        $summaryTxt     = Join-Path $script:CaseFolder 'collection_summary.txt'

        Detect-GoogleFormsIndicators -RootPath $script:CaseFolder -OutputCsv $googleFormsCsv
        Build-Timeline -RootPath $script:CaseFolder -OutputCsv $timelineCsv
        Export-Manifest -RootPath $script:CaseFolder -OutputCsv $manifestCsv

        Export-Hashes -RootPath $script:CaseFolder -OutputCsv $hashesCsv -ExcludePaths @(
            $hashesCsv,
            $timelineCsv,
            $manifestCsv,
            $script:LogFile,
            $summaryTxt
        )

        Export-CollectionSummary `
            -OutputFile $summaryTxt `
            -SelectedBrowsers $SelectedBrowsers `
            -CurrentUserOnly $CurrentUserOnly `
            -StartDate $StartDate `
            -EndDate $EndDate `
            -FullHighVolumeCollection $FullHighVolumeCollection `
            -CreateZip $CreateZip

        $zipPath = $null
        if ($CreateZip) {
            $zipPath = Create-ZipPackage -SourceFolder $script:CaseFolder
        }

        Write-Log 'Collection completed successfully.'

        $message = if ($zipPath) {
            "Collection finished successfully.`r`n`r`nOutput Folder:`r`n$($script:CaseFolder)`r`n`r`nZIP Package:`r`n$zipPath"
        }
        else {
            "Collection finished successfully.`r`n`r`nOutput Folder:`r`n$($script:CaseFolder)"
        }

        Show-InfoMessage -Message $message
    }
    catch {
        if ($script:LogFile) {
            Write-Log "Fatal error: $($_.Exception.Message)" 'ERROR'
        }

        Show-ErrorMessage -Message ("Collection failed.`r`n`r`n{0}" -f $_.Exception.Message)
    }
}

# ------------------------------------------------------------
# GUI
# ------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Browser Field Triage Collector v3.5'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(760, 620)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.TopMost = $false

# Layout helpers
$leftLabel = 20
$leftInput = 210
$top = 20
$lineH = 30
$groupW = 700

# Title
$labelTitle = New-Object System.Windows.Forms.Label
$labelTitle.Text = 'Browser Field Triage Collector'
$labelTitle.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
$labelTitle.Location = New-Object System.Drawing.Point(20, 15)
$labelTitle.Size = New-Object System.Drawing.Size(420, 28)
$form.Controls.Add($labelTitle)

# Browser group
$groupBrowsers = New-Object System.Windows.Forms.GroupBox
$groupBrowsers.Text = 'Browser Selection'
$groupBrowsers.Location = New-Object System.Drawing.Point(20, 55)
$groupBrowsers.Size = New-Object System.Drawing.Size($groupW, 90)
$form.Controls.Add($groupBrowsers)

$cbChrome = New-Object System.Windows.Forms.CheckBox
$cbChrome.Text = 'Chrome'
$cbChrome.Location = New-Object System.Drawing.Point(20, 30)
$cbChrome.Size = New-Object System.Drawing.Size(100, 24)
$cbChrome.Checked = $true
$groupBrowsers.Controls.Add($cbChrome)

$cbEdge = New-Object System.Windows.Forms.CheckBox
$cbEdge.Text = 'Edge'
$cbEdge.Location = New-Object System.Drawing.Point(130, 30)
$cbEdge.Size = New-Object System.Drawing.Size(100, 24)
$groupBrowsers.Controls.Add($cbEdge)

$cbFirefox = New-Object System.Windows.Forms.CheckBox
$cbFirefox.Text = 'Firefox'
$cbFirefox.Location = New-Object System.Drawing.Point(240, 30)
$cbFirefox.Size = New-Object System.Drawing.Size(100, 24)
$groupBrowsers.Controls.Add($cbFirefox)

$cbBrave = New-Object System.Windows.Forms.CheckBox
$cbBrave.Text = 'Brave'
$cbBrave.Location = New-Object System.Drawing.Point(350, 30)
$cbBrave.Size = New-Object System.Drawing.Size(100, 24)
$groupBrowsers.Controls.Add($cbBrave)

$cbOpera = New-Object System.Windows.Forms.CheckBox
$cbOpera.Text = 'Opera'
$cbOpera.Location = New-Object System.Drawing.Point(460, 30)
$cbOpera.Size = New-Object System.Drawing.Size(100, 24)
$groupBrowsers.Controls.Add($cbOpera)

# Scope group
$groupScope = New-Object System.Windows.Forms.GroupBox
$groupScope.Text = 'User Scope'
$groupScope.Location = New-Object System.Drawing.Point(20, 155)
$groupScope.Size = New-Object System.Drawing.Size($groupW, 70)
$form.Controls.Add($groupScope)

$rbCurrentUser = New-Object System.Windows.Forms.RadioButton
$rbCurrentUser.Text = 'Current user only'
$rbCurrentUser.Location = New-Object System.Drawing.Point(20, 28)
$rbCurrentUser.Size = New-Object System.Drawing.Size(150, 24)
$rbCurrentUser.Checked = $true
$groupScope.Controls.Add($rbCurrentUser)

$rbAllUsers = New-Object System.Windows.Forms.RadioButton
$rbAllUsers.Text = 'All local user profiles'
$rbAllUsers.Location = New-Object System.Drawing.Point(220, 28)
$rbAllUsers.Size = New-Object System.Drawing.Size(170, 24)
$groupScope.Controls.Add($rbAllUsers)

# Date/time group
$groupRange = New-Object System.Windows.Forms.GroupBox
$groupRange.Text = 'Date and Time Range'
$groupRange.Location = New-Object System.Drawing.Point(20, 235)
$groupRange.Size = New-Object System.Drawing.Size($groupW, 115)
$form.Controls.Add($groupRange)

$labelStart = New-Object System.Windows.Forms.Label
$labelStart.Text = 'Start Date/Time'
$labelStart.Location = New-Object System.Drawing.Point(20, 30)
$labelStart.Size = New-Object System.Drawing.Size(140, 24)
$groupRange.Controls.Add($labelStart)

$pickerStart = New-Object System.Windows.Forms.DateTimePicker
$pickerStart.Location = New-Object System.Drawing.Point(180, 26)
$pickerStart.Size = New-Object System.Drawing.Size(240, 24)
$pickerStart.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$pickerStart.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$pickerStart.Value = (Get-Date).AddDays(-2)
$groupRange.Controls.Add($pickerStart)

$labelEnd = New-Object System.Windows.Forms.Label
$labelEnd.Text = 'End Date/Time'
$labelEnd.Location = New-Object System.Drawing.Point(20, 66)
$labelEnd.Size = New-Object System.Drawing.Size(140, 24)
$groupRange.Controls.Add($labelEnd)

$pickerEnd = New-Object System.Windows.Forms.DateTimePicker
$pickerEnd.Location = New-Object System.Drawing.Point(180, 62)
$pickerEnd.Size = New-Object System.Drawing.Size(240, 24)
$pickerEnd.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$pickerEnd.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$pickerEnd.Value = Get-Date
$groupRange.Controls.Add($pickerEnd)

# Collection mode
$groupMode = New-Object System.Windows.Forms.GroupBox
$groupMode.Text = 'Collection Mode'
$groupMode.Location = New-Object System.Drawing.Point(20, 360)
$groupMode.Size = New-Object System.Drawing.Size($groupW, 95)
$form.Controls.Add($groupMode)

$rbDateFiltered = New-Object System.Windows.Forms.RadioButton
$rbDateFiltered.Text = 'Date-filter high-volume directories'
$rbDateFiltered.Location = New-Object System.Drawing.Point(20, 25)
$rbDateFiltered.Size = New-Object System.Drawing.Size(250, 24)
$rbDateFiltered.Checked = $true
$groupMode.Controls.Add($rbDateFiltered)

$rbFullHighVolume = New-Object System.Windows.Forms.RadioButton
$rbFullHighVolume.Text = 'Full copy of high-volume directories'
$rbFullHighVolume.Location = New-Object System.Drawing.Point(20, 55)
$rbFullHighVolume.Size = New-Object System.Drawing.Size(260, 24)
$groupMode.Controls.Add($rbFullHighVolume)

# Options
$groupOptions = New-Object System.Windows.Forms.GroupBox
$groupOptions.Text = 'Options'
$groupOptions.Location = New-Object System.Drawing.Point(20, 465)
$groupOptions.Size = New-Object System.Drawing.Size($groupW, 65)
$form.Controls.Add($groupOptions)

$cbZip = New-Object System.Windows.Forms.CheckBox
$cbZip.Text = 'Create ZIP package after collection'
$cbZip.Location = New-Object System.Drawing.Point(20, 28)
$cbZip.Size = New-Object System.Drawing.Size(250, 24)
$cbZip.Checked = $true
$groupOptions.Controls.Add($cbZip)

# Info label
$labelInfo = New-Object System.Windows.Forms.Label
$labelInfo.Text = 'Output folder will be created under C:\ as BrowserTriage_yyyyMMdd_HHmmss'
$labelInfo.Location = New-Object System.Drawing.Point(20, 515)
$labelInfo.Size = New-Object System.Drawing.Size(500, 18)
$form.Controls.Add($labelInfo)

# Buttons
$buttonRun = New-Object System.Windows.Forms.Button
$buttonRun.Text = 'Start Collection'
$buttonRun.Location = New-Object System.Drawing.Point(420, 540)
$buttonRun.Size = New-Object System.Drawing.Size(140, 32)
$form.Controls.Add($buttonRun)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Text = 'Close'
$buttonClose.Location = New-Object System.Drawing.Point(580, 540)
$buttonClose.Size = New-Object System.Drawing.Size(140, 32)
$buttonClose.Add_Click({ $form.Close() })
$form.Controls.Add($buttonClose)

$buttonRun.Add_Click({
    $buttonRun.Enabled = $false
    try {
        $selectedBrowsers = New-Object System.Collections.Generic.List[string]
        if ($cbChrome.Checked)  { $selectedBrowsers.Add('Chrome') }
        if ($cbEdge.Checked)    { $selectedBrowsers.Add('Edge') }
        if ($cbFirefox.Checked) { $selectedBrowsers.Add('Firefox') }
        if ($cbBrave.Checked)   { $selectedBrowsers.Add('Brave') }
        if ($cbOpera.Checked)   { $selectedBrowsers.Add('Opera') }

        if ($selectedBrowsers.Count -eq 0) {
            Show-WarningMessage -Message 'Select at least one browser.'
            return
        }

        if ($pickerEnd.Value -lt $pickerStart.Value) {
            Show-WarningMessage -Message 'End Date/Time must be greater than or equal to Start Date/Time.'
            return
        }

        $scopeCurrentUserOnly = $rbCurrentUser.Checked
        $fullHighVolume = $rbFullHighVolume.Checked
        $createZip = $cbZip.Checked

        Start-Collection `
            -SelectedBrowsers $selectedBrowsers.ToArray() `
            -CurrentUserOnly $scopeCurrentUserOnly `
            -StartDate $pickerStart.Value `
            -EndDate $pickerEnd.Value `
            -FullHighVolumeCollection $fullHighVolume `
            -CreateZip $createZip
    }
    finally {
        $buttonRun.Enabled = $true
    }
})

[void]$form.ShowDialog()

# End of script
