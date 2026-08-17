<#
.SYNOPSIS
    Enterprise Certificate Repository Organizer.

.DESCRIPTION
    Inventories certificate repository files, extracts X.509 metadata where possible,
    previews the destination folder derived from the issuer CN, and moves only explicitly
    selected files after revalidation.

    Designed for Windows PowerShell 5.1 and Windows Server 2019.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    2026-08-17-v2.0.2-ENTERPRISE-GUI-STABLE

.NOTES
    Safety model:
      - Dry Run enabled by default.
      - Scan and move are separate operations.
      - Every displayed column is searchable through the global filter.
      - File identity is revalidated by SHA-256 immediately before a real move.
      - Existing destination files are never overwritten.
      - Source and target directories cannot be identical.
      - Reparse-point directories are not traversed.
      - Empty-directory cleanup is optional and occurs only after a real move.
      - Files that cannot be parsed as a single X.509 certificate remain visible as
        PARSE FAILED and are not eligible for movement.
      - GUI selection guards prevent non-READY rows from being checked for movement.
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Hide the hosting console as early as possible.
try {
    if (-not ('NativeConsoleWindow' -as [type])) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeConsoleWindow {
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() {
        IntPtr h = GetConsoleWindow();
        if (h != IntPtr.Zero) { ShowWindow(h, 0); }
    }
}
"@
    }
    [NativeConsoleWindow]::Hide()
} catch {}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:ScriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:LogDir = 'C:\Logs-TEMP'
$script:LogPath = Join-Path $script:LogDir ("{0}-{1}.log" -f $script:ScriptName,(Get-Date -Format 'yyyyMMdd-HHmmss'))
$script:Candidates = @()
$script:Displayed = @()
$script:SortColumn = 0
$script:SortAscending = $true
$script:ListView = $null
$script:FilterBox = $null
$script:StatusLabel = $null
$script:LogBox = $null

if (-not (Test-Path -LiteralPath $script:LogDir)) {
    [void](New-Item -Path $script:LogDir -ItemType Directory -Force)
}

function Write-AppLog {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','SUCCESS','WARN','ERROR')][string]$Level='INFO'
    )
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message
    try { Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8 } catch {}
    if ($null -ne $script:LogBox -and -not $script:LogBox.IsDisposed) {
        [void]$script:LogBox.Items.Add($line)
        if ($script:LogBox.Items.Count -gt 0) { $script:LogBox.TopIndex = $script:LogBox.Items.Count - 1 }
    }
}

function Show-AppError {
    param([string]$Message)
    Write-AppLog $Message ERROR
    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,'Error',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}

function Get-NormalizedPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Get-SafeFolderName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return 'Unknown-Issuer' }
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $chars = $Name.ToCharArray() | ForEach-Object {
        if ($invalid -contains $_) { '_' } else { $_ }
    }
    $safe = (-join $chars).Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'Unknown-Issuer' }
    if ($safe.Length -gt 100) { $safe = $safe.Substring(0,100).TrimEnd() }
    return $safe
}

function Get-IssuerCommonName {
    param([string]$Issuer)
    if ([string]::IsNullOrWhiteSpace($Issuer)) { return 'Unknown-Issuer' }
    $m = [regex]::Match($Issuer,'(?:^|,\s*)CN\s*=\s*(?:"([^"]+)"|([^,]+))',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) {
        if (-not [string]::IsNullOrWhiteSpace($m.Groups[1].Value)) { return $m.Groups[1].Value.Trim() }
        return $m.Groups[2].Value.Trim()
    }
    return 'Unknown-Issuer'
}

function Get-Sha256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}

function Get-CertificateCandidate {
    param(
        [Parameter(Mandatory=$true)][IO.FileInfo]$File,
        [Parameter(Mandatory=$true)][string]$TargetRoot
    )

    $hash = ''
    try { $hash = Get-Sha256 -Path $File.FullName } catch {}

    $status = 'PARSE FAILED'
    $detail = ''
    $issuer = ''
    $issuerCN = ''
    $subject = ''
    $thumbprint = ''
    $notBefore = $null
    $notAfter = $null
    $destination = ''

    try {
        # X509Certificate2 reliably handles DER/CER/CRT and unprotected PFX/P12.
        # PEM/PKCS#7/CRL content that cannot be parsed as one certificate is retained
        # in inventory as PARSE FAILED rather than being moved blindly.
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
        try {
            $cert.Import($File.FullName)
            $issuer = [string]$cert.Issuer
            $issuerCN = Get-IssuerCommonName -Issuer $issuer
            $subject = [string]$cert.Subject
            $thumbprint = [string]$cert.Thumbprint
            $notBefore = $cert.NotBefore
            $notAfter = $cert.NotAfter
            $folder = Get-SafeFolderName -Name $issuerCN
            $destination = Join-Path (Join-Path $TargetRoot $folder) $File.Name
            $status = 'READY'
            $detail = 'Certificate parsed successfully.'
        } finally {
            $cert.Reset()
        }
    } catch {
        $detail = $_.Exception.Message
    }

    [pscustomobject]@{
        Selected       = $false
        Name           = $File.Name
        Extension      = $File.Extension
        SizeKB         = [math]::Round(($File.Length / 1KB),2)
        IssuerCN       = $issuerCN
        Subject        = $subject
        Issuer         = $issuer
        Thumbprint     = $thumbprint
        NotBefore      = $notBefore
        NotAfter       = $notAfter
        Status         = $status
        Detail         = $detail
        SourcePath     = $File.FullName
        Destination    = $destination
        SHA256         = $hash
        LastWriteTime  = $File.LastWriteTime
    }
}

function Get-RepositoryFiles {
    param([Parameter(Mandatory=$true)][string]$Root)

    $extensions = @('.cer','.crt','.der','.pem','.pfx','.p12','.p7b','.p7c','.crl')
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push((Get-NormalizedPath $Root))

    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        $entries = @(Get-ChildItem -LiteralPath $current -Force -ErrorAction SilentlyContinue)
        foreach ($entry in $entries) {
            if ($entry.PSIsContainer) {
                if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    Write-AppLog "Skipped reparse-point directory '$($entry.FullName)'." WARN
                    continue
                }
                $pending.Push($entry.FullName)
            } elseif ($extensions -contains $entry.Extension.ToLowerInvariant()) {
                $entry
            }
        }
    }
}

function Test-CandidateMatchesFilter {
    param($Candidate,[string]$Filter)
    if ([string]::IsNullOrWhiteSpace($Filter)) { return $true }
    $needle = $Filter.Trim()
    $values = @(
        $Candidate.Name,$Candidate.Extension,[string]$Candidate.SizeKB,
        $Candidate.IssuerCN,$Candidate.Subject,$Candidate.Issuer,$Candidate.Thumbprint,
        [string]$Candidate.NotBefore,[string]$Candidate.NotAfter,
        $Candidate.Status,$Candidate.Detail,$Candidate.SourcePath,
        $Candidate.Destination,$Candidate.SHA256,[string]$Candidate.LastWriteTime
    )
    foreach ($v in $values) {
        if ($null -ne $v -and ([string]$v).IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }
    return $false
}

function Set-CandidateList {
    param([array]$Items)

    $script:Displayed = @($Items)
    $script:ListView.BeginUpdate()
    try {
        $script:ListView.Items.Clear()
        foreach ($c in $script:Displayed) {
            $item = New-Object System.Windows.Forms.ListViewItem([string]$c.Name)
            $item.Checked = [bool]$c.Selected
            [void]$item.SubItems.Add([string]$c.Extension)
            [void]$item.SubItems.Add([string]$c.SizeKB)
            [void]$item.SubItems.Add([string]$c.IssuerCN)
            [void]$item.SubItems.Add([string]$c.Subject)
            [void]$item.SubItems.Add([string]$c.Thumbprint)
            [void]$item.SubItems.Add($(if($null-ne$c.NotAfter){$c.NotAfter.ToString('yyyy-MM-dd')}else{''}))
            [void]$item.SubItems.Add([string]$c.Status)
            [void]$item.SubItems.Add([string]$c.SourcePath)
            [void]$item.SubItems.Add([string]$c.Destination)
            [void]$item.SubItems.Add([string]$c.Detail)
            $item.Tag = $c
            [void]$script:ListView.Items.Add($item)
        }
    } finally {
        $script:ListView.EndUpdate()
    }

    $ready = @($script:Candidates | Where-Object { $_.Status -eq 'READY' }).Count
    $failed = @($script:Candidates | Where-Object { $_.Status -eq 'PARSE FAILED' }).Count
    $script:StatusLabel.Text = "Candidates: $($script:Candidates.Count) | Ready: $ready | Parse failed: $failed | Displayed: $($script:Displayed.Count)"
}

function Apply-CandidateFilter {
    foreach ($i in $script:ListView.Items) {
        if ($null -ne $i.Tag) { $i.Tag.Selected = [bool]$i.Checked }
    }
    $filtered = @($script:Candidates | Where-Object {
        Test-CandidateMatchesFilter -Candidate $_ -Filter $script:FilterBox.Text
    })
    Set-CandidateList -Items $filtered
}

function Sort-Candidates {
    param([int]$Column)

    if ($script:SortColumn -eq $Column) {
        $script:SortAscending = -not $script:SortAscending
    } else {
        $script:SortColumn = $Column
        $script:SortAscending = $true
    }

    $property = switch ($Column) {
        0 {'Name'} 1 {'Extension'} 2 {'SizeKB'} 3 {'IssuerCN'} 4 {'Subject'}
        5 {'Thumbprint'} 6 {'NotAfter'} 7 {'Status'} 8 {'SourcePath'}
        9 {'Destination'} 10 {'Detail'} default {'Name'}
    }

    if ($script:SortAscending) {
        $script:Candidates = @($script:Candidates | Sort-Object -Property $property)
    } else {
        $script:Candidates = @($script:Candidates | Sort-Object -Property $property -Descending)
    }
    Apply-CandidateFilter
}

function Remove-EmptyRepositoryDirectories {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][string]$TargetRoot
    )
    $rootNorm = Get-NormalizedPath $Root
    $targetNorm = Get-NormalizedPath $TargetRoot

    $dirs = @(Get-ChildItem -LiteralPath $rootNorm -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 } |
        Sort-Object { $_.FullName.Length } -Descending)

    foreach ($dir in $dirs) {
        $dn = Get-NormalizedPath $dir.FullName
        if ($dn -eq $targetNorm -or $targetNorm.StartsWith($dn + '\',[StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        try {
            if (@(Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction Stop).Count -eq 0) {
                Remove-Item -LiteralPath $dir.FullName -Force -ErrorAction Stop
                Write-AppLog "Removed empty directory '$($dir.FullName)'." SUCCESS
            }
        } catch {
            Write-AppLog "Could not remove empty directory '$($dir.FullName)': $($_.Exception.Message)" WARN
        }
    }
}

# ---------------- GUI ----------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Certificate Repository Organizer - Enterprise Edition'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1500,860)
$form.MinimumSize = New-Object System.Drawing.Size(1180,720)

# Main layout: configuration, actions, filter, results, status/safety/log.
$main = New-Object System.Windows.Forms.TableLayoutPanel
$main.Dock = 'Fill'
$main.Padding = New-Object System.Windows.Forms.Padding(10)
$main.ColumnCount = 1
$main.RowCount = 6
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 72)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 28)))
$form.Controls.Add($main)

# Row 1: symmetric Source / Target selectors.
$paths = New-Object System.Windows.Forms.TableLayoutPanel
$paths.Dock = 'Fill'
$paths.AutoSize = $true
$paths.ColumnCount = 6
$paths.RowCount = 1
$paths.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize')))
$paths.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 50)))
$paths.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize')))
$paths.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize')))
$paths.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 50)))
$paths.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize')))

$lblSource = New-Object System.Windows.Forms.Label
$lblSource.Text = 'Source:'
$lblSource.AutoSize = $true
$lblSource.Anchor = 'Left'
$lblSource.Margin = New-Object System.Windows.Forms.Padding(3,7,8,3)

$txtSource = New-Object System.Windows.Forms.TextBox
$txtSource.Dock = 'Fill'
$txtSource.Margin = New-Object System.Windows.Forms.Padding(0,3,6,3)

$btnSource = New-Object System.Windows.Forms.Button
$btnSource.Text = 'Browse...'
$btnSource.Width = 90

$lblTarget = New-Object System.Windows.Forms.Label
$lblTarget.Text = 'Target:'
$lblTarget.AutoSize = $true
$lblTarget.Anchor = 'Left'
$lblTarget.Margin = New-Object System.Windows.Forms.Padding(18,7,8,3)

$txtTarget = New-Object System.Windows.Forms.TextBox
$txtTarget.Dock = 'Fill'
$txtTarget.Margin = New-Object System.Windows.Forms.Padding(0,3,6,3)

$btnTarget = New-Object System.Windows.Forms.Button
$btnTarget.Text = 'Browse...'
$btnTarget.Width = 90

$paths.Controls.Add($lblSource,0,0)
$paths.Controls.Add($txtSource,1,0)
$paths.Controls.Add($btnSource,2,0)
$paths.Controls.Add($lblTarget,3,0)
$paths.Controls.Add($txtTarget,4,0)
$paths.Controls.Add($btnTarget,5,0)

$main.Controls.Add($paths,0,0)

# Row 2: operational controls in one line.
$actions = New-Object System.Windows.Forms.FlowLayoutPanel
$actions.Dock = 'Fill'
$actions.AutoSize = $true
$actions.WrapContents = $false
$actions.FlowDirection = 'LeftToRight'

$chkDry = New-Object System.Windows.Forms.CheckBox
$chkDry.Text = 'Dry Run'
$chkDry.Checked = $true
$chkDry.AutoSize = $true
$chkDry.Margin = New-Object System.Windows.Forms.Padding(3,7,18,3)

$chkCleanup = New-Object System.Windows.Forms.CheckBox
$chkCleanup.Text = 'Remove empty source folders after commit'
$chkCleanup.Checked = $false
$chkCleanup.AutoSize = $true
$chkCleanup.Margin = New-Object System.Windows.Forms.Padding(3,7,24,3)

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = 'Scan Candidates'
$btnScan.Width = 120

$btnPreview = New-Object System.Windows.Forms.Button
$btnPreview.Text = 'Preview Selected'
$btnPreview.Width = 120

$btnMove = New-Object System.Windows.Forms.Button
$btnMove.Text = 'Move Selected'
$btnMove.Width = 110

$actions.Controls.Add($chkDry)
$actions.Controls.Add($chkCleanup)
$actions.Controls.Add($btnScan)
$actions.Controls.Add($btnPreview)
$actions.Controls.Add($btnMove)

$main.Controls.Add($actions,0,1)

# Row 3: full-width search/filter and list actions.
$filterPanel = New-Object System.Windows.Forms.TableLayoutPanel
$filterPanel.Dock = 'Fill'
$filterPanel.AutoSize = $true
$filterPanel.ColumnCount = 5
$filterPanel.RowCount = 1
$filterPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize')))
$filterPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
$filterPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize')))
$filterPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize')))
$filterPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize')))

$lblFilter = New-Object System.Windows.Forms.Label
$lblFilter.Text = 'Filter displayed columns:'
$lblFilter.AutoSize = $true
$lblFilter.Anchor = 'Left'
$lblFilter.Margin = New-Object System.Windows.Forms.Padding(3,7,8,3)

$txtFilter = New-Object System.Windows.Forms.TextBox
$txtFilter.Dock = 'Fill'
$script:FilterBox = $txtFilter

$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Text = 'Clear Filter'
$btnClear.Width = 95

$btnSelect = New-Object System.Windows.Forms.Button
$btnSelect.Text = 'Select All Eligible'
$btnSelect.Width = 130

$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = 'Export Displayed'
$btnExport.Width = 115

$filterPanel.Controls.Add($lblFilter,0,0)
$filterPanel.Controls.Add($txtFilter,1,0)
$filterPanel.Controls.Add($btnClear,2,0)
$filterPanel.Controls.Add($btnSelect,3,0)
$filterPanel.Controls.Add($btnExport,4,0)

$main.Controls.Add($filterPanel,0,2)

# Row 4: results grid.
$list = New-Object System.Windows.Forms.ListView
$list.Dock = 'Fill'
$list.View = 'Details'
$list.FullRowSelect = $true
$list.GridLines = $true
$list.CheckBoxes = $true
$list.HideSelection = $false
$script:ListView = $list

[void]$list.Columns.Add('Name',145)
[void]$list.Columns.Add('Ext',55)
[void]$list.Columns.Add('KB',70)
[void]$list.Columns.Add('Issuer CN',175)
[void]$list.Columns.Add('Subject',250)
[void]$list.Columns.Add('Thumbprint',245)
[void]$list.Columns.Add('Expires',90)
[void]$list.Columns.Add('Status',100)
[void]$list.Columns.Add('Source Path',330)
[void]$list.Columns.Add('Destination',330)
[void]$list.Columns.Add('Detail',280)

$main.Controls.Add($list,0,3)

# Row 5: compact status + safety strip.
$infoPanel = New-Object System.Windows.Forms.TableLayoutPanel
$infoPanel.Dock = 'Fill'
$infoPanel.AutoSize = $true
$infoPanel.ColumnCount = 1
$infoPanel.RowCount = 2

$status = New-Object System.Windows.Forms.Label
$status.Dock = 'Fill'
$status.AutoSize = $true
$status.Padding = New-Object System.Windows.Forms.Padding(2,3,2,3)
$status.Text = 'Ready. Select source and target directories, then Scan Candidates.'
$script:StatusLabel = $status

$safety = New-Object System.Windows.Forms.Label
$safety.Dock = 'Fill'
$safety.AutoSize = $true
$safety.Padding = New-Object System.Windows.Forms.Padding(2,3,2,5)
$safety.Text = 'Safety: Dry Run is enabled by default. Existing destination files are never overwritten. Files are SHA-256 revalidated before commit. PARSE FAILED files remain visible for audit but cannot be selected or moved.'

$infoPanel.Controls.Add($status,0,0)
$infoPanel.Controls.Add($safety,0,1)
$main.Controls.Add($infoPanel,0,4)

# Row 6: bounded runtime log pane.
$logGroup = New-Object System.Windows.Forms.GroupBox
$logGroup.Text = 'Runtime Log'
$logGroup.Dock = 'Fill'
$logGroup.Padding = New-Object System.Windows.Forms.Padding(8)

$log = New-Object System.Windows.Forms.ListBox
$log.Dock = 'Fill'
$log.HorizontalScrollbar = $true
$log.Font = New-Object System.Drawing.Font('Consolas',8.5)
$script:LogBox = $log
$logGroup.Controls.Add($log)

$main.Controls.Add($logGroup,0,5)

function Select-FolderInto {
    param([System.Windows.Forms.TextBox]$TextBox)
    $dlg=New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.ShowNewFolderButton=$true
    if($dlg.ShowDialog()-eq[System.Windows.Forms.DialogResult]::OK){$TextBox.Text=$dlg.SelectedPath}
}

$btnSource.Add_Click({ Select-FolderInto -TextBox $txtSource })
$btnTarget.Add_Click({ Select-FolderInto -TextBox $txtTarget })
$txtFilter.Add_TextChanged({ Apply-CandidateFilter })
$btnClear.Add_Click({ $txtFilter.Clear() })
$list.Add_ColumnClick({ param($sender,$e) Sort-Candidates -Column $e.Column })

$list.Add_ItemCheck({
    param($sender,$e)

    try{
        $item = $list.Items[$e.Index]
        if($null -ne $item.Tag -and $item.Tag.Status -ne 'READY' -and
           $e.NewValue -eq [System.Windows.Forms.CheckState]::Checked){

            # Prevent PARSE FAILED / otherwise blocked rows from being selected
            # for a move operation. Inventory remains fully visible/searchable.
            $e.NewValue = [System.Windows.Forms.CheckState]::Unchecked
            $script:StatusLabel.Text = "Selection blocked: '$($item.Tag.Name)' is $($item.Tag.Status). Only READY rows can be moved."
        }
    }catch{}
})

$btnSelect.Add_Click({
    $eligible = 0
    $blocked = 0

    foreach($i in $list.Items){
        if($null -eq $i.Tag){ continue }

        if($i.Tag.Status -eq 'READY'){
            $i.Checked = $true
            $i.Tag.Selected = $true
            $eligible++
        }else{
            $i.Checked = $false
            $i.Tag.Selected = $false
            $blocked++
        }
    }

    $script:StatusLabel.Text = "Selected eligible rows: $eligible | Blocked rows not selected: $blocked"
    Write-AppLog "Select All Eligible: EligibleSelected=$eligible; BlockedNotSelected=$blocked." INFO
})

$btnScan.Add_Click({
    try {
        if([string]::IsNullOrWhiteSpace($txtSource.Text)-or[string]::IsNullOrWhiteSpace($txtTarget.Text)){
            throw 'Source and Target directories are required.'
        }
        if(-not(Test-Path -LiteralPath $txtSource.Text -PathType Container)){throw 'Source directory does not exist.'}
        $source=Get-NormalizedPath $txtSource.Text
        $target=Get-NormalizedPath $txtTarget.Text
        if($source.Equals($target,[StringComparison]::OrdinalIgnoreCase)){throw 'Source and Target directories cannot be the same.'}

        if(-not(Test-Path -LiteralPath $target -PathType Container)){
            if($chkDry.Checked){
                Write-AppLog "DRY RUN: Target directory '$target' does not exist; it would be created during commit." INFO
            } else {
                [void](New-Item -Path $target -ItemType Directory -Force)
                Write-AppLog "Created target directory '$target'." SUCCESS
            }
        }

        Write-AppLog "Candidate scan started. Source='$source'; Target='$target'." INFO
        $files=@(Get-RepositoryFiles -Root $source)
        $rows=New-Object System.Collections.ArrayList
        foreach($f in $files){
            [void]$rows.Add((Get-CertificateCandidate -File $f -TargetRoot $target))
            [System.Windows.Forms.Application]::DoEvents()
        }
        $script:Candidates=@($rows)
        Apply-CandidateFilter
        Write-AppLog "Candidate scan completed. Enumerated=$($files.Count); Candidates=$($script:Candidates.Count); Ready=$(@($script:Candidates|Where-Object{$_.Status-eq'READY'}).Count); ParseFailed=$(@($script:Candidates|Where-Object{$_.Status-eq'PARSE FAILED'}).Count)." SUCCESS
    } catch {
        Show-AppError ("Candidate scan failed: " + $_.Exception.Message)
    }
})

function Get-CheckedCandidates {
    $selected=New-Object System.Collections.ArrayList
    foreach($i in $list.Items){
        if($null-ne$i.Tag){$i.Tag.Selected=[bool]$i.Checked}
        if($i.Checked -and $null-ne$i.Tag){[void]$selected.Add($i.Tag)}
    }
    return @($selected)
}

$btnPreview.Add_Click({
    $selected=@(Get-CheckedCandidates)
    if($selected.Count-eq0){
        [void][System.Windows.Forms.MessageBox]::Show('Select at least one displayed candidate.','Preview')
        return
    }
    $ready=@($selected | Where-Object { $_.Status -eq 'READY' })
    $blocked=@($selected | Where-Object { $_.Status -ne 'READY' })
    $collisions=@($ready | Where-Object { Test-Path -LiteralPath $_.Destination })
    $message="Selected: $($selected.Count)`r`nReady: $($ready.Count)`r`nBlocked: $($blocked.Count)`r`nDestination collisions: $($collisions.Count)`r`nDry Run: $($chkDry.Checked)"
    [void][System.Windows.Forms.MessageBox]::Show($message,'Move Preview',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)
})

$btnMove.Add_Click({
    try {
        $selected=@(Get-CheckedCandidates)
        if($selected.Count -eq 0){
            [void][System.Windows.Forms.MessageBox]::Show(
                'Select at least one READY certificate row before continuing.',
                'Nothing Eligible Selected',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            $script:StatusLabel.Text = 'No eligible certificate rows are selected.'
            return
        }

        $ready=@($selected | Where-Object { $_.Status -eq 'READY' })
        if($ready.Count -eq 0){
            [void][System.Windows.Forms.MessageBox]::Show(
                'The selected rows are not eligible for movement. Only rows with Status = READY can be moved.',
                'Selection Validation',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            $script:StatusLabel.Text = 'Selection contains no READY rows.'
            return
        }

        if($chkDry.Checked){
            foreach($c in $ready){
                if(Test-Path -LiteralPath $c.Destination){
                    Write-AppLog "DRY RUN BLOCKED: '$($c.SourcePath)' -> '$($c.Destination)' because destination exists." WARN
                } else {
                    Write-AppLog "DRY RUN: '$($c.SourcePath)' -> '$($c.Destination)'." INFO
                }
            }
            [void][System.Windows.Forms.MessageBox]::Show("Dry Run completed for $($ready.Count) eligible file(s). No filesystem state was changed.",'Dry Run')
            return
        }

        $confirm=[System.Windows.Forms.MessageBox]::Show(
            "Move $($ready.Count) selected certificate file(s)?`r`n`r`nExisting destination files will NOT be overwritten.",
            'Confirm Certificate Moves',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if($confirm-ne[System.Windows.Forms.DialogResult]::Yes){
            Write-AppLog 'Move cancelled by operator.' WARN
            return
        }

        $success=0;$failed=0;$skipped=0
        foreach($c in $ready){
            try {
                if(-not(Test-Path -LiteralPath $c.SourcePath -PathType Leaf)){
                    $skipped++;Write-AppLog "SKIPPED: Source no longer exists '$($c.SourcePath)'." WARN;continue
                }
                $currentHash=Get-Sha256 -Path $c.SourcePath
                if($currentHash-ne$c.SHA256){
                    $skipped++;Write-AppLog "SKIPPED: SHA-256 changed since scan '$($c.SourcePath)'." WARN;continue
                }
                if(Test-Path -LiteralPath $c.Destination){
                    $skipped++;Write-AppLog "SKIPPED: Destination already exists '$($c.Destination)'." WARN;continue
                }

                $destDir=Split-Path -Parent $c.Destination
                if(-not(Test-Path -LiteralPath $destDir -PathType Container)){
                    [void](New-Item -Path $destDir -ItemType Directory -Force)
                }

                Move-Item -LiteralPath $c.SourcePath -Destination $c.Destination -ErrorAction Stop
                if(-not(Test-Path -LiteralPath $c.Destination -PathType Leaf)){throw 'Post-move verification failed: destination file not found.'}
                $destHash=Get-Sha256 -Path $c.Destination
                if($destHash-ne$c.SHA256){throw 'Post-move verification failed: destination SHA-256 mismatch.'}

                $success++
                Write-AppLog "Moved and verified '$($c.SourcePath)' -> '$($c.Destination)'." SUCCESS
            } catch {
                $failed++
                Write-AppLog "FAILED '$($c.SourcePath)': $($_.Exception.Message)" ERROR
            }
            [System.Windows.Forms.Application]::DoEvents()
        }

        if($chkCleanup.Checked -and $success-gt0){
            Remove-EmptyRepositoryDirectories -Root $txtSource.Text -TargetRoot $txtTarget.Text
        }

        Write-AppLog "Move summary: Success=$success; Failed=$failed; Skipped=$skipped." INFO
        [void][System.Windows.Forms.MessageBox]::Show("Operation completed.`r`nSuccess: $success`r`nFailed: $failed`r`nSkipped: $skipped",'Completed')
        $btnScan.PerformClick()
    } catch {
        Show-AppError ("Move operation failed: " + $_.Exception.Message)
    }
})

$btnExport.Add_Click({
    try {
        if($script:Displayed.Count-eq0){throw 'There are no displayed rows to export.'}
        $dlg=New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Filter='CSV (*.csv)|*.csv'
        $dlg.FileName="Certificate-Repository-Inventory-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss')
        if($dlg.ShowDialog()-eq[System.Windows.Forms.DialogResult]::OK){
            $script:Displayed | Select-Object Name,Extension,SizeKB,IssuerCN,Subject,Issuer,Thumbprint,NotBefore,NotAfter,Status,Detail,SourcePath,Destination,SHA256,LastWriteTime |
                Export-Csv -LiteralPath $dlg.FileName -NoTypeInformation -Encoding UTF8
            Write-AppLog "Exported displayed inventory to '$($dlg.FileName)'." SUCCESS
        }
    } catch {
        Show-AppError ("Export failed: " + $_.Exception.Message)
    }
})

Write-AppLog "Starting $script:ScriptName." INFO
Write-AppLog ("Host PowerShell: {0}; OS: {1}" -f $PSVersionTable.PSVersion,[Environment]::OSVersion.VersionString) INFO
[void]$form.ShowDialog()
Write-AppLog "Closing $script:ScriptName." INFO

# End of script
