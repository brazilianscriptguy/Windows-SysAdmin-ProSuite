<#
.SYNOPSIS
    Collects and exports WSUS environment details (inventory/preflight).

.DESCRIPTION
    Produces a structured environment report to support WSUS maintenance troubleshooting.
    Exports:
      - JSON report (full detail)
      - CSV summary (flattened)
      - Log file (single log per run)

    Hardened:
      - StrictMode safe
      - Robust WSUS Admin API load
      - Explicit server/port/ssl parameters
      - IIS + services + disk + WSUS config inventory
      - Optional GUI (default) or headless mode (-NoGui)

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: 2026-02-05  -03
    Version: 1.50
#>

param(
    [string]$ServerName = "localhost",
    [int]$Port = 8530,
    [switch]$UseSSL,
    [string]$OutputDir = "C:\Logs-TEMP\WSUS-GUI\Reports",
    [switch]$NoGui,
    [switch]$Quiet,
    [switch]$ShowConsole
)

#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null
[System.Windows.Forms.Application]::EnableVisualStyles()

# ----------------- Paths / logging -----------------
$scriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$rootDir    = "C:\Logs-TEMP\WSUS-GUI"
$logDir     = Join-Path $rootDir "Logs"
$null = New-Item -Path $logDir -ItemType Directory -Force -ErrorAction SilentlyContinue
$null = New-Item -Path $OutputDir -ItemType Directory -Force -ErrorAction SilentlyContinue
$logPath    = Join-Path $logDir "$scriptName.log"

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO","WARNING","ERROR","DEBUG")][string]$Level = "INFO"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    try { Add-Content -Path $logPath -Value $line -Encoding UTF8 -ErrorAction Stop } catch {}
}

function Show-Ui {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Title = "WSUS Inventory",
        [ValidateSet("Information","Warning","Error")][string]$Icon = "Information"
    )
    if ($Quiet -or $NoGui) { return }
    $mbIcon = [System.Windows.Forms.MessageBoxIcon]::$Icon
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, 'OK', $mbIcon) | Out-Null
}

# ----------------- Console visibility -----------------
function Set-ConsoleVisibility {
    param([bool]$Visible)

    try {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinConsole {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@ -ErrorAction Stop

        $h = [WinConsole]::GetConsoleWindow()
        if ($h -ne [IntPtr]::Zero) {
            $cmd = if ($Visible) { 5 } else { 0 }
            [void][WinConsole]::ShowWindow($h, $cmd)
        }
    } catch { }
}
if (-not $ShowConsole) { Set-ConsoleVisibility -Visible:$false }

# ----------------- Helpers -----------------
function Normalize-ServerName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return "localhost" }
    if ($Name -match '^(localhost|127\.0\.0\.1)$') { return "localhost" }
    return $Name.Trim()
}

function Get-FQDNLocal {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        if ($cs.Domain -and $cs.Domain -ne $cs.DNSHostName) { return "$($cs.DNSHostName).$($cs.Domain)" }
        return $cs.DNSHostName
    } catch {
        try { return [System.Net.Dns]::GetHostEntry('').HostName } catch { return $env:COMPUTERNAME }
    }
}

function Resolve-WsusAdminAssembly {
    $apiPath = "C:\Program Files\Update Services\Api\Microsoft.UpdateServices.Administration.dll"

    $loaded = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq "Microsoft.UpdateServices.Administration" }
    if ($loaded) { return @{ Loaded=$true; Method="AlreadyLoaded"; Path=$null } }

    if (Test-Path $apiPath) {
        try { Add-Type -Path $apiPath -ErrorAction Stop; return @{ Loaded=$true; Method="AddTypePath"; Path=$apiPath } }
        catch { return @{ Loaded=$false; Method="AddTypePath"; Path=$apiPath; Error=$_.Exception.Message } }
    }

    try {
        $asm = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")
        if ($asm) { return @{ Loaded=$true; Method="LoadWithPartialName"; Path=$asm.Location } }
    } catch {}

    return @{ Loaded=$false; Method="NotFound"; Path=$null; Error="Microsoft.UpdateServices.Administration not found. Install WSUS Tools (UpdateServices-UI)." }
}

function Get-ServiceState {
    param([string]$Name)
    try {
        $s = Get-Service -Name $Name -ErrorAction Stop
        return [pscustomobject]@{ Name=$Name; Status=$s.Status.ToString(); StartType=$s.StartType.ToString() }
    } catch {
        return [pscustomobject]@{ Name=$Name; Status="NotFound"; StartType=$null }
    }
}

function Get-DiskInfo {
    param([string[]]$DriveLetters)

    $out = @()
    foreach ($d in $DriveLetters | Where-Object { $_ }) {
        try {
            $drive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $d) -ErrorAction Stop
            $out += [pscustomobject]@{
                Drive       = $drive.DeviceID
                SizeGB      = [math]::Round(($drive.Size/1GB),2)
                FreeGB      = [math]::Round(($drive.FreeSpace/1GB),2)
                FreePct     = if ($drive.Size -gt 0) { [math]::Round(($drive.FreeSpace/$drive.Size)*100,2) } else { $null }
            }
        } catch { }
    }
    return $out
}

function Get-IisWsusPoolInfo {
    try {
        Import-Module WebAdministration -ErrorAction Stop
        if (Test-Path "IIS:\AppPools\WsusPool") {
            $p = Get-Item "IIS:\AppPools\WsusPool"
            return [pscustomobject]@{
                Exists = $true
                State  = $p.state
            }
        }
        return [pscustomobject]@{ Exists=$false; State=$null }
    } catch {
        return [pscustomobject]@{ Exists=$false; State=$null; Error=$_.Exception.Message }
    }
}

function Get-WsusReport {
    param([string]$Server,[int]$Port,[bool]$UseSSL)

    $Server = Normalize-ServerName $Server
    $localFqdn = Get-FQDNLocal

    $asm = Resolve-WsusAdminAssembly
    if (-not $asm.Loaded) { throw $asm.Error }

    # WSUS connect (prefer 3-arg overload)
    $wsus = $null
    try { $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($Server,$UseSSL,$Port) }
    catch { $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($Server,$UseSSL) }

    $cfg = $wsus.GetConfiguration()

    # Content dir + drive
    $contentDir = $null
    try { $contentDir = $cfg.LocalContentCachePath } catch { $contentDir = $null }
    $contentDrive = if ($contentDir -and $contentDir.Length -ge 2) { $contentDir.Substring(0,2) } else { $null }

    # Some WSUS stats can be heavy; keep it modest.
    $updateStats = $null
    try {
        $updates = $wsus.GetUpdates()
        $updateStats = [pscustomobject]@{
            Total     = @($updates).Count
            Approved  = @($updates | Where-Object { $_.IsApproved }).Count
            Declined  = @($updates | Where-Object { $_.IsDeclined }).Count
        }
    } catch {
        $updateStats = [pscustomobject]@{ Error=$_.Exception.Message }
    }

    # Computer groups (count only)
    $groups = @()
    try {
        $groups = $wsus.GetComputerTargetGroups() | ForEach-Object {
            [pscustomobject]@{ Name=$_.Name; Computers=$_.GetComputerTargets().Count }
        }
    } catch { }

    # Services + IIS
    $svc = @(
        Get-ServiceState "W3SVC"
        Get-ServiceState "WSUSService"
    )
    $pool = Get-IisWsusPoolInfo

    # LogFiles dir size
    $logDir = "C:\Program Files\Update Services\LogFiles"
    $logSizeMB = 0
    try {
        if (Test-Path $logDir) {
            $sum = (Get-ChildItem -Path $logDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            $logSizeMB = [math]::Round(($sum/1MB),2)
        }
    } catch { $logSizeMB = $null }

    # Disk info (system + content)
    $drives = @("C:")
    if ($contentDrive -and ($drives -notcontains $contentDrive)) { $drives += $contentDrive }
    $disk = Get-DiskInfo -DriveLetters $drives

    return [pscustomobject]@{
        Timestamp     = (Get-Date)
        Target        = [pscustomobject]@{ Server=$Server; Port=$Port; UseSSL=$UseSSL; LocalFqdn=$localFqdn }
        Assembly      = [pscustomobject]@{ Loaded=$asm.Loaded; Method=$asm.Method; Path=$asm.Path }
        Services      = $svc
        IisWsusPool   = $pool
        Wsus          = [pscustomobject]@{
            Name                 = $wsus.Name
            Version              = $wsus.Version.ToString()
            ContentDir           = $contentDir
            SyncFromMicrosoft    = $cfg.SyncFromMicrosoftUpdate
            UpstreamServer       = if ($cfg.SyncFromMicrosoftUpdate) { $null } else { $cfg.UpstreamWsusServerName }
            UpstreamPort         = if ($cfg.SyncFromMicrosoftUpdate) { $null } else { $cfg.UpstreamWsusServerPortNumber }
            NextSyncTime         = try { $cfg.NextSyncTime } catch { $null }
        }
        UpdateStats   = $updateStats
        ComputerGroups= $groups
        WsusLogSizeMB = $logSizeMB
        Disks         = $disk
    }
}

function Export-WsusReport {
    param([psobject]$Report)

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $jsonPath = Join-Path $OutputDir ("WSUS-Inventory-{0}.json" -f $stamp)
    $csvPath  = Join-Path $OutputDir ("WSUS-Inventory-{0}.csv" -f $stamp)

    $Report | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8

    function Get-ObjProp {
        param([object]$Obj,[string]$PropName)
        if ($null -eq $Obj) { return $null }
        $p = $Obj.PSObject.Properties[$PropName]
        if ($null -eq $p) { return $null }
        return $p.Value
    }

    # Safe update stat extraction (works even if UpdateStats is {Error=...})
    $total    = Get-ObjProp -Obj $Report.UpdateStats -PropName "Total"
    $approved = Get-ObjProp -Obj $Report.UpdateStats -PropName "Approved"
    $declined = Get-ObjProp -Obj $Report.UpdateStats -PropName "Declined"
    $ustErr   = Get-ObjProp -Obj $Report.UpdateStats -PropName "Error"

    $w3svc     = ($Report.Services | Where-Object Name -eq "W3SVC"     | Select-Object -First 1)
    $wsusSvc   = ($Report.Services | Where-Object Name -eq "WSUSService" | Select-Object -First 1)

    $row = [pscustomobject]@{
        Timestamp          = $Report.Timestamp
        Server             = $Report.Target.Server
        Port               = $Report.Target.Port
        UseSSL             = $Report.Target.UseSSL
        LocalFqdn          = $Report.Target.LocalFqdn

        AdminApiLoaded     = $Report.Assembly.Loaded
        AdminApiMethod     = $Report.Assembly.Method

        WSUSName           = $Report.Wsus.Name
        WSUSVersion        = $Report.Wsus.Version
        ContentDir         = $Report.Wsus.ContentDir
        SyncFromMicrosoft  = $Report.Wsus.SyncFromMicrosoft
        UpstreamServer     = $Report.Wsus.UpstreamServer

        W3SVC              = $w3svc.Status
        WSUSService        = $wsusSvc.Status
        WsusPoolExists     = $Report.IisWsusPool.Exists
        WsusPoolState      = $Report.IisWsusPool.State

        TotalUpdates       = $total
        ApprovedUpdates    = $approved
        DeclinedUpdates    = $declined
        UpdateStatsError   = $ustErr

        GroupCount         = @($Report.ComputerGroups).Count
        WsusLogSizeMB      = $Report.WsusLogSizeMB
    }

    $row | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    return @{ Json=$jsonPath; Csv=$csvPath }
}

# ----------------- Main execution -----------------
Write-Log "========== WSUS INVENTORY START ==========" "INFO"

$ServerName = Normalize-ServerName $ServerName
Write-Log "Target: Server=$ServerName Port=$Port SSL=$($UseSSL.IsPresent) OutputDir=$OutputDir" "INFO"

$runInventory = {
    try {
        $report = Get-WsusReport -Server $ServerName -Port $Port -UseSSL ([bool]$UseSSL)
        $paths  = Export-WsusReport -Report $report

        Write-Log "Exported JSON: $($paths.Json)" "INFO"
        Write-Log "Exported CSV : $($paths.Csv)"  "INFO"
        Write-Log "========== WSUS INVENTORY END ==========" "INFO"

        if (-not $Quiet) {
            Show-Ui -Message ("WSUS inventory completed.`n`nJSON: {0}`nCSV : {1}`nLog : {2}" -f $paths.Json,$paths.Csv,$logPath) -Icon Information
        }

        return $paths
    } catch {
        Write-Log ("Inventory failed: {0}" -f $_.Exception.Message) "ERROR"
        Show-Ui -Message ("Inventory failed.`n`nError: {0}`nLog: {1}" -f $_.Exception.Message,$logPath) -Icon Error
        throw
    }
}

if ($NoGui) {
    & $runInventory | Out-Null
    return
}

# ----------------- Minimal GUI -----------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "WSUS Inventory"
$form.Size = New-Object System.Drawing.Size(520, 240)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$btn = New-Object System.Windows.Forms.Button
$btn.Text = "Run Inventory"
$btn.Location = New-Object System.Drawing.Point(15, 15)
$btn.Size = New-Object System.Drawing.Size(140, 30)
$form.Controls.Add($btn)

$lbl = New-Object System.Windows.Forms.Label
$lbl.Text = "Ready"
$lbl.Location = New-Object System.Drawing.Point(15, 55)
$lbl.Size = New-Object System.Drawing.Size(470, 20)
$form.Controls.Add($lbl)

$bar = New-Object System.Windows.Forms.ProgressBar
$bar.Location = New-Object System.Drawing.Point(15, 80)
$bar.Size = New-Object System.Drawing.Size(470, 20)
$bar.Minimum = 0
$bar.Maximum = 100
$form.Controls.Add($bar)

$btn.Add_Click({
    $btn.Enabled = $false
    $bar.Value = 10
    $lbl.Text = "Running..."
    $form.Refresh()

    try {
        $bar.Value = 35
        $form.Refresh()
        & $runInventory | Out-Null
        $bar.Value = 100
        $lbl.Text = "Done"
    } catch {
        $bar.Value = 0
        $lbl.Text = "Failed — see log"
    } finally {
        $btn.Enabled = $true
    }
})

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()

# End of script

