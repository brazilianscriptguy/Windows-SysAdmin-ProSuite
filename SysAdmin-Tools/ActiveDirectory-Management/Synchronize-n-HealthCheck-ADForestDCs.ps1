<#
.SYNOPSIS
    Active Directory Forest Replication Synchronization and Health Check - Enterprise Edition.

.DESCRIPTION
    Forest-agnostic WinForms administration tool for Microsoft Active Directory.

    Capabilities:
      - Discovers every domain in the current AD forest.
      - Enumerates every writable Domain Controller across the forest.
      - Displays a searchable/filterable DC inventory with click-to-sort column headers.
      - Startup and Refresh Forest are inventory-only; remote health probes run only on explicit operator request.
      - Allows explicit per-DC selection using check boxes.
      - Retrieves the complete Windows build version (major.minor.build.UBR) for each DC.
      - Queries and displays the Netlogon service state for each DC.
      - Runs repadmin /replsummary as a pre-flight and correlates per-DC replication status, failures, total attempts, failure percentage, and maximum delta.
      - Run Basic Pre-Flight explicitly audits build, Netlogon, SYSVOL/NETLOGON shares, DFSR, W32Time, DNS, DC Locator, FSMO ownership, and bounded critical event counts.
      - Replication Pre-Flight remains independent and runs repadmin /replsummary only when requested.
      - Calculates a normalized per-DC Overall Health state: HEALTHY, DEGRADED, or CRITICAL.
      - Performs pre/post replication comparison after forced synchronization.
      - Exports both CSV inventory and structured JSON health snapshots.
      - Forces replication with repadmin /syncall.
      - Triggers KCC with repadmin /kcc.
      - Runs repadmin /replsummary.
      - Runs repadmin /showrepl * /csv with locale-tolerant parsing.
      - Runs repadmin /queue *.
      - Runs repadmin /istg * /verbose.
      - Runs focused dcdiag tests:
          Replications
          Services
          Connectivity
          DNS /DnsBasic
      - Audits Global Catalog availability.
      - Provides structured runtime logging and export.

    Design requirements:
      - Windows PowerShell 5.1 compatible.
      - Windows Server 2019 compatible.
      - Forest/domain names are never hard-coded.
      - All displayed columns are searchable.
      - External utilities are executed without opening extra console windows.
      - ActiveDirectory module import is performed without spawning a secondary console.
      - Explicit DC selection is required for write operations.
      - `${Variable}:` syntax is used where a simple variable is directly followed by a colon.
      - repadmin /replsummary parsing is locale-tolerant and based on stable data-row tokens rather than localized headings.
      - DC Locator health uses structured Get-ADDomainController -Discover results instead of localized nltest output.
      - Object properties continue to use $() subexpressions.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    2026-08-18-v3.1.0-ENTERPRISE-HEALTHENGINE
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$ShowConsole
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# =====================================================================================
# INITIALIZATION
# =====================================================================================
try {
    if(-not $ShowConsole){
        try{
            if(-not ('NativeConsoleWindow' -as [type])){
                Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeConsoleWindow {
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public static void Hide() {
        IntPtr hWnd = GetConsoleWindow();
        if(hWnd != IntPtr.Zero) {
            ShowWindow(hWnd, 0);
        }
    }
}
"@ -ErrorAction SilentlyContinue
            }

            [NativeConsoleWindow]::Hide()
        }
        catch {}
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    if(-not (Get-Module -ListAvailable -Name ActiveDirectory)){
        throw 'The ActiveDirectory PowerShell module is not installed.'
    }

    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Error "Initialization failed: $($_.Exception.Message)"
    return
}

# =====================================================================================
# GLOBAL STATE
# =====================================================================================
$script:AppName = 'AD Forest Synchronization & Health Check'
$script:AppVersion = '3.1.0'
$script:LogRoot = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'ADForestHealth\Logs'
$script:LogFile = Join-Path $script:LogRoot ("ADForestHealth-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

$script:RepadminPath = $null
$script:DcdiagPath = $null

$script:Forest = $null
$script:DCInventory = @()
$script:DisplayedDCs = @()
$script:SortProperty = 'Domain'
$script:SortAscending = $true

$script:IsBusy = $false
$script:CancelRequested = $false

# Enterprise health policy / thresholds. Centralized to avoid scattered constants.
$script:HealthPolicy = [pscustomobject]@{
    ReplicationWarningSeconds  = 3600       # 1 hour
    ReplicationCriticalSeconds = 14400      # 4 hours
    RemoteTimeoutSeconds       = 12
    EventLookbackHours         = 24
    EventWarningCount          = 1
    EventCriticalCount         = 10
}

$script:LastHealthSnapshot = @{}


$script:txtRuntimeLog = $null
$script:statusMain = $null
$script:statusCurrent = $null
$script:progress = $null

if(-not (Test-Path -LiteralPath $script:LogRoot)){
    New-Item -Path $script:LogRoot -ItemType Directory -Force | Out-Null
}

# =====================================================================================
# LOGGING / STATUS
# =====================================================================================
function Write-AppLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [ValidateSet('DEBUG','INFO','SUCCESS','WARN','ERROR')]
        [string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message

    try{
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch{}

    if($script:txtRuntimeLog -and -not $script:txtRuntimeLog.IsDisposed){
        try{
            $script:txtRuntimeLog.AppendText($line + [Environment]::NewLine)
            $script:txtRuntimeLog.SelectionStart = $script:txtRuntimeLog.Text.Length
            $script:txtRuntimeLog.ScrollToCaret()
        }
        catch{}
    }
    elseif($ShowConsole){
        Write-Host $line
    }
}

function Set-AppStatus {
    param([string]$Text)

    if($script:statusMain -and -not $script:statusMain.IsDisposed){
        $script:statusMain.Text = $Text
        [Windows.Forms.Application]::DoEvents()
    }
}

function Set-CurrentOperation {
    param([string]$Text)

    if($script:statusCurrent -and -not $script:statusCurrent.IsDisposed){
        $script:statusCurrent.Text = $Text
        [Windows.Forms.Application]::DoEvents()
    }
}

function Set-ProgressState {
    param(
        [int]$Value,
        [int]$Maximum = 1
    )

    if($script:progress -and -not $script:progress.IsDisposed){
        $script:progress.Maximum = [Math]::Max(1,$Maximum)
        $script:progress.Value = [Math]::Min(
            [Math]::Max(0,$Value),
            $script:progress.Maximum
        )
    }
}

function Show-AppMessage {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [string]$Title = $script:AppName,

        [ValidateSet('Information','Warning','Error')]
        [string]$Type = 'Information'
    )

    $icon = switch($Type){
        'Warning' { [Windows.Forms.MessageBoxIcon]::Warning }
        'Error'   { [Windows.Forms.MessageBoxIcon]::Error }
        default   { [Windows.Forms.MessageBoxIcon]::Information }
    }

    [void][Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [Windows.Forms.MessageBoxButtons]::OK,
        $icon
    )
}

function Write-Section {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Title
    )

    $line = '=' * 92
    Write-AppLog $line INFO
    Write-AppLog ("SECTION: {0}" -f $Title) INFO
    Write-AppLog $line INFO
}

# =====================================================================================
# DEPENDENCIES / EXTERNAL PROCESS
# =====================================================================================
function Initialize-Dependencies {
    [CmdletBinding()]
    param()

    $script:RepadminPath = (Get-Command repadmin.exe -ErrorAction Stop).Source
    $script:DcdiagPath = (Get-Command dcdiag.exe -ErrorAction Stop).Source

    Write-AppLog "repadmin.exe: $($script:RepadminPath)" SUCCESS
    Write-AppLog "dcdiag.exe: $($script:DcdiagPath)" SUCCESS
}

function ConvertTo-ProcessArgument {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Value
    )

    $escaped = $Value -replace '"','\"'

    if($escaped -match '\s|[&\(\)\^\%\!\|<>]'){
        return '"' + $escaped + '"'
    }

    return $escaped
}

function Invoke-ExternalProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,

        [Parameter(Mandatory=$true)]
        [string[]]$Arguments
    )

    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = (($Arguments | ForEach-Object {
        ConvertTo-ProcessArgument -Value $_
    }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden

    try{
        $oem = [Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
        $encoding = [Text.Encoding]::GetEncoding($oem)
        $psi.StandardOutputEncoding = $encoding
        $psi.StandardErrorEncoding = $encoding
    }
    catch{}

    $process = New-Object Diagnostics.Process
    $process.StartInfo = $psi

    [void]$process.Start()

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()

    $process.WaitForExit()

    [pscustomobject]@{
        ExitCode = [int]$process.ExitCode
        StdOut   = [string]$stdout
        StdErr   = [string]$stderr
    }
}

function Get-CommandVerdict {
    param(
        [Parameter(Mandatory=$true)]
        [int]$ExitCode,

        [string]$Output
    )

    if($ExitCode -ne 0){
        return 'FAIL'
    }

    if([string]::IsNullOrWhiteSpace($Output)){
        return 'OK'
    }

    if($Output -match '(?i)\b(fail|fails|failed|error|fatal|cannot|unavailable|denied|access\s+is\s+denied)\b'){
        return 'WARN'
    }

    return 'OK'
}

function Write-ExternalResult {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Command,

        [Parameter(Mandatory=$true)]
        $Result
    )

    $output = (($Result.StdOut + [Environment]::NewLine + $Result.StdErr).Trim())
    $verdict = Get-CommandVerdict -ExitCode $Result.ExitCode -Output $output

    $level = switch($verdict){
        'OK'   { 'SUCCESS' }
        'WARN' { 'WARN' }
        default { 'ERROR' }
    }

    Write-AppLog ("${Command}: ${verdict} (exit $($Result.ExitCode))") $level

    if(-not [string]::IsNullOrWhiteSpace($output)){
        Write-AppLog ("${Command}: raw output follows.`r`n$output") DEBUG
    }

    return [pscustomobject]@{
        Command  = $Command
        ExitCode = $Result.ExitCode
        Verdict  = $verdict
        Output   = $output
    }
}

function Get-RemoteFullBuildVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ComputerName,

        [string]$FallbackVersion
    )

    try{
        $build = Invoke-Command `
            -ComputerName $ComputerName `
            -ErrorAction Stop `
            -ScriptBlock {
                $key = Get-ItemProperty `
                    -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' `
                    -ErrorAction Stop

                $major = if($null -ne $key.CurrentMajorVersionNumber){
                    [int]$key.CurrentMajorVersionNumber
                }else{
                    10
                }

                $minor = if($null -ne $key.CurrentMinorVersionNumber){
                    [int]$key.CurrentMinorVersionNumber
                }else{
                    0
                }

                $buildNumber = if(-not [string]::IsNullOrWhiteSpace([string]$key.CurrentBuildNumber)){
                    [string]$key.CurrentBuildNumber
                }else{
                    [string]$key.CurrentBuild
                }

                $ubr = if($null -ne $key.UBR){
                    [string]$key.UBR
                }else{
                    '0'
                }

                '{0}.{1}.{2}.{3}' -f $major,$minor,$buildNumber,$ubr
            }

        if(-not [string]::IsNullOrWhiteSpace([string]$build)){
            return [string]$build
        }
    }
    catch{
        Write-AppLog "Full build query failed for '${ComputerName}': $($_.Exception.Message)" WARN
    }

    if(-not [string]::IsNullOrWhiteSpace($FallbackVersion)){
        return $FallbackVersion
    }

    return 'UNAVAILABLE'
}

function Get-RemoteNetlogonStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ComputerName
    )

    try{
        $status = Invoke-Command `
            -ComputerName $ComputerName `
            -ErrorAction Stop `
            -ScriptBlock {
                [string](Get-Service -Name Netlogon -ErrorAction Stop).Status
            }

        return [pscustomobject]@{
            Status = [string]$status
            Query  = 'SUCCESS'
        }
    }
    catch{
        Write-AppLog "Netlogon query failed for '${ComputerName}': $($_.Exception.Message)" WARN

        return [pscustomobject]@{
            Status = 'UNAVAILABLE'
            Query  = 'FAILED'
        }
    }
}

# =====================================================================================
# FOREST / DOMAIN CONTROLLER DISCOVERY
# =====================================================================================
function Get-ForestDCInventory {
    [CmdletBinding()]
    param()

    $forest = Get-ADForest -ErrorAction Stop
    $script:Forest = $forest

    $rows = New-Object Collections.ArrayList

    foreach($domainName in @($forest.Domains | Sort-Object)){
        Write-AppLog "Discovering Domain Controllers in '$domainName'." INFO

        try{
            $dcs = @(
                Get-ADDomainController `
                    -Filter * `
                    -Server ([string]$domainName) `
                    -ErrorAction Stop |
                Sort-Object HostName
            )

            foreach($dc in $dcs){
                $fqdn = [string](@($dc.HostName)[0])
                $ipv4 = [string](@($dc.IPv4Address)[0])

                $adOSVersion = [string]$dc.OperatingSystemVersion

                [void]$rows.Add([pscustomobject]@{
                    Selected         = $true
                    Domain           = [string]$domainName
                    DCFqdn           = $fqdn
                    IPv4             = $ipv4
                    Site             = [string]$dc.Site
                    GlobalCatalog    = [bool]$dc.IsGlobalCatalog
                    ReadOnly         = [bool]$dc.IsReadOnly
                    Writable         = (-not [bool]$dc.IsReadOnly)
                    OperatingSystem   = [string]$dc.OperatingSystem
                    OSVersion         = $adOSVersion
                    FullBuildVersion  = $adOSVersion
                    NetlogonStatus       = 'NOT TESTED'
                    NetlogonQuery        = 'NOT TESTED'
                    ReplicationStatus    = 'NOT TESTED'
                    ReplicationFailures  = 0
                    ReplicationTotal     = 0
                    ReplicationFailurePct= 0
                    MaxReplicationDelta  = ''
                    ReplicationError      = ''
                    FSMORoles             = ''
                    SYSVOLShare           = 'NOT TESTED'
                    NETLOGONShare         = 'NOT TESTED'
                    DFSRStatus            = 'NOT TESTED'
                    W32TimeStatus         = 'NOT TESTED'
                    TimeSource            = ''
                    DNSStatus             = 'NOT TESTED'
                    DCLocatorStatus       = 'NOT TESTED'
                    DCLocatorDC           = ''
                    DCLocatorDetail       = ''
                    CriticalEventCount    = -1
                    RemoteQuery           = 'NOT TESTED'
                    OverallHealth         = 'NOT TESTED'
                })
            }
        }
        catch{
            Write-AppLog "Domain discovery failed for '${domainName}': $($_.Exception.Message)" ERROR
        }
    }

    return @($rows)
}

function Get-CheckedDCRecords {
    $rows = New-Object Collections.ArrayList

    foreach($item in $listDC.Items){
        if($item.Checked){
            [void]$rows.Add($item.Tag)
        }
    }

    return @($rows)
}

function Convert-ReplSummaryDeltaToSortableSeconds {
    [CmdletBinding()]
    param(
        [string]$DeltaText
    )

    if([string]::IsNullOrWhiteSpace($DeltaText)){
        return 0
    }

    $value = $DeltaText.Trim().ToLowerInvariant()
    $total = 0.0

    # repadmin commonly emits compact values such as:
    # 12m:34s, 01h:04m, 2d.03h:10m:22s, >60 days
    $matches = [regex]::Matches(
        $value,
        '(?<n>\d+(?:[\.,]\d+)?)\s*(?<u>d|day|days|dia|dias|h|hr|hrs|hora|horas|m|min|mins|minuto|minutos|s|sec|secs|seg|segs|segundo|segundos)'
    )

    foreach($m in $matches){
        $numberText = $m.Groups['n'].Value -replace ',','.'
        $number = 0.0

        if(-not [double]::TryParse(
            $numberText,
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$number
        )){
            continue
        }

        switch -Regex ($m.Groups['u'].Value){
            '^(d|day|days|dia|dias)$'          { $total += $number * 86400; break }
            '^(h|hr|hrs|hora|horas)$'          { $total += $number * 3600; break }
            '^(m|min|mins|minuto|minutos)$'    { $total += $number * 60; break }
            '^(s|sec|secs|seg|segs|segundo|segundos)$' { $total += $number; break }
        }
    }

    return [int][math]::Round($total)
}

function Get-ReplicationPreFlightFromReplSummary {
    [CmdletBinding()]
    param()

    Write-AppLog 'Running replication pre-flight: repadmin /replsummary.' INFO

    $result = Invoke-ExternalProcess `
        -FilePath $script:RepadminPath `
        -Arguments @('/replsummary')

    $combined = (($result.StdOut + [Environment]::NewLine + $result.StdErr).Trim())

    Write-AppLog ("repadmin /replsummary pre-flight exit code: {0}" -f $result.ExitCode) `
        $(if($result.ExitCode -eq 0){'SUCCESS'}else{'WARN'})

    if(-not [string]::IsNullOrWhiteSpace($combined)){
        Write-AppLog ("repadmin /replsummary pre-flight raw output:`r`n$combined") DEBUG
    }

    $map = @{}

    if([string]::IsNullOrWhiteSpace($combined)){
        return [pscustomobject]@{
            ExitCode = $result.ExitCode
            Rows     = $map
            Raw      = $combined
        }
    }

    foreach($line in ($combined -split "`r?`n")){
        $trimmed=$line.Trim()
        if([string]::IsNullOrWhiteSpace($trimmed)){ continue }

        # Locale-tolerant parsing. Do not depend on localized column headings.
        # Normal repadmin rows tokenize as:
        #   DSA  DELTA  FAILS  /  TOTAL  PCT  [ERROR...]
        # Example PT-BR:
        #   ADDS01-FTJ  06m:11s  0 / 18  0
        $tokens=@($trimmed -split '\s+' | Where-Object {$_ -ne ''})

        if($tokens.Count -lt 6){ continue }
        if($tokens[3] -ne '/'){ continue }
        if($tokens[0] -notmatch '^[A-Za-z0-9][A-Za-z0-9\._-]*$'){ continue }
        if($tokens[2] -notmatch '^\d+$' -or $tokens[4] -notmatch '^\d+$'){ continue }

        $dsa=[string]$tokens[0]
        $delta=[string]$tokens[1]
        $fails=[int]$tokens[2]
        $total=[int]$tokens[4]

        $pctText=([string]$tokens[5]).TrimEnd('%')
        $pct=0
        if(-not [int]::TryParse($pctText,[ref]$pct)){ continue }

        $errorText=''
        if($tokens.Count -gt 6){
            $errorText=(@($tokens[6..($tokens.Count-1)]) -join ' ')
        }

        $key=$dsa.ToUpperInvariant()
        $candidate=[pscustomobject]@{
            DSA=$dsa
            Delta=$delta
            DeltaSeconds=Convert-ReplSummaryDeltaToSortableSeconds -DeltaText $delta
            Failures=$fails
            Total=$total
            FailurePct=$pct
            Error=$errorText
        }

        # A DC appears in source and destination sections. Keep the worst result,
        # but preserve the greater total attempts when health is otherwise equal.
        if(-not $map.ContainsKey($key)){
            $map[$key]=$candidate
        }else{
            $existing=$map[$key]
            $replace=(
                $candidate.Failures -gt $existing.Failures -or
                $candidate.FailurePct -gt $existing.FailurePct -or
                $candidate.DeltaSeconds -gt $existing.DeltaSeconds -or
                (
                    $candidate.Failures -eq $existing.Failures -and
                    $candidate.FailurePct -eq $existing.FailurePct -and
                    $candidate.DeltaSeconds -eq $existing.DeltaSeconds -and
                    $candidate.Total -gt $existing.Total
                )
            )
            if($replace){ $map[$key]=$candidate }
        }
    }

    Write-AppLog ("repadmin /replsummary parser correlated {0} unique DSA row(s)." -f $map.Count) `
        $(if($map.Count -gt 0){'SUCCESS'}else{'WARN'})

    return [pscustomobject]@{
        ExitCode = $result.ExitCode
        Rows     = $map
        Raw      = $combined
    }
}

function Update-ReplicationPreFlightInventory {
    [CmdletBinding()]
    param()

    $preflight = Get-ReplicationPreFlightFromReplSummary

    if($preflight.ExitCode -eq 0 -and $preflight.Rows.Count -eq 0){
        Write-AppLog 'repadmin /replsummary succeeded but no DSA rows were parsed. Replication status will remain UNKNOWN; review localized raw output.' WARN
    }

    foreach($dc in @($script:DCInventory)){
        $shortName = ([string]$dc.DCFqdn -split '\.')[0]
        $candidateKeys = @(
            ([string]$dc.DCFqdn).ToUpperInvariant(),
            $shortName.ToUpperInvariant()
        )

        $row = $null

        foreach($key in $candidateKeys){
            if($preflight.Rows.ContainsKey($key)){
                $row = $preflight.Rows[$key]
                break
            }
        }

        if($null -eq $row){
            $dc.ReplicationStatus     = $(if($preflight.ExitCode -eq 0){'UNKNOWN'}else{'QUERY FAILED'})
            $dc.ReplicationFailures   = 0
            $dc.ReplicationTotal      = 0
            $dc.ReplicationFailurePct = 0
            $dc.MaxReplicationDelta   = ''
            $dc.ReplicationError      = ''
            continue
        }

        $dc.ReplicationFailures   = [int]$row.Failures
        $dc.ReplicationTotal      = [int]$row.Total
        $dc.ReplicationFailurePct = [int]$row.FailurePct
        $dc.MaxReplicationDelta   = [string]$row.Delta
        $dc.ReplicationError      = [string]$row.Error

        if($row.Failures -eq 0 -and $row.FailurePct -eq 0){
            $dc.ReplicationStatus = 'OK'
        }
        elseif($row.Failures -gt 0 -and $row.FailurePct -lt 100){
            $dc.ReplicationStatus = 'WARN'
        }
        else{
            $dc.ReplicationStatus = 'FAIL'
        }
    }

    $issues = @(
        $script:DCInventory |
        Where-Object {
            $_.ReplicationStatus -ne 'OK'
        }
    )

    if($issues.Count -eq 0){
        Write-AppLog 'Replication pre-flight: all correlated DCs report OK.' SUCCESS
    }else{
        Write-AppLog "Replication pre-flight: $($issues.Count) DC(s) are not reporting OK." WARN

        foreach($issue in $issues){
            Write-AppLog (
                "Replication pre-flight issue: DC='{0}'; Status='{1}'; Failures={2}/{3}; FailurePct={4}; MaxDelta='{5}'; Error='{6}'." -f
                $issue.DCFqdn,
                $issue.ReplicationStatus,
                $issue.ReplicationFailures,
                $issue.ReplicationTotal,
                $issue.ReplicationFailurePct,
                $issue.MaxReplicationDelta,
                $issue.ReplicationError
            ) WARN
        }
    }
}


function Get-FSMORoleMap {
    [CmdletBinding()]
    param()

    $map = @{}

    function Add-Role {
        param([string]$Server,[string]$Role)
        if([string]::IsNullOrWhiteSpace($Server)){ return }
        $short = ($Server -split '\.')[0].ToUpperInvariant()
        if(-not $map.ContainsKey($short)){ $map[$short] = New-Object Collections.ArrayList }
        [void]$map[$short].Add($Role)
    }

    try{
        $forest = Get-ADForest -ErrorAction Stop
        Add-Role -Server ([string]$forest.SchemaMaster) -Role 'Schema'
        Add-Role -Server ([string]$forest.DomainNamingMaster) -Role 'DomainNaming'

        foreach($domainName in @($forest.Domains)){
            $domain = Get-ADDomain -Identity ([string]$domainName) -Server ([string]$domainName) -ErrorAction Stop
            Add-Role -Server ([string]$domain.PDCEmulator) -Role 'PDC'
            Add-Role -Server ([string]$domain.RIDMaster) -Role 'RID'
            Add-Role -Server ([string]$domain.InfrastructureMaster) -Role 'Infrastructure'
        }
    }
    catch{
        Write-AppLog "FSMO discovery failed: $($_.Exception.Message)" WARN
    }

    return $map
}

function Invoke-RemoteDCEnterpriseProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName
    )

    try{
        $result = Invoke-Command -ComputerName $ComputerName -ErrorAction Stop -ScriptBlock {
            $out = [ordered]@{}

            foreach($serviceName in @('Netlogon','DFSR','W32Time')){
                try{ $out[$serviceName] = [string](Get-Service -Name $serviceName -ErrorAction Stop).Status }
                catch{ $out[$serviceName] = 'UNAVAILABLE' }
            }

            try{
                $shares = @(Get-CimInstance Win32_Share -ErrorAction Stop | Select-Object -ExpandProperty Name)
                $out['SYSVOLShare'] = if($shares -contains 'SYSVOL'){'OK'}else{'MISSING'}
                $out['NETLOGONShare'] = if($shares -contains 'NETLOGON'){'OK'}else{'MISSING'}
            }catch{
                $out['SYSVOLShare']='UNKNOWN'; $out['NETLOGONShare']='UNKNOWN'
            }

            try{
                $key = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
                $major = if($null -ne $key.CurrentMajorVersionNumber){[int]$key.CurrentMajorVersionNumber}else{10}
                $minor = if($null -ne $key.CurrentMinorVersionNumber){[int]$key.CurrentMinorVersionNumber}else{0}
                $build = if($key.CurrentBuildNumber){[string]$key.CurrentBuildNumber}else{[string]$key.CurrentBuild}
                $ubr = if($null -ne $key.UBR){[string]$key.UBR}else{'0'}
                $out['FullBuildVersion'] = '{0}.{1}.{2}.{3}' -f $major,$minor,$build,$ubr
            }catch{ $out['FullBuildVersion']='UNAVAILABLE' }

            try{
                $source = (& w32tm.exe /query /source 2>&1 | Out-String).Trim()
                $out['TimeSource'] = if($source){$source}else{'UNKNOWN'}
            }catch{ $out['TimeSource']='UNKNOWN' }

            try{
                $since=(Get-Date).AddHours(-24)
                $criticalIds=@(1311,1566,1865,1925,2042,2087,2088,4013,4015,2213,4012)
                $events=@(Get-WinEvent -FilterHashtable @{LogName='System';StartTime=$since;Level=1,2,3} -ErrorAction SilentlyContinue |
                    Where-Object {$criticalIds -contains $_.Id})
                $out['CriticalEventCount']=$events.Count
            }catch{ $out['CriticalEventCount']=-1 }

            [pscustomobject]$out
        }

        return [pscustomobject]@{
            Query='SUCCESS'
            NetlogonStatus=[string]$result.Netlogon
            DFSRStatus=[string]$result.DFSR
            W32TimeStatus=[string]$result.W32Time
            SYSVOLShare=[string]$result.SYSVOLShare
            NETLOGONShare=[string]$result.NETLOGONShare
            FullBuildVersion=[string]$result.FullBuildVersion
            TimeSource=[string]$result.TimeSource
            CriticalEventCount=[int]$result.CriticalEventCount
        }
    }
    catch{
        Write-AppLog "Enterprise remote probe failed for '${ComputerName}': $($_.Exception.Message)" WARN
        return [pscustomobject]@{
            Query='FAILED'; NetlogonStatus='UNAVAILABLE'; DFSRStatus='UNAVAILABLE'; W32TimeStatus='UNAVAILABLE'
            SYSVOLShare='UNKNOWN'; NETLOGONShare='UNKNOWN'; FullBuildVersion='UNAVAILABLE'; TimeSource='UNKNOWN'; CriticalEventCount=-1
        }
    }
}

function Test-DCLocatorAndDNS {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $DCRecord
    )

    $dns='UNKNOWN'
    $locator='UNKNOWN'
    $locatedDC=''
    $locatorDetail=''

    # -------------------------------------------------------------------------
    # DNS: validate that the selected DC FQDN resolves.
    # -------------------------------------------------------------------------
    try{
        $a = @(
            Resolve-DnsName `
                -Name $DCRecord.DCFqdn `
                -Type A `
                -ErrorAction Stop
        )

        if($a.Count -gt 0){
            $dns='OK'
        }else{
            $dns='FAIL'
        }
    }
    catch{
        $dns='FAIL'
        Write-AppLog (
            "DNS resolution failed for DC='{0}'; Domain='{1}'; Error='{2}'." -f
            $DCRecord.DCFqdn,
            $DCRecord.Domain,
            $_.Exception.Message
        ) WARN
    }

    # -------------------------------------------------------------------------
    # DC Locator:
    #
    # Use the ActiveDirectory module discovery API instead of parsing localized
    # NLTEST command output. Get-ADDomainController -Discover ultimately relies
    # on domain-controller discovery but gives us structured objects and avoids
    # command-line/localization ambiguity.
    # -------------------------------------------------------------------------
    try{
        $discovered = Get-ADDomainController `
            -Discover `
            -DomainName ([string]$DCRecord.Domain) `
            -Writable `
            -ErrorAction Stop

        if($null -ne $discovered){
            $locator='OK'
            $locatedDC=[string](@($discovered.HostName)[0])
            $locatorDetail="Discovered=$locatedDC"
        }else{
            $locator='FAIL'
            $locatorDetail='No writable DC returned.'
        }
    }
    catch{
        $locator='FAIL'
        $locatorDetail=$_.Exception.Message

        Write-AppLog (
            "DC Locator discovery failed for Domain='{0}'; InventoryDC='{1}'; Error='{2}'." -f
            $DCRecord.Domain,
            $DCRecord.DCFqdn,
            $_.Exception.Message
        ) WARN
    }

    [pscustomobject]@{
        DNSStatus       = $dns
        DCLocatorStatus = $locator
        LocatedDC       = $locatedDC
        LocatorDetail   = $locatorDetail
    }
}


function Get-OverallHealth {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$DCRecord)

    $critical = $false
    $warning = $false

    if($DCRecord.NetlogonStatus -ne 'Running'){ $critical=$true }
    if($DCRecord.SYSVOLShare -ne 'OK' -or $DCRecord.NETLOGONShare -ne 'OK'){ $critical=$true }
    if($DCRecord.ReplicationStatus -eq 'FAIL'){ $critical=$true }

    # DNS is foundational to AD and remains a critical condition.
    if($DCRecord.DNSStatus -eq 'FAIL'){ $critical=$true }

    # A standalone Locator failure is degraded. Escalate to critical when it is
    # corroborated by another domain-controller advertising/availability fault.
    if($DCRecord.DCLocatorStatus -eq 'FAIL'){
        if(
            $DCRecord.NetlogonStatus -ne 'Running' -or
            $DCRecord.SYSVOLShare -ne 'OK' -or
            $DCRecord.NETLOGONShare -ne 'OK' -or
            $DCRecord.DNSStatus -eq 'FAIL'
        ){
            $critical=$true
        }else{
            $warning=$true
        }
    }

    if($DCRecord.DFSRStatus -ne 'Running' -or $DCRecord.W32TimeStatus -ne 'Running'){ $warning=$true }
    if($DCRecord.ReplicationStatus -in @('WARN','UNKNOWN','QUERY FAILED')){ $warning=$true }

    $deltaSeconds=Convert-ReplSummaryDeltaToSortableSeconds -DeltaText $DCRecord.MaxReplicationDelta
    if($deltaSeconds -ge $script:HealthPolicy.ReplicationCriticalSeconds){
        $critical=$true
    }elseif($deltaSeconds -ge $script:HealthPolicy.ReplicationWarningSeconds){
        $warning=$true
    }

    if($DCRecord.CriticalEventCount -ge $script:HealthPolicy.EventCriticalCount){
        $critical=$true
    }elseif($DCRecord.CriticalEventCount -ge $script:HealthPolicy.EventWarningCount){
        $warning=$true
    }
    if($DCRecord.RemoteQuery -ne 'SUCCESS'){ $warning=$true }

    if($critical){ return 'CRITICAL' }
    if($warning){ return 'DEGRADED' }
    return 'HEALTHY'
}

function Update-BasicPreFlightInventory {
    [CmdletBinding()]
    param()

    $fsmo = Get-FSMORoleMap
    $count = $script:DCInventory.Count
    $i = 0

    foreach($dc in @($script:DCInventory)){
        $i++
        Set-AppStatus "Basic pre-flight ${i}/${count}: $($dc.DCFqdn)"
        Set-CurrentOperation "Probe: $($dc.DCFqdn)"
        [Windows.Forms.Application]::DoEvents()

        $probe = Invoke-RemoteDCEnterpriseProbe -ComputerName $dc.DCFqdn
        $dc.RemoteQuery = $probe.Query
        $dc.NetlogonStatus = $probe.NetlogonStatus
        $dc.NetlogonQuery = $probe.Query
        $dc.DFSRStatus = $probe.DFSRStatus
        $dc.W32TimeStatus = $probe.W32TimeStatus
        $dc.SYSVOLShare = $probe.SYSVOLShare
        $dc.NETLOGONShare = $probe.NETLOGONShare

        if($probe.FullBuildVersion -ne 'UNAVAILABLE'){
            $dc.FullBuildVersion = $probe.FullBuildVersion
        }

        $dc.TimeSource = $probe.TimeSource
        $dc.CriticalEventCount = $probe.CriticalEventCount

        $short = ($dc.DCFqdn -split '\.')[0].ToUpperInvariant()
        $dc.FSMORoles = if($fsmo.ContainsKey($short)){ (@($fsmo[$short]) -join ',') }else{ '' }

        $network = Test-DCLocatorAndDNS -DCRecord $dc
        $dc.DNSStatus = $network.DNSStatus
        $dc.DCLocatorStatus = $network.DCLocatorStatus
        $dc.DCLocatorDC = $network.LocatedDC
        $dc.DCLocatorDetail = $network.LocatorDetail

        # Replication remains explicitly separate. NOT TESTED is not penalized.
        $dc.OverallHealth = Get-OverallHealth -DCRecord $dc
    }

    Write-AppLog "Basic pre-flight completed across $count DC(s)." SUCCESS
}

function Update-EnterpriseHealthInventory {
    [CmdletBinding()]
    param()

    $fsmo = Get-FSMORoleMap
    $count=$script:DCInventory.Count; $i=0

    foreach($dc in @($script:DCInventory)){
        $i++
        Set-AppStatus "Enterprise pre-flight ${i}/${count}: $($dc.DCFqdn)"
        Set-CurrentOperation "Probe: $($dc.DCFqdn)"
        [Windows.Forms.Application]::DoEvents()

        $probe=Invoke-RemoteDCEnterpriseProbe -ComputerName $dc.DCFqdn
        $dc.RemoteQuery=$probe.Query
        $dc.NetlogonStatus=$probe.NetlogonStatus
        $dc.DFSRStatus=$probe.DFSRStatus
        $dc.W32TimeStatus=$probe.W32TimeStatus
        $dc.SYSVOLShare=$probe.SYSVOLShare
        $dc.NETLOGONShare=$probe.NETLOGONShare
        if($probe.FullBuildVersion -ne 'UNAVAILABLE'){ $dc.FullBuildVersion=$probe.FullBuildVersion }
        $dc.TimeSource=$probe.TimeSource
        $dc.CriticalEventCount=$probe.CriticalEventCount

        $short=($dc.DCFqdn -split '\.')[0].ToUpperInvariant()
        $dc.FSMORoles=if($fsmo.ContainsKey($short)){(@($fsmo[$short]) -join ',')}else{''}

        $network=Test-DCLocatorAndDNS -DCRecord $dc
        $dc.DNSStatus=$network.DNSStatus
        $dc.DCLocatorStatus=$network.DCLocatorStatus
        $dc.DCLocatorDC=$network.LocatedDC
        $dc.DCLocatorDetail=$network.LocatorDetail
    }

    Update-ReplicationPreFlightInventory

    foreach($dc in @($script:DCInventory)){
        $dc.OverallHealth=Get-OverallHealth -DCRecord $dc
    }
}

function New-HealthSnapshot {
    [CmdletBinding()]
    param()

    $snapshot=@{}
    foreach($dc in @($script:DCInventory)){
        $snapshot[$dc.DCFqdn]=[pscustomobject]@{
            ReplicationStatus=$dc.ReplicationStatus
            ReplicationFailures=$dc.ReplicationFailures
            MaxReplicationDelta=$dc.MaxReplicationDelta
            OverallHealth=$dc.OverallHealth
        }
    }
    return $snapshot
}

function Write-PrePostReplicationComparison {
    param([hashtable]$Before)
    foreach($dc in @($script:DCInventory)){
        if($Before.ContainsKey($dc.DCFqdn)){
            $b=$Before[$dc.DCFqdn]
            Write-AppLog ("Pre/Post: DC='{0}'; Replication='{1}' -> '{2}'; Failures={3} -> {4}; Delta='{5}' -> '{6}'; Health='{7}' -> '{8}'." -f
                $dc.DCFqdn,$b.ReplicationStatus,$dc.ReplicationStatus,$b.ReplicationFailures,$dc.ReplicationFailures,$b.MaxReplicationDelta,$dc.MaxReplicationDelta,$b.OverallHealth,$dc.OverallHealth) INFO
        }
    }
}

# =====================================================================================
# SHOWREPL CSV PARSING
# =====================================================================================
function Resolve-ShowReplColumns {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$PropertyNames
    )

    function Get-FirstPropertyMatch {
        param([string]$Pattern)

        return (
            $PropertyNames |
            Where-Object { $_ -match $Pattern } |
            Select-Object -First 1
        )
    }

    [pscustomobject]@{
        Failures = Get-FirstPropertyMatch '(?i)^(number\s+of\s+failures|n[uú]mero\s+de\s+falhas|n£mero\s+de\s+falhas)$'
        LastSuccess = Get-FirstPropertyMatch '(?i)^(last\s+success\s+time|hor[aá]rio\s+do\s+[uú]ltimo\s+(e[xê]ito|sucesso))$'
        LastStatus = Get-FirstPropertyMatch '(?i)^(last\s+failure\s+status|status\s+da\s+[uú]ltima\s+falha)$'
        NCContext = Get-FirstPropertyMatch '(?i)^(naming\s+context|contexto\s+de\s+nomenclatura)$'
        SourceDSA = Get-FirstPropertyMatch '(?i)^(source\s+dsa|dsa\s+de\s+origem)$'
        DestinationDSA = Get-FirstPropertyMatch '(?i)^(destination\s+dsa|dsa\s+de\s+destino)$'
    }
}

# =====================================================================================
# OPERATIONS
# =====================================================================================
function Invoke-SelectedDCSynchronization {
    if($script:IsBusy){
        return
    }

    $targets = @(Get-CheckedDCRecords)

    if($targets.Count -eq 0){
        Show-AppMessage 'Select at least one Domain Controller in the grid.' 'Replication Synchronization' Warning
        return
    }

    $answer = [Windows.Forms.MessageBox]::Show(
        "Force replication on $($targets.Count) selected Domain Controller(s)?`r`n`r`nThis will execute repadmin /syncall with enterprise/forest scope switches.",
        'Confirm Forced Replication',
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Warning,
        [Windows.Forms.MessageBoxDefaultButton]::Button2
    )

    if($answer -ne [Windows.Forms.DialogResult]::Yes){
        return
    }

    $script:IsBusy = $true
    $script:CancelRequested = $false

    try{
        Write-Section 'Forced Replication - repadmin /syncall'
        $preSyncSnapshot=New-HealthSnapshot
        Set-ProgressState -Value 0 -Maximum $targets.Count

        $index = 0
        $success = 0
        $warning = 0
        $failed = 0

        foreach($dc in $targets){
            if($script:CancelRequested){
                Write-AppLog 'Replication synchronization cancelled by operator.' WARN
                Set-AppStatus 'Operation cancelled.'
                break
            }

            $index++
            Set-CurrentOperation ("Sync: $($dc.DCFqdn) ($index/$($targets.Count))")
            Set-ProgressState -Value $index -Maximum $targets.Count
            Set-AppStatus "Synchronizing $($dc.DCFqdn)..."
            [Windows.Forms.Application]::DoEvents()

            $result = Invoke-ExternalProcess `
                -FilePath $script:RepadminPath `
                -Arguments @(
                    '/syncall',
                    $dc.DCFqdn,
                    '/A',
                    '/e',
                    '/P',
                    '/d',
                    '/q'
                )

            $summary = Write-ExternalResult `
                -Command ("repadmin /syncall {0}" -f $dc.DCFqdn) `
                -Result $result

            switch($summary.Verdict){
                'OK'   { $success++ }
                'WARN' { $warning++ }
                default { $failed++ }
            }
        }

        if(-not $script:CancelRequested){
            Write-AppLog ("Replication synchronization completed. Success={0}; Warning={1}; Failed={2}." -f
                $success,$warning,$failed) $(if($failed -gt 0){'ERROR'}elseif($warning -gt 0){'WARN'}else{'SUCCESS'})

            Set-AppStatus 'Refreshing replication health after synchronization...'
            Start-Sleep -Seconds 2
            Update-ReplicationPreFlightInventory
            foreach($dc in @($script:DCInventory)){ $dc.OverallHealth=Get-OverallHealth -DCRecord $dc }
            Write-PrePostReplicationComparison -Before $preSyncSnapshot
            Refresh-DCGrid -Filter $txtFilter.Text
            Set-AppStatus 'Replication synchronization and post-flight completed.'

            Show-AppMessage (
                "Replication synchronization completed.`r`n`r`n" +
                "Success: $success`r`n" +
                "Warning: $warning`r`n" +
                "Failed: $failed"
            ) 'Replication Synchronization' $(if($failed -gt 0){'Warning'}else{'Information'})
        }
    }
    catch{
        Write-AppLog "Replication synchronization failed: $($_.Exception.Message)" ERROR
        Set-AppStatus 'Replication synchronization failed.'
        Show-AppMessage "Replication synchronization failed:`r`n`r`n$($_.Exception.Message)" 'Replication Synchronization' Error
    }
    finally{
        $script:IsBusy = $false
        $script:CancelRequested = $false
        Set-CurrentOperation 'Current operation: none'
        Set-ProgressState 0 1
    }
}

function Invoke-ADForestHealthCheck {
    if($script:IsBusy){
        return
    }

    $targets = @(Get-CheckedDCRecords)

    if($targets.Count -eq 0){
        Show-AppMessage 'Select at least one Domain Controller in the grid.' 'AD Forest Health Check' Warning
        return
    }

    $script:IsBusy = $true
    $script:CancelRequested = $false

    try{
        Write-Section 'AD Forest Health Check'
        Write-AppLog ("Selected DCs: {0}" -f (($targets | ForEach-Object {$_.DCFqdn}) -join ', ')) INFO
        Set-AppStatus 'Refreshing Basic Pre-Flight state...'
        Update-BasicPreFlightInventory

        Set-AppStatus 'Refreshing Replication Pre-Flight state...'
        Update-ReplicationPreFlightInventory

        foreach($dc in @($script:DCInventory)){
            $dc.OverallHealth=Get-OverallHealth -DCRecord $dc
        }

        Refresh-DCGrid -Filter $txtFilter.Text

        # ---------------------------------------------------------------------
        # KCC per selected DC
        # ---------------------------------------------------------------------
        Write-Section 'KCC - repadmin /kcc'

        Set-ProgressState 0 $targets.Count
        $index = 0

        foreach($dc in $targets){
            if($script:CancelRequested){
                Set-AppStatus 'Health check cancelled.'
                return
            }

            $index++
            Set-CurrentOperation ("KCC: $($dc.DCFqdn) ($index/$($targets.Count))")
            Set-ProgressState $index $targets.Count
            [Windows.Forms.Application]::DoEvents()

            $result = Invoke-ExternalProcess `
                -FilePath $script:RepadminPath `
                -Arguments @('/kcc',$dc.DCFqdn)

            [void](Write-ExternalResult `
                -Command ("repadmin /kcc {0}" -f $dc.DCFqdn) `
                -Result $result)
        }

        if($script:CancelRequested){
            return
        }

        # ---------------------------------------------------------------------
        # Replication summary
        # ---------------------------------------------------------------------
        Write-Section 'Replication Summary - repadmin /replsummary'

        $replSummary = Invoke-ExternalProcess `
            -FilePath $script:RepadminPath `
            -Arguments @('/replsummary')

        [void](Write-ExternalResult -Command 'repadmin /replsummary' -Result $replSummary)

        # ---------------------------------------------------------------------
        # SHOWREPL
        # ---------------------------------------------------------------------
        Write-Section 'Replication Detail - repadmin /showrepl * /csv'

        $showRepl = Invoke-ExternalProcess `
            -FilePath $script:RepadminPath `
            -Arguments @('/showrepl','*','/csv')

        $showReplResult = Write-ExternalResult `
            -Command 'repadmin /showrepl * /csv' `
            -Result $showRepl

        if(-not [string]::IsNullOrWhiteSpace($showReplResult.Output)){
            try{
                $replRows = @($showReplResult.Output | ConvertFrom-Csv -ErrorAction Stop)

                if($replRows.Count -gt 0){
                    $columns = Resolve-ShowReplColumns `
                        -PropertyNames @($replRows[0].PSObject.Properties.Name)

                    if($columns.Failures){
                        $issues = @(
                            $replRows |
                            Where-Object {
                                $failureValue = 0
                                [void][int]::TryParse(
                                    (("$($_.($columns.Failures))") -replace '[^\d]',''),
                                    [ref]$failureValue
                                )

                                $lastStatus = if($columns.LastStatus){
                                    "$($_.($columns.LastStatus))"
                                }else{
                                    ''
                                }

                                ($failureValue -gt 0) -or
                                (
                                    -not [string]::IsNullOrWhiteSpace($lastStatus) -and
                                    $lastStatus -notmatch '(?i)\b0\b|success|passed|ok|êxito|sucesso'
                                )
                            }
                        )

                        if($issues.Count -gt 0){
                            Write-AppLog "repadmin /showrepl detected $($issues.Count) potential replication issue(s)." WARN

                            foreach($issue in ($issues | Select-Object -First 25)){
                                $source = if($columns.SourceDSA){ "$($issue.($columns.SourceDSA))" }else{'UNKNOWN'}
                                $destination = if($columns.DestinationDSA){ "$($issue.($columns.DestinationDSA))" }else{'UNKNOWN'}
                                $nc = if($columns.NCContext){ "$($issue.($columns.NCContext))" }else{'UNKNOWN'}

                                Write-AppLog (
                                    "Replication issue: Source='{0}'; Destination='{1}'; NC='{2}'; Failures='{3}'." -f
                                    $source,$destination,$nc,$issue.($columns.Failures)
                                ) WARN
                            }
                        }
                        else{
                            Write-AppLog 'repadmin /showrepl detected no replication failures.' SUCCESS
                        }
                    }
                    else{
                        Write-AppLog 'Could not resolve the showrepl failures column for the current locale.' WARN
                    }
                }
            }
            catch{
                Write-AppLog "showrepl CSV parsing failed: $($_.Exception.Message)" WARN
            }
        }

        # ---------------------------------------------------------------------
        # Replication queue
        # ---------------------------------------------------------------------
        Write-Section 'Replication Queue - repadmin /queue *'

        $queue = Invoke-ExternalProcess `
            -FilePath $script:RepadminPath `
            -Arguments @('/queue','*')

        [void](Write-ExternalResult -Command 'repadmin /queue *' -Result $queue)

        # ---------------------------------------------------------------------
        # ISTG
        # ---------------------------------------------------------------------
        Write-Section 'ISTG - repadmin /istg * /verbose'

        $istg = Invoke-ExternalProcess `
            -FilePath $script:RepadminPath `
            -Arguments @('/istg','*','/verbose')

        [void](Write-ExternalResult -Command 'repadmin /istg * /verbose' -Result $istg)

        # ---------------------------------------------------------------------
        # DCDIAG focused tests
        # ---------------------------------------------------------------------
        Write-Section 'DCDIAG Focused Tests'

        $dcdiagTests = @(
            [pscustomobject]@{
                Name='Replications'
                Args=@('/test:Replications','/v')
            },
            [pscustomobject]@{
                Name='Services'
                Args=@('/test:Services','/v')
            },
            [pscustomobject]@{
                Name='Connectivity'
                Args=@('/test:Connectivity','/v')
            },
            [pscustomobject]@{
                Name='DNS /DnsBasic'
                Args=@('/test:DNS','/DnsBasic','/v')
            }
        )

        foreach($test in $dcdiagTests){
            if($script:CancelRequested){
                return
            }

            Set-CurrentOperation "DCDIAG: $($test.Name)"
            [Windows.Forms.Application]::DoEvents()

            $dcdiag = Invoke-ExternalProcess `
                -FilePath $script:DcdiagPath `
                -Arguments $test.Args

            $result = Write-ExternalResult `
                -Command ("dcdiag {0}" -f $test.Name) `
                -Result $dcdiag

            $passPattern = '(?i)passed\s+test|passou\s+no\s+teste|teste\s+aprovado'
            $failPattern = '(?i)failed\s+test|falhou\s+no\s+teste'

            if($result.Output -match $failPattern){
                Write-AppLog "dcdiag '$($test.Name)' reported FAILED." ERROR
            }
            elseif($result.Output -match $passPattern){
                Write-AppLog "dcdiag '$($test.Name)' reported PASSED." SUCCESS
            }
            else{
                Write-AppLog "dcdiag '$($test.Name)' result could not be classified from localized output." WARN
            }
        }

        # ---------------------------------------------------------------------
        # Global Catalog audit across the complete forest
        # ---------------------------------------------------------------------
        Write-Section 'Global Catalog Audit'

        $globalCatalogs = @(
            $script:DCInventory |
            Where-Object {$_.GlobalCatalog}
        )

        if($globalCatalogs.Count -gt 0){
            Write-AppLog "Global Catalog servers found: $($globalCatalogs.Count)." SUCCESS

            foreach($gc in $globalCatalogs){
                Write-AppLog ("GC: {0} | Domain: {1} | Site: {2} | IPv4: {3}" -f
                    $gc.DCFqdn,$gc.Domain,$gc.Site,$gc.IPv4) INFO
            }
        }
        else{
            Write-AppLog 'No Global Catalog servers were discovered in the forest.' ERROR
        }

        Write-Section 'Health Check Complete'
        Write-AppLog 'AD forest health check completed.' SUCCESS
        Set-AppStatus 'Health check completed.'

        Show-AppMessage (
            "AD forest health check completed.`r`n`r`n" +
            "Selected DCs: $($targets.Count)`r`n" +
            "Forest domains: $(@($script:Forest.Domains).Count)`r`n" +
            "Global Catalogs: $($globalCatalogs.Count)`r`n`r`n" +
            "Review the runtime log for detailed results."
        ) 'AD Forest Health Check' Information
    }
    catch{
        Write-AppLog "Health check failed: $($_.Exception.Message)" ERROR
        Set-AppStatus 'Health check failed.'
        Show-AppMessage "Health check failed:`r`n`r`n$($_.Exception.Message)" 'AD Forest Health Check' Error
    }
    finally{
        $script:IsBusy = $false
        $script:CancelRequested = $false
        Set-CurrentOperation 'Current operation: none'
        Set-ProgressState 0 1
    }
}

# =====================================================================================
# GUI
# =====================================================================================
$form = New-Object Windows.Forms.Form
$form.Text = "$($script:AppName) - v$($script:AppVersion)"
$form.Size = New-Object Drawing.Size(1240,820)
$form.MinimumSize = New-Object Drawing.Size(1050,700)
$form.StartPosition = 'CenterScreen'

$main = New-Object Windows.Forms.TableLayoutPanel
$main.Dock='Fill'
$main.Padding=New-Object Windows.Forms.Padding(10)
$main.ColumnCount=1
$main.RowCount=7

$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',52)))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',48)))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))

$form.Controls.Add($main)

# Header / filter
$pHeader = New-Object Windows.Forms.TableLayoutPanel
$pHeader.Dock='Fill'
$pHeader.AutoSize=$true
$pHeader.ColumnCount=10
$pHeader.RowCount=1

$pHeader.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pHeader.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
$pHeader.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pHeader.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pHeader.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pHeader.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pHeader.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pHeader.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pHeader.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pHeader.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))

$lblFilter = New-Object Windows.Forms.Label
$lblFilter.Text='Filter all columns:'
$lblFilter.AutoSize=$true
$lblFilter.Anchor='Left'
$pHeader.Controls.Add($lblFilter,0,0)

$txtFilter = New-Object Windows.Forms.TextBox
$txtFilter.Dock='Fill'
$pHeader.Controls.Add($txtFilter,1,0)

$btnClearFilter = New-Object Windows.Forms.Button
$btnClearFilter.Text='Clear Filter'
$btnClearFilter.Width=90
$pHeader.Controls.Add($btnClearFilter,2,0)

$btnSelectAll = New-Object Windows.Forms.Button
$btnSelectAll.Text='Select All'
$btnSelectAll.Width=85
$pHeader.Controls.Add($btnSelectAll,3,0)

$btnSelectNone = New-Object Windows.Forms.Button
$btnSelectNone.Text='Select None'
$btnSelectNone.Width=85
$pHeader.Controls.Add($btnSelectNone,4,0)

$btnRefresh = New-Object Windows.Forms.Button
$btnRefresh.Text='Refresh Forest'
$btnRefresh.Width=100
$pHeader.Controls.Add($btnRefresh,5,0)

$btnExport = New-Object Windows.Forms.Button
$btnExport.Text='Export Inventory'
$btnExport.Width=105
$pHeader.Controls.Add($btnExport,6,0)

$btnExportJson = New-Object Windows.Forms.Button
$btnExportJson.Text='Export JSON'
$btnExportJson.Width=90
$pHeader.Controls.Add($btnExportJson,7,0)

$btnBasicPreFlight = New-Object Windows.Forms.Button
$btnBasicPreFlight.Text='Run Basic Pre-Flight'
$btnBasicPreFlight.Width=120
$pHeader.Controls.Add($btnBasicPreFlight,8,0)

$btnReplicationPreFlight = New-Object Windows.Forms.Button
$btnReplicationPreFlight.Text='Replication Pre-Flight'
$btnReplicationPreFlight.Width=125
$pHeader.Controls.Add($btnReplicationPreFlight,9,0)

$main.Controls.Add($pHeader,0,0)

# DC inventory
$listDC = New-Object Windows.Forms.ListView
$listDC.Dock='Fill'
$listDC.View='Details'
$listDC.CheckBoxes=$true
$listDC.FullRowSelect=$true
$listDC.GridLines=$true
$listDC.HideSelection=$false

[void]$listDC.Columns.Add('Domain',190)
[void]$listDC.Columns.Add('DC FQDN',250)
[void]$listDC.Columns.Add('IPv4',105)
[void]$listDC.Columns.Add('Site',130)
[void]$listDC.Columns.Add('GC',50)
[void]$listDC.Columns.Add('Writable',70)
[void]$listDC.Columns.Add('RODC',55)
[void]$listDC.Columns.Add('Operating System',180)
[void]$listDC.Columns.Add('Full Build Version',135)
[void]$listDC.Columns.Add('Netlogon Status',100)
[void]$listDC.Columns.Add('SYSVOL',75)
[void]$listDC.Columns.Add('NETLOGON Share',100)
[void]$listDC.Columns.Add('DFSR',75)
[void]$listDC.Columns.Add('DNS',65)
[void]$listDC.Columns.Add('DC Locator',80)
[void]$listDC.Columns.Add('W32Time',80)
[void]$listDC.Columns.Add('FSMO Roles',150)
[void]$listDC.Columns.Add('Replication Status',115)
[void]$listDC.Columns.Add('Failures',70)
[void]$listDC.Columns.Add('Total Attempts',85)
[void]$listDC.Columns.Add('Failure %',75)
[void]$listDC.Columns.Add('Max Delta',105)
[void]$listDC.Columns.Add('Events 24h',75)
[void]$listDC.Columns.Add('Overall Health',105)

$main.Controls.Add($listDC,0,1)

$lblSummary = New-Object Windows.Forms.Label
$lblSummary.AutoSize=$true
$lblSummary.Text='No DC inventory loaded.'
$main.Controls.Add($lblSummary,0,2)

# Progress / action row
$pActions = New-Object Windows.Forms.FlowLayoutPanel
$pActions.Dock='Fill'
$pActions.AutoSize=$true
$pActions.WrapContents=$true
$pActions.FlowDirection='LeftToRight'

$btnSync = New-Object Windows.Forms.Button
$btnSync.Text='Sync Selected DCs'
$btnSync.Width=135
$btnSync.Height=34
$pActions.Controls.Add($btnSync)

$btnHealth = New-Object Windows.Forms.Button
$btnHealth.Text='Health Check'
$btnHealth.Width=120
$btnHealth.Height=34
$pActions.Controls.Add($btnHealth)

$btnCancel = New-Object Windows.Forms.Button
$btnCancel.Text='Cancel'
$btnCancel.Width=90
$btnCancel.Height=34
$pActions.Controls.Add($btnCancel)

$btnOpenLog = New-Object Windows.Forms.Button
$btnOpenLog.Text='Open Log'
$btnOpenLog.Width=90
$btnOpenLog.Height=34
$pActions.Controls.Add($btnOpenLog)

$btnSaveLog = New-Object Windows.Forms.Button
$btnSaveLog.Text='Export Log'
$btnSaveLog.Width=90
$btnSaveLog.Height=34
$pActions.Controls.Add($btnSaveLog)

$main.Controls.Add($pActions,0,3)

# Runtime log
$txtRuntimeLog = New-Object Windows.Forms.TextBox
$txtRuntimeLog.Dock='Fill'
$txtRuntimeLog.Multiline=$true
$txtRuntimeLog.ReadOnly=$true
$txtRuntimeLog.ScrollBars='Both'
$txtRuntimeLog.WordWrap=$false
$txtRuntimeLog.Font=New-Object Drawing.Font('Consolas',8.5)
$script:txtRuntimeLog=$txtRuntimeLog

$main.Controls.Add($txtRuntimeLog,0,4)

# Current operation + progress
$pProgress = New-Object Windows.Forms.TableLayoutPanel
$pProgress.Dock='Fill'
$pProgress.AutoSize=$true
$pProgress.ColumnCount=2
$pProgress.RowCount=1
$pProgress.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pProgress.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))

$lblCurrent = New-Object Windows.Forms.Label
$lblCurrent.AutoSize=$true
$lblCurrent.Text='Current operation: none'
$script:statusCurrent=$lblCurrent
$pProgress.Controls.Add($lblCurrent,0,0)

$progress = New-Object Windows.Forms.ProgressBar
$progress.Dock='Fill'
$progress.Minimum=0
$progress.Maximum=1
$progress.Value=0
$script:progress=$progress
$pProgress.Controls.Add($progress,1,0)

$main.Controls.Add($pProgress,0,5)

# Status strip
$statusStrip = New-Object Windows.Forms.StatusStrip

$statusMain = New-Object Windows.Forms.ToolStripStatusLabel
$statusMain.Spring=$true
$statusMain.Text='Ready'
$script:statusMain=$statusMain
[void]$statusStrip.Items.Add($statusMain)

$statusForest = New-Object Windows.Forms.ToolStripStatusLabel
$statusForest.Text='Forest: -'
[void]$statusStrip.Items.Add($statusForest)

$statusLog = New-Object Windows.Forms.ToolStripStatusLabel
$statusLog.Text="Log: $([IO.Path]::GetFileName($script:LogFile))"
[void]$statusStrip.Items.Add($statusLog)

$main.Controls.Add($statusStrip,0,6)

# =====================================================================================
# GUI DATA / FILTER
# =====================================================================================
function Get-SortPropertyByColumnIndex {
    param([Parameter(Mandatory=$true)][int]$ColumnIndex)
    switch($ColumnIndex){
        0 {'Domain'}; 1 {'DCFqdn'}; 2 {'IPv4'}; 3 {'Site'}; 4 {'GlobalCatalog'}; 5 {'Writable'}; 6 {'ReadOnly'}
        7 {'OperatingSystem'}; 8 {'FullBuildVersion'}; 9 {'NetlogonStatus'}; 10 {'SYSVOLShare'}; 11 {'NETLOGONShare'}
        12 {'DFSRStatus'}; 13 {'DNSStatus'}; 14 {'DCLocatorStatus'}; 15 {'W32TimeStatus'}; 16 {'FSMORoles'}
        17 {'ReplicationStatus'}; 18 {'ReplicationFailures'}; 19 {'ReplicationTotal'}; 20 {'ReplicationFailurePct'}
        21 {'MaxReplicationDelta'}; 22 {'CriticalEventCount'}; 23 {'OverallHealth'}; default {'Domain'}
    }
}

function Refresh-DCGrid {
    param(
        [string]$Filter = ''
    )

    $checkedKeys = @{}

    foreach($item in $listDC.Items){
        if($item.Checked){
            $checkedKeys[[string]$item.Tag.DCFqdn] = $true
        }
    }

    $rows = @(
        $script:DCInventory |
        Where-Object {
            [string]::IsNullOrWhiteSpace($Filter) -or
            $_.Domain.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.DCFqdn.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.IPv4.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.Site.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            ([string]$_.GlobalCatalog).IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            ([string]$_.Writable).IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            ([string]$_.ReadOnly).IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.OperatingSystem.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.FullBuildVersion.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.NetlogonStatus.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.NetlogonQuery.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.SYSVOLShare.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.NETLOGONShare.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.DFSRStatus.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.DNSStatus.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.DCLocatorStatus.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.DCLocatorDC.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.DCLocatorDetail.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.W32TimeStatus.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.FSMORoles.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.ReplicationStatus.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            ([string]$_.ReplicationFailures).IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            ([string]$_.ReplicationTotal).IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            ([string]$_.ReplicationFailurePct).IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.MaxReplicationDelta.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.ReplicationError.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            ([string]$_.CriticalEventCount).IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.OverallHealth.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0
        }
    )

    if($script:SortAscending){
        $rows = @($rows | Sort-Object -Property $script:SortProperty)
    }else{
        $rows = @($rows | Sort-Object -Property $script:SortProperty -Descending)
    }

    $script:DisplayedDCs = $rows

    $listDC.BeginUpdate()

    try{
        $listDC.Items.Clear()

        foreach($row in $rows){
            $item = New-Object Windows.Forms.ListViewItem($row.Domain)
            [void]$item.SubItems.Add($row.DCFqdn)
            [void]$item.SubItems.Add($row.IPv4)
            [void]$item.SubItems.Add($row.Site)
            [void]$item.SubItems.Add([string]$row.GlobalCatalog)
            [void]$item.SubItems.Add([string]$row.Writable)
            [void]$item.SubItems.Add([string]$row.ReadOnly)
            [void]$item.SubItems.Add($row.OperatingSystem)
            [void]$item.SubItems.Add($row.FullBuildVersion)
            [void]$item.SubItems.Add($row.NetlogonStatus)
            [void]$item.SubItems.Add($row.SYSVOLShare)
            [void]$item.SubItems.Add($row.NETLOGONShare)
            [void]$item.SubItems.Add($row.DFSRStatus)
            [void]$item.SubItems.Add($row.DNSStatus)
            [void]$item.SubItems.Add($row.DCLocatorStatus)
            [void]$item.SubItems.Add($row.W32TimeStatus)
            [void]$item.SubItems.Add($row.FSMORoles)
            [void]$item.SubItems.Add($row.ReplicationStatus)
            [void]$item.SubItems.Add([string]$row.ReplicationFailures)
            [void]$item.SubItems.Add([string]$row.ReplicationTotal)
            [void]$item.SubItems.Add([string]$row.ReplicationFailurePct)
            [void]$item.SubItems.Add($row.MaxReplicationDelta)
            [void]$item.SubItems.Add([string]$row.CriticalEventCount)
            [void]$item.SubItems.Add($row.OverallHealth)
            $item.Tag=$row

            if($checkedKeys.ContainsKey($row.DCFqdn)){
                $item.Checked=$true
            }
            elseif($checkedKeys.Count -eq 0){
                $item.Checked=$true
            }

            [void]$listDC.Items.Add($item)
        }
    }
    finally{
        $listDC.EndUpdate()
    }

    $selectedCount = @(Get-CheckedDCRecords).Count

    $lblSummary.Text = (
        "Forest: {0} | Domains: {1} | DCs: {2} | Writable: {3} | RODC: {4} | Selected: {5} | Displayed: {6}" -f
        $script:Forest.Name,
        @($script:Forest.Domains).Count,
        $script:DCInventory.Count,
        @($script:DCInventory | Where-Object {$_.Writable}).Count,
        @($script:DCInventory | Where-Object {$_.ReadOnly}).Count,
        $selectedCount,
        $rows.Count
    )
}

function Refresh-ForestInventory {
    if($script:IsBusy){
        return
    }

    $script:IsBusy=$true

    try{
        Set-AppStatus 'Discovering Active Directory forest...'
        Set-CurrentOperation 'Discovery'
        [Windows.Forms.Application]::DoEvents()

        Initialize-Dependencies

        $script:DCInventory=@(Get-ForestDCInventory)

        # Inventory-only by design. Health probes are explicitly operator initiated.
        Refresh-DCGrid -Filter $txtFilter.Text

        $statusForest.Text="Forest: $($script:Forest.Name)"

        Write-AppLog 'Forest inventory loaded. Basic health checks are NOT TESTED until explicitly requested.' INFO

        Write-AppLog (
            "Forest discovery completed. Forest='{0}'; Domains={1}; DCs={2}; Writable={3}; RODC={4}." -f
            $script:Forest.Name,
            @($script:Forest.Domains).Count,
            $script:DCInventory.Count,
            @($script:DCInventory | Where-Object {$_.Writable}).Count,
            @($script:DCInventory | Where-Object {$_.ReadOnly}).Count
        ) SUCCESS

        Set-AppStatus 'Forest inventory loaded. Run Basic Pre-Flight or Replication Pre-Flight when desired.'
    }
    catch{
        Write-AppLog "Forest discovery failed: $($_.Exception.Message)" ERROR
        Set-AppStatus 'Forest discovery failed.'
        Show-AppMessage "Forest discovery failed:`r`n`r`n$($_.Exception.Message)" 'Forest Discovery' Error
    }
    finally{
        $script:IsBusy=$false
        Set-CurrentOperation 'Current operation: none'
    }
}

# =====================================================================================
# GUI EVENTS
# =====================================================================================
$txtFilter.Add_TextChanged({
    Refresh-DCGrid -Filter $txtFilter.Text
})

$btnClearFilter.Add_Click({
    $txtFilter.Clear()
})

$btnSelectAll.Add_Click({
    foreach($item in $listDC.Items){
        $item.Checked=$true
    }
    Refresh-DCGrid -Filter $txtFilter.Text
})

$btnSelectNone.Add_Click({
    foreach($item in $listDC.Items){
        $item.Checked=$false
    }
    $lblSummary.Text = $lblSummary.Text -replace 'Selected:\s*\d+','Selected: 0'
})

$listDC.Add_ColumnClick({
    param($sender,$e)

    $newProperty = Get-SortPropertyByColumnIndex -ColumnIndex $e.Column

    if($script:SortProperty -eq $newProperty){
        $script:SortAscending = -not $script:SortAscending
    }else{
        $script:SortProperty = $newProperty
        $script:SortAscending = $true
    }

    Refresh-DCGrid -Filter $txtFilter.Text

    $direction = if($script:SortAscending){'ascending'}else{'descending'}
    Set-AppStatus "Sorted by '$($script:SortProperty)' ($direction)."
})

$listDC.Add_ItemChecked({
    $form.BeginInvoke([Action]{
        try{
            $selected=@(Get-CheckedDCRecords).Count
            $lblSummary.Text=$lblSummary.Text -replace 'Selected:\s*\d+',("Selected: {0}" -f $selected)
        }catch{}
    }) | Out-Null
})

$btnBasicPreFlight.Add_Click({
    if($script:IsBusy){ return }

    try{
        $script:IsBusy=$true

        if($script:DCInventory.Count -eq 0){ throw 'No DC inventory is loaded.' }

        Set-AppStatus 'Running Basic Pre-Flight...'
        Set-CurrentOperation 'Basic Pre-Flight'
        [Windows.Forms.Application]::DoEvents()

        Write-Section 'Basic Pre-Flight'
        Update-BasicPreFlightInventory
        Refresh-DCGrid -Filter $txtFilter.Text

        $healthy=@($script:DCInventory|Where-Object{$_.OverallHealth -eq 'HEALTHY'}).Count
        $degraded=@($script:DCInventory|Where-Object{$_.OverallHealth -eq 'DEGRADED'}).Count
        $critical=@($script:DCInventory|Where-Object{$_.OverallHealth -eq 'CRITICAL'}).Count

        Write-AppLog ("Basic Pre-Flight summary: Healthy={0}; Degraded={1}; Critical={2}." -f $healthy,$degraded,$critical) `
            $(if($critical -gt 0){'ERROR'}elseif($degraded -gt 0){'WARN'}else{'SUCCESS'})

        Set-AppStatus 'Basic Pre-Flight completed.'
    }
    catch{
        Write-AppLog "Basic Pre-Flight failed: $($_.Exception.Message)" ERROR
        Set-AppStatus 'Basic Pre-Flight failed.'
        Show-AppMessage "Basic Pre-Flight failed:`r`n`r`n$($_.Exception.Message)" 'Basic Pre-Flight' Error
    }
    finally{
        $script:IsBusy=$false
        Set-CurrentOperation 'Current operation: none'
    }
})

$btnReplicationPreFlight.Add_Click({
    if($script:IsBusy){
        return
    }

    try{
        $script:IsBusy=$true

        if($script:DCInventory.Count -eq 0){
            throw 'No DC inventory is loaded.'
        }

        Set-AppStatus 'Running replication pre-flight...'
        Set-CurrentOperation 'repadmin /replsummary'
        [Windows.Forms.Application]::DoEvents()

        Update-ReplicationPreFlightInventory
        foreach($dc in @($script:DCInventory)){ $dc.OverallHealth=Get-OverallHealth -DCRecord $dc }
        Refresh-DCGrid -Filter $txtFilter.Text

        Set-AppStatus 'Replication pre-flight completed.'
    }
    catch{
        Write-AppLog "Replication pre-flight failed: $($_.Exception.Message)" ERROR
        Set-AppStatus 'Replication pre-flight failed.'
        Show-AppMessage "Replication pre-flight failed:`r`n`r`n$($_.Exception.Message)" 'Replication Pre-Flight' Error
    }
    finally{
        $script:IsBusy=$false
        Set-CurrentOperation 'Current operation: none'
    }
})

$btnRefresh.Add_Click({
    Refresh-ForestInventory
})

$btnSync.Add_Click({
    Invoke-SelectedDCSynchronization
})

$btnHealth.Add_Click({
    Invoke-ADForestHealthCheck
})

$btnCancel.Add_Click({
    if($script:IsBusy){
        $script:CancelRequested=$true
        Write-AppLog 'Cancel requested by operator.' WARN
        Set-AppStatus 'Cancellation requested...'
    }
})

$btnOpenLog.Add_Click({
    try{
        Start-Process notepad.exe -ArgumentList $script:LogFile
    }
    catch{
        Show-AppMessage "Unable to open log:`r`n$($_.Exception.Message)" 'Open Log' Error
    }
})

$btnSaveLog.Add_Click({
    try{
        $dialog = New-Object Windows.Forms.SaveFileDialog
        $dialog.Filter='Log files (*.log)|*.log|Text files (*.txt)|*.txt'
        $dialog.FileName="ADForestHealth-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss')

        if($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){
            Copy-Item -LiteralPath $script:LogFile -Destination $dialog.FileName -Force
            Write-AppLog "Log exported to '$($dialog.FileName)'." SUCCESS
        }
    }
    catch{
        Show-AppMessage "Log export failed:`r`n$($_.Exception.Message)" 'Export Log' Error
    }
})

$btnExportJson.Add_Click({
    try{
        if($script:DCInventory.Count -eq 0){ throw 'No DC inventory is loaded.' }
        $dialog=New-Object Windows.Forms.SaveFileDialog
        $dialog.Filter='JSON files (*.json)|*.json'
        $dialog.FileName="ADForest-Health-Snapshot-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss')
        if($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){
            $payload=[pscustomobject]@{
                Generated=(Get-Date).ToString('o')
                Forest=$script:Forest.Name
                Policy=$script:HealthPolicy
                DomainControllers=@($script:DCInventory)
            }
            $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $dialog.FileName -Encoding UTF8
            Write-AppLog "Health snapshot JSON exported to '$($dialog.FileName)'." SUCCESS
        }
    }catch{
        Show-AppMessage "JSON export failed:`r`n$($_.Exception.Message)" 'Export JSON' Error
    }
})

$btnExport.Add_Click({
    try{
        if($script:DCInventory.Count -eq 0){
            throw 'No DC inventory is loaded.'
        }

        $dialog=New-Object Windows.Forms.SaveFileDialog
        $dialog.Filter='CSV files (*.csv)|*.csv'
        $dialog.FileName="ADForest-DC-Inventory-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss')

        if($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){
            $script:DCInventory |
                Select-Object Domain,DCFqdn,IPv4,Site,GlobalCatalog,Writable,ReadOnly,OperatingSystem,OSVersion,FullBuildVersion,FSMORoles,NetlogonStatus,NetlogonQuery,SYSVOLShare,NETLOGONShare,DFSRStatus,DNSStatus,DCLocatorStatus,DCLocatorDC,DCLocatorDetail,W32TimeStatus,TimeSource,ReplicationStatus,ReplicationFailures,ReplicationTotal,ReplicationFailurePct,MaxReplicationDelta,ReplicationError,CriticalEventCount,RemoteQuery,OverallHealth |
                Export-Csv -LiteralPath $dialog.FileName -NoTypeInformation -Encoding UTF8

            Write-AppLog "DC inventory exported to '$($dialog.FileName)'." SUCCESS
        }
    }
    catch{
        Show-AppMessage "Inventory export failed:`r`n$($_.Exception.Message)" 'Export Inventory' Error
    }
})

$form.Add_Shown({
    try{
        Write-AppLog 'Starting AD Forest Synchronization & Health Check.' INFO
        Write-AppLog ("Management Computer: {0}; Domain: {1}" -f $env:COMPUTERNAME,$env:USERDNSDOMAIN) INFO
        Write-AppLog ("Host PowerShell: {0}; OS: {1}" -f $PSVersionTable.PSVersion,[Environment]::OSVersion.VersionString) INFO
        Refresh-ForestInventory
    }
    catch{
        Write-AppLog "Startup failed: $($_.Exception.Message)" ERROR
    }
})

$form.Add_FormClosed({
    Write-AppLog 'Closing AD Forest Synchronization & Health Check.' INFO
})

# =====================================================================================
# MAIN
# =====================================================================================
try{
    [void]$form.ShowDialog()
}
catch{
    try{
        Write-AppLog "Fatal error: $($_.Exception.Message)" ERROR
    }
    catch{}

    Show-AppMessage "Fatal error:`r`n`r`n$($_.Exception.Message)" 'Fatal Error' Error
}

# End of script
