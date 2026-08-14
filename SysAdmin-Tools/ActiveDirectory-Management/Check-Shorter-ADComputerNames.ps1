<#
.SYNOPSIS
  Active Directory Computer Name Length Audit v2.0.0 Enterprise Edition.

.DESCRIPTION
  Enterprise Windows Forms audit tool for identifying enabled Active Directory
  workstation computer accounts whose Name attribute is shorter than a configured
  minimum length.

  The tool:
  - Supports Windows PowerShell 5.1 and Windows Server 2019
  - Hides the PowerShell console before importing the ActiveDirectory module
  - Supports Current Domain, Specific Domain, and All Domains in Forest scopes
  - Uses explicit -Server targeting for every Active Directory computer query
  - Uses Active Directory domain context rather than legacy WMI domain discovery
  - Excludes computer accounts whose OperatingSystem contains "Server"
  - Includes only enabled computer accounts
  - Provides a configurable minimum-name-length threshold (default: 15)
  - Provides client-side filtering across every displayed result column
  - Provides ascending/descending sorting by clicking column headers
  - Retains complete and filtered datasets separately
  - Exports either all retrieved results or only the currently displayed results
  - Produces timestamped audit logs in C:\Logs-TEMP
  - Does not modify Active Directory

  IMPORTANT:
  15 characters is the legacy NetBIOS computer-name maximum, not a universal minimum
  naming requirement. The default threshold is retained as an administrative audit
  value and should reflect the organization's actual naming standard.

.AUTHOR
  Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
  2026-08-14-v2.0.0-ENTERPRISE-EDITION

.REQUIREMENTS
  - Windows PowerShell 5.1
  - Windows Server 2019
  - RSAT ActiveDirectory PowerShell module
  - Network connectivity and permissions to query the selected Active Directory domain(s)
#>

#Requires -Version 5.1

[CmdletBinding()]
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
            if ($consolePtr -ne [IntPtr]::Zero) {
                [void][ConsoleControl.Win32ShowWindowAsync]::ShowWindowAsync($consolePtr, 0)
            }
        } catch { }
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw 'The ActiveDirectory PowerShell module is not installed or available.'
    }

    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Error "Failed to initialize required components: $($_.Exception.Message)"
    return
}

# =====================================================================================
# Globals
# =====================================================================================
$script:ScriptName       = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:LogRoot          = 'C:\Logs-TEMP'
$script:RunStamp         = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:LogFile          = Join-Path $script:LogRoot "$($script:ScriptName)-$($script:RunStamp).log"

$script:SearchResults    = @()
$script:DisplayedResults = @()
$script:ForestDomains    = @()
$script:SortColumn       = -1
$script:SortDescending   = $false

$script:listView         = $null
$script:txtRuntimeLog    = $null
$script:statusMain       = $null

if (-not (Test-Path -LiteralPath $script:LogRoot)) {
    New-Item -ItemType Directory -Path $script:LogRoot -Force | Out-Null
}

# =====================================================================================
# Basic helpers
# =====================================================================================
function Write-AppLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO','SUCCESS','WARN','ERROR')][string]$Level = 'INFO'
    )

    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message

    try {
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Warning "Unable to write log file: $($_.Exception.Message)"
    }

    if ($script:txtRuntimeLog -and -not $script:txtRuntimeLog.IsDisposed) {
        $script:txtRuntimeLog.AppendText($line + [Environment]::NewLine)
        $script:txtRuntimeLog.SelectionStart = $script:txtRuntimeLog.Text.Length
        $script:txtRuntimeLog.ScrollToCaret()
    } elseif ($ShowConsole) {
        Write-Host $line
    }
}

function Show-AppMessage {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Information','Warning','Error')][string]$Type = 'Information'
    )

    switch ($Type) {
        'Error' {
            Write-AppLog -Message $Message -Level ERROR
            [void][System.Windows.Forms.MessageBox]::Show(
                $Message, 'Error',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
        'Warning' {
            Write-AppLog -Message $Message -Level WARN
            [void][System.Windows.Forms.MessageBox]::Show(
                $Message, 'Warning',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
        }
        default {
            Write-AppLog -Message $Message -Level INFO
            [void][System.Windows.Forms.MessageBox]::Show(
                $Message, 'Information',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
    }
}

function Set-AppStatus {
    param([Parameter(Mandatory = $true)][string]$Text)

    if ($script:statusMain -and -not $script:statusMain.IsDisposed) {
        $script:statusMain.Text = $Text
        [System.Windows.Forms.Application]::DoEvents()
    }
}

# =====================================================================================
# Active Directory discovery
# =====================================================================================
function Get-ForestDomains {
    try {
        $forest = Get-ADForest -ErrorAction Stop
        return @($forest.Domains | Sort-Object)
    } catch {
        throw "Unable to discover Active Directory forest domains. $($_.Exception.Message)"
    }
}

function Get-CurrentDomainDnsRoot {
    try {
        $domain = Get-ADDomain -ErrorAction Stop
        return [string]$domain.DNSRoot
    } catch {
        throw "Unable to determine the current Active Directory domain. $($_.Exception.Message)"
    }
}

function Test-DomainTarget {
    param([Parameter(Mandatory = $true)][string]$Server)

    try {
        $domain = Get-ADDomain -Server $Server -ErrorAction Stop
        Write-AppLog -Message ("Domain pre-flight succeeded: {0} ({1})" -f
            $domain.DNSRoot, $domain.NetBIOSName) -Level SUCCESS
        return $true
    } catch {
        Write-AppLog -Message "Domain pre-flight failed for '$Server': $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Get-SearchDomains {
    param(
        [Parameter(Mandatory = $true)][string]$Scope,
        [AllowEmptyString()][string]$SpecificDomain
    )

    switch ($Scope) {
        'Current Domain' {
            return @((Get-CurrentDomainDnsRoot))
        }
        'Specific Domain' {
            if ([string]::IsNullOrWhiteSpace($SpecificDomain)) {
                throw 'Select a specific domain.'
            }
            return @($SpecificDomain)
        }
        'All Domains in Forest' {
            return @($script:ForestDomains)
        }
        default {
            throw "Unsupported search scope '$Scope'."
        }
    }
}

function Find-ShortADComputerNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$Domains,
        [Parameter(Mandatory = $true)][ValidateRange(1,63)][int]$MinimumLength
    )

    $results = New-Object System.Collections.ArrayList
    $failedDomains = New-Object System.Collections.ArrayList

    foreach ($domain in $Domains) {
        Set-AppStatus "Searching $domain..."
        Write-AppLog -Message "Searching '$domain' for enabled workstation computer accounts with Name length < $MinimumLength."

        if (-not (Test-DomainTarget -Server $domain)) {
            [void]$failedDomains.Add($domain)
            continue
        }

        try {
            # Keep the AD-side filter simple and deterministic. Name length is evaluated
            # client-side because AD LDAP filters do not provide a reliable length operator.
            $computers = @(
                Get-ADComputer -Server $domain `
                    -Filter "Enabled -eq 'True'" `
                    -Properties DNSHostName, OperatingSystem, Enabled, DistinguishedName, ObjectGUID `
                    -ErrorAction Stop |
                Where-Object {
                    $_.OperatingSystem -notlike '*Server*' -and
                    -not [string]::IsNullOrWhiteSpace([string]$_.Name) -and
                    $_.Name.Length -lt $MinimumLength
                }
            )

            foreach ($computer in $computers) {
                [void]$results.Add([pscustomobject]@{
                    Name              = [string]$computer.Name
                    CharactersLength  = [int]$computer.Name.Length
                    DNSHostName       = [string]$computer.DNSHostName
                    OperatingSystem   = [string]$computer.OperatingSystem
                    Enabled           = [bool]$computer.Enabled
                    DomainFQDN        = [string]$domain
                    DistinguishedName = [string]$computer.DistinguishedName
                    ObjectGUID        = [Guid]$computer.ObjectGUID
                })
            }

            Write-AppLog -Message ("Domain '{0}' completed. Matching workstation accounts: {1}" -f
                $domain, $computers.Count) -Level SUCCESS
        } catch {
            [void]$failedDomains.Add($domain)
            Write-AppLog -Message "Search failed in '$domain': $($_.Exception.Message)" -Level ERROR
        }
    }

    return [pscustomobject]@{
        Results       = @($results)
        FailedDomains = @($failedDomains)
    }
}

# =====================================================================================
# Searchable / sortable results browser
# =====================================================================================
function Set-ResultListViewData {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Results
    )

    $script:listView.BeginUpdate()
    try {
        $script:listView.Items.Clear()

        foreach ($row in $Results) {
            $item = New-Object System.Windows.Forms.ListViewItem([string]$row.Name)
            [void]$item.SubItems.Add([string]$row.CharactersLength)
            [void]$item.SubItems.Add([string]$row.DNSHostName)
            [void]$item.SubItems.Add([string]$row.OperatingSystem)
            [void]$item.SubItems.Add([string]$row.Enabled)
            [void]$item.SubItems.Add([string]$row.DomainFQDN)
            [void]$item.SubItems.Add([string]$row.DistinguishedName)
            $item.Tag = $row
            [void]$script:listView.Items.Add($item)
        }
    } finally {
        $script:listView.EndUpdate()
    }
}

function Test-ResultMatchesFilter {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$FilterText
    )

    if ([string]::IsNullOrWhiteSpace($FilterText)) {
        return $true
    }

    $needle = $FilterText.Trim()
    $values = @(
        [string]$Result.Name,
        [string]$Result.CharactersLength,
        [string]$Result.DNSHostName,
        [string]$Result.OperatingSystem,
        [string]$Result.Enabled,
        [string]$Result.DomainFQDN,
        [string]$Result.DistinguishedName
    )

    foreach ($value in $values) {
        if ($null -ne $value -and
            $value.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }

    return $false
}

function Apply-ResultsFilter {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$FilterText)

    $filtered = @(
        $script:SearchResults | Where-Object {
            Test-ResultMatchesFilter -Result $_ -FilterText $FilterText
        }
    )

    $script:DisplayedResults = $filtered
    Set-ResultListViewData -Results $filtered

    Set-AppStatus ("Displayed {0} of {1} result(s)." -f
        $filtered.Count, $script:SearchResults.Count)
}

function Sort-SearchResults {
    param(
        [Parameter(Mandatory = $true)][int]$ColumnIndex,
        [Parameter(Mandatory = $true)][bool]$Descending
    )

    switch ($ColumnIndex) {
        0 { $property = 'Name' }
        1 { $property = 'CharactersLength' }
        2 { $property = 'DNSHostName' }
        3 { $property = 'OperatingSystem' }
        4 { $property = 'Enabled' }
        5 { $property = 'DomainFQDN' }
        6 { $property = 'DistinguishedName' }
        default { $property = 'Name' }
    }

    $script:SearchResults = @(
        $script:SearchResults |
        Sort-Object -Property $property -Descending:$Descending
    )
}

# =====================================================================================
# Export
# =====================================================================================
function Export-AuditResults {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Data,
        [Parameter(Mandatory = $true)][string]$SuggestedName
    )

    if ($Data.Count -eq 0) {
        Show-AppMessage -Message 'No data is available to export.' -Type Information
        return
    }

    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = 'CSV files (*.csv)|*.csv'
    $dialog.Title = 'Export AD Computer Name Audit'
    $dialog.FileName = $SuggestedName
    $dialog.AddExtension = $true
    $dialog.DefaultExt = 'csv'

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    try {
        $Data |
            Select-Object Name, CharactersLength, DNSHostName, OperatingSystem, Enabled,
                DomainFQDN, DistinguishedName, ObjectGUID |
            Export-Csv -LiteralPath $dialog.FileName -NoTypeInformation -Delimiter ';' -Encoding UTF8

        Write-AppLog -Message ("Exported {0} row(s) to '{1}'." -f $Data.Count, $dialog.FileName) -Level SUCCESS
        [void][System.Windows.Forms.MessageBox]::Show(
            "Successfully exported $($Data.Count) row(s).`r`n`r`n$($dialog.FileName)",
            'Export Complete',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    } catch {
        Show-AppMessage -Message "Export failed: $($_.Exception.Message)" -Type Error
    }
}

# =====================================================================================
# GUI
# =====================================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'AD Computer Name Length Audit - Enterprise Edition'
$form.Size = New-Object System.Drawing.Size(1240, 800)
$form.MinimumSize = New-Object System.Drawing.Size(1000, 700)
$form.StartPosition = 'CenterScreen'

$main = New-Object System.Windows.Forms.TableLayoutPanel
$main.Dock = 'Fill'
$main.Padding = New-Object System.Windows.Forms.Padding(10)
$main.ColumnCount = 1
$main.RowCount = 8
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 65)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 35)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$form.Controls.Add($main)

$scopePanel = New-Object System.Windows.Forms.FlowLayoutPanel
$scopePanel.Dock = 'Fill'
$scopePanel.AutoSize = $true
$scopePanel.WrapContents = $false

$labelScope = New-Object System.Windows.Forms.Label
$labelScope.Text = 'Search Scope:'
$labelScope.AutoSize = $true
$labelScope.Margin = New-Object System.Windows.Forms.Padding(3, 7, 3, 3)
$scopePanel.Controls.Add($labelScope)

$comboScope = New-Object System.Windows.Forms.ComboBox
$comboScope.Width = 190
$comboScope.DropDownStyle = 'DropDownList'
[void]$comboScope.Items.AddRange(@('Current Domain','Specific Domain','All Domains in Forest'))
$comboScope.SelectedIndex = 0
$scopePanel.Controls.Add($comboScope)

$labelDomain = New-Object System.Windows.Forms.Label
$labelDomain.Text = 'Domain:'
$labelDomain.AutoSize = $true
$labelDomain.Margin = New-Object System.Windows.Forms.Padding(20, 7, 3, 3)
$scopePanel.Controls.Add($labelDomain)

$comboDomain = New-Object System.Windows.Forms.ComboBox
$comboDomain.Width = 280
$comboDomain.DropDownStyle = 'DropDownList'
$comboDomain.Enabled = $false
$scopePanel.Controls.Add($comboDomain)

$labelLength = New-Object System.Windows.Forms.Label
$labelLength.Text = 'Minimum Length:'
$labelLength.AutoSize = $true
$labelLength.Margin = New-Object System.Windows.Forms.Padding(20, 7, 3, 3)
$scopePanel.Controls.Add($labelLength)

$numericLength = New-Object System.Windows.Forms.NumericUpDown
$numericLength.Minimum = 1
$numericLength.Maximum = 63
$numericLength.Value = 15
$numericLength.Width = 65
$scopePanel.Controls.Add($numericLength)

$buttonSearch = New-Object System.Windows.Forms.Button
$buttonSearch.Text = 'Search'
$buttonSearch.Width = 100
$scopePanel.Controls.Add($buttonSearch)

$main.Controls.Add($scopePanel, 0, 0)

$filterPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$filterPanel.Dock = 'Fill'
$filterPanel.AutoSize = $true
$filterPanel.WrapContents = $false

$labelFilter = New-Object System.Windows.Forms.Label
$labelFilter.Text = 'Filter displayed columns:'
$labelFilter.AutoSize = $true
$labelFilter.Margin = New-Object System.Windows.Forms.Padding(3, 7, 3, 3)
$filterPanel.Controls.Add($labelFilter)

$textFilter = New-Object System.Windows.Forms.TextBox
$textFilter.Width = 550
$filterPanel.Controls.Add($textFilter)

$buttonClearFilter = New-Object System.Windows.Forms.Button
$buttonClearFilter.Text = 'Clear Filter'
$buttonClearFilter.Width = 100
$filterPanel.Controls.Add($buttonClearFilter)

$main.Controls.Add($filterPanel, 0, 1)

$listView = New-Object System.Windows.Forms.ListView
$listView.Dock = 'Fill'
$listView.View = 'Details'
$listView.FullRowSelect = $true
$listView.GridLines = $true
$listView.MultiSelect = $true
$listView.HideSelection = $false
[void]$listView.Columns.Add('Name', 150)
[void]$listView.Columns.Add('Length', 70)
[void]$listView.Columns.Add('DNSHostName', 220)
[void]$listView.Columns.Add('Operating System', 220)
[void]$listView.Columns.Add('Enabled', 70)
[void]$listView.Columns.Add('Domain FQDN', 180)
[void]$listView.Columns.Add('DistinguishedName', 430)
$script:listView = $listView
$main.Controls.Add($listView, 0, 2)

$summaryLabel = New-Object System.Windows.Forms.Label
$summaryLabel.AutoSize = $true
$summaryLabel.Text = 'No audit has been run.'
$main.Controls.Add($summaryLabel, 0, 3)

$buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$buttonPanel.Dock = 'Fill'
$buttonPanel.AutoSize = $true
$buttonPanel.WrapContents = $false

$buttonExportDisplayed = New-Object System.Windows.Forms.Button
$buttonExportDisplayed.Text = 'Export Displayed'
$buttonExportDisplayed.Width = 130
$buttonPanel.Controls.Add($buttonExportDisplayed)

$buttonExportAll = New-Object System.Windows.Forms.Button
$buttonExportAll.Text = 'Export All Results'
$buttonExportAll.Width = 130
$buttonPanel.Controls.Add($buttonExportAll)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Text = 'Close'
$buttonClose.Width = 100
$buttonPanel.Controls.Add($buttonClose)

$main.Controls.Add($buttonPanel, 0, 4)

$noteLabel = New-Object System.Windows.Forms.Label
$noteLabel.AutoSize = $true
$noteLabel.MaximumSize = New-Object System.Drawing.Size(1150, 0)
$noteLabel.Text = 'Audit rule: enabled AD computer accounts whose OperatingSystem does not contain "Server" and whose Name length is below the configured threshold. The default threshold of 15 is an organizational audit value, not a Windows minimum requirement.'
$main.Controls.Add($noteLabel, 0, 5)

$txtRuntimeLog = New-Object System.Windows.Forms.TextBox
$txtRuntimeLog.Dock = 'Fill'
$txtRuntimeLog.Multiline = $true
$txtRuntimeLog.ReadOnly = $true
$txtRuntimeLog.ScrollBars = 'Vertical'
$txtRuntimeLog.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$script:txtRuntimeLog = $txtRuntimeLog
$main.Controls.Add($txtRuntimeLog, 0, 6)

$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusMain = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusMain.Spring = $true
$statusMain.TextAlign = 'MiddleLeft'
$statusMain.Text = 'Ready'
$script:statusMain = $statusMain
[void]$statusStrip.Items.Add($statusMain)

$statusLog = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLog.Text = "Log: $($script:LogFile)"
[void]$statusStrip.Items.Add($statusLog)

$main.Controls.Add($statusStrip, 0, 7)

# =====================================================================================
# GUI event handlers
# =====================================================================================
$comboScope.Add_SelectedIndexChanged({
    $comboDomain.Enabled = ($comboScope.SelectedItem -eq 'Specific Domain')
})

$textFilter.Add_TextChanged({
    try {
        Apply-ResultsFilter -FilterText $textFilter.Text
        $summaryLabel.Text = "Displayed: $($script:DisplayedResults.Count) | Total matches: $($script:SearchResults.Count)"
    } catch {
        Write-AppLog -Message "Display filter failed: $($_.Exception.Message)" -Level ERROR
        Set-AppStatus 'Display filter failed.'
    }
})

$buttonClearFilter.Add_Click({
    $textFilter.Clear()
})

$listView.Add_ColumnClick({
    param($sender, $eventArgs)

    if ($script:SortColumn -eq $eventArgs.Column) {
        $script:SortDescending = -not $script:SortDescending
    } else {
        $script:SortColumn = $eventArgs.Column
        $script:SortDescending = $false
    }

    Sort-SearchResults -ColumnIndex $script:SortColumn -Descending $script:SortDescending
    Apply-ResultsFilter -FilterText $textFilter.Text
})

$buttonSearch.Add_Click({
    try {
        $scope = [string]$comboScope.SelectedItem
        $specificDomain = if ($comboDomain.SelectedItem) { [string]$comboDomain.SelectedItem } else { '' }
        $minimumLength = [int]$numericLength.Value
        $domains = @(Get-SearchDomains -Scope $scope -SpecificDomain $specificDomain)

        if ($domains.Count -eq 0) {
            Show-AppMessage -Message 'No domains are available for the selected scope.' -Type Warning
            return
        }

        Write-AppLog -Message ("Starting audit. Scope='{0}'; Domains={1}; MinimumLength={2}" -f
            $scope, ($domains -join ', '), $minimumLength)

        $textFilter.Clear()
        $script:SearchResults = @()
        $script:DisplayedResults = @()
        Set-ResultListViewData -Results @()

        $audit = Find-ShortADComputerNames -Domains $domains -MinimumLength $minimumLength

        $script:SearchResults = @($audit.Results | Sort-Object CharactersLength, Name)
        $script:DisplayedResults = @($script:SearchResults)
        Set-ResultListViewData -Results $script:DisplayedResults

        $failedCount = @($audit.FailedDomains).Count
        $summaryLabel.Text = "Total matches: $($script:SearchResults.Count) | Domains searched: $($domains.Count) | Domain failures: $failedCount"

        if ($failedCount -gt 0) {
            Write-AppLog -Message ("Audit completed with domain failures: {0}" -f
                (@($audit.FailedDomains) -join ', ')) -Level WARN
            Show-AppMessage -Message ("Audit completed with $($script:SearchResults.Count) match(es), but $failedCount domain(s) could not be queried. Review the runtime log.") -Type Warning
        } else {
            Write-AppLog -Message ("Audit completed successfully. Matches={0}; Domains={1}." -f
                $script:SearchResults.Count, $domains.Count) -Level SUCCESS
            Set-AppStatus ("Audit completed: {0} matching computer(s)." -f $script:SearchResults.Count)
        }
    } catch {
        Show-AppMessage -Message "Audit failed: $($_.Exception.Message)" -Type Error
        Set-AppStatus 'Audit failed.'
    }
})

$buttonExportDisplayed.Add_Click({
    $name = "{0}-DISPLAYED-{1}.csv" -f $script:ScriptName, (Get-Date -Format 'yyyyMMdd-HHmmss')
    Export-AuditResults -Data @($script:DisplayedResults) -SuggestedName $name
})

$buttonExportAll.Add_Click({
    $name = "{0}-ALL-{1}.csv" -f $script:ScriptName, (Get-Date -Format 'yyyyMMdd-HHmmss')
    Export-AuditResults -Data @($script:SearchResults) -SuggestedName $name
})

$buttonClose.Add_Click({
    $form.Close()
})

# =====================================================================================
# Main execution
# =====================================================================================
try {
    Write-AppLog -Message "Starting $($script:ScriptName)."
    Write-AppLog -Message ("Host PowerShell: {0}; OS: {1}" -f
        $PSVersionTable.PSVersion, [Environment]::OSVersion.VersionString)

    $script:ForestDomains = @(Get-ForestDomains)
    foreach ($domain in $script:ForestDomains) {
        [void]$comboDomain.Items.Add($domain)
    }

    if ($comboDomain.Items.Count -gt 0) {
        $comboDomain.SelectedIndex = 0
    }

    Write-AppLog -Message ("Discovered forest domains: {0}" -f
        ($script:ForestDomains -join ', ')) -Level SUCCESS

    [void]$form.ShowDialog()
} catch {
    Write-AppLog -Message "Fatal startup error: $($_.Exception.Message)" -Level ERROR
    [void][System.Windows.Forms.MessageBox]::Show(
        "Fatal startup error:`r`n$($_.Exception.Message)",
        'AD Computer Name Length Audit',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
} finally {
    Write-AppLog -Message "Closing $($script:ScriptName)."
}

# End of script
