#requires -Version 5.1
<#
.SYNOPSIS
  Active Directory Inactive Computer Cleanup v1.0.4 - Enterprise workstation cleanup console.

.DESCRIPTION
  Enterprise Windows Forms GUI for discovering and removing inactive Active Directory
  computer objects across one domain or all domains in the current forest.

  Implements:
  - Automatic forest-domain discovery during application startup
  - Writable domain controller discovery and per-domain caching
  - Inactive computer discovery based exclusively on LastLogonDate
  - Configurable inactivity threshold with an enterprise default of 180 days
  - Manual checkbox selection; objects are never preselected for deletion
  - CSV scan export and mandatory pre-deletion evidence export
  - Live inactivity revalidation immediately before each deletion
  - Protected-from-accidental-deletion safe skip
  - Remove-ADComputer deletion through the authoritative writable domain controller
  - Runtime log panel, status bar, progress indicator and deletion journal
  - Hidden-console bootstrap for GUI-first execution

  Eligibility rule:

      InactiveDays >= configured threshold

  Objects without LastLogonDate are not classified as eligible because the required
  inactivity evidence is unavailable.

.AUTHOR
  Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
  2026-07-28-v1.0.4-ENTERPRISE-EDITION

.REQUIREMENTS
  - Windows PowerShell 5.1
  - RSAT ActiveDirectory PowerShell module
  - Appropriate Active Directory read and delete permissions
  - Network and DNS connectivity to the selected forest domains

.NOTES
  Validate the tool in a controlled organizational unit before production use.
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
$script:AppVersion = '1.0.4'
$script:SessionId = [guid]::NewGuid().ToString()
$script:CurrentResults = New-Object System.Collections.ArrayList
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
        $script:numInactiveDays
    )) {
        if ($control -and -not $control.IsDisposed) {
            $control.Enabled = -not $Busy
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

function Convert-ToInactiveComputerRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Computer,

        [Parameter(Mandatory)]
        [string]$DomainName,

        [Parameter(Mandatory)]
        [string]$DomainController,

        [Parameter(Mandatory)]
        [datetime]$ReferenceTime,

        [Parameter(Mandatory)]
        [int]$ThresholdDays
    )

    if (-not $Computer.LastLogonDate) {
        return $null
    }

    $lastLogon = [datetime]$Computer.LastLogonDate
    $inactiveDays = [int][Math]::Floor(($ReferenceTime - $lastLogon).TotalDays)

    if ($inactiveDays -lt $ThresholdDays) {
        return $null
    }

    [pscustomobject]@{
        Selected                       = $false
        Domain                         = $DomainName
        DomainController               = $DomainController
        Name                           = [string]$Computer.Name
        DNSHostName                    = [string]$Computer.DNSHostName
        Enabled                        = [bool]$Computer.Enabled
        OperatingSystem                = [string]$Computer.OperatingSystem
        LastLogonDate                  = $lastLogon
        InactiveDays                   = $inactiveDays
        Status                         = 'ELIGIBLE_BY_INACTIVITY'
        ProtectedFromAccidentalDeletion = [bool]$Computer.ProtectedFromAccidentalDeletion
        DistinguishedName              = [string]$Computer.DistinguishedName
        ObjectGuid                     = [guid]$Computer.ObjectGuid
        WhenCreated                    = $Computer.WhenCreated
    }
}

function Get-InactiveComputersFromDomain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DomainName,

        [Parameter(Mandatory)]
        [int]$InactiveDays
    )

    $referenceTime = Get-Date
    $cutoff = $referenceTime.AddDays(-$InactiveDays)
    $cutoffFileTime = $cutoff.ToFileTimeUtc()
    $dc = Resolve-WritableDomainController -DomainName $DomainName

    Write-AppLog -Level INFO -Message (
        "Inactive computer scan started. Domain={0} | DC={1} | ThresholdDays={2} | Cutoff={3:o}" -f
        $DomainName,
        $dc,
        $InactiveDays,
        $cutoff
    )

    # Excludes domain controllers through SERVER_TRUST_ACCOUNT (8192).
    # lastLogonTimestamp drives LastLogonDate in the AD module.
    $ldapFilter = "(&(objectCategory=computer)(lastLogonTimestamp<=$cutoffFileTime)(!(userAccountControl:1.2.840.113556.1.4.803:=8192)))"

    $properties = @(
        'DNSHostName',
        'Enabled',
        'OperatingSystem',
        'LastLogonDate',
        'LastLogonTimestamp',
        'ObjectGuid',
        'ProtectedFromAccidentalDeletion',
        'WhenCreated'
    )

    $rawComputers = @(
        Get-ADComputer `
            -LDAPFilter $ldapFilter `
            -Server $dc `
            -Properties $properties `
            -ResultPageSize 500 `
            -ResultSetSize $null `
            -ErrorAction Stop
    )

    $records = New-Object System.Collections.ArrayList

    foreach ($computer in $rawComputers) {
        $record = Convert-ToInactiveComputerRecord `
            -Computer $computer `
            -DomainName $DomainName `
            -DomainController $dc `
            -ReferenceTime $referenceTime `
            -ThresholdDays $InactiveDays

        if ($null -ne $record) {
            [void]$records.Add($record)
        }
    }

    Write-AppLog -Level SUCCESS -Message (
        "Inactive computer scan completed. Domain={0} | DC={1} | Eligible={2}" -f
        $DomainName,
        $dc,
        $records.Count
    )

    return @($records)
}

function Get-LiveComputerValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Record,

        [Parameter(Mandatory)]
        [int]$InactiveDays
    )

    $dc = [string]$Record.DomainController

    if ([string]::IsNullOrWhiteSpace($dc)) {
        $dc = Resolve-WritableDomainController -DomainName ([string]$Record.Domain)
    }

    $properties = @(
        'LastLogonDate',
        'LastLogonTimestamp',
        'ProtectedFromAccidentalDeletion',
        'ObjectGuid',
        'DistinguishedName'
    )

    $computer = Get-ADComputer `
        -Identity ([guid]$Record.ObjectGuid) `
        -Server $dc `
        -Properties $properties `
        -ErrorAction Stop

    if (-not $computer.LastLogonDate) {
        return [pscustomobject]@{
            IsEligible   = $false
            Reason       = 'LastLogonDate is unavailable during live validation.'
            Computer     = $computer
            InactiveDays = $null
            Server       = $dc
        }
    }

    $currentInactiveDays = [int][Math]::Floor(((Get-Date) - [datetime]$computer.LastLogonDate).TotalDays)

    if ($currentInactiveDays -lt $InactiveDays) {
        return [pscustomobject]@{
            IsEligible   = $false
            Reason       = "Object is no longer inactive for the configured threshold. CurrentInactiveDays=$currentInactiveDays"
            Computer     = $computer
            InactiveDays = $currentInactiveDays
            Server       = $dc
        }
    }

    return [pscustomobject]@{
        IsEligible   = $true
        Reason       = 'Eligible by current inactivity value.'
        Computer     = $computer
        InactiveDays = $currentInactiveDays
        Server       = $dc
    }
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
            OperatingSystem,
            LastLogonDate,
            InactiveDays,
            Status,
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
    $selectColumn.HeaderText = 'Delete'
    $selectColumn.DataPropertyName = 'Selected'
    $selectColumn.Width = 55
    $selectColumn.ReadOnly = $false
    [void]$script:grid.Columns.Add($selectColumn)

    $columns = @(
        @{ Name = 'Domain'; Header = 'Domain'; Property = 'Domain'; Width = 170 },
        @{ Name = 'Name'; Header = 'Computer'; Property = 'Name'; Width = 145 },
        @{ Name = 'Enabled'; Header = 'Enabled'; Property = 'Enabled'; Width = 65 },
        @{ Name = 'OperatingSystem'; Header = 'Operating System'; Property = 'OperatingSystem'; Width = 210 },
        @{ Name = 'LastLogonDate'; Header = 'Last Logon'; Property = 'LastLogonDate'; Width = 135 },
        @{ Name = 'InactiveDays'; Header = 'Inactive Days'; Property = 'InactiveDays'; Width = 90 },
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

    $script:lblSummary.Text = 'Objects: {0} | Checked: {1}' -f `
        $script:CurrentResults.Count,
        $checkedCount
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
            $row.Cells['OperatingSystem'].Value = [string]$record.OperatingSystem
            $row.Cells['LastLogonDate'].Value = $record.LastLogonDate
            $row.Cells['InactiveDays'].Value = [int]$record.InactiveDays
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
    Refresh-ResultsGrid

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
                    [void]$script:CurrentResults.Add($record)
                }
            }
            catch {
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

        Write-AppLog -Level SUCCESS -Message (
            "Scan completed. Scope={0} | ThresholdDays={1} | EligibleObjects={2}" -f
            $selectedScope,
            $inactiveDays,
            $script:CurrentResults.Count
        )

        Set-UiStatus `
            -Text ("Scan completed. Eligible inactive computers: {0}" -f $script:CurrentResults.Count) `
            -Percent 100
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
    [CmdletBinding()]
    param()

    if ($script:IsBusy) {
        return
    }

    [object[]]$selectedRecords = @(Get-CheckedRecords | Where-Object {
        $null -ne $_ -and
        $null -ne $_.PSObject.Properties['Name'] -and
        $null -ne $_.PSObject.Properties['ObjectGuid'] -and
        $null -ne $_.PSObject.Properties['Domain']
    })

    if ($selectedRecords.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            $script:form,
            'Check at least one computer object before starting deletion.',
            'No objects selected',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    $inactiveDays = [int]$script:numInactiveDays.Value

    $confirmationText = @"
You are about to permanently remove $($selectedRecords.Count) Active Directory computer object(s).

Each object will be revalidated immediately before deletion.

Required live rule:
InactiveDays >= $inactiveDays

Objects protected from accidental deletion will fail safely and will not be unprotected automatically.

Continue?
"@

    $answer = [System.Windows.Forms.MessageBox]::Show(
        $script:form,
        $confirmationText,
        'Confirm Active Directory deletion',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )

    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        Write-AppLog -Level WARNING -Message 'Deletion cancelled by operator before evidence export.'
        return
    }

    Set-BusyState -Busy $true

    $deleted = 0
    $skipped = 0
    $failed = 0
    $evidencePath = $null

    try {
        Set-UiStatus -Text 'Exporting pre-deletion evidence...' -Percent 0
        Write-AppLog -Level INFO -Message ("Pre-deletion pipeline started. Selected={0}" -f $selectedRecords.Count)

        $evidencePath = Export-RecordsToCsv -Records $selectedRecords -Purpose 'predelete-evidence'

        Write-AppLog -Level SUCCESS -Message (
            "Pre-deletion evidence completed. Path={0} | Selected={1}" -f
            $evidencePath,
            $selectedRecords.Count
        )

        $index = 0

        foreach ($record in $selectedRecords) {
            $index++

            if (
                $null -eq $record -or
                $null -eq $record.PSObject.Properties['Name'] -or
                $null -eq $record.PSObject.Properties['ObjectGuid'] -or
                $null -eq $record.PSObject.Properties['Domain']
            ) {
                $failed++
                $recordType = if ($null -eq $record) { '<null>' } else { $record.GetType().FullName }

                Write-AppLog -Level ERROR -Message (
                    "Invalid deletion record rejected. Index={0}/{1} | RecordType={2}" -f
                    $index,
                    $selectedRecords.Count,
                    $recordType
                )

                continue
            }

            $percent = [int](($index - 1) / [double]$selectedRecords.Count * 100)

            Set-UiStatus `
                -Text ("Validating and deleting {0} of {1}: {2}" -f $index, $selectedRecords.Count, $record.Name) `
                -Percent $percent

            Write-AppLog -Level INFO -Message (
                "Deletion item started. Index={0}/{1} | Domain={2} | DC={3} | Name={4} | ObjectGuid={5} | DN={6}" -f
                $index,
                $selectedRecords.Count,
                $record.Domain,
                $record.DomainController,
                $record.Name,
                $record.ObjectGuid,
                $record.DistinguishedName
            )

            try {
                Write-AppLog -Level INFO -Message (
                    "Live revalidation started. Domain={0} | DC={1} | Name={2} | ObjectGuid={3}" -f
                    $record.Domain,
                    $record.DomainController,
                    $record.Name,
                    $record.ObjectGuid
                )

                $validation = Get-LiveComputerValidation -Record $record -InactiveDays $inactiveDays

                Write-AppLog -Level INFO -Message (
                    "Live revalidation completed. Name={0} | Eligible={1} | CurrentInactiveDays={2} | Reason={3}" -f
                    $record.Name,
                    $validation.IsEligible,
                    $validation.InactiveDays,
                    $validation.Reason
                )

                if (-not $validation.IsEligible) {
                    $skipped++

                    Add-DeletionJournalEntry `
                        -Domain $record.Domain `
                        -DomainController $validation.Server `
                        -Name $record.Name `
                        -DistinguishedName $record.DistinguishedName `
                        -ObjectGuid ([string]$record.ObjectGuid) `
                        -InactiveDays $validation.InactiveDays `
                        -Result 'SKIPPED' `
                        -Details $validation.Reason

                    Write-AppLog -Level WARNING -Message (
                        "Deletion skipped after live validation. Name={0} | Reason={1}" -f
                        $record.Name,
                        $validation.Reason
                    )

                    continue
                }

                if ($validation.Computer.ProtectedFromAccidentalDeletion) {
                    $skipped++
                    $reason = 'Object is protected from accidental deletion. Protection was not changed automatically.'

                    Add-DeletionJournalEntry `
                        -Domain $record.Domain `
                        -DomainController $validation.Server `
                        -Name $record.Name `
                        -DistinguishedName $validation.Computer.DistinguishedName `
                        -ObjectGuid ([string]$validation.Computer.ObjectGuid) `
                        -InactiveDays $validation.InactiveDays `
                        -Result 'SKIPPED_PROTECTED' `
                        -Details $reason

                    Write-AppLog -Level WARNING -Message (
                        "Deletion skipped. Name={0} | Reason={1}" -f
                        $record.Name,
                        $reason
                    )

                    continue
                }

                Write-AppLog -Level WARNING -Message (
                    "Remove-ADComputer invocation starting. Domain={0} | DC={1} | Name={2} | ObjectGuid={3} | DN={4}" -f
                    $record.Domain,
                    $validation.Server,
                    $record.Name,
                    $validation.Computer.ObjectGuid,
                    $validation.Computer.DistinguishedName
                )

                Remove-ADComputer `
                    -Identity $validation.Computer.ObjectGuid `
                    -Server $validation.Server `
                    -Confirm:$false `
                    -ErrorAction Stop

                $deleted++

                Add-DeletionJournalEntry `
                    -Domain $record.Domain `
                    -DomainController $validation.Server `
                    -Name $record.Name `
                    -DistinguishedName $validation.Computer.DistinguishedName `
                    -ObjectGuid ([string]$validation.Computer.ObjectGuid) `
                    -InactiveDays $validation.InactiveDays `
                    -Result 'DELETED' `
                    -Details 'Computer object removed successfully by Remove-ADComputer.'

                Write-AppLog -Level SUCCESS -Message (
                    "Computer object deleted. Domain={0} | DC={1} | Name={2} | ObjectGuid={3} | DN={4}" -f
                    $record.Domain,
                    $validation.Server,
                    $record.Name,
                    $validation.Computer.ObjectGuid,
                    $validation.Computer.DistinguishedName
                )

                [void]$script:CurrentResults.Remove($record)
            }
            catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
                $skipped++
                $reason = 'Object no longer exists in Active Directory.'

                Add-DeletionJournalEntry `
                    -Domain $record.Domain `
                    -DomainController $record.DomainController `
                    -Name $record.Name `
                    -DistinguishedName $record.DistinguishedName `
                    -ObjectGuid ([string]$record.ObjectGuid) `
                    -InactiveDays $null `
                    -Result 'SKIPPED_NOT_FOUND' `
                    -Details $reason

                Write-AppLog -Level WARNING -Message (
                    "Deletion skipped. Name={0} | Reason={1}" -f
                    $record.Name,
                    $reason
                )

                [void]$script:CurrentResults.Remove($record)
            }
            catch {
                $failed++
                $details = $_.Exception.Message

                Add-DeletionJournalEntry `
                    -Domain $record.Domain `
                    -DomainController $record.DomainController `
                    -Name $record.Name `
                    -DistinguishedName $record.DistinguishedName `
                    -ObjectGuid ([string]$record.ObjectGuid) `
                    -InactiveDays $record.InactiveDays `
                    -Result 'FAILED' `
                    -Details $details

                Write-AppLog -Level ERROR -Message (
                    "Deletion failed. Domain={0} | DC={1} | Name={2} | ObjectGuid={3} | Error={4}" -f
                    $record.Domain,
                    $record.DomainController,
                    $record.Name,
                    $record.ObjectGuid,
                    $details
                )
            }

            Refresh-ResultsGrid
        }

        Refresh-ResultsGrid

        $summary = @"
Deletion operation completed.

Selected: $($selectedRecords.Count)
Deleted:  $deleted
Skipped:  $skipped
Failed:   $failed

Evidence:
$evidencePath

Journal:
$($script:JournalPath)
"@

        Write-AppLog -Level SUCCESS -Message (
            "Deletion batch completed. Selected={0} | Deleted={1} | Skipped={2} | Failed={3}" -f
            $selectedRecords.Count,
            $deleted,
            $skipped,
            $failed
        )

        Set-UiStatus `
            -Text ("Deletion completed. Deleted={0} | Skipped={1} | Failed={2}" -f $deleted, $skipped, $failed) `
            -Percent 100

        [System.Windows.Forms.MessageBox]::Show(
            $script:form,
            $summary,
            'Deletion completed',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    catch {
        Write-AppLog -Level ERROR -Message ("Deletion pipeline failed before completion. Error={0}" -f $_.Exception.Message)
        Set-UiStatus -Text 'Deletion pipeline failed.' -Percent 0
        Show-ErrorMessage -Message $_.Exception.Message -Title 'Deletion pipeline failed'
    }
    finally {
        Set-BusyState -Busy $false
    }
}

# =====================================================================================
# GUI construction
# =====================================================================================

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
$script:btnDelete.Text = 'Delete Checked'
$script:btnDelete.Location = New-Object System.Drawing.Point(515, 31)
$script:btnDelete.Size = New-Object System.Drawing.Size(120, 30)
$topPanel.Controls.Add($script:btnDelete)

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
$script:lblSummary.Text = 'Objects: 0 | Checked: 0'
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
