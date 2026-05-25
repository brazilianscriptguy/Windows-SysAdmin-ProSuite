<#
.SYNOPSIS
    Active Directory Computer Governance Lifecycle Management Platform.

.DESCRIPTION
    Enterprise-grade Windows PowerShell 5.1 WinForms platform for managing the lifecycle of
    Active Directory workstation computer accounts.

    Integrated lifecycle workflows:
      1. Disabled Workstations Governance Audit
         - Forest-wide disabled workstation inventory.
         - Governance scoring.
         - Lifecycle state classification.
         - SPN risk intelligence.
         - Optional DNS and Ping checks.
         - Read-only workflow.
         - CSV export.

      2. Inactive Workstations Discovery and Cleanup
         - Forest-wide or selected-domain inactive workstation discovery.
         - Includes enabled and disabled stale workstation objects for correlation.
         - Shows Operating System and effective Last Machine Logon.
         - Lifecycle state classification.
         - Optional DNS and Ping checks.
         - Controlled "Remove Checked Objects" workflow.
         - CSV export before destructive actions is strongly recommended.

    Lifecycle states:
      - ACTIVE
      - STALE_ENABLED
      - DISABLED_PENDING_REVIEW
      - DISABLED_PENDING_REMOVAL
      - SAFE_REMOVE
      - RISK_MANUAL_REVIEW

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    2026-05-25-v9.3.0-SORTABLE-COLUMNS-CLEANUP-BUTTON-VERIFIED

.NOTES
    Requires:
      - Windows PowerShell 5.1
      - RSAT ActiveDirectory module
      - Domain/forest read permissions
      - Delete permissions only if using Remove Checked Objects

.WARNING
    The "Disabled Workstations Governance Audit" workflow is read-only.
    The "Inactive Workstations Discovery and Cleanup" workflow can remove checked AD computer objects.
    Removal requires explicit confirmation.
#>

# Hide the PowerShell console window
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() {
        var handle = GetConsoleWindow();
        ShowWindow(handle, 0); // 0 = SW_HIDE
    }
    public static void Show() {
        var handle = GetConsoleWindow();
        ShowWindow(handle, 5); // 5 = SW_SHOW
    }
}
"@

[Window]::Hide()

$ProgressPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'

# ------------------------------------------------------------
# Assemblies and visual styles
# ------------------------------------------------------------
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    [System.Windows.Forms.Application]::EnableVisualStyles()
    }
catch {
    Write-Error "Failed to load required .NET assemblies: $($_.Exception.Message)"
    exit 1
}

# ------------------------------------------------------------
# Script name and logging
# ------------------------------------------------------------
$scriptName = try {
    if ($script:PreferredScriptName) { [string]$script:PreferredScriptName }
    elseif ($PSCommandPath) { [IO.Path]::GetFileNameWithoutExtension($PSCommandPath) }
    elseif ($MyInvocation.MyCommand.Path) { [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Path) }
    else { "Invoke-ADComputerGovernanceLifecycle" }
}
catch {
    "Invoke-ADComputerGovernanceLifecycle"
}

$Script:LogDir  = "C:\Logs-TEMP"
$Script:LogPath = Join-Path -Path $Script:LogDir -ChildPath ("{0}.log" -f $scriptName)
$Script:StatePath = Join-Path -Path $Script:LogDir -ChildPath ("{0}-state.json" -f $scriptName)
$Script:ActionJournalPath = Join-Path -Path $Script:LogDir -ChildPath ("{0}-action-journal.jsonl" -f $scriptName)
$Script:TombstonePath = Join-Path -Path $Script:LogDir -ChildPath ("{0}-tombstones.json" -f $scriptName)
$Script:GovernanceSchemaVersion = 3

try {
    if (-not (Test-Path -LiteralPath $Script:LogDir)) {
        New-Item -Path $Script:LogDir -ItemType Directory -Force | Out-Null
    }
}
catch {
    [void][System.Windows.Forms.MessageBox]::Show(
        "Failed to create log directory: $Script:LogDir`r`n$($_.Exception.Message)",
        "AD Computer Governance",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    exit 1
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("INFO","WARNING","ERROR","SUCCESS")][string]$Level = "INFO"
    )

    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message

    try {
        Add-Content -LiteralPath $Script:LogPath -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # Logging must never crash the GUI.
    }
}

function Show-AppMessage {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("Information","Warning","Error")][string]$Type = "Information"
    )

    $icon = switch ($Type) {
        "Information" { [System.Windows.Forms.MessageBoxIcon]::Information }
        "Warning"     { [System.Windows.Forms.MessageBoxIcon]::Warning }
        "Error"       { [System.Windows.Forms.MessageBoxIcon]::Error }
    }

    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,
        "AD Computer Governance",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $icon
    )

    $level = if ($Type -eq "Error") { "ERROR" } elseif ($Type -eq "Warning") { "WARNING" } else { "INFO" }
    Write-Log -Message $Message.Replace("`r", " ").Replace("`n", " ") -Level $level
}

function Invoke-GuiSafe {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [string]$Context = "GUI operation"
    )

    try {
        & $ScriptBlock
    }
    catch {
        $msg = "Unexpected GUI operation failure during: $Context`r`n$($_.Exception.Message)"
        Write-Log -Message $msg.Replace("`r", " ").Replace("`n", " ") -Level "ERROR"
        Show-AppMessage -Message $msg -Type Error
    }
}

Write-Log -Message "==== Session started ====" -Level INFO
Write-Log -Message "Startup model: GUI-first; no ActiveDirectory module import and no forest enumeration during window creation." -Level INFO
Write-Log -Message ("Script: {0}" -f $PSCommandPath) -Level INFO
Write-Log -Message ("LogPath: {0}" -f $Script:LogPath) -Level INFO
Write-Log -Message ("StatePath: {0}" -f $Script:StatePath) -Level INFO
Write-Log -Message ("ActionJournalPath: {0}" -f $Script:ActionJournalPath) -Level INFO

# ------------------------------------------------------------
# PS 5.1 safe object helpers
# ------------------------------------------------------------
function ConvertTo-SafeArray {
    param([AllowNull()]$InputObject)

    if ($null -eq $InputObject) {
        return @()
    }

    if ($InputObject -is [string]) {
        return @($InputObject)
    }

    if ($InputObject -is [System.Array]) {
        return @($InputObject)
    }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        $items = @()

        try {
            foreach ($item in $InputObject) {
                $items += $item
            }

            return @($items)
        }
        catch {
            return @($InputObject)
        }
    }

    return @($InputObject)
}

function Get-SafeCount {
    param([AllowNull()]$InputObject)

    return @(ConvertTo-SafeArray -InputObject $InputObject).Count
}

function Test-HasItems {
    param([AllowNull()]$InputObject)

    return ((Get-SafeCount -InputObject $InputObject) -gt 0)
}

function Get-ListViewCheckedItemsSafe {
    param([Parameter(Mandatory = $true)][System.Windows.Forms.ListView]$ListView)

    $items = New-Object System.Collections.Generic.List[System.Windows.Forms.ListViewItem]
    foreach ($item in $ListView.Items) {
        if ($item.Checked) { [void]$items.Add($item) }
    }

    return @($items.ToArray())
}

function Set-StatusText {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Label]$Label,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $Label.Text = $Text

    try {
        if ($null -ne $statusWorkflow) {
            $statusWorkflow.Text = "Status: $Text"
        }
    }
    catch {}

    [System.Windows.Forms.Application]::DoEvents()
}

function Confirm-Action {
    param([Parameter(Mandatory = $true)][string]$Message)

    $result = [System.Windows.Forms.MessageBox]::Show(
        $Message,
        "Confirm operation",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )

    return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
}

# ------------------------------------------------------------
# Deferred ActiveDirectory module loader
# Same operational model used by Check-Shorter-ADComputerNames.ps1:
# import only inside the AD operation path, not during startup.
# ------------------------------------------------------------
$script:ActiveDirectoryModuleLoaded = $false

function Ensure-ActiveDirectoryModule {
    # ActiveDirectory PowerShell module intentionally not used.
    # This tool uses System.DirectoryServices / LDAP to avoid AD module loading progress windows.
    return $true
}

# ------------------------------------------------------------
# Governance parameters
# ------------------------------------------------------------
$Script:VeryStaleDays = 365
$Script:StaleDays = 180

$Script:ProtectedOuKeywords = @(
    "Domain Controllers",
    "Servers",
    "Infrastructure",
    "PKI",
    "DNS",
    "DHCP",
    "ADFS",
    "Cluster",
    "HCI",
    "VDI",
    "Template",
    "Gold",
    "Critical",
    "Tier 0",
    "Tier0"
)

$Script:LowRiskSPNPatterns = @(
    "^HOST/",
    "^RestrictedKrbHost/"
)

$Script:MediumRiskSPNPatterns = @(
    "^TERMSRV/",
    "^WSMAN/"
)

$Script:HighRiskSPNPatterns = @(
    "^MSSQLSvc/",
    "^LDAP/",
    "^GC/",
    "^DNS/",
    "^HTTP/",
    "^CIFS/"
)


# ------------------------------------------------------------
# Lifecycle Orchestration State Engine
# ------------------------------------------------------------

function New-GovernanceObjectKey {
    param(
        [AllowNull()][string]$SourceDomain,
        [AllowNull()][string]$DistinguishedName
    )

    $source = if ([string]::IsNullOrWhiteSpace($SourceDomain)) { "UNKNOWN_DOMAIN" } else { [string]$SourceDomain }
    $dn = if ([string]::IsNullOrWhiteSpace($DistinguishedName)) { "UNKNOWN_DN" } else { [string]$DistinguishedName }

    return ("{0}|{1}" -f $source.ToUpperInvariant(), $dn.ToUpperInvariant())
}

function Test-ObjectProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    return ($null -ne $Object.PSObject.Properties[$Name])
}

function Get-ObjectPropertyValue {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()]$Default = $null
    )

    if (Test-ObjectProperty -Object $Object -Name $Name) {
        return $Object.$Name
    }

    return $Default
}

function ConvertTo-GovernanceStateRecord {
    param(
        [Parameter(Mandatory = $true)]$Item
    )

    $sourceDomain = [string](Get-ObjectPropertyValue -Object $Item -Name "SourceDomain" -Default "")
    $dn = [string](Get-ObjectPropertyValue -Object $Item -Name "DistinguishedName" -Default "")
    $name = [string](Get-ObjectPropertyValue -Object $Item -Name "Name" -Default "")
    $sam = [string](Get-ObjectPropertyValue -Object $Item -Name "SamAccountName" -Default "")
    $key = [string](Get-ObjectPropertyValue -Object $Item -Name "Key" -Default "")

    if ([string]::IsNullOrWhiteSpace($key)) {
        $key = New-GovernanceObjectKey -SourceDomain $sourceDomain -DistinguishedName $dn
    }

    $now = Get-Date

    $firstSeen = [string](Get-ObjectPropertyValue -Object $Item -Name "FirstSeen" -Default $now.ToString("o"))
    $lastSeen = [string](Get-ObjectPropertyValue -Object $Item -Name "LastSeen" -Default $firstSeen)

    $record = [PSCustomObject]@{
        SchemaVersion            = [int]$Script:GovernanceSchemaVersion
        Key                      = $key
        FirstSeen                = $firstSeen
        LastSeen                 = $lastSeen
        LastWorkflow             = [string](Get-ObjectPropertyValue -Object $Item -Name "LastWorkflow" -Default "")
        SourceDomain             = $sourceDomain
        Name                     = $name
        SamAccountName           = $sam
        DistinguishedName        = $dn
        OperatingSystem          = [string](Get-ObjectPropertyValue -Object $Item -Name "OperatingSystem" -Default "")
        LastLifecycleState       = [string](Get-ObjectPropertyValue -Object $Item -Name "LastLifecycleState" -Default "UNKNOWN")
        LastClassification       = [string](Get-ObjectPropertyValue -Object $Item -Name "LastClassification" -Default "UNKNOWN")
        LastGovernanceScore      = Get-ObjectPropertyValue -Object $Item -Name "LastGovernanceScore" -Default $null
        LastDaysSinceLastLogon   = Get-ObjectPropertyValue -Object $Item -Name "LastDaysSinceLastLogon" -Default $null
        LastDaysSincePasswordSet = Get-ObjectPropertyValue -Object $Item -Name "LastDaysSincePasswordSet" -Default $null
        LastEnabled              = [bool](Get-ObjectPropertyValue -Object $Item -Name "LastEnabled" -Default $false)
        LastDnsStatus            = [string](Get-ObjectPropertyValue -Object $Item -Name "LastDnsStatus" -Default "")
        LastPingStatus           = [string](Get-ObjectPropertyValue -Object $Item -Name "LastPingStatus" -Default "")
        ActionStatus             = [string](Get-ObjectPropertyValue -Object $Item -Name "ActionStatus" -Default "DISCOVERED")
        LastAction               = [string](Get-ObjectPropertyValue -Object $Item -Name "LastAction" -Default "")
        LastActionTime           = [string](Get-ObjectPropertyValue -Object $Item -Name "LastActionTime" -Default "")
        ActionNotes              = [string](Get-ObjectPropertyValue -Object $Item -Name "ActionNotes" -Default "")
        OrchestrationState       = [string](Get-ObjectPropertyValue -Object $Item -Name "OrchestrationState" -Default "DISCOVERED")
        QuarantineTime           = [string](Get-ObjectPropertyValue -Object $Item -Name "QuarantineTime" -Default "")
        PendingRemovalTime       = [string](Get-ObjectPropertyValue -Object $Item -Name "PendingRemovalTime" -Default "")
        RemovedTime              = [string](Get-ObjectPropertyValue -Object $Item -Name "RemovedTime" -Default "")
        ApprovalStatus           = [string](Get-ObjectPropertyValue -Object $Item -Name "ApprovalStatus" -Default "NOT_REQUIRED")
        ApprovedBy               = [string](Get-ObjectPropertyValue -Object $Item -Name "ApprovedBy" -Default "")
        ApprovalTime             = [string](Get-ObjectPropertyValue -Object $Item -Name "ApprovalTime" -Default "")
    }

    return $record
}

function Repair-GovernanceStateItems {
    param([AllowNull()]$Items)

    $repaired = New-Object System.Collections.ArrayList

    foreach ($item in (ConvertTo-SafeArray -InputObject $Items)) {
        try {
            $record = ConvertTo-GovernanceStateRecord -Item $item

            if (-not [string]::IsNullOrWhiteSpace([string]$record.Key)) {
                [void]$repaired.Add($record)
            }
        }
        catch {
            Write-Log -Message ("State record repair failed. {0}" -f $_.Exception.Message) -Level WARNING
        }
    }

    return @($repaired.ToArray())
}

function Import-GovernanceState {
    $state = @{}

    try {
        if (Test-Path -LiteralPath $Script:StatePath) {
            $raw = Get-Content -LiteralPath $Script:StatePath -Raw -Encoding UTF8 -ErrorAction Stop

            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $jsonItems = @($raw | ConvertFrom-Json -ErrorAction Stop)
                $items = Repair-GovernanceStateItems -Items $jsonItems

                foreach ($item in (ConvertTo-SafeArray -InputObject $items)) {
                    $key = [string]$item.Key

                    if (-not [string]::IsNullOrWhiteSpace($key)) {
                        $state[$key] = $item
                    }
                }
            }
        }
    }
    catch {
        Write-Log -Message ("Failed to import governance state. {0}" -f $_.Exception.Message) -Level WARNING
    }

    return $state
}

function Export-GovernanceState {
    param([Parameter(Mandatory = $true)][hashtable]$State)

    try {
        $items = New-Object System.Collections.ArrayList

        foreach ($key in $State.Keys) {
            [void]$items.Add($State[$key])
        }

        $items |
            Sort-Object SourceDomain, Name |
            ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath $Script:StatePath -Encoding UTF8 -Force

        Write-Log -Message ("Governance state exported: {0}" -f $Script:StatePath) -Level SUCCESS
    }
    catch {
        Write-Log -Message ("Failed to export governance state. {0}" -f $_.Exception.Message) -Level ERROR
    }
}

function Write-ActionJournal {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)]$Record,
        [Parameter()][string]$Result = "INFO",
        [Parameter()][string]$Message = ""
    )

    try {
        $entry = [PSCustomObject]@{
            Timestamp         = (Get-Date).ToString("o")
            Action            = $Action
            Result            = $Result
            Message           = $Message
            SourceDomain      = [string]$Record.SourceDomain
            Name              = [string]$Record.Name
            SamAccountName    = [string]$Record.SamAccountName
            DistinguishedName = [string]$Record.DistinguishedName
            LifecycleState    = [string]$Record.LifecycleState
            Classification    = [string]$Record.Classification
            GovernanceScore   = $Record.GovernanceScore
        }

        $jsonLine = $entry | ConvertTo-Json -Depth 6 -Compress
        Add-Content -LiteralPath $Script:ActionJournalPath -Value $jsonLine -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Log -Message ("Failed to write action journal. {0}" -f $_.Exception.Message) -Level WARNING
    }
}

function Update-GovernanceStateFromResults {
    param(
        [Parameter(Mandatory = $true)]$Results,
        [Parameter(Mandatory = $true)][string]$Workflow
    )

    $state = Import-GovernanceState
    $now = Get-Date

    foreach ($record in (ConvertTo-SafeArray -InputObject $Results)) {
        $key = New-GovernanceObjectKey -SourceDomain $record.SourceDomain -DistinguishedName $record.DistinguishedName

        if ($state.ContainsKey($key)) {
            $existing = $state[$key]

            $existing.LastSeen = $now.ToString("o")
            $existing.LastWorkflow = $Workflow
            $existing.LastLifecycleState = [string]$record.LifecycleState
            $existing.LastClassification = [string]$record.Classification
            $existing.LastGovernanceScore = $record.GovernanceScore
            $existing.LastDaysSinceLastLogon = $record.DaysSinceLastLogon
            $existing.LastDaysSincePasswordSet = $record.DaysSincePasswordSet
            $existing.LastEnabled = [bool]$record.Enabled
            $existing.LastDnsStatus = [string]$record.DnsStatus
            $existing.LastPingStatus = [string]$record.PingStatus
        }
        else {
            $state[$key] = [PSCustomObject]@{
                Key                      = $key
                FirstSeen                = $now.ToString("o")
                LastSeen                 = $now.ToString("o")
                LastWorkflow             = $Workflow
                SourceDomain             = [string]$record.SourceDomain
                Name                     = [string]$record.Name
                SamAccountName           = [string]$record.SamAccountName
                DistinguishedName        = [string]$record.DistinguishedName
                OperatingSystem          = [string]$record.OperatingSystem
                LastLifecycleState       = [string]$record.LifecycleState
                LastClassification       = [string]$record.Classification
                LastGovernanceScore      = $record.GovernanceScore
                LastDaysSinceLastLogon   = $record.DaysSinceLastLogon
                LastDaysSincePasswordSet = $record.DaysSincePasswordSet
                LastEnabled              = [bool]$record.Enabled
                LastDnsStatus            = [string]$record.DnsStatus
                LastPingStatus           = [string]$record.PingStatus
                ActionStatus             = "DISCOVERED"
                LastAction               = ""
                LastActionTime           = ""
                ActionNotes              = ""
            }
        }
    }

    Export-GovernanceState -State $state
}

function Set-GovernanceActionState {
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)][string]$ActionStatus,
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter()][string]$Notes = ""
    )

    $state = Import-GovernanceState
    $key = New-GovernanceObjectKey -SourceDomain $Record.SourceDomain -DistinguishedName $Record.DistinguishedName
    $now = Get-Date

    if (-not $state.ContainsKey($key)) {
        $state[$key] = [PSCustomObject]@{
            Key                      = $key
            FirstSeen                = $now.ToString("o")
            LastSeen                 = $now.ToString("o")
            LastWorkflow             = [string]$Record.Workflow
            SourceDomain             = [string]$Record.SourceDomain
            Name                     = [string]$Record.Name
            SamAccountName           = [string]$Record.SamAccountName
            DistinguishedName        = [string]$Record.DistinguishedName
            OperatingSystem          = [string]$Record.OperatingSystem
            LastLifecycleState       = [string]$Record.LifecycleState
            LastClassification       = [string]$Record.Classification
            LastGovernanceScore      = $Record.GovernanceScore
            LastDaysSinceLastLogon   = $Record.DaysSinceLastLogon
            LastDaysSincePasswordSet = $Record.DaysSincePasswordSet
            LastEnabled              = [bool]$Record.Enabled
            LastDnsStatus            = [string]$Record.DnsStatus
            LastPingStatus           = [string]$Record.PingStatus
            ActionStatus             = $ActionStatus
            LastAction               = $Action
            LastActionTime           = $now.ToString("o")
            ActionNotes              = $Notes
        }
    }
    else {
        $existing = $state[$key]
        $existing.ActionStatus = $ActionStatus
        $existing.LastAction = $Action
        $existing.LastActionTime = $now.ToString("o")
        $existing.ActionNotes = $Notes
        $existing.LastSeen = $now.ToString("o")
        $existing.LastLifecycleState = [string]$Record.LifecycleState
        $existing.LastClassification = [string]$Record.Classification
        $existing.LastGovernanceScore = $Record.GovernanceScore
    }

    Export-GovernanceState -State $state
    Write-ActionJournal -Action $Action -Record $Record -Result $ActionStatus -Message $Notes
}

function Set-OrchestrationTransition {
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)]
        [ValidateSet("DISCOVERED","STALE","QUARANTINED","DISABLED","PENDING_REMOVAL","REMOVED","EXCLUDED","HIGH_RISK","FAILED","SKIPPED")]
        [string]$NewState,
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter()][string]$Notes = "",
        [Parameter()][string]$ApprovalStatus = ""
    )

    $state = Import-GovernanceState
    $key = New-GovernanceObjectKey -SourceDomain $Record.SourceDomain -DistinguishedName $Record.DistinguishedName
    $now = Get-Date

    if (-not $state.ContainsKey($key)) {
        $state[$key] = ConvertTo-GovernanceStateRecord -Item ([PSCustomObject]@{
            Key                      = $key
            FirstSeen                = $now.ToString("o")
            LastSeen                 = $now.ToString("o")
            LastWorkflow             = [string]$Record.Workflow
            SourceDomain             = [string]$Record.SourceDomain
            Name                     = [string]$Record.Name
            SamAccountName           = [string]$Record.SamAccountName
            DistinguishedName        = [string]$Record.DistinguishedName
            OperatingSystem          = [string]$Record.OperatingSystem
            LastLifecycleState       = [string]$Record.LifecycleState
            LastClassification       = [string]$Record.Classification
            LastGovernanceScore      = $Record.GovernanceScore
            LastDaysSinceLastLogon   = $Record.DaysSinceLastLogon
            LastDaysSincePasswordSet = $Record.DaysSincePasswordSet
            LastEnabled              = [bool]$Record.Enabled
            LastDnsStatus            = [string]$Record.DnsStatus
            LastPingStatus           = [string]$Record.PingStatus
            ActionStatus             = $NewState
            LastAction               = $Action
            LastActionTime           = $now.ToString("o")
            ActionNotes              = $Notes
            OrchestrationState       = $NewState
        })
    }

    $entry = $state[$key]
    $entry.SchemaVersion = [int]$Script:GovernanceSchemaVersion
    $entry.LastSeen = $now.ToString("o")
    $entry.LastWorkflow = [string]$Record.Workflow
    $entry.LastLifecycleState = [string]$Record.LifecycleState
    $entry.LastClassification = [string]$Record.Classification
    $entry.LastGovernanceScore = $Record.GovernanceScore
    $entry.LastDaysSinceLastLogon = $Record.DaysSinceLastLogon
    $entry.LastDaysSincePasswordSet = $Record.DaysSincePasswordSet
    $entry.LastEnabled = [bool]$Record.Enabled
    $entry.LastDnsStatus = [string]$Record.DnsStatus
    $entry.LastPingStatus = [string]$Record.PingStatus
    $entry.ActionStatus = $NewState
    $entry.LastAction = $Action
    $entry.LastActionTime = $now.ToString("o")
    $entry.ActionNotes = $Notes
    $entry.OrchestrationState = $NewState

    switch ($NewState) {
        "QUARANTINED" {
            $entry.QuarantineTime = $now.ToString("o")
        }
        "PENDING_REMOVAL" {
            $entry.PendingRemovalTime = $now.ToString("o")
            if ([string]::IsNullOrWhiteSpace($ApprovalStatus)) {
                $entry.ApprovalStatus = "PENDING"
            }
        }
        "REMOVED" {
            $entry.RemovedTime = $now.ToString("o")
        }
        "EXCLUDED" {
            $entry.ApprovalStatus = "EXCLUDED"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ApprovalStatus)) {
        $entry.ApprovalStatus = $ApprovalStatus
    }

    Export-GovernanceState -State $state
    Write-ActionJournal -Action $Action -Record $Record -Result $NewState -Message $Notes
}

function Write-TombstoneRecord {
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter()][string]$Reason = ""
    )

    try {
        $existing = @()

        if (Test-Path -LiteralPath $Script:TombstonePath) {
            $raw = Get-Content -LiteralPath $Script:TombstonePath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $existing = @($raw | ConvertFrom-Json -ErrorAction SilentlyContinue)
            }
        }

        $items = New-Object System.Collections.ArrayList

        foreach ($item in (ConvertTo-SafeArray -InputObject $existing)) {
            [void]$items.Add($item)
        }

        [void]$items.Add([PSCustomObject]@{
            SchemaVersion      = [int]$Script:GovernanceSchemaVersion
            TombstoneTime      = (Get-Date).ToString("o")
            SourceDomain       = [string]$Record.SourceDomain
            Name               = [string]$Record.Name
            SamAccountName     = [string]$Record.SamAccountName
            DistinguishedName  = [string]$Record.DistinguishedName
            OperatingSystem    = [string]$Record.OperatingSystem
            LifecycleState     = [string]$Record.LifecycleState
            Classification     = [string]$Record.Classification
            GovernanceScore    = $Record.GovernanceScore
            Reason             = $Reason
        })

        $items |
            ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath $Script:TombstonePath -Encoding UTF8 -Force
    }
    catch {
        Write-Log -Message ("Failed to write tombstone record. {0}" -f $_.Exception.Message) -Level WARNING
    }
}

function Set-CheckedRecordsOrchestrationState {
    param(
        [Parameter(Mandatory = $true)][object[]]$Records,
        [Parameter(Mandatory = $true)]
        [ValidateSet("QUARANTINED","PENDING_REMOVAL","EXCLUDED")]
        [string]$NewState
    )

    $count = 0

    foreach ($record in (ConvertTo-SafeArray -InputObject $Records)) {
        Set-OrchestrationTransition `
            -Record $record `
            -NewState $NewState `
            -Action ("SET_{0}" -f $NewState) `
            -Notes ("Operator set orchestration state to {0}." -f $NewState)

        $count++
    }

    Show-AppMessage -Message "State transition completed.`r`n`r`nObjects updated: $count`r`nNew state: $NewState" -Type Information
}

function Export-GovernanceStateCsv {
    try {
        $state = Import-GovernanceState

        if ($state.Count -eq 0) {
            Show-AppMessage -Message "There is no persisted governance state to export." -Type Information
            return
        }

        $csvPath = Join-Path $Script:LogDir ("{0}-state-{1}.csv" -f $scriptName, (Get-Date -Format "yyyyMMdd-HHmmss"))

        $items = foreach ($key in $state.Keys) {
            $state[$key]
        }

        $items |
            Sort-Object SourceDomain, Name |
            Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

        Show-AppMessage -Message "Governance state CSV exported:`r`n`r`n$csvPath" -Type Information
        Write-Log -Message ("Governance state CSV exported: {0}" -f $csvPath) -Level SUCCESS
    }
    catch {
        Show-AppMessage -Message "Failed to export governance state CSV.`r`n$($_.Exception.Message)" -Type Error
    }
}

# ------------------------------------------------------------
# AD and normalization helpers
# ------------------------------------------------------------
function Get-ForestDomainsSafe {
    try {
        Write-Log -Message "Attempting to retrieve forest domain information." -Level INFO

        $forest = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
        $domains = New-Object System.Collections.Generic.List[string]

        foreach ($domain in $forest.Domains) {
            if (-not [string]::IsNullOrWhiteSpace([string]$domain.Name)) {
                [void]$domains.Add([string]$domain.Name)
            }
        }

        return @($domains.ToArray() | Sort-Object)
    }
    catch {
        Write-Log -Message "Unable to enumerate forest domains: $($_.Exception.Message)" -Level ERROR
        return @()
    }
}

function Resolve-ADServerName {
    param(
        [Parameter(Mandatory = $true)]$DomainController,
        [Parameter(Mandatory = $true)][string]$Domain
    )

    $candidates = New-Object System.Collections.Generic.List[string]

    foreach ($value in (ConvertTo-SafeArray -InputObject $DomainController.HostName)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) { [void]$candidates.Add([string]$value) }
    }

    foreach ($value in (ConvertTo-SafeArray -InputObject $DomainController.Name)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) { [void]$candidates.Add([string]$value) }
    }

    if (-not [string]::IsNullOrWhiteSpace($Domain)) { [void]$candidates.Add($Domain) }

    if ($candidates.Count -eq 0) { return $Domain }

    return [string]$candidates[0]
}

function Convert-ADFileTime {
    param([AllowNull()]$Value)

    try {
        if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
        return [DateTime]::FromFileTime([Int64]$Value)
    }
    catch {
        return $null
    }
}

function Get-DaysSince {
    param([AllowNull()]$DateValue)

    if ($null -eq $DateValue) { return $null }

    try {
        return [int]((Get-Date) - ([DateTime]$DateValue)).TotalDays
    }
    catch {
        return $null
    }
}

function Get-ObjectDomainFromDN {
    param([AllowNull()][string]$DistinguishedName)

    if ([string]::IsNullOrWhiteSpace($DistinguishedName)) { return $null }

    $matches = [regex]::Matches($DistinguishedName, "(?i)DC=([^,]+)")
    if ((Get-SafeCount -InputObject $matches) -eq 0) { return $null }

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($match in $matches) {
        [void]$parts.Add([string]$match.Groups[1].Value)
    }

    return ($parts.ToArray() -join ".")
}

function Get-OUPathFromDN {
    param([AllowNull()][string]$DistinguishedName)

    if ([string]::IsNullOrWhiteSpace($DistinguishedName)) { return $null }

    $parts = @($DistinguishedName -split ",")
    if ((Get-SafeCount -InputObject $parts) -le 1) { return $null }

    return (($parts | Select-Object -Skip 1) -join ",")
}

function Join-SafeString {
    param(
        [AllowNull()]$InputObject,
        [string]$Separator = "; "
    )

    $values = New-Object System.Collections.Generic.List[string]

    foreach ($value in (ConvertTo-SafeArray -InputObject $InputObject)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
            [void]$values.Add([string]$value)
        }
    }

    if ($values.Count -eq 0) { return "" }

    return ($values.ToArray() -join $Separator)
}

function Get-SPNRiskTier {
    param([AllowNull()]$SPNs)

    $spnList = ConvertTo-SafeArray -InputObject $SPNs |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    if ((Get-SafeCount -InputObject $spnList) -eq 0) { return "NONE" }

    foreach ($spn in $spnList) {
        foreach ($pattern in $Script:HighRiskSPNPatterns) {
            if ([string]$spn -match $pattern) { return "HIGH" }
        }
    }

    foreach ($spn in $spnList) {
        foreach ($pattern in $Script:MediumRiskSPNPatterns) {
            if ([string]$spn -match $pattern) { return "MEDIUM" }
        }
    }

    foreach ($spn in $spnList) {
        foreach ($pattern in $Script:LowRiskSPNPatterns) {
            if ([string]$spn -match $pattern) { return "LOW" }
        }
    }

    return "UNKNOWN"
}

function Get-ProtectedOUStatus {
    param([AllowNull()][string]$OUPath)

    if ([string]::IsNullOrWhiteSpace($OUPath)) { return $false }

    foreach ($keyword in $Script:ProtectedOuKeywords) {
        if ($OUPath -match [Regex]::Escape($keyword)) { return $true }
    }

    return $false
}

function Test-DNSResolutionSafe {
    param([AllowNull()][string]$DnsHostName)

    if ([string]::IsNullOrWhiteSpace($DnsHostName)) { return "NO_DNS_NAME" }

    try {
        [void][System.Net.Dns]::GetHostEntry($DnsHostName)
        return "RESOLVES"
    }
    catch {
        return "NO_RESOLUTION"
    }
}

function Test-PingStatusSafe {
    param([AllowNull()][string]$DnsHostName)

    if ([string]::IsNullOrWhiteSpace($DnsHostName)) { return "NO_DNS_NAME" }

    try {
        if (Test-Connection -ComputerName $DnsHostName -Count 1 -Quiet -ErrorAction SilentlyContinue) {
            return "RESPONDS"
        }

        return "NO_RESPONSE"
    }
    catch {
        return "PING_ERROR"
    }
}

# ------------------------------------------------------------
# Lifecycle and governance scoring
# ------------------------------------------------------------
function Get-GovernanceScore {
    param(
        [AllowNull()]$DaysSinceLastLogon,
        [AllowNull()]$DaysSincePasswordSet,
        [string]$DnsStatus,
        [string]$PingStatus,
        [string]$SPNRiskTier,
        [bool]$ProtectedOU,
        [string]$OperatingSystem,
        [bool]$IsDisabled
    )

    $score = 0
    $reasons = New-Object System.Collections.Generic.List[string]

    if ($IsDisabled) {
        $score += 20
        [void]$reasons.Add("DISABLED_OBJECT")
    }
    else {
        [void]$reasons.Add("ENABLED_OBJECT")
    }

    if ($null -eq $DaysSinceLastLogon) {
        $score += 20
        [void]$reasons.Add("NO_EFFECTIVE_LAST_LOGON")
    }
    elseif ($DaysSinceLastLogon -ge 365) {
        $score += 40
        [void]$reasons.Add("VERY_STALE_LOGON")
    }
    elseif ($DaysSinceLastLogon -ge 180) {
        $score += 20
        [void]$reasons.Add("STALE_LOGON")
    }

    if ($null -eq $DaysSincePasswordSet) {
        $score += 10
        [void]$reasons.Add("NO_PASSWORD_LAST_SET")
    }
    elseif ($DaysSincePasswordSet -ge 365) {
        $score += 40
        [void]$reasons.Add("VERY_STALE_PASSWORD")
    }
    elseif ($DaysSincePasswordSet -ge 180) {
        $score += 20
        [void]$reasons.Add("STALE_PASSWORD")
    }

    if ($DnsStatus -eq "NO_RESOLUTION") {
        $score += 15
        [void]$reasons.Add("NO_DNS_RESOLUTION")
    }
    elseif ($DnsStatus -eq "RESOLVES") {
        $score -= 20
        [void]$reasons.Add("DNS_STILL_RESOLVES")
    }

    if ($PingStatus -eq "NO_RESPONSE") {
        $score += 15
        [void]$reasons.Add("NO_PING_RESPONSE")
    }
    elseif ($PingStatus -eq "RESPONDS") {
        $score -= 80
        [void]$reasons.Add("HOST_RESPONDS")
    }

    switch ($SPNRiskTier) {
        "LOW" {
            $score -= 5
            [void]$reasons.Add("LOW_RISK_SPN")
        }
        "MEDIUM" {
            $score -= 20
            [void]$reasons.Add("MEDIUM_RISK_SPN")
        }
        "HIGH" {
            $score -= 60
            [void]$reasons.Add("HIGH_RISK_SPN")
        }
        "UNKNOWN" {
            $score -= 10
            [void]$reasons.Add("UNKNOWN_SPN")
        }
    }

    if ($ProtectedOU) {
        $score -= 50
        [void]$reasons.Add("PROTECTED_OU")
    }

    if ([string]::IsNullOrWhiteSpace($OperatingSystem)) {
        $score -= 25
        [void]$reasons.Add("UNKNOWN_OS")
    }

    return [PSCustomObject]@{
        Score   = [int]$score
        Reasons = ($reasons.ToArray() -join "; ")
    }
}

function Get-GovernanceClassification {
    param([int]$Score)

    if ($Score -ge 80) { return "SAFE_REMOVE" }
    if ($Score -ge 50) { return "REVIEW" }
    return "RISK"
}

function Get-LifecycleState {
    param(
        [bool]$Enabled,
        [bool]$InactiveCandidate,
        [string]$Classification,
        [AllowNull()]$DaysSinceLastLogon,
        [AllowNull()]$DaysSincePasswordSet
    )

    if ($Enabled -eq $true -and $InactiveCandidate -eq $false) {
        return "ACTIVE"
    }

    if ($Enabled -eq $true -and $InactiveCandidate -eq $true) {
        return "STALE_ENABLED"
    }

    if ($Enabled -eq $false -and $Classification -eq "SAFE_REMOVE") {
        return "SAFE_REMOVE"
    }

    if ($Enabled -eq $false -and $Classification -eq "REVIEW") {
        return "DISABLED_PENDING_REVIEW"
    }

    if ($Enabled -eq $false -and $Classification -eq "RISK") {
        return "RISK_MANUAL_REVIEW"
    }

    return "RISK_MANUAL_REVIEW"
}

function Get-LifecycleAction {
    param(
        [string]$LifecycleState,
        [string]$Classification
    )

    switch ($LifecycleState) {
        "ACTIVE" {
            return "No action."
        }
        "STALE_ENABLED" {
            return "Disable or quarantine first."
        }
        "DISABLED_PENDING_REVIEW" {
            return "Validate owner and dependencies."
        }
        "SAFE_REMOVE" {
            return "Eligible for controlled removal."
        }
        "RISK_MANUAL_REVIEW" {
            return "Do not remove automatically."
        }
        default {
            return "Manual validation required."
        }
    }
}

function Get-GovernanceRecommendation {
    param([string]$Classification)

    switch ($Classification) {
        "SAFE_REMOVE" { return "Operationally stale candidate." }
        "REVIEW"      { return "Manual validation required." }
        "RISK"        { return "Risk indicators detected." }
        default       { return "Manual analysis required." }
    }
}


# ------------------------------------------------------------
# AD Governance Data Normalization Engine
# ------------------------------------------------------------

function ConvertTo-FirstScalarString {
    param([AllowNull()]$InputObject)

    $values = @(ConvertTo-SafeArray -InputObject $InputObject)

    if ((Get-SafeCount -InputObject $values) -eq 0) {
        return ""
    }

    foreach ($value in $values) {
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
            return [string]$value
        }
    }

    return ""
}

function ConvertTo-NullableDateTime {
    param([AllowNull()]$InputObject)

    if ($null -eq $InputObject) {
        return $null
    }

    $value = $InputObject

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $items = @(ConvertTo-SafeArray -InputObject $InputObject)

        if ((Get-SafeCount -InputObject $items) -eq 0) {
            return $null
        }

        $value = $items[0]
    }

    try {
        if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
            return $null
        }

        return [DateTime]$value
    }
    catch {
        return $null
    }
}

function ConvertTo-NullableInt64 {
    param([AllowNull()]$InputObject)

    if ($null -eq $InputObject) {
        return $null
    }

    $value = $InputObject

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $items = @(ConvertTo-SafeArray -InputObject $InputObject)

        if ((Get-SafeCount -InputObject $items) -eq 0) {
            return $null
        }

        $value = $items[0]
    }

    try {
        if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
            return $null
        }

        return [Int64]$value
    }
    catch {
        return $null
    }
}

function ConvertTo-NormalizedSpnArray {
    param([AllowNull()]$InputObject)

    $values = New-Object System.Collections.ArrayList

    foreach ($value in (ConvertTo-SafeArray -InputObject $InputObject)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
            [void]$values.Add([string]$value)
        }
    }

    return @($values.ToArray() | Sort-Object -Unique)
}

function ConvertTo-NormalizedComputerObject {
    param(
        [Parameter(Mandatory = $true)]
        $Computer,

        [Parameter(Mandatory = $true)]
        [string]$SourceDomain,

        [Parameter(Mandatory = $true)]
        [string]$SourceDomainController
    )

    $lastLogonDate = ConvertTo-NullableDateTime -InputObject $Computer.LastLogonDate
    $passwordLastSet = ConvertTo-NullableDateTime -InputObject $Computer.PasswordLastSet
    $whenCreated = ConvertTo-NullableDateTime -InputObject $Computer.WhenCreated
    $whenChanged = ConvertTo-NullableDateTime -InputObject $Computer.WhenChanged
    $lastLogonTimestamp = ConvertTo-NullableInt64 -InputObject $Computer.LastLogonTimestamp

    $enabledValue = $false

    try {
        $enabledValue = [bool]$Computer.Enabled
    }
    catch {
        $enabledValue = $false
    }

    return [PSCustomObject]@{
        PSTypeName                = "ADGovernance.NormalizedComputer"
        SourceDomain              = [string]$SourceDomain
        SourceDomainController    = [string]$SourceDomainController
        Name                      = ConvertTo-FirstScalarString -InputObject $Computer.Name
        SamAccountName            = ConvertTo-FirstScalarString -InputObject $Computer.SamAccountName
        DistinguishedName         = ConvertTo-FirstScalarString -InputObject $Computer.DistinguishedName
        Enabled                   = [bool]$enabledValue
        OperatingSystem           = ConvertTo-FirstScalarString -InputObject $Computer.OperatingSystem
        OperatingSystemVersion    = ConvertTo-FirstScalarString -InputObject $Computer.OperatingSystemVersion
        DNSHostName               = ConvertTo-FirstScalarString -InputObject $Computer.DNSHostName
        IPv4Address               = ConvertTo-FirstScalarString -InputObject $Computer.IPv4Address
        LastLogonDate             = $lastLogonDate
        LastLogonTimestamp        = $lastLogonTimestamp
        PasswordLastSet           = $passwordLastSet
        WhenCreated               = $whenCreated
        WhenChanged               = $whenChanged
        Description               = ConvertTo-FirstScalarString -InputObject $Computer.Description
        ServicePrincipalName      = @(ConvertTo-NormalizedSpnArray -InputObject $Computer.ServicePrincipalName)
        NormalizedAt              = Get-Date
    }
}


# ------------------------------------------------------------
# LDAP Engine - no ActiveDirectory PowerShell module dependency
# ------------------------------------------------------------

function ConvertTo-LdapFileTimeDate {
    param([AllowNull()]$Value)

    try {
        if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
            return $null
        }

        $i64 = [Int64]$Value
        if ($i64 -le 0) {
            return $null
        }

        return [DateTime]::FromFileTime($i64)
    }
    catch {
        return $null
    }
}

function Get-LdapPropertyFirst {
    param(
        [Parameter(Mandatory = $true)]$SearchResult,
        [Parameter(Mandatory = $true)][string]$PropertyName
    )

    try {
        $propertyKey = $PropertyName.ToLowerInvariant()

        if ($SearchResult.Properties.Contains($propertyKey) -and $SearchResult.Properties[$propertyKey].Count -gt 0) {
            return $SearchResult.Properties[$propertyKey][0]
        }
    }
    catch {}

    return $null
}

function Get-LdapPropertyArray {
    param(
        [Parameter(Mandatory = $true)]$SearchResult,
        [Parameter(Mandatory = $true)][string]$PropertyName
    )

    $values = @()

    try {
        $propertyKey = $PropertyName.ToLowerInvariant()

        if ($SearchResult.Properties.Contains($propertyKey)) {
            foreach ($value in $SearchResult.Properties[$propertyKey]) {
                if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                    $values += [string]$value
                }
            }
        }
    }
    catch {}

    return @($values)
}

function ConvertTo-NormalizedComputerObjectFromLdap {
    param(
        [Parameter(Mandatory = $true)]$SearchResult,
        [Parameter(Mandatory = $true)][string]$SourceDomain,
        [Parameter(Mandatory = $true)][string]$SourceDomainController
    )

    $uac = 0
    try { $uac = [int](Get-LdapPropertyFirst -SearchResult $SearchResult -PropertyName "userAccountControl") } catch { $uac = 0 }

    $lastLogonTimestampRaw = Get-LdapPropertyFirst -SearchResult $SearchResult -PropertyName "lastLogonTimestamp"
    $pwdLastSetRaw = Get-LdapPropertyFirst -SearchResult $SearchResult -PropertyName "pwdLastSet"
    $whenCreatedRaw = Get-LdapPropertyFirst -SearchResult $SearchResult -PropertyName "whenCreated"
    $whenChangedRaw = Get-LdapPropertyFirst -SearchResult $SearchResult -PropertyName "whenChanged"

    $lastLogonDate = ConvertTo-LdapFileTimeDate -Value $lastLogonTimestampRaw
    $passwordLastSet = ConvertTo-LdapFileTimeDate -Value $pwdLastSetRaw

    $whenCreated = $null
    $whenChanged = $null

    try { if ($whenCreatedRaw) { $whenCreated = [DateTime]$whenCreatedRaw } } catch {}
    try { if ($whenChangedRaw) { $whenChanged = [DateTime]$whenChangedRaw } } catch {}

    return [PSCustomObject]@{
        PSTypeName                = "ADGovernance.NormalizedComputer"
        SourceDomain              = [string]$SourceDomain
        SourceDomainController    = [string]$SourceDomainController
        Name                      = [string](Get-LdapPropertyFirst -SearchResult $SearchResult -PropertyName "name")
        SamAccountName            = [string](Get-LdapPropertyFirst -SearchResult $SearchResult -PropertyName "sAMAccountName")
        DistinguishedName         = [string](Get-LdapPropertyFirst -SearchResult $SearchResult -PropertyName "distinguishedName")
        Enabled                   = [bool](($uac -band 2) -eq 0)
        OperatingSystem           = [string](Get-LdapPropertyFirst -SearchResult $SearchResult -PropertyName "operatingSystem")
        OperatingSystemVersion    = [string](Get-LdapPropertyFirst -SearchResult $SearchResult -PropertyName "operatingSystemVersion")
        DNSHostName               = [string](Get-LdapPropertyFirst -SearchResult $SearchResult -PropertyName "dNSHostName")
        IPv4Address               = ""
        LastLogonDate             = $lastLogonDate
        LastLogonTimestamp        = if ($lastLogonTimestampRaw) { [Int64]$lastLogonTimestampRaw } else { $null }
        PasswordLastSet           = $passwordLastSet
        WhenCreated               = $whenCreated
        WhenChanged               = $whenChanged
        Description               = [string](Get-LdapPropertyFirst -SearchResult $SearchResult -PropertyName "description")
        ServicePrincipalName      = @(Get-LdapPropertyArray -SearchResult $SearchResult -PropertyName "servicePrincipalName")
        NormalizedAt              = Get-Date
    }
}

function Search-LdapComputers {
    param(
        [Parameter(Mandatory = $true)][string]$Domain,
        [Parameter(Mandatory = $true)][ValidateSet("DisabledOnly","AllWorkstations")][string]$Mode
    )

    $results = @()

    try {
        $ldapPath = "LDAP://$Domain"
        $root = New-Object System.DirectoryServices.DirectoryEntry($ldapPath)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.PageSize = 1000
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree

        if ($Mode -eq "DisabledOnly") {
            $searcher.Filter = "(&(objectCategory=computer)(objectClass=computer)(userAccountControl:1.2.840.113556.1.4.803:=2))"
        }
        else {
            $searcher.Filter = "(&(objectCategory=computer)(objectClass=computer))"
        }

        foreach ($property in @(
            "name",
            "sAMAccountName",
            "distinguishedName",
            "userAccountControl",
            "operatingSystem",
            "operatingSystemVersion",
            "dNSHostName",
            "lastLogonTimestamp",
            "pwdLastSet",
            "whenCreated",
            "whenChanged",
            "description",
            "servicePrincipalName"
        )) {
            [void]$searcher.PropertiesToLoad.Add($property)
        }

        $found = $searcher.FindAll()

        foreach ($item in $found) {
            $results += $item
        }

        try { $found.Dispose() } catch {}
        try { $searcher.Dispose() } catch {}
        try { $root.Dispose() } catch {}
    }
    catch {
        Write-Log -Message ("LDAP search failed for domain {0}. {1}" -f $Domain, $_.Exception.Message) -Level ERROR
    }

    return @($results)
}

function Remove-LdapComputerObject {
    param(
        [Parameter(Mandatory = $true)][string]$DistinguishedName
    )

    $entry = $null

    try {
        $entry = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DistinguishedName")
        $parent = $entry.Parent

        $parent.Children.Remove($entry)
        $parent.CommitChanges()

        try { $entry.Dispose() } catch {}
        try { $parent.Dispose() } catch {}

        return $true
    }
    catch {
        try { if ($entry) { $entry.Dispose() } } catch {}
        throw
    }
}

function Test-LdapObjectHasChildren {
    param(
        [Parameter(Mandatory = $true)][string]$DistinguishedName
    )

    try {
        $entry = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DistinguishedName")
        $children = $entry.Children

        foreach ($child in $children) {
            try { $entry.Dispose() } catch {}
            return $true
        }

        try { $entry.Dispose() } catch {}
        return $false
    }
    catch {
        return $true
    }
}

# ------------------------------------------------------------
# Query and record construction
# ------------------------------------------------------------
function New-ComputerGovernanceRecord {
    param(
        [Parameter(Mandatory = $true)]$Computer,
        [Parameter(Mandatory = $true)][string]$SourceDomain,
        [Parameter(Mandatory = $true)][string]$Workflow,
        [bool]$EnableDNS,
        [bool]$EnablePing,
        [int]$InactiveDays = 180
    )

    $os = [string]$Computer.OperatingSystem
    $effectiveLastLogon = $Computer.LastLogonDate

    if ($null -eq $effectiveLastLogon -and $Computer.LastLogonTimestamp) {
        $effectiveLastLogon = Convert-ADFileTime -Value $Computer.LastLogonTimestamp
    }

    $daysSinceLastLogon = Get-DaysSince -DateValue $effectiveLastLogon
    $daysSincePasswordSet = Get-DaysSince -DateValue $Computer.PasswordLastSet
    $daysSinceCreated = Get-DaysSince -DateValue $Computer.WhenCreated
    $daysSinceChanged = Get-DaysSince -DateValue $Computer.WhenChanged

    $spns = ConvertTo-SafeArray -InputObject $Computer.ServicePrincipalName
    $spnRiskTier = Get-SPNRiskTier -SPNs $spns

    $ouPath = Get-OUPathFromDN -DistinguishedName ([string]$Computer.DistinguishedName)
    $protectedOU = Get-ProtectedOUStatus -OUPath $ouPath

    $dnsStatus = "NOT_TESTED"
    $pingStatus = "NOT_TESTED"

    if ($EnableDNS) {
        $dnsStatus = Test-DNSResolutionSafe -DnsHostName ([string]$Computer.DNSHostName)
    }

    if ($EnablePing) {
        $pingStatus = Test-PingStatusSafe -DnsHostName ([string]$Computer.DNSHostName)
    }

    $isDisabled = -not ([bool]$Computer.Enabled)

    $governance = Get-GovernanceScore `
        -DaysSinceLastLogon $daysSinceLastLogon `
        -DaysSincePasswordSet $daysSincePasswordSet `
        -DnsStatus $dnsStatus `
        -PingStatus $pingStatus `
        -SPNRiskTier $spnRiskTier `
        -ProtectedOU $protectedOU `
        -OperatingSystem $os `
        -IsDisabled $isDisabled

    $classification = Get-GovernanceClassification -Score ([int]$governance.Score)
    $recommendation = Get-GovernanceRecommendation -Classification $classification

    $inactiveCandidate = $false
    $cutoff = (Get-Date).AddDays(-1 * $InactiveDays)

    if ($null -eq $effectiveLastLogon -or $effectiveLastLogon -lt $cutoff) {
        $inactiveCandidate = $true
    }

    $lifecycleState = Get-LifecycleState `
        -Enabled ([bool]$Computer.Enabled) `
        -InactiveCandidate ([bool]$inactiveCandidate) `
        -Classification $classification `
        -DaysSinceLastLogon $daysSinceLastLogon `
        -DaysSincePasswordSet $daysSincePasswordSet

    $lifecycleAction = Get-LifecycleAction -LifecycleState $lifecycleState -Classification $classification

    return [PSCustomObject]@{
        Workflow                 = $Workflow
        LifecycleState           = $lifecycleState
        LifecycleAction          = $lifecycleAction
        SourceDomain             = $SourceDomain
        ObjectDomain             = Get-ObjectDomainFromDN -DistinguishedName ([string]$Computer.DistinguishedName)
        Name                     = [string]$Computer.Name
        SamAccountName           = [string]$Computer.SamAccountName
        Enabled                  = [bool]$Computer.Enabled
        InactiveCandidate        = [bool]$inactiveCandidate
        DNSHostName              = [string]$Computer.DNSHostName
        IPv4Address              = [string]$Computer.IPv4Address
        OperatingSystem          = $os
        OperatingSystemVersion   = [string]$Computer.OperatingSystemVersion
        EffectiveLastLogon       = $effectiveLastLogon
        DaysSinceLastLogon       = $daysSinceLastLogon
        PasswordLastSet          = $Computer.PasswordLastSet
        DaysSincePasswordSet     = $daysSincePasswordSet
        WhenCreated              = $Computer.WhenCreated
        DaysSinceCreated         = $daysSinceCreated
        WhenChanged              = $Computer.WhenChanged
        DaysSinceChanged         = $daysSinceChanged
        DnsStatus                = $dnsStatus
        PingStatus               = $pingStatus
        SPNRiskTier              = $spnRiskTier
        SPNCount                 = (Get-SafeCount -InputObject $spns)
        ServicePrincipalNames    = Join-SafeString -InputObject $spns
        ProtectedOU              = [bool]$protectedOU
        GovernanceScore          = [int]$governance.Score
        GovernanceReasons        = [string]$governance.Reasons
        Classification           = $classification
        Recommendation           = $recommendation
        Description              = [string]$Computer.Description
        DistinguishedName        = [string]$Computer.DistinguishedName
        OUPath                   = $ouPath
        SourceDomainController   = if ($Computer.SourceDomainController) { [string]$Computer.SourceDomainController } else { $SourceDomain }
        ActionStatus             = "DISCOVERED"
    }
}

function Get-AdComputerInventoryForDomain {
    param(
        [Parameter(Mandatory = $true)][string]$Domain,
        [Parameter(Mandatory = $true)][ValidateSet("DisabledOnly","AllWorkstations")][string]$Mode,
        [bool]$IncludeUnknownOS,
        [bool]$IncludeServerLikeObjects
    )

    $records = @()

    try {
        $server = $Domain

        Write-Log -Message ("LDAP acquisition started. Domain={0} | Server={1} | Mode={2}" -f $Domain, $server, $Mode) -Level INFO

        $computerObjects = @(Search-LdapComputers -Domain $Domain -Mode $Mode)

        $rawCount = Get-SafeCount -InputObject $computerObjects
        $normalizedCount = 0
        $skippedCount = 0
        $normalizationFailures = 0

        foreach ($rawComputer in (ConvertTo-SafeArray -InputObject $computerObjects)) {
            try {
                $computer = ConvertTo-NormalizedComputerObjectFromLdap `
                    -SearchResult $rawComputer `
                    -SourceDomain $Domain `
                    -SourceDomainController $server

                $os = [string]$computer.OperatingSystem

                if ($os -match "Server" -and -not $IncludeServerLikeObjects) {
                    $skippedCount++
                    continue
                }

                if ([string]::IsNullOrWhiteSpace($os) -and -not $IncludeUnknownOS) {
                    $skippedCount++
                    continue
                }

                $records += $computer
                $normalizedCount++
            }
            catch {
                $normalizationFailures++
                Write-Log -Message ("Computer normalization failed in domain {0}. Error={1}" -f $Domain, $_.Exception.Message) -Level ERROR
                continue
            }
        }

        Write-Log -Message ("LDAP acquisition completed. Domain={0} | Mode={1} | Raw={2} | Normalized={3} | Skipped={4} | Failures={5}" -f $Domain, $Mode, $rawCount, $normalizedCount, $skippedCount, $normalizationFailures) -Level SUCCESS
    }
    catch {
        Write-Log -Message ("Domain LDAP inventory failed for {0}. {1}" -f $Domain, $_.Exception.Message) -Level ERROR
    }

    return @($records)
}

function Invoke-InactiveWorkstationsLifecycleDiscovery {
    param(
        [string]$DomainScope,
        [int]$InactiveDays,
        [bool]$EnableDNS,
        [bool]$EnablePing
    )

    $results = New-Object System.Collections.Generic.List[object]

    if ($DomainScope -eq "ALL_FOREST_DOMAINS") {
        $domains = Get-ForestDomainsSafe
    }
    else {
        $domains = @($DomainScope)
    }

    foreach ($domain in $domains) {
        Write-Log -Message "Inactive workstation lifecycle discovery: processing domain $domain with threshold $InactiveDays days." -Level INFO

        $computers = Get-AdComputerInventoryForDomain `
            -Domain $domain `
            -Mode AllWorkstations `
            -IncludeUnknownOS $false `
            -IncludeServerLikeObjects $false

        foreach ($computer in (ConvertTo-SafeArray -InputObject $computers)) {
            $record = New-ComputerGovernanceRecord `
                -Computer $computer `
                -SourceDomain $domain `
                -Workflow "INACTIVE_WORKSTATIONS_LIFECYCLE" `
                -EnableDNS $EnableDNS `
                -EnablePing $EnablePing `
                -InactiveDays $InactiveDays

            if ($record.InactiveCandidate -eq $true) {
                [void]$results.Add($record)
            }
        }
    }

    return @($results.ToArray() | Sort-Object -Property @{Expression="LifecycleState";Descending=$false}, @{Expression="DaysSinceLastLogon";Descending=$true}, SourceDomain, Name)
}

function Remove-SelectedWorkstationAccounts {
    param(
        [Parameter(Mandatory = $true)][object[]]$SelectedRecords
    )

    $removedComputers = New-Object System.Collections.Generic.List[object]
    $failedCount = 0
    $skippedCount = 0

    foreach ($record in (ConvertTo-SafeArray -InputObject $SelectedRecords)) {
        try {
            if ($record.Workflow -ne "INACTIVE_WORKSTATIONS_LIFECYCLE") {
                $skippedCount++
                Set-GovernanceActionState -Record $record -ActionStatus "SKIPPED" -Action "REMOVE_AD_COMPUTER" -Notes "Skipped non-cleanup workflow object."
                Write-Log -Message "Skipped non-cleanup workflow object: $($record.Name)" -Level WARNING
                continue
            }

            if ([string]::IsNullOrWhiteSpace([string]$record.DistinguishedName)) {
                $skippedCount++
                Set-GovernanceActionState -Record $record -ActionStatus "SKIPPED" -Action "REMOVE_AD_COMPUTER" -Notes "Skipped object with empty DistinguishedName."
                Write-Log -Message "Skipped object with empty DistinguishedName: $($record.Name)" -Level WARNING
                continue
            }

            $currentState = [string]$record.LifecycleState
            $currentClassification = [string]$record.Classification

            if ($currentClassification -ne "SAFE_REMOVE") {
                $skippedCount++
                Set-OrchestrationTransition -Record $record -NewState "SKIPPED" -Action "REMOVE_AD_COMPUTER" -Notes "Skipped because classification is not SAFE_REMOVE."
                Write-Log -Message "Skipped removal of $($record.Name). Classification is not SAFE_REMOVE." -Level WARNING
                continue
            }

            if (Test-LdapObjectHasChildren -DistinguishedName $record.DistinguishedName) {
                $skippedCount++
                Set-GovernanceActionState -Record $record -ActionStatus "SKIPPED" -Action "REMOVE_AD_COMPUTER" -Notes "Skipped because object contains child objects."
                Write-Log -Message "Skipped removal of $($record.Name). Object contains child objects." -Level WARNING
                continue
            }

            # Destructive cleanup operation: delete AD workstation object through LDAP.`r`n            Remove-LdapComputerObject -DistinguishedName $record.DistinguishedName | Out-Null

            [void]$removedComputers.Add($record)
            Set-OrchestrationTransition -Record $record -NewState "REMOVED" -Action "REMOVE_AD_COMPUTER" -Notes "AD computer object removed by operator through stateful lifecycle platform." -ApprovalStatus "APPROVED"
            Write-TombstoneRecord -Record $record -Reason "Removed by operator through stateful lifecycle platform."
            Write-Log -Message "Removed computer account: $($record.Name) | $($record.DistinguishedName)" -Level SUCCESS
        }
        catch {
            $failedCount++
            Set-GovernanceActionState -Record $record -ActionStatus "FAILED" -Action "REMOVE_AD_COMPUTER" -Notes $_.Exception.Message
            Write-Log -Message "Failed to remove $($record.Name). $($_.Exception.Message)" -Level ERROR
        }
    }

    if ((Get-SafeCount -InputObject $removedComputers) -gt 0) {
        $myDocuments = [Environment]::GetFolderPath("MyDocuments")
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $fileName = "${scriptName}_RemovedComputers_${timestamp}.csv"
        $filePath = Join-Path -Path $myDocuments -ChildPath $fileName

        $removedComputers |
            Select-Object Name,SourceDomain,SourceDomainController,DistinguishedName,OperatingSystem,EffectiveLastLogon,DaysSinceLastLogon,PasswordLastSet,LifecycleState,Classification,GovernanceScore |
            Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8 -Force

        Show-AppMessage -Message "Removal completed.`r`n`r`nRemoved: $((Get-SafeCount -InputObject $removedComputers))`r`nSkipped: $skippedCount`r`nFailed: $failedCount`r`n`r`nCSV exported:`r`n$filePath" -Type Information
    }
    else {
        Show-AppMessage -Message "No workstation account was removed.`r`n`r`nSkipped: $skippedCount`r`nFailed: $failedCount" -Type Warning
    }
}

# ------------------------------------------------------------
# Sortable ListView
# ------------------------------------------------------------
$script:SortColumn = -1
$script:SortAscending = $true

function Convert-ListViewSortValue {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $trimmed = $Value.Trim()

    $intValue = 0
    if ([int]::TryParse($trimmed, [ref]$intValue)) {
        return $intValue
    }

    $dateValue = [DateTime]::MinValue
    if ([DateTime]::TryParse($trimmed, [ref]$dateValue)) {
        return $dateValue
    }

    $boolValue = $false
    if ([bool]::TryParse($trimmed, [ref]$boolValue)) {
        return $boolValue
    }

    return $trimmed.ToUpperInvariant()
}

function Set-ListViewColumnSortIndicators {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.ListView]$ListView,
        [Parameter(Mandatory = $true)][int]$ColumnIndex,
        [Parameter(Mandatory = $true)][bool]$Ascending
    )

    for ($i = 0; $i -lt $ListView.Columns.Count; $i++) {
        $text = $ListView.Columns[$i].Text
        $text = $text -replace '\s*[▲▼]$', ''
        $ListView.Columns[$i].Text = $text
    }

    if ($ColumnIndex -ge 0 -and $ColumnIndex -lt $ListView.Columns.Count) {
        $arrow = if ($Ascending) { " ▲" } else { " ▼" }
        $ListView.Columns[$ColumnIndex].Text = ($ListView.Columns[$ColumnIndex].Text -replace '\s*[▲▼]$', '') + $arrow
    }
}

function Set-SortableListView {
    param([System.Windows.Forms.ListView]$ListView)

    $ListView.Add_ColumnClick({
        param($Sender, $EventArgs)

        if ($script:SortColumn -eq $EventArgs.Column) {
            $script:SortAscending = -not $script:SortAscending
        }
        else {
            $script:SortColumn = $EventArgs.Column
            $script:SortAscending = $true
        }

        $items = @()
        foreach ($item in $Sender.Items) {
            $items += $item
        }

        if ($script:SortAscending) {
            $sorted = $items | Sort-Object {
                Convert-ListViewSortValue -Value $_.SubItems[$EventArgs.Column].Text
            }
        }
        else {
            $sorted = $items | Sort-Object {
                Convert-ListViewSortValue -Value $_.SubItems[$EventArgs.Column].Text
            } -Descending
        }

        $Sender.BeginUpdate()
        try {
            $Sender.Items.Clear()

            foreach ($item in $sorted) {
                [void]$Sender.Items.Add($item)
            }

            Set-ListViewColumnSortIndicators -ListView $Sender -ColumnIndex $EventArgs.Column -Ascending $script:SortAscending
        }
        finally {
            $Sender.EndUpdate()
        }
    })
}

# ------------------------------------------------------------
# GUI construction
# ------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "AD Computer Lifecycle Governance Operations Center"
$form.ClientSize = New-Object System.Drawing.Size(1700, 850)
$form.MinimumSize = New-Object System.Drawing.Size(1450, 780)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$filterPanel = New-Object System.Windows.Forms.Panel
$filterPanel.Location = New-Object System.Drawing.Point(10, 10)
$filterPanel.Size = New-Object System.Drawing.Size(1680, 48)
$filterPanel.Anchor = "Top,Left,Right"
$filterPanel.BackColor = [System.Drawing.Color]::FromArgb(245,245,245)

$actionPanel = New-Object System.Windows.Forms.Panel
$actionPanel.Location = New-Object System.Drawing.Point(10, 62)
$actionPanel.Size = New-Object System.Drawing.Size(1680, 58)
$actionPanel.Anchor = "Top,Left,Right"
$actionPanel.BackColor = [System.Drawing.Color]::FromArgb(245,245,245)

$labelWorkflow = New-Object System.Windows.Forms.Label
$labelWorkflow.Text = "Filter:"
$labelWorkflow.Location = New-Object System.Drawing.Point(15, 15)
$labelWorkflow.AutoSize = $true

$comboWorkflow = New-Object System.Windows.Forms.ComboBox
$comboWorkflow.Location = New-Object System.Drawing.Point(80, 11)
$comboWorkflow.Size = New-Object System.Drawing.Size(300, 28)
$comboWorkflow.DropDownStyle = "DropDownList"
[void]$comboWorkflow.Items.Add("All Lifecycle Candidates")
[void]$comboWorkflow.Items.Add("Disabled Only")
[void]$comboWorkflow.Items.Add("Enabled Stale Only")
[void]$comboWorkflow.Items.Add("Safe Remove")
[void]$comboWorkflow.Items.Add("Manual Review")
[void]$comboWorkflow.Items.Add("Risk Only")
$comboWorkflow.SelectedIndex = 0

$labelDomain = New-Object System.Windows.Forms.Label
$labelDomain.Text = "Domain:"
$labelDomain.Location = New-Object System.Drawing.Point(400, 15)
$labelDomain.AutoSize = $true

$comboDomain = New-Object System.Windows.Forms.ComboBox
$comboDomain.Location = New-Object System.Drawing.Point(460, 11)
$comboDomain.Size = New-Object System.Drawing.Size(290, 28)
$comboDomain.DropDownStyle = "DropDownList"
[void]$comboDomain.Items.Add("ALL_FOREST_DOMAINS")

# Domains are intentionally not enumerated during GUI startup.
# This follows the Check-Shorter-ADComputerNames.ps1 model:
# open the GUI first, then touch Active Directory only after an operator action.
$comboDomain.SelectedIndex = 0

$labelDays = New-Object System.Windows.Forms.Label
$labelDays.Text = "Inactive Days:"
$labelDays.Location = New-Object System.Drawing.Point(770, 15)
$labelDays.AutoSize = $true

$textInactiveDays = New-Object System.Windows.Forms.TextBox
$textInactiveDays.Location = New-Object System.Drawing.Point(870, 11)
$textInactiveDays.Size = New-Object System.Drawing.Size(70, 28)
$textInactiveDays.Text = "180"

$checkboxDNS = New-Object System.Windows.Forms.CheckBox
$checkboxDNS.Text = "DNS Check"
$checkboxDNS.Location = New-Object System.Drawing.Point(965, 13)
$checkboxDNS.AutoSize = $true

$checkboxPing = New-Object System.Windows.Forms.CheckBox
$checkboxPing.Text = "Ping Check"
$checkboxPing.Location = New-Object System.Drawing.Point(1075, 13)
$checkboxPing.AutoSize = $true

$checkboxUnknownOS = New-Object System.Windows.Forms.CheckBox
$checkboxUnknownOS.Text = "Include Unknown OS"
$checkboxUnknownOS.Location = New-Object System.Drawing.Point(1185, 13)
$checkboxUnknownOS.AutoSize = $true

$checkboxServerLike = New-Object System.Windows.Forms.CheckBox
$checkboxServerLike.Text = "Include Server-Like OS"
$checkboxServerLike.Location = New-Object System.Drawing.Point(1355, 13)
$checkboxServerLike.AutoSize = $true

$buttonRun = New-Object System.Windows.Forms.Button
$buttonRun.Text = "Run Lifecycle Scan"
$buttonRun.Location = New-Object System.Drawing.Point(15, 12)
$buttonRun.Size = New-Object System.Drawing.Size(155, 34)
$buttonRun.BackColor = [System.Drawing.Color]::FromArgb(52,152,219)
$buttonRun.ForeColor = [System.Drawing.Color]::White
$buttonRun.FlatStyle = "Flat"

$buttonExport = New-Object System.Windows.Forms.Button
$buttonExport.Text = "Export CSV"
$buttonExport.Location = New-Object System.Drawing.Point(185, 12)
$buttonExport.Size = New-Object System.Drawing.Size(125, 34)
$buttonExport.BackColor = [System.Drawing.Color]::FromArgb(46,204,113)
$buttonExport.ForeColor = [System.Drawing.Color]::White
$buttonExport.FlatStyle = "Flat"

$buttonExportState = New-Object System.Windows.Forms.Button
$buttonExportState.Text = "Export State"
$buttonExportState.Location = New-Object System.Drawing.Point(320, 12)
$buttonExportState.Size = New-Object System.Drawing.Size(125, 34)
$buttonExportState.BackColor = [System.Drawing.Color]::FromArgb(39,174,96)
$buttonExportState.ForeColor = [System.Drawing.Color]::White
$buttonExportState.FlatStyle = "Flat"

$buttonLoadDomains = New-Object System.Windows.Forms.Button
$buttonLoadDomains.Text = "Load Domains"
$buttonLoadDomains.Location = New-Object System.Drawing.Point(455, 12)
$buttonLoadDomains.Size = New-Object System.Drawing.Size(130, 34)
$buttonLoadDomains.BackColor = [System.Drawing.Color]::FromArgb(41,128,185)
$buttonLoadDomains.ForeColor = [System.Drawing.Color]::White
$buttonLoadDomains.FlatStyle = "Flat"

$buttonRemove = New-Object System.Windows.Forms.Button
$buttonRemove.Text = "Delete Checked AD Objects"
$buttonRemove.Location = New-Object System.Drawing.Point(1010, 12)
$buttonRemove.Size = New-Object System.Drawing.Size(185, 34)
$buttonRemove.BackColor = [System.Drawing.Color]::FromArgb(192,57,43)
$buttonRemove.ForeColor = [System.Drawing.Color]::White
$buttonRemove.FlatStyle = "Flat"

$buttonQuarantine = New-Object System.Windows.Forms.Button
$buttonQuarantine.Text = "Quarantine"
$buttonQuarantine.Location = New-Object System.Drawing.Point(610, 12)
$buttonQuarantine.Size = New-Object System.Drawing.Size(110, 34)
$buttonQuarantine.BackColor = [System.Drawing.Color]::FromArgb(243,156,18)
$buttonQuarantine.ForeColor = [System.Drawing.Color]::White
$buttonQuarantine.FlatStyle = "Flat"

$buttonPendingRemoval = New-Object System.Windows.Forms.Button
$buttonPendingRemoval.Text = "Pending Removal"
$buttonPendingRemoval.Location = New-Object System.Drawing.Point(730, 12)
$buttonPendingRemoval.Size = New-Object System.Drawing.Size(145, 34)
$buttonPendingRemoval.BackColor = [System.Drawing.Color]::FromArgb(211,84,0)
$buttonPendingRemoval.ForeColor = [System.Drawing.Color]::White
$buttonPendingRemoval.FlatStyle = "Flat"

$buttonExclude = New-Object System.Windows.Forms.Button
$buttonExclude.Text = "Exclude"
$buttonExclude.Location = New-Object System.Drawing.Point(885, 12)
$buttonExclude.Size = New-Object System.Drawing.Size(95, 34)
$buttonExclude.BackColor = [System.Drawing.Color]::FromArgb(52,73,94)
$buttonExclude.ForeColor = [System.Drawing.Color]::White
$buttonExclude.FlatStyle = "Flat"



$buttonSelectAll = New-Object System.Windows.Forms.Button
$buttonSelectAll.Text = "Select All"
$buttonSelectAll.Location = New-Object System.Drawing.Point(1225, 12)
$buttonSelectAll.Size = New-Object System.Drawing.Size(105, 34)
$buttonSelectAll.BackColor = [System.Drawing.Color]::FromArgb(127,140,141)
$buttonSelectAll.ForeColor = [System.Drawing.Color]::White
$buttonSelectAll.FlatStyle = "Flat"

$buttonClear = New-Object System.Windows.Forms.Button
$buttonClear.Text = "Clear"
$buttonClear.Location = New-Object System.Drawing.Point(1340, 12)
$buttonClear.Size = New-Object System.Drawing.Size(95, 34)
$buttonClear.BackColor = [System.Drawing.Color]::FromArgb(127,140,141)
$buttonClear.ForeColor = [System.Drawing.Color]::White
$buttonClear.FlatStyle = "Flat"

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.SetToolTip($buttonRun, "Run the unified lifecycle governance scan.")
$toolTip.SetToolTip($buttonExport, "Export current result dataset to CSV.")
$toolTip.SetToolTip($buttonExportState, "Export the persistent governance state database to CSV.")
$toolTip.SetToolTip($buttonLoadDomains, "Load forest domains into the domain selector.")
$toolTip.SetToolTip($buttonQuarantine, "Mark checked objects as quarantined in governance state.")
$toolTip.SetToolTip($buttonPendingRemoval, "Mark checked objects as pending removal.")
$toolTip.SetToolTip($buttonExclude, "Exclude checked objects from normal lifecycle remediation.")
$toolTip.SetToolTip($buttonRemove, "DESTRUCTIVE: deletes checked SAFE_REMOVE workstation objects from Active Directory.")
$toolTip.SetToolTip($buttonSelectAll, "Select or deselect all visible rows.")
$toolTip.SetToolTip($buttonClear, "Clear the current grid view.")

# Legacy summary label retained only for compatibility; hidden from GUI.
$labelSummary = New-Object System.Windows.Forms.Label
$labelSummary.Visible = $false
$labelSummary.Text = ""

[void]$filterPanel.Controls.AddRange(@(
    $labelWorkflow,
    $comboWorkflow,
    $labelDomain,
    $comboDomain,
    $labelDays,
    $textInactiveDays,
    $checkboxDNS,
    $checkboxPing,
    $checkboxUnknownOS,
    $checkboxServerLike
))

[void]$actionPanel.Controls.AddRange(@(
    $buttonRun,
    $buttonExport,
    $buttonExportState,
    $buttonLoadDomains,
    $buttonQuarantine,
    $buttonPendingRemoval,
    $buttonExclude,
    $buttonRemove,
    $buttonSelectAll,
    $buttonClear
))

$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(10, 132)
$listView.Size = New-Object System.Drawing.Size(1225, 665)
$listView.Anchor = "Top,Bottom,Left,Right"
$listView.View = "Details"
$listView.FullRowSelect = $true
$listView.GridLines = $true
$listView.HideSelection = $false
$listView.CheckBoxes = $true
$listView.MultiSelect = $true

$inspectorPanel = New-Object System.Windows.Forms.GroupBox
$inspectorPanel.Text = "Object Inspector"
$inspectorPanel.Location = New-Object System.Drawing.Point(1245, 132)
$inspectorPanel.Size = New-Object System.Drawing.Size(445, 665)
$inspectorPanel.Anchor = "Top,Bottom,Right"
$inspectorPanel.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$txtInspector = New-Object System.Windows.Forms.TextBox
$txtInspector.Multiline = $true
$txtInspector.ReadOnly = $true
$txtInspector.ScrollBars = "Vertical"
$txtInspector.WordWrap = $false
$txtInspector.Location = New-Object System.Drawing.Point(10, 25)
$txtInspector.Size = New-Object System.Drawing.Size(425, 625)
$txtInspector.Anchor = "Top,Bottom,Left,Right"
$txtInspector.Font = New-Object System.Drawing.Font("Consolas", 9)

[void]$inspectorPanel.Controls.Add($txtInspector)

function Format-InspectorText {
    param([AllowNull()]$Record)

    if ($null -eq $Record) {
        return "Select an object to inspect governance details."
    }

    $lines = New-Object System.Collections.ArrayList

    [void]$lines.Add("=== IDENTITY ===")
    [void]$lines.Add(("Name                : {0}" -f $Record.Name))
    [void]$lines.Add(("SAM Account         : {0}" -f $Record.SamAccountName))
    [void]$lines.Add(("Domain              : {0}" -f $Record.SourceDomain))
    [void]$lines.Add(("Enabled             : {0}" -f $Record.Enabled))
    [void]$lines.Add(("Operating System    : {0}" -f $Record.OperatingSystem))
    [void]$lines.Add("")
    [void]$lines.Add("=== LIFECYCLE ===")
    [void]$lines.Add(("Lifecycle State     : {0}" -f $Record.LifecycleState))
    [void]$lines.Add(("Lifecycle Action    : {0}" -f $Record.LifecycleAction))
    [void]$lines.Add(("Classification      : {0}" -f $Record.Classification))
    [void]$lines.Add(("Governance Score    : {0}" -f $Record.GovernanceScore))
    [void]$lines.Add(("Recommendation      : {0}" -f $Record.Recommendation))
    [void]$lines.Add("")
    [void]$lines.Add("=== ACTIVITY ===")
    [void]$lines.Add(("Last Machine Logon  : {0}" -f $Record.EffectiveLastLogon))
    [void]$lines.Add(("Days Since Logon    : {0}" -f $Record.DaysSinceLastLogon))
    [void]$lines.Add(("Password Last Set   : {0}" -f $Record.PasswordLastSet))
    [void]$lines.Add(("Days Password       : {0}" -f $Record.DaysSincePasswordSet))
    [void]$lines.Add("")
    [void]$lines.Add("=== NETWORK ===")
    [void]$lines.Add(("DNS Hostname        : {0}" -f $Record.DNSHostName))
    [void]$lines.Add(("IPv4 Address        : {0}" -f $Record.IPv4Address))
    [void]$lines.Add(("DNS Status          : {0}" -f $Record.DnsStatus))
    [void]$lines.Add(("Ping Status         : {0}" -f $Record.PingStatus))
    [void]$lines.Add("")
    [void]$lines.Add("=== RISK ===")
    [void]$lines.Add(("SPN Risk            : {0}" -f $Record.SPNRiskTier))
    [void]$lines.Add(("SPN Count           : {0}" -f $Record.SPNCount))
    [void]$lines.Add(("Protected OU        : {0}" -f $Record.ProtectedOU))
    [void]$lines.Add(("Reasons             : {0}" -f $Record.GovernanceReasons))
    [void]$lines.Add("")
    [void]$lines.Add("=== DIRECTORY ===")
    [void]$lines.Add(("OU Path             : {0}" -f $Record.OUPath))
    [void]$lines.Add(("Distinguished Name  : {0}" -f $Record.DistinguishedName))
    [void]$lines.Add("")
    [void]$lines.Add("=== STATE ===")
    [void]$lines.Add(("Action Status       : {0}" -f $Record.ActionStatus))
    [void]$lines.Add(("Source DC           : {0}" -f $Record.SourceDomainController))

    return ($lines.ToArray() -join [Environment]::NewLine)
}

function Update-Inspector {
    param([AllowNull()]$Record)

    $txtInspector.Text = Format-InspectorText -Record $Record
}

Update-Inspector -Record $null

function Set-GridColumns {
    param(
        [Parameter()]
        [string]$Mode = "LifecycleGovernance"
    )

    $script:SortColumn = -1
    $script:SortAscending = $true
    $listView.Columns.Clear()

    [void]$listView.Columns.Add("Domain", 145)
    [void]$listView.Columns.Add("Name", 170)
    [void]$listView.Columns.Add("Enabled", 70)
    [void]$listView.Columns.Add("Inactive", 70)
    [void]$listView.Columns.Add("Lifecycle", 165)
    [void]$listView.Columns.Add("OS", 210)
    [void]$listView.Columns.Add("Last Logon", 150)
    [void]$listView.Columns.Add("Days", 70)
    [void]$listView.Columns.Add("Pwd Days", 80)
    [void]$listView.Columns.Add("SPN", 70)
    [void]$listView.Columns.Add("Score", 60)
    [void]$listView.Columns.Add("Class", 115)
}

Set-GridColumns
Set-SortableListView -ListView $listView

$statusStrip = New-Object System.Windows.Forms.StatusStrip

$statusWorkflow = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusWorkflow.Text = "Filter: Ready"

$statusObjects = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusObjects.Text = "Objects: 0"

$statusLifecycle = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLifecycle.Text = "Lifecycle: Active 0 | Stale 0 | Safe 0 | Review 0 | Risk 0"

$statusLog = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLog.Spring = $true
$statusLog.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$statusLog.Text = "Log: $Script:LogPath"

[void]$statusStrip.Items.Add($statusWorkflow)
[void]$statusStrip.Items.Add($statusObjects)
[void]$statusStrip.Items.Add($statusLifecycle)
[void]$statusStrip.Items.Add($statusLog)

function Set-TelemetryStatus {
    param(
        [string]$Workflow = "Ready",
        [int]$Objects = 0,
        [int]$Active = 0,
        [int]$Stale = 0,
        [int]$Safe = 0,
        [int]$Review = 0,
        [int]$Risk = 0
    )

    $statusWorkflow.Text = "Filter: $Workflow"
    $statusObjects.Text = "Objects: $Objects"
    $statusLifecycle.Text = "Lifecycle: Active $Active | Stale $Stale | Safe $Safe | Review $Review | Risk $Risk"
}

[void]$form.Controls.AddRange(@($filterPanel, $actionPanel, $listView, $inspectorPanel, $statusStrip))

$script:CurrentResults = @()
$script:AllSelectedState = $false

function Add-RecordToGrid {
    param([Parameter(Mandatory = $true)]$Record)

    $item = New-Object System.Windows.Forms.ListViewItem([string]$Record.SourceDomain)

    [void]$item.SubItems.Add([string]$Record.Name)
    [void]$item.SubItems.Add([string]$Record.Enabled)
    [void]$item.SubItems.Add([string]$Record.InactiveCandidate)
    [void]$item.SubItems.Add([string]$Record.LifecycleState)
    [void]$item.SubItems.Add([string]$Record.OperatingSystem)
    [void]$item.SubItems.Add([string]$Record.EffectiveLastLogon)
    [void]$item.SubItems.Add([string]$Record.DaysSinceLastLogon)
    [void]$item.SubItems.Add([string]$Record.DaysSincePasswordSet)
    [void]$item.SubItems.Add([string]$Record.SPNRiskTier)
    [void]$item.SubItems.Add([string]$Record.GovernanceScore)
    [void]$item.SubItems.Add([string]$Record.Classification)

    $item.Tag = $Record

    switch ($Record.LifecycleState) {
        "SAFE_REMOVE" {
            $item.BackColor = [System.Drawing.Color]::LightGreen
        }
        "DISABLED_PENDING_REVIEW" {
            $item.BackColor = [System.Drawing.Color]::Khaki
        }
        "STALE_ENABLED" {
            $item.BackColor = [System.Drawing.Color]::Moccasin
        }
        "RISK_MANUAL_REVIEW" {
            $item.BackColor = [System.Drawing.Color]::LightCoral
        }
        default {
            switch ($Record.Classification) {
                "SAFE_REMOVE" { $item.BackColor = [System.Drawing.Color]::LightGreen }
                "REVIEW"      { $item.BackColor = [System.Drawing.Color]::Khaki }
                "RISK"        { $item.BackColor = [System.Drawing.Color]::LightCoral }
                default       { $item.BackColor = [System.Drawing.Color]::White }
            }
        }
    }

    [void]$listView.Items.Add($item)
}

function Select-LifecycleResultsByFilter {
    param(
        [Parameter(Mandatory = $true)]$Results,
        [Parameter(Mandatory = $true)][string]$Filter
    )

    $items = @(ConvertTo-SafeArray -InputObject $Results)

    switch ($Filter) {
        "Disabled Only" {
            return @($items | Where-Object { $_.Enabled -eq $false })
        }
        "Enabled Stale Only" {
            return @($items | Where-Object { $_.Enabled -eq $true -and $_.InactiveCandidate -eq $true })
        }
        "Safe Remove" {
            return @($items | Where-Object { $_.Classification -eq "SAFE_REMOVE" -or $_.LifecycleState -eq "SAFE_REMOVE" })
        }
        "Manual Review" {
            return @($items | Where-Object { $_.Classification -eq "REVIEW" -or $_.LifecycleState -eq "DISABLED_PENDING_REVIEW" })
        }
        "Risk Only" {
            return @($items | Where-Object { $_.Classification -eq "RISK" -or $_.LifecycleState -eq "RISK_MANUAL_REVIEW" })
        }
        default {
            return @($items)
        }
    }
}

# ------------------------------------------------------------
# Events
# ------------------------------------------------------------

$listView.Add_SelectedIndexChanged({
    Invoke-GuiSafe -Context "Update object inspector" -ScriptBlock {
        if ($listView.SelectedItems.Count -gt 0) {
            $selected = $listView.SelectedItems[0]
            Update-Inspector -Record $selected.Tag
        }
        else {
            Update-Inspector -Record $null
        }
    }
})

$comboWorkflow.Add_SelectedIndexChanged({
    Invoke-GuiSafe -Context "Lifecycle filter changed" -ScriptBlock {
        $listView.Items.Clear()
        Update-Inspector -Record $null
        $script:AllSelectedState = $false
        $buttonSelectAll.Text = "Select All"

        Set-GridColumns

        $comboDomain.Enabled = $true
        $textInactiveDays.Enabled = $true
        $buttonRemove.Visible = $true
        $buttonRemove.Enabled = $true
        $buttonQuarantine.Visible = $true
        $buttonQuarantine.Enabled = $true
        $buttonPendingRemoval.Visible = $true
        $buttonPendingRemoval.Enabled = $true
        $buttonExclude.Visible = $true
        $buttonExclude.Enabled = $true
        $buttonSelectAll.Visible = $true
        $buttonSelectAll.Enabled = $true
        $checkboxUnknownOS.Enabled = $true
        $checkboxServerLike.Enabled = $true
        $listView.CheckBoxes = $true

        if ((Get-SafeCount -InputObject $script:CurrentResults) -gt 0) {
            $filtered = @(Select-LifecycleResultsByFilter -Results $script:CurrentResults -Filter ([string]$comboWorkflow.SelectedItem))

            foreach ($record in $filtered) {
                Add-RecordToGrid -Record $record
            }

            Set-StatusText -Label $labelSummary -Text "Filtered: $((Get-SafeCount -InputObject $filtered))"
        }
        else {
            Set-StatusText -Label $labelSummary -Text "Ready."
        }
    }
})

$comboWorkflow.SelectedIndex = 0
$comboDomain.Enabled = $true
$textInactiveDays.Enabled = $true
$buttonRemove.Visible = $true
$buttonRemove.Enabled = $true
$buttonQuarantine.Visible = $true
$buttonQuarantine.Enabled = $true
$buttonPendingRemoval.Visible = $true
$buttonPendingRemoval.Enabled = $true
$buttonExclude.Visible = $true
$buttonExclude.Enabled = $true
$buttonSelectAll.Visible = $true
$buttonSelectAll.Enabled = $true
$listView.CheckBoxes = $true

$buttonRun.Add_Click({
    Invoke-GuiSafe -Context "Run unified lifecycle governance scan" -ScriptBlock {
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        $buttonRun.Enabled = $false
        $listView.BeginUpdate()
        $listView.Items.Clear()
        Update-Inspector -Record $null
        $script:CurrentResults = @()

        try {
            $inactiveDays = 180
            if (-not [int]::TryParse($textInactiveDays.Text, [ref]$inactiveDays)) {
                Show-AppMessage -Message "Invalid inactive days value. The default value of 180 will be used." -Type Warning
                $inactiveDays = 180
            }

            Set-GridColumns
            $listView.CheckBoxes = $true

            $domainScope = [string]$comboDomain.SelectedItem
            if ([string]::IsNullOrWhiteSpace($domainScope)) {
                $domainScope = "ALL_FOREST_DOMAINS"
            }

            Set-StatusText -Label $labelSummary -Text "Scanning..."
            Write-Log -Message "Started Unified AD Computer Lifecycle Governance Scan. Scope: $domainScope | Days: $inactiveDays" -Level INFO

            $script:CurrentResults = Invoke-InactiveWorkstationsLifecycleDiscovery `
                -DomainScope $domainScope `
                -InactiveDays $inactiveDays `
                -EnableDNS ([bool]$checkboxDNS.Checked) `
                -EnablePing ([bool]$checkboxPing.Checked)

            $workflowStateName = "UNIFIED_AD_COMPUTER_LIFECYCLE_GOVERNANCE"
            Update-GovernanceStateFromResults -Results $script:CurrentResults -Workflow $workflowStateName

            $filtered = @(Select-LifecycleResultsByFilter -Results $script:CurrentResults -Filter ([string]$comboWorkflow.SelectedItem))

            foreach ($record in (ConvertTo-SafeArray -InputObject $filtered)) {
                Add-RecordToGrid -Record $record
            }

            $total = Get-SafeCount -InputObject $script:CurrentResults
            $visible = Get-SafeCount -InputObject $filtered
            $active = Get-SafeCount -InputObject ($script:CurrentResults | Where-Object { $_.LifecycleState -eq "ACTIVE" })
            $stale = Get-SafeCount -InputObject ($script:CurrentResults | Where-Object { $_.LifecycleState -eq "STALE_ENABLED" })
            $safe = Get-SafeCount -InputObject ($script:CurrentResults | Where-Object { $_.LifecycleState -eq "SAFE_REMOVE" })
            $review = Get-SafeCount -InputObject ($script:CurrentResults | Where-Object { $_.LifecycleState -eq "DISABLED_PENDING_REVIEW" })
            $risk = Get-SafeCount -InputObject ($script:CurrentResults | Where-Object { $_.LifecycleState -eq "RISK_MANUAL_REVIEW" })

            Set-TelemetryStatus -Workflow "Unified Lifecycle Governance" -Objects $total -Active $active -Stale $stale -Safe $safe -Review $review -Risk $risk
            Set-StatusText -Label $labelSummary -Text "Visible: $visible / $total"
            Write-Log -Message "Unified scan completed. Objects: $total | Visible: $visible | Active: $active | Stale Enabled: $stale | Safe Remove: $safe | Review: $review | Risk: $risk" -Level SUCCESS
        }
        finally {
            $listView.EndUpdate()
            $buttonRun.Enabled = $true
            $form.Cursor = [System.Windows.Forms.Cursors]::Default
        }
    }
})

$buttonExport.Add_Click({
    Invoke-GuiSafe -Context "Export CSV" -ScriptBlock {
        if ((Get-SafeCount -InputObject $script:CurrentResults) -eq 0) {
            Show-AppMessage -Message "There is no data to export." -Type Information
            return
        }

        $csvPath = Join-Path $Script:LogDir ("{0}-{1}.csv" -f $scriptName, (Get-Date -Format "yyyyMMdd-HHmmss"))

        $script:CurrentResults |
            Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

        Write-Log -Message "CSV exported: $csvPath" -Level SUCCESS
        Show-AppMessage -Message "CSV exported:`r`n`r`n$csvPath" -Type Information
    }
})

$buttonExportState.Add_Click({
    Invoke-GuiSafe -Context "Export governance state" -ScriptBlock {
        Export-GovernanceStateCsv
    }
})

$buttonLoadDomains.Add_Click({
    Invoke-GuiSafe -Context "Load forest domains" -ScriptBlock {
        $comboDomain.Items.Clear()
        [void]$comboDomain.Items.Add("ALL_FOREST_DOMAINS")

        foreach ($domain in (Get-ForestDomainsSafe)) {
            [void]$comboDomain.Items.Add($domain)
        }

        $comboDomain.SelectedIndex = 0
        Show-AppMessage -Message "Forest domains loaded into the domain selector." -Type Information
    }
})

$buttonSelectAll.Add_Click({
    Invoke-GuiSafe -Context "Select or deselect all" -ScriptBlock {
        $script:AllSelectedState = -not $script:AllSelectedState

        foreach ($item in $listView.Items) {
            $item.Checked = $script:AllSelectedState
        }

        if ($script:AllSelectedState) { $buttonSelectAll.Text = "Deselect All" }
        else { $buttonSelectAll.Text = "Select All" }
    }
})

function Get-CheckedGovernanceRecordsFromGrid {
    $checkedItems = @(Get-ListViewCheckedItemsSafe -ListView $listView)
    $records = New-Object System.Collections.ArrayList

    foreach ($item in $checkedItems) {
        if ($null -ne $item.Tag) {
            [void]$records.Add($item.Tag)
        }
    }

    return @($records.ToArray())
}

$buttonQuarantine.Add_Click({
    Invoke-GuiSafe -Context "Set checked records to quarantined" -ScriptBlock {
        $records = @(Get-CheckedGovernanceRecordsFromGrid)

        if ((Get-SafeCount -InputObject $records) -eq 0) {
            Show-AppMessage -Message "No workstation selected." -Type Information
            return
        }

        if (-not (Confirm-Action -Message "Set $((Get-SafeCount -InputObject $records)) checked object(s) to QUARANTINED?")) {
            return
        }

        Set-CheckedRecordsOrchestrationState -Records $records -NewState "QUARANTINED"
    }
})

$buttonPendingRemoval.Add_Click({
    Invoke-GuiSafe -Context "Set checked records to pending removal" -ScriptBlock {
        $records = @(Get-CheckedGovernanceRecordsFromGrid)

        if ((Get-SafeCount -InputObject $records) -eq 0) {
            Show-AppMessage -Message "No workstation selected." -Type Information
            return
        }

        if (-not (Confirm-Action -Message "Set $((Get-SafeCount -InputObject $records)) checked object(s) to PENDING_REMOVAL?")) {
            return
        }

        Set-CheckedRecordsOrchestrationState -Records $records -NewState "PENDING_REMOVAL"
    }
})

$buttonExclude.Add_Click({
    Invoke-GuiSafe -Context "Exclude checked records from lifecycle governance" -ScriptBlock {
        $records = @(Get-CheckedGovernanceRecordsFromGrid)

        if ((Get-SafeCount -InputObject $records) -eq 0) {
            Show-AppMessage -Message "No workstation selected." -Type Information
            return
        }

        if (-not (Confirm-Action -Message "Set $((Get-SafeCount -InputObject $records)) checked object(s) to EXCLUDED?")) {
            return
        }

        Set-CheckedRecordsOrchestrationState -Records $records -NewState "EXCLUDED"
    }
})

$buttonRemove.Add_Click({
    Invoke-GuiSafe -Context "Delete checked AD workstation objects" -ScriptBlock {
        Write-Log -Message "Delete Checked AD Objects button clicked. This is the destructive AD workstation cleanup action." -Level WARNING
        $checkedItems = @(Get-ListViewCheckedItemsSafe -ListView $listView)

        if ((Get-SafeCount -InputObject $checkedItems) -eq 0) {
            Show-AppMessage -Message "No workstation selected for removal." -Type Information
            return
        }

        $msg = "DELETE $((Get-SafeCount -InputObject $checkedItems)) checked AD workstation object(s)?`r`n`r`nThis is the cleanup/removal action and will DELETE the selected AD computer object(s).`r`n`r`nOnly SAFE_REMOVE objects are eligible. Proceed only after exporting and validating the evidence."

        if (-not (Confirm-Action -Message $msg)) {
            return
        }

        $selectedRecords = @(Get-CheckedGovernanceRecordsFromGrid)

        Remove-SelectedWorkstationAccounts -SelectedRecords $selectedRecords
    }
})

$buttonClear.Add_Click({
    Invoke-GuiSafe -Context "Clear grid" -ScriptBlock {
        $listView.Items.Clear()
        Update-Inspector -Record $null
        $script:CurrentResults = @()
        $script:AllSelectedState = $false
        $buttonSelectAll.Text = "Select All"
        Set-StatusText -Label $labelSummary -Text "Ready."
    }
})

[void]$form.ShowDialog()

# End of script
