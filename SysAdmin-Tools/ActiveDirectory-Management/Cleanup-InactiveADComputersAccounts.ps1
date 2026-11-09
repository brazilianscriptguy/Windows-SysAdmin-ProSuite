#requires -Version 5.1
<#
.SYNOPSIS
  Active Directory Inactive Computer Cleanup v1.4.1 - Workstations deletion GUI.

.DESCRIPTION
  DRY-RUN is the default. COMMIT permanently deletes explicitly checked,
  freshly revalidated workstation computer accounts. No servers or DCs.
  Eligibility requires positive Windows client OS, full writable DC coverage,
  lastLogon evidence older than threshold, no recent replicated logon, machine
  password update, or creation. No-logon accounts are reported separately.
  Review backup, dependencies and AD Recycle Bin before using COMMIT.

.REQUIREMENTS
  Windows PowerShell 5.1, RSAT ActiveDirectory, appropriate delegated permissions.
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 3650)]
    [int]$DefaultInactiveDays = 180,

    [string]$OutputDirectory = 'C:\Logs-TEMP',

    # Internal bootstrap switch. Do not specify manually.
    [switch]$HiddenChild
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# =====================================================================================
# Hidden-console bootstrap
# =====================================================================================
# A .ps1 file is normally hosted by powershell.exe, which creates a console
# window. The parent process below immediately relaunches this script with
# -WindowStyle Hidden and exits. The GUI then runs in the hidden child process.
#
# This avoids Win32 ShowWindow() against the current console, which can
# accidentally hide an administrator's existing PowerShell console when the
# script was launched from one.
if (-not $HiddenChild -and -not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
    try {
        $powerShellExe = Join-Path $PSHOME 'powershell.exe'

        $escapedScriptPath = '"' + ($PSCommandPath -replace '"', '""') + '"'
        $escapedOutputPath = '"' + ($OutputDirectory -replace '"', '""') + '"'

        $argumentLine = @(
            '-NoLogo'
            '-NoProfile'
            '-NonInteractive'
            '-ExecutionPolicy Bypass'
            '-WindowStyle Hidden'
            '-File'
            $escapedScriptPath
            '-DefaultInactiveDays'
            [string]$DefaultInactiveDays
            '-OutputDirectory'
            $escapedOutputPath
            '-HiddenChild'
        ) -join ' '

        Start-Process `
            -FilePath $powerShellExe `
            -ArgumentList $argumentLine `
            -WindowStyle Hidden `
            -ErrorAction Stop | Out-Null

        exit
    }
    catch {
        # If relaunch fails, continue in the current host so the application is
        # still usable and the startup error remains visible for diagnosis.
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# =====================================================================================
# Application metadata and paths
# =====================================================================================

$script:AppName = 'Active Directory Inactive Computer Cleanup'
$script:AppVersion = '1.4.0'
$script:SessionId = [guid]::NewGuid().ToString()
$script:CurrentResults = New-Object System.Collections.ArrayList
$script:NoLogonResults = New-Object System.Collections.ArrayList
$script:ScanStarted = $null
$script:DomainControllerCache = @{}
$script:IsBusy = $false

$script:ScriptPath = $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($script:ScriptPath)) {
    $script:ScriptPath = Join-Path -Path (Get-Location) -ChildPath 'AD-InactiveComputerCleanup.ps1'
}

$script:ScriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($script:ScriptPath)

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

$script:LogPath = Join-Path $OutputDirectory ($script:ScriptBaseName + '.log')
$script:JournalPath = Join-Path $OutputDirectory ($script:ScriptBaseName + '-deletion-journal.csv')
$script:EvidenceDirectory = Join-Path $OutputDirectory ($script:ScriptBaseName + '-evidence')

if (-not (Test-Path -LiteralPath $script:EvidenceDirectory)) {
    New-Item -Path $script:EvidenceDirectory -ItemType Directory -Force | Out-Null
}

# =====================================================================================
# Logging and UI helpers
# =====================================================================================

function Write-AppLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message

    try {
        Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
    }
    catch {
        # Logging must never terminate the GUI.
    }

    if ($script:txtLog -and -not $script:txtLog.IsDisposed) {
        try {
            $script:txtLog.AppendText($line + [Environment]::NewLine)
            $script:txtLog.SelectionStart = $script:txtLog.TextLength
            $script:txtLog.ScrollToCaret()
        }
        catch {
        }
    }
}

function Set-UiStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [ValidateRange(0, 100)]
        [int]$Percent = 0
    )

    if ($script:lblStatus -and -not $script:lblStatus.IsDisposed) {
        $script:lblStatus.Text = $Text
    }

    if ($script:progressBar -and -not $script:progressBar.IsDisposed) {
        $script:progressBar.Value = [Math]::Max(0, [Math]::Min(100, $Percent))
    }

    [System.Windows.Forms.Application]::DoEvents()
}

function Set-BusyState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$Busy
    )

    $script:IsBusy = $Busy

    foreach ($control in @(
        $script:btnScan,
        $script:btnDelete,
        $script:btnExport,
        $script:btnSelectAll,
        $script:btnClear,
        $script:btnRefreshDomains,
        $script:cmbDomain,
        $script:numInactiveDays,
        $script:chkCommit
    )) {
        if ($control -and -not $control.IsDisposed) {
            $control.Enabled = (-not $Busy -and ($true))
        }
    }

    if ($script:form -and -not $script:form.IsDisposed) {
        if ($Busy) {
            $script:form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        }
        else {
            $script:form.Cursor = [System.Windows.Forms.Cursors]::Default
        }
    }

    [System.Windows.Forms.Application]::DoEvents()
}

function Show-ErrorMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Title = 'Operation failed'
    )

    [System.Windows.Forms.MessageBox]::Show(
        $script:form,
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

# =====================================================================================
# Active Directory provider
# =====================================================================================

function Assert-ActiveDirectoryModule {
    [CmdletBinding()]
    param()

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw 'The ActiveDirectory PowerShell module is not installed. Install RSAT: Active Directory Domain Services and Lightweight Directory Services Tools.'
    }

    Import-Module ActiveDirectory -ErrorAction Stop
}

function Get-ForestDomainNames {
    [CmdletBinding()]
    param()

    Assert-ActiveDirectoryModule

    $forest = Get-ADForest -ErrorAction Stop
    return @($forest.Domains | Sort-Object)
}

function Resolve-WritableDomainController {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DomainName,

        [switch]$ForceRefresh
    )

    if (-not $ForceRefresh -and $script:DomainControllerCache.ContainsKey($DomainName)) {
        return [string]$script:DomainControllerCache[$DomainName]
    }

    Write-AppLog -Level INFO -Message ("Resolving writable domain controller. Domain={0}" -f $DomainName)

    $dc = Get-ADDomainController `
        -Discover `
        -DomainName $DomainName `
        -Writable `
        -ForceDiscover `
        -ErrorAction Stop

    $dcHostName = $null

    if ($null -ne $dc.HostName) {
        $dcHostName = [string](@($dc.HostName)[0])
    }

    if ([string]::IsNullOrWhiteSpace($dcHostName) -and $null -ne $dc.Name) {
        $dcHostName = [string](@($dc.Name)[0])
    }

    if ([string]::IsNullOrWhiteSpace($dcHostName)) {
        throw "No writable domain controller was resolved for domain '$DomainName'."
    }

    $script:DomainControllerCache[$DomainName] = $dcHostName

    Write-AppLog -Level SUCCESS -Message (
        "Writable domain controller resolved. Domain={0} | DC={1}" -f
        $DomainName,
        $dcHostName
    )

    return $dcHostName
}

function Test-WorkstationAccount {
    param($Computer)
    $uac = [int64]$Computer.userAccountControl
    $os = [string]$Computer.OperatingSystem
    # Fail closed: only positively identified Windows client OS and normal workstation trust.
    if (($uac -band 8192) -ne 0 -or ($uac -band 2048) -ne 0 -or ($uac -band 4096) -eq 0) { return $false }
    if ($null -ne $Computer.primaryGroupID -and [int]$Computer.primaryGroupID -ne 515) { return $false }
    if ($os -match '(?i)server|domain controller|storage|hyper-v|linux|unix') { return $false }
    return ($os -match '(?i)^Windows (10|11)(\s|$)' -or $os -match '(?i)^Windows (7|8|8\.1|XP|Vista)(\s|$)')
}

function Get-DomainWritableDCs {
    param([string]$DomainName)
    $dcs = @(Get-ADDomainController -Filter * -Server $DomainName -ErrorAction Stop |
        Where-Object { -not $_.IsReadOnly } | Select-Object -ExpandProperty HostName -Unique)
    if ($dcs.Count -eq 0) { throw "No writable DCs discovered for $DomainName" }
    return $dcs
}

function Get-InactiveComputersFromDomain {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DomainName,
          [Parameter(Mandatory)][int]$InactiveDays)
    $now = Get-Date
    $cutoff = $now.AddDays(-$InactiveDays)
    $dcs = @(Get-DomainWritableDCs -DomainName $DomainName)
    $dc = $dcs[0]
    Write-AppLog -Level INFO -Message "Domain=$DomainName; WritableDCs=$($dcs -join ','); Workstations only; audit-only."
    $props = @('DNSHostName','Enabled','OperatingSystem','LastLogonDate',
        'lastLogonTimestamp','pwdLastSet','PasswordLastSet','whenCreated',
        'ProtectedFromAccidentalDeletion','userAccountControl','servicePrincipalName','primaryGroupID')
    $computers = @(Get-ADComputer -Filter * -Server $dc -Properties $props -ResultPageSize 500 -ErrorAction Stop)
    $results = New-Object System.Collections.ArrayList
    foreach ($computer in $computers) {
        if (-not (Test-WorkstationAccount -Computer $computer)) { continue }
        $latest = $null
        $coverage = $true
        $errors = New-Object System.Collections.ArrayList
        foreach ($targetDC in $dcs) {
            try {
                $item = Get-ADComputer -Identity $computer.ObjectGuid -Server $targetDC -Properties lastLogon -ErrorAction Stop
                $raw = [int64]$item.lastLogon
                if ($raw -gt 0) {
                    $dt = [datetime]::FromFileTimeUtc($raw).ToLocalTime()
                    if ($null -eq $latest -or $dt -gt $latest) { $latest = $dt }
                }
            } catch {
                $coverage = $false
                [void]$errors.Add("${targetDC}: $($_.Exception.Message)")
            }
        }
        $pwd = $computer.PasswordLastSet
        $created = $computer.whenCreated
        $replicated = $computer.LastLogonDate
        $dates = @($latest,$replicated,$pwd,$created) | Where-Object { $null -ne $_ }
        $lastActivity = $null
        foreach ($dt in $dates) { if ($null -eq $lastActivity -or $dt -gt $lastActivity) { $lastActivity = $dt } }
        $age = if ($lastActivity) { [int][math]::Floor(($now - $lastActivity).TotalDays) } else { $null }
        # Only positively identified Windows clients can enter the review inventory.
        # A disabled account is NOT evidence of 180 days of inactivity.
        $noLogon = ($null -eq $latest -and $null -eq $replicated)
        $oldEnough = ($created -and $created -le $cutoff)
        $recentActivity = (($latest -and $latest -gt $cutoff) -or
            ($replicated -and $replicated -gt $cutoff) -or
            ($pwd -and $pwd -gt $cutoff) -or
            ($created -and $created -gt $cutoff))
        $state = if ([bool]$computer.Enabled) { 'ENABLED' } else { 'DISABLED' }
        $status = if (-not $coverage) { 'INCONCLUSIVE_DC_COVERAGE' }
            elseif ($computer.ProtectedFromAccidentalDeletion) { 'PROTECTED_REVIEW' }
            elseif (-not $created) { 'INCONCLUSIVE_CREATION_DATE' }
            elseif ($recentActivity) { "${state}_RECENT_PRESERVE" }
            elseif ($noLogon -and $oldEnough) { "${state}_NO_LOGON_REVIEW" }
            elseif ($oldEnough) { "${state}_180D_REVIEW" }
            else { 'INCONCLUSIVE_EVIDENCE' }
        $record = [pscustomobject]@{
            Selected = $false; Domain = $DomainName; DomainController = $dc
            Name = [string]$computer.Name; DNSHostName = [string]$computer.DNSHostName
            Enabled = [bool]$computer.Enabled; AccountState = $state
            OperatingSystem = [string]$computer.OperatingSystem
            LastLogonDate = $latest; InactiveDays = $age; Status = $status
            NoLogonEvidence = [bool]$noLogon
            CandidateForReview = [bool]($status -match '^(ENABLED|DISABLED)_180D_REVIEW$' -and $age -ge $InactiveDays -and -not $noLogon)
            ProtectedFromAccidentalDeletion = [bool]$computer.ProtectedFromAccidentalDeletion
            DistinguishedName = [string]$computer.DistinguishedName
            ObjectGuid = [guid]$computer.ObjectGuid; WhenCreated = $created
            PasswordLastSet = $pwd; ReplicatedLastLogonDate = $replicated
            WritableDCCount = $dcs.Count; DCsChecked = $dcs -join ';'
            DCErrors = $errors -join ' | '; AuditTime = $now
        }
        # Full workstation inventory is retained, including active accounts,
        # so separate no-logon exports can be reconciled against the scan.
        [void]$results.Add($record)
    }
    Write-AppLog -Level SUCCESS -Message "Workstation scan completed. Domain=$DomainName; ReviewRecords=$($results.Count)"
    return @($results)
}

# =====================================================================================
# Evidence and journal
# =====================================================================================

function Get-TimestampToken {
    return (Get-Date -Format 'yyyyMMdd-HHmmss')
}

function Export-RecordsToCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Records,

        [Parameter(Mandatory)]
        [string]$Purpose
    )

    if ($Records.Count -eq 0) {
        throw 'There are no records to export.'
    }

    $fileName = '{0}-{1}-{2}-{3}.csv' -f `
        $script:ScriptBaseName,
        $Purpose,
        (Get-TimestampToken),
        $script:SessionId.Substring(0, 8)

    $path = Join-Path $script:EvidenceDirectory $fileName

    $Records |
        Select-Object `
            Domain,
            DomainController,
            Name,
            DNSHostName,
            Enabled,
            AccountState,
            OperatingSystem,
            LastLogonDate,
            InactiveDays,
            Status,
            CandidateForReview,
            NoLogonEvidence,
            PasswordLastSet,
            ReplicatedLastLogonDate,
            WritableDCCount,
            DCsChecked,
            DCErrors,
            AuditTime,
            ProtectedFromAccidentalDeletion,
            DistinguishedName,
            ObjectGuid,
            WhenCreated |
        Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8

    Write-AppLog -Level SUCCESS -Message ("Evidence exported. Purpose={0} | Path={1} | Records={2}" -f $Purpose, $path, $Records.Count)

    return $path
}

function Add-DeletionJournalEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Domain,

        [Parameter(Mandatory)]
        [string]$DomainController,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$DistinguishedName,

        [Parameter(Mandatory)]
        [string]$ObjectGuid,

        [Parameter(Mandatory)]
        [string]$Result,

        [Parameter(Mandatory)]
        [string]$Details,

        [Nullable[int]]$InactiveDays
    )

    $entry = [pscustomobject]@{
        Timestamp        = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        SessionId        = $script:SessionId
        Operator         = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        ComputerName     = $env:COMPUTERNAME
        Domain           = $Domain
        DomainController = $DomainController
        Name             = $Name
        DistinguishedName = $DistinguishedName
        ObjectGuid       = $ObjectGuid
        InactiveDays     = $InactiveDays
        Result           = $Result
        Details          = $Details
    }

    $journalExists = Test-Path -LiteralPath $script:JournalPath

    if ($journalExists) {
        $entry | Export-Csv -LiteralPath $script:JournalPath -NoTypeInformation -Encoding UTF8 -Append
    }
    else {
        $entry | Export-Csv -LiteralPath $script:JournalPath -NoTypeInformation -Encoding UTF8
    }
}

# =====================================================================================
# DataGridView
# =====================================================================================

function Initialize-ResultsGrid {
    [CmdletBinding()]
    param()

    $script:grid.AutoGenerateColumns = $false
    $script:grid.AllowUserToAddRows = $false
    $script:grid.AllowUserToDeleteRows = $false
    $script:grid.AllowUserToOrderColumns = $true
    $script:grid.MultiSelect = $true
    $script:grid.ReadOnly = $false
    $script:grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $script:grid.RowHeadersVisible = $false
    $script:grid.AutoSizeRowsMode = [System.Windows.Forms.DataGridViewAutoSizeRowsMode]::None

    $selectColumn = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $selectColumn.Name = 'Selected'
    $selectColumn.HeaderText = 'Review'
    $selectColumn.DataPropertyName = 'Selected'
    $selectColumn.Width = 55
    $selectColumn.ReadOnly = $false
    [void]$script:grid.Columns.Add($selectColumn)

    $columns = @(
        @{ Name = 'Domain'; Header = 'Domain'; Property = 'Domain'; Width = 170 },
        @{ Name = 'Name'; Header = 'Computer'; Property = 'Name'; Width = 145 },
        @{ Name = 'Enabled'; Header = 'Enabled'; Property = 'Enabled'; Width = 65 },
        @{ Name = 'CandidateForReview'; Header = 'Candidate'; Property = 'CandidateForReview'; Width = 75 },
        @{ Name = 'NoLogonEvidence'; Header = 'No Logon'; Property = 'NoLogonEvidence'; Width = 75 },
        @{ Name = 'OperatingSystem'; Header = 'Operating System'; Property = 'OperatingSystem'; Width = 210 },
        @{ Name = 'LastLogonDate'; Header = 'Last Logon'; Property = 'LastLogonDate'; Width = 135 },
        @{ Name = 'InactiveDays'; Header = 'Inactive Days'; Property = 'InactiveDays'; Width = 90 },
        @{ Name = 'PasswordLastSet'; Header = 'Password Last Set'; Property = 'PasswordLastSet'; Width = 145 },
        @{ Name = 'ReplicatedLastLogonDate'; Header = 'Replicated Logon'; Property = 'ReplicatedLastLogonDate'; Width = 145 },
        @{ Name = 'WritableDCCount'; Header = 'DC Count'; Property = 'WritableDCCount'; Width = 65 },
        @{ Name = 'DCErrors'; Header = 'DC Errors'; Property = 'DCErrors'; Width = 240 },
        @{ Name = 'Protected'; Header = 'Protected'; Property = 'ProtectedFromAccidentalDeletion'; Width = 75 },
        @{ Name = 'Status'; Header = 'Status'; Property = 'Status'; Width = 170 },
        @{ Name = 'DNSHostName'; Header = 'DNS Host Name'; Property = 'DNSHostName'; Width = 220 },
        @{ Name = 'DistinguishedName'; Header = 'Distinguished Name'; Property = 'DistinguishedName'; Width = 360 }
    )

    foreach ($definition in $columns) {
        $column = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $column.Name = $definition.Name
        $column.HeaderText = $definition.Header
        $column.DataPropertyName = $definition.Property
        $column.Width = $definition.Width
        $column.ReadOnly = $true

        if ($definition.Name -eq 'LastLogonDate') {
            $column.DefaultCellStyle.Format = 'yyyy-MM-dd HH:mm:ss'
        }

        [void]$script:grid.Columns.Add($column)
    }
}

function Update-ResultsSummary {
    [CmdletBinding()]
    param()

    $checkedCount = 0

    foreach ($row in $script:grid.Rows) {
        if ($row.IsNewRow) {
            continue
        }

        if ([bool]$row.Cells['Selected'].Value) {
            $checkedCount++
        }
    }

    $candidateCount = @($script:CurrentResults | Where-Object { $_.CandidateForReview }).Count
    $script:lblSummary.Text = 'Eligible: {0} | Candidates: {1} | Checked: {2}' -f `
        $script:CurrentResults.Count, $candidateCount, $checkedCount
}

function Refresh-ResultsGrid {
    [CmdletBinding()]
    param()

    # PowerShell PSCustomObject collections can create the correct number of
    # DataGridView rows while leaving bound cells blank. Populate each row
    # explicitly and retain the source record in Row.Tag.
    $script:grid.SuspendLayout()

    try {
        $script:grid.Rows.Clear()

        foreach ($record in $script:CurrentResults) {
            $rowIndex = $script:grid.Rows.Add()
            $row = $script:grid.Rows[$rowIndex]
            $row.Tag = $record

            $row.Cells['Selected'].Value = [bool]$record.Selected
            $row.Cells['Domain'].Value = [string]$record.Domain
            $row.Cells['Name'].Value = [string]$record.Name
            $row.Cells['Enabled'].Value = [bool]$record.Enabled
            $row.Cells['CandidateForReview'].Value = [bool]$record.CandidateForReview
            $row.Cells['NoLogonEvidence'].Value = [bool]$record.NoLogonEvidence
            $row.Cells['OperatingSystem'].Value = [string]$record.OperatingSystem
            $row.Cells['LastLogonDate'].Value = $record.LastLogonDate
            $row.Cells['InactiveDays'].Value = if ($null -ne $record.InactiveDays) { [int]$record.InactiveDays } else { $null }
            $row.Cells['PasswordLastSet'].Value = $record.PasswordLastSet
            $row.Cells['ReplicatedLastLogonDate'].Value = $record.ReplicatedLastLogonDate
            $row.Cells['WritableDCCount'].Value = $record.WritableDCCount
            $row.Cells['DCErrors'].Value = $record.DCErrors
            $row.Cells['Protected'].Value = [bool]$record.ProtectedFromAccidentalDeletion
            $row.Cells['Status'].Value = [string]$record.Status
            $row.Cells['DNSHostName'].Value = [string]$record.DNSHostName
            $row.Cells['DistinguishedName'].Value = [string]$record.DistinguishedName
        }
    }
    finally {
        $script:grid.ResumeLayout()
    }

    Update-ResultsSummary
    $script:grid.Refresh()
}

function Sync-GridEdits {
    [CmdletBinding()]
    param()

    # WinForms methods such as CommitEdit() and EndEdit() return Boolean values.
    # Their return values must be suppressed; otherwise they enter the PowerShell
    # success pipeline and can be mistaken for selected AD records.
    if ($script:grid.IsCurrentCellDirty) {
        [void]$script:grid.CommitEdit(
            [System.Windows.Forms.DataGridViewDataErrorContexts]::Commit
        )
    }

    [void]$script:grid.EndEdit()

    foreach ($row in $script:grid.Rows) {
        if ($row.IsNewRow -or $null -eq $row.Tag) {
            continue
        }

        $row.Tag.Selected = [bool]$row.Cells['Selected'].Value
    }
}

function Get-CheckedRecords {
    [CmdletBinding()]
    param()

    # Explicitly discard any accidental output from the synchronization helper.
    $null = Sync-GridEdits

    $checked = New-Object System.Collections.Generic.List[object]

    foreach ($row in $script:grid.Rows) {
        if ($row.IsNewRow -or $null -eq $row.Tag) {
            continue
        }

        if (-not [bool]$row.Cells['Selected'].Value) {
            continue
        }

        $record = $row.Tag

        # Only admit normalized AD computer records to the deletion pipeline.
        $requiredProperties = @(
            'Domain',
            'DomainController',
            'Name',
            'DistinguishedName',
            'ObjectGuid',
            'InactiveDays'
        )

        $missingProperties = @(
            foreach ($propertyName in $requiredProperties) {
                if ($null -eq $record.PSObject.Properties[$propertyName]) {
                    $propertyName
                }
            }
        )

        if ($missingProperties.Count -gt 0) {
            Write-AppLog -Level ERROR -Message (
                "Invalid grid record rejected before deletion. MissingProperties={0} | RecordType={1}" -f
                ($missingProperties -join ','),
                $record.GetType().FullName
            )
            continue
        }

        $checked.Add($record)
    }

    # Return the records as a normal PowerShell array. A unary comma here would
    # wrap the array inside another array, causing the deletion loop to receive
    # one System.Object[] instead of individual computer records.
    return $checked.ToArray()
}

# =====================================================================================
# Operations
# =====================================================================================

function Load-ForestDomainsIntoGui {
    [CmdletBinding()]
    param()

    if ($script:IsBusy) {
        return
    }

    Set-BusyState -Busy $true
    Set-UiStatus -Text 'Loading forest domains...' -Percent 0

    try {
        Write-AppLog -Level INFO -Message 'Forest domain loading started.'

        $domains = @(Get-ForestDomainNames)

        $script:cmbDomain.Items.Clear()
        
        foreach ($domain in $domains) {
            [void]$script:cmbDomain.Items.Add($domain)
        }

        if ($script:cmbDomain.Items.Count -gt 0) {
            $script:cmbDomain.SelectedIndex = 0
        }

        Write-AppLog -Level SUCCESS -Message ("Forest domain loading completed. Domains={0}" -f $domains.Count)
        Set-UiStatus -Text ("Ready. Forest domains loaded: {0}" -f $domains.Count) -Percent 0
    }
    catch {
        Write-AppLog -Level ERROR -Message ("Forest domain loading failed. Error={0}" -f $_.Exception.Message)
        Set-UiStatus -Text 'Forest domain loading failed.' -Percent 0
        Show-ErrorMessage -Message $_.Exception.Message
    }
    finally {
        Set-BusyState -Busy $false
    }
}

function Start-InactiveComputerScan {
    [CmdletBinding()]
    param()

    if ($script:IsBusy) {
        return
    }

    if ($script:cmbDomain.SelectedItem -eq $null) {
        Show-ErrorMessage -Message 'Select a domain scope before scanning.' -Title 'Missing domain scope'
        return
    }

    $inactiveDays = [int]$script:numInactiveDays.Value
    $selectedScope = [string]$script:cmbDomain.SelectedItem

    Set-BusyState -Busy $true
    $script:CurrentResults.Clear()
    $script:NoLogonResults.Clear()
    $allAudited = New-Object System.Collections.ArrayList
    $script:ScanStarted = Get-Date
    Refresh-ResultsGrid
    $script:ScanFailures = 0
    $script:ScanThresholdDays = $inactiveDays
    $script:ScanScope = $selectedScope

    try {
        Assert-ActiveDirectoryModule

        if ($selectedScope -eq 'ALL_FOREST_DOMAINS') {
            $domains = @()
            foreach ($item in $script:cmbDomain.Items) {
                if ([string]$item -ne 'ALL_FOREST_DOMAINS') {
                    $domains += [string]$item
                }
            }
        }
        else {
            $domains = @($selectedScope)
        }

        if ($domains.Count -eq 0) {
            throw 'No forest domains are available for scanning.'
        }

        Write-AppLog -Level INFO -Message (
            "Scan initiated. Scope={0} | ThresholdDays={1} | Domains={2}" -f
            $selectedScope,
            $inactiveDays,
            $domains.Count
        )

        $domainIndex = 0

        foreach ($domain in $domains) {
            $domainIndex++
            $percent = [int](($domainIndex - 1) / [double]$domains.Count * 100)

            Set-UiStatus `
                -Text ("Scanning domain {0} of {1}: {2}" -f $domainIndex, $domains.Count, $domain) `
                -Percent $percent

            try {
                $records = @(Get-InactiveComputersFromDomain -DomainName $domain -InactiveDays $inactiveDays)

                foreach ($record in $records) {
                    [void]$allAudited.Add($record)
                    if ($record.NoLogonEvidence) { [void]$script:NoLogonResults.Add($record) }
                    if ($record.CandidateForReview) { [void]$script:CurrentResults.Add($record) }
                }
            }
            catch {
                $script:ScanFailures++
                Write-AppLog -Level ERROR -Message (
                    "Domain scan failed. Domain={0} | Error={1}" -f
                    $domain,
                    $_.Exception.Message
                )
            }

            Refresh-ResultsGrid
        }

        $sorted = @(
            $script:CurrentResults |
                Sort-Object Domain, @{ Expression = 'InactiveDays'; Descending = $true }, Name
        )

        $script:CurrentResults.Clear()
        foreach ($record in $sorted) {
            [void]$script:CurrentResults.Add($record)
        }

        Refresh-ResultsGrid

        # Automatically export complete evidence and a separate no-logon report.
        # A zero-row report still receives a header for deterministic auditing.
        $fullPath = '(none)'
        if ($allAudited.Count -gt 0) {
            $fullPath = Export-RecordsToCsv -Records @($allAudited) -Purpose 'all-workstations'
        }
        $noLogonPath = Join-Path $script:EvidenceDirectory ('no-logon-workstations-{0}-{1}.csv' -f (Get-TimestampToken), $script:SessionId.Substring(0,8))
        $headerFields = @('Domain','Name','Enabled','AccountState','OperatingSystem','LastLogonDate','ReplicatedLastLogonDate','PasswordLastSet','WhenCreated','InactiveDays','Status','CandidateForReview','NoLogonEvidence','WritableDCCount','DCsChecked','DCErrors','DistinguishedName','ObjectGuid','AuditTime')
        if ($script:NoLogonResults.Count -gt 0) {
            $script:NoLogonResults | Select-Object -Property $headerFields |
                Export-Csv -LiteralPath $noLogonPath -NoTypeInformation -Encoding UTF8
        } else {
            ('"' + ($headerFields -join '","') + '"') | Set-Content -LiteralPath $noLogonPath -Encoding UTF8
        }
        Write-AppLog -Level SUCCESS -Message "No-logon workstation report: $noLogonPath; Count=$($script:NoLogonResults.Count)"
        $candidates = @($script:CurrentResults | Where-Object { $_.CandidateForReview })
        if ($candidates.Count -gt 0 -and $script:ScanFailures -eq 0) {
            $candidatePath = Export-RecordsToCsv -Records $candidates -Purpose 'candidates-manual-review'
            Write-AppLog -Level INFO -Message "Candidate review CSV: $candidatePath"
        }
        Write-AppLog -Level INFO -Message "Full workstation CSV: $fullPath; Audited=$($allAudited.Count); Candidates=$($candidates.Count); NoLogon=$($script:NoLogonResults.Count)"

        if ($script:ScanFailures -gt 0) {
            $script:CurrentResults.Clear()
            Refresh-ResultsGrid
            Write-AppLog -Level ERROR -Message "PARTIAL_SCAN: $($script:ScanFailures) domain(s) failed. Results are incomplete."
        }
        Write-AppLog -Level SUCCESS -Message (
            "Scan completed. Scope={0} | ThresholdDays={1} | EligibleCandidates={2}" -f
            $selectedScope,
            $inactiveDays,
            $script:CurrentResults.Count
        )

        Set-UiStatus `
            -Text ("Scan completed. Eligible workstation candidates: {0}" -f $script:CurrentResults.Count) `
            -Percent 100

        # Operator notification: display only after scan and evidence export finish.
        if ($script:ScanFailures -gt 0) {
            $message = "INCOMPLETE AUDIT - NO DELETION ALLOWED.`r`n`r`nScope: $selectedScope`r`nThreshold: $inactiveDays days`r`nFailed domains: $($script:ScanFailures)`r`n`r`nThe candidate list was cleared because coverage is incomplete. Review the operational log and rerun the audit."
            [System.Windows.Forms.MessageBox]::Show($script:form, $message, 'Audit incomplete - COMMIT blocked', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
        elseif ($script:CurrentResults.Count -eq 0) {
            $message = "NO ELIGIBLE WORKSTATIONS FOUND.`r`n`r`nScope: $selectedScope`r`nThreshold: $inactiveDays days`r`nWorkstations audited: $($allAudited.Count)`r`nWithout logon evidence: $($script:NoLogonResults.Count)`r`n`r`nNo workstation met all candidate criteria. No AD object was modified.`r`n`r`nFull report: $fullPath`r`nNo-logon report: $noLogonPath"
            [System.Windows.Forms.MessageBox]::Show($script:form, $message, 'Audit complete - zero candidates', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        }
        else {
            $message = "ELIGIBLE WORKSTATIONS IDENTIFIED FOR REVIEW.`r`n`r`nScope: $selectedScope`r`nThreshold: $inactiveDays days`r`nWorkstations audited: $($allAudited.Count)`r`nCandidates: $($script:CurrentResults.Count)`r`nWithout logon evidence: $($script:NoLogonResults.Count)`r`n`r`nReview the listed objects and select them individually. DRY-RUN makes no AD changes. COMMIT permanently deletes selected objects after revalidation and confirmation.`r`n`r`nCandidate report: $candidatePath"
            [System.Windows.Forms.MessageBox]::Show($script:form, $message, 'Audit complete - candidates found', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        }
    }
    catch {
        Write-AppLog -Level ERROR -Message ("Scan failed. Error={0}" -f $_.Exception.Message)
        Set-UiStatus -Text 'Scan failed.' -Percent 0
        Show-ErrorMessage -Message $_.Exception.Message
    }
    finally {
        Set-BusyState -Busy $false
    }
}

function Export-CurrentResults {
    [CmdletBinding()]
    param()

    if ($script:CurrentResults.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            $script:form,
            'There are no scan results to export.',
            'Nothing to export',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    try {
        $path = Export-RecordsToCsv -Records @($script:CurrentResults) -Purpose 'scan-results'

        [System.Windows.Forms.MessageBox]::Show(
            $script:form,
            "CSV export completed.`r`n`r`n$path",
            'Export completed',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    catch {
        Write-AppLog -Level ERROR -Message ("Export failed. Error={0}" -f $_.Exception.Message)
        Show-ErrorMessage -Message $_.Exception.Message
    }
}

function Remove-CheckedInactiveComputers {
    # DRY-RUN never writes to AD; COMMIT requires a checked GUI opt-in.
    if ($script:IsBusy) { return }
    $items = @(Get-CheckedRecords)
    if ($items.Count -eq 0) { Show-ErrorMessage -Message 'Select at least one eligible workstation.'; return }
    $days = [int]$script:numInactiveDays.Value
    if ($days -lt 180) { Show-ErrorMessage -Message 'Deletion COMMIT requires a threshold of at least 180 days.'; return }
    if ($script:ScanFailures -gt 0 -or $script:ScanThresholdDays -ne $days -or $script:ScanScope -ne [string]$script:cmbDomain.SelectedItem) {
        Show-ErrorMessage -Message 'Scan is partial or parameters changed. Run a fresh scan.'; return
    }
    if (@($items | Where-Object { -not $_.CandidateForReview -or $_.NoLogonEvidence -or $_.ProtectedFromAccidentalDeletion -or $_.DCErrors }).Count -gt 0) {
        Show-ErrorMessage -Message 'Selection includes ineligible, protected or inconclusive objects.'; return
    }
    # Evidence must be durably written BEFORE any deletion.
    try {
        $evidencePath = Export-RecordsToCsv -Records $items -Purpose 'predelete-selected-workstations'
        if (-not (Test-Path -LiteralPath $evidencePath)) { throw 'Pre-deletion evidence was not created.' }
    } catch { Show-ErrorMessage -Message "Evidence export failed. No deletion: $($_.Exception.Message)"; return }
    if (-not $script:chkCommit.Checked) {
        Write-AppLog -Level INFO -Message "DRY-RUN: $($items.Count) selected; no AD writes. Evidence=$evidencePath"
        [System.Windows.Forms.MessageBox]::Show($script:form,"DRY-RUN: $($items.Count) selected. No AD objects modified.`nEvidence: $evidencePath",'DRY-RUN') | Out-Null
        return
    }
    $answer = [System.Windows.Forms.MessageBox]::Show($script:form,
        ("PERMANENTLY DELETE {0} workstation AD object(s)? This is not a disable operation. Confirm backup, dependencies and recovery readiness. Evidence: {1}" -f $items.Count,$evidencePath),
        'CONFIRM PERMANENT AD DELETION',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    Add-Type -AssemblyName Microsoft.VisualBasic
    $typed = [Microsoft.VisualBasic.Interaction]::InputBox(
        'Type DELETE to confirm permanent removal of the selected workstation accounts:',
        'Second confirmation required','')
    if ($typed -cne 'DELETE') { Write-AppLog -Level INFO -Message 'COMMIT canceled: confirmation phrase mismatch.'; return }
    $results = New-Object System.Collections.ArrayList
    Set-BusyState -Busy $true
    try {
        foreach ($record in $items) {
            $status = 'BLOCKED'; $detail = ''; $dcForJournal = [string]$record.DomainController
            try {
                $dcs = @(Get-DomainWritableDCs -DomainName $record.Domain)
                if ($dcs.Count -ne [int]$record.WritableDCCount -or (($dcs | Sort-Object) -join ';') -ne (([string]$record.DCsChecked -split ';' | Sort-Object) -join ';')) {
                    throw 'Writable DC coverage changed since scan.'
                }
                $base = Get-ADComputer -Identity $record.ObjectGuid -Server $dcs[0] -Properties Enabled,OperatingSystem,userAccountControl,primaryGroupID,whenCreated,PasswordLastSet,LastLogonDate,ProtectedFromAccidentalDeletion -ErrorAction Stop
                if (-not (Test-WorkstationAccount -Computer $base)) { throw 'Not a positively identified workstation.' }
                if ([guid]$base.ObjectGuid -ne [guid]$record.ObjectGuid -or [string]$base.DistinguishedName -ne [string]$record.DistinguishedName) { throw 'Identity or DN changed.' }
                if ([bool]$base.Enabled -ne [bool]$record.Enabled) { throw 'Enabled state changed since scan.' }
                if ($base.ProtectedFromAccidentalDeletion) { throw 'Protected from accidental deletion.' }
                $cutoff = (Get-Date).AddDays(-$days)
                if (-not $base.whenCreated -or $base.whenCreated -gt $cutoff) { throw 'Creation date recent or unknown.' }
                if ($base.PasswordLastSet -and $base.PasswordLastSet -gt $cutoff) { throw 'Recent machine password update.' }
                if ($base.LastLogonDate -and $base.LastLogonDate -gt $cutoff) { throw 'Recent replicated logon.' }
                $foundLogon = $false
                foreach ($dc in $dcs) {
                    $live = Get-ADComputer -Identity $record.ObjectGuid -Server $dc -Properties lastLogon,Enabled,userAccountControl,OperatingSystem,primaryGroupID -ErrorAction Stop
                    if (-not (Test-WorkstationAccount -Computer $live)) { throw "Workstation check failed on $dc" }
                    if ([bool]$live.Enabled -ne [bool]$base.Enabled) { throw "Account state differs on $dc" }
                    $raw = [int64]$live.lastLogon
                    if ($raw -gt 0) {
                        $foundLogon = $true
                        if ([datetime]::FromFileTimeUtc($raw) -gt $cutoff.ToUniversalTime()) { throw "Recent lastLogon on $dc" }
                    }
                }
                if (-not $foundLogon) { throw 'No logon evidence; manual review only.' }
                $dcForJournal = $dcs[0]
                # Journal intent before destructive action; failure blocks deletion.
                Add-DeletionJournalEntry -Domain $record.Domain -DomainController $dcForJournal -Name $record.Name -DistinguishedName $record.DistinguishedName -ObjectGuid $record.ObjectGuid -InactiveDays $record.InactiveDays -Result 'DELETE_ATTEMPT' -Details "Evidence=$evidencePath"
                Remove-ADComputer -Identity $record.ObjectGuid -Server $dcForJournal -Confirm:$false -ErrorAction Stop
                $status = 'DELETED'
                $record.CandidateForReview = $false
                $record.Status = 'DELETED'
                Write-AppLog -Level SUCCESS -Message "COMMIT deleted workstation: $($record.Domain) / $($record.Name)"
            } catch {
                $detail = $_.Exception.Message
                Write-AppLog -Level ERROR -Message "Deletion blocked/failed: $($record.Domain) / $($record.Name): $detail"
            } finally {
                [void]$results.Add([pscustomobject]@{ Timestamp=(Get-Date).ToString('o');Domain=$record.Domain;Name=$record.Name;ObjectGuid=$record.ObjectGuid;Result=$status;Detail=$detail })
                try { Add-DeletionJournalEntry -Domain $record.Domain -DomainController $dcForJournal -Name $record.Name -DistinguishedName $record.DistinguishedName -ObjectGuid $record.ObjectGuid -InactiveDays $record.InactiveDays -Result $status -Details $detail } catch { Write-AppLog -Level ERROR -Message "Journal failure: $($_.Exception.Message)" }
            }
        }
        $path = Join-Path $script:EvidenceDirectory ('commit-delete-{0}.csv' -f (Get-TimestampToken))
        $results | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Refresh-ResultsGrid
        [System.Windows.Forms.MessageBox]::Show($script:form,"COMMIT finished. Review deletion results: $path",'COMMIT results') | Out-Null
    } finally { Set-BusyState -Busy $false }
}

$script:form = New-Object System.Windows.Forms.Form
$script:form.Text = "$($script:AppName) v$($script:AppVersion)"
$script:form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$script:form.Size = New-Object System.Drawing.Size(1500, 900)
$script:form.MinimumSize = New-Object System.Drawing.Size(1100, 700)
$script:form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$script:form.KeyPreview = $true

$topPanel = New-Object System.Windows.Forms.Panel
$topPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$topPanel.Height = 78
$topPanel.Padding = New-Object System.Windows.Forms.Padding(10)
$script:form.Controls.Add($topPanel)

$lblDomain = New-Object System.Windows.Forms.Label
$lblDomain.Text = 'Domain scope'
$lblDomain.AutoSize = $true
$lblDomain.Location = New-Object System.Drawing.Point(12, 12)
$topPanel.Controls.Add($lblDomain)

$script:cmbDomain = New-Object System.Windows.Forms.ComboBox
$script:cmbDomain.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$script:cmbDomain.Location = New-Object System.Drawing.Point(12, 34)
$script:cmbDomain.Width = 270
$topPanel.Controls.Add($script:cmbDomain)

$lblInactiveDays = New-Object System.Windows.Forms.Label
$lblInactiveDays.Text = 'Inactive days'
$lblInactiveDays.AutoSize = $true
$lblInactiveDays.Location = New-Object System.Drawing.Point(295, 12)
$topPanel.Controls.Add($lblInactiveDays)

$script:numInactiveDays = New-Object System.Windows.Forms.NumericUpDown
$script:numInactiveDays.Location = New-Object System.Drawing.Point(295, 34)
$script:numInactiveDays.Width = 95
$script:numInactiveDays.Minimum = 1
$script:numInactiveDays.Maximum = 3650
$script:numInactiveDays.Value = $DefaultInactiveDays
$topPanel.Controls.Add($script:numInactiveDays)

$script:btnScan = New-Object System.Windows.Forms.Button
$script:btnScan.Text = 'Run Scan'
$script:btnScan.Location = New-Object System.Drawing.Point(405, 31)
$script:btnScan.Size = New-Object System.Drawing.Size(100, 30)
$topPanel.Controls.Add($script:btnScan)

$script:btnDelete = New-Object System.Windows.Forms.Button
$script:btnDelete.Text = 'Execute selected'
$script:btnDelete.Enabled = $true
$script:btnDelete.Location = New-Object System.Drawing.Point(515, 31)
$script:btnDelete.Size = New-Object System.Drawing.Size(120, 30)
$topPanel.Controls.Add($script:btnDelete)

$script:chkCommit = New-Object System.Windows.Forms.CheckBox
$script:chkCommit.Text = 'COMMIT (permanent delete)'
$script:chkCommit.Checked = $false
$script:chkCommit.AutoSize = $true
$script:chkCommit.Location = New-Object System.Drawing.Point(515, 8)
$topPanel.Controls.Add($script:chkCommit)
$script:chkCommit.Add_CheckedChanged({
    if (-not $script:IsBusy) { $script:btnDelete.Enabled = $true }
    Write-AppLog -Level INFO -Message ("Operation mode: {0}" -f $(if ($script:chkCommit.Checked) { 'COMMIT-DELETE' } else { 'DRY-RUN' }))
})


$script:btnExport = New-Object System.Windows.Forms.Button
$script:btnExport.Text = 'Export CSV'
$script:btnExport.Location = New-Object System.Drawing.Point(645, 31)
$script:btnExport.Size = New-Object System.Drawing.Size(100, 30)
$topPanel.Controls.Add($script:btnExport)

$script:btnSelectAll = New-Object System.Windows.Forms.Button
$script:btnSelectAll.Text = 'Select All'
$script:btnSelectAll.Location = New-Object System.Drawing.Point(755, 31)
$script:btnSelectAll.Size = New-Object System.Drawing.Size(90, 30)
$topPanel.Controls.Add($script:btnSelectAll)

$script:btnClear = New-Object System.Windows.Forms.Button
$script:btnClear.Text = 'Clear'
$script:btnClear.Location = New-Object System.Drawing.Point(855, 31)
$script:btnClear.Size = New-Object System.Drawing.Size(80, 30)
$topPanel.Controls.Add($script:btnClear)

$script:btnRefreshDomains = New-Object System.Windows.Forms.Button
$script:btnRefreshDomains.Text = 'Refresh Domains'
$script:btnRefreshDomains.Location = New-Object System.Drawing.Point(945, 31)
$script:btnRefreshDomains.Size = New-Object System.Drawing.Size(120, 30)
$topPanel.Controls.Add($script:btnRefreshDomains)

$script:lblSummary = New-Object System.Windows.Forms.Label
$script:lblSummary.Text = 'Eligible: 0 | Candidates: 0 | Checked: 0'
$script:lblSummary.AutoSize = $true
$script:lblSummary.Location = New-Object System.Drawing.Point(1080, 39)
$topPanel.Controls.Add($script:lblSummary)

$splitContainer = New-Object System.Windows.Forms.SplitContainer
$splitContainer.Dock = [System.Windows.Forms.DockStyle]::Fill
$splitContainer.Orientation = [System.Windows.Forms.Orientation]::Horizontal
$splitContainer.SplitterDistance = 560
$splitContainer.Panel1MinSize = 300
$splitContainer.Panel2MinSize = 120
$script:form.Controls.Add($splitContainer)
$splitContainer.BringToFront()

$script:grid = New-Object System.Windows.Forms.DataGridView
$script:grid.Dock = [System.Windows.Forms.DockStyle]::Fill
$splitContainer.Panel1.Controls.Add($script:grid)
Initialize-ResultsGrid

$script:txtLog = New-Object System.Windows.Forms.TextBox
$script:txtLog.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:txtLog.Multiline = $true
$script:txtLog.ReadOnly = $true
$script:txtLog.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
$script:txtLog.WordWrap = $false
$script:txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$splitContainer.Panel2.Controls.Add($script:txtLog)

$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusStrip.SizingGrip = $false

$script:lblStatus = New-Object System.Windows.Forms.ToolStripStatusLabel
$script:lblStatus.Text = 'Starting...'
$script:lblStatus.Spring = $true
$script:lblStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
[void]$statusStrip.Items.Add($script:lblStatus)

$script:progressBar = New-Object System.Windows.Forms.ToolStripProgressBar
$script:progressBar.Minimum = 0
$script:progressBar.Maximum = 100
$script:progressBar.Value = 0
$script:progressBar.Width = 250
[void]$statusStrip.Items.Add($script:progressBar)

$script:form.Controls.Add($statusStrip)

# =====================================================================================
# Events
# =====================================================================================

$script:btnRefreshDomains.Add_Click({
    Load-ForestDomainsIntoGui
})

$script:btnScan.Add_Click({
    Start-InactiveComputerScan
})

$script:btnExport.Add_Click({
    Export-CurrentResults
})

$script:btnDelete.Add_Click({
    Remove-CheckedInactiveComputers
})

$script:btnSelectAll.Add_Click({
    if ($script:IsBusy) {
        return
    }

    foreach ($row in $script:grid.Rows) {
        if ($row.IsNewRow -or $null -eq $row.Tag) {
            continue
        }

        $row.Cells['Selected'].Value = $true
        $row.Tag.Selected = $true
    }

    Update-ResultsSummary
    $script:grid.Refresh()
})

$script:btnClear.Add_Click({
    if ($script:IsBusy) {
        return
    }

    foreach ($row in $script:grid.Rows) {
        if ($row.IsNewRow -or $null -eq $row.Tag) {
            continue
        }

        $row.Cells['Selected'].Value = $false
        $row.Tag.Selected = $false
    }

    Update-ResultsSummary
    $script:grid.Refresh()
})

$script:grid.Add_CurrentCellDirtyStateChanged({
    if ($script:grid.IsCurrentCellDirty) {
        [void]$script:grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
    }
})

$script:grid.Add_CellValueChanged({
    if ($_.RowIndex -ge 0 -and $_.ColumnIndex -eq $script:grid.Columns['Selected'].Index) {
        $row = $script:grid.Rows[$_.RowIndex]

        if ($null -ne $row.Tag) {
            $row.Tag.Selected = [bool]$row.Cells['Selected'].Value
        }

        Update-ResultsSummary
    }
})

$script:form.Add_FormClosing({
    if ($script:IsBusy) {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            $script:form,
            'An operation is in progress. Closing now may interrupt it. Close anyway?',
            'Operation in progress',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2
        )

        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            $_.Cancel = $true
        }
    }
})

$script:form.Add_Shown({
    try {
        Write-AppLog -Level INFO -Message '==== Session started ===='
        Write-AppLog -Level INFO -Message (
            "Application={0} | Version={1} | SessionId={2} | Operator={3} | Host={4}" -f
            $script:AppName,
            $script:AppVersion,
            $script:SessionId,
            [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
            $env:COMPUTERNAME
        )
        Write-AppLog -Level INFO -Message ("Script={0}" -f $script:ScriptPath)
        Write-AppLog -Level INFO -Message (
            "HostMode=HiddenConsole | ProcessId={0} | HiddenChild={1}" -f
            $PID,
            [bool]$HiddenChild
        )
        Write-AppLog -Level INFO -Message ("LogPath={0}" -f $script:LogPath)
        Write-AppLog -Level INFO -Message ("JournalPath={0}" -f $script:JournalPath)

        Load-ForestDomainsIntoGui
    }
    catch {
        Write-AppLog -Level ERROR -Message ("Startup failed. Error={0}" -f $_.Exception.Message)
        Show-ErrorMessage -Message $_.Exception.Message -Title 'Startup failed'
    }
})

# =====================================================================================
# Main
# =====================================================================================

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($script:form)

# End of script
