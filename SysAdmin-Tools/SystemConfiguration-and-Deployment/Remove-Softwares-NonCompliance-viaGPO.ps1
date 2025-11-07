<#
.SYNOPSIS
    Script to remove obsolete or non-compliant software packages installed on workstations.

.DESCRIPTION
    This script scans for and removes obsolete or non-compliant software from workstations.
    It reads uninstall entries from the registry and, if the DisplayName matches a predefined list,
    the script performs a silent uninstall when possible.
    For specific software such as LibreOffice, the script performs extra version checks
    to determine whether removal is required.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy
    
.VERSION
    Last update: 11/07/2025
#>

[CmdletBinding()]
param(
    [string[]]$SoftwareNames = @(
        # Adware & PUAs
        "Amazon Music","CCleaner","Glary Utilities","Driver Booster","Reimage Repair","SlimCleaner","glpi agent 1.11",
        "Advanced SystemCare","Unchecky","Ask Toolbar","Yahoo Toolbar","Bing Toolbar","WebDiscover Browser",

        # Unauthorized browsers & extensions
        "Perplexity AI Comet","perplexity.ai/comet",
        "OpenAI Atlas Browser","openai atlas",
        "Comet Browser","Atlas Browser",

        # Games & Entertainment
        "Bubble Witch","Candy Crush","Checkers Deluxe","Circle Empires","Crosswords","Gardenscapes",
        "Damas Pro","Souldiers","Solitaire","Among Us","Minecraft","Fortnite","League of Legends",
        "Roblox","World of Warcraft","Genshin Impact","PUBG","StarCraft","SupremaPoker","GGPoker","Wandering",

        # Streaming & Media
        "Deezer","Spotify","Disney","Netflix","Prime Video","Hulu","Vudu","Crackle","HBO Max",
        "Crunchyroll","Groove Music","TikTok","Kodi","Plex",

        # VPNs, Proxies & File Sharing
        "Hotspot","Infatica","OpenVPN","WireGuard","ZeroTier","uTorrent","BitTorrent","FrostWire",
        "eMule","Shareaza","Ares Galaxy","LimeWire","Psiphon","Hotspot Shield","ProtonVPN","ExpressVPN",
        "Surfshark","NordVPN","Private Internet Access",

        # Hacking / Unauthorized Tools
        "Cheat Engine","Cain & Abel","John the Ripper","Hydra","Aircrack-ng",

        # Conflicting Antivirus / Security
        "avast","avg","McAfee","Avira","Trend Micro","Comodo Antivirus","ESET NOD32",

        # Unauthorized / Obsolete Office Software
        "broffice"
    ),
    [string]$LogDir = 'C:\Scripts-LOGS'
)

# =====================================================================
# General settings (GPO – Machine): no prompts, no UI, no pauses
# =====================================================================
$ErrorActionPreference = 'Continue'
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
if ([string]::IsNullOrWhiteSpace($scriptName)) { $scriptName = 'Remove-NonComplianceSoftware' }

try {
    if (-not (Test-Path -LiteralPath $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
} catch {
    $LogDir = Join-Path $env:SystemRoot 'Temp'
}
$logFile = Join-Path $LogDir ("{0}.log" -f $scriptName)

# ===================== Logging =====================
function Log-Message {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARNING','ERROR','DEBUG')]
        [string]$Level = 'INFO'
    )
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $entry = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message
    try {
        Add-Content -Path $logFile -Value $entry -Encoding UTF8
    } catch {
        try { [System.IO.File]::AppendAllText($logFile, $entry + [Environment]::NewLine) } catch { }
    }
    if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
        Write-Verbose $entry
    }
}

# ===================== Utilities =====================
function Get-NormalizedVersion {
    [CmdletBinding()]
    param([string]$VersionString)
    if ([string]::IsNullOrWhiteSpace($VersionString)) { return $null }
    $m = [regex]::Match($VersionString, '\d+(\.\d+){0,3}')
    if ($m.Success) { try { return [Version]$m.Value } catch { return $null } }
    return $null
}

function Split-UninstallString {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$UninstallString)
    $u = $UninstallString.Trim()
    if     ($u -match '^\s*"(.*?)"\s*(.*)$') { return [pscustomobject]@{ Executable=$matches[1]; Arguments=$matches[2].Trim() } }
    elseif ($u -match '^\s*([^\s]+)\s*(.*)$') { return [pscustomobject]@{ Executable=$matches[1]; Arguments=$matches[2].Trim() } }
    else { return [pscustomobject]@{ Executable=$u; Arguments='' } }
}

function Invoke-CommandWithTimeout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$CommandLine,[int]$TimeoutSec=300)
    try {
        $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $CommandLine" -WindowStyle Hidden -PassThru
        if (-not $proc.WaitForExit($TimeoutSec * 1000)) { try { $proc.Kill() } catch { } ; return @{ ExitCode=-1; TimedOut=$true } }
        return @{ ExitCode=[int]$proc.ExitCode; TimedOut=$false }
    } catch { return @{ ExitCode=-2; TimedOut=$false } }
}

# ---------- Silent EXE auto-detection + MSI support ----------
function Get-WorkingSilentUninstallCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$UninstallString)

    $un = Split-UninstallString -UninstallString $UninstallString
    $exe = $un.Executable
    $baseArgs = $un.Arguments

    if ($exe -match '(?i)msiexec(\.exe)?$') {
        if ($UninstallString -match '(\{[0-9A-Fa-f\-]{36}\})') {
            $guid = $matches[1]
            return [pscustomobject]@{ Command="msiexec.exe /x $guid /qn /norestart"; ParmsUsed="/x $guid /qn /norestart"; IsMSI=$true; Executed=$false }
        } else {
            $cmd = $UninstallString
            if ($cmd -notmatch '(?i)/q')      { $cmd += ' /qn' }
            if ($cmd -notmatch '(?i)restart') { $cmd += ' /norestart' }
            return [pscustomobject]@{ Command=$cmd; ParmsUsed=($cmd -replace '(?i)^.*?msiexec(\.exe)?\s*',''); IsMSI=$true; Executed=$false }
        }
    }

    $candidates = @(
        "$baseArgs /quiet /norestart",
        "$baseArgs /silent /norestart",
        "$baseArgs /VERYSILENT /SUPPRESSMSGBOXES /NORESTART",
        "$baseArgs /S /NORESTART",
        "$baseArgs /SILENT /NORESTART",
        "$baseArgs /uninstall /quiet /norestart",
        "$baseArgs /remove /quiet /norestart"
    )

    foreach ($args in $candidates) {
        $cmd = "`"$exe`" $args".Trim()
        $r = Invoke-CommandWithTimeout -CommandLine $cmd -TimeoutSec 300
        if (-not $r.TimedOut -and ($r.ExitCode -eq 0 -or $r.ExitCode -eq 3010 -or $r.ExitCode -eq 1641)) {
            return [pscustomobject]@{ Command=$cmd; ParmsUsed=($args -replace '^\s+',''); IsMSI=$false; Executed=$true }
        }
    }
    return $null
}

function Get-MSIProductCodeFromDisplayName {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$DisplayName)
    $paths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($rp in $paths) {
        try {
            $items = Get-ChildItem -Path $rp -ErrorAction SilentlyContinue
            foreach ($it in $items) {
                try {
                    $props = Get-ItemProperty -Path $it.PSPath -ErrorAction SilentlyContinue
                    if ($props -and $props.DisplayName -and ($props.DisplayName -eq $DisplayName)) {
                        $leaf = $it.PSChildName
                        if ($leaf -match '^\{[0-9A-Fa-f\-]{36}\}$') { return $leaf }
                        if ($props.UninstallString -match '(\{[0-9A-Fa-f\-]{36}\})') { return $matches[1] }
                    }
                } catch {}
            }
        } catch {}
    }
    return $null
}

# --------- Cleanup Helpers ---------
function Remove-ItemSafe {
    param([Parameter(Mandatory=$true)][string]$Path)
    try {
        if (Test-Path -LiteralPath $Path) {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $Path)) { Log-Message "Removed: $Path" }
            else { Log-Message "Unable to remove: $Path" "WARNING" }
        }
    } catch { Log-Message "Error removing '$Path': $_" "ERROR" }
}

function Remove-RegistryKeySafe {
    param([Parameter(Mandatory=$true)][string]$KeyPath)
    try {
        if (Test-Path -LiteralPath $KeyPath) {
            Remove-Item -LiteralPath $KeyPath -Recurse -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $KeyPath)) { Log-Message "Registry key removed: $KeyPath" }
            else { Log-Message "Unable to remove registry key: $KeyPath" "WARNING" }
        }
    } catch { Log-Message "Error removing registry key '$KeyPath': $_" "ERROR" }
}

function Stop-ProcessesUnderFolder {
    param([Parameter(Mandatory=$true)][string]$FolderPath)
    if ([string]::IsNullOrWhiteSpace($FolderPath)) { return }
    if (-not (Test-Path -LiteralPath $FolderPath)) { return }
    try {
        Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.Path -and ($_.Path -like ("{0}*" -f ($FolderPath.TrimEnd('\') + '\')))
        } | ForEach-Object {
            try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } catch { }
        }
    } catch {}
}

function Force-UninstallExe {
    <#
        Forced uninstall mode when no silent parameter works.
        Tries generic uninstall switches (/uninstall, /remove, /S, /quiet etc.).
        Returns process exit code.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$UninstallString)

    $un = Split-UninstallString -UninstallString $UninstallString
    $exe = $un.Executable
    $args = $un.Arguments

    $candidates = @(
        "$exe /uninstall /quiet /norestart",
        "$exe /remove /quiet /norestart",
        "$exe /uninstall /S /NORESTART",
        "$exe /remove /S /NORESTART",
        "$exe /S /NORESTART",
        "$exe /silent /norestart",
        "$exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART"
    )

    foreach ($cmd in $candidates) {
        $r = Invoke-CommandWithTimeout -CommandLine $cmd -TimeoutSec 300
        if (-not $r.TimedOut -and $r.ExitCode -ne -2) {
            return $r.ExitCode
        }
    }
    return 1
}

function Invoke-HardCleanup {
    <#
        Full cleanup for software that failed every removal method.
        Created for "Glary Utilities", but generic enough for other cases.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$DisplayName,
        [Parameter(Mandatory=$true)][string]$UninstallString
    )

    Log-Message "Applying full cleanup for '$DisplayName' (direct file/registry removal)."

    # 1) Locate installation folders
    $un = Split-UninstallString -UninstallString $UninstallString
    $exePath = $un.Executable
    $candidates = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)

    if ($exePath -and (Test-Path -LiteralPath $exePath)) {
        $dir = Split-Path -Path $exePath -Parent
        if ($dir) { [void]$candidates.Add($dir) }
    }

    # Standard Glary folders (x64 / x86)
    $pf  = ${env:ProgramFiles}
    $pf86 = ${env:ProgramFiles(x86)}
    if ($pf)  { Get-ChildItem -LiteralPath $pf  -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "Glary Utilities*" } | ForEach-Object { [void]$candidates.Add($_.FullName) } }
    if ($pf86){ Get-ChildItem -LiteralPath $pf86 -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "Glary Utilities*" } | ForEach-Object { [void]$candidates.Add($_.FullName) } }

    # 2) Kill processes running from inside those folders
    foreach ($p in $candidates) { Stop-ProcessesUnderFolder -FolderPath $p }

    # 3) Remove services
    try {
        Get-Service -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match '(?i)glary|guser|guservice' -or $_.DisplayName -match '(?i)glary'
        } | ForEach-Object {
            try {
                if ($_.Status -ne 'Stopped') { Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue }
                sc.exe delete $_.Name | Out-Null
                Log-Message "Service removed: $($_.Name)"
            } catch { Log-Message "Failed to remove service $($_.Name): $_" "WARNING" }
        }
    } catch {}

    # 4) Remove scheduled tasks
    try {
        $tasks = schtasks.exe /Query /FO LIST /V | Out-String
        $blocks = $tasks -split "(`r`n){2,}"
        foreach ($blk in $blocks) {
            if ($blk -match '(?i)glary') {
                if ($blk -match 'TaskName:\s+(.+)$') {
                    $tn = $matches[1].Trim()
                    try { schtasks.exe /Delete /TN "$tn" /F | Out-Null ; Log-Message "Scheduled task removed: $tn" } catch {}
                }
            }
        }
    } catch {}

    # 5) Remove shortcuts (Start Menu / Public Desktop)
    $progData = $env:ProgramData
    $public = "$env:Public\Desktop"
    $lnkTargets = @(
        Join-Path $progData 'Microsoft\Windows\Start Menu\Programs'
        $public
    )
    foreach ($base in $lnkTargets) {
        try {
            if (Test-Path -LiteralPath $base) {
                Get-ChildItem -LiteralPath $base -Recurse -ErrorAction SilentlyContinue | Where-Object {
                    $_.Name -like '*Glary*'
                } | ForEach-Object { Remove-ItemSafe -Path $_.FullName }
            }
        } catch {}
    }

    # 6) Remove startup entries
    $runKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )
    foreach ($rk in $runKeys) {
        try {
            if (Test-Path -LiteralPath $rk) {
                Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue | ForEach-Object {
                    $_.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' -and [string]($_.Value) -match '(?i)glary' } | ForEach-Object {
                        try { Remove-ItemProperty -Path $rk -Name $_.Name -Force -ErrorAction SilentlyContinue ; Log-Message "Removed RUN entry: $rk\$($_.Name)" } catch {}
                    }
                }
            }
        } catch {}
    }

    # 7) Remove uninstall keys
    $uninstallRoots = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $uninstallRoots) {
        try {
            Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $p = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
                    if ($p -and $p.DisplayName -and ($p.DisplayName -like "*Glary*")) {
                        Remove-RegistryKeySafe -KeyPath $_.PSPath
                    }
                } catch {}
            }
        } catch {}
    }

    # 8) Remove folders (full wipe – option A)
    foreach ($p in $candidates) { Remove-ItemSafe -Path $p }

    # 9) Remove common leftovers
    $residuals = @(
        Join-Path $env:ProgramData 'Glary*'
    )
    foreach ($r in $residuals) {
        Get-ChildItem -Path $r -ErrorAction SilentlyContinue | ForEach-Object { Remove-ItemSafe -Path $_.FullName }
    }

    Log-Message "Full cleanup completed for '$DisplayName'."
}

# ===================== Uninstall Handler =====================
function Invoke-Uninstall {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Software)

    $displayName     = $Software.DisplayName
    $uninstallString = $Software.UninstallString

    if ([string]::IsNullOrWhiteSpace($displayName)) { Log-Message "Registry entry without DisplayName skipped." "DEBUG"; return }
    if ([string]::IsNullOrWhiteSpace($uninstallString)) { Log-Message "No uninstall string found for '$displayName'." "WARNING"; return }

    # 1) Silent EXE or MSI uninstall
    $work = Get-WorkingSilentUninstallCommand -UninstallString $uninstallString
    if ($work -ne $null) {
        if ($work.IsMSI) {
            $r = Invoke-CommandWithTimeout -CommandLine $work.Command -TimeoutSec 600
            Log-Message "Uninstall of '$displayName' returned code: $($r.ExitCode)"
            if ($r.ExitCode -eq 0 -or $r.ExitCode -eq 3010 -or $r.ExitCode -eq 1641) { return }
        } else {
            Log-Message "Silent parameter detected for '$displayName': $($work.ParmsUsed)"
            $postExit = 0
            $stillThere = $false
            try {
                $paths = @(
                    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
                    'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
                )
                foreach ($rp in $paths) {
                    $stillThere = ($null -ne (Get-ChildItem $rp -ErrorAction SilentlyContinue | ForEach-Object {
                        try { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue) } catch { $null }
                    } | Where-Object { $_.DisplayName -eq $displayName }))
                    if ($stillThere) { break }
                }
            } catch {}
            if ($stillThere) {
                $r = Invoke-CommandWithTimeout -CommandLine $work.Command -TimeoutSec 300
                $postExit = $r.ExitCode
            }
            Log-Message "Uninstall of '$displayName' returned code: $postExit"
            if (-not $stillThere -or $postExit -eq 0 -or $postExit -eq 3010 -or $postExit -eq 1641) { return }
        }
    }

    # 2) Hidden MSI GUID (HKLM)
    $guid = Get-MSIProductCodeFromDisplayName -DisplayName $displayName
    if ($guid) {
        Log-Message "MSI GUID detected for '$displayName': $guid"
        $msiCmd = "msiexec.exe /x $guid /qn /norestart"
        $r = Invoke-CommandWithTimeout -CommandLine $msiCmd -TimeoutSec 600
        Log-Message "Uninstall of '$displayName' returned code: $($r.ExitCode)"
        if ($r.ExitCode -eq 0 -or $r.ExitCode -eq 3010 -or $r.ExitCode -eq 1641) { return }
    }

    # 3) Forced uninstall
    Log-Message "No valid silent parameter for '$displayName'. Starting forced mode." "WARNING"
    $forceExit = 0 + (Force-UninstallExe -UninstallString $uninstallString)
    if ($forceExit -eq 0 -or $forceExit -eq 3010 -or $forceExit -eq 1641) {
        Log-Message "Forced mode completed for '$displayName' (exit: $forceExit)."
        return
    } else {
        Log-Message "Forced mode failed for '$displayName' (exit: $forceExit)." "ERROR"
    }

    # 4) Full wipe
    Invoke-HardCleanup -DisplayName $displayName -UninstallString $uninstallString
}

# ===================== Main Logic =====================
function Remove-NonComplianceSoftware {
    [CmdletBinding()]
    param()

    Log-Message "Starting scan and removal of obsolete / non-compliant software."
    $registryPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($regPath in $registryPaths) {
        try {
            $items = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                try {
                    $software = Get-ItemProperty -Path $item.PSPath -ErrorAction SilentlyContinue
                    if (-not $software) { continue }
                    $displayName = $software.DisplayName
                    if ([string]::IsNullOrWhiteSpace($displayName)) { continue }

                    $matched = $false

                    foreach ($name in $SoftwareNames) {
                        if (-not [string]::IsNullOrWhiteSpace($name) -and $displayName -like "*$name*") {
                            Log-Message "Software flagged for removal (list match): '$displayName'."
                            Invoke-Uninstall -Software $software
                            $matched = $true
                            break
                        }
                    }
                    if ($matched) { continue }

                    if ($displayName -like "*libreoffice*") {
                        $ver = Get-NormalizedVersion -VersionString $software.DisplayVersion
                        if ($ver -and $ver.Major -lt 24) {
                            Log-Message "LibreOffice detected: '$displayName' version '$($software.DisplayVersion)'. Version < 24 -> uninstalling."
                            Invoke-Uninstall -Software $software
                            continue
                        } else {
                            Log-Message "LibreOffice '$displayName' version '$($software.DisplayVersion)' (>= 24) will not be removed."
                        }
                    }
                } catch {
                    Log-Message "Error processing registry entry: $($item.PSPath). Details: $_" "ERROR"
                }
            }
        } catch {
            Log-Message "Error accessing registry path: $regPath. Details: $_" "ERROR"
        }
    }
    Log-Message "Removal of obsolete and non-compliant software completed."
}

# ===================== Execution (GPO – Machine) =====================
Log-Message "Script execution started."
try {
    Remove-NonComplianceSoftware -Verbose:$false
} catch {
    Log-Message "Unhandled exception during main execution: $_" "ERROR"
}
Log-Message "Script execution finished."

# End of script
