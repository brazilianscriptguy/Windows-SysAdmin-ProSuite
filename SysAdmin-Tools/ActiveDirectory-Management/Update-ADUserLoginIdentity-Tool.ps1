<#
.SYNOPSIS
  Active Directory Login Identity Migration Console - multi-environment OldLogin to NewLogin mapping.

.DESCRIPTION
  Enterprise and governance-grade Windows Forms GUI tool for controlled multi-environment Active Directory login migration.

  Implements:
  - Responsive Windows Forms GUI using MenuStrip, StatusStrip and TableLayoutPanel
  - Flexible mapping schema: "oldlogin","newlogin" with aliases for oldsamaccountname/newsamaccountname and matricula/cpf
  - New login values are read as text, preserving leading zeros and non-country-specific identifiers
  - Mapping validation before Active Directory preview
  - Interactive OU search/browse
  - Forest domain discovery and writable DC resolution
  - Preview-first workflow
  - Preview-first workflow with Apply-time Simulation (Dry Run) or Commit mode
  - PowerShell native WhatIf support for console execution only
  - DN-based Set-ADUser updates
  - Idempotent alignment of sAMAccountName and userPrincipalName
  - Current per-user UPN suffix preservation during alignment
  - Rollback CSV and undo-last-change capability
  - Runtime log panel, statistics section and double-click row details dialog
  - Structured logs/reports in C:\Logs-TEMP

.AUTHOR
  Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
  2026-07-08-v4.0.0-MULTI-ENVIRONMENT-GENERIC-LOGIN-GOVERNANCE-GUI
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [switch]$ShowConsole
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# =====================================================================================
# Assemblies and process mode
# =====================================================================================
try {
    if (-not $ShowConsole) {
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

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Data
    [System.Windows.Forms.Application]::EnableVisualStyles()
    [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
} catch {
    Write-Error "Failed to initialize WinForms assemblies: $($_.Exception.Message)"
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

$script:Domains        = @()
$script:WritableDC     = $null
$script:MappingTable   = @{}
$script:MappingReverseTable = @{}
$script:MappingRows    = @()
$script:MappingLookupAll = @{}
$script:MappingReverseLookupAll = @{}
$script:PreviewItems   = New-Object System.Collections.ArrayList
$script:UndoStack      = New-Object System.Collections.Stack
$script:Stats          = [ordered]@{
    MappingRows          = 0
    MappingReady         = 0
    MappingDuplicatesOld = 0
    MappingDuplicatesNew = 0
    MappingInvalid       = 0
    UsersRead            = 0
    PreviewReady         = 0
    PreviewSkipped       = 0
    PreviewErrors        = 0
    Updated              = 0
    Failed               = 0
}

New-Item -ItemType Directory -Path $script:LogRoot -Force | Out-Null
New-Item -ItemType Directory -Path $script:ReportRoot -Force | Out-Null

# GUI variables
$script:form = $null
$script:cmbDomain = $null
$script:txtDC = $null
$script:txtSearchBase = $null
$script:txtMappingFile = $null
$script:lblMapStatus = $null
$script:progressMapping = $null
$script:btnLoadMap = $null
$script:btnBrowseMap = $null
$script:chkIncludeDisabled = $null
$script:chkCpfChecksum = $null
$script:chkDryRun = $null
$script:grid = $null
$script:txtLog = $null
$script:txtDetails = $null
$script:txtStats = $null
$script:statusMain = $null
$script:statusDomain = $null
$script:statusDC = $null
$script:statusMapping = $null
$script:statusPreview = $null

# =====================================================================================
# Logging and UI helpers
# =====================================================================================
function Write-AppLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','SUCCESS','WARN','ERROR','DEBUG')][string]$Level = 'INFO'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
    if ($script:txtLog -and -not $script:txtLog.IsDisposed) {
        $script:txtLog.AppendText($line + [Environment]::NewLine)
        $script:txtLog.SelectionStart = $script:txtLog.Text.Length
        $script:txtLog.ScrollToCaret()
    }
}

function Show-AppMessage {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Title = 'AD sAMAccountName Migration Console',
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )
    [void][System.Windows.Forms.MessageBox]::Show($script:form, $Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon)
}

function Update-StatusBar {
    param([string]$Message = 'Ready')
    if ($script:statusMain)    { $script:statusMain.Text    = $Message }
    if ($script:statusDomain)  { $script:statusDomain.Text  = "Domain: $($script:cmbDomain.Text)" }
    if ($script:statusDC)      { $script:statusDC.Text      = "DC: $($script:txtDC.Text)" }
    if ($script:statusMapping) { $script:statusMapping.Text = "Mapping: $($script:Stats.MappingReady)/$($script:Stats.MappingRows)" }
    if ($script:statusPreview) { $script:statusPreview.Text = "Preview: $($script:Stats.PreviewReady) ready / $($script:Stats.PreviewErrors) errors" }
}


function Set-MappingLoadBusy {
    param(
        [bool]$IsBusy,
        [string]$Message = ''
    )

    if ($script:lblMapStatus -and -not $script:lblMapStatus.IsDisposed -and -not [string]::IsNullOrWhiteSpace($Message)) {
        $script:lblMapStatus.Text = $Message
    }

    if ($script:progressMapping -and -not $script:progressMapping.IsDisposed) {
        if ($IsBusy) {
            $script:progressMapping.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
            $script:progressMapping.MarqueeAnimationSpeed = 35
            $script:progressMapping.Visible = $true
        }
        else {
            $script:progressMapping.MarqueeAnimationSpeed = 0
            $script:progressMapping.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
            $script:progressMapping.Visible = $false
        }
    }

    foreach ($control in @($script:btnLoadMap, $script:btnBrowseMap, $script:txtMappingFile, $script:chkCpfChecksum)) {
        if ($control -and -not $control.IsDisposed) {
            $control.Enabled = -not $IsBusy
        }
    }

    if ($script:form -and -not $script:form.IsDisposed) {
        if ($IsBusy) { $script:form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor }
        else { $script:form.Cursor = [System.Windows.Forms.Cursors]::Default }
    }

    Update-StatusBar $(if ($IsBusy) { 'Loading and validating mapping file...' } else { 'Ready.' })
    [System.Windows.Forms.Application]::DoEvents()
}

function Invoke-UIAction {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [string]$ErrorTitle = 'Operation Error'
    )
    try {
        & $Action
    } catch {
        $msg = $_.Exception.Message
        Write-AppLog $msg 'ERROR'
        Show-AppMessage $msg $ErrorTitle ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Refresh-StatisticsView {
    if (-not $script:txtStats -or $script:txtStats.IsDisposed) { return }

    $script:txtStats.BeginUpdate()
    try {
        $script:txtStats.Items.Clear()

        function Add-StatsRow {
            param(
                [Parameter(Mandatory)][string]$Metric,
                [AllowNull()][object]$Value,
                [bool]$IsSection = $false,
                [string]$Level = 'NORMAL'
            )

            $item = New-Object System.Windows.Forms.ListViewItem($Metric)
            [void]$item.SubItems.Add([string]$Value)

            if ($IsSection) {
                $item.Font = New-Object System.Drawing.Font('Segoe UI',8.25,[System.Drawing.FontStyle]::Bold)
                $item.BackColor = [System.Drawing.Color]::FromArgb(235,240,245)
            }
            else {
                switch ($Level) {
                    'GOOD' { $item.ForeColor = [System.Drawing.Color]::DarkGreen }
                    'WARN' { $item.ForeColor = [System.Drawing.Color]::DarkOrange }
                    'BAD'  { $item.ForeColor = [System.Drawing.Color]::Firebrick }
                    default { $item.ForeColor = [System.Drawing.Color]::Black }
                }
            }

            [void]$script:txtStats.Items.Add($item)
        }

        Add-StatsRow 'Mapping' '' $true
        Add-StatsRow 'Rows read'             $script:Stats.MappingRows
        Add-StatsRow 'Ready mappings'        $script:Stats.MappingReady -Level 'GOOD'
        Add-StatsRow 'Duplicate old logins'  $script:Stats.MappingDuplicatesOld -Level $(if ($script:Stats.MappingDuplicatesOld -gt 0) { 'WARN' } else { 'GOOD' })
        Add-StatsRow 'Duplicate new logins'  $script:Stats.MappingDuplicatesNew -Level $(if ($script:Stats.MappingDuplicatesNew -gt 0) { 'WARN' } else { 'GOOD' })
        Add-StatsRow 'Invalid mappings'      $script:Stats.MappingInvalid -Level $(if ($script:Stats.MappingInvalid -gt 0) { 'WARN' } else { 'GOOD' })

        Add-StatsRow 'Preview' '' $true
        Add-StatsRow 'AD users read'         $script:Stats.UsersRead
        Add-StatsRow 'Actionable rows'            $script:Stats.PreviewReady -Level $(if ($script:Stats.PreviewReady -gt 0) { 'GOOD' } else { 'NORMAL' })
        Add-StatsRow 'SKIPPED rows'          $script:Stats.PreviewSkipped -Level $(if ($script:Stats.PreviewSkipped -gt 0) { 'WARN' } else { 'GOOD' })
        Add-StatsRow 'ERROR rows'            $script:Stats.PreviewErrors -Level $(if ($script:Stats.PreviewErrors -gt 0) { 'BAD' } else { 'GOOD' })

        Add-StatsRow 'Execution' '' $true
        Add-StatsRow 'Updated'               $script:Stats.Updated -Level $(if ($script:Stats.Updated -gt 0) { 'GOOD' } else { 'NORMAL' })
        Add-StatsRow 'Failed'                $script:Stats.Failed -Level $(if ($script:Stats.Failed -gt 0) { 'BAD' } else { 'GOOD' })
    }
    finally {
        if ($script:txtStats.Columns.Count -ge 2) {
            $script:txtStats.Columns[0].Width = 145
            $script:txtStats.Columns[1].Width = 80
        }
        $script:txtStats.EndUpdate()
    }
}

# =====================================================================================
# Validation helpers
# =====================================================================================
function Normalize-Digits {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Trim() -replace '\D',''
}

function Test-ValidSamAccountName {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    if ($Value.Length -gt 20) { return $false }
    # Microsoft restriction for sAMAccountName: / \ [ ] : ; | = , + * ? < > and quotes
    if ($Value -match '["/\\\[\]:;\|=,\+\*\?<>]') { return $false }
    return $true
}

function Test-CPFChecksum {
    param([string]$CPF)
    $cpfDigits = Normalize-Digits $CPF
    if ($cpfDigits.Length -ne 11) { return $false }
    if ($cpfDigits -match '^(\d)\1{10}$') { return $false }

    $n = @()
    foreach ($c in $cpfDigits.ToCharArray()) { $n += [int]([string]$c) }

    $sum = 0
    for ($i = 0; $i -lt 9; $i++) { $sum += $n[$i] * (10 - $i) }
    $r = $sum % 11
    if ($r -lt 2) { $d1 = 0 } else { $d1 = 11 - $r }

    $sum = 0
    for ($i = 0; $i -lt 10; $i++) { $sum += $n[$i] * (11 - $i) }
    $r = $sum % 11
    if ($r -lt 2) { $d2 = 0 } else { $d2 = 11 - $r }

    return ($n[9] -eq $d1 -and $n[10] -eq $d2)
}

# =====================================================================================
# AD helpers
# =====================================================================================
function Test-ADModule {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw 'ActiveDirectory PowerShell module not found. Install RSAT Active Directory tools or run on an AD management server.'
    }
    Import-Module ActiveDirectory -ErrorAction Stop
}

function Get-ForestDomainsSafe {
    Test-ADModule
    $forest = Get-ADForest -ErrorAction Stop
    return @($forest.Domains | Sort-Object)
}

function Get-DomainDN {
    param([Parameter(Mandatory)][string]$Domain)
    return (($Domain -split '\.') | ForEach-Object { "DC=$_" }) -join ','
}

function Convert-ToSingleString {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [System.Array]) { return [string]($Value | Select-Object -First 1) }
    if ($Value.PSObject.TypeNames -contains 'Microsoft.ActiveDirectory.Management.ADPropertyValueCollection') {
        return [string]($Value | Select-Object -First 1)
    }
    return [string]$Value
}

function Get-CurrentServerName {
    if (-not [string]::IsNullOrWhiteSpace($script:WritableDC)) {
        return (Convert-ToSingleString $script:WritableDC)
    }
    if ($script:txtDC -and -not [string]::IsNullOrWhiteSpace($script:txtDC.Text)) {
        return (Convert-ToSingleString $script:txtDC.Text)
    }
    return ''
}

function Resolve-WritableDC {
    param([Parameter(Mandatory)][string]$Domain)
    Test-ADModule
    $dc = Get-ADDomainController -Discover -Writable -DomainName $Domain -ErrorAction Stop
    $dcHost = Convert-ToSingleString $dc.HostName
    if ([string]::IsNullOrWhiteSpace($dcHost)) { $dcHost = Convert-ToSingleString $dc.Name }
    if ([string]::IsNullOrWhiteSpace($dcHost)) { throw "Unable to resolve a writable domain controller hostname for ${Domain}." }

    $script:WritableDC = $dcHost
    if ($script:txtDC) { $script:txtDC.Text = $dcHost }
    Write-AppLog "Resolved writable domain controller for ${Domain}: $dcHost" 'SUCCESS'
    Update-StatusBar 'Writable DC resolved.'
    return $dcHost
}

function Get-OUList {
    param([Parameter(Mandatory)][string]$Domain)
    Test-ADModule
    $server = Get-CurrentServerName
    if ([string]::IsNullOrWhiteSpace($server)) { $server = Resolve-WritableDC -Domain $Domain }
    $server = Convert-ToSingleString $server
    $base = Get-DomainDN -Domain $Domain
    return @(Get-ADOrganizationalUnit -Filter * -SearchBase $base -Server $server -Properties DistinguishedName,Name -ErrorAction Stop |
        Sort-Object DistinguishedName |
        Select-Object Name, DistinguishedName)
}

function Escape-LdapFilterValue {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    $text = [string]$Value
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $text.ToCharArray()) {
        switch ([int][char]$ch) {
            0  { [void]$sb.Append('\00'); break }
            40 { [void]$sb.Append('\28'); break }
            41 { [void]$sb.Append('\29'); break }
            42 { [void]$sb.Append('\2a'); break }
            92 { [void]$sb.Append('\5c'); break }
            default { [void]$sb.Append($ch); break }
        }
    }
    return $sb.ToString()
}

function Test-SamExists {
    param(
        [AllowNull()][string]$Sam,
        [string]$ExcludeDistinguishedName
    )
    if ([string]::IsNullOrWhiteSpace($Sam)) { return $false }
    $safe = Escape-LdapFilterValue -Value $Sam
    $server = Get-CurrentServerName
    if ([string]::IsNullOrWhiteSpace($server)) { throw 'Writable domain controller is not resolved.' }
    $found = @(Get-ADUser -LDAPFilter "(sAMAccountName=$safe)" -Server $server -Properties DistinguishedName -ErrorAction Stop)
    foreach ($u in $found) {
        if ([string]$u.DistinguishedName -ne [string]$ExcludeDistinguishedName) { return $true }
    }
    return $false
}

# =====================================================================================
# Mapping engine
# =====================================================================================
function Get-MappingColumnName {
    param(
        [Parameter(Mandatory)][string[]]$AvailableColumns,
        [Parameter(Mandatory)][string[]]$Aliases
    )
    foreach ($alias in $Aliases) {
        foreach ($col in $AvailableColumns) {
            if ($col.Trim().Equals($alias, [System.StringComparison]::OrdinalIgnoreCase)) { return $col }
        }
    }
    return $null
}

function Normalize-MappingLogin {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Trim().Trim([char]0xFEFF).Trim('"')
}

function Normalize-MappingCpf {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    return (([string]$Value).Trim().Trim([char]0xFEFF).Trim('"') -replace '\D','')
}

function Import-OldSamNewSamMapping {
    param([Parameter(Mandatory)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        throw 'Mapping file path is empty or invalid. Browse/select the mapping file before Load / Validate.'
    }

    $rows = @(Import-Csv -LiteralPath $Path -ErrorAction Stop)
    if ($rows.Count -eq 0) { throw 'Mapping file has no data rows.' }

    $availableColumns = @($rows[0].PSObject.Properties.Name)
    $oldColumn = Get-MappingColumnName -AvailableColumns $availableColumns -Aliases @('oldlogin','oldsamaccountname','matricula','oldsam','currentlogin','sourceLogin','source')
    $newColumn = Get-MappingColumnName -AvailableColumns $availableColumns -Aliases @('newlogin','newsamaccountname','cpf','newsam','targetlogin','destinationLogin','target')

    if ([string]::IsNullOrWhiteSpace($oldColumn) -or [string]::IsNullOrWhiteSpace($newColumn)) {
        throw 'Invalid mapping schema. Supported schemas include "oldlogin","newlogin", "oldsamaccountname","newsamaccountname", or "matricula","cpf".'
    }

    $script:MappingRows = @()
    $script:MappingTable = @{}
    $script:MappingReverseTable = @{}
    $script:MappingLookupAll = @{}
    $script:MappingReverseLookupAll = @{}

    $rowNumber = 1
    foreach ($r in $rows) {
        $rowNumber++
        $oldRaw = $r.PSObject.Properties[$oldColumn].Value
        $newRaw = $r.PSObject.Properties[$newColumn].Value
        $old = Normalize-MappingLogin -Value $oldRaw
        $new = Normalize-MappingLogin -Value $newRaw

        $item = [pscustomobject]@{
            RowNumber         = $rowNumber
            SourceOldColumn   = $oldColumn
            SourceNewColumn   = $newColumn
            OldSamAccountName = $old
            NewSamAccountName = $new
            Status            = 'READY'
            Message           = 'Ready.'
        }

        if ([string]::IsNullOrWhiteSpace($old)) {
            $item.Status = 'INVALID'; $item.Message = 'Old login value is empty.'
        } elseif ([string]::IsNullOrWhiteSpace($new)) {
            $item.Status = 'INVALID'; $item.Message = 'New login value is empty.'
        } elseif (-not (Test-ValidSamAccountName -Value $new)) {
            $item.Status = 'INVALID'; $item.Message = 'New login value is invalid for sAMAccountName or exceeds 20 characters.'
        } elseif ($script:chkCpfChecksum -and $script:chkCpfChecksum.Checked -and (-not (Test-CPFChecksum -CPF $new))) {
            $item.Status = 'INVALID'; $item.Message = 'New login value failed the optional Brazil CPF checksum validation.'
        }
        $script:MappingRows += $item
    }

    $validForDup = @($script:MappingRows | Where-Object { $_.Status -eq 'READY' })
    $dupsOld = @($validForDup | Where-Object { $_.OldSamAccountName } | Group-Object OldSamAccountName | Where-Object { $_.Count -gt 1 })
    $dupsNew = @($validForDup | Where-Object { $_.NewSamAccountName } | Group-Object NewSamAccountName | Where-Object { $_.Count -gt 1 })
    $oldDupSet = @{}
    foreach ($g in $dupsOld) { $oldDupSet[$g.Name] = $true }
    $newDupSet = @{}
    foreach ($g in $dupsNew) { $newDupSet[$g.Name] = $true }

    foreach ($m in $script:MappingRows) {
        if ($m.Status -eq 'READY') {
            if ($oldDupSet.ContainsKey($m.OldSamAccountName)) {
                $m.Status = 'DUPLICATE'; $m.Message = 'Duplicate old login value in mapping file.'
            } elseif ($newDupSet.ContainsKey($m.NewSamAccountName)) {
                $m.Status = 'DUPLICATE'; $m.Message = 'Duplicate new login value in mapping file.'
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($m.OldSamAccountName)) {
            if (-not $script:MappingLookupAll.ContainsKey($m.OldSamAccountName)) { $script:MappingLookupAll[$m.OldSamAccountName] = New-Object System.Collections.ArrayList }
            [void]$script:MappingLookupAll[$m.OldSamAccountName].Add($m)
        }
        if (-not [string]::IsNullOrWhiteSpace($m.NewSamAccountName)) {
            if (-not $script:MappingReverseLookupAll.ContainsKey($m.NewSamAccountName)) { $script:MappingReverseLookupAll[$m.NewSamAccountName] = New-Object System.Collections.ArrayList }
            [void]$script:MappingReverseLookupAll[$m.NewSamAccountName].Add($m)
        }
    }

    foreach ($m in ($script:MappingRows | Where-Object { $_.Status -eq 'READY' })) {
        $script:MappingTable[$m.OldSamAccountName] = $m.NewSamAccountName
        $script:MappingReverseTable[$m.NewSamAccountName] = $m.OldSamAccountName
    }

    $script:Stats.MappingRows = $script:MappingRows.Count
    $script:Stats.MappingReady = $script:MappingTable.Count
    $script:Stats.MappingDuplicatesOld = $dupsOld.Count
    $script:Stats.MappingDuplicatesNew = $dupsNew.Count
    $script:Stats.MappingInvalid = @($script:MappingRows | Where-Object { $_.Status -ne 'READY' }).Count

    $report = Join-Path $script:ReportRoot "Mapping-Validation-$($script:RunStamp).csv"
    $script:MappingRows | Export-Csv -Path $report -NoTypeInformation -Encoding UTF8

    $script:lblMapStatus.Text = "Loaded: $($script:Stats.MappingReady) ready / $($script:Stats.MappingRows) rows"
    Write-AppLog "Mapping loaded. Schema=$oldColumn->$newColumn; Ready=$($script:Stats.MappingReady); Rows=$($script:Stats.MappingRows); InvalidOrBlocked=$($script:Stats.MappingInvalid). Report: $report" 'SUCCESS'
    Refresh-StatisticsView
    Update-StatusBar 'Mapping loaded.'
}

# =====================================================================================
# Preview / migration engine
# =====================================================================================
function Reset-PreviewState {
    [void]$script:PreviewItems.Clear()
    $script:Stats.UsersRead = 0
    $script:Stats.PreviewReady = 0
    $script:Stats.PreviewSkipped = 0
    $script:Stats.PreviewErrors = 0
    if ($script:grid -and -not $script:grid.IsDisposed) {
        $script:grid.DataSource = $null
        $script:grid.Rows.Clear()
        $script:grid.Columns.Clear()
    }
    Refresh-StatisticsView
    Update-StatusBar 'Preview cleared.'
}

function Initialize-PreviewGridColumns {
    if (-not $script:grid -or $script:grid.IsDisposed) { throw 'Preview grid is not initialized.' }

    $script:grid.DataSource = $null
    $script:grid.Rows.Clear()
    $script:grid.Columns.Clear()

    $colSelect = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $colSelect.Name = 'Select'
    $colSelect.HeaderText = 'Select'
    $colSelect.Width = 55
    [void]$script:grid.Columns.Add($colSelect)

    $columns = @(
        @{Name='Name'; Header='Name'; Width=230; Visible=$true},
        @{Name='OldSamAccountName'; Header='Current Login'; Width=120; Visible=$true},
        @{Name='NewSamAccountName'; Header='New Login'; Width=130; Visible=$true},
        @{Name='OldUserPrincipalName'; Header='Current UPN'; Width=180; Visible=$false},
        @{Name='NewUserPrincipalName'; Header='New UPN'; Width=180; Visible=$false},
        @{Name='Status'; Header='Status'; Width=90; Visible=$true},
        @{Name='Message'; Header='Message'; Width=360; Visible=$true},
        @{Name='DistinguishedName'; Header='DistinguishedName'; Width=500; Visible=$false},
        @{Name='Index'; Header='Index'; Width=50; Visible=$false}
    )

    foreach ($c in $columns) {
        $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $col.Name = $c.Name
        $col.HeaderText = $c.Header
        $col.Width = $c.Width
        $col.Visible = [bool]$c.Visible
        [void]$script:grid.Columns.Add($col)
    }

    if ($script:grid.Columns['Message']) {
        $script:grid.Columns['Message'].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
    }
}

function Refresh-PreviewGrid {
    if (-not $script:grid -or $script:grid.IsDisposed) { return }

    Initialize-PreviewGridColumns

    for ($idx = 0; $idx -lt $script:PreviewItems.Count; $idx++) {
        $i = $script:PreviewItems[$idx]
        if ($null -eq $i) { continue }

        $rowIndex = $script:grid.Rows.Add()
        $row = $script:grid.Rows[$rowIndex]
        $isReadyForSelection = (Test-PreviewItemReady -Item $i)
        if (-not $isReadyForSelection) { $i.Selected = $false }

        $row.Cells['Select'].Value = [bool]$i.Selected
        $row.Cells['Select'].ReadOnly = (-not $isReadyForSelection)
        if (-not $isReadyForSelection) {
            $row.Cells['Select'].Style.BackColor = [System.Drawing.Color]::Gainsboro
            $row.Cells['Select'].ToolTipText = 'Only READY/PARTIAL rows can be selected.'
        }
        else {
            $row.Cells['Select'].ToolTipText = 'Actionable row. This row can be selected for Apply.'
        }
        $row.Cells['Name'].Value = [string]$i.Name
        $row.Cells['OldSamAccountName'].Value = [string]$i.OldSamAccountName
        $row.Cells['NewSamAccountName'].Value = [string]$i.NewSamAccountName
        $row.Cells['OldUserPrincipalName'].Value = [string]$i.OldUserPrincipalName
        $row.Cells['NewUserPrincipalName'].Value = [string]$i.NewUserPrincipalName
        $row.Cells['Status'].Value = [string]$i.Status
        $row.Cells['Message'].Value = [string]$i.Message
        $row.Cells['DistinguishedName'].Value = [string]$i.DistinguishedName
        $row.Cells['Index'].Value = [string]$idx

        switch ([string]$i.Status) {
            'READY'     { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::Honeydew }
            'PARTIAL'   { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightCyan }
            'ALIGNED'   { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::MistyRose }
            'NOTFOUND'  { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightYellow }
            'SKIPPED'   { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightYellow }
            'MIGRATED'  { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::Gainsboro }
            'DUPLICATE' { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::Moccasin }
            'CONFLICT'  { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::MistyRose }
            'INVALID'   { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::MistyRose }
            default     { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::MistyRose }
        }
    }

    Refresh-StatisticsView
    Update-StatusBar 'Preview refreshed.'
}

function Sync-GridSelection {
    if (-not $script:grid -or $script:grid.IsDisposed) { return }
    if ($null -eq $script:PreviewItems) { return }
    if ($script:grid.Columns.Count -eq 0) { return }
    if (-not $script:grid.Columns['Select'] -or -not $script:grid.Columns['Index']) { return }

    $blocked = 0

    foreach ($row in $script:grid.Rows) {
        if ($row.IsNewRow) { continue }
        $idxText = [string]$row.Cells['Index'].Value
        $idx = 0
        if ([int]::TryParse($idxText, [ref]$idx)) {
            if ($idx -ge 0 -and $idx -lt $script:PreviewItems.Count) {
                $item = $script:PreviewItems[$idx]
                if ($null -ne $item) {
                    $isReadyForSelection = (Test-PreviewItemReady -Item $item)
                    $requestedSelection = [bool]$row.Cells['Select'].Value

                    if ($requestedSelection -and -not $isReadyForSelection) {
                        $item.Selected = $false
                        $row.Cells['Select'].Value = $false
                        $row.Cells['Select'].ReadOnly = $true
                        $row.Cells['Select'].Style.BackColor = [System.Drawing.Color]::Gainsboro
                        $row.Cells['Select'].ToolTipText = 'Only READY/PARTIAL rows can be selected.'
                        $blocked++
                    }
                    else {
                        $item.Selected = ($requestedSelection -and $isReadyForSelection)
                    }
                }
            }
        }
    }

    if ($blocked -gt 0) {
        Write-AppLog "Blocked manual selection for $blocked non-actionable row(s). Only READY/PARTIAL rows can be applied." 'INFO'
        Update-StatusBar 'Only READY/PARTIAL rows can be selected.'
    }
}

function Test-PreviewItemActionable {
    param([object]$Item)

    if ($null -eq $Item) { return $false }

    $status = ([string]$Item.Status).Trim().ToUpperInvariant()
    if (@('READY','PARTIAL') -notcontains $status) { return $false }

    if (-not [bool]$Item.CanApply) { return $false }
    if ([string]::IsNullOrWhiteSpace([string]$Item.NewSamAccountName)) { return $false }
    if ([string]::IsNullOrWhiteSpace([string]$Item.DistinguishedName)) { return $false }

    return $true
}

function Test-PreviewItemReady {
    param([object]$Item)
    return (Test-PreviewItemActionable -Item $Item)
}

function Select-ReadyRows {
    if ($null -eq $script:PreviewItems -or $script:PreviewItems.Count -eq 0) {
        throw 'No preview data. Run Preview first.'
    }
    if (-not $script:grid -or $script:grid.IsDisposed) {
        throw 'Preview grid is not initialized.'
    }

    $selectedReady = 0
    $totalReady = 0

    for ($idx = 0; $idx -lt $script:PreviewItems.Count; $idx++) {
        $item = $script:PreviewItems[$idx]
        $isReady = Test-PreviewItemReady -Item $item
        if ($isReady) {
            $totalReady++
            $item.Selected = $true
            $selectedReady++
        }
        elseif ($null -ne $item) {
            $item.Selected = $false
        }
    }

    if ($script:grid.Columns.Count -gt 0 -and $script:grid.Columns['Select'] -and $script:grid.Columns['Index']) {
        foreach ($row in $script:grid.Rows) {
            if ($row.IsNewRow) { continue }
            $idxText = [string]$row.Cells['Index'].Value
            $rowIdx = 0
            if ([int]::TryParse($idxText, [ref]$rowIdx)) {
                if ($rowIdx -ge 0 -and $rowIdx -lt $script:PreviewItems.Count) {
                    $item = $script:PreviewItems[$rowIdx]
                    $isReady = Test-PreviewItemReady -Item $item
                    $row.Cells['Select'].ReadOnly = (-not $isReady)
                    $row.Cells['Select'].Value = [bool]$isReady
                    if ($isReady) {
                        $row.Cells['Select'].Style.BackColor = [System.Drawing.Color]::White
                        $row.Cells['Select'].ToolTipText = 'Actionable row selected for Apply.'
                    }
                    else {
                        $row.Cells['Select'].Style.BackColor = [System.Drawing.Color]::Gainsboro
                        $row.Cells['Select'].ToolTipText = 'Only READY/PARTIAL rows can be selected.'
                    }
                }
            }
        }
        $script:grid.Refresh()
    }

    Refresh-StatisticsView
    Write-AppLog "Actionable rows selected: $selectedReady of $totalReady." 'INFO'
    Update-StatusBar "Actionable rows selected: $selectedReady."

    if ($selectedReady -eq 0) {
        Show-AppMessage 'No READY/PARTIAL rows exist in the current preview. Review the Status and Message columns.' 'Select READY' ([System.Windows.Forms.MessageBoxIcon]::Information)
    }
}

function Get-SelectedReadyTargets {
    Sync-GridSelection
    $targets = @($script:PreviewItems | Where-Object { $_ -and $_.Selected -and (Test-PreviewItemReady -Item $_) })
    return $targets
}

function Add-PreviewItem {
    param(
        [bool]$Selected,
        [bool]$CanApply,
        [string]$Domain,
        [string]$DC,
        [AllowNull()]$User,
        [string]$OldSamAccountName,
        [string]$NewSamAccountName,
        [string]$OldUserPrincipalName,
        [string]$NewUserPrincipalName,
        [string]$Status,
        [string]$Message
    )

    $name = ''
    $display = ''
    $enabled = $false
    $dn = ''
    $guid = ''
    $sid = ''
    $userPrincipalName = ''

    if ($null -ne $User) {
        $name = [string]$User.Name
        $display = [string]$User.DisplayName
        $enabled = [bool]$User.Enabled
        $dn = [string]$User.DistinguishedName
        $guid = [string]$User.ObjectGUID
        $sid = [string]$User.SID
        $userPrincipalName = [string]$User.UserPrincipalName
    }

    [void]$script:PreviewItems.Add([pscustomobject]@{
        Selected = $Selected
        CanApply = $CanApply
        Domain = $Domain
        DC = $DC
        Name = $name
        DisplayName = $display
        Enabled = $enabled
        OldSamAccountName = $OldSamAccountName
        NewSamAccountName = $NewSamAccountName
        OldUserPrincipalName = $(if ([string]::IsNullOrWhiteSpace($OldUserPrincipalName)) { $userPrincipalName } else { $OldUserPrincipalName })
        NewUserPrincipalName = $NewUserPrincipalName
        Status = $Status
        Message = $Message
        DistinguishedName = $dn
        ObjectGUID = $guid
        SID = $sid
    })
}


function Get-NewUserPrincipalName {
    <#
    .SYNOPSIS
      Builds the new UPN preserving the user's CURRENT UPN suffix.

    .DESCRIPTION
      This function intentionally replaces ONLY the UPN left side with the new target login/NewSamAccountName.
      It preserves the suffix that already exists in AD for the user. This is required because the
      forest contains multiple domains and possibly multiple configured UPN suffixes.

      Example:
        Current UPN : oldlogin@example.com
        New SAM     : newlogin
        New UPN     : newlogin@example.com

      The function must NOT derive the suffix from the selected domain when the current UPN already
      contains an '@' suffix.
    #>
    param(
        [AllowNull()]$User,
        [Parameter(Mandatory)][string]$NewSamAccountName,
        [string]$CurrentUserPrincipalName,
        [string]$Domain
    )

    $newLeft = ([string]$NewSamAccountName).Trim()
    if ([string]::IsNullOrWhiteSpace($newLeft)) { return '' }

    $currentUpn = ''
    if (-not [string]::IsNullOrWhiteSpace($CurrentUserPrincipalName)) {
        $currentUpn = ([string]$CurrentUserPrincipalName).Trim()
    }
    elseif ($null -ne $User) {
        $currentUpn = ([string]$User.UserPrincipalName).Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($currentUpn) -and $currentUpn.Contains('@')) {
        $suffix = $currentUpn.Substring($currentUpn.IndexOf('@') + 1).Trim()
        if (-not [string]::IsNullOrWhiteSpace($suffix)) {
            return ("{0}@{1}" -f $newLeft, $suffix)
        }
    }

    # If the account currently has no UPN suffix, there is no suffix to preserve.
    # In that case, keep the UPN left-side only instead of inventing a suffix from the selected domain.
    # This prevents accidental cross-suffix normalization during migration.
    return $newLeft
}


function Test-StringEqualsCI {
    param(
        [AllowNull()][string]$A,
        [AllowNull()][string]$B
    )
    return ([string]$A).Trim().Equals(([string]$B).Trim(), [System.StringComparison]::OrdinalIgnoreCase)
}

function Resolve-SamMappingState {
    <#
    .SYNOPSIS
      Resolves the desired target login for the current AD sAMAccountName in an idempotent way.

    .DESCRIPTION
      Supports both pre-migration and post-migration states:
      - Current sAMAccountName equals OldSamAccountName: target is NewSamAccountName.
      - Current sAMAccountName already equals NewSamAccountName: target is itself and the row can still
        be evaluated for UPN alignment.
      - Duplicate/invalid mapping rows are returned as blocked states instead of false NOTFOUND.
    #>
    param([Parameter(Mandatory)][string]$CurrentSam)

    $sam = (Normalize-MappingLogin -Value $CurrentSam)
    if ([string]::IsNullOrWhiteSpace($sam)) { return $null }

    if ($script:MappingTable -and $script:MappingTable.ContainsKey($sam)) {
        return [pscustomobject]@{
            Found = $true
            CurrentMatched = 'OldSamAccountName'
            MappingStatus = 'READY'
            MappingMessage = 'Ready.'
            OriginalOldSamAccountName = $sam
            TargetSamAccountName = ([string]$script:MappingTable[$sam]).Trim()
        }
    }

    if ($script:MappingReverseTable -and $script:MappingReverseTable.ContainsKey($sam)) {
        return [pscustomobject]@{
            Found = $true
            CurrentMatched = 'NewSamAccountName'
            MappingStatus = 'READY'
            MappingMessage = 'Ready.'
            OriginalOldSamAccountName = ([string]$script:MappingReverseTable[$sam]).Trim()
            TargetSamAccountName = $sam
        }
    }

    if ($script:MappingLookupAll -and $script:MappingLookupAll.ContainsKey($sam)) {
        $matches = @($script:MappingLookupAll[$sam])
        $first = $matches[0]
        return [pscustomobject]@{
            Found = $true
            CurrentMatched = 'OldSamAccountName'
            MappingStatus = ([string]$first.Status)
            MappingMessage = ([string]$first.Message)
            OriginalOldSamAccountName = $sam
            TargetSamAccountName = ([string]$first.NewSamAccountName).Trim()
        }
    }

    if ($script:MappingReverseLookupAll -and $script:MappingReverseLookupAll.ContainsKey($sam)) {
        $matches = @($script:MappingReverseLookupAll[$sam])
        $first = $matches[0]
        return [pscustomobject]@{
            Found = $true
            CurrentMatched = 'NewSamAccountName'
            MappingStatus = ([string]$first.Status)
            MappingMessage = ([string]$first.Message)
            OriginalOldSamAccountName = ([string]$first.OldSamAccountName).Trim()
            TargetSamAccountName = $sam
        }
    }

    return [pscustomobject]@{
        Found = $false
        CurrentMatched = 'None'
        MappingStatus = 'NOTFOUND'
        MappingMessage = 'Current sAMAccountName not found as old login or new login in mapping file.'
        OriginalOldSamAccountName = ''
        TargetSamAccountName = ''
    }
}

function Test-UpnAlignedToSamPreservingSuffix {
    param(
        [Parameter(Mandatory)][string]$CurrentUPN,
        [Parameter(Mandatory)][string]$TargetSam
    )
    $desired = Get-NewUserPrincipalName -User $null -NewSamAccountName $TargetSam -CurrentUserPrincipalName $CurrentUPN -Domain ''
    return (Test-StringEqualsCI -A $CurrentUPN -B $desired)
}


function Test-CurrentSamCanBeUsedAsCpfTarget {
    <#
    .SYNOPSIS
      Allows optional Brazil CPF-only idempotent UPN alignment when the current sAMAccountName is already a CPF-like target.

    .DESCRIPTION
      Some users may already have sAMAccountName changed while userPrincipalName still has
      the old logon name on the left side. In that state, the current sAMAccountName may no longer
      be present as OldSamAccountName in the mapping file. This helper permits the Preview engine
      to use the current sAMAccountName itself as the target, but only when optional Brazil CPF validation is enabled and it is an 11-digit CPF-like
      value and, when enabled in the GUI, it passes CPF checksum validation.
    #>
    param([AllowNull()][string]$Sam)

    $value = ([string]$Sam).Trim()
    if ($value -notmatch '^\d{11}$') { return $false }
    if ($script:chkCpfChecksum -and $script:chkCpfChecksum.Checked) {
        return (Test-CPFChecksum -CPF $value)
    }
    return $true
}

function Test-UserPrincipalNameExistsOnServer {
    param(
        [Parameter(Mandatory)][string]$UserPrincipalName,
        [Parameter(Mandatory)][string]$Server,
        [string]$ExcludeDistinguishedName
    )

    if ([string]::IsNullOrWhiteSpace($UserPrincipalName)) { return $false }
    if ([string]::IsNullOrWhiteSpace($Server)) { throw 'Writable domain controller is not resolved.' }

    $safe = Escape-LdapFilterValue -Value $UserPrincipalName
    $found = @(Get-ADUser -LDAPFilter "(userPrincipalName=$safe)" -Server $Server -Properties DistinguishedName -ErrorAction Stop)
    foreach ($u in $found) {
        if ([string]$u.DistinguishedName -ne [string]$ExcludeDistinguishedName) { return $true }
    }
    return $false
}

function Test-SamExistsOnServer {
    param(
        [Parameter(Mandatory)][string]$Sam,
        [Parameter(Mandatory)][string]$Server,
        [string]$ExcludeDistinguishedName
    )

    if ([string]::IsNullOrWhiteSpace($Sam)) { return $false }
    if ([string]::IsNullOrWhiteSpace($Server)) { throw 'Writable domain controller is not resolved.' }

    $safe = Escape-LdapFilterValue -Value $Sam
    $found = @(Get-ADUser -LDAPFilter "(sAMAccountName=$safe)" -Server $Server -Properties DistinguishedName -ErrorAction Stop)
    foreach ($u in $found) {
        if ([string]$u.DistinguishedName -ne [string]$ExcludeDistinguishedName) { return $true }
    }
    return $false
}

function Build-MigrationPreview {
    Reset-PreviewState

    if ($null -eq $script:MappingRows -or $script:MappingRows.Count -eq 0) { throw 'Load and validate the mapping file before preview.' }
    if (-not $script:cmbDomain) { throw 'Domain selector is not initialized.' }
    if (-not $script:txtSearchBase) { throw 'SearchBase control is not initialized.' }

    $domain = [string]$script:cmbDomain.Text
    if ([string]::IsNullOrWhiteSpace($domain)) { throw 'Select a domain first.' }

    $server = Convert-ToSingleString (Get-CurrentServerName)
    if ([string]::IsNullOrWhiteSpace($server)) { $server = Convert-ToSingleString (Resolve-WritableDC -Domain $domain) }
    if ([string]::IsNullOrWhiteSpace($server)) { throw 'Could not resolve a writable domain controller.' }

    $searchBase = [string]$script:txtSearchBase.Text
    if ([string]::IsNullOrWhiteSpace($searchBase)) {
        $searchBase = Get-DomainDN -Domain $domain
        $script:txtSearchBase.Text = $searchBase
    }

    $enabledFilter = if ($script:chkIncludeDisabled -and $script:chkIncludeDisabled.Checked) { '*' } else { 'Enabled -eq $true' }

    Write-AppLog "Querying AD users. Domain=$domain; DC=$server; SearchBase=$searchBase; IncludeDisabled=$($script:chkIncludeDisabled.Checked)" 'INFO'
    Update-StatusBar 'Querying AD users...'

    try {
        $users = @(Get-ADUser -Filter $enabledFilter -SearchBase $searchBase -SearchScope Subtree -Server $server -Properties DisplayName,Enabled,ObjectGUID,SID,UserPrincipalName -ErrorAction Stop)
    } catch {
        Write-AppLog "AD query failed. Domain=$domain; DC=$server; SearchBase=$searchBase; Error=$($_.Exception.Message)" 'ERROR'
        throw
    }

    $script:Stats.UsersRead = $users.Count
    $script:Stats.PreviewReady = 0
    $script:Stats.PreviewSkipped = 0
    $script:Stats.PreviewErrors = 0

    foreach ($u in $users) {
        $old = ''
        $new = ''
        $oldUpn = ''
        $newUpn = ''
        $status = 'NOTFOUND'
        $message = 'Current sAMAccountName not found in mapping file.'
        $canApply = $false

        try {
            if ($null -eq $u) { throw 'Null AD user object returned by query.' }

            $old = (Normalize-MappingLogin -Value $u.SamAccountName)
            $oldUpn = ([string]$u.UserPrincipalName).Trim()
            if ([string]::IsNullOrWhiteSpace($old)) {
                $status = 'ERROR'
                $message = 'AD user has empty sAMAccountName.'
            }
            else {
                $mapState = Resolve-SamMappingState -CurrentSam $old
                if ($null -eq $mapState -or -not $mapState.Found) {
                    if (Test-CurrentSamCanBeUsedAsCpfTarget -Sam $old) {
                        # Idempotent fallback: current sAMAccountName is already a CPF-like target, but mapping file has no row for it.
                        $new = $old
                        $newUpn = Get-NewUserPrincipalName -User $u -NewSamAccountName $new -CurrentUserPrincipalName $oldUpn -Domain $domain
                        $upnAligned = (Test-StringEqualsCI -A $oldUpn -B $newUpn)

                        if ([string]::IsNullOrWhiteSpace($newUpn)) {
                            $status = 'ERROR'; $message = 'Target userPrincipalName could not be generated from current target-like sAMAccountName.'
                        } elseif (-not $upnAligned -and (Test-UserPrincipalNameExistsOnServer -UserPrincipalName $newUpn -Server $server -ExcludeDistinguishedName ([string]$u.DistinguishedName))) {
                            $status = 'CONFLICT'; $message = 'Target userPrincipalName already exists in AD.'
                        } elseif ($upnAligned) {
                            $status = 'ALIGNED'; $message = 'sAMAccountName and userPrincipalName are already aligned with the target login.'; $canApply = $false
                        } else {
                            $status = 'PARTIAL'
                            $message = 'sAMAccountName already uses the target login; userPrincipalName needs left-side alignment with preserved suffix.'
                            $canApply = $true
                        }
                    }
                    else {
                        $status = 'NOTFOUND'
                        $message = 'Current sAMAccountName not found as old login or new login in mapping file.'
                    }
                }
                elseif ([string]$mapState.MappingStatus -ne 'READY') {
                    $new = ([string]$mapState.TargetSamAccountName).Trim()
                    $blockedStatus = ([string]$mapState.MappingStatus).Trim().ToUpperInvariant()
                    if ($blockedStatus -eq 'INVALID') { $status = 'INVALID' }
                    elseif ($blockedStatus -eq 'DUPLICATE') { $status = 'DUPLICATE' }
                    else { $status = 'ERROR' }
                    $message = ([string]$mapState.MappingMessage)
                    $canApply = $false
                }
                else {
                    $new = ([string]$mapState.TargetSamAccountName).Trim()
                    if ([string]::IsNullOrWhiteSpace($new)) {
                        $status = 'ERROR'; $message = 'Mapping target New login value is empty.'
                    } elseif (-not (Test-ValidSamAccountName -Value $new)) {
                        $status = 'INVALID'; $message = 'Target sAMAccountName/new login value is invalid or exceeds 20 characters.'
                    } else {
                        $newUpn = Get-NewUserPrincipalName -User $u -NewSamAccountName $new -CurrentUserPrincipalName $oldUpn -Domain $domain
                        $samAligned = (Test-StringEqualsCI -A $old -B $new)
                        $upnAligned = (Test-StringEqualsCI -A $oldUpn -B $newUpn)

                        if (-not $samAligned -and (Test-SamExistsOnServer -Sam $new -Server $server -ExcludeDistinguishedName ([string]$u.DistinguishedName))) {
                            $status = 'CONFLICT'; $message = 'Target sAMAccountName already exists in AD.'
                        } elseif ([string]::IsNullOrWhiteSpace($newUpn)) {
                            $status = 'ERROR'; $message = 'Target userPrincipalName could not be generated.'
                        } elseif (-not $upnAligned -and (Test-UserPrincipalNameExistsOnServer -UserPrincipalName $newUpn -Server $server -ExcludeDistinguishedName ([string]$u.DistinguishedName))) {
                            $status = 'CONFLICT'; $message = 'Target userPrincipalName already exists in AD.'
                        } elseif ($samAligned -and $upnAligned) {
                            $status = 'ALIGNED'; $message = 'sAMAccountName and userPrincipalName are already aligned with the target login.'; $canApply = $false
                        } elseif ($samAligned -or $upnAligned) {
                            $status = 'PARTIAL'
                            if ($samAligned -and -not $upnAligned) {
                                $message = 'sAMAccountName already uses the target login; userPrincipalName needs left-side alignment with preserved suffix.'
                            } else {
                                $message = 'userPrincipalName already uses the target login with preserved suffix; sAMAccountName needs alignment.'
                            }
                            $canApply = $true
                        } else {
                            $status = 'READY'
                            $message = 'Ready to align sAMAccountName and userPrincipalName.'
                            $canApply = $true
                        }
                    }
                }
            }
        } catch {
            $status = 'ERROR'
            $message = "Preview validation error: $($_.Exception.Message)"
            Write-AppLog "Preview row error. UserDN=$([string]$u.DistinguishedName); OldSam=$old; Error=$($_.Exception.Message)" 'ERROR'
        }

        if (@('READY','PARTIAL') -contains $status) { $script:Stats.PreviewReady++ }
        elseif (@('ERROR','CONFLICT','DUPLICATE','INVALID') -contains $status) { $script:Stats.PreviewErrors++ }
        else { $script:Stats.PreviewSkipped++ }

        Add-PreviewItem -Selected:$canApply -CanApply:$canApply -Domain $domain -DC $server -User $u -OldSamAccountName $old -NewSamAccountName $new -OldUserPrincipalName $oldUpn -NewUserPrincipalName $newUpn -Status $status -Message $message
    }

    Refresh-PreviewGrid

    $previewReport = Join-Path $script:ReportRoot "Preview-$($script:RunStamp).csv"
    $script:PreviewItems | Export-Csv -Path $previewReport -NoTypeInformation -Encoding UTF8
    Write-AppLog "Preview completed. Users=$($script:Stats.UsersRead); Actionable=$($script:Stats.PreviewReady); Skipped=$($script:Stats.PreviewSkipped); Errors=$($script:Stats.PreviewErrors). Report: $previewReport" 'SUCCESS'
    Update-StatusBar 'Preview completed.'
}

function Show-ApplyModeDialog {
    param([Parameter(Mandatory)][int]$TargetCount)

    if ($WhatIfPreference) { return 'DryRun' }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Apply Migration Mode'
    $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dlg.Size = New-Object System.Drawing.Size(520,260)
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = [System.Windows.Forms.DockStyle]::Fill
    $layout.ColumnCount = 1
    $layout.RowCount = 4
    $layout.Padding = New-Object System.Windows.Forms.Padding(14)
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,55)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,42)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,42)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
    $dlg.Controls.Add($layout)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Selected READY users: $TargetCount`r`nChoose how the Apply operation will run."
    $lbl.Dock = [System.Windows.Forms.DockStyle]::Fill
    $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $layout.Controls.Add($lbl,0,0)

    $rbDry = New-Object System.Windows.Forms.RadioButton
    $rbDry.Text = 'Simulation only (Dry Run) - no AD changes'
    $rbDry.Dock = [System.Windows.Forms.DockStyle]::Fill
    $rbDry.Checked = $true
    if ($script:chkDryRun -and (-not $script:chkDryRun.Checked)) { $rbDry.Checked = $false }
    $layout.Controls.Add($rbDry,0,1)

    $rbCommit = New-Object System.Windows.Forms.RadioButton
    $rbCommit.Text = 'Commit changes to Active Directory'
    $rbCommit.Dock = [System.Windows.Forms.DockStyle]::Fill
    if ($script:chkDryRun -and (-not $script:chkDryRun.Checked)) { $rbCommit.Checked = $true }
    $layout.Controls.Add($rbCommit,0,2)

    $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttons.Dock = [System.Windows.Forms.DockStyle]::Fill
    $buttons.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
    $buttons.Padding = New-Object System.Windows.Forms.Padding(0,12,0,0)
    $layout.Controls.Add($buttons,0,3)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = 'OK'
    $btnOk.Width = 110
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $buttons.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Cancel'
    $btnCancel.Width = 110
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $buttons.Controls.Add($btnCancel)

    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel

    $result = $dlg.ShowDialog($script:form)
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return 'Cancel' }
    if ($rbCommit.Checked) { return 'Commit' }
    return 'DryRun'
}

function Invoke-SamMigration {
    if ($script:PreviewItems.Count -eq 0) { throw 'No preview data. Run Preview before Apply.' }
    Sync-GridSelection
    $targets = @(Get-SelectedReadyTargets)
    if ($targets.Count -eq 0) { throw 'No READY/PARTIAL rows selected. Use Select Actionable or manually check actionable rows in the preview grid.' }

    $mode = Show-ApplyModeDialog -TargetCount $targets.Count
    if ($mode -eq 'Cancel') { return }

    if ($mode -eq 'DryRun') {
        foreach ($t in $targets) { Write-AppLog "DRYRUN: would align sAMAccountName $($t.OldSamAccountName) -> $($t.NewSamAccountName); UPN $($t.OldUserPrincipalName) -> $($t.NewUserPrincipalName) [$($t.DistinguishedName)]" 'INFO' }
        $dryRunReport = Join-Path $script:ReportRoot "DryRun-$($script:RunStamp).csv"
        $targets | Export-Csv -Path $dryRunReport -NoTypeInformation -Encoding UTF8
        Show-AppMessage "Dry Run completed. No AD changes were made.`r`nTargets evaluated: $($targets.Count)`r`nReport: $dryRunReport" 'Dry Run' ([System.Windows.Forms.MessageBoxIcon]::Information)
        Write-AppLog "Dry Run completed. Targets=$($targets.Count). Report: $dryRunReport" 'SUCCESS'
        return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show($script:form, "FINAL CONFIRMATION`r`n`r`nThis will align sAMAccountName and userPrincipalName for $($targets.Count) selected AD users. The current AD UPN suffix will be preserved per user. Already-aligned users will be skipped safely.`r`n`r`nContinue and commit to Active Directory?", 'Confirm AD Migration Commit', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $success = @()
    $failed = @()
    foreach ($t in $targets) {
        try {
            if ($null -eq $t) { continue }
            if ([string]::IsNullOrWhiteSpace([string]$t.DistinguishedName)) { throw 'Target DistinguishedName is empty.' }
            if ([string]::IsNullOrWhiteSpace([string]$t.DC)) { throw 'Target DC is empty.' }
            if ([string]::IsNullOrWhiteSpace([string]$t.NewSamAccountName)) { throw 'Target NewSamAccountName is empty.' }

            # Re-read the user immediately before writing. This makes the operation idempotent and
            # prevents stale preview data from forcing unnecessary updates.
            $currentUser = Get-ADUser -Identity $t.DistinguishedName -Server $t.DC -Properties SamAccountName,UserPrincipalName,DistinguishedName -ErrorAction Stop
            $currentSam = ([string]$currentUser.SamAccountName).Trim()
            $currentUPN = ([string]$currentUser.UserPrincipalName).Trim()

            $desiredSam = ([string]$t.NewSamAccountName).Trim()
            $desiredUPN = Get-NewUserPrincipalName -User $currentUser -NewSamAccountName $desiredSam -CurrentUserPrincipalName $currentUPN -Domain $t.Domain
            if ([string]::IsNullOrWhiteSpace([string]$desiredUPN)) { throw 'Target NewUserPrincipalName is empty.' }

            $samNeedsUpdate = -not (Test-StringEqualsCI -A $currentSam -B $desiredSam)
            $upnNeedsUpdate = -not (Test-StringEqualsCI -A $currentUPN -B $desiredUPN)

            if (-not $samNeedsUpdate -and -not $upnNeedsUpdate) {
                $t.Status = 'ALIGNED'; $t.Message = 'No change required; sAMAccountName and userPrincipalName are already aligned.'; $t.Selected = $false; $t.CanApply = $false
                $success += $t
                Write-AppLog "IDEMPOTENT NO-OP: already aligned sAMAccountName=$currentSam; UPN=$currentUPN [$($t.DistinguishedName)]" 'SUCCESS'
                continue
            }

            $action = "Align sAMAccountName '$currentSam' to '$desiredSam' and userPrincipalName '$currentUPN' to '$desiredUPN'"
            if ($PSCmdlet.ShouldProcess($t.DistinguishedName, $action)) {
                Set-ADUser -Identity $t.DistinguishedName -SamAccountName $desiredSam -UserPrincipalName $desiredUPN -Server $t.DC -ErrorAction Stop
                $script:UndoStack.Push([pscustomobject]@{ DistinguishedName=$t.DistinguishedName; OldSam=$currentSam; NewSam=$desiredSam; OldUPN=$currentUPN; NewUPN=$desiredUPN; DC=$t.DC })
                $t.OldSamAccountName = $currentSam
                $t.NewSamAccountName = $desiredSam
                $t.OldUserPrincipalName = $currentUPN
                $t.NewUserPrincipalName = $desiredUPN
                $t.Status = 'MIGRATED'; $t.Message = 'sAMAccountName and userPrincipalName aligned successfully.'; $t.Selected = $false; $t.CanApply = $false
                $script:Stats.Updated++
                $success += $t
                Write-AppLog "SUCCESS: sAMAccountName $currentSam -> $desiredSam; UPN $currentUPN -> $desiredUPN [$($t.DistinguishedName)]" 'SUCCESS'
            } else {
                Write-AppLog "WHATIF: would align sAMAccountName $currentSam -> $desiredSam; UPN $currentUPN -> $desiredUPN [$($t.DistinguishedName)]" 'INFO'
            }
        } catch {
            if ($null -ne $t) {
                $t.Status = 'ERROR'; $t.Message = $_.Exception.Message
                $failed += $t
                Write-AppLog "FAILED: $($t.OldSamAccountName) -> $($t.NewSamAccountName): $($_.Exception.Message)" 'ERROR'
            } else {
                Write-AppLog "FAILED: null target object: $($_.Exception.Message)" 'ERROR'
            }
            $script:Stats.Failed++
        }
    }

    if ($success.Count -gt 0) { $success | Export-Csv -Path (Join-Path $script:ReportRoot "Migration-Success-$($script:RunStamp).csv") -NoTypeInformation -Encoding UTF8 }
    if ($failed.Count -gt 0)  { $failed  | Export-Csv -Path (Join-Path $script:ReportRoot "Migration-Failed-$($script:RunStamp).csv")  -NoTypeInformation -Encoding UTF8 }
    if ($script:UndoStack.Count -gt 0) { $script:UndoStack.ToArray() | Export-Csv -Path (Join-Path $script:ReportRoot "Rollback-$($script:RunStamp).csv") -NoTypeInformation -Encoding UTF8 }

    Refresh-PreviewGrid
    Refresh-StatisticsView
    Show-AppMessage "Migration finished.`r`nUpdated: $($success.Count)`r`nFailed: $($failed.Count)" 'Migration Complete'
}

function Undo-LastSamMigration {
    if ($script:UndoStack.Count -eq 0) { throw 'Undo stack is empty.' }
    $item = $script:UndoStack.Peek()

    if ($WhatIfPreference) {
        Write-AppLog "WHATIF: would rollback $($item.NewSam) -> $($item.OldSam) [$($item.DistinguishedName)]" 'INFO'
        return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show($script:form, "Rollback last change?`r`n`r`n$($item.NewSam) -> $($item.OldSam)`r`n$($item.DistinguishedName)", 'Confirm Undo', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $item = $script:UndoStack.Pop()
    if ($PSCmdlet.ShouldProcess($item.DistinguishedName, "Rollback sAMAccountName '$($item.NewSam)' to '$($item.OldSam)'")) {
        Set-ADUser -Identity $item.DistinguishedName -SamAccountName $item.OldSam -UserPrincipalName $item.OldUPN -Server $item.DC -ErrorAction Stop
        Write-AppLog "UNDO SUCCESS: sAMAccountName $($item.NewSam) -> $($item.OldSam); UPN $($item.NewUPN) -> $($item.OldUPN) [$($item.DistinguishedName)]" 'SUCCESS'
        Show-AppMessage "Undo completed for:`r`n$($item.NewSam) -> $($item.OldSam)" 'Undo Complete'
    }
}

# =====================================================================================
# OU browser
# =====================================================================================
function Show-OUBrowserDialog {
    param([Parameter(Mandatory)][string]$Domain)
    $ous = Get-OUList -Domain $Domain

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Search / Browse OU'
    $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dlg.Size = New-Object System.Drawing.Size(900,600)
    $dlg.MinimumSize = New-Object System.Drawing.Size(700,450)

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = [System.Windows.Forms.DockStyle]::Fill
    $layout.RowCount = 3
    $layout.ColumnCount = 1
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 38)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 45)))
    $dlg.Controls.Add($layout)

    $txtFilter = New-Object System.Windows.Forms.TextBox
    $txtFilter.Dock = [System.Windows.Forms.DockStyle]::Fill
    $txtFilter.Margin = New-Object System.Windows.Forms.Padding(8)
    $layout.Controls.Add($txtFilter,0,0)

    $gridOU = New-Object System.Windows.Forms.DataGridView
    $gridOU.Dock = [System.Windows.Forms.DockStyle]::Fill
    $gridOU.ReadOnly = $true
    $gridOU.AllowUserToAddRows = $false
    $gridOU.AllowUserToDeleteRows = $false
    $gridOU.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $gridOU.MultiSelect = $false
    $gridOU.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $layout.Controls.Add($gridOU,0,1)

    $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttons.Dock = [System.Windows.Forms.DockStyle]::Fill
    $buttons.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
    $buttons.Padding = New-Object System.Windows.Forms.Padding(6)
    $layout.Controls.Add($buttons,0,2)

    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text = 'Select OU'
    $btnOK.Width = 110
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Cancel'
    $btnCancel.Width = 90
    [void]$buttons.Controls.Add($btnOK)
    [void]$buttons.Controls.Add($btnCancel)

    function Set-OuGridData([object[]]$Items) {
        $dt = New-Object System.Data.DataTable
        [void]$dt.Columns.Add('Name',[string])
        [void]$dt.Columns.Add('DistinguishedName',[string])
        foreach ($ou in $Items) { $r=$dt.NewRow(); $r['Name']=$ou.Name; $r['DistinguishedName']=$ou.DistinguishedName; [void]$dt.Rows.Add($r) }
        $gridOU.DataSource = $dt
    }
    Set-OuGridData $ous

    $txtFilter.Add_TextChanged({
        $f = $txtFilter.Text
        if ([string]::IsNullOrWhiteSpace($f)) { Set-OuGridData $ous }
        else { Set-OuGridData @($ous | Where-Object { $_.Name -like "*$f*" -or $_.DistinguishedName -like "*$f*" }) }
    })

    $script:selectedOU = $null
    $selectAction = {
        if ($gridOU.SelectedRows.Count -gt 0) {
            $script:selectedOU = [string]$gridOU.SelectedRows[0].Cells['DistinguishedName'].Value
            $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dlg.Close()
        }
    }
    $btnOK.Add_Click($selectAction)
    $gridOU.Add_CellDoubleClick($selectAction)
    $btnCancel.Add_Click({ $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $dlg.Close() })

    if ($dlg.ShowDialog($script:form) -eq [System.Windows.Forms.DialogResult]::OK) { return $script:selectedOU }
    return $null
}

# =====================================================================================
# GUI build helpers
# =====================================================================================
function New-Label {
    param([string]$Text)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Text
    $lbl.AutoSize = $true
    $lbl.Anchor = [System.Windows.Forms.AnchorStyles]::Left
    $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $lbl.Margin = New-Object System.Windows.Forms.Padding(6,7,6,3)
    return $lbl
}

function Add-TextRow {
    param(
        [System.Windows.Forms.TableLayoutPanel]$Layout,
        [int]$Row,
        [string]$Label,
        [System.Windows.Forms.Control]$Control
    )
    $Layout.Controls.Add((New-Label $Label),0,$Row)
    $Control.Dock = [System.Windows.Forms.DockStyle]::Fill
    $Control.Margin = New-Object System.Windows.Forms.Padding(4)
    $Layout.Controls.Add($Control,1,$Row)
}

# =====================================================================================
# GUI construction
# =====================================================================================
function Show-RowDetailsDialog {
    param([Parameter(Mandatory)]$Item)
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Migration Row Details'
    $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dlg.Size = New-Object System.Drawing.Size(850,520)
    $dlg.MinimizeBox = $false
    $dlg.MaximizeBox = $true
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Dock = [System.Windows.Forms.DockStyle]::Fill
    $txt.Multiline = $true
    $txt.ReadOnly = $true
    $txt.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
    $txt.WordWrap = $false
    $txt.Font = New-Object System.Drawing.Font('Consolas',9)
    $txt.Text = @"
Name              : $($Item.Name)
DisplayName       : $($Item.DisplayName)
Domain            : $($Item.Domain)
DC                : $($Item.DC)
Enabled           : $($Item.Enabled)
Current Login     : $($Item.OldSamAccountName)
New Login         : $($Item.NewSamAccountName)
Current UPN       : $($Item.OldUserPrincipalName)
New UPN           : $($Item.NewUserPrincipalName)
Status            : $($Item.Status)
Message           : $($Item.Message)
ObjectGUID        : $($Item.ObjectGUID)
SID               : $($Item.SID)
DistinguishedName : $($Item.DistinguishedName)
"@
    $dlg.Controls.Add($txt)
    [void]$dlg.ShowDialog($script:form)
}

function Build-GUI {
    $script:form = New-Object System.Windows.Forms.Form
    $script:form.Text = 'Update AD User sAMAccountName v3.2.9 - Governance Migration Console'
    $script:form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $script:form.Size = New-Object System.Drawing.Size(1360,760)
    $script:form.MinimumSize = New-Object System.Drawing.Size(1180,700)
    $script:form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

    $main = New-Object System.Windows.Forms.TableLayoutPanel
    $main.Dock = [System.Windows.Forms.DockStyle]::Fill
    $main.ColumnCount = 1
    $main.RowCount = 5
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,24)))   # Menu
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,155)))  # Scope/options
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))   # Grid
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,105)))  # Log
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,24)))   # Status
    $script:form.Controls.Add($main)

    # MenuStrip only. No duplicated ToolStrip commands.
    $menu = New-Object System.Windows.Forms.MenuStrip
    $menu.Dock = [System.Windows.Forms.DockStyle]::Fill
    $fileMenu = New-Object System.Windows.Forms.ToolStripMenuItem('File')
    $miOpenMap = New-Object System.Windows.Forms.ToolStripMenuItem('Open Mapping File...')
    $miExport = New-Object System.Windows.Forms.ToolStripMenuItem('Export Preview...')
    $miOpenLogs = New-Object System.Windows.Forms.ToolStripMenuItem('Open Logs Folder')
    $miExit = New-Object System.Windows.Forms.ToolStripMenuItem('Exit')
    [void]$fileMenu.DropDownItems.AddRange(@($miOpenMap,$miExport,$miOpenLogs,(New-Object System.Windows.Forms.ToolStripSeparator),$miExit))

    $adMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Active Directory')
    $miRefreshDomains = New-Object System.Windows.Forms.ToolStripMenuItem('Refresh Domains')
    $miResolveDC = New-Object System.Windows.Forms.ToolStripMenuItem('Resolve Writable DC')
    $miBrowseOU = New-Object System.Windows.Forms.ToolStripMenuItem('Browse OU...')
    $miDomainRoot = New-Object System.Windows.Forms.ToolStripMenuItem('Use Domain Root')
    [void]$adMenu.DropDownItems.AddRange(@($miRefreshDomains,$miResolveDC,$miBrowseOU,$miDomainRoot))

    $migMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Migration')
    $miLoad = New-Object System.Windows.Forms.ToolStripMenuItem('Load / Validate Mapping')
    $miPreview = New-Object System.Windows.Forms.ToolStripMenuItem('Run Preview')
    $miSelectReady = New-Object System.Windows.Forms.ToolStripMenuItem('Select Actionable Rows')
    $miClear = New-Object System.Windows.Forms.ToolStripMenuItem('Clear Selection')
    $miApply = New-Object System.Windows.Forms.ToolStripMenuItem('Apply Selected')
    $miUndo = New-Object System.Windows.Forms.ToolStripMenuItem('Undo Last Change')
    [void]$migMenu.DropDownItems.AddRange(@($miLoad,$miPreview,$miSelectReady,$miClear,(New-Object System.Windows.Forms.ToolStripSeparator),$miApply,$miUndo))

    $helpMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Help')
    $miAbout = New-Object System.Windows.Forms.ToolStripMenuItem('About')
    [void]$helpMenu.DropDownItems.Add($miAbout)
    [void]$menu.Items.AddRange(@($fileMenu,$adMenu,$migMenu,$helpMenu))
    $main.Controls.Add($menu,0,0)

    # Top configuration area: four clear sections.
    $config = New-Object System.Windows.Forms.TableLayoutPanel
    $config.Dock = [System.Windows.Forms.DockStyle]::Fill
    $config.ColumnCount = 4
    $config.RowCount = 1
    [void]$config.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,34)))
    [void]$config.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,34)))
    [void]$config.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,16)))
    [void]$config.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,16)))
    $main.Controls.Add($config,0,1)

    # Active Directory Scope
    $grpAD = New-Object System.Windows.Forms.GroupBox
    $grpAD.Text = 'Active Directory Scope'
    $grpAD.Dock = [System.Windows.Forms.DockStyle]::Fill
    $config.Controls.Add($grpAD,0,0)

    $ad = New-Object System.Windows.Forms.TableLayoutPanel
    $ad.Dock = [System.Windows.Forms.DockStyle]::Fill
    $ad.ColumnCount = 3
    $ad.RowCount = 4
    [void]$ad.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,90)))
    [void]$ad.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))
    [void]$ad.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,120)))
    for ($r=0; $r -lt 4; $r++) { [void]$ad.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,31))) }
    $grpAD.Controls.Add($ad)

    $script:cmbDomain = New-Object System.Windows.Forms.ComboBox
    $script:cmbDomain.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    Add-TextRow $ad 0 'Domain:' $script:cmbDomain
    $btnRefresh = New-Object System.Windows.Forms.Button; $btnRefresh.Text = 'Refresh'; $btnRefresh.Dock = [System.Windows.Forms.DockStyle]::Fill
    $ad.Controls.Add($btnRefresh,2,0)

    $script:txtDC = New-Object System.Windows.Forms.TextBox
    $script:txtDC.ReadOnly = $true
    Add-TextRow $ad 1 'Writable DC:' $script:txtDC
    $btnResolve = New-Object System.Windows.Forms.Button; $btnResolve.Text = 'Resolve DC'; $btnResolve.Dock = [System.Windows.Forms.DockStyle]::Fill
    $ad.Controls.Add($btnResolve,2,1)

    $script:txtSearchBase = New-Object System.Windows.Forms.TextBox
    Add-TextRow $ad 2 'SearchBase:' $script:txtSearchBase
    $btnBrowseOU = New-Object System.Windows.Forms.Button; $btnBrowseOU.Text = 'Browse OU'; $btnBrowseOU.Dock = [System.Windows.Forms.DockStyle]::Fill
    $ad.Controls.Add($btnBrowseOU,2,2)

    $script:chkIncludeDisabled = New-Object System.Windows.Forms.CheckBox
    $script:chkIncludeDisabled.Text = 'Include disabled users'
    $script:chkIncludeDisabled.Dock = [System.Windows.Forms.DockStyle]::Fill
    $ad.Controls.Add($script:chkIncludeDisabled,1,3)
    $btnRoot = New-Object System.Windows.Forms.Button; $btnRoot.Text = 'Domain Root'; $btnRoot.Dock = [System.Windows.Forms.DockStyle]::Fill
    $ad.Controls.Add($btnRoot,2,3)

    # Mapping Source
    $grpMap = New-Object System.Windows.Forms.GroupBox
    $grpMap.Text = 'Mapping Source: oldlogin,newlogin or aliases'
    $grpMap.Dock = [System.Windows.Forms.DockStyle]::Fill
    $config.Controls.Add($grpMap,1,0)

    $map = New-Object System.Windows.Forms.TableLayoutPanel
    $map.Dock = [System.Windows.Forms.DockStyle]::Fill
    $map.ColumnCount = 3
    $map.RowCount = 4
    [void]$map.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,50)))
    [void]$map.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))
    [void]$map.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,120)))
    for ($r=0; $r -lt 4; $r++) { [void]$map.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,31))) }
    $grpMap.Controls.Add($map)

    $script:txtMappingFile = New-Object System.Windows.Forms.TextBox
    Add-TextRow $map 0 'File:' $script:txtMappingFile
    $script:btnBrowseMap = New-Object System.Windows.Forms.Button; $script:btnBrowseMap.Text = 'Browse'; $script:btnBrowseMap.Dock = [System.Windows.Forms.DockStyle]::Fill
    $map.Controls.Add($script:btnBrowseMap,2,0)
    $script:btnLoadMap = New-Object System.Windows.Forms.Button; $script:btnLoadMap.Text = 'Load / Validate'; $script:btnLoadMap.Dock = [System.Windows.Forms.DockStyle]::Fill
    $map.Controls.Add($script:btnLoadMap,2,1)

    $script:chkCpfChecksum = New-Object System.Windows.Forms.CheckBox
    $script:chkCpfChecksum.Text = 'Optional Brazil CPF checksum validation'
    $script:chkCpfChecksum.Dock = [System.Windows.Forms.DockStyle]::Fill
    $map.Controls.Add($script:chkCpfChecksum,1,1)

    $script:lblMapStatus = New-Object System.Windows.Forms.Label
    $script:lblMapStatus.Text = 'Mapping not loaded.'
    $script:lblMapStatus.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:lblMapStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $map.Controls.Add($script:lblMapStatus,1,2)
    $map.SetColumnSpan($script:lblMapStatus,2)

    $script:progressMapping = New-Object System.Windows.Forms.ProgressBar
    $script:progressMapping.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:progressMapping.Visible = $false
    $script:progressMapping.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
    $script:progressMapping.MarqueeAnimationSpeed = 0
    $map.Controls.Add($script:progressMapping,1,3)
    $map.SetColumnSpan($script:progressMapping,2)

    # Execution Mode
    $grpExec = New-Object System.Windows.Forms.GroupBox
    $grpExec.Text = 'Preview / Apply Workflow'
    $grpExec.Dock = [System.Windows.Forms.DockStyle]::Fill
    $config.Controls.Add($grpExec,2,0)

    $exec = New-Object System.Windows.Forms.TableLayoutPanel
    $exec.Dock = [System.Windows.Forms.DockStyle]::Fill
    $exec.ColumnCount = 2
    $exec.RowCount = 4
    [void]$exec.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,50)))
    [void]$exec.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,50)))
    for ($r=0; $r -lt 4; $r++) { [void]$exec.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,31))) }
    $grpExec.Controls.Add($exec)

    $script:chkDryRun = New-Object System.Windows.Forms.CheckBox
    $script:chkDryRun.Text = 'Default Apply dialog: Simulation (Dry Run)'
    $script:chkDryRun.Checked = $true
    $script:chkDryRun.Dock = [System.Windows.Forms.DockStyle]::Fill
    $exec.Controls.Add($script:chkDryRun,0,0)
    $exec.SetColumnSpan($script:chkDryRun,2)

    $btnPreview = New-Object System.Windows.Forms.Button; $btnPreview.Text = '1. Run Preview'; $btnPreview.Dock = [System.Windows.Forms.DockStyle]::Fill
    $exec.Controls.Add($btnPreview,0,1)
    $btnSelect = New-Object System.Windows.Forms.Button; $btnSelect.Text = '2. Select Actionable'; $btnSelect.Dock = [System.Windows.Forms.DockStyle]::Fill
    $exec.Controls.Add($btnSelect,1,1)
    $btnApply = New-Object System.Windows.Forms.Button; $btnApply.Text = '3. Apply'; $btnApply.Dock = [System.Windows.Forms.DockStyle]::Fill; $btnApply.BackColor = [System.Drawing.Color]::FromArgb(192,57,43); $btnApply.ForeColor = [System.Drawing.Color]::White
    $exec.Controls.Add($btnApply,0,2)
    $btnUndo = New-Object System.Windows.Forms.Button; $btnUndo.Text = 'Undo'; $btnUndo.Dock = [System.Windows.Forms.DockStyle]::Fill
    $exec.Controls.Add($btnUndo,1,2)
    $btnExport = New-Object System.Windows.Forms.Button; $btnExport.Text = 'Export'; $btnExport.Dock = [System.Windows.Forms.DockStyle]::Fill
    $exec.Controls.Add($btnExport,0,3)
    $btnLogs = New-Object System.Windows.Forms.Button; $btnLogs.Text = 'Logs'; $btnLogs.Dock = [System.Windows.Forms.DockStyle]::Fill
    $exec.Controls.Add($btnLogs,1,3)

    # Statistics
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
    $script:txtStats.MultiSelect = $false
    $script:txtStats.Font = New-Object System.Drawing.Font('Segoe UI',8.25)
    [void]$script:txtStats.Columns.Add('Metric',145)
    [void]$script:txtStats.Columns.Add('Value',80,[System.Windows.Forms.HorizontalAlignment]::Right)
    $grpStats.Controls.Add($script:txtStats)

    # Preview grid
    $script:grid = New-Object System.Windows.Forms.DataGridView
    $script:grid.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:grid.AllowUserToAddRows = $false
    $script:grid.AllowUserToDeleteRows = $false
    $script:grid.MultiSelect = $true
    $script:grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $script:grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
    $script:grid.EditMode = [System.Windows.Forms.DataGridViewEditMode]::EditOnEnter
    $main.Controls.Add($script:grid,0,2)

    # Runtime Log only at bottom. Row details are available by double-clicking a preview row.
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

    # StatusStrip
    $status = New-Object System.Windows.Forms.StatusStrip
    $status.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:statusMain = New-Object System.Windows.Forms.ToolStripStatusLabel
    $script:statusMain.Spring = $true
    $script:statusMain.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $script:statusMain.Text = 'Ready.'
    $script:statusDomain = New-Object System.Windows.Forms.ToolStripStatusLabel
    $script:statusDC = New-Object System.Windows.Forms.ToolStripStatusLabel
    $script:statusMapping = New-Object System.Windows.Forms.ToolStripStatusLabel
    $script:statusPreview = New-Object System.Windows.Forms.ToolStripStatusLabel
    [void]$status.Items.AddRange(@($script:statusMain,$script:statusDomain,$script:statusDC,$script:statusMapping,$script:statusPreview))
    $main.Controls.Add($status,0,4)

    # Actions stored in script scope to avoid event-scope loss.
    $script:RefreshDomains = {
        $script:Domains = Get-ForestDomainsSafe
        $script:cmbDomain.Items.Clear()
        foreach ($d in $script:Domains) { [void]$script:cmbDomain.Items.Add($d) }
        if ($script:cmbDomain.Items.Count -gt 0 -and $script:cmbDomain.SelectedIndex -lt 0) { $script:cmbDomain.SelectedIndex = 0 }
        Write-AppLog "Forest domains discovered: $($script:Domains -join ', ')" 'SUCCESS'
        Update-StatusBar 'Domains refreshed.'
    }
    $script:ResolveDCAction = { [void](Resolve-WritableDC -Domain ([string]$script:cmbDomain.Text)) }
    $script:DomainRootAction = { $script:txtSearchBase.Text = Get-DomainDN -Domain ([string]$script:cmbDomain.Text); Update-StatusBar 'Domain root selected.' }
    $script:BrowseOUAction = { $selected = Show-OUBrowserDialog -Domain ([string]$script:cmbDomain.Text); if ($selected) { $script:txtSearchBase.Text = $selected; Update-StatusBar 'OU selected.' } }
    $script:OpenMappingAction = {
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = 'TXT/CSV mapping (*.txt;*.csv)|*.txt;*.csv|All files (*.*)|*.*'
        if ($ofd.ShowDialog($script:form) -eq [System.Windows.Forms.DialogResult]::OK) { $script:txtMappingFile.Text = $ofd.FileName }
    }
    $script:LoadMappingAction = {
        $mapPath = ''
        if ($script:txtMappingFile -and -not $script:txtMappingFile.IsDisposed) {
            $mapPath = ([string]$script:txtMappingFile.Text).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($mapPath)) {
            throw 'Please browse or type the mapping source file path before clicking Load / Validate.'
        }
        if (-not (Test-Path -LiteralPath $mapPath -PathType Leaf)) {
            throw "Mapping source file was not found: $mapPath"
        }

        Set-MappingLoadBusy -IsBusy $true -Message 'Loading and validating mapping file...'
        Write-AppLog "Mapping validation started: $mapPath" 'INFO'
        try {
            Import-OldSamNewSamMapping -Path $mapPath
        }
        finally {
            Set-MappingLoadBusy -IsBusy $false
            if ($script:lblMapStatus -and -not $script:lblMapStatus.IsDisposed -and $script:Stats.MappingRows -gt 0) {
                $script:lblMapStatus.Text = "Loaded: $($script:Stats.MappingReady) ready / $($script:Stats.MappingRows) rows"
            }
        }
    }
    $script:PreviewAction = { Build-MigrationPreview }
    $script:SelectReadyAction = { Select-ReadyRows }
    $script:ClearSelectionAction = { foreach ($i in $script:PreviewItems) { if ($null -ne $i) { $i.Selected = $false } }; Refresh-PreviewGrid; Update-StatusBar 'Selection cleared.' }
    $script:ApplyAction = { Invoke-SamMigration }
    $script:UndoAction = { Invoke-UndoLastChange }
    $script:ExportAction = { if ($script:PreviewItems.Count -eq 0) { throw 'No preview data to export.' }; $sfd=New-Object System.Windows.Forms.SaveFileDialog; $sfd.Filter='CSV (*.csv)|*.csv'; $sfd.FileName="AD-SamMigration-Preview-$($script:RunStamp).csv"; if ($sfd.ShowDialog($script:form) -eq [System.Windows.Forms.DialogResult]::OK) { $script:PreviewItems | Export-Csv -Path $sfd.FileName -NoTypeInformation -Encoding UTF8; Write-AppLog "Preview exported: $($sfd.FileName)" 'SUCCESS' } }
    $script:OpenLogsAction = { Start-Process explorer.exe $script:ReportRoot }

    # Event wiring - menu and section buttons call the same script-scope actions.
    $btnRefresh.Add_Click({ Invoke-UIAction $script:RefreshDomains 'Domain Refresh Error' }); $miRefreshDomains.Add_Click({ Invoke-UIAction $script:RefreshDomains 'Domain Refresh Error' })
    $btnResolve.Add_Click({ Invoke-UIAction $script:ResolveDCAction 'DC Resolution Error' }); $miResolveDC.Add_Click({ Invoke-UIAction $script:ResolveDCAction 'DC Resolution Error' })
    $btnRoot.Add_Click({ Invoke-UIAction $script:DomainRootAction 'SearchBase Error' }); $miDomainRoot.Add_Click({ Invoke-UIAction $script:DomainRootAction 'SearchBase Error' })
    $btnBrowseOU.Add_Click({ Invoke-UIAction $script:BrowseOUAction 'OU Browser Error' }); $miBrowseOU.Add_Click({ Invoke-UIAction $script:BrowseOUAction 'OU Browser Error' })
    $script:btnBrowseMap.Add_Click({ Invoke-UIAction $script:OpenMappingAction 'Open Mapping Error' }); $miOpenMap.Add_Click({ Invoke-UIAction $script:OpenMappingAction 'Open Mapping Error' })
    $script:btnLoadMap.Add_Click({ Invoke-UIAction $script:LoadMappingAction 'Mapping Error' }); $miLoad.Add_Click({ Invoke-UIAction $script:LoadMappingAction 'Mapping Error' })
    $btnPreview.Add_Click({ Invoke-UIAction $script:PreviewAction 'Preview Error' }); $miPreview.Add_Click({ Invoke-UIAction $script:PreviewAction 'Preview Error' })
    $btnSelect.Add_Click({ Invoke-UIAction $script:SelectReadyAction 'Selection Error' }); $miSelectReady.Add_Click({ Invoke-UIAction $script:SelectReadyAction 'Selection Error' })
    $miClear.Add_Click({ Invoke-UIAction $script:ClearSelectionAction 'Selection Error' })
    $btnApply.Add_Click({ Invoke-UIAction $script:ApplyAction 'Apply Error' }); $miApply.Add_Click({ Invoke-UIAction $script:ApplyAction 'Apply Error' })
    $btnUndo.Add_Click({ Invoke-UIAction $script:UndoAction 'Undo Error' }); $miUndo.Add_Click({ Invoke-UIAction $script:UndoAction 'Undo Error' })
    $btnExport.Add_Click({ Invoke-UIAction $script:ExportAction 'Export Error' }); $miExport.Add_Click({ Invoke-UIAction $script:ExportAction 'Export Error' })
    $btnLogs.Add_Click({ Invoke-UIAction $script:OpenLogsAction 'Open Logs Error' }); $miOpenLogs.Add_Click({ Invoke-UIAction $script:OpenLogsAction 'Open Logs Error' })
    $miExit.Add_Click({ $script:form.Close() })
    $miAbout.Add_Click({ Show-AppMessage "Update AD User sAMAccountName v3.2.9`r`nOldSamAccountName to NewSamAccountName migration console.`r`n`r`nAuthor: Luiz Hamilton Roberto da Silva - @brazilianscriptguy" 'About' })

    $script:cmbDomain.Add_SelectedIndexChanged({ $script:WritableDC = $null; $script:txtDC.Text = ''; Update-StatusBar 'Domain selected.' })
    $script:grid.Add_CurrentCellDirtyStateChanged({ if ($script:grid.IsCurrentCellDirty) { $script:grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit) } })
    $script:grid.Add_CellValueChanged({ if ($_.ColumnIndex -ge 0 -and $script:grid.Columns.Count -gt $_.ColumnIndex -and $script:grid.Columns[$_.ColumnIndex].Name -eq 'Select') { Sync-GridSelection } })
    $script:grid.Add_CellDoubleClick({
        if ($_.RowIndex -ge 0 -and $_.RowIndex -lt $script:grid.Rows.Count) {
            $idxText = [string]$script:grid.Rows[$_.RowIndex].Cells['Index'].Value
            $idx = 0
            if ([int]::TryParse($idxText, [ref]$idx)) {
                if ($idx -ge 0 -and $idx -lt $script:PreviewItems.Count) { Show-RowDetailsDialog -Item $script:PreviewItems[$idx] }
            }
        }
    })

    $script:form.Add_Shown({
        Invoke-UIAction { Write-AppLog 'GUI started.' 'SUCCESS'; Refresh-StatisticsView; & $script:RefreshDomains; Update-StatusBar 'Ready.' } 'Startup Error'
    })
}

# =====================================================================================
# Global exception handlers
# =====================================================================================
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException({
    param($sender, $e)
    try { Write-AppLog "Unhandled UI exception: $($e.Exception.ToString())" 'ERROR' } catch { }
    [System.Windows.Forms.MessageBox]::Show("Unhandled UI exception:`r`n$($e.Exception.Message)`r`n`r`nLog: $script:LogFile", 'Unhandled UI Exception', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
})
[AppDomain]::CurrentDomain.add_UnhandledException({
    param($sender, $e)
    try { Write-AppLog "Unhandled domain exception: $($e.ExceptionObject.ToString())" 'ERROR' } catch { }
})

try {
    Build-GUI
    [void][System.Windows.Forms.Application]::Run($script:form)
} catch {
    $fatal = $_.Exception.ToString()
    try { Write-AppLog "Fatal startup error: $fatal" 'ERROR' } catch { }
    [System.Windows.Forms.MessageBox]::Show("Fatal startup error:`r`n$($_.Exception.Message)`r`n`r`nLog: $script:LogFile", 'Fatal Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    if ($ShowConsole) { throw }
}

# End of script
