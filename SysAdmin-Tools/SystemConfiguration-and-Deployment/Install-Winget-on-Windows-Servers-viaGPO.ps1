<#
.SYNOPSIS
  Idempotent WinGet bootstrap for Windows Server 2019 (17763+) with parser-safe PowerShell 5.1 syntax.

.DESCRIPTION
  Designed for Server 2019 domain / GPO startup scenarios where:
    - DesktopAppInstaller may install but no usable winget command appears.
    - WindowsApps packaged winget.exe is not directly runnable.
    - Portable extraction can work only when the correct payload folder is copied.

  Strategy:
    1) If an already deployed portable winget works, exit success.
    2) Best-effort prerequisites:
         - Enable AppX sideloading policies
         - Microsoft.VCLibs.x64.14.00.Desktop
         - Microsoft.UI.Xaml 2.8 x64
         - Windows App Runtime 1.8 installer
    3) Try Microsoft.WinGet.Client bootstrap (when PSGallery is reachable).
    4) Try DesktopAppInstaller Add-AppxPackage (best effort).
    5) Fallback to portable payload extraction from pinned MSIXBUNDLE releases:
         - Extract bundle
         - Pick x64 MSIX
         - Find winget.exe candidates
         - Rank by sibling DLL count and total folder size
         - Deploy candidate parent folder to C:\Program Files\winget
         - Validate by running winget --version
         - Roll back automatically on failure

  Notes:
    - No size-based "stub" rejection. A ~23 KB winget.exe can still be valid if the full payload beside it is correct.
    - Uses only PowerShell 5.1-safe syntax.
    - File-only logging.

.AUTHOR
  Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
  2026-03-05 (v3)
#>

[CmdletBinding()]
param(
    [string]$LogDir = "C:\Logs-TEMP",
    [string]$SetupRoot = "C:\ProgramData\WinGet-Setup",
    [string]$PortableDir = "C:\Program Files\winget",
    [switch]$StrictPrereqs,
    [string[]]$CandidateReleases = @(
        "v1.11.180-preview",
        "v1.11.230-preview",
        "latest"
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$VerbosePreference = "SilentlyContinue"

function Get-ScriptBaseName {
    try {
        if ($PSCommandPath) { return [IO.Path]::GetFileNameWithoutExtension($PSCommandPath) }
    } catch {}
    try {
        if ($MyInvocation.MyCommand.Path) { return [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Path) }
    } catch {}
    try {
        if ($MyInvocation.MyCommand.Name) { return [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name) }
    } catch {}
    return "new-winget-install-servers"
}

function Ensure-Directory {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

$scriptBase = Get-ScriptBaseName
Ensure-Directory -Path $LogDir
$script:LogPath = Join-Path $LogDir ($scriptBase + ".log")

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO","WARNING","ERROR")][string]$Level = "INFO"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[{0}] [{1}] {2}" -f $Level, $ts, $Message
    try { Add-Content -Path $script:LogPath -Value $line -Encoding UTF8 -ErrorAction Stop } catch {}
}

Write-Log -Message ("Log initialized: {0}" -f $script:LogPath)

function Test-IsAdmin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Enable-Tls12 {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
}

function Download-File {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$OutFile
    )
    Ensure-Directory -Path (Split-Path $OutFile -Parent)
    if (Test-Path -LiteralPath $OutFile) {
        $len = (Get-Item -LiteralPath $OutFile).Length
        if ($len -gt 1024) {
            Write-Log -Message ("Found existing download: {0} ({1} bytes)" -f $OutFile, $len)
            return $true
        }
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
    }

    Write-Log -Message ("Downloading: {0} -> {1}" -f $Url, $OutFile)
    Enable-Tls12
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
        $len2 = (Get-Item -LiteralPath $OutFile).Length
        Write-Log -Message ("Download OK. Size: {0} bytes." -f $len2)
        return $true
    } catch {
        Write-Log -Message ("Download failed: {0}" -f $_.Exception.Message) -Level "WARNING"
        return $false
    }
}

function Invoke-Native {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSec = 60
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = ($Arguments -join " ")
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()

    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch {}
        return [PSCustomObject]@{
            ExitCode = 1460
            StdOut   = ""
            StdErr   = "Timed out"
        }
    }

    return [PSCustomObject]@{
        ExitCode = $p.ExitCode
        StdOut   = ($p.StandardOutput.ReadToEnd()).Trim()
        StdErr   = ($p.StandardError.ReadToEnd()).Trim()
    }
}

function Get-WinGetFromPath {
    try {
        $cmd = Get-Command winget.exe -ErrorAction Stop
        return $cmd.Source
    } catch {
        return $null
    }
}

function Test-WinGetFunctional {
    param([Parameter(Mandatory=$true)][string]$WingetPath)
    if (-not (Test-Path -LiteralPath $WingetPath)) { return $false }

    $r = Invoke-Native -FilePath $WingetPath -Arguments @("--version") -TimeoutSec 20
    if ($r.ExitCode -eq 0 -and $r.StdOut) {
        Write-Log -Message ("winget functional: {0} :: {1}" -f $WingetPath, $r.StdOut)
        return $true
    }

    Write-Log -Message ("winget test failed. ExitCode={0} StdOut='{1}' StdErr='{2}'" -f $r.ExitCode, $r.StdOut, $r.StdErr) -Level "WARNING"
    return $false
}

function Ensure-InMachinePath {
    param([Parameter(Mandatory=$true)][string]$Dir)
    $mp = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine)
    $parts = @($mp -split ';' | Where-Object { $_ -and $_.Trim() })
    if ($parts -contains $Dir) {
        Write-Log -Message ("Already in PATH (Machine): {0}" -f $Dir)
    } else {
        $new = ($parts + $Dir) -join ';'
        [Environment]::SetEnvironmentVariable("Path", $new, [EnvironmentVariableTarget]::Machine)
        Write-Log -Message ("Added to PATH (Machine): {0}" -f $Dir)
    }
    $env:Path = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine)
}

function Expand-ZipLike {
    param(
        [Parameter(Mandatory=$true)][string]$PackagePath,
        [Parameter(Mandatory=$true)][string]$DestDir
    )
    if (Test-Path -LiteralPath $DestDir) {
        Remove-Item -LiteralPath $DestDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Ensure-Directory -Path $DestDir

    $tmpZip = Join-Path $SetupRoot ([IO.Path]::GetRandomFileName() + ".zip")
    Copy-Item -LiteralPath $PackagePath -Destination $tmpZip -Force
    Expand-Archive -Path $tmpZip -DestinationPath $DestDir -Force
    Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue
}

function Set-AppxPolicies {
    try {
        $k = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx"
        if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
        New-ItemProperty -Path $k -Name "AllowAllTrustedApps" -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $k -Name "AllowDevelopmentWithoutDevLicense" -Value 1 -PropertyType DWord -Force | Out-Null
        Write-Log -Message "Ensured AppX policy: AllowAllTrustedApps=1, AllowDevelopmentWithoutDevLicense=1"
        return $true
    } catch {
        Write-Log -Message ("Failed setting AppX policy: {0}" -f $_.Exception.Message) -Level "WARNING"
        return $false
    }
}

function Try-AddAppx {
    param([Parameter(Mandatory=$true)][string]$PackagePath)
    try {
        Add-AppxPackage -Path $PackagePath -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Log -Message ("Add-AppxPackage failed for {0}: {1}" -f $PackagePath, $_.Exception.Message) -Level "WARNING"
        return $false
    }
}

function Ensure-VCLibs {
    $have = Get-AppxPackage -AllUsers -Name "Microsoft.VCLibs.140.00*" -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if ($have) {
        Write-Log -Message ("VCLibs detected. Version: {0}" -f $have.Version)
        return $true
    }

    Write-Log -Message "Ensuring Microsoft.VCLibs.x64.14.00.Desktop (best effort)..."
    $depDir = Join-Path $SetupRoot "Dependencies"
    Ensure-Directory -Path $depDir
    $vcl = Join-Path $depDir "Microsoft.VCLibs.x64.14.00.Desktop.appx"
    if (-not (Download-File -Url "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -OutFile $vcl)) {
        return $false
    }

    [void](Try-AddAppx -PackagePath $vcl)
    Start-Sleep -Seconds 2

    $have2 = Get-AppxPackage -AllUsers -Name "Microsoft.VCLibs.140.00*" -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if ($have2) {
        Write-Log -Message ("VCLibs installed/updated. Version: {0}" -f $have2.Version)
        return $true
    }

    Write-Log -Message "VCLibs still not detected after attempt." -Level "WARNING"
    return $false
}

function Ensure-UIXaml28 {
    $have = Get-AppxPackage -AllUsers -Name "Microsoft.UI.Xaml*" -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if ($have) {
        Write-Log -Message ("UI.Xaml detected. Version: {0}" -f $have.Version)
        return $true
    }

    Write-Log -Message "UI.Xaml not detected. Attempting best-effort install..."
    $depDir = Join-Path $SetupRoot "Dependencies"
    Ensure-Directory -Path $depDir
    $uix = Join-Path $depDir "Microsoft.UI.Xaml.2.8.x64.appx"
    if (-not (Download-File -Url "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx" -OutFile $uix)) {
        return $false
    }

    [void](Try-AddAppx -PackagePath $uix)
    Start-Sleep -Seconds 2

    $have2 = Get-AppxPackage -AllUsers -Name "Microsoft.UI.Xaml*" -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if ($have2) {
        Write-Log -Message ("UI.Xaml installed. Version: {0}" -f $have2.Version)
        return $true
    }

    Write-Log -Message "UI.Xaml still not detected after attempt." -Level "WARNING"
    return $false
}

function Ensure-WindowsAppRuntime18 {
    $have = Get-AppxPackage -AllUsers -Name "Microsoft.WindowsAppRuntime.1.8*" -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if ($have) {
        Write-Log -Message ("WindowsAppRuntime 1.8 detected. Version: {0}" -f $have.Version)
        return $true
    }

    Write-Log -Message "WindowsAppRuntime 1.8 not detected. Attempting install..."
    $depDir = Join-Path $SetupRoot "Dependencies"
    Ensure-Directory -Path $depDir
    $exe = Join-Path $depDir ("WindowsAppRuntimeInstall-x64_{0}.exe" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
    if (-not (Download-File -Url "https://aka.ms/windowsappsdk/1.8/1.8.260209005/windowsappruntimeinstall-x64.exe" -OutFile $exe)) {
        return $false
    }

    $r = Invoke-Native -FilePath $exe -Arguments @("/install","/quiet","/norestart") -TimeoutSec 300
    Write-Log -Message ("WindowsAppRuntime installer exit code: {0}" -f $r.ExitCode)

    Start-Sleep -Seconds 2
    $have2 = Get-AppxPackage -AllUsers -Name "Microsoft.WindowsAppRuntime.1.8*" -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if ($have2) {
        Write-Log -Message ("WindowsAppRuntime 1.8 installed. Version: {0}" -f $have2.Version)
        return $true
    }

    Write-Log -Message "WindowsAppRuntime 1.8 still not detected after attempt." -Level "WARNING"
    return $false
}

function Try-RepairWinGetPackageManager {
    Write-Log -Message "Attempting Microsoft.WinGet.Client workflow (best effort)..."
    try {
        try {
            Install-PackageProvider -Name NuGet -Force -Scope AllUsers -ErrorAction SilentlyContinue | Out-Null
        } catch {}

        Install-Module -Name Microsoft.WinGet.Client -Force -Scope AllUsers -ErrorAction Stop | Out-Null
        Import-Module Microsoft.WinGet.Client -Force -ErrorAction Stop
        Repair-WinGetPackageManager -AllUsers -ErrorAction Stop | Out-Null
        Start-Sleep -Seconds 3

        $p = Get-WinGetFromPath
        if ($p -and (Test-WinGetFunctional -WingetPath $p)) {
            return $true
        }

        try {
            Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction SilentlyContinue | Out-Null
        } catch {}

        $p2 = Get-WinGetFromPath
        if ($p2 -and (Test-WinGetFunctional -WingetPath $p2)) {
            return $true
        }

        return $false
    } catch {
        Write-Log -Message ("Microsoft.WinGet.Client workflow failed: {0}" -f $_.Exception.Message) -Level "WARNING"
        return $false
    }
}

function Try-DesktopAppInstallerAppx {
    param([Parameter(Mandatory=$true)][string]$BundlePath)

    Write-Log -Message ("Attempting DesktopAppInstaller install from: {0}" -f $BundlePath)
    try {
        Add-AppxPackage -Path $BundlePath -ErrorAction Stop | Out-Null
        Write-Log -Message "DesktopAppInstaller installed via Add-AppxPackage."
    } catch {
        Write-Log -Message ("DesktopAppInstaller Add-AppxPackage failed: {0}" -f $_.Exception.Message) -Level "WARNING"
    }

    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction SilentlyContinue | Out-Null
    } catch {}

    Start-Sleep -Seconds 2
    $p = Get-WinGetFromPath
    if ($p -and (Test-WinGetFunctional -WingetPath $p)) {
        return $true
    }
    return $false
}

function Get-PayloadCandidatesFromBundle {
    param([Parameter(Mandatory=$true)][string]$MsixBundlePath)

    $bundleExtract = Join-Path $SetupRoot "_bundle_extract"
    Expand-ZipLike -PackagePath $MsixBundlePath -DestDir $bundleExtract

    $msixFiles = Get-ChildItem -Path $bundleExtract -Filter "*.msix" -ErrorAction SilentlyContinue | Sort-Object Name
    if (-not $msixFiles) { throw "No .msix files found inside bundle." }

    $x64 = $msixFiles | Where-Object { $_.Name -match "x64" -and $_.Name -notmatch "arm64" } | Select-Object -First 1
    if (-not $x64) { $x64 = $msixFiles | Where-Object { $_.Name -notmatch "arm64" } | Select-Object -First 1 }
    if (-not $x64) { throw "No suitable x64/non-arm64 .msix found inside bundle." }

    Write-Log -Message ("Selected MSIX: {0}" -f $x64.FullName)

    $msixScan = Join-Path $SetupRoot "_msix_scan"
    Expand-ZipLike -PackagePath $x64.FullName -DestDir $msixScan

    $cands = Get-ChildItem -Path $msixScan -Filter "winget.exe" -Recurse -ErrorAction SilentlyContinue
    if (-not $cands) { throw "No winget.exe candidates found inside MSIX." }

    $ranked = @()
    foreach ($c in $cands) {
        $dir = Split-Path $c.FullName -Parent
        $dllCount = @(Get-ChildItem -Path $dir -Filter "*.dll" -ErrorAction SilentlyContinue).Count
        $totalSize = 0
        try {
            $totalSize = (Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        } catch {}

        $ranked += [PSCustomObject]@{
            FullName  = $c.FullName
            Length    = $c.Length
            Dir       = $dir
            DllCount  = $dllCount
            TotalSize = [int64]$totalSize
        }
    }

    $ranked = $ranked | Sort-Object -Property `
        @{Expression='DllCount';Descending=$true},
        @{Expression='TotalSize';Descending=$true},
        @{Expression='Length';Descending=$true}

    return ,$ranked
}

function Deploy-PortablePayload {
    param([Parameter(Mandatory=$true)][string]$PayloadDir)

    Ensure-Directory -Path (Split-Path $PortableDir -Parent)

    $backup = $null
    if (Test-Path -LiteralPath $PortableDir) {
        $backup = "{0}.bak.{1}" -f $PortableDir, (Get-Date -Format "yyyyMMdd-HHmmss")
        Move-Item -Path $PortableDir -Destination $backup -Force
        Write-Log -Message ("Backed up existing payload: {0}" -f $backup)
    }

    Ensure-Directory -Path $PortableDir
    Copy-Item -Path (Join-Path $PayloadDir "*") -Destination $PortableDir -Recurse -Force -ErrorAction Stop
    Write-Log -Message ("Deployed portable payload to: {0}" -f $PortableDir)

    Ensure-InMachinePath -Dir $PortableDir

    $winget = Join-Path $PortableDir "winget.exe"
    if (Test-WinGetFunctional -WingetPath $winget) {
        return $true
    }

    Write-Log -Message "Deployed payload failed validation (winget did not run cleanly). Initiating rollback." -Level "ERROR"
    try {
        Remove-Item -Path $PortableDir -Recurse -Force -ErrorAction SilentlyContinue
        if ($backup -and (Test-Path -LiteralPath $backup)) {
            Move-Item -Path $backup -Destination $PortableDir -Force
            Write-Log -Message ("Rollback complete. Restored previous payload from: {0}" -f $backup) -Level "WARNING"
        }
    } catch {}
    return $false
}

function Cleanup-Temp {
    foreach ($p in @((Join-Path $SetupRoot "_bundle_extract"), (Join-Path $SetupRoot "_msix_scan"))) {
        try { Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
    Write-Log -Message "Cleanup completed (temporary extracts removed)."
}

try {
    if (-not (Test-IsAdmin)) { throw "This script must run elevated (Administrator)." }

    Write-Log -Message "Starting WinGet configuration on Windows Server 2019..."

    Ensure-Directory -Path $SetupRoot
    Ensure-Directory -Path (Join-Path $SetupRoot "Downloads")

    $existingPath = Get-WinGetFromPath
    if ($existingPath -and (Test-WinGetFunctional -WingetPath $existingPath)) {
        Write-Log -Message "WinGet already functional from PATH. No changes required."
        exit 0
    }

    $portableWinget = Join-Path $PortableDir "winget.exe"
    if (Test-WinGetFunctional -WingetPath $portableWinget) {
        Ensure-InMachinePath -Dir $PortableDir
        Write-Log -Message "Portable WinGet already functional. No changes required."
        exit 0
    }

    if (Try-RepairWinGetPackageManager) {
        Write-Log -Message "WinGet installed via Microsoft.WinGet.Client workflow."
        exit 0
    }

    [void](Set-AppxPolicies)
    $vOk = Ensure-VCLibs
    $uOk = Ensure-UIXaml28
    $rOk = Ensure-WindowsAppRuntime18

    if ($StrictPrereqs) {
        if (-not $vOk) { throw "Strict prereq failure: VCLibs" }
        if (-not $uOk) { throw "Strict prereq failure: UI.Xaml" }
    }

    $downloads = Join-Path $SetupRoot "Downloads"

    foreach ($tag in $CandidateReleases) {
        try {
            $bundleName = "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe_{0}.msixbundle" -f $tag.Replace('/','_')
            $bundlePath = Join-Path $downloads $bundleName

            if ($tag -eq "latest") {
                $url = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
            } else {
                $url = "https://github.com/microsoft/winget-cli/releases/download/{0}/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -f $tag
            }

            if (-not (Download-File -Url $url -OutFile $bundlePath)) {
                Write-Log -Message ("Skipping release {0}; download failed." -f $tag) -Level "WARNING"
                continue
            }

            if ($rOk) {
                if (Try-DesktopAppInstallerAppx -BundlePath $bundlePath) {
                    Write-Log -Message ("WinGet functional after DesktopAppInstaller install from {0}" -f $tag)
                    exit 0
                }
            } else {
                Write-Log -Message ("WindowsAppRuntime 1.8 missing; skipping AppX registration attempt for {0}" -f $tag) -Level "WARNING"
            }

            $ranked = Get-PayloadCandidatesFromBundle -MsixBundlePath $bundlePath
            $best = $ranked | Select-Object -First 1
            Write-Log -Message ("Best candidate from {0}: {1} (Size={2} DllCount={3} TotalSize={4})" -f $tag, $best.FullName, $best.Length, $best.DllCount, $best.TotalSize)

            if ($best.Dir -match "arm64") {
                Write-Log -Message ("Skipping ARM64-looking candidate for release {0}" -f $tag) -Level "WARNING"
                continue
            }

            if (Deploy-PortablePayload -PayloadDir $best.Dir) {
                Write-Log -Message ("WinGet installed via portable payload from release {0}" -f $tag)
                exit 0
            }
        } catch {
            Write-Log -Message ("Release {0} failed: {1}" -f $tag, $_.Exception.Message) -Level "WARNING"
        } finally {
            Cleanup-Temp
        }
    }

    throw ("All candidate releases failed validation. See log for details: {0}" -f $script:LogPath)
}
catch {
    Write-Log -Message ("Fatal error: {0}" -f $_.Exception.Message) -Level "ERROR"
    try { Cleanup-Temp } catch {}
    exit 1
}

# End of script
