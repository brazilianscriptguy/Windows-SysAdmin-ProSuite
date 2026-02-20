<#
.SYNOPSIS
    AD Forest Integrated GUI: Forced Replication + Health Checks (repadmin/dcdiag)

.DESCRIPTION
    Enterprise-style WinForms tool for Active Directory forest operations:
      - Discover forest domains and DCs (scoped selection)
      - Force replication (repadmin /syncall)
      - Health checks:
          * repadmin /kcc (per selected DCs)
          * repadmin /replsummary
          * repadmin /showrepl * /csv (locale-tolerant parsing)
          * repadmin /queue *
          * repadmin /istg * /verbose
          * dcdiag focused tests (Replications/Services/Connectivity/DnsBasic)
          * Global Catalog presence

    Design goals:
      - PowerShell 5.1-safe (no PS7-only operators)
      - Single log per run: C:\Logs-TEMP\<ScriptName>.log
      - Safe external command runner (ProcessStartInfo, stdout/stderr/exit code)
      - GUI-first UX (message boxes, status strip, progress, cancel)

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: 2026-02-20
    Version: 1.10
#>

[CmdletBinding()]
param(
    [switch]$ShowConsole
)

#Requires -RunAsAdministrator

#region --- Global Setup / Strict Mode / WinForms / Admin Check

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Require elevation (defensive, in addition to #Requires)
$IsAdmin = $false
try {
    $currentIdentity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    $IsAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { $IsAdmin = $false }

if (-not $IsAdmin) {
    [void][System.Windows.Forms.MessageBox]::Show(
        "This tool must be run as Administrator.",
        "Elevation Required",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    exit 1
}

function Set-ConsoleVisible {
    param(
        [Parameter(Mandatory=$true)][bool]$Visible
    )
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
"@ -ErrorAction SilentlyContinue | Out-Null

        $hWnd = [WinConsole]::GetConsoleWindow()
        if ($hWnd -ne [IntPtr]::Zero) {
            # 0 = SW_HIDE ; 5 = SW_SHOW
            [void][WinConsole]::ShowWindow($hWnd, $(if ($Visible) { 5 } else { 0 }))
        }
    } catch { }
}

if (-not $ShowConsole) { Set-ConsoleVisible -Visible $false }

#endregion

#region --- Config / Globals

$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir     = 'C:\Logs-TEMP'
$logPath    = Join-Path $logDir ("{0}.log" -f $scriptName)

$script:IsBusy          = $false
$script:CancelRequested = $false

$script:DiscoveredDomains = @()
$script:DiscoveredDCs     = @()

$script:repadminPath = $null
$script:dcdiagPath   = $null

# GUI references
$script:statusLabel  = $null
$script:lblCurrentDc = $null
$script:progress     = $null
$script:clbDomains   = $null
$script:clbDcs       = $null
$global:logBox        = $null

#endregion

#region --- Logging

function Ensure-LogDirectory {
    try {
        if (-not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
    } catch { }
}

function Log-Message {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("DEBUG","INFO","WARNING","ERROR")][string]$MessageType = "INFO"
    )

    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$stamp] [$MessageType] $($Message.TrimEnd())"

    # Never crash if logging fails
    try { Add-Content -Path $logPath -Value $entry -Encoding UTF8 -ErrorAction SilentlyContinue } catch { }

    if ($global:logBox -and -not $global:logBox.IsDisposed) {
        try {
            $global:logBox.SelectionStart  = $global:logBox.TextLength
            $global:logBox.SelectionLength = 0
            $global:logBox.SelectionColor  = switch ($MessageType) {
                "ERROR"   { [System.Drawing.Color]::Red }
                "WARNING" { [System.Drawing.Color]::DarkOrange }
                "DEBUG"   { [System.Drawing.Color]::Gray }
                default   { [System.Drawing.Color]::Black }
            }
            $global:logBox.AppendText($entry + "`r`n")
            $global:logBox.SelectionColor = [System.Drawing.Color]::Black
            $global:logBox.ScrollToCaret()
        } catch { }
    }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("DEBUG","INFO","WARNING","ERROR")][string]$Level="INFO"
    )
    Log-Message -Message $Message -MessageType $Level
}

function Normalize-LineBreaks {
    <#
      .SYNOPSIS
        Normalizes text to Windows CRLF line breaks for consistent log framing.
    #>
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }

    $t = $Text
    # Normalize any mixed line endings to CRLF.
    $t = ($t -replace "`r`n","`n")
    $t = ($t -replace "`r","`n")
    $t = ($t -replace "`n","`r`n")

    return $t.TrimEnd()
}

function Write-SectionBanner {
    <#
      .SYNOPSIS
        Writes a dedicated banner section to both the log file and UI pane.
    #>
    param(
        [Parameter(Mandatory)][string]$Title
    )

    $line = ("=" * 92)
    Write-Log $line "INFO"
    Write-Log ("SECTION: {0}" -f $Title) "INFO"
    Write-Log $line "INFO"

    if ($global:logBox -and -not $global:logBox.IsDisposed) {
        try {
            $global:logBox.AppendText("`r`n" + $line + "`r`n")
            $global:logBox.AppendText(("SECTION: {0}`r`n" -f $Title))
            $global:logBox.AppendText($line + "`r`n")
        } catch { }
    }
}

function Get-CommandVerdict {
    <#
      .SYNOPSIS
        Produces a short verdict string based on exit code and output heuristics.
    #>
    param(
        [Parameter(Mandatory)][int]$ExitCode,
        [string]$Output
    )

    if ($ExitCode -ne 0) { return "FAIL" }
    if ([string]::IsNullOrWhiteSpace($Output)) { return "OK" }

    # Conservative: any obvious error/failure tokens => WARN
    if ($Output -match '(?i)\b(fail|fails|failed|error|fatal|cannot|unavailable|denied|access\s+is\s+denied)\b') { return "WARN" }

    return "OK"
}

function Write-CommandSummary {
    <#
      .SYNOPSIS
        Writes a short English summary line per command (exit code + key verdict).
    #>
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][int]$ExitCode,
        [string]$Output
    )

    $verdict = Get-CommandVerdict -ExitCode $ExitCode -Output $Output
    $lvl = switch ($verdict) {
        "OK"   { "INFO" }
        "WARN" { "WARNING" }
        default { "ERROR" }
    }

    Write-Log ("SUMMARY: {0} -> {1} (exit {2})" -f $Command, $verdict, $ExitCode) $lvl
}

function Write-CommandRawOutput {
    <#
      .SYNOPSIS
        Logs raw command output to the log file (DEBUG) with normalized line breaks.
    #>
    param(
        [Parameter(Mandatory)][string]$Command,
        [string]$StdOut,
        [string]$StdErr
    )

    $combined = Normalize-LineBreaks (($StdOut + "`n" + $StdErr).Trim())
    if ($combined) {
        Write-Log ("RAW OUTPUT: {0}`r`n{1}" -f $Command, $combined) "DEBUG"
    } else {
        Write-Log ("RAW OUTPUT: {0} -> (no output)" -f $Command) "DEBUG"
    }

    return $combined
}



function Log-SessionStart {
    Ensure-LogDirectory
    Log-Message ("=" * 92) "INFO"
    Log-Message ("AD FOREST SESSION START: {0}" -f (Get-Date)) "INFO"
    Log-Message ("Host: {0}" -f $env:COMPUTERNAME) "INFO"
    Log-Message ("User: {0}" -f $env:USERNAME) "INFO"
    Log-Message ("LogPath: {0}" -f $logPath) "INFO"
    Log-Message ("=" * 92) "INFO"
}

function Log-SessionEnd {
    Log-Message ("=" * 92) "INFO"
    Log-Message ("AD FOREST SESSION END: {0}" -f (Get-Date)) "INFO"
    Log-Message ("=" * 92) "INFO"
}

#endregion

#region --- UI Helpers

function Show-MessageBox {
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Title = "AD Forest Tool",
        [ValidateSet('Information','Warning','Error')]$Icon = 'Information'
    )
    [void][System.Windows.Forms.MessageBox]::Show(
        $Text,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::$Icon
    )
}

function Set-Status {
    param([string]$Text)
    if ($script:statusLabel) { $script:statusLabel.Text = $Text }
}

function Set-CurrentDC {
    param([string]$Text)
    if ($script:lblCurrentDc) { $script:lblCurrentDc.Text = $Text }
}

function Set-Progress {
    param([int]$Value, [int]$Max = 1)
    if ($script:progress) {
        $script:progress.Maximum = [Math]::Max(1, $Max)
        $script:progress.Value   = [Math]::Min([Math]::Max(0, $Value), $script:progress.Maximum)
    }
}

function Append-ColoredBlock {
    param(
        [Parameter(Mandatory)][string]$Header,
        [Parameter(Mandatory)][string]$Body,
        [System.Drawing.Color]$Color = [System.Drawing.Color]::Black
    )
    if (-not $global:logBox -or $global:logBox.IsDisposed) { return }
    $global:logBox.SelectionColor = $Color
    $global:logBox.AppendText("`n=== $Header ===`n")
    $global:logBox.AppendText($Body.TrimEnd() + "`n")
    $global:logBox.SelectionColor = [System.Drawing.Color]::Black
}

#endregion

#region --- Dependencies / Modules / External Runner

function Ensure-ADModule {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-Log "Module loaded: ActiveDirectory" "INFO"
        return $true
    } catch {
        Write-Log ("Unable to load ActiveDirectory module: {0}" -f $_.Exception.Message) "ERROR"
        Show-MessageBox "Unable to load ActiveDirectory module.`n`nError: $($_.Exception.Message)`n`nInstall RSAT: Active Directory PowerShell." "Critical Error" "Error"
        return $false
    }
}

function Ensure-Dependencies {
    try {
        $script:repadminPath = (Get-Command -Name repadmin.exe -ErrorAction Stop).Source
        $script:dcdiagPath   = (Get-Command -Name dcdiag.exe   -ErrorAction Stop).Source
        return $true
    } catch {
        Write-Log ("Missing dependency: {0}" -f $_.Exception.Message) "ERROR"
        Show-MessageBox "Required tools not found (repadmin.exe / dcdiag.exe).`n`nError: $($_.Exception.Message)" "Critical Error" "Error"
        return $false
    }
}

function ConvertTo-ProcessArgument {
    param([Parameter(Mandatory)][string]$Value)
    if ($null -eq $Value) { return "" }

    # Escape internal quotes
    $escaped = $Value -replace '"','\"'

    # Quote when it contains whitespace or special CMD metacharacters
    if ($escaped -match '\s|[&\(\)\^\%\!\|<>]') {
        return '"' + $escaped + '"'
    }
    return $escaped
}

function Invoke-ExternalProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = $FilePath
    $psi.Arguments = (($Arguments | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join ' ')
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    try {
        # Keep native tool output legible
        $oemCp = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
        $enc = [System.Text.Encoding]::GetEncoding($oemCp)
        $psi.StandardOutputEncoding = $enc
        $psi.StandardErrorEncoding  = $enc
    } catch { }
    $psi.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi

    [void]$p.Start()

    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()

    $p.WaitForExit()

    [pscustomobject]@{
        ExitCode = $p.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }
}

#endregion

#region --- Discovery / Selection

function Get-SelectedDomains {
    $checked = $script:clbDomains.CheckedItems
    if ($checked.Count -eq 0) { return @($script:DiscoveredDomains) }
    return @($checked)
}

function Get-SelectedDCNames {
    $checked = $script:clbDcs.CheckedItems
    if ($checked.Count -eq 0) { return @($script:clbDcs.Items) }
    return @($checked)
}

function Get-SelectedDCObjects {
    $domains  = Get-SelectedDomains
    $allDCs   = @($domains | ForEach-Object { Get-ADDomainController -Filter * -Server $_ -ErrorAction SilentlyContinue })
    $selNames = Get-SelectedDCNames

    $targets = @($allDCs | Where-Object { $selNames -contains $_.HostName })
    if (@($targets).Count -eq 0) { $targets = @($allDCs) }

    return @($targets)
}

function Refresh-Discovery {
    if ($script:IsBusy) { return }
    $script:IsBusy = $true

    try {
        Set-Status "Discovering domains and DCs..."
        if (-not (Ensure-Dependencies)) { return }

        $forest = Get-ADForest -ErrorAction Stop
        $script:DiscoveredDomains = @($forest.Domains)
        $script:DiscoveredDCs     = @()

        $script:clbDomains.BeginUpdate()
        $script:clbDomains.Items.Clear()
        foreach ($d in $script:DiscoveredDomains) { [void]$script:clbDomains.Items.Add($d, $true) }
        $script:clbDomains.EndUpdate()

        foreach ($domain in $script:DiscoveredDomains) {
            try {
                $dcs = Get-ADDomainController -Filter * -Server $domain -ErrorAction Stop
                $script:DiscoveredDCs += $dcs
            } catch {
                Write-Log ("Failed to list DCs in {0}: {1}" -f $domain, $_.Exception.Message) "ERROR"
            }
        }

        $script:clbDcs.BeginUpdate()
        $script:clbDcs.Items.Clear()
        $seen = @{}
        foreach ($dc in $script:DiscoveredDCs) {
            $hn = $dc.HostName
            if ($hn -and -not $seen.ContainsKey($hn)) {
                $seen[$hn] = $true
                [void]$script:clbDcs.Items.Add($hn, $true)
            }
        }
        $script:clbDcs.EndUpdate()

        Write-Log ("Discovery completed – Domains: {0} | DCs: {1}" -f @($script:DiscoveredDomains).Count, @($script:DiscoveredDCs).Count) "INFO"
        Set-Status "Ready"
    } catch {
        Write-Log ("Discovery failed: {0}" -f $_.Exception.Message) "ERROR"
        Set-Status "Discovery error"
        Show-MessageBox "Discovery failed.`n`n$($_.Exception.Message)" "Discovery Error" "Error"
    } finally {
        $script:IsBusy = $false
    }
}

#endregion

#region --- Replication Sync

function Sync-AllDCs {
    if ($script:IsBusy) { return }
    $script:IsBusy = $true
    $script:CancelRequested = $false

    try {
        Set-Status "Preparing sync..."
        Write-SectionBanner "Forced Replication: repadmin /syncall (selected DCs)"
        Write-Log "Starting forced replication (repadmin /syncall)" "INFO"
        if (-not (Ensure-Dependencies)) { return }

        $targets = Get-SelectedDCObjects
        $total   = @($targets).Count

        if ($total -le 0) {
            Write-Log "No domain controllers available." "ERROR"
            Set-Status "No DCs"
            Show-MessageBox "No DCs found or selected." "Sync" "Error"
            return
        }

        Set-Progress 0 $total
        $idx = 0

        foreach ($dc in $targets) {
            if ($script:CancelRequested) {
                Write-Log "Sync cancelled by user." "WARNING"
                Set-Status "Cancelled"
                break
            }

            $idx++
            $name = $dc.HostName

            Set-CurrentDC ("Current DC: {0} ({1}/{2})" -f $name, $idx, $total)
            Set-Progress $idx $total
            [System.Windows.Forms.Application]::DoEvents()

            Write-Log ("Syncing {0}" -f $name) "INFO"

            $res = Invoke-ExternalProcess -FilePath $script:repadminPath -Arguments @('/syncall', $name, '/A', '/e', '/P', '/d', '/q')

            $raw = Write-CommandRawOutput -Command ("repadmin /syncall {0} /A /e /P /d /q" -f $name) -StdOut $res.StdOut -StdErr $res.StdErr
            Write-CommandSummary -Command ("repadmin /syncall {0}" -f $name) -ExitCode $res.ExitCode -Output $raw

            if ($res.ExitCode -eq 0) {
                if ($raw) { Write-Log $raw "INFO" } else { Write-Log ("{0}: OK (no output)" -f $name) "INFO" }
            } else {
                Write-Log ("repadmin /syncall exit code {0} on {1}. Output: {2}" -f $res.ExitCode, $name, $raw) "ERROR"
            }
        }

        if (-not $script:CancelRequested) {
            Write-Log "Forced replication completed." "INFO"
            Set-Status "Sync completed"
            Show-MessageBox "Replication triggered on selected DCs. Review the log." "Sync" "Information"
        }
    } catch {
        Write-Log ("Sync failed: {0}" -f $_.Exception.Message) "ERROR"
        Set-Status "Sync error"
        Show-MessageBox "Sync failed.`n`n$($_.Exception.Message)" "Sync Error" "Error"
    } finally {
        $script:IsBusy = $false
        $script:CancelRequested = $false
        Set-CurrentDC "Current DC: —"
        Set-Progress 0 1
    }
}

#endregion

#region --- showrepl CSV: locale-tolerant column resolution

function Resolve-ShowReplColumns {
    param([Parameter(Mandatory)][string[]]$PropertyNames)

    $map = [ordered]@{
        Failures    = $null
        LastSuccess = $null
        LastStatus  = $null
        NCContext   = $null
        SourceDSA   = $null
    }

    function Pick([string]$pattern) {
        return ($PropertyNames | Where-Object { $_ -match $pattern } | Select-Object -First 1)
    }

    # EN + PT-BR + common mojibake
    $map.Failures    = Pick '(?i)^(number\s+of\s+failures|n[uú]mero\s+de\s+falhas|n£mero\s+de\s+falhas)$'
    $map.LastSuccess = Pick '(?i)^(last\s+success\s+time|hor[aá]rio\s+do\s+[uú]ltimo\s+(e[xê]ito|sucesso))$'
    $map.LastStatus  = Pick '(?i)^(last\s+failure\s+status|status\s+da\s+[uú]ltima\s+falha)$'
    $map.NCContext   = Pick '(?i)^(naming\s+context|contexto\s+de\s+nomenclatura)$'
    $map.SourceDSA   = Pick '(?i)^(source\s+dsa|dsa\s+de\s+origem)$'

    [pscustomobject]$map
}

#endregion

#region --- Health Check (KCC integrated)

function Run-ADHealthCheck {
    if ($script:IsBusy) { return }
    $script:IsBusy = $true
    $script:CancelRequested = $false

    try {
        Set-Status "Running health checks..."
        Write-SectionBanner "AD Health Check: KCC + repadmin + dcdiag"
        Write-Log "AD Health Check started." "INFO"
        if (-not (Ensure-Dependencies)) { return }

        # 0) KCC (per selected DCs)
        $targets = Get-SelectedDCObjects
        if (@($targets).Count -gt 0) {
            Write-Log "Triggering KCC (repadmin /kcc) on selected DCs..." "INFO"
            $kccTotal = @($targets).Count
            $kccIdx = 0

            foreach ($dc in $targets) {
                if ($script:CancelRequested) { Write-Log "KCC cancelled by user." "WARNING"; break }
                $kccIdx++
                $name = $dc.HostName
                Set-CurrentDC ("KCC: {0} ({1}/{2})" -f $name, $kccIdx, $kccTotal)
                [System.Windows.Forms.Application]::DoEvents()

                $r = Invoke-ExternalProcess -FilePath $script:repadminPath -Arguments @('/kcc', $name)
                $out = Write-CommandRawOutput -Command ("repadmin /kcc {0}" -f $name) -StdOut $r.StdOut -StdErr $r.StdErr
                Write-CommandSummary -Command ("repadmin /kcc {0}" -f $name) -ExitCode $r.ExitCode -Output $out

                if ($r.ExitCode -eq 0) {
                    Write-Log ("KCC {0}: OK" -f $name) "INFO"
                    if ($out) { Write-Log $out "DEBUG" }
                } else {
                    Write-Log ("KCC {0}: exit code {1}. Output: {2}" -f $name, $r.ExitCode, $out) "ERROR"
                }
            }
        } else {
            Write-Log "KCC step skipped: no DCs found/selected." "WARNING"
        }

        if ($script:CancelRequested) { Set-Status "Cancelled"; return }

        # 1) replsummary
        Write-SectionBanner "Replication Summary: repadmin /replsummary"
        $rs = Invoke-ExternalProcess -FilePath $script:repadminPath -Arguments @('/replsummary')

        $sum = Write-CommandRawOutput -Command "repadmin /replsummary" -StdOut $rs.StdOut -StdErr $rs.StdErr
        # /replsummary is often multi-line; keep UI readable and always normalize line breaks.
        Write-CommandSummary -Command "repadmin /replsummary" -ExitCode $rs.ExitCode -Output $sum

        $sumColor = if ($sum -match '(?i)fail|fails|error|fatal|cannot|unavailable') { [System.Drawing.Color]::Red } else { [System.Drawing.Color]::DarkGreen }
        Append-ColoredBlock -Header "repadmin /replsummary (raw)" -Body $sum -Color $sumColor
        Write-Log ("repadmin /replsummary collected (exit {0})" -f $rs.ExitCode) "INFO"


        # 2) showrepl /csv parsing
        $sr = Invoke-ExternalProcess -FilePath $script:repadminPath -Arguments @('/showrepl','*','/csv')
        $csvRaw = Write-CommandRawOutput -Command "repadmin /showrepl * /csv" -StdOut $sr.StdOut -StdErr $sr.StdErr
        Write-CommandSummary -Command "repadmin /showrepl * /csv" -ExitCode $sr.ExitCode -Output $csvRaw

        if ($csvRaw) {
            $repl = $csvRaw | ConvertFrom-Csv -ErrorAction SilentlyContinue
            if ($repl -and @($repl).Count -gt 0) {
                $cols = Resolve-ShowReplColumns -PropertyNames @($repl[0].PSObject.Properties.Name)

                if ($cols.Failures) {
                    $bad = @($repl | Where-Object {
                        $failVal = 0
                        [void][int]::TryParse(("$($_.($cols.Failures))" -replace '[^\d]',''), [ref]$failVal)
                        $lastStatus  = "$($_.($cols.LastStatus))"
                        $lastSuccess = "$($_.($cols.LastSuccess))"

                        ($failVal -gt 0) -or
                        ($lastStatus -and $lastStatus -notmatch '(?i)\b0\b|success|passed|ok|êxito|sucesso') -or
                        ($lastSuccess -match '(?i)\b\d+\s*(day|days|dia|dias)\b')
                    })

                    if (@($bad).Count -gt 0) {
                        Write-Log ("showrepl: {0} potential issue(s) detected." -f @($bad).Count) "WARNING"
                        $preview = $bad | Select-Object `
                            @{n='Naming Context'; e={ if($cols.NCContext){ $_.($cols.NCContext) } else { $null } }}, `
                            @{n='Source DSA';     e={ if($cols.SourceDSA){ $_.($cols.SourceDSA) } else { $null } }}, `
                            @{n=$cols.Failures;   e={ $_.($cols.Failures) }}, `
                            @{n='Last Success';   e={ if($cols.LastSuccess){ $_.($cols.LastSuccess) } else { $null } }}, `
                            @{n='Last Status';    e={ if($cols.LastStatus){ $_.($cols.LastStatus) } else { $null } }} |
                            Format-Table -AutoSize | Out-String
                        Append-ColoredBlock -Header "repadmin /showrepl (issues)" -Body $preview -Color ([System.Drawing.Color]::DarkOrange)
                    } else {
                        Write-Log "showrepl: no replication failures detected." "INFO"
                    }
                } else {
                    Write-Log "showrepl: could not resolve failures column; showing raw preview." "WARNING"
                    $lines = ($csvRaw -split "`n" | Select-Object -First 25) -join "`n"
                    Append-ColoredBlock -Header "showrepl CSV preview" -Body $lines -Color ([System.Drawing.Color]::DarkOrange)
                }
            } else {
                Write-Log "showrepl: CSV returned no parsable rows." "WARNING"
            }
        } else {
            Write-Log "showrepl: no output." "WARNING"
        }

        # 3) queue
        $q = Invoke-ExternalProcess -FilePath $script:repadminPath -Arguments @('/queue','*')
        $queueOut = Write-CommandRawOutput -Command "repadmin /queue *" -StdOut $q.StdOut -StdErr $q.StdErr
        Write-CommandSummary -Command "repadmin /queue *" -ExitCode $q.ExitCode -Output $queueOut
        if ($queueOut -match '(?i)\bitems?\b|\bcontains\b') { Write-Log $queueOut "WARNING" } else { Write-Log "Replication queue appears empty." "INFO" }

        # 4) ISTG
        $i = Invoke-ExternalProcess -FilePath $script:repadminPath -Arguments @('/istg','*','/verbose')
        $istgOut = Write-CommandRawOutput -Command "repadmin /istg * /verbose" -StdOut $i.StdOut -StdErr $i.StdErr
        Write-CommandSummary -Command "repadmin /istg * /verbose" -ExitCode $i.ExitCode -Output $istgOut
        Append-ColoredBlock -Header "repadmin /istg * /verbose" -Body $istgOut -Color ([System.Drawing.Color]::Black)

        # 5) dcdiag focused tests
        # NOTE: dcdiag output is localized in some environments (PT-BR), so we evaluate pass/fail with locale-tolerant patterns.
        foreach ($test in @('Replications','Services','Connectivity','DNS_DnsBasic')) {

            $args = @("/test:$test","/v")
            if ($test -eq 'DNS_DnsBasic') { $args = @("/test:DNS","/DnsBasic","/v") }
            $d = Invoke-ExternalProcess -FilePath $script:dcdiagPath -Arguments $args
            $out = (($d.StdOut + "`n" + $d.StdErr).Trim())
            $testNameForMatch = $(if ($test -eq 'DNS_DnsBasic') { 'DNS' } else { $test })

            # Pass/Fail detection (EN + PT-BR)
            $passPattern = "(?i)passed\s+test\s+$([regex]::Escape($testNameForMatch))|passou\s+no\s+teste\s+$([regex]::Escape($testNameForMatch))|teste\s+aprovado\s+$([regex]::Escape($testNameForMatch))"
            $failPattern = "(?i)failed\s+test\s+$([regex]::Escape($testNameForMatch))|falhou\s+no\s+teste\s+$([regex]::Escape($testNameForMatch))"

            $hasFail = $false
            $hasPass = $false

            if ($out) {
                $hasFail = [regex]::IsMatch($out, $failPattern, 'IgnoreCase')
                $hasPass = [regex]::IsMatch($out, $passPattern, 'IgnoreCase')
            }

            $status = if ($hasFail) { "FAILED" } elseif ($hasPass) { "PASSED" } else { "UNKNOWN" }

            $color = switch ($status) {
                "PASSED"  { [System.Drawing.Color]::DarkGreen }
                "FAILED"  { [System.Drawing.Color]::Red }
                default   { [System.Drawing.Color]::DarkOrange }
            }

            # Log status + exit code, and keep full output in the log file (DEBUG) for troubleshooting
            Write-Log ("dcdiag /test:{0} -> {1} (exit {2})" -f ($(if($test -eq 'DNS_DnsBasic'){'DNS /DnsBasic'}else{$test})), $status, $d.ExitCode) "INFO"
            if ($out) {
                Write-Log ("dcdiag /test:{0} raw output:`n{1}" -f ($(if($test -eq 'DNS_DnsBasic'){'DNS /DnsBasic'}else{$test})), $out) "DEBUG"
            } else {
                Write-Log ("dcdiag /test:{0} returned no output." -f ($(if($test -eq 'DNS_DnsBasic'){'DNS /DnsBasic'}else{$test}))) "WARNING"
            }

            # Show a readable excerpt in the GUI (avoid flooding the pane)
            $excerpt = $out
            if ($excerpt) {
                $lines = $excerpt -split "`r?`n"
                if ($lines.Count -gt 120) {
                    $excerpt = (($lines | Select-Object -Last 120) -join "`n")
                    $excerpt = "[Output truncated: showing last 120 lines]`n" + $excerpt
                }
            } else {
                $excerpt = "(no output)"
            }

            Append-ColoredBlock -Header ("dcdiag /test:{0} ({1})" -f ($(if($test -eq 'DNS_DnsBasic'){'DNS /DnsBasic'}else{$test})), $status) -Body $excerpt -Color $color
        }
        # 6) Global Catalog
        $gcs = @(Get-ADDomainController -Filter { IsGlobalCatalog -eq $true } -ErrorAction SilentlyContinue)
        $gcText  = "Global Catalog servers found: $(@($gcs).Count)"
        $gcColor = if (@($gcs).Count -ge 1) { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::Red }
        Append-ColoredBlock -Header "Global Catalog" -Body $gcText -Color $gcColor

        Write-Log "Health check completed." "INFO"
        Set-Status "Health check completed"
        Show-MessageBox "Health check completed. Review the output pane and log file." "Health Check" "Information"
    } catch {
        Write-Log ("Health check failed: {0}" -f $_.Exception.Message) "ERROR"
        Set-Status "Health check error"
        Show-MessageBox "Health check failed.`n`n$($_.Exception.Message)" "Health Check Error" "Error"
    } finally {
        $script:IsBusy = $false
        $script:CancelRequested = $false
        Set-CurrentDC "Current DC: —"
    }
}

#endregion

#region --- Log Pane Helpers

function Clear-LogPane {
    try { if ($global:logBox) { $global:logBox.Clear() }; Write-Log "Log pane cleared." "INFO" } catch { }
}

function Copy-LogPane {
    try {
        if ($global:logBox) {
            [System.Windows.Forms.Clipboard]::SetText($global:logBox.Text)
            Write-Log "Log copied to clipboard." "INFO"
        }
    } catch {
        Write-Log ("Copy failed: {0}" -f $_.Exception.Message) "WARNING"
    }
}

function Save-LogPaneAs {
    try {
        $dlg = New-Object System.Windows.Forms.SaveFileDialog -Property @{
            Filter   = "Text files (*.txt)|*.txt|Log files (*.log)|*.log"
            FileName = ("{0}_{1}.txt" -f $scriptName, (Get-Date -Format 'yyyyMMdd-HHmm'))
        }
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $global:logBox.Text | Out-File -FilePath $dlg.FileName -Encoding utf8
            Write-Log ("Log saved to: {0}" -f $dlg.FileName) "INFO"
        }
    } catch {
        Write-Log ("Save As failed: {0}" -f $_.Exception.Message) "ERROR"
    }
}

function Open-LogFile {
    try { notepad.exe $logPath } catch { Write-Log ("Open log failed: {0}" -f $_.Exception.Message) "ERROR" }
}

#endregion

#region --- GUI

$form = New-Object System.Windows.Forms.Form -Property @{
    Text            = "AD Forest Sync + Health Tool"
    StartPosition   = 'CenterScreen'
    FormBorderStyle = 'FixedDialog'
    MaximizeBox     = $false
    ClientSize      = New-Object System.Drawing.Size 980, 700
    Font            = New-Object System.Drawing.Font("Segoe UI", 9)
}

$statusStrip = New-Object System.Windows.Forms.StatusStrip
$script:statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel -Property @{ Text = "Ready" }
[void]$statusStrip.Items.Add($script:statusLabel)
$form.Controls.Add($statusStrip)

# Left panel
$grpSel = New-Object System.Windows.Forms.GroupBox -Property @{
    Text     = "Scope Selection"
    Location = New-Object System.Drawing.Point 10, 10
    Size     = New-Object System.Drawing.Size 300, 610
}

$lblDomains = New-Object System.Windows.Forms.Label -Property @{
    Text     = "Domains"
    Location = New-Object System.Drawing.Point 12, 25
    AutoSize = $true
}

$script:clbDomains = New-Object System.Windows.Forms.CheckedListBox -Property @{
    Location     = New-Object System.Drawing.Point 12, 45
    Size         = New-Object System.Drawing.Size 275, 170
    CheckOnClick = $true
}

$lblDCs = New-Object System.Windows.Forms.Label -Property @{
    Text     = "Domain Controllers (Hostname)"
    Location = New-Object System.Drawing.Point 12, 225
    AutoSize = $true
}

$script:clbDcs = New-Object System.Windows.Forms.CheckedListBox -Property @{
    Location     = New-Object System.Drawing.Point 12, 245
    Size         = New-Object System.Drawing.Size 275, 300
    CheckOnClick = $true
}

$btnRefresh = New-Object System.Windows.Forms.Button -Property @{
    Text     = "Refresh"
    Location = New-Object System.Drawing.Point 12, 555
    Size     = New-Object System.Drawing.Size 90, 35
}

$btnAll = New-Object System.Windows.Forms.Button -Property @{
    Text     = "All"
    Location = New-Object System.Drawing.Point 112, 555
    Size     = New-Object System.Drawing.Size 55, 35
}

$btnNone = New-Object System.Windows.Forms.Button -Property @{
    Text     = "None"
    Location = New-Object System.Drawing.Point 177, 555
    Size     = New-Object System.Drawing.Size 55, 35
}

$btnRefresh.Add_Click({ Refresh-Discovery })
$btnAll.Add_Click({
    for ($i=0; $i -lt $script:clbDomains.Items.Count; $i++) { $script:clbDomains.SetItemChecked($i, $true) }
    for ($i=0; $i -lt $script:clbDcs.Items.Count;     $i++) { $script:clbDcs.SetItemChecked($i, $true) }
})
$btnNone.Add_Click({
    for ($i=0; $i -lt $script:clbDomains.Items.Count; $i++) { $script:clbDomains.SetItemChecked($i, $false) }
    for ($i=0; $i -lt $script:clbDcs.Items.Count;     $i++) { $script:clbDcs.SetItemChecked($i, $false) }
})

$grpSel.Controls.AddRange(@($lblDomains, $script:clbDomains, $lblDCs, $script:clbDcs, $btnRefresh, $btnAll, $btnNone))
$form.Controls.Add($grpSel)

# Right panel
$grpLog = New-Object System.Windows.Forms.GroupBox -Property @{
    Text     = "Log & Progress"
    Location = New-Object System.Drawing.Point 320, 10
    Size     = New-Object System.Drawing.Size 650, 610
}

$global:logBox = New-Object System.Windows.Forms.RichTextBox -Property @{
    Location   = New-Object System.Drawing.Point 12, 25
    Size       = New-Object System.Drawing.Size 625, 470
    ReadOnly   = $true
    Font       = New-Object System.Drawing.Font("Consolas", 9)
    WordWrap   = $false
    ScrollBars = 'Vertical'
}

$script:lblCurrentDc = New-Object System.Windows.Forms.Label -Property @{
    Text     = "Current DC: —"
    Location = New-Object System.Drawing.Point 12, 505
    AutoSize = $true
}

$script:progress = New-Object System.Windows.Forms.ProgressBar -Property @{
    Location = New-Object System.Drawing.Point 12, 530
    Size     = New-Object System.Drawing.Size 625, 18
}

$btnClear = New-Object System.Windows.Forms.Button -Property @{
    Text     = "Clear"
    Location = New-Object System.Drawing.Point 12, 555
    Size     = New-Object System.Drawing.Size 80, 35
}
$btnCopy = New-Object System.Windows.Forms.Button -Property @{
    Text     = "Copy"
    Location = New-Object System.Drawing.Point 100, 555
    Size     = New-Object System.Drawing.Size 80, 35
}
$btnSave = New-Object System.Windows.Forms.Button -Property @{
    Text     = "Save As..."
    Location = New-Object System.Drawing.Point 188, 555
    Size     = New-Object System.Drawing.Size 90, 35
}

$btnClear.Add_Click({ Clear-LogPane })
$btnCopy.Add_Click({ Copy-LogPane })
$btnSave.Add_Click({ Save-LogPaneAs })

$grpLog.Controls.AddRange(@($global:logBox, $script:lblCurrentDc, $script:progress, $btnClear, $btnCopy, $btnSave))
$form.Controls.Add($grpLog)

# Bottom action row (aligned)
$y = 630; $h = 45; $gap = 12; $x = 10

$btnSync = New-Object System.Windows.Forms.Button -Property @{
    Text     = "Sync Selected DCs"
    Location = New-Object System.Drawing.Point $x, $y
    Size     = New-Object System.Drawing.Size 200, $h
}
$btnCancel = New-Object System.Windows.Forms.Button -Property @{
    Text     = "Cancel"
    Location = New-Object System.Drawing.Point ($x + 200 + $gap), $y
    Size     = New-Object System.Drawing.Size 120, $h
}
$btnHealth = New-Object System.Windows.Forms.Button -Property @{
    Text      = "Health Check (KCC + Tests)"
    Location  = New-Object System.Drawing.Point ($x + 200 + $gap + 120 + $gap), $y
    Size      = New-Object System.Drawing.Size 220, $h
    BackColor = [System.Drawing.Color]::LightSteelBlue
}
$btnOpenLog = New-Object System.Windows.Forms.Button -Property @{
    Text     = "Open Log"
    Location = New-Object System.Drawing.Point ($x + 200 + $gap + 120 + $gap + 220 + $gap), $y
    Size     = New-Object System.Drawing.Size 140, $h
}
$btnRefresh2 = New-Object System.Windows.Forms.Button -Property @{
    Text     = "Refresh Scope"
    Location = New-Object System.Drawing.Point ($x + 200 + $gap + 120 + $gap + 220 + $gap + 140 + $gap), $y
    Size     = New-Object System.Drawing.Size 140, $h
}

$btnSync.Add_Click({
    $btnSync.Enabled = $false
    try { Sync-AllDCs } finally { $btnSync.Enabled = $true }
})
$btnCancel.Add_Click({
    if ($script:IsBusy) {
        $script:CancelRequested = $true
        Write-Log "Cancel requested..." "WARNING"
        Set-Status "Cancelling..."
    }
})
$btnHealth.Add_Click({ Run-ADHealthCheck })
$btnOpenLog.Add_Click({ Open-LogFile })
$btnRefresh2.Add_Click({ Refresh-Discovery })

$form.Controls.AddRange(@($btnSync, $btnCancel, $btnHealth, $btnOpenLog, $btnRefresh2))

#endregion

#region --- Main

try {
    Log-SessionStart

    if (-not (Ensure-ADModule)) { exit 1 }
    if (-not (Ensure-Dependencies)) { exit 1 }

    $form.Add_Shown({
        Write-Log ("Tool started – Log: {0}" -f $logPath) "INFO"
        Refresh-Discovery
        Set-Status "Ready – select scope and action"
    })

    [void]$form.ShowDialog()
} catch {
    try { Write-Log ("Fatal error: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    Show-MessageBox "Fatal error.`n`n$($_.Exception.Message)" "Fatal Error" "Error"
    exit 1
} finally {
    try { Log-SessionEnd } catch { }
}

#endregion

# End of script
