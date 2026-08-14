<#
.SYNOPSIS
  Filesystem Cleanup Manager v2.0.0 Enterprise Edition.

.DESCRIPTION
  Enterprise Windows Forms tool for discovering and deleting files by either:
    - Empty-file criterion (Length = 0 bytes), or
    - LastWriteTime date range.

  The tool:
  - Supports Windows PowerShell 5.1 and Windows Server 2019
  - Hides the PowerShell console before GUI initialization
  - Uses FolderBrowserDialog for explicit folder selection
  - Uses one explicit cleanup mode at a time
  - Inventories candidates before any deletion
  - Provides client-side filtering across every displayed result column
  - Provides ascending/descending sorting by clicking column headers
  - Uses Dry Run by default
  - Provides Preview and Commit workflows
  - Uses exact per-file FullName identity from the discovery inventory
  - Revalidates file existence and cleanup criterion immediately before deletion
  - Does not recurse through reparse-point directories by default
  - Does not delete directories
  - Verifies that each file no longer exists after deletion
  - Produces accurate SUCCESS / FAILED / SKIPPED counts
  - Produces timestamped audit logs in C:\Logs-TEMP
  - Supports exporting the candidate inventory to CSV
  - Uses a PowerShell 5.1-safe byte accumulator, including zero-candidate scans

.AUTHOR
  Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
  2026-08-14-v2.0.1-ENTERPRISE-EDITION

.REQUIREMENTS
  - Windows PowerShell 5.1
  - Windows Server 2019
  - Filesystem permissions sufficient to enumerate/delete the selected files
#>

#Requires -Version 5.1

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
            if ($consolePtr -ne [IntPtr]::Zero) {
                [void][ConsoleControl.Win32ShowWindowAsync]::ShowWindowAsync($consolePtr, 0)
            }
        } catch { }
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
} catch {
    Write-Error "Failed to initialize GUI components: $($_.Exception.Message)"
    return
}

# =====================================================================================
# Globals
# =====================================================================================
$script:ScriptName        = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:LogRoot           = 'C:\Logs-TEMP'
$script:RunStamp          = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:LogFile           = Join-Path $script:LogRoot "$($script:ScriptName)-$($script:RunStamp).log"

$script:SelectedFolder    = $null
$script:CandidateFiles    = @()
$script:DisplayedFiles    = @()
$script:SortColumn        = -1
$script:SortDescending    = $false

$script:listView          = $null
$script:txtRuntimeLog     = $null
$script:statusMain        = $null
$script:statusMode        = $null
$script:chkDryRun         = $null

if (-not (Test-Path -LiteralPath $script:LogRoot)) {
    New-Item -ItemType Directory -Path $script:LogRoot -Force | Out-Null
}

# =====================================================================================
# Logging / messaging
# =====================================================================================
function Write-AppLog {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','SUCCESS','WARN','ERROR')][string]$Level='INFO'
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
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('Information','Warning','Error')][string]$Type='Information'
    )

    switch ($Type) {
        'Error' {
            Write-AppLog -Message $Message -Level ERROR
            $icon = [System.Windows.Forms.MessageBoxIcon]::Error
        }
        'Warning' {
            Write-AppLog -Message $Message -Level WARN
            $icon = [System.Windows.Forms.MessageBoxIcon]::Warning
        }
        default {
            Write-AppLog -Message $Message -Level INFO
            $icon = [System.Windows.Forms.MessageBoxIcon]::Information
        }
    }

    [void][System.Windows.Forms.MessageBox]::Show(
        $Message, $Type,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $icon
    )
}

function Set-AppStatus {
    param([Parameter(Mandatory=$true)][string]$Text)

    if ($script:statusMain -and -not $script:statusMain.IsDisposed) {
        $script:statusMain.Text = $Text
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Get-ExecutionModeLabel {
    if ($script:chkDryRun -and -not $script:chkDryRun.IsDisposed -and $script:chkDryRun.Checked) {
        return 'DRY RUN'
    }
    return 'COMMIT'
}

function Get-TotalLengthBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [object[]]$Files
    )

    [int64]$total = 0
    foreach ($file in $Files) {
        if ($null -ne $file -and $null -ne $file.LengthBytes) {
            $total += [int64]$file.LengthBytes
        }
    }
    return $total
}

# =====================================================================================
# Path and enumeration helpers
# =====================================================================================
function Select-Folder {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select the folder to audit and clean'
    $dialog.ShowNewFolderButton = $false

    if ($script:SelectedFolder -and (Test-Path -LiteralPath $script:SelectedFolder -PathType Container)) {
        $dialog.SelectedPath = $script:SelectedFolder
    }

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return [IO.Path]::GetFullPath($dialog.SelectedPath)
    }

    return $null
}

function Test-TargetFolder {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "The selected folder does not exist: $Path"
    }

    $full = [IO.Path]::GetFullPath($Path)

    # Explicitly block drive-root cleanup. An operator can select a narrower path instead.
    $root = [IO.Path]::GetPathRoot($full)
    if ($full.TrimEnd('\') -eq $root.TrimEnd('\')) {
        throw "Drive-root cleanup is blocked for safety. Select a subfolder instead of '$full'."
    }

    return $full
}

function Get-FilesSafeRecursive {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RootPath)

    $files = New-Object System.Collections.ArrayList
    $stack = New-Object System.Collections.Stack
    $stack.Push((Get-Item -LiteralPath $RootPath -Force -ErrorAction Stop))

    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()

        try {
            $children = @(Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction Stop)
        } catch {
            Write-AppLog -Message "Unable to enumerate '$($dir.FullName)': $($_.Exception.Message)" -Level WARN
            continue
        }

        foreach ($child in $children) {
            if ($child.PSIsContainer) {
                if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    Write-AppLog -Message "Skipping reparse-point directory '$($child.FullName)'." -Level WARN
                    continue
                }
                $stack.Push($child)
            } else {
                [void]$files.Add($child)
            }
        }
    }

    return @($files)
}

function Get-SelectedCleanupMode {
    if ($radioEmpty.Checked) { return 'Empty Files' }
    return 'Date Range'
}

function Get-DateRangeBoundary {
    $start = $dateStart.Value.Date
    # Make the end date inclusive through 23:59:59.999...
    $endExclusive = $dateEnd.Value.Date.AddDays(1)

    if ($start -ge $endExclusive) {
        throw 'The start date must be earlier than or equal to the end date.'
    }

    return [pscustomobject]@{
        Start = $start
        EndExclusive = $endExclusive
        EndDisplay = $endExclusive.AddTicks(-1)
    }
}

function Find-CleanupCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Folder,
        [Parameter(Mandatory=$true)][ValidateSet('Empty Files','Date Range')][string]$Mode
    )

    $folder = Test-TargetFolder -Path $Folder
    $allFiles = @(Get-FilesSafeRecursive -RootPath $folder)

    if ($Mode -eq 'Empty Files') {
        $matches = @($allFiles | Where-Object { $_.Length -eq 0 })
        $criteria = 'Length = 0 bytes'
    } else {
        $range = Get-DateRangeBoundary
        $matches = @(
            $allFiles | Where-Object {
                $_.LastWriteTime -ge $range.Start -and
                $_.LastWriteTime -lt $range.EndExclusive
            }
        )
        $criteria = "LastWriteTime from $($range.Start.ToString('yyyy-MM-dd')) through $($range.EndDisplay.ToString('yyyy-MM-dd'))"
    }

    $records = foreach ($file in $matches) {
        [pscustomobject]@{
            Name          = [string]$file.Name
            FullName      = [string]$file.FullName
            DirectoryName = [string]$file.DirectoryName
            LengthBytes   = [int64]$file.Length
            LastWriteTime = [datetime]$file.LastWriteTime
            CreationTime  = [datetime]$file.CreationTime
            Extension     = [string]$file.Extension
            Attributes    = [string]$file.Attributes
            Criterion     = $criteria
        }
    }

    Write-AppLog -Message ("Candidate discovery completed. Mode='{0}'; Folder='{1}'; FilesEnumerated={2}; Candidates={3}; Criterion='{4}'." -f
        $Mode, $folder, $allFiles.Count, @($records).Count, $criteria) -Level SUCCESS

    return @($records)
}

# =====================================================================================
# Searchable / sortable results
# =====================================================================================
function Set-ResultListViewData {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [object[]]$Results
    )

    $checkedPaths = @{}
    foreach ($item in $script:listView.CheckedItems) {
        if ($null -ne $item.Tag) {
            $checkedPaths[[string]$item.Tag.FullName] = $true
        }
    }

    $script:listView.BeginUpdate()
    try {
        $script:listView.Items.Clear()

        foreach ($file in $Results) {
            $item = New-Object System.Windows.Forms.ListViewItem([string]$file.Name)
            [void]$item.SubItems.Add([string]$file.LengthBytes)
            [void]$item.SubItems.Add($file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
            [void]$item.SubItems.Add($file.CreationTime.ToString('yyyy-MM-dd HH:mm:ss'))
            [void]$item.SubItems.Add([string]$file.Extension)
            [void]$item.SubItems.Add([string]$file.DirectoryName)
            [void]$item.SubItems.Add([string]$file.FullName)
            [void]$item.SubItems.Add([string]$file.Attributes)
            $item.Tag = $file

            if ($checkedPaths.ContainsKey([string]$file.FullName)) {
                $item.Checked = $true
            }

            [void]$script:listView.Items.Add($item)
        }
    } finally {
        $script:listView.EndUpdate()
    }
}

function Test-ResultMatchesFilter {
    param(
        [Parameter(Mandatory=$true)]$Result,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$FilterText
    )

    if ([string]::IsNullOrWhiteSpace($FilterText)) { return $true }

    $needle = $FilterText.Trim()
    $values = @(
        [string]$Result.Name,
        [string]$Result.LengthBytes,
        $Result.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'),
        $Result.CreationTime.ToString('yyyy-MM-dd HH:mm:ss'),
        [string]$Result.Extension,
        [string]$Result.DirectoryName,
        [string]$Result.FullName,
        [string]$Result.Attributes
    )

    foreach ($value in $values) {
        if ($value.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }

    return $false
}

function Apply-ResultsFilter {
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$FilterText)

    $filtered = @(
        $script:CandidateFiles | Where-Object {
            Test-ResultMatchesFilter -Result $_ -FilterText $FilterText
        }
    )

    $script:DisplayedFiles = $filtered
    Set-ResultListViewData -Results $filtered
    Set-AppStatus ("Displayed {0} of {1} candidate file(s)." -f
        $filtered.Count, $script:CandidateFiles.Count)
}

function Sort-Candidates {
    param(
        [Parameter(Mandatory=$true)][int]$ColumnIndex,
        [Parameter(Mandatory=$true)][bool]$Descending
    )

    switch ($ColumnIndex) {
        0 { $property='Name' }
        1 { $property='LengthBytes' }
        2 { $property='LastWriteTime' }
        3 { $property='CreationTime' }
        4 { $property='Extension' }
        5 { $property='DirectoryName' }
        6 { $property='FullName' }
        7 { $property='Attributes' }
        default { $property='FullName' }
    }

    $script:CandidateFiles = @(
        $script:CandidateFiles |
        Sort-Object -Property $property -Descending:$Descending
    )
}

function Get-CheckedFileRecords {
    $records = New-Object System.Collections.ArrayList
    foreach ($item in $script:listView.CheckedItems) {
        if ($null -ne $item.Tag) {
            [void]$records.Add($item.Tag)
        }
    }
    return @($records)
}

# =====================================================================================
# Preview / delete / verification
# =====================================================================================
function Test-FileStillMatchesCriterion {
    param(
        [Parameter(Mandatory=$true)]$Record,
        [Parameter(Mandatory=$true)][ValidateSet('Empty Files','Date Range')][string]$Mode
    )

    if (-not (Test-Path -LiteralPath $Record.FullName -PathType Leaf)) {
        return [pscustomobject]@{ Match=$false; Detail='File no longer exists.' }
    }

    try {
        $current = Get-Item -LiteralPath $Record.FullName -Force -ErrorAction Stop
    } catch {
        return [pscustomobject]@{ Match=$false; Detail=$_.Exception.Message }
    }

    if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        return [pscustomobject]@{ Match=$false; Detail='File is a reparse point and is blocked.' }
    }

    if ($Mode -eq 'Empty Files') {
        if ($current.Length -eq 0) {
            return [pscustomobject]@{ Match=$true; Detail='Still empty.' }
        }
        return [pscustomobject]@{ Match=$false; Detail="File is no longer empty (Length=$($current.Length))." }
    }

    $range = Get-DateRangeBoundary
    if ($current.LastWriteTime -ge $range.Start -and $current.LastWriteTime -lt $range.EndExclusive) {
        return [pscustomobject]@{ Match=$true; Detail='Still within requested LastWriteTime range.' }
    }

    return [pscustomobject]@{ Match=$false; Detail='LastWriteTime is no longer within requested range.' }
}

function Show-DeletionPreview {
    param(
        [Parameter(Mandatory=$true)][object[]]$Files,
        [Parameter(Mandatory=$true)][string]$Mode
    )

    [int64]$totalBytes = Get-TotalLengthBytes -Files $Files

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Execution mode : $(Get-ExecutionModeLabel)")
    $lines.Add("Cleanup mode   : $Mode")
    $lines.Add("Selected files : $($Files.Count)")
    $lines.Add("Total bytes    : $totalBytes")
    $lines.Add('')
    foreach ($file in $Files) {
        $lines.Add(("{0,12}  {1}  {2}" -f
            $file.LengthBytes,
            $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'),
            $file.FullName))
    }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Filesystem Cleanup Preview'
    $dialog.Size = New-Object System.Drawing.Size(1000, 600)
    $dialog.StartPosition = 'CenterParent'

    $box = New-Object System.Windows.Forms.TextBox
    $box.Multiline = $true
    $box.ReadOnly = $true
    $box.ScrollBars = 'Both'
    $box.WordWrap = $false
    $box.Font = New-Object System.Drawing.Font('Consolas', 9)
    $box.Dock = 'Fill'
    $box.Text = ($lines -join [Environment]::NewLine)
    $dialog.Controls.Add($box)

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = 'Bottom'
    $panel.Height = 45

    $close = New-Object System.Windows.Forms.Button
    $close.Text = 'Close'
    $close.Width = 100
    $close.Height = 28
    $close.Left = 865
    $close.Top = 8
    $close.Anchor = 'Right,Top'
    $close.Add_Click({ $dialog.Close() })
    $panel.Controls.Add($close)
    $dialog.Controls.Add($panel)

    [void]$dialog.ShowDialog()
}

function Remove-FilesControlled {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)][object[]]$Files,
        [Parameter(Mandatory=$true)][ValidateSet('Empty Files','Date Range')][string]$Mode
    )

    $results = New-Object System.Collections.ArrayList

    foreach ($record in $Files) {
        try {
            $criterion = Test-FileStillMatchesCriterion -Record $record -Mode $Mode
            if (-not $criterion.Match) {
                Write-AppLog -Message "Skipped '$($record.FullName)': $($criterion.Detail)" -Level WARN
                [void]$results.Add([pscustomobject]@{
                    FullName=$record.FullName; Result='SKIPPED'; Detail=$criterion.Detail
                })
                continue
            }

            $target = $record.FullName
            $action = "Delete file under cleanup mode '$Mode'"

            if ($PSCmdlet.ShouldProcess($target, $action)) {
                Remove-Item -LiteralPath $record.FullName -Force -ErrorAction Stop

                if (Test-Path -LiteralPath $record.FullName) {
                    throw 'Post-delete verification failed: path still exists.'
                }

                Write-AppLog -Message "Deleted and verified '$($record.FullName)'." -Level SUCCESS
                [void]$results.Add([pscustomobject]@{
                    FullName=$record.FullName; Result='SUCCESS'; Detail='Deleted and verified.'
                })
            } else {
                [void]$results.Add([pscustomobject]@{
                    FullName=$record.FullName; Result='SKIPPED'; Detail='ShouldProcess declined the operation.'
                })
            }
        } catch {
            Write-AppLog -Message "Failed to delete '$($record.FullName)': $($_.Exception.Message)" -Level ERROR
            [void]$results.Add([pscustomobject]@{
                FullName=$record.FullName; Result='FAILED'; Detail=$_.Exception.Message
            })
        }
    }

    return @($results)
}

function Export-Candidates {
    $data = @($script:DisplayedFiles)
    if ($data.Count -eq 0) {
        Show-AppMessage -Message 'No displayed candidate files are available to export.' -Type Information
        return
    }

    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = 'CSV files (*.csv)|*.csv'
    $dialog.FileName = "$($script:ScriptName)-Candidates-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    try {
        $data |
            Select-Object Name,FullName,DirectoryName,LengthBytes,LastWriteTime,CreationTime,Extension,Attributes,Criterion |
            Export-Csv -LiteralPath $dialog.FileName -NoTypeInformation -Delimiter ';' -Encoding UTF8

        Write-AppLog -Message "Exported $($data.Count) candidate row(s) to '$($dialog.FileName)'." -Level SUCCESS
    } catch {
        Show-AppMessage -Message "Export failed: $($_.Exception.Message)" -Type Error
    }
}

# =====================================================================================
# GUI
# =====================================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Filesystem Cleanup Manager - Enterprise Edition'
$form.Size = New-Object System.Drawing.Size(1280, 820)
$form.MinimumSize = New-Object System.Drawing.Size(1050, 700)
$form.StartPosition = 'CenterScreen'

$main = New-Object System.Windows.Forms.TableLayoutPanel
$main.Dock = 'Fill'
$main.Padding = New-Object System.Windows.Forms.Padding(10)
$main.ColumnCount = 1
$main.RowCount = 8
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',65)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',35)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$form.Controls.Add($main)

$folderPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$folderPanel.Dock='Fill'; $folderPanel.AutoSize=$true; $folderPanel.WrapContents=$false

$buttonFolder = New-Object System.Windows.Forms.Button
$buttonFolder.Text='Select Folder'; $buttonFolder.Width=110
$folderPanel.Controls.Add($buttonFolder)

$textFolder = New-Object System.Windows.Forms.TextBox
$textFolder.Width=700; $textFolder.ReadOnly=$true
$folderPanel.Controls.Add($textFolder)

$buttonOpen = New-Object System.Windows.Forms.Button
$buttonOpen.Text='Open Folder'; $buttonOpen.Width=100
$folderPanel.Controls.Add($buttonOpen)

$chkDryRun = New-Object System.Windows.Forms.CheckBox
$chkDryRun.Text='Dry Run'; $chkDryRun.Checked=$true; $chkDryRun.AutoSize=$true
$chkDryRun.Margin=New-Object System.Windows.Forms.Padding(20,6,3,3)
$script:chkDryRun=$chkDryRun
$folderPanel.Controls.Add($chkDryRun)

$main.Controls.Add($folderPanel,0,0)

$criteriaPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$criteriaPanel.Dock='Fill'; $criteriaPanel.AutoSize=$true; $criteriaPanel.WrapContents=$false

$radioEmpty = New-Object System.Windows.Forms.RadioButton
$radioEmpty.Text='Empty Files (0 bytes)'; $radioEmpty.Checked=$true; $radioEmpty.AutoSize=$true
$criteriaPanel.Controls.Add($radioEmpty)

$radioDate = New-Object System.Windows.Forms.RadioButton
$radioDate.Text='LastWriteTime Date Range'; $radioDate.AutoSize=$true
$radioDate.Margin=New-Object System.Windows.Forms.Padding(20,3,3,3)
$criteriaPanel.Controls.Add($radioDate)

$dateStart = New-Object System.Windows.Forms.DateTimePicker
$dateStart.Format='Short'; $dateStart.Enabled=$false
$criteriaPanel.Controls.Add($dateStart)

$dateEnd = New-Object System.Windows.Forms.DateTimePicker
$dateEnd.Format='Short'; $dateEnd.Enabled=$false
$criteriaPanel.Controls.Add($dateEnd)

$buttonScan = New-Object System.Windows.Forms.Button
$buttonScan.Text='Scan Candidates'; $buttonScan.Width=120
$criteriaPanel.Controls.Add($buttonScan)

$buttonPreview = New-Object System.Windows.Forms.Button
$buttonPreview.Text='Preview'; $buttonPreview.Width=90
$criteriaPanel.Controls.Add($buttonPreview)

$buttonDelete = New-Object System.Windows.Forms.Button
$buttonDelete.Text='Delete Selected'; $buttonDelete.Width=120
$criteriaPanel.Controls.Add($buttonDelete)

$main.Controls.Add($criteriaPanel,0,1)

$filterPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$filterPanel.Dock='Fill'; $filterPanel.AutoSize=$true; $filterPanel.WrapContents=$false

$labelFilter = New-Object System.Windows.Forms.Label
$labelFilter.Text='Filter displayed columns:'; $labelFilter.AutoSize=$true
$labelFilter.Margin=New-Object System.Windows.Forms.Padding(3,7,3,3)
$filterPanel.Controls.Add($labelFilter)

$textFilter = New-Object System.Windows.Forms.TextBox
$textFilter.Width=520
$filterPanel.Controls.Add($textFilter)

$buttonClearFilter = New-Object System.Windows.Forms.Button
$buttonClearFilter.Text='Clear Filter'; $buttonClearFilter.Width=100
$filterPanel.Controls.Add($buttonClearFilter)

$buttonSelectAll = New-Object System.Windows.Forms.Button
$buttonSelectAll.Text='Select All'; $buttonSelectAll.Width=100
$filterPanel.Controls.Add($buttonSelectAll)

$buttonExport = New-Object System.Windows.Forms.Button
$buttonExport.Text='Export Displayed'; $buttonExport.Width=120
$filterPanel.Controls.Add($buttonExport)

$main.Controls.Add($filterPanel,0,2)

$listView = New-Object System.Windows.Forms.ListView
$listView.Dock='Fill'; $listView.View='Details'; $listView.CheckBoxes=$true
$listView.FullRowSelect=$true; $listView.GridLines=$true; $listView.HideSelection=$false
[void]$listView.Columns.Add('Name',160)
[void]$listView.Columns.Add('Bytes',85)
[void]$listView.Columns.Add('LastWriteTime',145)
[void]$listView.Columns.Add('CreationTime',145)
[void]$listView.Columns.Add('Extension',80)
[void]$listView.Columns.Add('Directory',290)
[void]$listView.Columns.Add('FullName',420)
[void]$listView.Columns.Add('Attributes',130)
$script:listView=$listView
$main.Controls.Add($listView,0,3)

$summaryLabel = New-Object System.Windows.Forms.Label
$summaryLabel.AutoSize=$true; $summaryLabel.Text='No candidate scan has been run.'
$main.Controls.Add($summaryLabel,0,4)

$noteLabel = New-Object System.Windows.Forms.Label
$noteLabel.AutoSize=$true; $noteLabel.MaximumSize=New-Object System.Drawing.Size(1200,0)
$noteLabel.Text='Safety controls: drive-root cleanup is blocked; directories are never deleted; recursive enumeration skips reparse-point directories; each file is revalidated against the selected criterion immediately before deletion.'
$main.Controls.Add($noteLabel,0,5)

$txtRuntimeLog = New-Object System.Windows.Forms.TextBox
$txtRuntimeLog.Dock='Fill'; $txtRuntimeLog.Multiline=$true; $txtRuntimeLog.ReadOnly=$true
$txtRuntimeLog.ScrollBars='Vertical'; $txtRuntimeLog.Font=New-Object System.Drawing.Font('Consolas',8.5)
$script:txtRuntimeLog=$txtRuntimeLog
$main.Controls.Add($txtRuntimeLog,0,6)

$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusMain = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusMain.Spring=$true; $statusMain.TextAlign='MiddleLeft'; $statusMain.Text='Ready'
$script:statusMain=$statusMain
[void]$statusStrip.Items.Add($statusMain)

$statusMode = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusMode.Text='Mode: DRY RUN'
[void]$statusStrip.Items.Add($statusMode)
$main.Controls.Add($statusStrip,0,7)

# =====================================================================================
# GUI events
# =====================================================================================
$radioEmpty.Add_CheckedChanged({
    if ($radioEmpty.Checked) {
        $dateStart.Enabled=$false; $dateEnd.Enabled=$false
    }
})
$radioDate.Add_CheckedChanged({
    if ($radioDate.Checked) {
        $dateStart.Enabled=$true; $dateEnd.Enabled=$true
    }
})
$chkDryRun.Add_CheckedChanged({
    $statusMode.Text = if ($chkDryRun.Checked) { 'Mode: DRY RUN' } else { 'Mode: COMMIT' }
})
$buttonFolder.Add_Click({
    $folder = Select-Folder
    if ($folder) {
        try {
            $script:SelectedFolder = Test-TargetFolder -Path $folder
            $textFolder.Text = $script:SelectedFolder
            $script:CandidateFiles=@(); $script:DisplayedFiles=@()
            Set-ResultListViewData -Results @()
            $summaryLabel.Text='Folder selected. Run Scan Candidates.'
            Write-AppLog -Message "Selected cleanup folder '$($script:SelectedFolder)'."
        } catch {
            Show-AppMessage -Message $_.Exception.Message -Type Error
        }
    }
})
$buttonOpen.Add_Click({
    if ($script:SelectedFolder -and (Test-Path -LiteralPath $script:SelectedFolder -PathType Container)) {
        Start-Process explorer.exe -ArgumentList ('"{0}"' -f $script:SelectedFolder)
    } else {
        Show-AppMessage -Message 'Select a valid folder first.' -Type Warning
    }
})
$buttonScan.Add_Click({
    try {
        if (-not $script:SelectedFolder) { throw 'Select a folder first.' }

        $mode = Get-SelectedCleanupMode
        Set-AppStatus 'Scanning filesystem candidates...'
        $script:CandidateFiles = @(Find-CleanupCandidates -Folder $script:SelectedFolder -Mode $mode |
            Sort-Object FullName)
        $script:DisplayedFiles = @($script:CandidateFiles)
        $textFilter.Clear()
        Set-ResultListViewData -Results $script:DisplayedFiles

        [int64]$bytes = Get-TotalLengthBytes -Files $script:CandidateFiles
        $summaryLabel.Text = "Mode: $mode | Candidates: $($script:CandidateFiles.Count) | Total bytes: $bytes"
        Set-AppStatus ("Candidate scan completed: {0} file(s)." -f $script:CandidateFiles.Count)
    } catch {
        Show-AppMessage -Message "Candidate scan failed: $($_.Exception.Message)" -Type Error
    }
})
$textFilter.Add_TextChanged({
    try {
        Apply-ResultsFilter -FilterText $textFilter.Text
        $summaryLabel.Text = "Displayed: $($script:DisplayedFiles.Count) | Total candidates: $($script:CandidateFiles.Count)"
    } catch {
        Write-AppLog -Message "Display filter failed: $($_.Exception.Message)" -Level ERROR
    }
})
$buttonClearFilter.Add_Click({ $textFilter.Clear() })
$buttonSelectAll.Add_Click({
    foreach ($item in $script:listView.Items) { $item.Checked=$true }
    Set-AppStatus ("Selected {0} displayed candidate(s)." -f $script:listView.Items.Count)
})
$listView.Add_ColumnClick({
    param($sender,$eventArgs)
    if ($script:SortColumn -eq $eventArgs.Column) {
        $script:SortDescending = -not $script:SortDescending
    } else {
        $script:SortColumn = $eventArgs.Column
        $script:SortDescending = $false
    }
    Sort-Candidates -ColumnIndex $script:SortColumn -Descending $script:SortDescending
    Apply-ResultsFilter -FilterText $textFilter.Text
})
$buttonExport.Add_Click({ Export-Candidates })
$buttonPreview.Add_Click({
    $files = @(Get-CheckedFileRecords)
    if ($files.Count -eq 0) {
        Show-AppMessage -Message 'Select at least one candidate file.' -Type Warning
        return
    }
    Show-DeletionPreview -Files $files -Mode (Get-SelectedCleanupMode)
})
$buttonDelete.Add_Click({
    try {
        $files = @(Get-CheckedFileRecords)
        if ($files.Count -eq 0) {
            Show-AppMessage -Message 'Select at least one candidate file.' -Type Warning
            return
        }

        $mode = Get-SelectedCleanupMode

        if ($chkDryRun.Checked) {
            Show-DeletionPreview -Files $files -Mode $mode
            Write-AppLog -Message ("DRY RUN: Mode='{0}'; Selected={1}; no files deleted." -f $mode,$files.Count)
            Show-AppMessage -Message 'Dry Run completed. No files were deleted.' -Type Information
            return
        }

        [int64]$bytes = Get-TotalLengthBytes -Files $files

        $confirmation = @"
COMMIT filesystem deletion?

Folder: $($script:SelectedFolder)
Cleanup mode: $mode
Selected files: $($files.Count)
Total bytes from discovery: $bytes

Each file will be revalidated against the selected criterion immediately before deletion.
This operation does not use the Recycle Bin.
"@

        $answer = [System.Windows.Forms.MessageBox]::Show(
            $confirmation,
            'Confirm File Deletion',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2
        )

        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            Write-AppLog -Message 'File deletion commit cancelled by operator.' -Level WARN
            return
        }

        Set-AppStatus 'Deleting and verifying selected files...'
        $results = @(Remove-FilesControlled -Files $files -Mode $mode -Confirm:$false)

        $success = @($results | Where-Object {$_.Result -eq 'SUCCESS'}).Count
        $failed = @($results | Where-Object {$_.Result -eq 'FAILED'}).Count
        $skipped = @($results | Where-Object {$_.Result -eq 'SKIPPED'}).Count

        # Refresh candidates using the currently selected criterion.
        $script:CandidateFiles = @(Find-CleanupCandidates -Folder $script:SelectedFolder -Mode $mode |
            Sort-Object FullName)
        Apply-ResultsFilter -FilterText $textFilter.Text

        $summary = @"
Execution completed.

Deleted: $success
Failed: $failed
Skipped: $skipped

Log: $($script:LogFile)
"@

        if ($failed -gt 0) {
            Show-AppMessage -Message $summary -Type Warning
        } else {
            Write-AppLog -Message ("Deletion summary: Success={0}; Failed={1}; Skipped={2}" -f
                $success,$failed,$skipped) -Level SUCCESS
            [void][System.Windows.Forms.MessageBox]::Show(
                $summary,'Execution Summary',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
        Set-AppStatus ("Completed: Deleted={0}, Failed={1}, Skipped={2}" -f $success,$failed,$skipped)
    } catch {
        Show-AppMessage -Message "Deletion failed: $($_.Exception.Message)" -Type Error
    }
})

# =====================================================================================
# Main
# =====================================================================================
try {
    Write-AppLog -Message "Starting $($script:ScriptName)."
    Write-AppLog -Message ("Host PowerShell: {0}; OS: {1}" -f
        $PSVersionTable.PSVersion,[Environment]::OSVersion.VersionString)

    [void]$form.ShowDialog()
} catch {
    Write-AppLog -Message "Fatal startup error: $($_.Exception.Message)" -Level ERROR
    [void][System.Windows.Forms.MessageBox]::Show(
        "Fatal startup error:`r`n$($_.Exception.Message)",
        'Filesystem Cleanup Manager',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
} finally {
    Write-AppLog -Message "Closing $($script:ScriptName)."
}

# End of script
