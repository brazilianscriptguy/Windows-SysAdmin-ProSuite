<#
.SYNOPSIS
  PKI Certificate Lifecycle Manager v5.5.2 Enterprise Edition - Enterprise AD CS lifecycle governance console.

.DESCRIPTION
  Enterprise Windows Forms GUI and console tool for Microsoft AD CS lifecycle maintenance.

  Implements:
  - Responsive WinForms GUI using MenuStrip, StatusStrip and TableLayoutPanel
  - CA database discovery through AD CS COM ICertView instead of localized certutil CSV parsing
  - Expired issued certificate discovery
  - Replacement certificate validation before Superseded revocation
  - Optional force mode for policy-driven revocation without replacement
  - Template filtering
  - Explicit Dry Run / Commit workflow with confirmation gates and selected-row counters
  - Native WhatIf support for console execution
  - CRL and Delta CRL publication
  - CA database cleanup after retention period
  - Failed Requests cleanup after retention period using the same safety model as revoked cleanup
  - CA database backup and registry export helpers
  - Runtime log panel, statistics dashboard and double-click row details dialog
  - CSV, JSON and HTML reports in C:\Logs-TEMP
  - Idempotent execution: already revoked certificates are not returned because only issued rows are queried

.AUTHOR
  Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
  2026-07-07-v5.5.2-ENTERPRISE-EDITION

.REQUIREMENTS
  - Windows PowerShell 5.1
  - Windows Server 2019/2022 with Microsoft AD CS administration tools
  - Run as Administrator on the CA server or from a machine that can query the CA
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [switch]$ShowConsole,
    [switch]$RunConsole,
    [string]$CAConfig = '',
    [string[]]$TemplateFilter = @(),
    [switch]$PublishCRL,
    [switch]$PublishDeltaCRL,
    [switch]$ForceRevokeWithoutReplacement,
    [int]$RetentionDays = 365,
    [switch]$CleanupDatabase,
    [switch]$BackupCA,
    [string]$BackupRoot = 'D:\PKIBackup',
    [switch]$ExportOnly,
    [string]$ConfigPath = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# =====================================================================================
# Assemblies and process mode
# =====================================================================================
try {
    if (-not $ShowConsole -and -not $RunConsole) {
        try {
            Add-Type -Name Win32ShowWindowAsync -Namespace ConsoleControl -MemberDefinition @"
[DllImport("user32.dll")]
public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
[DllImport("kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
"@
            $consolePtr = [ConsoleControl.Win32ShowWindowAsync]::GetConsoleWindow()
            if ($consolePtr -ne [IntPtr]::Zero) { [void][ConsoleControl.Win32ShowWindowAsync]::ShowWindowAsync($consolePtr, 0) }
        } catch { }
    }

    if (-not $RunConsole) {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        Add-Type -AssemblyName System.Data
        # SetCompatibleTextRenderingDefault can throw if the host already created an IWin32Window.
        # Omitting it is safe for this WinForms console and prevents startup failure in PowerShell hosts.
        [System.Windows.Forms.Application]::EnableVisualStyles()
    }
} catch {
    Write-Error "Failed to initialize required assemblies: $($_.Exception.Message)"
    return
}

# =====================================================================================
# Globals
# =====================================================================================
$script:ScriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:LogRoot    = 'C:\Logs-TEMP'
$script:RunStamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:ReportRoot = Join-Path $script:LogRoot "$($script:ScriptName)-Reports-$($script:RunStamp)"
$script:LogFile    = Join-Path $script:LogRoot "$($script:ScriptName)-$($script:RunStamp).log"

$script:ConfigPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) { Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'config.json' } else { $ConfigPath }
$script:Config = $null
$script:DefaultConfig = [ordered]@{
    # CA identity
    # Use empty string for auto-discovery / operator configuration.
    # Example: 'CAHOST.domain.local\CA-NAME'
    CAConfig = ''

    # Retention windows
    # Legacy fallback only. Prefer explicit windows below.
    RetentionDays              = 365
    LifecycleRetentionDays     = 30
    RevokedRetentionDays       = 365
    FailedRetentionDays        = 365

    # AD CS disposition values for failed/denied request repositories.
    FailedRequestDispositions  = @(30, 31)

    # CRL publication
    PublishDeltaCRL            = $true
    PublishFullCRL             = $false
    VerifyCRLPublication       = $true

    # Lifecycle safety
    VerifyReplacement          = $true
    VerifyRevocation           = $true
    AutoMode                   = $false

    # Cleanup / maintenance
    CleanupFailedRequests      = $true
    CompactDatabase            = $true
    BackupBeforeCleanup        = $true
    BackupBeforeFailedCleanup  = $true

    # Backup policy
    BackupBeforeApply          = $true
    BackupPrivateKey           = $false
    BackupRoot                 = "$env:SystemDrive\PKIBackup"
    RequireBackup              = $true
    RequireSnapshot            = $true

    # Execution controls
    DefaultDryRun              = $true
    RequireCommitConfirmation  = $true
    ShowExecutionModeInStatus  = $true
    EnablePreFlightChecks      = $true
    EnableRiskAnalysis         = $true
    EnableExecutionHistory     = $true
    ExecutionHistoryDays       = 90

    # Performance
    EnableRepositoryCache      = $true
    MaxParallelLookup          = 8

    # Template policy
    # Keep this intentionally generic. Add enterprise/custom templates in config.json.
    AllowedTemplates = @(
        'Computer',
        'User',
        'Web Server',
        'Client Authentication',
        'IPSec',
        'EFS'
    )

    ExcludedTemplates = @(
        'CA Exchange',
        'Domain Controller',
        'Domain Controller Authentication',
        'Kerberos Authentication',
        'SubCA',
        'Certification Authority',
        'Enrollment Agent',
        'OCSP Response Signing'
    )
}

$script:CAConfig = $CAConfig
$script:ComputerClassCache = @{}
$script:UseADComputerLookup = $false  # v4.1: safe default; heuristic classification prevents DirectoryServices/COM type mismatch. Set to $true manually if required.
$script:IssuedCerts = @()
$script:RepositoryCache = [ordered]@{ Issued = $null; IssuedCAConfig = $null; IssuedLoadedAt = $null }
$script:ReplacementIndex = $null
$script:CurrentOperationStarted = $null
$script:lblProgressDetail = $null
$script:ActionControls = @()
$script:PreviewItems = New-Object System.Collections.ArrayList
$script:Stats = [ordered]@{
    IssuedLoaded       = 0
    ExpiredFound       = 0
    TemplateMatched    = 0
    ReplacementFound   = 0
    ReadyToRevoke      = 0
    SkippedNoReplace   = 0
    SkippedInvalid     = 0
    Revoked            = 0
    Failed             = 0
    CRLPublished       = 0
    DeltaCRLPublished  = 0
    CleanupCandidates  = 0
    FailedCleanupCandidates = 0
    CleanupActions     = 0
    FailedCleanupActions = 0
    BackupActions      = 0
    SnapshotActions    = 0
    WorkstationCerts    = 0
    ServerCerts         = 0
    DomainControllerCerts = 0
    UnknownDeviceCerts  = 0
}

New-Item -ItemType Directory -Path $script:LogRoot -Force | Out-Null
New-Item -ItemType Directory -Path $script:ReportRoot -Force | Out-Null

# GUI variables
$script:form = $null
$script:txtCAConfig = $null
$script:txtTemplates = $null
$script:txtRetention = $null # legacy alias for revoked retention
$script:txtLifecycleRetention = $null
$script:txtRevokedRetention = $null
$script:txtFailedRetention = $null
$script:txtBackupRoot = $null
$script:chkDryRun = $null
$script:chkForce = $null
$script:chkPublishCRL = $null
$script:chkPublishDelta = $null
$script:chkCleanup = $null
$script:chkBackup = $null
$script:grid = $null
$script:txtLog = $null
$script:txtStats = $null
$script:statusMain = $null
$script:statusCA = $null
$script:statusPreview = $null
$script:statusMode = $null
$script:progress = $null
$script:ExecutionTimeline = New-Object System.Collections.ArrayList
$script:LastPreFlight = @()

# =====================================================================================
# Basic helpers
# =====================================================================================
function Write-AppLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','SUCCESS','WARN','ERROR')][string]$Level = 'INFO'
    )
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
    if ($script:txtLog -and -not $script:txtLog.IsDisposed) {
        $script:txtLog.AppendText($line + [Environment]::NewLine)
        $script:txtLog.SelectionStart = $script:txtLog.Text.Length
        $script:txtLog.ScrollToCaret()
    } else {
        Write-Host $line
    }
}

function Get-ExecutionModeLabel {
    if ($script:chkDryRun -and -not $script:chkDryRun.IsDisposed) {
        if ([bool]$script:chkDryRun.Checked) { return 'DRY RUN' }
        return 'COMMIT'
    }
    if ($script:Config -and ($script:Config.PSObject.Properties.Name -contains 'DefaultDryRun')) {
        if ([bool]$script:Config.DefaultDryRun) { return 'DRY RUN' }
    }
    return 'COMMIT'
}

function Get-SelectedPreviewCount {
    if (-not $script:PreviewItems) { return 0 }
    return @($script:PreviewItems | Where-Object { $_.Selected -eq $true }).Count
}

function Update-StatusBar {
    param([string]$Message = 'Ready.')
    $mode = Get-ExecutionModeLabel
    $selected = Get-SelectedPreviewCount
    $rows = 0
    if ($script:PreviewItems) { $rows = $script:PreviewItems.Count }
    if ($script:statusMain -and -not $script:statusMain.IsDisposed) { $script:statusMain.Text = $Message }
    if ($script:statusCA -and -not $script:statusCA.IsDisposed) { $script:statusCA.Text = "CA: $($script:CAConfig)" }
    if ($script:statusPreview -and -not $script:statusPreview.IsDisposed) { $script:statusPreview.Text = "Rows: $rows | Selected: $selected" }
    if ($script:statusMode -and -not $script:statusMode.IsDisposed) { $script:statusMode.Text = "Mode: $mode" }
    if (-not $RunConsole) { [System.Windows.Forms.Application]::DoEvents() }
}

function Show-AppMessage {
    param(
        [string]$Message,
        [string]$Title = 'PKI Lifecycle Manager',
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )
    [void][System.Windows.Forms.MessageBox]::Show($script:form, $Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon)
}

function Show-PKIExecutionConfirmation {
    param(
        [ValidateSet('Revoke','Cleanup')][string]$Mode,
        [bool]$DryRun,
        [int]$Targets
    )
    $modeText = if ($DryRun) { 'DRY RUN' } else { 'COMMIT' }
    if ($Targets -le 0) { return $true }
    if ($DryRun) {
        $msg = "$Mode Operation`r`n`r`nExecution Mode: DRY RUN`r`nTargets: $Targets`r`n`r`nNo CA records will be modified. The tool will generate reports showing what would happen."
        $buttons = [System.Windows.Forms.MessageBoxButtons]::OKCancel
        $icon = [System.Windows.Forms.MessageBoxIcon]::Information
        $result = [System.Windows.Forms.MessageBox]::Show($script:form, $msg, "$Mode Confirmation - $modeText", $buttons, $icon)
        return ($result -eq [System.Windows.Forms.DialogResult]::OK)
    }
    if ($script:Config -and ($script:Config.PSObject.Properties.Name -contains 'RequireCommitConfirmation') -and -not [bool]$script:Config.RequireCommitConfirmation) {
        return $true
    }
    $verb = if ($Mode -eq 'Revoke') { 'revoke selected issued certificates with reason Superseded' } else { 'delete old revoked CA database rows' }
    $msg = "$Mode Operation`r`n`r`nExecution Mode: COMMIT`r`nTargets: $Targets`r`n`r`nThis will $verb.`r`n`r`nA snapshot/report will be generated before execution. Continue?"
    $result = [System.Windows.Forms.MessageBox]::Show($script:form, $msg, "$Mode Confirmation - COMMIT", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Get-SelectedReadyTargetsCount {
    param([ValidateSet('Revoke','Cleanup')][string]$Mode)
    if (-not $script:PreviewItems) { return 0 }
    if ($Mode -eq 'Revoke') {
        return @($script:PreviewItems | Where-Object { $_.Selected -eq $true -and $_.Status -eq 'READY' -and $_.Decision -eq 'ReadyToRevoke' }).Count
    }
    return @($script:PreviewItems | Where-Object { $_.Selected -eq $true -and (($_.Status -eq 'CLEANUP_READY' -and $_.Decision -eq 'ReadyToDeleteRevokedRow') -or ($_.Status -eq 'FAILED_CLEANUP_READY' -and $_.Decision -eq 'ReadyToDeleteFailedRequest')) }).Count
}

function Update-ExecutionModeVisualState {
    $mode = Get-ExecutionModeLabel
    if ($script:chkDryRun -and -not $script:chkDryRun.IsDisposed) {
        if ($mode -eq 'DRY RUN') { $script:chkDryRun.Text = 'Execution Mode: DRY RUN' }
        else { $script:chkDryRun.Text = 'Execution Mode: COMMIT' }
    }
    Update-StatusBar "Execution mode: $mode"
}

function Invoke-UIAction {
    param([Parameter(Mandatory)][scriptblock]$Action, [string]$ErrorTitle = 'Operation Error')
    try { & $Action }
    catch {
        $msg = $_.Exception.Message
        Write-AppLog $msg 'ERROR'
        Show-AppMessage $msg $ErrorTitle ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Set-Busy {
    param([bool]$IsBusy, [string]$Message = 'Working...')
    foreach ($c in @($script:txtCAConfig,$script:txtTemplates,$script:txtLifecycleRetention,$script:txtRevokedRetention,$script:txtFailedRetention,$script:txtBackupRoot,$script:chkDryRun,$script:chkForce,$script:chkPublishCRL,$script:chkPublishDelta,$script:chkCleanup,$script:chkBackup)) {
        if ($c -and -not $c.IsDisposed) { $c.Enabled = -not $IsBusy }
    }
    foreach ($c in @($script:ActionControls)) {
        try { if ($c -and -not $c.IsDisposed) { $c.Enabled = -not $IsBusy } } catch {}
    }
    if ($script:form -and -not $script:form.IsDisposed) {
        $script:form.Cursor = if ($IsBusy) { [System.Windows.Forms.Cursors]::WaitCursor } else { [System.Windows.Forms.Cursors]::Default }
    }
    if ($script:progress -and -not $script:progress.IsDisposed) {
        $script:progress.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
        $script:progress.Minimum = 0
        $script:progress.Maximum = 100
        if (-not $IsBusy) { $script:progress.Value = 0 }
    }
    if ($script:lblProgressDetail -and -not $script:lblProgressDetail.IsDisposed) { $script:lblProgressDetail.Text = $Message }
    Update-StatusBar $Message
    try { [System.Windows.Forms.Application]::DoEvents() } catch {}
}


function Update-Progress {
    [CmdletBinding()]
    param(
        [int]$Current = 0,
        [int]$Total = 100,
        [string]$Message = ''
    )
    try {
        $pct = 0
        if ($Total -gt 0) { $pct = [Math]::Min(100,[Math]::Max(0,[int](($Current / [double]$Total) * 100))) }
        if ($script:progress -and -not $script:progress.IsDisposed) {
            $script:progress.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
            $script:progress.Minimum = 0
            $script:progress.Maximum = 100
            $script:progress.Value = $pct
        }
        $elapsedText = ''
        if ($script:CurrentOperationStarted) {
            try { $elapsedText = ' | Elapsed ' + ((Get-Date) - $script:CurrentOperationStarted).ToString('hh\:mm\:ss') } catch {}
        }
        if ($script:lblProgressDetail -and -not $script:lblProgressDetail.IsDisposed) {
            $detail = if ([string]::IsNullOrWhiteSpace($Message)) { "$pct%$elapsedText" } else { "$Message ($pct%)$elapsedText" }
            $script:lblProgressDetail.Text = $detail
        }
        if (-not [string]::IsNullOrWhiteSpace($Message)) { Update-StatusBar $Message }
        if (-not $RunConsole) { [System.Windows.Forms.Application]::DoEvents() }
    } catch { }
}

function Update-StageProgress {
    [CmdletBinding()]
    param(
        [int]$Stage = 1,
        [int]$StageCount = 1,
        [int]$Current = 0,
        [int]$Total = 100,
        [string]$Message = ''
    )
    $stageBase = 0
    $stageWidth = 100
    if ($StageCount -gt 0) {
        $stageBase = [int](([Math]::Max(0,$Stage-1) / [double]$StageCount) * 100)
        $stageWidth = [int](100 / [double]$StageCount)
    }
    $inner = 0
    if ($Total -gt 0) { $inner = [Math]::Min(100,[Math]::Max(0,[int](($Current / [double]$Total) * 100))) }
    $overall = [Math]::Min(100, [Math]::Max(0, $stageBase + [int](($inner / 100.0) * $stageWidth)))
    $stageMsg = "Stage $Stage/$StageCount - $Message"
    Update-Progress -Current $overall -Total 100 -Message $stageMsg
}

function New-PKIExecutionId {
    return (Get-Date -Format 'yyyyMMdd-HHmmss')
}

function Test-PKIRevocationVerified {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SerialNumber,
        [Parameter(Mandatory)][string]$CAConfigValue
    )
    Assert-CertutilAvailable
    if ([string]::IsNullOrWhiteSpace($SerialNumber)) { return $false }
    try {
        $restrict = "SerialNumber=$SerialNumber,Disposition=21"
        $out = & certutil.exe -config $CAConfigValue -view -restrict $restrict -out "RequestID,SerialNumber,Request.RevokedWhen,Request.RevokedReason" 2>&1
        $text = ($out -join "`n")
        if ($LASTEXITCODE -eq 0 -and $text -match [regex]::Escape($SerialNumber)) { return $true }
        Write-AppLog "Revocation verification did not confirm Serial=$SerialNumber. ExitCode=$LASTEXITCODE Output=$($text -replace "`r?`n", ' ' )" 'WARN'
        return $false
    } catch {
        Write-AppLog "Revocation verification exception for Serial=$SerialNumber. Error=$($_.Exception.Message)" 'WARN'
        return $false
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-CertutilAvailable {
    $cmd = Get-Command certutil.exe -ErrorAction SilentlyContinue
    if (-not $cmd) { throw 'certutil.exe was not found. Install AD CS tools or run on the CA server.' }
}

function Convert-CADate {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return [datetime]$Value }

    try {
        if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) {
            $d = [double]$Value
            if ($d -gt 20000 -and $d -lt 80000) { return [datetime]::FromOADate($d) }
        }
    } catch { }

    $text = $null
    try { $text = [string]$Value } catch { return $null }
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $clean = $text.Trim().Trim('"')
    $clean = $clean -replace '\s+',' '
    $clean = $clean -replace '(?i)\s+(UTC|GMT).*$',''
    $clean = $clean.Trim()

    $formats = @(
        'dd/MM/yyyy HH:mm:ss','dd/MM/yyyy HH:mm','d/M/yyyy HH:mm:ss','d/M/yyyy HH:mm',
        'dd/MM/yyyy h:mm:ss tt','dd/MM/yyyy h:mm tt','d/M/yyyy h:mm:ss tt','d/M/yyyy h:mm tt',
        'MM/dd/yyyy HH:mm:ss','MM/dd/yyyy HH:mm','M/d/yyyy HH:mm:ss','M/d/yyyy HH:mm',
        'MM/dd/yyyy h:mm:ss tt','MM/dd/yyyy h:mm tt','M/d/yyyy h:mm:ss tt','M/d/yyyy h:mm tt',
        'yyyy-MM-dd HH:mm:ss','yyyy-MM-dd HH:mm','yyyyMMddHHmmss','yyyyMMdd'
    )
    $cultures = @(
        [System.Globalization.CultureInfo]::GetCultureInfo('pt-BR'),
        [System.Globalization.CultureInfo]::GetCultureInfo('en-US'),
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.CultureInfo]::CurrentCulture
    )
    foreach ($culture in $cultures) {
        foreach ($fmt in $formats) {
            $dt = [datetime]::MinValue
            if ([datetime]::TryParseExact($clean, $fmt, $culture, [System.Globalization.DateTimeStyles]::AssumeLocal, [ref]$dt)) { return $dt }
        }
    }
    foreach ($culture in $cultures) {
        $dt = [datetime]::MinValue
        if ([datetime]::TryParse($clean, $culture, [System.Globalization.DateTimeStyles]::AssumeLocal, [ref]$dt)) { return $dt }
    }
    return $null
}

function Get-PropValue {
    param([object]$Object, [string[]]$Names)
    if (-not $Object) { return $null }

    foreach ($name in $Names) {
        if ($Object.PSObject.Properties.Name -contains $name) { return $Object.$name }
    }

    # Locale and certutil-version resilient lookup: normalize both requested names
    # and returned column names, then accept exact/contains matches.
    $wanted = @($Names | ForEach-Object { Normalize-PKIText $_ })
    foreach ($prop in $Object.PSObject.Properties) {
        $pn = Normalize-PKIText $prop.Name
        foreach ($w in $wanted) {
            if ($pn -eq $w -or $pn.Contains($w) -or $w.Contains($pn)) { return $prop.Value }
        }
    }

    # Special fallbacks for CA DB date columns exposed under localized/display names.
    foreach ($prop in $Object.PSObject.Properties) {
        $pn = Normalize-PKIText $prop.Name
        if (($wanted -contains 'notafter') -and ($pn -match 'expiration|validade|notafter|expires')) { return $prop.Value }
        if (($wanted -contains 'notbefore') -and ($pn -match 'effective|efetiva|notbefore|valid from')) { return $prop.Value }
        if (($wanted -contains 'certificatetemplate') -and ($pn -match 'template|modelo')) { return $prop.Value }
        if (($wanted -contains 'requestername') -and ($pn -match 'requester|solicitante')) { return $prop.Value }
        if (($wanted -contains 'serialnumber') -and ($pn -match 'serial|serie')) { return $prop.Value }
        if (($wanted -contains 'requestid') -and ($pn -match 'requestid|solicitacao')) { return $prop.Value }
    }
    return $null
}
function Normalize-PKIText {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $text = ([string]$Value).Trim().ToLowerInvariant()
    $formD = $text.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $formD.ToCharArray()) {
        $cat = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
        if ($cat -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    return ($sb.ToString().Normalize([System.Text.NormalizationForm]::FormC) -replace '[^a-z0-9\.\-\\_\$ ]','' -replace '\s+',' ').Trim()
}

function Get-PKITemplateAliases {
    param([AllowNull()][string]$Template)
    $n = Normalize-PKIText $Template
    $aliases = New-Object System.Collections.Generic.List[string]
    if ($n) { $aliases.Add($n) }

    # Portuguese MMC display names and common AD CS template names do not always match certutil output.
    switch -Regex ($n) {
        'autenticacao de estacao|station authentication|workstation authentication|computer|machine' {
            foreach ($x in @('workstation authentication','autenticacao de estacao','computer','machine','maquina','estacao')) { if (-not $aliases.Contains($x)) { $aliases.Add($x) } }
        }
        'controlador de dominio|domain controller|kerberos authentication' {
            foreach ($x in @('domain controller','domain controller authentication','controlador de dominio','kerberos authentication')) { if (-not $aliases.Contains($x)) { $aliases.Add($x) } }
        }
        'ca exchange|certification authority|subca|ca infrastructure|ocsp|key recovery|enrollment agent' {
            foreach ($x in @('ca exchange','certification authority','subca','ca infrastructure','ocsp response signing','key recovery agent','enrollment agent')) { if (-not $aliases.Contains($x)) { $aliases.Add($x) } }
        }
        'web server|servidor web' {
            foreach ($x in @('web server','servidor web')) { if (-not $aliases.Contains($x)) { $aliases.Add($x) } }
        }
        'client authentication|user|usuario|efs|ipsec' {
            foreach ($x in @('client authentication','user','usuario','efs','ipsec')) { if (-not $aliases.Contains($x)) { $aliases.Add($x) } }
        }
    }
    return @($aliases)
}

function Test-PKITemplateMatch {
    param([AllowNull()][string]$CertTemplate, [string[]]$Filters)
    if (-not $Filters -or $Filters.Count -eq 0) { return $true }
    $certAliases = @(Get-PKITemplateAliases $CertTemplate)
    foreach ($filter in $Filters) {
        $filterAliases = @(Get-PKITemplateAliases $filter)
        foreach ($ca in $certAliases) {
            foreach ($fa in $filterAliases) {
                if ($ca -eq $fa -or $ca.Contains($fa) -or $fa.Contains($ca)) { return $true }
            }
        }
    }
    return $false
}

function Get-PKIIdentityKeys {
    param([object]$Cert)
    $keys = New-Object System.Collections.Generic.List[string]
    foreach ($v in @($Cert.RequesterName, $Cert.CommonName)) {
        $n = Normalize-PKIText $v
        if ($n -and -not $keys.Contains($n)) { $keys.Add($n) }
        if ($n -match '([^\\]+)\\([^\\]+)$') {
            $sam = $Matches[2]
            if ($sam -and -not $keys.Contains($sam)) { $keys.Add($sam) }
            $nos = $sam.TrimEnd('$')
            if ($nos -and -not $keys.Contains($nos)) { $keys.Add($nos) }
        }
    }
    return @($keys)
}

function Test-SamePKISubject {
    param([object]$A, [object]$B)
    $ak = @(Get-PKIIdentityKeys $A)
    $bk = @(Get-PKIIdentityKeys $B)
    foreach ($x in $ak) { if ($bk -contains $x) { return $true } }
    return $false
}

function Get-PKIBoolConfigValue {
    param([string]$Name, [bool]$Default = $false)
    try {
        if ($script:Config -and ($script:Config.PSObject.Properties.Name -contains $Name)) {
            return [System.Convert]::ToBoolean($script:Config.$Name)
        }
    } catch { }
    return $Default
}


function Get-PKIComputerSamCandidate {
    param([object]$Cert)
    foreach ($v in @($Cert.RequesterName, $Cert.CommonName, $Cert.Subject)) {
        $n = Normalize-PKIText $v
        if (-not $n) { continue }
        if ($n -match '([^\\]+)\\([^\\]+)\$?$') { return $Matches[2].TrimEnd('$') }
        if ($n -match 'cn=([^,]+)') { return $Matches[1].TrimEnd('$') }
        if ($n -match '^([a-z0-9][a-z0-9\-]{1,62})\$?$') { return $Matches[1].TrimEnd('$') }
    }
    return $null
}

function Resolve-PKIDeviceClass {
    param([object]$Cert)

    $sam = Get-PKIComputerSamCandidate -Cert $Cert
    if ([string]::IsNullOrWhiteSpace($sam)) {
        return [pscustomobject]@{ DeviceClass='Unknown'; ComputerName=$null; OperatingSystem=$null; DistinguishedName=$null; Source='NoComputerIdentity' }
    }

    if (-not (Get-Variable -Name ComputerClassCache -Scope Script -ErrorAction SilentlyContinue)) { $script:ComputerClassCache = @{} }
    if ($null -eq $script:ComputerClassCache) { $script:ComputerClassCache = @{} }
    $key = $sam.ToUpperInvariant()
    if ($script:ComputerClassCache.ContainsKey($key)) { return $script:ComputerClassCache[$key] }

    # v4.1: classify safely first without AD lookup. AD lookup is optional because DirectoryServices can
    # throw non-terminating COM/type mismatch errors on some hosts/locales and must never break PKI preview.
    $class = 'Workstation'
    $os = $null
    $dn = $null
    $source = 'Heuristic'

    if ($sam -match '(?i)(^|[-_])(dc|adds)([-_]|\d|$)') { $class = 'DomainController' }
    elseif ($sam -match '(?i)(^|[-_])(srv|server|fs|file|sql|db|adfs|wsus|print|prn|ca|pki|iis|web|rds|rd|app|mail|exch|dns|dhcp|kms|wds|glpi|kes)([-_]|\d|$)') { $class = 'Server' }
    elseif ($sam -match '(?i)(adfs|adcs|adds|wsus|print|prn|srv|server|sql|pki|ca|rds|glpi|kms|wds)') { $class = 'Server' }

    if ($script:UseADComputerLookup) {
        try {
            $root = [ADSI]'LDAP://RootDSE'
            $basePath = [string]$root.defaultNamingContext
            if (-not [string]::IsNullOrWhiteSpace($basePath)) {
                $base = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$basePath")
                $ds = New-Object System.DirectoryServices.DirectorySearcher
                $ds.SearchRoot = $base
                $safeSam = $sam.Replace('\\','\\5c').Replace('*','\\2a').Replace('(','\\28').Replace(')','\\29')
                $ds.Filter = "(&(objectCategory=computer)(sAMAccountName=$safeSam`$))"
                $ds.PageSize = 1
                foreach ($p in @('operatingSystem','distinguishedName','dNSHostName','userAccountControl')) { try { [void]$ds.PropertiesToLoad.Add([string]$p) } catch {} }
                $found = $ds.FindOne()
                if ($found) {
                    if ($found.Properties.Contains('operatingsystem') -and $found.Properties['operatingsystem'].Count -gt 0) { $os = [string]$found.Properties['operatingsystem'][0] }
                    if ($found.Properties.Contains('distinguishedname') -and $found.Properties['distinguishedname'].Count -gt 0) { $dn = [string]$found.Properties['distinguishedname'][0] }
                    if ($os -match '(?i)server') { $class = 'Server' }
                    if ($dn -match '(?i)OU=Domain Controllers|CN=Domain Controllers') { $class = 'DomainController' }
                    if ($found.Properties.Contains('useraccountcontrol') -and $found.Properties['useraccountcontrol'].Count -gt 0) {
                        $uac = 0
                        if ([int]::TryParse([string]$found.Properties['useraccountcontrol'][0], [ref]$uac)) {
                            if (($uac -band 0x2000) -ne 0) { $class = 'DomainController' }
                        }
                    }
                    $source = 'ActiveDirectory'
                }
            }
        } catch {
            $source = 'HeuristicADLookupFailed'
        }
    }

    $result = [pscustomobject]@{ DeviceClass=$class; ComputerName=$sam; OperatingSystem=$os; DistinguishedName=$dn; Source=$source }
    $script:ComputerClassCache[$key] = $result
    return $result
}

function Resolve-CAConfigSafe {
    param([string]$Preferred)
    if (-not [string]::IsNullOrWhiteSpace($Preferred)) { return $Preferred.Trim() }
    try {
        $out = & certutil.exe -config - -ping 2>&1
        $line = $out | Where-Object { $_ -match '\\\\|\\' -and $_ -match '-' } | Select-Object -First 1
        if ($line) { return ([string]$line).Trim().Trim('"') }
    } catch { }
    return $env:COMPUTERNAME
}




function Add-ExecutionTimeline {
    param(
        [Parameter(Mandatory)][string]$Stage,
        [string]$Detail = '',
        [ValidateSet('INFO','SUCCESS','WARN','ERROR')][string]$Level = 'INFO'
    )
    try {
        if (-not $script:ExecutionTimeline) { $script:ExecutionTimeline = New-Object System.Collections.ArrayList }
        [void]$script:ExecutionTimeline.Add([pscustomobject]@{
            Timestamp = Get-Date
            ExecutionID = $script:RunStamp
            Level = $Level
            Stage = $Stage
            Detail = $Detail
        })
    } catch { }
}

function Export-ExecutionTimeline {
    param([string]$NamePrefix = 'PKI-Execution-Timeline')
    if (-not $script:ExecutionTimeline -or $script:ExecutionTimeline.Count -eq 0) { return $null }
    $file = Join-Path $script:ReportRoot ("{0}-{1}.csv" -f $NamePrefix,$script:RunStamp)
    $script:ExecutionTimeline | Export-Csv -Path $file -NoTypeInformation -Encoding UTF8
    return $file
}

function Get-PKIRiskAssessment {
    param([object]$Item, [string]$Mode = 'Lifecycle')
    $level = 'MEDIUM'
    $reason = 'Standard operator review required'
    if ($Mode -eq 'Cleanup') {
        $level = 'LOW'; $reason = 'Revoked row is older than retention and cleanup does not revoke certificates'
        if ($Item.OldTemplate -match 'Domain Controller|Controlador de Domínio|Kerberos|CA|Certification Authority') {
            $level = 'MEDIUM'; $reason = 'Revoked infrastructure-template record; cleanup only, but verify retention and audit requirements'
        }
        return [pscustomobject]@{ Level=$level; Reason=$reason }
    }
    if ($Item.Status -eq 'READY' -and [bool]$Item.ReplacementFound -and [bool]$Item.TemplateAllowed) {
        $level = 'LOW'; $reason = 'Expired certificate, allowed template, same requester/template, valid replacement found'
    } elseif ($Item.Status -eq 'READY' -and [bool]$Item.TemplateAllowed -and -not [bool]$Item.ReplacementFound) {
        $level = 'HIGH'; $reason = 'Expired certificate selected because VerifyReplacement=false; no replacement was confirmed'
    } elseif ($Item.Status -eq 'MANUAL REVIEW' -and [bool]$Item.TemplateAllowed -and -not [bool]$Item.ReplacementFound) {
        $level = 'HIGH'; $reason = 'Expired certificate is allowed, but no currently valid replacement was found'
    } elseif (-not [bool]$Item.TemplateAllowed) {
        $level = 'HIGH'; $reason = 'Template is not allowed or is explicitly excluded'
    }
    return [pscustomobject]@{ Level=$level; Reason=$reason }
}

function Test-PKIPreFlight {
    [CmdletBinding()]
    param(
        [ValidateSet('Revoke','Cleanup','Preview')][string]$Mode,
        [bool]$DryRun = $true
    )
    $results = New-Object System.Collections.ArrayList
    function Add-Check([string]$Name,[bool]$Passed,[string]$Detail) {
        [void]$results.Add([pscustomobject]@{ Name=$Name; Passed=$Passed; Detail=$Detail })
    }
    Add-Check 'CAConfig present' (-not [string]::IsNullOrWhiteSpace([string]$script:CAConfig)) ([string]$script:CAConfig)
    $certutil = Get-Command certutil.exe -ErrorAction SilentlyContinue
    Add-Check 'certutil.exe available' ([bool]$certutil) ($(if($certutil){$certutil.Source}else{'not found'}))
    try { $view = New-Object -ComObject CertificateAuthority.View; Add-Check 'ICertView COM available' $true 'CertificateAuthority.View created' } catch { Add-Check 'ICertView COM available' $false $_.Exception.Message }
    if ($Mode -in @('Revoke','Cleanup') -and -not $DryRun) {
        $needBackup = $false
        if ($Mode -eq 'Revoke' -and [bool]$script:Config.RequireBackup) { $needBackup = $true }
        if ($Mode -eq 'Cleanup' -and [bool]$script:Config.BackupBeforeCleanup) { $needBackup = $true }
        if ($needBackup) {
            $root = [string]$script:Config.BackupRoot
            try { if (-not (Test-Path $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }; Add-Check 'Backup root writable' $true $root }
            catch { Add-Check 'Backup root writable' $false $_.Exception.Message }
        }
        try {
            $drive = Get-PSDrive -Name ([IO.Path]::GetPathRoot($script:ReportRoot).TrimEnd(':\')) -ErrorAction SilentlyContinue
            $ok = $false; $detail = 'unknown'
            if ($drive) { $ok = ($drive.Free -gt 1GB); $detail = ('Free={0:N2} GB' -f ($drive.Free/1GB)) }
            Add-Check 'Report disk free space' $ok $detail
        } catch { Add-Check 'Report disk free space' $false $_.Exception.Message }
    }
    $script:LastPreFlight = @($results)
    foreach ($r in $results) {
        if ($r.Passed) { Write-AppLog "PreFlight[$Mode] PASS: $($r.Name) - $($r.Detail)" 'SUCCESS' }
        else { Write-AppLog "PreFlight[$Mode] FAIL: $($r.Name) - $($r.Detail)" 'ERROR' }
    }
    if (@($results | Where-Object { -not $_.Passed }).Count -gt 0) { return $false }
    return $true
}

function Assert-PKIPreFlight {
    param([string]$Mode,[bool]$DryRun=$true)
    if (-not [bool]$script:Config.EnablePreFlightChecks) { return }
    Add-ExecutionTimeline -Stage "PreFlight $Mode" -Detail 'Started' -Level 'INFO'
    $ok = Test-PKIPreFlight -Mode $Mode -DryRun $DryRun
    if (-not $ok) {
        Add-ExecutionTimeline -Stage "PreFlight $Mode" -Detail 'Failed' -Level 'ERROR'
        throw "Pre-flight validation failed for $Mode. Review the runtime log before proceeding."
    }
    Add-ExecutionTimeline -Stage "PreFlight $Mode" -Detail 'Passed' -Level 'SUCCESS'
}

# =====================================================================================
# Configuration - v5.0
# =====================================================================================
function Load-Configuration {
    [CmdletBinding()]
    param([string]$Path = $script:ConfigPath)

    $cfg = [pscustomobject]$script:DefaultConfig
    if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path)) {
        try {
            $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $json.PSObject.Properties) {
                try { $cfg | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force } catch { }
            }
            Write-AppLog "Configuration loaded: $Path" 'SUCCESS'
        } catch {
            throw "Failed to load config.json from '$Path'. $($_.Exception.Message)"
        }
    } else {
        try {
            $script:DefaultConfig | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -Encoding UTF8
            Write-AppLog "Default configuration created: $Path" 'WARN'
        } catch {
            Write-AppLog "Default configuration could not be created at '$Path'. $($_.Exception.Message)" 'WARN'
        }
    }

    if (-not $cfg.RetentionDays -or [int]$cfg.RetentionDays -lt 30) { $cfg.RetentionDays = 365 }
    if (-not (Get-Member -InputObject $cfg -Name 'LifecycleRetentionDays' -MemberType NoteProperty -ErrorAction SilentlyContinue) -or [int]$cfg.LifecycleRetentionDays -lt 0) { $cfg | Add-Member -NotePropertyName LifecycleRetentionDays -NotePropertyValue 30 -Force }
    if (-not (Get-Member -InputObject $cfg -Name 'RevokedRetentionDays' -MemberType NoteProperty -ErrorAction SilentlyContinue) -or [int]$cfg.RevokedRetentionDays -lt 30) { $cfg | Add-Member -NotePropertyName RevokedRetentionDays -NotePropertyValue ([int]$cfg.RetentionDays) -Force }
    if (-not (Get-Member -InputObject $cfg -Name 'FailedRetentionDays' -MemberType NoteProperty -ErrorAction SilentlyContinue) -or [int]$cfg.FailedRetentionDays -lt 30) { $cfg | Add-Member -NotePropertyName FailedRetentionDays -NotePropertyValue ([int]$cfg.RetentionDays) -Force }
    if (-not (Get-Member -InputObject $cfg -Name 'FailedRequestDispositions' -MemberType NoteProperty -ErrorAction SilentlyContinue) -or -not $cfg.FailedRequestDispositions) { $cfg | Add-Member -NotePropertyName FailedRequestDispositions -NotePropertyValue @(30,31) -Force }
    if (-not $cfg.AllowedTemplates) { $cfg.AllowedTemplates = $script:DefaultConfig.AllowedTemplates }
    if (-not $cfg.ExcludedTemplates) { $cfg.ExcludedTemplates = $script:DefaultConfig.ExcludedTemplates }
    if ([string]::IsNullOrWhiteSpace([string]$cfg.BackupRoot)) { $cfg.BackupRoot = 'D:\PKIBackup' }
    $script:Config = $cfg
    return $cfg
}

function Initialize-Application {
    [CmdletBinding()]
    param()
    New-Item -ItemType Directory -Path $script:LogRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $script:ReportRoot -Force | Out-Null
    $cfg = Load-Configuration
    if ([string]::IsNullOrWhiteSpace($script:CAConfig)) { $script:CAConfig = Resolve-CAConfigSafe ([string]$cfg.CAConfig) }
    Write-AppLog 'Application initialized.' 'SUCCESS'
}


function Get-PKITemplateDirectoryMap {
    [CmdletBinding()]
    param()

    if (Get-Variable -Name TemplateDirectoryMap -Scope Script -ErrorAction SilentlyContinue) {
        if ($script:TemplateDirectoryMap -and $script:TemplateDirectoryMap.Count -gt 0) { return $script:TemplateDirectoryMap }
    }

    $map = @{}
    try {
        $root = [ADSI]'LDAP://RootDSE'
        $configNC = [string]$root.configurationNamingContext
        if ([string]::IsNullOrWhiteSpace($configNC)) { throw 'configurationNamingContext is empty.' }
        $base = [ADSI]('LDAP://CN=Certificate Templates,CN=Public Key Services,CN=Services,' + $configNC)
        $searcher = New-Object DirectoryServices.DirectorySearcher($base)
        $searcher.Filter = '(objectClass=pKICertificateTemplate)'
        $searcher.PageSize = 500
        foreach ($prop in @('cn','displayName','name','msPKI-Cert-Template-OID')) { [void]$searcher.PropertiesToLoad.Add($prop) }
        $results = $searcher.FindAll()
        foreach ($r in $results) {
            $cn = $null; $display = $null; $name = $null; $oid = $null
            if ($r.Properties['cn'] -and $r.Properties['cn'].Count -gt 0) { $cn = [string]$r.Properties['cn'][0] }
            if ($r.Properties['displayname'] -and $r.Properties['displayname'].Count -gt 0) { $display = [string]$r.Properties['displayname'][0] }
            if ($r.Properties['name'] -and $r.Properties['name'].Count -gt 0) { $name = [string]$r.Properties['name'][0] }
            if ($r.Properties['mspki-cert-template-oid'] -and $r.Properties['mspki-cert-template-oid'].Count -gt 0) { $oid = [string]$r.Properties['mspki-cert-template-oid'][0] }
            $obj = [pscustomobject]@{
                OID = $oid
                Name = $(if ($name) { $name } else { $cn })
                CN = $cn
                DisplayName = $(if ($display) { $display } elseif ($cn) { $cn } else { $name })
            }
            foreach ($key in @($oid,$cn,$display,$name)) {
                $nk = Normalize-PKIText $key
                if ($nk -and -not $map.ContainsKey($nk)) { $map[$nk] = $obj }
            }
        }
        Write-AppLog "Enterprise certificate templates resolved from AD: $($results.Count)" 'SUCCESS'
    } catch {
        Write-AppLog "Could not resolve Enterprise Certificate Templates from AD. Raw template values will be used. Error=$($_.Exception.Message)" 'WARN'
    }
    $script:TemplateDirectoryMap = $map
    return $script:TemplateDirectoryMap
}

function Resolve-PKICertificateTemplate {
    [CmdletBinding()]
    param([AllowNull()][string]$RawTemplate)

    $raw = if ($RawTemplate) { ([string]$RawTemplate).Trim() } else { '' }
    $oidPattern = '^\d+(\.\d+)+$'
    $obj = [pscustomobject]@{
        Raw = $raw
        OID = $null
        Name = $raw
        DisplayName = $raw
        Resolved = $false
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $obj }
    if ($raw -match $oidPattern) { $obj.OID = $raw }

    $map = Get-PKITemplateDirectoryMap
    $key = Normalize-PKIText $raw
    if ($map -and $map.ContainsKey($key)) {
        $t = $map[$key]
        $obj.OID = $t.OID
        $obj.Name = $t.Name
        $obj.DisplayName = $t.DisplayName
        $obj.Resolved = $true
    }
    return $obj
}

function Test-TemplateAllowedV5 {
    param([AllowNull()][string]$Template, [AllowNull()][object]$Certificate)
    $candidateValues = New-Object System.Collections.Generic.List[string]
    foreach ($v in @($Template)) { if (-not [string]::IsNullOrWhiteSpace([string]$v)) { [void]$candidateValues.Add([string]$v) } }
    if ($Certificate) {
        foreach ($pn in @('Template','TemplateName','TemplateDisplayName','TemplateOID')) {
            if ($Certificate.PSObject.Properties.Name -contains $pn) {
                $v = [string]$Certificate.$pn
                if (-not [string]::IsNullOrWhiteSpace($v) -and -not $candidateValues.Contains($v)) { [void]$candidateValues.Add($v) }
            }
        }
    }
    if ($candidateValues.Count -eq 0) { return $false }

    foreach ($candidate in $candidateValues) {
        foreach ($ex in @($script:Config.ExcludedTemplates)) {
            if (Test-PKITemplateMatch -CertTemplate $candidate -Filters @([string]$ex)) { return $false }
        }
    }
    if (-not $script:Config.AllowedTemplates -or @($script:Config.AllowedTemplates).Count -eq 0) { return $true }
    foreach ($candidate in $candidateValues) {
        if (Test-PKITemplateMatch -CertTemplate $candidate -Filters @($script:Config.AllowedTemplates)) { return $true }
    }
    return $false
}

function New-LifecycleSnapshot {
    [CmdletBinding()]
    param([string]$NamePrefix = 'Snapshot')
    if (-not (Test-Path $script:ReportRoot)) { New-Item -ItemType Directory -Path $script:ReportRoot -Force | Out-Null }
    $file = Join-Path $script:ReportRoot ("{0}-{1}.csv" -f $NamePrefix,(Get-Date -Format 'yyyyMMdd-HHmmss'))
    $script:PreviewItems |
        Select-Object Index,Selected,Status,Decision,RiskLevel,RiskReason,Result,OldRequestID,OldSerialNumber,OldRequesterName,OldCommonName,OldTemplate,OldTemplateRaw,OldTemplateOID,OldTemplateName,OldTemplateResolved,OldNotBefore,OldNotAfter,ReplacementFound,ReplacementCandidateCount,ReplacementDecisionTrace,ReplacementRequestID,ReplacementSerialNumber,ReplacementNotBefore,ReplacementNotAfter,LifecycleRetentionDays,LifecycleCutoff,DaysExpired,RevocationDate,RetentionCutoff |
        Export-Csv -Path $file -NoTypeInformation -Encoding UTF8
    $script:Stats.SnapshotActions++
    Write-AppLog "Snapshot generated: $file" 'SUCCESS'
    return $file
}

# =====================================================================================
# Execution actions - revocation, CRL, cleanup and backup
# =====================================================================================

function Invoke-RevokeSupersededCertificates {
    [CmdletBinding()]
    param([bool]$DryRun = $true)

    Assert-CertutilAvailable
    if (-not $script:PreviewItems -or $script:PreviewItems.Count -eq 0) {
        Write-AppLog 'No lifecycle preview rows are loaded. Run Lifecycle Preview first.' 'WARN'
        return
    }

    $targets = @($script:PreviewItems | Where-Object { $_.Selected -eq $true -and $_.Status -eq 'READY' -and $_.Decision -eq 'ReadyToRevoke' })
    if ($targets.Count -eq 0) {
        Write-AppLog 'No selected READY certificates to process.' 'WARN'
        return
    }

    $executionId = New-PKIExecutionId
    Add-ExecutionTimeline -Stage 'Revoke Selected' -Detail "Started. ExecutionID=$executionId Targets=$($targets.Count) DryRun=$DryRun" -Level 'INFO'
    Assert-PKIPreFlight -Mode 'Revoke' -DryRun $DryRun
    [void](New-LifecycleSnapshot -NamePrefix "Snapshot-Revoke-$executionId")
    Write-AppLog "Revoke Selected started. ExecutionID=$executionId Targets=$($targets.Count), DryRun=$DryRun" 'INFO'

    if (-not $DryRun -and [bool]$script:Config.BackupBeforeApply) {
        Write-AppLog "BackupBeforeApply=true. Running CA backup before revocation. ExecutionID=$executionId" 'INFO'
        Invoke-CABackup -Root ([string]$script:Config.BackupRoot) -IncludePrivateKey ([bool]$script:Config.BackupPrivateKey)
    } elseif (-not $DryRun) {
        Write-AppLog 'BackupBeforeApply=false. Proceeding without pre-apply CA backup by configuration.' 'WARN'
    }

    $processed = 0
    $dryRunCount = 0
    foreach ($item in $targets) {
        $processed++
        Update-Progress -Current $processed -Total $targets.Count -Message "Revoke Selected: processing $processed of $($targets.Count)..."
        $serial = [string]$item.OldSerialNumber
        if ([string]::IsNullOrWhiteSpace($serial)) {
            $item.Status = 'FAILED'; $item.Decision = 'RevokeFailed'; $item.Result = 'Missing serial number'; $script:Stats.Failed++
            Write-AppLog "Skipping RequestID=$($item.OldRequestID): missing serial number." 'ERROR'
            continue
        }
        $requireReplacementAtApply = Get-PKIBoolConfigValue -Name 'VerifyReplacement' -Default $true
        # v5.5.2 correction:
        # Apply honors the Lifecycle Preview READY decision. READY is based on OldNotAfter being beyond
        # the lifecycle retention cutoff. Replacement presence is logged as diagnostic evidence and no
        # longer downgrades a selected READY row to Manual Review at apply time.
        if (-not [bool]$item.ReplacementFound) {
            Write-AppLog "Lifecycle READY without confirmed replacement. RequestID=$($item.OldRequestID), Serial=${serial}. VerifyReplacement=$requireReplacementAtApply. Proceeding because Lifecycle Preview classified the row as READY based on OldNotAfter." 'WARN'
        }
        if ($DryRun) {
            $dryRunCount++
            $item.Status = 'DRYRUN'; $item.Decision = 'DryRun'; $item.Result = 'Dry Run: would revoke certificate as Superseded'
            Write-AppLog "DRYRUN: would revoke RequestID=$($item.OldRequestID), Serial=$serial, Reason=Superseded" 'INFO'
            continue
        }
        try {
            Write-AppLog "Revoking RequestID=$($item.OldRequestID), Serial=$serial, Reason=Superseded, ExecutionID=$executionId" 'INFO'
            $output = & certutil.exe -config $script:CAConfig -revoke $serial Superseded 2>&1
            $exitCode = $LASTEXITCODE
            if ($exitCode -eq 0) {
                $verified = Test-PKIRevocationVerified -SerialNumber $serial -CAConfigValue $script:CAConfig
                if ($verified) {
                    $item.Status = 'REVOKED'; $item.Decision = 'Revoked'; $item.Result = 'Revoked successfully with reason Superseded and verified in CA database'; $item.Selected = $false
                    $script:Stats.Revoked++
                    Write-AppLog "Revoked and verified. RequestID=$($item.OldRequestID), Serial=$serial" 'SUCCESS'
                } else {
                    $item.Status = 'VERIFY_PENDING'; $item.Decision = 'RevokeVerificationPending'; $item.Result = 'certutil -revoke returned success, but immediate CA database verification did not confirm revocation yet'
                    Write-AppLog "Revocation command succeeded but verification is pending. RequestID=$($item.OldRequestID), Serial=$serial" 'WARN'
                }
            } else {
                $item.Status = 'FAILED'; $item.Decision = 'RevokeFailed'; $item.Result = "certutil -revoke failed. ExitCode=$exitCode. Output=$($output -join ' ')"; $script:Stats.Failed++
                Write-AppLog $item.Result 'ERROR'
            }
        } catch {
            $item.Status = 'FAILED'; $item.Decision = 'RevokeFailed'; $item.Result = $_.Exception.Message; $script:Stats.Failed++
            Write-AppLog "Revoke exception for RequestID=$($item.OldRequestID), Serial=$serial. Error=$($_.Exception.Message)" 'ERROR'
        }
    }

    if (-not $DryRun -and $script:Stats.Revoked -gt 0) {
        if ([bool]$script:Config.PublishDeltaCRL) { Publish-DeltaCRL }
        if ([bool]$script:Config.PublishFullCRL) { Publish-CARevocationLists -FullCRL $true -DeltaCRL $false }
    }
    Refresh-PreviewGrid; Refresh-StatisticsView
    Export-Reports -NamePrefix "PKI-Lifecycle-Apply-$executionId" | Out-Null
    Update-Progress -Current 100 -Total 100 -Message 'Revoke Selected completed.'
    Add-ExecutionTimeline -Stage 'Revoke Selected' -Detail "Completed. ExecutionID=$executionId DryRun=$DryRun DryRunTargets=$dryRunCount Revoked=$($script:Stats.Revoked) Failed=$($script:Stats.Failed)" -Level 'SUCCESS'
    Write-AppLog "Revoke Selected completed. ExecutionID=$executionId DryRun=$DryRun DryRunTargets=$dryRunCount, Revoked=$($script:Stats.Revoked), Failed=$($script:Stats.Failed)" 'SUCCESS'
}

function Invoke-RevokeSelectedExpiredCertificates {
    [CmdletBinding()]
    param([bool]$DryRun = $true, [bool]$ForceNoReplacement = $false)
    if ($ForceNoReplacement) { Write-AppLog 'ForceNoReplacement is intentionally ignored in v5.4 Enterprise Edition. Replacement verification is mandatory.' 'WARN' }
    Invoke-RevokeSupersededCertificates -DryRun $DryRun
}

function Publish-DeltaCRL {
    [CmdletBinding()]
    param()
    # AD CS certutil does not expose a valid "-delta" publication verb/switch on the
    # target platform.  Delta publication is triggered through the standard CRL
    # publication verb when delta CRLs are enabled on the CA.
    Publish-CARevocationLists -FullCRL $false -DeltaCRL $true
}

function Publish-CARevocationLists {
    [CmdletBinding()]
    param([bool]$FullCRL = $false, [bool]$DeltaCRL = $true)

    Assert-CertutilAvailable
    if ([string]::IsNullOrWhiteSpace($script:CAConfig)) { throw 'CAConfig is empty. Run Lifecycle Preview or set CA Config first.' }

    if (-not $FullCRL -and -not $DeltaCRL) {
        Write-AppLog 'CRL publication skipped. Neither Full CRL nor Delta CRL was selected.' 'WARN'
        Refresh-StatisticsView; Update-StatusBar 'CRL publication skipped.'
        return
    }

    $requested = @()
    if ($FullCRL)  { $requested += 'Full CRL' }
    if ($DeltaCRL) { $requested += 'Delta CRL' }

    # Correct AD CS command:
    #   certutil -config "CAHost\CAName" -CRL
    # This publishes the CA revocation lists according to the CA configuration.
    # Using "-delta" is invalid on Windows Server certutil and returns:
    #   CertUtil: Unknown arg: -delta
    Write-AppLog "Publishing CRL using certutil -CRL. Requested=$($requested -join ', ')." 'INFO'
    $out = & certutil.exe -config $script:CAConfig -CRL 2>&1

    if ($LASTEXITCODE -eq 0) {
        if ($FullCRL)  { $script:Stats.CRLPublished++ }
        if ($DeltaCRL) { $script:Stats.DeltaCRLPublished++ }
        Write-AppLog "CRL publication command completed successfully. Requested=$($requested -join ', ')." 'SUCCESS'
    }
    else {
        $script:Stats.Failed++
        Write-AppLog "CRL publication failed. ExitCode=$LASTEXITCODE. Requested=$($requested -join ', '). Output=$($out -join ' ')" 'ERROR'
    }

    Refresh-StatisticsView
    Update-StatusBar 'CRL publication completed.'
}

function Invoke-CABackup {
    [CmdletBinding()]
    param([string]$Root = 'D:\PKIBackup', [bool]$IncludePrivateKey = $false)
    Assert-CertutilAvailable
    if ([string]::IsNullOrWhiteSpace($Root)) { throw 'Backup root is empty.' }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $target = Join-Path $Root "CA-Backup-$stamp"
    $dbPath = Join-Path $target 'Database'
    $regPath = Join-Path $target 'Registry'
    New-Item -ItemType Directory -Path $dbPath,$regPath -Force | Out-Null
    Write-AppLog "Backing up CA database to $dbPath" 'INFO'
    $out = & certutil.exe -config $script:CAConfig -backupDB $dbPath 2>&1
    if ($LASTEXITCODE -eq 0) { $script:Stats.BackupActions++; Write-AppLog 'CA database backup completed.' 'SUCCESS' } else { $script:Stats.Failed++; Write-AppLog "CA database backup failed. ExitCode=$LASTEXITCODE. Output=$($out -join ' ')" 'ERROR' }
    if ($IncludePrivateKey) {
        $keyPath = Join-Path $target 'PrivateKey'
        New-Item -ItemType Directory -Path $keyPath -Force | Out-Null
        Write-AppLog "Backing up CA private key to $keyPath" 'INFO'
        $out = & certutil.exe -config $script:CAConfig -backupKey $keyPath 2>&1
        if ($LASTEXITCODE -eq 0) { $script:Stats.BackupActions++; Write-AppLog 'CA private key backup completed.' 'SUCCESS' } else { $script:Stats.Failed++; Write-AppLog "CA private key backup failed. ExitCode=$LASTEXITCODE. Output=$($out -join ' ')" 'ERROR' }
    } else { Write-AppLog 'Private key backup skipped by configuration.' 'INFO' }
    $regFile = Join-Path $regPath 'CertSvc.reg'
    Write-AppLog "Exporting CertSvc registry to $regFile" 'INFO'
    $out = & reg.exe export 'HKLM\SYSTEM\CurrentControlSet\Services\CertSvc' $regFile /y 2>&1
    if ($LASTEXITCODE -eq 0) { $script:Stats.BackupActions++; Write-AppLog 'CertSvc registry export completed.' 'SUCCESS' } else { $script:Stats.Failed++; Write-AppLog "CertSvc registry export failed. ExitCode=$LASTEXITCODE. Output=$($out -join ' ')" 'ERROR' }
    Refresh-StatisticsView; Update-StatusBar 'CA backup completed.'
}

function Get-RevokedCleanupCandidates {
    [CmdletBinding()]
    param([int]$RetentionDays = 365)
    if ($RetentionDays -lt 30) { throw 'Retention days must be 30 or greater for safety.' }
    $cutoff = (Get-Date).AddDays(-1 * $RetentionDays)
    Add-ExecutionTimeline -Stage 'Cleanup Preview' -Detail "Started. RetentionDays=$RetentionDays Cutoff=$cutoff" -Level 'INFO'
    Write-AppLog "Loading revoked certificates for cleanup preview. RetentionDays=$RetentionDays, Cutoff=$cutoff" 'INFO'
    $rows = @(Invoke-CertViewRepositoryQuery -CAConfigValue $script:CAConfig -Disposition 21 -IncludeRevocationColumns)
    Write-AppLog "Cleanup repository returned revoked rows=$($rows.Count). Applying retention cutoff." 'INFO'
    $list = New-Object System.Collections.ArrayList
    $idx = 0
    $seen = 0
    $missingRevocationDate = 0
    $notOldEnough = 0
    foreach ($row in $rows) {
        $seen++
        if (($seen % 100) -eq 0 -or $seen -eq $rows.Count) { Update-Progress -Current $seen -Total $rows.Count -Message "Cleanup Preview: evaluated $seen of $($rows.Count) revoked rows..." }
        $cert = New-PKICertObject -Row $row
        $revRaw = Get-PropValue $row @('Request.RevokedWhen','Request.RevokedEffectiveWhen','RevokedWhen','RevokedEffectiveWhen','RevocationDate','Revoked Effective Date','Revocation Effective Date','Revocation Date','Revoked Date','Data de Revogação')
        $revDate = if ($cert.RevocationDate) { $cert.RevocationDate } else { Convert-CADate $revRaw }
        if (-not $revDate) { $missingRevocationDate++; continue }
        if ($revDate -ge $cutoff) { $notOldEnough++; continue }
        $idx++
        $cleanupRiskSeed = [pscustomobject]@{ OldTemplate=$cert.Template }
        $cleanupRisk = if ([bool]$script:Config.EnableRiskAnalysis) { Get-PKIRiskAssessment -Item $cleanupRiskSeed -Mode 'Cleanup' } else { [pscustomobject]@{ Level=''; Reason='' } }
        [void]$list.Add([pscustomobject]@{
            Index=$idx; Selected=$true; Status='CLEANUP_READY'; Decision='ReadyToDeleteRevokedRow'; RiskLevel=$cleanupRisk.Level; RiskReason=$cleanupRisk.Reason; Result='Revoked database record is older than retention and eligible for cleanup'
            CleanupRepository='Revoked'; OldRequestID=$cert.RequestID; OldSerialNumber=$cert.SerialNumber; OldRequesterName=$cert.RequesterName; OldCommonName=$cert.CommonName; OldTemplate=$cert.Template; OldTemplateRaw=$cert.TemplateRaw; OldTemplateOID=$cert.TemplateOID; OldTemplateName=$cert.TemplateName; OldTemplateResolved=$cert.TemplateResolved; RevocationReason=$cert.RevocationReason
            DeviceClass=$cert.DeviceClass; ComputerName=$cert.ComputerName; OperatingSystem=$cert.OperatingSystem; DeviceClassSource=$cert.DeviceClassSource
            OldNotBefore=$cert.NotBefore; OldNotAfter=$cert.NotAfter; RevocationDate=$revDate; RetentionCutoff=$cutoff
            ReplacementFound=$false; ReplacementRequestID=$null; ReplacementSerialNumber=$null; ReplacementNotBefore=$null; ReplacementNotAfter=$null
        })
    }
    $script:Stats.CleanupCandidates = $list.Count
    if ($missingRevocationDate -gt 0) { Write-AppLog "Cleanup preview skipped revoked rows with missing/unparseable RevocationDate=$missingRevocationDate. Review ICertView-Columns and normalized CSV." 'WARN' }
    Add-ExecutionTimeline -Stage 'Cleanup Preview' -Detail "Candidates=$($list.Count) Evaluated=$seen NotOldEnough=$notOldEnough MissingRevocationDate=$missingRevocationDate" -Level 'SUCCESS'
    Write-AppLog "Cleanup preview candidates: $($list.Count). RevokedRowsEvaluated=$seen, NotOldEnough=$notOldEnough, MissingRevocationDate=$missingRevocationDate, RetentionDays=$RetentionDays, Cutoff=$cutoff" 'SUCCESS'
    return @($list)
}


function Get-FailedCleanupCandidates {
    [CmdletBinding()]
    param([int]$RetentionDays = 365)
    if ($RetentionDays -lt 30) { throw 'Failed request retention days must be 30 or greater for safety.' }
    $cutoff = (Get-Date).AddDays(-1 * $RetentionDays)
    Add-ExecutionTimeline -Stage 'Failed Preview' -Detail "Started. RetentionDays=$RetentionDays Cutoff=$cutoff" -Level 'INFO'
    Write-AppLog "Loading failed requests for cleanup preview. RetentionDays=$RetentionDays, Cutoff=$cutoff" 'INFO'
    $failedDispositions = @()
    try { $failedDispositions = @($script:Config.FailedRequestDispositions | ForEach-Object { [int]$_ }) } catch { $failedDispositions = @() }
    if (-not $failedDispositions -or $failedDispositions.Count -eq 0) { $failedDispositions = @(30,31) }
    $rowMap = @{}
    foreach ($disp in $failedDispositions) {
        try {
            $dispRows = @(Invoke-CertViewRepositoryQuery -CAConfigValue $script:CAConfig -Disposition $disp)
            Write-AppLog "Failed request repository disposition=$disp returned rows=$($dispRows.Count)." 'INFO'
            foreach ($r in $dispRows) {
                $rid = Get-PropValue $r @('RequestID','Request.RequestID','Request ID','ID da Solicitação')
                if ([string]::IsNullOrWhiteSpace([string]$rid)) { $rid = [guid]::NewGuid().ToString() }
                if (-not $rowMap.ContainsKey([string]$rid)) { $rowMap[[string]$rid] = $r }
            }
        } catch {
            Write-AppLog "Failed request repository disposition=$disp query failed. $($_.Exception.Message)" 'WARN'
        }
    }
    $rows = @($rowMap.Values)
    Write-AppLog "Failed request repository returned rows=$($rows.Count) from dispositions=$($failedDispositions -join ','). Applying retention cutoff." 'INFO'
    $list = New-Object System.Collections.ArrayList
    $idx = 0
    $seen = 0
    $missingRequestDate = 0
    $notOldEnough = 0
    foreach ($row in $rows) {
        $seen++
        if (($seen % 100) -eq 0 -or $seen -eq $rows.Count) { Update-Progress -Current $seen -Total $rows.Count -Message "Failed Preview: evaluated $seen of $($rows.Count) failed rows..." }
        $cert = New-PKICertObject -Row $row
        $requestDate = $cert.SubmittedWhen
        if (-not $requestDate) { $requestDate = $cert.ResolvedWhen }
        if (-not $requestDate) {
            $rawDate = Get-PropValue $row @('Request.SubmittedWhen','SubmittedWhen','Request Submission Date','Submission Date','Data da Solicitação','Data de Envio da Solicitação','Request.ResolvedWhen','ResolvedWhen')
            $requestDate = Convert-CADate $rawDate
        }
        if (-not $requestDate) { $missingRequestDate++; continue }
        if ($requestDate -ge $cutoff) { $notOldEnough++; continue }
        $idx++
        $failureMessage = if ($cert.DispositionMessage) { $cert.DispositionMessage } else { [string]$cert.Disposition }
        $failureRisk = [pscustomobject]@{ Level='LOW'; Reason='Failed request row is older than retention and cleanup does not affect issued certificates' }
        if ($cert.Template -match 'Domain Controller|Kerberos|CA Exchange|Certification Authority|SubCA') {
            $failureRisk = [pscustomobject]@{ Level='MEDIUM'; Reason='Old failed request for infrastructure-related template; cleanup only, but verify audit requirements' }
        }
        [void]$list.Add([pscustomobject]@{
            Index=$idx; Selected=$true; Status='FAILED_CLEANUP_READY'; Decision='ReadyToDeleteFailedRequest'; RiskLevel=$failureRisk.Level; RiskReason=$failureRisk.Reason; Result='Failed request record is older than retention and eligible for cleanup'
            CleanupRepository='Failed'; OldRequestID=$cert.RequestID; OldSerialNumber=$cert.SerialNumber; OldRequesterName=$cert.RequesterName; OldCommonName=$cert.CommonName; OldTemplate=$cert.Template; OldTemplateRaw=$cert.TemplateRaw; OldTemplateOID=$cert.TemplateOID; OldTemplateName=$cert.TemplateName; OldTemplateResolved=$cert.TemplateResolved; RevocationReason=$null
            DeviceClass=$cert.DeviceClass; ComputerName=$cert.ComputerName; OperatingSystem=$cert.OperatingSystem; DeviceClassSource=$cert.DeviceClassSource
            OldNotBefore=$cert.NotBefore; OldNotAfter=$cert.NotAfter; RequestDate=$requestDate; SubmittedWhen=$cert.SubmittedWhen; ResolvedWhen=$cert.ResolvedWhen; DispositionMessage=$failureMessage; RetentionCutoff=$cutoff
            ReplacementFound=$false; ReplacementRequestID=$null; ReplacementSerialNumber=$null; ReplacementNotBefore=$null; ReplacementNotAfter=$null; RevocationDate=$null
        })
    }
    $script:Stats.FailedCleanupCandidates = $list.Count
    if ($missingRequestDate -gt 0) { Write-AppLog "Failed preview skipped rows with missing/unparseable request date=$missingRequestDate. Review ICertView-Columns and normalized CSV." 'WARN' }
    Add-ExecutionTimeline -Stage 'Failed Preview' -Detail "Candidates=$($list.Count) Evaluated=$seen NotOldEnough=$notOldEnough MissingRequestDate=$missingRequestDate" -Level 'SUCCESS'
    Write-AppLog "Failed cleanup preview candidates: $($list.Count). FailedRowsEvaluated=$seen, NotOldEnough=$notOldEnough, MissingRequestDate=$missingRequestDate, RetentionDays=$RetentionDays, Cutoff=$cutoff" 'SUCCESS'
    return @($list)
}

function Invoke-RemoveOldRevokedCertificates {
    [CmdletBinding()]
    param([int]$RetentionDays = 365, [bool]$DryRun = $true, [bool]$CompactDatabase = $false)
    Assert-CertutilAvailable
    if ($RetentionDays -lt 30) { throw 'Retention days must be 30 or greater for safety.' }
    $targets = @($script:PreviewItems | Where-Object { $_.Selected -eq $true -and ($_.Status -eq 'CLEANUP_READY' -or $_.Status -eq 'FAILED_CLEANUP_READY') })
    if ($targets.Count -eq 0) { Write-AppLog 'No selected cleanup candidates are loaded. Run Revoked Preview or Failed Preview first.' 'WARN'; return }
    $executionId = New-PKIExecutionId
    Add-ExecutionTimeline -Stage 'Cleanup Selected' -Detail "Started. ExecutionID=$executionId Targets=$($targets.Count) DryRun=$DryRun" -Level 'INFO'
    Assert-PKIPreFlight -Mode 'Cleanup' -DryRun $DryRun
    [void](New-LifecycleSnapshot -NamePrefix "Cleanup-Snapshot-$executionId")
    Write-AppLog "Cleanup Selected started. ExecutionID=$executionId Targets=$($targets.Count) DryRun=$DryRun" 'INFO'
    if ([bool]$script:Config.BackupBeforeCleanup -and -not $DryRun) { Invoke-CABackup -Root ([string]$script:Config.BackupRoot) -IncludePrivateKey ([bool]$script:Config.BackupPrivateKey) }
    elseif (-not $DryRun) { Write-AppLog 'BackupBeforeCleanup=false. Proceeding without pre-cleanup CA backup by configuration.' 'WARN' }
    $processed = 0
    $dryRunCount = 0
    foreach ($item in $targets) {
        $processed++
        Update-Progress -Current $processed -Total $targets.Count -Message "Cleanup Selected: processing $processed of $($targets.Count)..."
        if ($DryRun) { $item.Status='DRYRUN'; if ($item.Decision -eq 'ReadyToDeleteFailedRequest') { $item.Decision='FailedCleanupDryRun'; $item.Result='Dry Run: would delete old failed request row' } else { $item.Decision='CleanupDryRun'; $item.Result='Dry Run: would delete old revoked database row' }; $dryRunCount++; continue }
        try {
            $rid = [string]$item.OldRequestID
            if ([string]::IsNullOrWhiteSpace($rid)) { throw 'Missing RequestID for revoked cleanup row.' }
            $cleanupRepository = Get-PropValue $item @('CleanupRepository')
            $isFailedCleanup = ($item.Decision -eq 'ReadyToDeleteFailedRequest' -or $cleanupRepository -eq 'Failed')
            $tableName = if ($isFailedCleanup) { 'Request' } else { 'Cert' }
            $what = if ($isFailedCleanup) { 'failed request row' } else { 'revoked database row' }
            Write-AppLog "Deleting $what RequestID=$rid Table=$tableName ExecutionID=$executionId" 'INFO'
            $out = & certutil.exe -config $script:CAConfig -deleterow $rid $tableName 2>&1
            if ($LASTEXITCODE -eq 0) {
                if ($isFailedCleanup) { $item.Status='FAILED_CLEANED'; $item.Decision='DeletedFailedRequest'; $item.Result='Old failed request row removed'; $script:Stats.FailedCleanupActions++ }
                else { $item.Status='CLEANED'; $item.Decision='DeletedRevokedRow'; $item.Result='Old revoked row removed'; $script:Stats.CleanupActions++ }
                $item.Selected=$false
                Write-AppLog "Deleted $what RequestID=$rid" 'SUCCESS'
            }
            else { $item.Status='FAILED'; $item.Decision='CleanupFailed'; $item.Result="certutil -deleterow $tableName failed. ExitCode=$LASTEXITCODE. Output=$($out -join ' ')"; $script:Stats.Failed++; Write-AppLog $item.Result 'ERROR' }
        } catch { $item.Status='FAILED'; $item.Decision='CleanupFailed'; $item.Result=$_.Exception.Message; $script:Stats.Failed++; Write-AppLog "Cleanup exception: $($_.Exception.Message)" 'ERROR' }
    }
    if ($CompactDatabase -and -not $DryRun) { Invoke-CompactCADatabase }
    Refresh-PreviewGrid; Refresh-StatisticsView; Export-Reports -NamePrefix "PKI-Cleanup-Apply-$executionId" | Out-Null
    Update-Progress -Current 100 -Total 100 -Message 'Cleanup Selected completed.'
    Add-ExecutionTimeline -Stage 'Cleanup Selected' -Detail "Completed. ExecutionID=$executionId DryRun=$DryRun DryRunTargets=$dryRunCount Cleaned=$($script:Stats.CleanupActions) FailedCleaned=$($script:Stats.FailedCleanupActions) Failed=$($script:Stats.Failed)" -Level 'SUCCESS'
    Write-AppLog "Cleanup Selected completed. ExecutionID=$executionId DryRun=$DryRun DryRunTargets=$dryRunCount, Cleaned=$($script:Stats.CleanupActions) FailedCleaned=$($script:Stats.FailedCleanupActions), Failed=$($script:Stats.Failed)" 'SUCCESS'
}

function Invoke-CADatabaseCleanup {
    [CmdletBinding()]
    param([int]$Days = 365)
    Invoke-RemoveOldRevokedCertificates -RetentionDays $Days -DryRun $false -CompactDatabase ([bool]$script:Config.CompactDatabase)
}

function Invoke-CompactCADatabase {
    [CmdletBinding()]
    param()
    Write-AppLog 'Database compaction requested. Ensure the CA service maintenance window is approved before running offline compaction.' 'WARN'
    Write-AppLog 'v5.0 does not stop CertSvc automatically. Use esentutl.exe manually during a controlled CA outage if physical database compaction is required.' 'WARN'
}

# =====================================================================================
# Reporting and statistics
# =====================================================================================
function Reset-Stats {
    foreach ($key in @($script:Stats.Keys)) { $script:Stats[$key] = 0 }
}

function Refresh-StatisticsView {
    if (-not $script:txtStats -or $script:txtStats.IsDisposed) { return }
    $script:txtStats.BeginUpdate()
    try {
        $script:txtStats.Items.Clear()
        function Add-StatsRow {
            param([string]$Metric, [object]$Value, [bool]$IsSection = $false, [string]$Level = 'NORMAL')
            $item = New-Object System.Windows.Forms.ListViewItem($Metric)
            [void]$item.SubItems.Add([string]$Value)
            if ($IsSection) {
                $item.Font = New-Object System.Drawing.Font('Segoe UI',8.25,[System.Drawing.FontStyle]::Bold)
                $item.BackColor = [System.Drawing.Color]::FromArgb(235,240,245)
            } else {
                switch ($Level) {
                    'GOOD' { $item.ForeColor = [System.Drawing.Color]::DarkGreen }
                    'WARN' { $item.ForeColor = [System.Drawing.Color]::DarkOrange }
                    'BAD'  { $item.ForeColor = [System.Drawing.Color]::Firebrick }
                    default { $item.ForeColor = [System.Drawing.Color]::Black }
                }
            }
            [void]$script:txtStats.Items.Add($item)
        }
        Add-StatsRow 'CA Health' '' $true
        Add-StatsRow 'Execution ID' $script:RunStamp
        Add-StatsRow 'CA Config' $script:CAConfig
        Add-StatsRow 'Execution Mode' $(if ($script:chkDryRun -and $script:chkDryRun.Checked) { 'Dry Run' } else { 'Commit-capable' })
        Add-StatsRow 'Lifecycle retention days' $(if ($script:Config) { $script:Config.LifecycleRetentionDays } else { '' })
        Add-StatsRow 'Verify replacement' $(if ($script:Config) { $script:Config.VerifyReplacement } else { '' })
        Add-StatsRow 'Revoked retention days' $(if ($script:Config) { $script:Config.RevokedRetentionDays } else { '' })
        Add-StatsRow 'Failed retention days' $(if ($script:Config) { $script:Config.FailedRetentionDays } else { '' })
        Add-StatsRow 'Delta CRL' $(if ($script:Config -and $script:Config.PublishDeltaCRL) { 'Enabled' } else { 'Disabled' })
        Add-StatsRow 'Discovery' '' $true
        Add-StatsRow 'Issued loaded' $script:Stats.IssuedLoaded
        Add-StatsRow 'Expired found' $script:Stats.ExpiredFound -Level $(if ($script:Stats.ExpiredFound -gt 0) { 'WARN' } else { 'GOOD' })
        Add-StatsRow 'Template matched' $script:Stats.TemplateMatched
        Add-StatsRow 'Device class' '' $true
        Add-StatsRow 'Workstation certs' $script:Stats.WorkstationCerts -Level 'GOOD'
        Add-StatsRow 'Server certs' $script:Stats.ServerCerts -Level $(if ($script:Stats.ServerCerts -gt 0) { 'WARN' } else { 'NORMAL' })
        Add-StatsRow 'Domain controller certs' $script:Stats.DomainControllerCerts -Level $(if ($script:Stats.DomainControllerCerts -gt 0) { 'WARN' } else { 'NORMAL' })
        Add-StatsRow 'Unknown device certs' $script:Stats.UnknownDeviceCerts -Level $(if ($script:Stats.UnknownDeviceCerts -gt 0) { 'WARN' } else { 'NORMAL' })
        Add-StatsRow 'Lifecycle' '' $true
        Add-StatsRow 'Replacement found' $script:Stats.ReplacementFound -Level 'GOOD'
        Add-StatsRow 'Ready for revocation' $script:Stats.ReadyToRevoke -Level $(if ($script:Stats.ReadyToRevoke -gt 0) { 'WARN' } else { 'GOOD' })
        Add-StatsRow 'Skipped no replace' $script:Stats.SkippedNoReplace -Level $(if ($script:Stats.SkippedNoReplace -gt 0) { 'WARN' } else { 'GOOD' })
        Add-StatsRow 'Skipped invalid' $script:Stats.SkippedInvalid -Level $(if ($script:Stats.SkippedInvalid -gt 0) { 'WARN' } else { 'GOOD' })
        Add-StatsRow 'Execution' '' $true
        Add-StatsRow 'Revoked' $script:Stats.Revoked -Level $(if ($script:Stats.Revoked -gt 0) { 'GOOD' } else { 'NORMAL' })
        Add-StatsRow 'Failed' $script:Stats.Failed -Level $(if ($script:Stats.Failed -gt 0) { 'BAD' } else { 'GOOD' })
        Add-StatsRow 'Full CRL' $script:Stats.CRLPublished -Level $(if ($script:Stats.CRLPublished -gt 0) { 'GOOD' } else { 'NORMAL' })
        Add-StatsRow 'Delta CRL' $script:Stats.DeltaCRLPublished -Level $(if ($script:Stats.DeltaCRLPublished -gt 0) { 'GOOD' } else { 'NORMAL' })
        Add-StatsRow 'Maintenance' '' $true
        Add-StatsRow 'Revoked cleanup candidates' $script:Stats.CleanupCandidates
        Add-StatsRow 'Revoked rows cleaned' $script:Stats.CleanupActions
        Add-StatsRow 'Failed cleanup candidates' $script:Stats.FailedCleanupCandidates
        Add-StatsRow 'Failed requests cleaned' $script:Stats.FailedCleanupActions
        Add-StatsRow 'Backup actions' $script:Stats.BackupActions
        Add-StatsRow 'Snapshots' $script:Stats.SnapshotActions
    } finally {
        $script:txtStats.EndUpdate()
    }
}

function Export-Reports {
    param([string]$NamePrefix = 'PKI-Lifecycle')
    $csv = Join-Path $script:ReportRoot "$NamePrefix-$($script:RunStamp).csv"
    $json = Join-Path $script:ReportRoot "$NamePrefix-$($script:RunStamp).json"
    $html = Join-Path $script:ReportRoot "$NamePrefix-$($script:RunStamp).html"
    $script:PreviewItems | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
    $script:PreviewItems | ConvertTo-Json -Depth 5 | Set-Content -Path $json -Encoding UTF8
    $style = '<style>body{font-family:Segoe UI,Arial;font-size:12px}table{border-collapse:collapse;width:100%}th,td{border:1px solid #ccc;padding:4px}th{background:#e9eef5}.READY{background:#fff4ce}.REVOKED{background:#dff6dd}.FAILED{background:#fde7e9}.SKIPPED{background:#f3f2f1}</style>'
    $rows = foreach ($i in $script:PreviewItems) {
        $cls = if ($i.Decision -eq 'Revoked') {'REVOKED'} elseif ($i.Decision -eq 'RevokeFailed') {'FAILED'} elseif ($i.Status -eq 'READY') {'READY'} else {'SKIPPED'}
        '<tr class="{0}"><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td><td>{6}</td><td>{7}</td><td>{8}</td><td>{9}</td><td>{10}</td><td>{11}</td></tr>' -f $cls,$i.Status,$i.Decision,$i.RiskLevel,$i.OldRequestID,$i.OldRequesterName,$i.OldTemplate,$i.OldNotAfter,$i.DaysExpired,$i.ReplacementFound,$i.ReplacementCandidateCount,$i.Result
    }
    @"
<html><head><meta charset="utf-8"><title>PKI Lifecycle Report</title>$style</head><body>
<h1>PKI Certificate Lifecycle Manager v5.5.2 Enterprise Edition</h1>
<p><b>Run:</b> $($script:RunStamp) &nbsp; <b>CA:</b> $($script:CAConfig)</p>
<table><tr><th>Status</th><th>Decision</th><th>Risk</th><th>RequestID</th><th>Requester</th><th>Template</th><th>Old NotAfter</th><th>Days Expired</th><th>Replacement</th><th>Candidates</th><th>Result</th></tr>
$($rows -join [Environment]::NewLine)
</table></body></html>
"@ | Set-Content -Path $html -Encoding UTF8
    [void](Export-ExecutionTimeline)
    Write-AppLog "Reports exported: $script:ReportRoot" 'SUCCESS'
    return @{ Csv=$csv; Json=$json; Html=$html }
}


# =====================================================================================
# AD CS COM repository and lifecycle logic - v4.0.1
# =====================================================================================
function New-PKICertObject {
    param(
        [object]$Row
    )

    $requestID = Get-PropValue $Row @('RequestID','Request ID','ID da Solicitação')
    $serial    = Get-PropValue $Row @('SerialNumber','Serial Number','Número de Série')
    $requester = Get-PropValue $Row @('RequesterName','Requester Name','Nome do Solicitante')
    $cn        = Get-PropValue $Row @('CommonName','Common Name','Nome Comum')
    $template  = Get-PropValue $Row @('CertificateTemplate','Certificate Template','Modelo de Certificado')
    $subject   = Get-PropValue $Row @('Subject','Certificate Subject','Assunto','Requerente')
    $nbRaw     = Get-PropValue $Row @('NotBefore','Certificate Effective Date','Data Efetiva do Certificado')
    $naRaw     = Get-PropValue $Row @('NotAfter','Certificate Expiration Date','Data de Validade do Certificado')
    $disp      = Get-PropValue $Row @('Disposition','Request Disposition','DispositionMessage')
    $submittedRaw = Get-PropValue $Row @('Request.SubmittedWhen','SubmittedWhen','Request Submission Date','Submission Date','Data da Solicitação','Data de Envio da Solicitação')
    $resolvedRaw  = Get-PropValue $Row @('Request.ResolvedWhen','ResolvedWhen','Request Resolution Date','Resolution Date','Data de Resolução')
    $dispMsgRaw   = Get-PropValue $Row @('Request.DispositionMessage','DispositionMessage','Disposition Message','Mensagem de Disposição')
    $revRaw    = Get-PropValue $Row @('Request.RevokedWhen','Request.RevokedEffectiveWhen','Request.RevokedReason','RevokedWhen','RevokedEffectiveWhen','RevocationDate','Revoked Effective Date','Revocation Effective Date','Revocation Date','Revoked Date','Data de Revogação')
    $reasonRaw = Get-PropValue $Row @('Request.RevokedReason','RevokedReason','Revocation Reason','Motivo da Revogação')
    $tpl       = Resolve-PKICertificateTemplate -RawTemplate $template

    [pscustomobject]@{
        RequestID         = $requestID
        SerialNumber      = if ($serial) { ([string]$serial).Trim() } else { $null }
        RequesterName     = if ($requester) { ([string]$requester).Trim() } else { $null }
        CommonName        = if ($cn) { ([string]$cn).Trim() } else { $null }
        Template          = if ($tpl.DisplayName) { ([string]$tpl.DisplayName).Trim() } else { if ($template) { ([string]$template).Trim() } else { $null } }
        TemplateRaw       = if ($template) { ([string]$template).Trim() } else { $null }
        TemplateOID       = $tpl.OID
        TemplateName      = $tpl.Name
        TemplateDisplayName = $tpl.DisplayName
        TemplateResolved  = [bool]$tpl.Resolved
        Subject           = if ($subject) { ([string]$subject).Trim() } else { $null }
        NotBefore         = Convert-CADate $nbRaw
        NotAfter          = Convert-CADate $naRaw
        RawNotBefore      = $nbRaw
        RawNotAfter       = $naRaw
        Disposition       = $disp
        SubmittedWhen     = Convert-CADate $submittedRaw
        ResolvedWhen      = Convert-CADate $resolvedRaw
        DispositionMessage = if ($dispMsgRaw) { ([string]$dispMsgRaw).Trim() } else { $null }
        DeviceClass       = $null
        ComputerName      = $null
        OperatingSystem   = $null
        DeviceClassSource = $null
        RevocationDate    = Convert-CADate $revRaw
        RevocationReason  = if ($reasonRaw) { ([string]$reasonRaw).Trim() } else { $null }
        RetentionCutoff   = $null
    }
}

function Convert-CertViewValue {
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    try {
        if ($Value -is [datetime]) { return [datetime]$Value }
        if ($Value -is [byte[]]) { return ([BitConverter]::ToString($Value) -replace '-','') }
        if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) {
            $d = [double]$Value
            if ($d -gt 20000 -and $d -lt 80000) { return [datetime]::FromOADate($d) }
            return $d
        }
        return [string]$Value
    } catch {
        try { return $Value.ToString() } catch { return $null }
    }
}

function Get-CertViewColumnValue {
    param([object]$Column)

    foreach ($format in @(0,1,4,11,2)) {
        try {
            $v = $Column.GetValue([int]$format)
            $converted = Convert-CertViewValue $v
            if ($null -ne $converted -and ([string]$converted).Length -gt 0) { return $converted }
        } catch { }
    }
    return $null
}

function Get-CertViewColumnIndexSafe {
    param(
        [object]$View,
        [string]$Name
    )
    try { return [int]$View.GetColumnIndex($false, $Name) } catch { return $null }
}

function Get-CertViewAvailableColumns {
    param([object]$View)
    $names = New-Object System.Collections.Generic.List[string]
    try {
        $enum = $View.EnumCertViewColumn($false)
        while ($enum.Next() -ne -1) {
            try {
                $name = [string]$enum.GetName()
                if ($name -and -not $names.Contains($name)) { $names.Add($name) }
            } catch { }
        }
    } catch { }
    return @($names)
}

function Resolve-CertViewColumnName {
    param(
        [string]$Wanted,
        [string[]]$Available
    )

    if (-not $Available -or $Available.Count -eq 0) { return $Wanted }
    foreach ($a in $Available) { if ($a -eq $Wanted) { return $a } }

    $wantedNorm = Normalize-PKIText $Wanted
    foreach ($a in $Available) {
        $n = Normalize-PKIText $a
        if ($n -eq $wantedNorm -or $n.Contains($wantedNorm) -or $wantedNorm.Contains($n)) { return $a }
    }

    switch -Regex ($wantedNorm) {
        'requestid'          { foreach ($a in $Available) { if ((Normalize-PKIText $a) -match 'request.*id|solicitacao') { return $a } } }
        'serialnumber'       { foreach ($a in $Available) { if ((Normalize-PKIText $a) -match 'serial|serie') { return $a } } }
        'requestername'      { foreach ($a in $Available) { if ((Normalize-PKIText $a) -match 'requester|solicitante') { return $a } } }
        'commonname'         { foreach ($a in $Available) { if ((Normalize-PKIText $a) -match 'common.*name|nome.*comum') { return $a } } }
        'certificatetemplate'{ foreach ($a in $Available) { if ((Normalize-PKIText $a) -match 'template|modelo') { return $a } } }
        'subject'            { foreach ($a in $Available) { if ((Normalize-PKIText $a) -match 'subject|assunto|requerente') { return $a } } }
        'notbefore'          { foreach ($a in $Available) { if ((Normalize-PKIText $a) -match 'notbefore|effective|efetiva|valid from') { return $a } } }
        'notafter'           { foreach ($a in $Available) { if ((Normalize-PKIText $a) -match 'notafter|expiration|validade|expires') { return $a } } }
        'disposition'        { foreach ($a in $Available) { if ((Normalize-PKIText $a) -match 'disposition|status') { return $a } } }
    }
    return $Wanted
}


function Invoke-CertViewRepositoryQuery {
    param(
        [string]$CAConfigValue,
        [int]$Disposition = 20,
        [switch]$IncludeRevocationColumns
    )

    Write-AppLog "Using AD CS COM ICertView repository. CA=$CAConfigValue Disposition=$Disposition" 'INFO'
    try { $view = New-Object -ComObject CertificateAuthority.View }
    catch { throw "Failed to create CertificateAuthority.View COM object. Install AD CS administration tools or run on the CA server. $($_.Exception.Message)" }
    try { $view.OpenConnection($CAConfigValue) }
    catch { throw "ICertView.OpenConnection failed for '$CAConfigValue'. Verify CAConfig format 'CAHost\CAName'. $($_.Exception.Message)" }

    $available = @(Get-CertViewAvailableColumns -View $view)
    if ($available.Count -gt 0) {
        Write-AppLog "ICertView available columns discovered: $($available.Count)" 'SUCCESS'
        $available | Set-Content -Path (Join-Path $script:ReportRoot "ICertView-Columns-$($script:RunStamp).txt") -Encoding UTF8
    } else { Write-AppLog 'Could not enumerate ICertView columns; proceeding with canonical AD CS column names.' 'WARN' }

    $wanted = @('RequestID','SerialNumber','RequesterName','CommonName','CertificateTemplate','Subject','NotBefore','NotAfter','Disposition','Request.SubmittedWhen','Request.ResolvedWhen','Request.DispositionMessage','DispositionMessage','Request.StatusCode','Request.DispositionMessage')
    if ($IncludeRevocationColumns) { $wanted += @('Request.RevokedWhen','Request.RevokedEffectiveWhen','Request.RevokedReason','RevokedWhen','RevokedEffectiveWhen','RevocationDate','Revoked Effective Date','Revocation Reason') }
    $resolved = New-Object System.Collections.Generic.List[string]
    foreach ($w in $wanted) {
        $r = Resolve-CertViewColumnName -Wanted $w -Available $available
        $idx = Get-CertViewColumnIndexSafe -View $view -Name $r
        if ($null -ne $idx -and -not $resolved.Contains($r)) { $resolved.Add($r) }
        else { Write-AppLog "ICertView column unavailable: wanted='$w', resolved='$r'" 'WARN' }
    }
    if ($resolved.Count -lt 4) { throw "ICertView did not expose enough required columns. Found: $($resolved -join ', ')" }
    try {
        $view.SetResultColumnCount($resolved.Count)
        foreach ($name in $resolved) { $idx = [int]$view.GetColumnIndex($false, $name); $view.SetResultColumn($idx) }
    } catch { throw "Failed to configure ICertView result columns. Columns=$($resolved -join ', '). $($_.Exception.Message)" }
    try {
        $dispName = Resolve-CertViewColumnName -Wanted 'Disposition' -Available $available
        $dispIdx = Get-CertViewColumnIndexSafe -View $view -Name $dispName
        if ($null -ne $dispIdx) { $view.SetRestriction([int]$dispIdx, 1, 0, $Disposition); Write-AppLog "ICertView restriction applied: Disposition=$Disposition." 'INFO' }
        else { Write-AppLog 'Disposition column unavailable; disposition filtering will be performed after retrieval when possible.' 'WARN' }
    } catch { Write-AppLog "Could not apply ICertView Disposition=$Disposition restriction. Continuing without restriction. $($_.Exception.Message)" 'WARN' }
    $results = New-Object System.Collections.ArrayList
    $count = 0
    try {
        $rows = $view.OpenView()
        while ($rows.Next() -ne -1) {
            $count++
            $obj = [ordered]@{}
            $cols = $rows.EnumCertViewColumn()
            while ($cols.Next() -ne -1) {
                try { $name = [string]$cols.GetName() } catch { $name = "Column$count" }
                $obj[$name] = Get-CertViewColumnValue -Column $cols
            }
            [void]$results.Add([pscustomobject]$obj)
            if (($count % 500) -eq 0) { Write-AppLog "ICertView rows read: $count" 'INFO'; Update-StatusBar "ICertView rows read: $count"; try { [System.Windows.Forms.Application]::DoEvents() } catch {} }
        }
    } catch { throw "ICertView.OpenView/Enumeration failed. $($_.Exception.Message)" }
    Write-AppLog "ICertView rows returned: $($results.Count)" 'SUCCESS'
    return @($results)
}

function Get-IssuedCertificates {
    param([string]$CAConfigValue)

    Write-AppLog 'Repository stage: querying ICertView rows.' 'INFO'
    $rows = @(Invoke-CertViewRepositoryQuery -CAConfigValue $CAConfigValue)
    Write-AppLog "Repository stage: normalizing $($rows.Count) ICertView rows." 'INFO'

    $normalizedList = New-Object System.Collections.ArrayList
    $normalizeErrors = 0
    $rowNumber = 0
    foreach ($row in $rows) {
        $rowNumber++
        try {
            $obj = New-PKICertObject -Row $row
            if ($null -ne $obj) { [void]$normalizedList.Add($obj) }
        } catch {
            $normalizeErrors++
            if ($normalizeErrors -le 20) {
                Write-AppLog "Row normalization failed at row $rowNumber. Error=$($_.Exception.Message)" 'WARN'
            }
        }
    }
    if ($normalizeErrors -gt 0) { Write-AppLog "Rows skipped during normalization: $normalizeErrors" 'WARN' }

    $normalized = @()
    foreach ($n in $normalizedList) { $normalized += $n }
    Write-AppLog "Repository stage: normalized rows=$($normalized.Count)." 'SUCCESS'

    Write-AppLog 'Repository stage: applying issued-state filter.' 'INFO'
    $itemsList = New-Object System.Collections.ArrayList
    foreach ($n in $normalized) {
        try {
            $d = [string]$n.Disposition
            if ([string]::IsNullOrWhiteSpace($d) -or $d -eq '20' -or $d -match '(?i)issued|emitido') {
                [void]$itemsList.Add($n)
            }
        } catch {
            [void]$itemsList.Add($n)
        }
    }
    $items = @()
    foreach ($i in $itemsList) { $items += $i }
    Write-AppLog "Repository stage: issued rows after filter=$($items.Count)." 'SUCCESS'

    $rawPath = Join-Path $script:ReportRoot "ICertView-Normalized-$($script:RunStamp).csv"
    try {
        $items | Export-Csv -Path $rawPath -NoTypeInformation -Encoding UTF8
        Write-AppLog "Normalized ICertView repository exported: $rawPath" 'SUCCESS'
    } catch {
        Write-AppLog "Normalized CSV export failed but execution will continue. Error=$($_.Exception.Message)" 'WARN'
    }

    $missingDates = @($items | Where-Object { -not $_.NotAfter }).Count
    if ($items.Count -gt 0 -and $missingDates -eq $items.Count) {
        Write-AppLog 'No parseable NotAfter values were returned by ICertView. Check ICertView-Columns and Normalized CSV reports.' 'ERROR'
    } elseif ($missingDates -gt 0) {
        Write-AppLog "Rows with missing NotAfter: $missingDates" 'WARN'
    }

    Write-AppLog 'Repository stage: classifying devices using safe heuristic engine.' 'INFO'
    $classErrors = 0
    foreach ($item in $items) {
        try {
            $dc = Resolve-PKIDeviceClass -Cert $item
            $item.DeviceClass = [string]$dc.DeviceClass
            $item.ComputerName = [string]$dc.ComputerName
            $item.OperatingSystem = [string]$dc.OperatingSystem
            $item.DeviceClassSource = [string]$dc.Source
        } catch {
            $classErrors++
            try { $item.DeviceClass = 'Unknown'; $item.DeviceClassSource = 'ClassificationError' } catch {}
            if ($classErrors -le 20) { Write-AppLog "Device classification failed for RequestID=$($item.RequestID): $($_.Exception.Message)" 'WARN' }
        }
    }
    if ($classErrors -gt 0) { Write-AppLog "Device classification errors: $classErrors" 'WARN' }
    Write-AppLog 'Repository stage: completed.' 'SUCCESS'
    return @($items)
}


function Get-PKITemplateIdentityValues {
    param([object]$Cert)
    $values = New-Object System.Collections.Generic.List[string]
    if (-not $Cert) { return @() }
    foreach ($pn in @('Template','TemplateRaw','TemplateOID','TemplateName','TemplateDisplayName')) {
        if ($Cert.PSObject.Properties.Name -contains $pn) {
            $v = [string]$Cert.$pn
            if (-not [string]::IsNullOrWhiteSpace($v) -and -not $values.Contains($v)) { [void]$values.Add($v) }
        }
    }
    return @($values)
}

function Test-SamePKITemplateV2 {
    param([object]$A, [object]$B)
    $aVals = @(Get-PKITemplateIdentityValues -Cert $A)
    $bVals = @(Get-PKITemplateIdentityValues -Cert $B)
    if ($aVals.Count -eq 0 -or $bVals.Count -eq 0) { return $false }

    foreach ($a in $aVals) {
        foreach ($b in $bVals) {
            if ([string]::IsNullOrWhiteSpace($a) -or [string]::IsNullOrWhiteSpace($b)) { continue }
            if ((Normalize-PKIText $a) -eq (Normalize-PKIText $b)) { return $true }
            if (Test-PKITemplateMatch -CertTemplate $a -Filters @($b)) { return $true }
            if (Test-PKITemplateMatch -CertTemplate $b -Filters @($a)) { return $true }
        }
    }
    return $false
}

function Test-SamePKIRequesterOrSubjectV2 {
    param([object]$OldCert, [object]$Candidate)
    if (-not $OldCert -or -not $Candidate) { return $false }

    $oldRequester = Normalize-PKIText $OldCert.RequesterName
    $newRequester = Normalize-PKIText $Candidate.RequesterName
    if ($oldRequester -and $newRequester -and $oldRequester -eq $newRequester) { return $true }

    if (Test-SamePKISubject -A $OldCert -B $Candidate) { return $true }

    $oldComputer = Normalize-PKIText $OldCert.ComputerName
    $newComputer = Normalize-PKIText $Candidate.ComputerName
    if ($oldComputer -and $newComputer -and $oldComputer -eq $newComputer) { return $true }

    return $false
}

function Get-PKIIdentityKeysV5 {
    param([object]$Cert)
    $keys = New-Object System.Collections.Generic.List[string]
    if (-not $Cert) { return @() }
    foreach ($pn in @('RequesterName','CommonName','ComputerName','Subject')) {
        try {
            if ($Cert.PSObject.Properties.Name -contains $pn) {
                $v = Normalize-PKIText $Cert.$pn
                if (-not [string]::IsNullOrWhiteSpace($v) -and -not $keys.Contains($v)) { [void]$keys.Add($v) }
            }
        } catch {}
    }
    return @($keys)
}

function Get-PKITemplateKeysV5 {
    param([object]$Cert)
    $keys = New-Object System.Collections.Generic.List[string]
    foreach ($v in @(Get-PKITemplateIdentityValues -Cert $Cert)) {
        $n = Normalize-PKIText $v
        if (-not [string]::IsNullOrWhiteSpace($n) -and -not $keys.Contains($n)) { [void]$keys.Add($n) }
    }
    return @($keys)
}

function Add-PKIIndexedCandidate {
    param([hashtable]$Index, [string]$Key, [object]$Cert)
    if ([string]::IsNullOrWhiteSpace($Key) -or -not $Cert) { return }
    if (-not $Index.ContainsKey($Key)) { $Index[$Key] = New-Object System.Collections.ArrayList }
    [void]$Index[$Key].Add($Cert)
}

function New-PKIReplacementIndex {
    [CmdletBinding()]
    param([object[]]$AllIssued)
    $byTemplateIdentity = @{}
    $byTemplate = @{}
    $total = @($AllIssued).Count
    $i = 0
    foreach ($cert in @($AllIssued)) {
        $i++
        if (-not $cert) { continue }
        $templateKeys = @(Get-PKITemplateKeysV5 -Cert $cert)
        $identityKeys = @(Get-PKIIdentityKeysV5 -Cert $cert)
        foreach ($tk in $templateKeys) {
            Add-PKIIndexedCandidate -Index $byTemplate -Key $tk -Cert $cert
            foreach ($ik in $identityKeys) {
                Add-PKIIndexedCandidate -Index $byTemplateIdentity -Key "$tk|$ik" -Cert $cert
            }
        }
        if (($i % 250) -eq 0 -or $i -eq $total) {
            Update-StageProgress -Stage 3 -StageCount 8 -Current $i -Total $total -Message "Building replacement index $i of $total"
        }
    }
    return [pscustomobject]@{
        ByTemplateIdentity = $byTemplateIdentity
        ByTemplate = $byTemplate
        IndexedCertificates = $total
        TemplateIdentityKeys = $byTemplateIdentity.Count
        TemplateKeys = $byTemplate.Count
    }
}

function Get-ReplacementDecisionFromIndex {
    [CmdletBinding()]
    param(
        [object]$OldCert,
        [object]$ReplacementIndex,
        [object[]]$AllIssued,
        [datetime]$Now
    )
    if (-not $ReplacementIndex) { return Get-ReplacementDecisionTrace -OldCert $OldCert -AllIssued $AllIssued -Now $Now }
    $candidateMap = @{}
    $templateKeys = @(Get-PKITemplateKeysV5 -Cert $OldCert)
    $identityKeys = @(Get-PKIIdentityKeysV5 -Cert $OldCert)
    foreach ($tk in $templateKeys) {
        foreach ($ik in $identityKeys) {
            $key = "$tk|$ik"
            if ($ReplacementIndex.ByTemplateIdentity.ContainsKey($key)) {
                foreach ($c in @($ReplacementIndex.ByTemplateIdentity[$key])) {
                    if ($c -and $c.RequestID) { $candidateMap[[string]$c.RequestID] = $c }
                }
            }
        }
    }
    $pool = @($candidateMap.Values | Where-Object {
        $_ -and $_.RequestID -ne $OldCert.RequestID -and
        $_.SerialNumber -and $_.SerialNumber -ne $OldCert.SerialNumber
    })
    $newer = @($pool | Where-Object { $_.NotBefore -and $OldCert.NotBefore -and $_.NotBefore -gt $OldCert.NotBefore })
    $currentlyValid = @($newer | Where-Object { $_.NotBefore -le $Now -and $_.NotAfter -and $_.NotAfter -gt $Now })
    $sameTemplate = @($currentlyValid | Where-Object { Test-SamePKITemplateV2 -A $OldCert -B $_ })
    $sameIdentity = @($sameTemplate | Where-Object { Test-SamePKIRequesterOrSubjectV2 -OldCert $OldCert -Candidate $_ })
    $longerValidity = @($sameIdentity | Where-Object { $_.NotAfter -and $OldCert.NotAfter -and $_.NotAfter -gt $OldCert.NotAfter })
    $best = @($longerValidity | Sort-Object NotBefore -Descending | Select-Object -First 1)
    $candidate = if ($best.Count -gt 0) { $best[0] } else { $null }
    $trace = 'Indexed=True; IndexPool={0}; NewerNotBefore={1}; CurrentlyValid={2}; SameTemplate={3}; SameIdentity={4}; LongerValidity={5}; SelectedReplacement={6}; IndexKeys={7}/{8}' -f `
        $pool.Count, $newer.Count, $currentlyValid.Count, $sameTemplate.Count, $sameIdentity.Count, $longerValidity.Count, $(if($candidate){$candidate.RequestID}else{'None'}), $ReplacementIndex.TemplateIdentityKeys, $ReplacementIndex.TemplateKeys
    return [pscustomobject]@{
        PoolCount = $pool.Count
        NewerNotBeforeCount = $newer.Count
        CurrentlyValidCount = $currentlyValid.Count
        SameTemplateCount = $sameTemplate.Count
        SameIdentityCount = $sameIdentity.Count
        LongerValidityCount = $longerValidity.Count
        CandidateCount = $longerValidity.Count
        Candidate = $candidate
        Trace = $trace
    }
}

function Get-ReplacementDecisionTrace {
    param([object]$OldCert, [object[]]$AllIssued, [datetime]$Now)
    $pool = @($AllIssued | Where-Object {
        $_ -and $_.RequestID -ne $OldCert.RequestID -and
        $_.SerialNumber -and $_.SerialNumber -ne $OldCert.SerialNumber
    })
    $newer = @($pool | Where-Object { $_.NotBefore -and $OldCert.NotBefore -and $_.NotBefore -gt $OldCert.NotBefore })
    $currentlyValid = @($newer | Where-Object { $_.NotBefore -le $Now -and $_.NotAfter -and $_.NotAfter -gt $Now })
    $sameTemplate = @($currentlyValid | Where-Object { Test-SamePKITemplateV2 -A $OldCert -B $_ })
    $sameIdentity = @($sameTemplate | Where-Object { Test-SamePKIRequesterOrSubjectV2 -OldCert $OldCert -Candidate $_ })
    $longerValidity = @($sameIdentity | Where-Object { $_.NotAfter -and $OldCert.NotAfter -and $_.NotAfter -gt $OldCert.NotAfter })

    $best = @($longerValidity | Sort-Object NotBefore -Descending | Select-Object -First 1)
    $candidate = if ($best.Count -gt 0) { $best[0] } else { $null }
    $trace = 'Pool={0}; NewerNotBefore={1}; CurrentlyValid={2}; SameTemplate={3}; SameIdentity={4}; LongerValidity={5}; SelectedReplacement={6}' -f `
        $pool.Count, $newer.Count, $currentlyValid.Count, $sameTemplate.Count, $sameIdentity.Count, $longerValidity.Count, $(if($candidate){$candidate.RequestID}else{'None'})

    return [pscustomobject]@{
        PoolCount = $pool.Count
        NewerNotBeforeCount = $newer.Count
        CurrentlyValidCount = $currentlyValid.Count
        SameTemplateCount = $sameTemplate.Count
        SameIdentityCount = $sameIdentity.Count
        LongerValidityCount = $longerValidity.Count
        CandidateCount = $longerValidity.Count
        Candidate = $candidate
        Trace = $trace
    }
}

function Find-ReplacementCertificates {
    param([object]$OldCert, [object[]]$AllIssued, [datetime]$Now)
    $trace = Get-ReplacementDecisionTrace -OldCert $OldCert -AllIssued $AllIssued -Now $Now
    $matches = @($AllIssued | Where-Object {
        $_ -and $_.RequestID -ne $OldCert.RequestID -and
        $_.SerialNumber -and $_.SerialNumber -ne $OldCert.SerialNumber -and
        $_.NotBefore -and $OldCert.NotBefore -and $_.NotBefore -gt $OldCert.NotBefore -and
        $_.NotBefore -le $Now -and
        $_.NotAfter -and $_.NotAfter -gt $Now -and
        $_.NotAfter -and $OldCert.NotAfter -and $_.NotAfter -gt $OldCert.NotAfter -and
        (Test-SamePKITemplateV2 -A $OldCert -B $_) -and
        (Test-SamePKIRequesterOrSubjectV2 -OldCert $OldCert -Candidate $_)
    } | Sort-Object NotBefore -Descending)
    return @($matches)
}

function Find-ReplacementCertificate {
    param([object]$OldCert, [object[]]$AllIssued, [datetime]$Now)
    $matches = @(Find-ReplacementCertificates -OldCert $OldCert -AllIssued $AllIssued -Now $Now | Select-Object -First 1)
    if ($matches.Count -gt 0) { return $matches[0] }
    return $null
}

function Build-Preview {
    param([string]$CAConfigValue, [string[]]$Templates)
    Build-LifecyclePreview -CAConfigValue $CAConfigValue -Templates $Templates
}

function Build-LifecyclePreview {
    param([string]$CAConfigValue, [string[]]$Templates, [int]$LifecycleRetentionDays = -1)
    $script:CurrentOperationStarted = Get-Date
    Set-Busy $true 'Lifecycle Preview starting...'
    try {
        Reset-Stats
        [void]$script:PreviewItems.Clear()
        $now = Get-Date
        if (-not $script:Config) { [void](Load-Configuration) }
        if ($LifecycleRetentionDays -lt 0) { $LifecycleRetentionDays = [int]$script:Config.LifecycleRetentionDays }
        if ($LifecycleRetentionDays -lt 0) { $LifecycleRetentionDays = 0 }
        $lifecycleCutoff = $now.AddDays(-1 * $LifecycleRetentionDays)
        $requireReplacement = Get-PKIBoolConfigValue -Name 'VerifyReplacement' -Default $true
        $script:CAConfig = $CAConfigValue
        Add-ExecutionTimeline -Stage 'Lifecycle Preview' -Detail "Started for CA $CAConfigValue" -Level 'INFO'

        Update-StageProgress -Stage 1 -StageCount 8 -Current 0 -Total 100 -Message 'Loading issued repository'
        $cacheEnabled = Get-PKIBoolConfigValue -Name 'EnableRepositoryCache' -Default $true
        $cacheHit = $false
        if ($cacheEnabled -and $script:RepositoryCache -and $script:RepositoryCache.Issued -and $script:RepositoryCache.IssuedCAConfig -eq $CAConfigValue) {
            $script:IssuedCerts = @($script:RepositoryCache.Issued)
            $cacheHit = $true
            Write-AppLog "Issued repository cache hit. Rows=$($script:IssuedCerts.Count) LoadedAt=$($script:RepositoryCache.IssuedLoadedAt)" 'SUCCESS'
        } else {
            Write-AppLog "Loading issued certificates from CA using ICertView: $CAConfigValue" 'INFO'
            $script:IssuedCerts = @(Get-IssuedCertificates -CAConfigValue $CAConfigValue)
            if ($cacheEnabled) {
                $script:RepositoryCache.Issued = @($script:IssuedCerts)
                $script:RepositoryCache.IssuedCAConfig = $CAConfigValue
                $script:RepositoryCache.IssuedLoadedAt = Get-Date
            }
        }
        $script:Stats.IssuedLoaded = $script:IssuedCerts.Count
        Write-AppLog "Issued certificates loaded: $($script:IssuedCerts.Count). CacheHit=$cacheHit" 'SUCCESS'
        Update-StageProgress -Stage 1 -StageCount 8 -Current 100 -Total 100 -Message "Issued repository loaded: $($script:IssuedCerts.Count) rows"

        Update-StageProgress -Stage 2 -StageCount 8 -Current 0 -Total 100 -Message 'Filtering expired issued certificates'
        $expiredAll = @($script:IssuedCerts | Where-Object { $_.SerialNumber -and $_.NotAfter -and $_.NotAfter -lt $now })
        $script:Stats.ExpiredFound = $expiredAll.Count
        Update-StageProgress -Stage 2 -StageCount 8 -Current 100 -Total 100 -Message "Expired certificates found: $($expiredAll.Count)"

        Update-StageProgress -Stage 3 -StageCount 8 -Current 0 -Total 100 -Message 'Building replacement index'
        $script:ReplacementIndex = New-PKIReplacementIndex -AllIssued $script:IssuedCerts
        Write-AppLog "Replacement index built. Certificates=$($script:ReplacementIndex.IndexedCertificates), TemplateIdentityKeys=$($script:ReplacementIndex.TemplateIdentityKeys), TemplateKeys=$($script:ReplacementIndex.TemplateKeys)" 'SUCCESS'
        Update-StageProgress -Stage 3 -StageCount 8 -Current 100 -Total 100 -Message 'Replacement index completed'

        $allowed = if ($Templates -and $Templates.Count -gt 0) { @($Templates) } else { @($script:Config.AllowedTemplates) }
        $idx = 0
        $totalExpired = [Math]::Max(1, $expiredAll.Count)
        foreach ($old in $expiredAll) {
            $idx++
            if (($idx % 10) -eq 0 -or $idx -eq 1 -or $idx -eq $expiredAll.Count) {
                Update-StageProgress -Stage 4 -StageCount 8 -Current $idx -Total $totalExpired -Message "Evaluating lifecycle row $idx of $($expiredAll.Count)"
            }
            $status = 'MANUAL REVIEW'; $decision = 'ManualReview'; $result = 'Not evaluated'; $replacement = $null; $replacementTrace = $null
            $replacementCandidateCount = 0
            $templateAllowed = $false
            if (-not $old.SerialNumber -or -not $old.NotAfter -or -not $old.NotBefore -or -not $old.RequesterName -or -not $old.Template) {
                $script:Stats.SkippedInvalid++; $result = 'Missing required database fields'
            } elseif (-not (Test-TemplateAllowedV5 -Template $old.Template -Certificate $old)) {
                $result = 'Template is not allowed or is explicitly excluded'
            } elseif ($old.NotAfter -gt $lifecycleCutoff) {
                $templateAllowed = $true; $script:Stats.TemplateMatched++
                $status = 'GRACE PERIOD'; $decision = 'GracePeriod'; $result = "Expired certificate is still inside lifecycle retention/grace window. NotAfter=$($old.NotAfter), Cutoff=$lifecycleCutoff, LifecycleRetentionDays=$LifecycleRetentionDays"
            } else {
                $templateAllowed = $true; $script:Stats.TemplateMatched++
                $replacementTrace = Get-ReplacementDecisionFromIndex -OldCert $old -ReplacementIndex $script:ReplacementIndex -AllIssued $script:IssuedCerts -Now $now
                $replacement = $replacementTrace.Candidate
                $replacementCandidateCount = [int]$replacementTrace.CandidateCount
                # v5.5.2 correction:
                # Lifecycle readiness is driven by the old certificate expiration date (OldNotAfter).
                # If OldNotAfter is older than the lifecycle cutoff, the row is READY for operator-selected revocation.
                # Replacement discovery remains visible as diagnostic evidence, but it no longer blocks READY status.
                if ($replacement) {
                    $script:Stats.ReplacementFound++
                    $script:Stats.ReadyToRevoke++
                    $status = 'READY'; $decision = 'ReadyToRevoke'; $result = "Certificate expired beyond lifecycle retention window ($LifecycleRetentionDays days) based on OldNotAfter and a newer currently valid replacement certificate was found. VerifyReplacement=$requireReplacement. Trace: $($replacementTrace.Trace)"
                } else {
                    $script:Stats.SkippedNoReplace++
                    $script:Stats.ReadyToRevoke++
                    $status = 'READY'; $decision = 'ReadyToRevoke'; $result = "Certificate expired beyond lifecycle retention window ($LifecycleRetentionDays days) based on OldNotAfter. No newer currently valid replacement certificate was found; replacement status is recorded for operator review. Trace: $($replacementTrace.Trace)"
                }
            }
            $riskSeed = [pscustomobject]@{ Status=$status; ReplacementFound=[bool]$replacement; TemplateAllowed=$templateAllowed }
            $risk = if ([bool]$script:Config.EnableRiskAnalysis) { Get-PKIRiskAssessment -Item $riskSeed -Mode 'Lifecycle' } else { [pscustomobject]@{ Level=''; Reason='' } }
            [void]$script:PreviewItems.Add([pscustomobject]@{
                Index=$idx; Selected=($status -eq 'READY'); Status=$status; Decision=$decision; RiskLevel=$risk.Level; RiskReason=$risk.Reason; Result=$result
                OldRequestID=$old.RequestID; OldSerialNumber=$old.SerialNumber; OldRequesterName=$old.RequesterName; OldCommonName=$old.CommonName; OldTemplate=$old.Template; OldTemplateRaw=$old.TemplateRaw; OldTemplateOID=$old.TemplateOID; OldTemplateName=$old.TemplateName; OldTemplateResolved=$old.TemplateResolved
                TemplateAllowed=$templateAllowed; DeviceClass=$old.DeviceClass; ComputerName=$old.ComputerName; OperatingSystem=$old.OperatingSystem; DeviceClassSource=$old.DeviceClassSource
                OldNotBefore=$old.NotBefore; OldNotAfter=$old.NotAfter
                ReplacementFound=[bool]$replacement; ReplacementCandidateCount=$replacementCandidateCount; ReplacementDecisionTrace=if($replacementTrace){$replacementTrace.Trace}else{$null}; ReplacementRequestID=if($replacement){$replacement.RequestID}else{$null}; ReplacementSerialNumber=if($replacement){$replacement.SerialNumber}else{$null}; ReplacementNotBefore=if($replacement){$replacement.NotBefore}else{$null}; ReplacementNotAfter=if($replacement){$replacement.NotAfter}else{$null}
                LifecycleRetentionDays=$LifecycleRetentionDays; LifecycleCutoff=$lifecycleCutoff; DaysExpired=if($old.NotAfter){ [int](($now - $old.NotAfter).TotalDays) } else { $null }
                RevocationDate=$null; RetentionCutoff=$null
            })
        }
        Update-StageProgress -Stage 5 -StageCount 8 -Current 100 -Total 100 -Message 'Risk and decision evaluation completed'

        $considered = @($script:PreviewItems | Where-Object { $_.TemplateAllowed }).Count
        $manualTotal = @($script:PreviewItems | Where-Object { $_.Decision -eq 'ManualReview' }).Count
        $script:Stats.SkippedNoReplace = $manualTotal
        $script:Stats.WorkstationCerts = @($script:PreviewItems | Where-Object { $_.DeviceClass -eq 'Workstation' }).Count
        $script:Stats.ServerCerts = @($script:PreviewItems | Where-Object { $_.DeviceClass -eq 'Server' }).Count
        $script:Stats.DomainControllerCerts = @($script:PreviewItems | Where-Object { $_.DeviceClass -eq 'DomainController' }).Count
        $script:Stats.UnknownDeviceCerts = @($script:PreviewItems | Where-Object { $_.DeviceClass -eq 'Unknown' -or [string]::IsNullOrWhiteSpace($_.DeviceClass) }).Count
        Add-ExecutionTimeline -Stage 'Lifecycle Preview' -Detail "Expired=$($script:Stats.ExpiredFound) Allowed=$considered Ready=$($script:Stats.ReadyToRevoke) ManualReview=$manualTotal" -Level 'SUCCESS'
        Write-AppLog "Lifecycle Preview built. Expired=$($script:Stats.ExpiredFound), Allowed=$considered, Ready=$($script:Stats.ReadyToRevoke), ManualReview=$manualTotal, LifecycleRetentionDays=$LifecycleRetentionDays, LifecycleCutoff=$lifecycleCutoff, VerifyReplacement=$requireReplacement" 'SUCCESS'
        if ($script:Stats.ExpiredFound -gt 0 -and $considered -eq 0) {
            $templateSample = @($expiredAll | Select-Object -ExpandProperty Template -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 20)
            if ($templateSample.Count -gt 0) {
                Write-AppLog ("No expired certificates matched AllowedTemplates. Expired template sample: {0}. Verify AD template resolution or add the resolved template display/name to config.json." -f ($templateSample -join '; ')) 'WARN'
            } else {
                Write-AppLog 'No expired certificates matched AllowedTemplates and the CA query did not return CertificateTemplate values for expired rows. Review ICertView-Normalized CSV columns.' 'WARN'
            }
        }
        Update-StageProgress -Stage 6 -StageCount 8 -Current 100 -Total 100 -Message 'Refreshing preview grid and statistics'
        Refresh-PreviewGrid; Refresh-StatisticsView
        Update-StageProgress -Stage 7 -StageCount 8 -Current 50 -Total 100 -Message 'Generating reports'
        Export-Reports | Out-Null
        Update-StageProgress -Stage 8 -StageCount 8 -Current 100 -Total 100 -Message 'Lifecycle Preview completed'
        Update-StatusBar 'Lifecycle Preview completed.'
    } finally {
        Set-Busy $false 'Ready.'
        $script:CurrentOperationStarted = $null
    }
}

# =====================================================================================
# Reporting and statistics
# =====================================================================================
function Reset-Stats {
    foreach ($key in @($script:Stats.Keys)) { $script:Stats[$key] = 0 }
}

function Refresh-StatisticsView {
    if (-not $script:txtStats -or $script:txtStats.IsDisposed) { return }
    $script:txtStats.BeginUpdate()
    try {
        $script:txtStats.Items.Clear()
        function Add-StatsRow {
            param([string]$Metric, [object]$Value, [bool]$IsSection = $false, [string]$Level = 'NORMAL')
            $item = New-Object System.Windows.Forms.ListViewItem($Metric)
            [void]$item.SubItems.Add([string]$Value)
            if ($IsSection) {
                $item.Font = New-Object System.Drawing.Font('Segoe UI',8.25,[System.Drawing.FontStyle]::Bold)
                $item.BackColor = [System.Drawing.Color]::FromArgb(235,240,245)
            } else {
                switch ($Level) {
                    'GOOD' { $item.ForeColor = [System.Drawing.Color]::DarkGreen }
                    'WARN' { $item.ForeColor = [System.Drawing.Color]::DarkOrange }
                    'BAD'  { $item.ForeColor = [System.Drawing.Color]::Firebrick }
                    default { $item.ForeColor = [System.Drawing.Color]::Black }
                }
            }
            [void]$script:txtStats.Items.Add($item)
        }
        Add-StatsRow 'CA Health' '' $true
        Add-StatsRow 'Execution ID' $script:RunStamp
        Add-StatsRow 'CA Config' $script:CAConfig
        Add-StatsRow 'Execution Mode' $(if ($script:chkDryRun -and $script:chkDryRun.Checked) { 'Dry Run' } else { 'Commit-capable' })
        Add-StatsRow 'Lifecycle retention days' $(if ($script:Config) { $script:Config.LifecycleRetentionDays } else { '' })
        Add-StatsRow 'Revoked retention days' $(if ($script:Config) { $script:Config.RevokedRetentionDays } else { '' })
        Add-StatsRow 'Failed retention days' $(if ($script:Config) { $script:Config.FailedRetentionDays } else { '' })
        Add-StatsRow 'Delta CRL' $(if ($script:Config -and $script:Config.PublishDeltaCRL) { 'Enabled' } else { 'Disabled' })
        Add-StatsRow 'Discovery' '' $true
        Add-StatsRow 'Issued loaded' $script:Stats.IssuedLoaded
        Add-StatsRow 'Expired found' $script:Stats.ExpiredFound -Level $(if ($script:Stats.ExpiredFound -gt 0) { 'WARN' } else { 'GOOD' })
        Add-StatsRow 'Template matched' $script:Stats.TemplateMatched
        Add-StatsRow 'Device class' '' $true
        Add-StatsRow 'Workstation certs' $script:Stats.WorkstationCerts -Level 'GOOD'
        Add-StatsRow 'Server certs' $script:Stats.ServerCerts -Level $(if ($script:Stats.ServerCerts -gt 0) { 'WARN' } else { 'NORMAL' })
        Add-StatsRow 'Domain controller certs' $script:Stats.DomainControllerCerts -Level $(if ($script:Stats.DomainControllerCerts -gt 0) { 'WARN' } else { 'NORMAL' })
        Add-StatsRow 'Unknown device certs' $script:Stats.UnknownDeviceCerts -Level $(if ($script:Stats.UnknownDeviceCerts -gt 0) { 'WARN' } else { 'NORMAL' })
        Add-StatsRow 'Lifecycle' '' $true
        Add-StatsRow 'Replacement found' $script:Stats.ReplacementFound -Level 'GOOD'
        Add-StatsRow 'Ready for revocation' $script:Stats.ReadyToRevoke -Level $(if ($script:Stats.ReadyToRevoke -gt 0) { 'WARN' } else { 'GOOD' })
        Add-StatsRow 'Skipped no replace' $script:Stats.SkippedNoReplace -Level $(if ($script:Stats.SkippedNoReplace -gt 0) { 'WARN' } else { 'GOOD' })
        Add-StatsRow 'Skipped invalid' $script:Stats.SkippedInvalid -Level $(if ($script:Stats.SkippedInvalid -gt 0) { 'WARN' } else { 'GOOD' })
        Add-StatsRow 'Execution' '' $true
        Add-StatsRow 'Revoked' $script:Stats.Revoked -Level $(if ($script:Stats.Revoked -gt 0) { 'GOOD' } else { 'NORMAL' })
        Add-StatsRow 'Failed' $script:Stats.Failed -Level $(if ($script:Stats.Failed -gt 0) { 'BAD' } else { 'GOOD' })
        Add-StatsRow 'Full CRL' $script:Stats.CRLPublished -Level $(if ($script:Stats.CRLPublished -gt 0) { 'GOOD' } else { 'NORMAL' })
        Add-StatsRow 'Delta CRL' $script:Stats.DeltaCRLPublished -Level $(if ($script:Stats.DeltaCRLPublished -gt 0) { 'GOOD' } else { 'NORMAL' })
        Add-StatsRow 'Maintenance' '' $true
        Add-StatsRow 'Revoked cleanup candidates' $script:Stats.CleanupCandidates
        Add-StatsRow 'Revoked rows cleaned' $script:Stats.CleanupActions
        Add-StatsRow 'Failed cleanup candidates' $script:Stats.FailedCleanupCandidates
        Add-StatsRow 'Failed requests cleaned' $script:Stats.FailedCleanupActions
        Add-StatsRow 'Backup actions' $script:Stats.BackupActions
        Add-StatsRow 'Snapshots' $script:Stats.SnapshotActions
    } finally {
        $script:txtStats.EndUpdate()
    }
}

function Export-Reports {
    param([string]$NamePrefix = 'PKI-Lifecycle')
    $csv = Join-Path $script:ReportRoot "$NamePrefix-$($script:RunStamp).csv"
    $json = Join-Path $script:ReportRoot "$NamePrefix-$($script:RunStamp).json"
    $html = Join-Path $script:ReportRoot "$NamePrefix-$($script:RunStamp).html"
    $script:PreviewItems | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
    $script:PreviewItems | ConvertTo-Json -Depth 5 | Set-Content -Path $json -Encoding UTF8
    $style = '<style>body{font-family:Segoe UI,Arial;font-size:12px}table{border-collapse:collapse;width:100%}th,td{border:1px solid #ccc;padding:4px}th{background:#e9eef5}.READY{background:#fff4ce}.REVOKED{background:#dff6dd}.FAILED{background:#fde7e9}.SKIPPED{background:#f3f2f1}</style>'
    $rows = foreach ($i in $script:PreviewItems) {
        $cls = if ($i.Decision -eq 'Revoked') {'REVOKED'} elseif ($i.Decision -eq 'RevokeFailed') {'FAILED'} elseif ($i.Status -eq 'READY') {'READY'} else {'SKIPPED'}
        '<tr class="{0}"><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td><td>{6}</td><td>{7}</td><td>{8}</td><td>{9}</td><td>{10}</td><td>{11}</td></tr>' -f $cls,$i.Status,$i.Decision,$i.RiskLevel,$i.OldRequestID,$i.OldRequesterName,$i.OldTemplate,$i.OldNotAfter,$i.DaysExpired,$i.ReplacementFound,$i.ReplacementCandidateCount,$i.Result
    }
    @"
<html><head><meta charset="utf-8"><title>PKI Lifecycle Report</title>$style</head><body>
<h1>PKI Certificate Lifecycle Manager v5.5.2 Enterprise Edition</h1>
<p><b>Run:</b> $($script:RunStamp) &nbsp; <b>CA:</b> $($script:CAConfig)</p>
<table><tr><th>Status</th><th>Decision</th><th>Risk</th><th>RequestID</th><th>Requester</th><th>Template</th><th>Old NotAfter</th><th>Days Expired</th><th>Replacement</th><th>Candidates</th><th>Result</th></tr>
$($rows -join [Environment]::NewLine)
</table></body></html>
"@ | Set-Content -Path $html -Encoding UTF8
    [void](Export-ExecutionTimeline)
    Write-AppLog "Reports exported: $script:ReportRoot" 'SUCCESS'
    return @{ Csv=$csv; Json=$json; Html=$html }
}

# =====================================================================================
# GUI rendering
# =====================================================================================
function Add-TextRow {
    param([System.Windows.Forms.TableLayoutPanel]$Panel, [int]$Row, [string]$Label, [System.Windows.Forms.Control]$Control)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Label
    $lbl.Dock = [System.Windows.Forms.DockStyle]::Fill
    $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $Control.Dock = [System.Windows.Forms.DockStyle]::Fill
    $Panel.Controls.Add($lbl,0,$Row)
    $Panel.Controls.Add($Control,1,$Row)
}

function Refresh-PreviewGrid {
    if (-not $script:grid -or $script:grid.IsDisposed) { return }
    $script:grid.DataSource = $null
    $table = New-Object System.Data.DataTable
    foreach ($col in @('Select','Index','Status','Decision','RiskLevel','RiskReason','OldRequestID','OldSerialNumber','OldRequesterName','OldCommonName','OldTemplate','DeviceClass','ComputerName','OperatingSystem','OldNotAfter','ReplacementFound','ReplacementCandidateCount','ReplacementRequestID','ReplacementSerialNumber','ReplacementNotAfter','DaysExpired','RevocationDate','RetentionCutoff','Result')) {
        if ($col -eq 'Select') {
            [void]$table.Columns.Add($col, [bool])
        } else {
            [void]$table.Columns.Add($col)
        }
    }
    foreach ($item in $script:PreviewItems) {
        $row = $table.NewRow()
        $row['Select'] = [bool]$item.Selected
        $row['Index'] = [string]$item.Index
        $row['Status'] = [string]$item.Status
        $row['Decision'] = [string]$item.Decision
        if ($table.Columns.Contains('RiskLevel')) { $row['RiskLevel'] = [string]$item.RiskLevel }
        if ($table.Columns.Contains('RiskReason')) { $row['RiskReason'] = [string]$item.RiskReason }
        $row['OldRequestID'] = [string]$item.OldRequestID
        $row['OldSerialNumber'] = [string]$item.OldSerialNumber
        $row['OldRequesterName'] = [string]$item.OldRequesterName
        $row['OldCommonName'] = [string]$item.OldCommonName
        $row['OldTemplate'] = [string]$item.OldTemplate
        $row['DeviceClass'] = [string]$item.DeviceClass
        $row['ComputerName'] = [string]$item.ComputerName
        $row['OperatingSystem'] = [string]$item.OperatingSystem
        $row['OldNotAfter'] = [string]$item.OldNotAfter
        $row['ReplacementFound'] = [string]$item.ReplacementFound
        if ($table.Columns.Contains('ReplacementCandidateCount')) { $row['ReplacementCandidateCount'] = [string]$item.ReplacementCandidateCount }
        $row['ReplacementRequestID'] = [string]$item.ReplacementRequestID
        $row['ReplacementSerialNumber'] = [string]$item.ReplacementSerialNumber
        $row['ReplacementNotAfter'] = [string]$item.ReplacementNotAfter
        if ($table.Columns.Contains('DaysExpired')) { $row['DaysExpired'] = [string]$item.DaysExpired }
        if ($table.Columns.Contains('RevocationDate')) { $row['RevocationDate'] = [string]$item.RevocationDate }
        if ($table.Columns.Contains('RetentionCutoff')) { $row['RetentionCutoff'] = [string]$item.RetentionCutoff }
        $row['Result'] = [string]$item.Result
        try { [void]$table.Rows.Add($row) } catch { Write-AppLog "Grid row add failed for index $($item.Index): $($_.Exception.Message)" 'WARN' }
    }
    $script:grid.DataSource = $table
    if ($script:grid.Columns.Contains('Select')) {
        $script:grid.Columns['Select'].Width = 60
    }
    foreach ($row in $script:grid.Rows) {
        $status = [string]$row.Cells['Status'].Value
        switch ($status) {
            'READY' { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(255,244,206) }
            'CLEANUP_READY' { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(255,244,206) }
            'REVOKED' { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(223,246,221) }
            'CLEANED' { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(223,246,221) }
            'DRYRUN' { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(232,242,254) }
            'FAILED' { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(253,231,233) }
        }
    }
}

function Sync-GridSelection {
    if (-not $script:grid -or $script:grid.IsDisposed) { return }
    foreach ($row in $script:grid.Rows) {
        $idx = 0
        if ([int]::TryParse([string]$row.Cells['Index'].Value, [ref]$idx)) {
            $obj = $script:PreviewItems | Where-Object { $_.Index -eq $idx } | Select-Object -First 1
            if ($obj) {
                $cellValue = $row.Cells['Select'].Value
                if ($cellValue -is [bool]) {
                    $obj.Selected = [bool]$cellValue
                } else {
                    $obj.Selected = ([string]$cellValue -match '^(?i:true|1|yes|y)$')
                }
            }
        }
    }
}

function Show-RowDetails {
    param([int]$Index)
    $obj = $script:PreviewItems | Where-Object { $_.Index -eq $Index } | Select-Object -First 1
    if (-not $obj) { return }
    $text = ($obj | Format-List * | Out-String)
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Certificate Details - Row $Index"
    $dlg.Size = New-Object System.Drawing.Size(820,520)
    $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Dock = [System.Windows.Forms.DockStyle]::Fill
    $tb.Multiline = $true
    $tb.ReadOnly = $true
    $tb.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
    $tb.WordWrap = $false
    $tb.Font = New-Object System.Drawing.Font('Consolas',9)
    $tb.Text = $text
    $dlg.Controls.Add($tb)
    [void]$dlg.ShowDialog($script:form)
}

function Build-GUI {
    $script:form = New-Object System.Windows.Forms.Form
    $script:form.Text = 'PKI Certificate Lifecycle Manager v5.5.2 Enterprise Edition - AD CS Governance Console'
    $script:form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $script:form.Size = New-Object System.Drawing.Size(1380,780)
    $script:form.MinimumSize = New-Object System.Drawing.Size(1200,720)
    $script:form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

    $main = New-Object System.Windows.Forms.TableLayoutPanel
    $main.Dock = [System.Windows.Forms.DockStyle]::Fill
    $main.ColumnCount = 1
    $main.RowCount = 5
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,24)))
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,175)))
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,120)))
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,24)))
    $script:form.Controls.Add($main)

    $menu = New-Object System.Windows.Forms.MenuStrip
    $fileMenu = New-Object System.Windows.Forms.ToolStripMenuItem('File')
    $miExport = New-Object System.Windows.Forms.ToolStripMenuItem('Export Reports')
    $miOpenLogs = New-Object System.Windows.Forms.ToolStripMenuItem('Open Logs Folder')
    $miExit = New-Object System.Windows.Forms.ToolStripMenuItem('Exit')
    [void]$fileMenu.DropDownItems.AddRange(@($miExport,$miOpenLogs,(New-Object System.Windows.Forms.ToolStripSeparator),$miExit))
    $lifecycleMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Lifecycle')
    $miPreview = New-Object System.Windows.Forms.ToolStripMenuItem('Lifecycle Preview')
    $miSelectReady = New-Object System.Windows.Forms.ToolStripMenuItem('Select Ready')
    $miApply = New-Object System.Windows.Forms.ToolStripMenuItem('Revoke Selected')
    $miCrl = New-Object System.Windows.Forms.ToolStripMenuItem('Publish CRL')
    [void]$lifecycleMenu.DropDownItems.AddRange(@($miPreview,$miSelectReady,$miApply,(New-Object System.Windows.Forms.ToolStripSeparator),$miCrl))

    $maintenanceMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Database Maintenance')
    $miCleanup = New-Object System.Windows.Forms.ToolStripMenuItem('Revoked Preview')
    $miFailed = New-Object System.Windows.Forms.ToolStripMenuItem('Failed Preview')
    $miCleanupSelected = New-Object System.Windows.Forms.ToolStripMenuItem('Cleanup Selected')
    [void]$maintenanceMenu.DropDownItems.AddRange(@($miCleanup,$miFailed,(New-Object System.Windows.Forms.ToolStripSeparator),$miCleanupSelected))

    $reportsMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Reports')
    $miReportsExport = New-Object System.Windows.Forms.ToolStripMenuItem('Export Reports')
    $miReportsOpenLogs = New-Object System.Windows.Forms.ToolStripMenuItem('Open Logs')
    [void]$reportsMenu.DropDownItems.AddRange(@($miReportsExport,$miReportsOpenLogs))

    $helpMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Help')
    $miAbout = New-Object System.Windows.Forms.ToolStripMenuItem('About')
    [void]$helpMenu.DropDownItems.Add($miAbout)
    [void]$menu.Items.AddRange(@($fileMenu,$lifecycleMenu,$maintenanceMenu,$reportsMenu,$helpMenu))
    $main.Controls.Add($menu,0,0)

    $config = New-Object System.Windows.Forms.TableLayoutPanel
    $config.Dock = [System.Windows.Forms.DockStyle]::Fill
    $config.ColumnCount = 4
    $config.RowCount = 1
    [void]$config.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,34)))
    [void]$config.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,26)))
    [void]$config.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,20)))
    [void]$config.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,20)))
    $main.Controls.Add($config,0,1)

    $grpScope = New-Object System.Windows.Forms.GroupBox
    $grpScope.Text = 'CA Scope'
    $grpScope.Dock = [System.Windows.Forms.DockStyle]::Fill
    $config.Controls.Add($grpScope,0,0)
    $scope = New-Object System.Windows.Forms.TableLayoutPanel
    $scope.Dock = [System.Windows.Forms.DockStyle]::Fill
    $scope.ColumnCount = 2
    $scope.RowCount = 7
    [void]$scope.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,135)))
    [void]$scope.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))
    for ($r=0; $r -lt 7; $r++) { [void]$scope.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,24))) }
    $grpScope.Controls.Add($scope)
    $script:txtCAConfig = New-Object System.Windows.Forms.TextBox
    $script:txtCAConfig.Text = if ($script:CAConfig) { $script:CAConfig } else { Resolve-CAConfigSafe '' }
    Add-TextRow $scope 0 'CA Config:' $script:txtCAConfig
    $script:txtTemplates = New-Object System.Windows.Forms.TextBox
    $script:txtTemplates.Text = (($script:Config.AllowedTemplates) -join '; ')
    Add-TextRow $scope 1 'Templates:' $script:txtTemplates
    $script:txtLifecycleRetention = New-Object System.Windows.Forms.TextBox
    $script:txtLifecycleRetention.Text = [string]$script:Config.LifecycleRetentionDays
    Add-TextRow $scope 2 'Lifecycle days:' $script:txtLifecycleRetention
    $script:txtRevokedRetention = New-Object System.Windows.Forms.TextBox
    $script:txtRevokedRetention.Text = [string]$script:Config.RevokedRetentionDays
    Add-TextRow $scope 3 'Revoked days:' $script:txtRevokedRetention
    $script:txtFailedRetention = New-Object System.Windows.Forms.TextBox
    $script:txtFailedRetention.Text = [string]$script:Config.FailedRetentionDays
    Add-TextRow $scope 4 'Failed days:' $script:txtFailedRetention
    $script:txtRetention = $script:txtRevokedRetention
    $script:txtBackupRoot = New-Object System.Windows.Forms.TextBox
    $script:txtBackupRoot.Text = [string]$script:Config.BackupRoot
    Add-TextRow $scope 5 'Backup root:' $script:txtBackupRoot
    $lblReservedProgress = New-Object System.Windows.Forms.Label
    $lblReservedProgress.Text = ''
    $scope.Controls.Add($lblReservedProgress,1,6)

    $grpOptions = New-Object System.Windows.Forms.GroupBox
    $grpOptions.Text = 'Execution Options'
    $grpOptions.Dock = [System.Windows.Forms.DockStyle]::Fill
    $config.Controls.Add($grpOptions,1,0)
    $opts = New-Object System.Windows.Forms.TableLayoutPanel
    $opts.Dock = [System.Windows.Forms.DockStyle]::Fill
    $opts.ColumnCount = 2
    $opts.RowCount = 5
    for ($r=0; $r -lt 3; $r++) { [void]$opts.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,28))) }
    [void]$opts.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,22)))
    [void]$opts.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
    [void]$opts.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,50)))
    [void]$opts.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,50)))
    $grpOptions.Controls.Add($opts)
    $script:chkDryRun = New-Object System.Windows.Forms.CheckBox; $script:chkDryRun.Text = 'Execution Mode: DRY RUN'; $script:chkDryRun.Checked = [bool]$script:Config.DefaultDryRun; $script:chkDryRun.Dock = 'Fill'
    $script:chkForce = New-Object System.Windows.Forms.CheckBox; $script:chkForce.Text = 'Auto mode'; $script:chkForce.Checked = [bool]$script:Config.AutoMode; $script:chkForce.Dock = 'Fill'
    $script:chkPublishCRL = New-Object System.Windows.Forms.CheckBox; $script:chkPublishCRL.Text = 'Publish Full CRL'; $script:chkPublishCRL.Checked = [bool]$script:Config.PublishFullCRL; $script:chkPublishCRL.Dock = 'Fill'
    $script:chkPublishDelta = New-Object System.Windows.Forms.CheckBox; $script:chkPublishDelta.Text = 'Publish Delta CRL'; $script:chkPublishDelta.Checked = [bool]$script:Config.PublishDeltaCRL; $script:chkPublishDelta.Dock = 'Fill'
    $script:chkCleanup = New-Object System.Windows.Forms.CheckBox; $script:chkCleanup.Text = 'Cleanup database'; $script:chkCleanup.Dock = 'Fill'
    $script:chkBackup = New-Object System.Windows.Forms.CheckBox; $script:chkBackup.Text = 'Backup CA'; $script:chkBackup.Dock = 'Fill'
    $opts.Controls.Add($script:chkDryRun,0,0); $opts.Controls.Add($script:chkForce,1,0)
    $opts.Controls.Add($script:chkPublishCRL,0,1); $opts.Controls.Add($script:chkPublishDelta,1,1)
    $opts.Controls.Add($script:chkCleanup,0,2); $opts.Controls.Add($script:chkBackup,1,2)
    $script:progress = New-Object System.Windows.Forms.ProgressBar
    $script:progress.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:progress.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
    $opts.Controls.Add($script:progress,0,3)
    $opts.SetColumnSpan($script:progress,2)
    $script:lblProgressDetail = New-Object System.Windows.Forms.Label
    $script:lblProgressDetail.Text = 'Ready.'
    $script:lblProgressDetail.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:lblProgressDetail.AutoEllipsis = $true
    $script:lblProgressDetail.Font = New-Object System.Drawing.Font('Segoe UI',7.5)
    $opts.Controls.Add($script:lblProgressDetail,0,4)
    $opts.SetColumnSpan($script:lblProgressDetail,2)

    $grpExec = New-Object System.Windows.Forms.GroupBox
    $grpExec.Text = 'Workflow - Lifecycle / Database Maintenance / Reports'
    $grpExec.Dock = [System.Windows.Forms.DockStyle]::Fill
    $config.Controls.Add($grpExec,2,0)
    $exec = New-Object System.Windows.Forms.TableLayoutPanel
    $exec.Dock = [System.Windows.Forms.DockStyle]::Fill
    $exec.ColumnCount = 2
    $exec.RowCount = 5
    for ($r=0; $r -lt 5; $r++) { [void]$exec.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,35))) }
    [void]$exec.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,50)))
    [void]$exec.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,50)))
    $grpExec.Controls.Add($exec)
    $btnPreview = New-Object System.Windows.Forms.Button; $btnPreview.Text = 'Lifecycle Preview'; $btnPreview.Dock = 'Fill'
    $btnSelect = New-Object System.Windows.Forms.Button; $btnSelect.Text = 'Select Ready'; $btnSelect.Dock = 'Fill'
    $btnApply = New-Object System.Windows.Forms.Button; $btnApply.Text = 'Revoke Selected'; $btnApply.Dock = 'Fill'
    $btnCrl = New-Object System.Windows.Forms.Button; $btnCrl.Text = 'Publish CRL'; $btnCrl.Dock = 'Fill'
    $btnCleanup = New-Object System.Windows.Forms.Button; $btnCleanup.Text = 'Revoked Preview'; $btnCleanup.Dock = 'Fill'
    $btnFailed = New-Object System.Windows.Forms.Button; $btnFailed.Text = 'Failed Preview'; $btnFailed.Dock = 'Fill'
    $btnBackup = New-Object System.Windows.Forms.Button; $btnBackup.Text = 'Cleanup Selected'; $btnBackup.Dock = 'Fill'
    $btnReports = New-Object System.Windows.Forms.Button; $btnReports.Text = 'Export Reports'; $btnReports.Dock = 'Fill'
    $btnLogs = New-Object System.Windows.Forms.Button; $btnLogs.Text = 'Open Logs'; $btnLogs.Dock = 'Fill'
    $exec.Controls.Add($btnPreview,0,0); $exec.Controls.Add($btnSelect,1,0)
    $exec.Controls.Add($btnApply,0,1); $exec.Controls.Add($btnCrl,1,1)
    $exec.Controls.Add($btnCleanup,0,2); $exec.Controls.Add($btnFailed,1,2)
    $exec.Controls.Add($btnBackup,0,3); $exec.Controls.Add($btnReports,1,3)
    $exec.Controls.Add($btnLogs,0,4)
    $script:ActionControls = @($btnPreview,$btnSelect,$btnApply,$btnCrl,$btnCleanup,$btnFailed,$btnBackup,$btnReports,$btnLogs,$miPreview,$miSelectReady,$miApply,$miCrl,$miCleanup,$miFailed,$miCleanupSelected,$miExport,$miOpenLogs,$miReportsExport,$miReportsOpenLogs)

    $grpStats = New-Object System.Windows.Forms.GroupBox
    $grpStats.Text = 'Statistics'
    $grpStats.Dock = [System.Windows.Forms.DockStyle]::Fill
    $config.Controls.Add($grpStats,3,0)
    $script:txtStats = New-Object System.Windows.Forms.ListView
    $script:txtStats.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:txtStats.View = [System.Windows.Forms.View]::Details
    $script:txtStats.FullRowSelect = $true
    $script:txtStats.GridLines = $true
    $script:txtStats.HeaderStyle = [System.Windows.Forms.ColumnHeaderStyle]::Nonclickable
    $script:txtStats.Font = New-Object System.Drawing.Font('Segoe UI',8.25)
    [void]$script:txtStats.Columns.Add('Metric',155)
    [void]$script:txtStats.Columns.Add('Value',80,[System.Windows.Forms.HorizontalAlignment]::Right)
    $grpStats.Controls.Add($script:txtStats)

    $script:grid = New-Object System.Windows.Forms.DataGridView
    $script:grid.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:grid.AllowUserToAddRows = $false
    $script:grid.AllowUserToDeleteRows = $false
    $script:grid.MultiSelect = $true
    $script:grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $script:grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
    $script:grid.EditMode = [System.Windows.Forms.DataGridViewEditMode]::EditOnEnter
    $main.Controls.Add($script:grid,0,2)

    $grpLog = New-Object System.Windows.Forms.GroupBox
    $grpLog.Text = 'Runtime Log'
    $grpLog.Dock = [System.Windows.Forms.DockStyle]::Fill
    $main.Controls.Add($grpLog,0,3)
    $script:txtLog = New-Object System.Windows.Forms.TextBox
    $script:txtLog.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:txtLog.Multiline = $true
    $script:txtLog.ReadOnly = $true
    $script:txtLog.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
    $script:txtLog.WordWrap = $false
    $script:txtLog.Font = New-Object System.Drawing.Font('Consolas',8)
    $grpLog.Controls.Add($script:txtLog)

    $status = New-Object System.Windows.Forms.StatusStrip
    $status.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:statusMain = New-Object System.Windows.Forms.ToolStripStatusLabel
    $script:statusMain.Spring = $true
    $script:statusMain.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $script:statusMain.Text = 'Ready.'
    $script:statusCA = New-Object System.Windows.Forms.ToolStripStatusLabel
    $script:statusPreview = New-Object System.Windows.Forms.ToolStripStatusLabel
    $script:statusMode = New-Object System.Windows.Forms.ToolStripStatusLabel
    $script:statusMode.Font = New-Object System.Drawing.Font('Segoe UI',8.25,[System.Drawing.FontStyle]::Bold)
    [void]$status.Items.AddRange(@($script:statusMain,$script:statusCA,$script:statusPreview,$script:statusMode))
    $main.Controls.Add($status,0,4)

    $getTemplates = { @(([string]$script:txtTemplates.Text).Split([char[]]@(';',','), [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    $parseDays = { param([object]$TextBox,[string]$Name,[int]$Min) $v=$Min; if (-not [int]::TryParse([string]$TextBox.Text,[ref]$v)) { throw "Invalid $Name." }; if ($v -lt $Min) { throw "$Name must be $Min or greater." }; return $v }
    $getLifecycleRetention = { & $parseDays $script:txtLifecycleRetention 'lifecycle retention days' 0 }
    $getRevokedRetention   = { & $parseDays $script:txtRevokedRetention 'revoked retention days' 30 }
    $getFailedRetention    = { & $parseDays $script:txtFailedRetention 'failed retention days' 30 }
    $getRetention = $getRevokedRetention
    if ($script:chkDryRun) { $script:chkDryRun.Add_CheckedChanged({ Update-ExecutionModeVisualState }) }
    Update-ExecutionModeVisualState
    $previewAction = { Set-Busy $true 'Building lifecycle preview...'; try { Build-LifecyclePreview -CAConfigValue ([string]$script:txtCAConfig.Text).Trim() -Templates (& $getTemplates) -LifecycleRetentionDays (& $getLifecycleRetention) } finally { Set-Busy $false 'Ready.' } }
    $selectAction = {
        if (-not $script:PreviewItems -or $script:PreviewItems.Count -eq 0) {
            Write-AppLog 'Select Ready requested, but no preview rows are loaded.' 'WARN'
            Update-StatusBar 'No preview rows loaded.'
            return
        }
        $selected = 0
        foreach ($i in $script:PreviewItems) {
            if ($i.Status -eq 'READY' -or $i.Status -eq 'CLEANUP_READY' -or $i.Status -eq 'FAILED_CLEANUP_READY') {
                $i.Selected = $true
                $selected++
            } else {
                $i.Selected = $false
            }
        }
        Refresh-PreviewGrid
        Refresh-StatisticsView
        Write-AppLog "Select Ready completed. Selected=$selected rows with status READY/CLEANUP_READY/FAILED_CLEANUP_READY." 'SUCCESS'
        $mode = Get-ExecutionModeLabel
        Update-StatusBar "Selected ready rows: $selected | Mode: $mode"
    }
    $applyAction = { Sync-GridSelection; if (([bool]$script:chkForce.Checked) -and -not [bool]$script:Config.AutoMode) { throw 'Automatic mode is disabled in config.json. Set AutoMode=true before unattended apply.' }; $dry=[bool]$script:chkDryRun.Checked; $targets=Get-SelectedReadyTargetsCount -Mode 'Revoke'; if (-not (Show-PKIExecutionConfirmation -Mode 'Revoke' -DryRun $dry -Targets $targets)) { Write-AppLog 'Revoke Selected canceled by operator.' 'WARN'; return }; Invoke-RevokeSupersededCertificates -DryRun $dry }
    $crlAction = { Publish-CARevocationLists -FullCRL ([bool]$script:chkPublishCRL.Checked) -DeltaCRL ([bool]$script:chkPublishDelta.Checked) }
    $cleanupAction = {
        Set-Busy $true 'Building revoked cleanup preview...'
        try {
            $script:CAConfig = Resolve-CAConfigSafe ([string]$script:txtCAConfig.Text).Trim()
            [void]$script:PreviewItems.Clear()
            $cleanupCandidates = @(Get-RevokedCleanupCandidates -RetentionDays (& $getRevokedRetention))
            foreach ($c in $cleanupCandidates) { [void]$script:PreviewItems.Add($c) }
            Refresh-PreviewGrid
            Refresh-StatisticsView
            Export-Reports -NamePrefix 'PKI-Revoked-Cleanup-Preview' | Out-Null
            if ($cleanupCandidates.Count -eq 0) {
                Write-AppLog 'Revoked Preview completed. No revoked records are older than the configured retention window.' 'WARN'
                Show-AppMessage 'Cleanup Preview completed, but no revoked records matched the retention filter. Check the log for total revoked rows read and the retention cutoff date.' 'Revoked Preview' ([System.Windows.Forms.MessageBoxIcon]::Information)
            } else {
                Write-AppLog "Revoked Preview completed. Candidates=$($cleanupCandidates.Count)" 'SUCCESS'
                Update-StatusBar "Revoked Preview completed. Rows: $($cleanupCandidates.Count)"
            }
        } finally { Set-Busy $false 'Ready.' }
    }
    $failedAction = {
        Set-Busy $true 'Building failed request preview...'
        try {
            $script:CAConfig = Resolve-CAConfigSafe ([string]$script:txtCAConfig.Text).Trim()
            [void]$script:PreviewItems.Clear()
            $days = (& $getFailedRetention)
            $failedCandidates = @(Get-FailedCleanupCandidates -RetentionDays $days)
            foreach ($c in $failedCandidates) { [void]$script:PreviewItems.Add($c) }
            Refresh-PreviewGrid
            Refresh-StatisticsView
            Export-Reports -NamePrefix 'PKI-Failed-Preview' | Out-Null
            if ($failedCandidates.Count -eq 0) {
                Write-AppLog 'Failed Preview completed. No failed requests are older than the configured retention window.' 'WARN'
                Show-AppMessage 'Failed Preview completed, but no failed request rows matched the retention filter.' 'Failed Preview' ([System.Windows.Forms.MessageBoxIcon]::Information)
            } else {
                Write-AppLog "Failed Preview completed. Candidates=$($failedCandidates.Count)" 'SUCCESS'
                Update-StatusBar "Failed Preview completed. Rows: $($failedCandidates.Count)"
            }
        } finally { Set-Busy $false 'Ready.' }
    }
    $backupAction = { Set-Busy $true 'Applying cleanup...'; try { Sync-GridSelection; $dry=[bool]$script:chkDryRun.Checked; $targets=Get-SelectedReadyTargetsCount -Mode 'Cleanup'; if (-not (Show-PKIExecutionConfirmation -Mode 'Cleanup' -DryRun $dry -Targets $targets)) { Write-AppLog 'Cleanup Selected canceled by operator.' 'WARN'; return }; Invoke-RemoveOldRevokedCertificates -RetentionDays (& $getRevokedRetention) -DryRun $dry -CompactDatabase ([bool]$script:Config.CompactDatabase) } finally { Set-Busy $false 'Ready.' } }
    $reportsAction = { Export-Reports | Out-Null; Start-Process explorer.exe $script:ReportRoot }
    $logsAction = { Start-Process explorer.exe $script:ReportRoot }

    $btnPreview.Add_Click({ Invoke-UIAction $previewAction 'Lifecycle Preview Error' }); $miPreview.Add_Click({ Invoke-UIAction $previewAction 'Lifecycle Preview Error' })
    $btnSelect.Add_Click({ Invoke-UIAction $selectAction 'Selection Error' }); $miSelectReady.Add_Click({ Invoke-UIAction $selectAction 'Selection Error' })
    $btnApply.Add_Click({ Invoke-UIAction $applyAction 'Revoke Error' }); $miApply.Add_Click({ Invoke-UIAction $applyAction 'Revoke Error' })
    $btnCrl.Add_Click({ Invoke-UIAction $crlAction 'CRL Error' }); $miCrl.Add_Click({ Invoke-UIAction $crlAction 'CRL Error' })
    $btnCleanup.Add_Click({ Invoke-UIAction $cleanupAction 'Revoked Preview Error' }); $miCleanup.Add_Click({ Invoke-UIAction $cleanupAction 'Revoked Preview Error' })
    $btnFailed.Add_Click({ Invoke-UIAction $failedAction 'Failed Preview Error' }); $miFailed.Add_Click({ Invoke-UIAction $failedAction 'Failed Preview Error' })
    $btnBackup.Add_Click({ Invoke-UIAction $backupAction 'Cleanup Error' }); $miCleanupSelected.Add_Click({ Invoke-UIAction $backupAction 'Cleanup Error' })
    $btnReports.Add_Click({ Invoke-UIAction $reportsAction 'Export Error' }); $miExport.Add_Click({ Invoke-UIAction $reportsAction 'Export Error' }); $miReportsExport.Add_Click({ Invoke-UIAction $reportsAction 'Export Error' })
    $btnLogs.Add_Click({ Invoke-UIAction $logsAction 'Logs Error' }); $miOpenLogs.Add_Click({ Invoke-UIAction $logsAction 'Logs Error' }); $miReportsOpenLogs.Add_Click({ Invoke-UIAction $logsAction 'Logs Error' })
    $miExit.Add_Click({ $script:form.Close() })
    $miAbout.Add_Click({ Show-AppMessage "PKI Certificate Lifecycle Manager v5.5.2 Enterprise Edition`r`nEnterprise AD CS lifecycle governance, lifecycle preview, revoked cleanup, and failed request maintenance console.`r`n`r`nAuthor: Luiz Hamilton Roberto da Silva - @brazilianscriptguy" 'About' })
    $script:grid.Add_CurrentCellDirtyStateChanged({ if ($script:grid.IsCurrentCellDirty) { $script:grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit) } })
    $script:grid.Add_CellValueChanged({ if ($_.ColumnIndex -ge 0 -and $script:grid.Columns.Count -gt $_.ColumnIndex -and $script:grid.Columns[$_.ColumnIndex].Name -eq 'Select') { Sync-GridSelection } })
    $script:grid.Add_CellDoubleClick({ if ($_.RowIndex -ge 0) { $idx=0; if ([int]::TryParse([string]$script:grid.Rows[$_.RowIndex].Cells['Index'].Value,[ref]$idx)) { Show-RowDetails -Index $idx } } })

    Refresh-StatisticsView
    Update-StatusBar 'Ready.'
    $script:form.Add_Shown({ Write-AppLog 'GUI started.' 'SUCCESS'; if (-not (Test-IsAdministrator)) { Write-AppLog 'Process is not elevated. Revocation, cleanup and backup may fail.' 'WARN' } })
    [void][System.Windows.Forms.Application]::Run($script:form)
}

# =====================================================================================
# Console mode
# =====================================================================================
function Invoke-ConsoleWorkflow {
    if (-not $script:Config) { [void](Load-Configuration) }
    $script:CAConfig = Resolve-CAConfigSafe $(if ($CAConfig) { $CAConfig } else { [string]$script:Config.CAConfig })
    if (-not (Test-IsAdministrator)) { Write-AppLog 'Process is not elevated. Some operations may fail.' 'WARN' }
    Build-LifecyclePreview -CAConfigValue $script:CAConfig -Templates $TemplateFilter
    if (-not $ExportOnly) {
        if (-not [bool]$script:Config.AutoMode -and -not $WhatIfPreference) { Write-AppLog 'Console apply blocked because AutoMode=false in config.json. Use -WhatIf for preview/export or set AutoMode=true.' 'WARN' } else { Invoke-RevokeSupersededCertificates -DryRun $WhatIfPreference }
    }
    if ($CleanupDatabase) { [void]$script:PreviewItems.Clear(); foreach ($c in @(Get-RevokedCleanupCandidates -RetentionDays $RetentionDays)) { [void]$script:PreviewItems.Add($c) }; Invoke-RemoveOldRevokedCertificates -RetentionDays $RetentionDays -DryRun $WhatIfPreference -CompactDatabase ([bool]$script:Config.CompactDatabase) }
    if ($BackupCA) { Invoke-CABackup -Root $BackupRoot -IncludePrivateKey ([bool]$script:Config.BackupPrivateKey) }
    Export-Reports | Out-Null
    Write-AppLog 'Console workflow completed.' 'SUCCESS'
}

# =====================================================================================
# Entry point
# =====================================================================================
try {
    Write-AppLog "Starting $script:ScriptName" 'INFO'
    Initialize-Application
    if ($RunConsole) { Invoke-ConsoleWorkflow }
    else { Build-GUI }
} catch {
    Write-AppLog $_.Exception.Message 'ERROR'
    if ($RunConsole) { throw }
    else { Show-AppMessage $_.Exception.Message 'Fatal Error' ([System.Windows.Forms.MessageBoxIcon]::Error) }
}

# End of script
