<#
.SYNOPSIS
  Enterprise Certificate Repository Expiration Audit and Cleanup Tool.

.DESCRIPTION
  Audits certificate repository files, classifies certificate expiration state,
  lists certificates approaching expiration, and deletes only explicitly selected
  expired certificate files after revalidation.

  Designed for Windows PowerShell 5.1 and Windows Server 2019.

  Key behavior:
  - Certificate files successfully parsed as X509Certificate2 are classified as:
      EXPIRED, EXPIRING, VALID.
  - CRL files are inventoried separately and are not incorrectly treated as certificates.
  - Password-protected PFX/P12 files and unsupported containers remain visible as
      PARSE FAILED / CRL / UNSUPPORTED rather than being deleted.
  - Deletion is never automatic immediately after scanning.

.AUTHOR
  Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
  2026-08-17-v2.0.0-ENTERPRISE-EDITION

.REQUIREMENTS
  - Windows PowerShell 5.1
  - Windows Server 2019
  - Filesystem permissions sufficient to enumerate/delete selected files

.SAFETY
  - Dry Run enabled by default.
  - Explicit candidate inventory before deletion.
  - Only Status=EXPIRED rows are eligible for deletion.
  - File SHA-256 is captured during discovery and revalidated before deletion.
  - Reparse-point directories are not traversed.
  - Existing directories are never deleted.
  - Uses -LiteralPath for filesystem mutation.
  - Post-delete verification is mandatory.
#>

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param([switch]$ShowConsole)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

# =====================================================================================
# Console suppression and GUI initialization
# =====================================================================================
try {
    if(-not$ShowConsole){
        try{
            if(-not('NativeConsoleWindow' -as [type])){
                Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeConsoleWindow {
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd,int nCmdShow);
    public static void Hide(){
        IntPtr h=GetConsoleWindow();
        if(h!=IntPtr.Zero){ShowWindow(h,0);}
    }
}
"@
            }
            [NativeConsoleWindow]::Hide()
        }catch{}
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
}catch{
    Write-Error "Failed to initialize GUI: $($_.Exception.Message)"
    return
}

# =====================================================================================
# Globals / logging
# =====================================================================================
$script:ScriptName=[IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:LogRoot='C:\Logs-TEMP'
$script:RunStamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$script:LogFile=Join-Path $script:LogRoot "$($script:ScriptName)-$($script:RunStamp).log"

$script:Inventory=@()
$script:Displayed=@()
$script:SortColumn=-1
$script:SortDescending=$false

$script:listView=$null
$script:txtRuntimeLog=$null
$script:statusMain=$null
$script:chkDryRun=$null

if(-not(Test-Path -LiteralPath $script:LogRoot)){
    New-Item -ItemType Directory -Path $script:LogRoot -Force|Out-Null
}

function Write-AppLog {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','SUCCESS','WARN','ERROR')][string]$Level='INFO'
    )

    $line="{0} [{1}] {2}"-f(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message
    try{Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop}catch{}

    if($script:txtRuntimeLog-and-not$script:txtRuntimeLog.IsDisposed){
        $script:txtRuntimeLog.AppendText($line+[Environment]::NewLine)
        $script:txtRuntimeLog.SelectionStart=$script:txtRuntimeLog.Text.Length
        $script:txtRuntimeLog.ScrollToCaret()
    }elseif($ShowConsole){
        Write-Host $line
    }
}

function Show-AppMessage {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('Information','Warning','Error')][string]$Type='Information'
    )

    switch($Type){
        'Error'{$icon=[Windows.Forms.MessageBoxIcon]::Error;Write-AppLog $Message ERROR}
        'Warning'{$icon=[Windows.Forms.MessageBoxIcon]::Warning;Write-AppLog $Message WARN}
        default{$icon=[Windows.Forms.MessageBoxIcon]::Information;Write-AppLog $Message INFO}
    }

    [void][Windows.Forms.MessageBox]::Show(
        $Message,$Type,[Windows.Forms.MessageBoxButtons]::OK,$icon
    )
}

function Set-AppStatus {
    param([string]$Text)
    if($script:statusMain-and-not$script:statusMain.IsDisposed){
        $script:statusMain.Text=$Text
        [Windows.Forms.Application]::DoEvents()
    }
}

function Get-NormalizedPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Get-Sha256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}

# =====================================================================================
# Safe recursive repository enumeration
# =====================================================================================
function Get-RepositoryFiles {
    param([Parameter(Mandatory=$true)][string]$Root)

    if(-not(Test-Path -LiteralPath $Root -PathType Container)){
        throw "Repository path does not exist: $Root"
    }

    $extensions=@('.cer','.crt','.der','.pem','.pfx','.p12','.p7b','.p7c','.crl')
    $stack=New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push((Get-NormalizedPath $Root))

    $files=New-Object Collections.ArrayList

    while($stack.Count-gt0){
        $dir=$stack.Pop()
        try{
            $entries=@(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop)
        }catch{
            Write-AppLog "Enumeration failed for '$dir': $($_.Exception.Message)" WARN
            continue
        }

        foreach($entry in $entries){
            if($entry.PSIsContainer){
                if(($entry.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){
                    Write-AppLog "Skipped reparse-point directory '$($entry.FullName)'." WARN
                    continue
                }
                $stack.Push($entry.FullName)
            }elseif($extensions-contains$entry.Extension.ToLowerInvariant()){
                [void]$files.Add($entry)
            }
        }
    }

    return @($files)
}

# =====================================================================================
# Certificate metadata / classification
# =====================================================================================
function Get-CertificateInventoryRecord {
    param(
        [Parameter(Mandatory=$true)][IO.FileInfo]$File,
        [Parameter(Mandatory=$true)][int]$ExpiringDays
    )

    $record=[ordered]@{
        Name=[string]$File.Name
        Extension=[string]$File.Extension
        SizeKB=[math]::Round($File.Length/1KB,2)
        ObjectType=''
        Status=''
        Subject=''
        Issuer=''
        Thumbprint=''
        NotBefore=$null
        NotAfter=$null
        DaysRemaining=$null
        SourcePath=[string]$File.FullName
        SHA256=''
        LastWriteTime=[datetime]$File.LastWriteTime
        Detail=''
    }

    try{$record.SHA256=Get-Sha256 -Path $File.FullName}catch{}

    if($File.Extension.ToLowerInvariant()-eq'.crl'){
        $record.ObjectType='CRL'
        $record.Status='CRL'
        $record.Detail='CRL detected. CRLs do not expose certificate NotAfter semantics and are not eligible for certificate-expiration deletion.'
        return [pscustomobject]$record
    }

    try{
        $cert=New-Object Security.Cryptography.X509Certificates.X509Certificate2
        try{
            $cert.Import($File.FullName)

            $record.ObjectType='Certificate'
            $record.Subject=[string]$cert.Subject
            $record.Issuer=[string]$cert.Issuer
            $record.Thumbprint=[string]$cert.Thumbprint
            $record.NotBefore=[datetime]$cert.NotBefore
            $record.NotAfter=[datetime]$cert.NotAfter

            $now=Get-Date
            $days=[math]::Floor(($cert.NotAfter-$now).TotalDays)
            $record.DaysRemaining=[int]$days

            if($cert.NotAfter-lt$now){
                $record.Status='EXPIRED'
                $record.Detail='Certificate expiration date is in the past.'
            }elseif($cert.NotAfter-le$now.AddDays($ExpiringDays)){
                $record.Status='EXPIRING'
                $record.Detail="Certificate expires within $ExpiringDays day(s)."
            }else{
                $record.Status='VALID'
                $record.Detail='Certificate is outside the configured expiration-warning window.'
            }
        }finally{
            $cert.Reset()
        }
    }catch{
        $record.ObjectType='Unknown/Container'
        $record.Status='PARSE FAILED'
        $record.Detail=$_.Exception.Message
    }

    return [pscustomobject]$record
}

function Invoke-RepositoryAudit {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][int]$ExpiringDays
    )

    $files=@(Get-RepositoryFiles -Root $Root)
    $results=New-Object Collections.ArrayList

    $n=0
    foreach($file in $files){
        $n++
        Set-AppStatus ("Auditing file {0} of {1}: {2}"-f$n,$files.Count,$file.Name)
        [void]$results.Add((Get-CertificateInventoryRecord -File $file -ExpiringDays $ExpiringDays))
        [Windows.Forms.Application]::DoEvents()
    }

    Write-AppLog ("Repository audit completed. Files={0}; ExpiringWindowDays={1}."-f$files.Count,$ExpiringDays) SUCCESS
    return @($results)
}

# =====================================================================================
# Searchable / sortable ListView
# =====================================================================================
function Set-InventoryList {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [object[]]$Rows
    )

    $selected=@{}
    foreach($i in $script:listView.CheckedItems){
        if($i.Tag){$selected[[string]$i.Tag.SourcePath]=$true}
    }

    $script:listView.BeginUpdate()
    try{
        $script:listView.Items.Clear()

        foreach($r in $Rows){
            $item=New-Object Windows.Forms.ListViewItem([string]$r.Name)
            [void]$item.SubItems.Add([string]$r.Extension)
            [void]$item.SubItems.Add([string]$r.ObjectType)
            [void]$item.SubItems.Add([string]$r.Status)
            [void]$item.SubItems.Add([string]$r.Subject)
            [void]$item.SubItems.Add([string]$r.Issuer)
            [void]$item.SubItems.Add([string]$r.Thumbprint)
            [void]$item.SubItems.Add($(if($null-ne$r.NotAfter){$r.NotAfter.ToString('yyyy-MM-dd HH:mm:ss')}else{''}))
            [void]$item.SubItems.Add($(if($null-ne$r.DaysRemaining){[string]$r.DaysRemaining}else{''}))
            [void]$item.SubItems.Add([string]$r.SizeKB)
            [void]$item.SubItems.Add([string]$r.SourcePath)
            [void]$item.SubItems.Add([string]$r.Detail)

            $item.Tag=$r

            # Only expired certificates are eligible for selection/deletion.
            if($r.Status-eq'EXPIRED'-and$selected.ContainsKey([string]$r.SourcePath)){
                $item.Checked=$true
            }

            [void]$script:listView.Items.Add($item)
        }
    }finally{
        $script:listView.EndUpdate()
    }
}

function Test-RowMatchesFilter {
    param($Row,[string]$Filter)

    if([string]::IsNullOrWhiteSpace($Filter)){return $true}
    $needle=$Filter.Trim()

    foreach($v in @(
        $Row.Name,$Row.Extension,$Row.ObjectType,$Row.Status,$Row.Subject,$Row.Issuer,
        $Row.Thumbprint,[string]$Row.NotBefore,[string]$Row.NotAfter,
        [string]$Row.DaysRemaining,[string]$Row.SizeKB,$Row.SourcePath,$Row.SHA256,
        [string]$Row.LastWriteTime,$Row.Detail
    )){
        if(([string]$v).IndexOf($needle,[StringComparison]::OrdinalIgnoreCase)-ge0){
            return $true
        }
    }
    return $false
}

function Apply-InventoryFilter {
    param([string]$Filter)

    $script:Displayed=@(
        $script:Inventory|Where-Object{
            Test-RowMatchesFilter -Row $_ -Filter $Filter
        }
    )

    Set-InventoryList -Rows $script:Displayed

    $expired=@($script:Inventory|Where-Object{$_.Status-eq'EXPIRED'}).Count
    $expiring=@($script:Inventory|Where-Object{$_.Status-eq'EXPIRING'}).Count
    $valid=@($script:Inventory|Where-Object{$_.Status-eq'VALID'}).Count
    $crl=@($script:Inventory|Where-Object{$_.Status-eq'CRL'}).Count
    $failed=@($script:Inventory|Where-Object{$_.Status-eq'PARSE FAILED'}).Count

    $summaryLabel.Text="Total: $($script:Inventory.Count) | Expired: $expired | Expiring: $expiring | Valid: $valid | CRL: $crl | Parse failed: $failed | Displayed: $($script:Displayed.Count)"
}

function Sort-Inventory {
    param([int]$Column)

    if($script:SortColumn-eq$Column){
        $script:SortDescending=-not$script:SortDescending
    }else{
        $script:SortColumn=$Column
        $script:SortDescending=$false
    }

    switch($Column){
        0{$p='Name'}1{$p='Extension'}2{$p='ObjectType'}3{$p='Status'}
        4{$p='Subject'}5{$p='Issuer'}6{$p='Thumbprint'}7{$p='NotAfter'}
        8{$p='DaysRemaining'}9{$p='SizeKB'}10{$p='SourcePath'}11{$p='Detail'}
        default{$p='Name'}
    }

    $script:Inventory=@(
        $script:Inventory|Sort-Object -Property $p -Descending:$script:SortDescending
    )

    Apply-InventoryFilter -Filter $txtFilter.Text
}

function Get-CheckedExpiredRows {
    $rows=New-Object Collections.ArrayList
    foreach($i in $script:listView.CheckedItems){
        if($i.Tag-and$i.Tag.Status-eq'EXPIRED'){
            [void]$rows.Add($i.Tag)
        }
    }
    return @($rows)
}

# =====================================================================================
# Controlled deletion
# =====================================================================================
function Remove-ExpiredCertificateFiles {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param([Parameter(Mandatory=$true)][object[]]$Rows)

    $results=New-Object Collections.ArrayList

    foreach($r in $Rows){
        try{
            if($r.Status-ne'EXPIRED'){
                [void]$results.Add([pscustomobject]@{Name=$r.Name;Result='SKIPPED';Detail='Status is not EXPIRED.'})
                continue
            }

            if(-not(Test-Path -LiteralPath $r.SourcePath -PathType Leaf)){
                [void]$results.Add([pscustomobject]@{Name=$r.Name;Result='SKIPPED';Detail='Source file no longer exists.'})
                continue
            }

            $currentHash=Get-Sha256 -Path $r.SourcePath
            if($currentHash-ne$r.SHA256){
                throw 'SHA-256 changed since inventory. Deletion blocked.'
            }

            # Reparse the certificate immediately before deletion and confirm it is still expired.
            $currentFile=Get-Item -LiteralPath $r.SourcePath -Force -ErrorAction Stop
            $recheck=Get-CertificateInventoryRecord -File $currentFile -ExpiringDays ([int]$numDays.Value)
            if($recheck.Status-ne'EXPIRED'){
                throw "File is no longer classified EXPIRED. Current status='$($recheck.Status)'."
            }

            if($PSCmdlet.ShouldProcess($r.SourcePath,'Delete expired certificate file')){
                Remove-Item -LiteralPath $r.SourcePath -Force -ErrorAction Stop

                if(Test-Path -LiteralPath $r.SourcePath){
                    throw 'Post-delete verification failed: source path still exists.'
                }

                Write-AppLog "Deleted and verified expired certificate '$($r.SourcePath)'." SUCCESS
                [void]$results.Add([pscustomobject]@{Name=$r.Name;Result='SUCCESS';Detail='Deleted and verified.'})
            }
        }catch{
            Write-AppLog "Deletion failed for '$($r.SourcePath)': $($_.Exception.Message)" ERROR
            [void]$results.Add([pscustomobject]@{Name=$r.Name;Result='FAILED';Detail=$_.Exception.Message})
        }
    }

    return @($results)
}

# =====================================================================================
# GUI
# =====================================================================================
$form=New-Object Windows.Forms.Form
$form.Text='Certificate Repository Expiration Audit & Cleanup - Enterprise Edition'
$form.Size=New-Object Drawing.Size(1500,860)
$form.MinimumSize=New-Object Drawing.Size(1180,720)
$form.StartPosition='CenterScreen'

$main=New-Object Windows.Forms.TableLayoutPanel
$main.Dock='Fill'
$main.Padding=New-Object Windows.Forms.Padding(10)
$main.ColumnCount=1
$main.RowCount=7
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',68)))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',32)))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$form.Controls.Add($main)

# Repository path / audit controls
$p1=New-Object Windows.Forms.TableLayoutPanel
$p1.Dock='Fill';$p1.AutoSize=$true;$p1.ColumnCount=7;$p1.RowCount=1
$p1.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$p1.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
$p1.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$p1.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$p1.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$p1.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$p1.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))

$lblPath=New-Object Windows.Forms.Label
$lblPath.Text='Repository:';$lblPath.AutoSize=$true;$lblPath.Anchor='Left';$lblPath.Margin=New-Object Windows.Forms.Padding(3,7,8,3)
$p1.Controls.Add($lblPath,0,0)

$txtPath=New-Object Windows.Forms.TextBox
$txtPath.Dock='Fill'
$p1.Controls.Add($txtPath,1,0)

$btnBrowse=New-Object Windows.Forms.Button
$btnBrowse.Text='Browse...';$btnBrowse.Width=90
$p1.Controls.Add($btnBrowse,2,0)

$lblDays=New-Object Windows.Forms.Label
$lblDays.Text='Expiring within days:';$lblDays.AutoSize=$true;$lblDays.Anchor='Left';$lblDays.Margin=New-Object Windows.Forms.Padding(20,7,5,3)
$p1.Controls.Add($lblDays,3,0)

$numDays=New-Object Windows.Forms.NumericUpDown
$numDays.Minimum=1;$numDays.Maximum=730;$numDays.Value=180;$numDays.Width=70
$p1.Controls.Add($numDays,4,0)

$btnAudit=New-Object Windows.Forms.Button
$btnAudit.Text='Audit Repository';$btnAudit.Width=115
$p1.Controls.Add($btnAudit,5,0)

$chkDryRun=New-Object Windows.Forms.CheckBox
$chkDryRun.Text='Dry Run';$chkDryRun.Checked=$true;$chkDryRun.AutoSize=$true;$chkDryRun.Margin=New-Object Windows.Forms.Padding(18,7,3,3)
$script:chkDryRun=$chkDryRun
$p1.Controls.Add($chkDryRun,6,0)

$main.Controls.Add($p1,0,0)

# Action row
$p2=New-Object Windows.Forms.FlowLayoutPanel
$p2.Dock='Fill';$p2.AutoSize=$true;$p2.WrapContents=$false

$btnSelectExpired=New-Object Windows.Forms.Button
$btnSelectExpired.Text='Select All Expired';$btnSelectExpired.Width=125
$p2.Controls.Add($btnSelectExpired)

$btnPreview=New-Object Windows.Forms.Button
$btnPreview.Text='Preview Deletion';$btnPreview.Width=115
$p2.Controls.Add($btnPreview)

$btnDelete=New-Object Windows.Forms.Button
$btnDelete.Text='Delete Selected';$btnDelete.Width=115
$p2.Controls.Add($btnDelete)

$btnExport=New-Object Windows.Forms.Button
$btnExport.Text='Export Displayed';$btnExport.Width=120
$p2.Controls.Add($btnExport)

$main.Controls.Add($p2,0,1)

# Search/filter row
$p3=New-Object Windows.Forms.TableLayoutPanel
$p3.Dock='Fill';$p3.AutoSize=$true;$p3.ColumnCount=3;$p3.RowCount=1
$p3.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$p3.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
$p3.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))

$lblFilter=New-Object Windows.Forms.Label
$lblFilter.Text='Filter displayed columns:';$lblFilter.AutoSize=$true;$lblFilter.Anchor='Left';$lblFilter.Margin=New-Object Windows.Forms.Padding(3,7,8,3)
$p3.Controls.Add($lblFilter,0,0)

$txtFilter=New-Object Windows.Forms.TextBox
$txtFilter.Dock='Fill'
$p3.Controls.Add($txtFilter,1,0)

$btnClear=New-Object Windows.Forms.Button
$btnClear.Text='Clear Filter';$btnClear.Width=95
$p3.Controls.Add($btnClear,2,0)

$main.Controls.Add($p3,0,2)

# Results
$listView=New-Object Windows.Forms.ListView
$listView.Dock='Fill';$listView.View='Details';$listView.CheckBoxes=$true
$listView.FullRowSelect=$true;$listView.GridLines=$true;$listView.HideSelection=$false
$script:listView=$listView

[void]$listView.Columns.Add('Name',145)
[void]$listView.Columns.Add('Ext',55)
[void]$listView.Columns.Add('Object Type',105)
[void]$listView.Columns.Add('Status',95)
[void]$listView.Columns.Add('Subject',240)
[void]$listView.Columns.Add('Issuer',220)
[void]$listView.Columns.Add('Thumbprint',245)
[void]$listView.Columns.Add('NotAfter',145)
[void]$listView.Columns.Add('Days',65)
[void]$listView.Columns.Add('KB',70)
[void]$listView.Columns.Add('Source Path',330)
[void]$listView.Columns.Add('Detail',300)

$main.Controls.Add($listView,0,3)

$summaryLabel=New-Object Windows.Forms.Label
$summaryLabel.AutoSize=$true
$summaryLabel.Text='No repository audit has been run.'
$main.Controls.Add($summaryLabel,0,4)

$txtRuntimeLog=New-Object Windows.Forms.TextBox
$txtRuntimeLog.Dock='Fill';$txtRuntimeLog.Multiline=$true;$txtRuntimeLog.ReadOnly=$true
$txtRuntimeLog.ScrollBars='Vertical';$txtRuntimeLog.Font=New-Object Drawing.Font('Consolas',8.5)
$script:txtRuntimeLog=$txtRuntimeLog
$main.Controls.Add($txtRuntimeLog,0,5)

$statusStrip=New-Object Windows.Forms.StatusStrip
$statusMain=New-Object Windows.Forms.ToolStripStatusLabel
$statusMain.Spring=$true;$statusMain.Text='Ready';$script:statusMain=$statusMain
[void]$statusStrip.Items.Add($statusMain)

$statusMode=New-Object Windows.Forms.ToolStripStatusLabel
$statusMode.Text='Mode: DRY RUN'
[void]$statusStrip.Items.Add($statusMode)

$main.Controls.Add($statusStrip,0,6)

# =====================================================================================
# GUI events
# =====================================================================================
$btnBrowse.Add_Click({
    $dlg=New-Object Windows.Forms.FolderBrowserDialog
    $dlg.Description='Select certificate repository folder'
    $dlg.ShowNewFolderButton=$false
    if($dlg.ShowDialog()-eq[Windows.Forms.DialogResult]::OK){
        $txtPath.Text=$dlg.SelectedPath
    }
})

$chkDryRun.Add_CheckedChanged({
    $statusMode.Text=if($chkDryRun.Checked){'Mode: DRY RUN'}else{'Mode: COMMIT'}
})

$txtFilter.Add_TextChanged({
    Apply-InventoryFilter -Filter $txtFilter.Text
})

$btnClear.Add_Click({$txtFilter.Clear()})

$listView.Add_ColumnClick({
    param($sender,$e)
    Sort-Inventory -Column $e.Column
})

# Prevent non-expired rows from being selected.
$listView.Add_ItemCheck({
    param($sender,$e)
    try{
        $item=$listView.Items[$e.Index]
        if($item.Tag-and$item.Tag.Status-ne'EXPIRED'-and
           $e.NewValue-eq[Windows.Forms.CheckState]::Checked){
            $e.NewValue=[Windows.Forms.CheckState]::Unchecked
            Set-AppStatus "Selection blocked: '$($item.Tag.Name)' is $($item.Tag.Status). Only EXPIRED certificates can be deleted."
        }
    }catch{}
})

$btnSelectExpired.Add_Click({
    $selected=0
    foreach($i in $listView.Items){
        if($i.Tag-and$i.Tag.Status-eq'EXPIRED'){
            $i.Checked=$true
            $selected++
        }else{
            $i.Checked=$false
        }
    }
    Set-AppStatus "Selected $selected displayed expired certificate(s)."
})

$btnAudit.Add_Click({
    try{
        if([string]::IsNullOrWhiteSpace($txtPath.Text)){
            throw 'Select or enter a repository path.'
        }

        $root=Get-NormalizedPath $txtPath.Text
        if(-not(Test-Path -LiteralPath $root -PathType Container)){
            throw "Repository path does not exist: $root"
        }

        Write-AppLog "Repository audit started. Path='$root'; ExpiringDays=$([int]$numDays.Value)." INFO
        $script:Inventory=@(
            Invoke-RepositoryAudit -Root $root -ExpiringDays ([int]$numDays.Value)
        )
        $script:Displayed=@($script:Inventory)
        $txtFilter.Clear()
        Set-InventoryList -Rows $script:Displayed
        Apply-InventoryFilter -Filter ''

        Set-AppStatus 'Repository audit completed.'
    }catch{
        Show-AppMessage "Repository audit failed: $($_.Exception.Message)" Error
    }
})

$btnPreview.Add_Click({
    $selected=@(Get-CheckedExpiredRows)
    if($selected.Count-eq0){
        Show-AppMessage 'Select at least one EXPIRED certificate.' Information
        return
    }

    $bytes=0L
    foreach($r in $selected){$bytes+=[int64]([math]::Round($r.SizeKB*1KB,0))}

    $message=@"
Mode: $(if($chkDryRun.Checked){'DRY RUN'}else{'COMMIT'})

Selected expired certificates: $($selected.Count)
Approximate bytes: $bytes

Only EXPIRED certificate files are eligible.
Each file will be SHA-256 revalidated and reparsed immediately before deletion.
"@

    [void][Windows.Forms.MessageBox]::Show(
        $message,'Deletion Preview',
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Information
    )
})

$btnDelete.Add_Click({
    try{
        $selected=@(Get-CheckedExpiredRows)
        if($selected.Count-eq0){
            Show-AppMessage 'Select at least one EXPIRED certificate.' Information
            return
        }

        if($chkDryRun.Checked){
            foreach($r in $selected){
                Write-AppLog "DRY RUN: Would delete expired certificate '$($r.SourcePath)'." INFO
            }
            Show-AppMessage "Dry Run completed. $($selected.Count) expired certificate(s) would be deleted; no filesystem state was changed." Information
            return
        }

        $confirm=[Windows.Forms.MessageBox]::Show(
            "Delete $($selected.Count) selected EXPIRED certificate file(s)?`r`n`r`nThis operation does not use the Recycle Bin.",
            'Confirm Expired Certificate Deletion',
            [Windows.Forms.MessageBoxButtons]::YesNo,
            [Windows.Forms.MessageBoxIcon]::Warning,
            [Windows.Forms.MessageBoxDefaultButton]::Button2
        )

        if($confirm-ne[Windows.Forms.DialogResult]::Yes){
            Write-AppLog 'Deletion cancelled by operator.' WARN
            return
        }

        Set-AppStatus 'Deleting and verifying selected expired certificates...'
        $results=@(
            Remove-ExpiredCertificateFiles -Rows $selected -Confirm:$false
        )

        $success=@($results|Where-Object{$_.Result-eq'SUCCESS'}).Count
        $failed=@($results|Where-Object{$_.Result-eq'FAILED'}).Count
        $skipped=@($results|Where-Object{$_.Result-eq'SKIPPED'}).Count

        Write-AppLog ("Deletion summary: Success={0}; Failed={1}; Skipped={2}"-f$success,$failed,$skipped) INFO

        # Refresh repository after commit.
        $script:Inventory=@(
            Invoke-RepositoryAudit -Root (Get-NormalizedPath $txtPath.Text) -ExpiringDays ([int]$numDays.Value)
        )
        Apply-InventoryFilter -Filter $txtFilter.Text

        $message="Execution completed.`r`n`r`nDeleted: $success`r`nFailed: $failed`r`nSkipped: $skipped"
        if($failed-gt0){
            Show-AppMessage $message Warning
        }else{
            Show-AppMessage $message Information
        }
    }catch{
        Show-AppMessage "Deletion operation failed: $($_.Exception.Message)" Error
    }
})

$btnExport.Add_Click({
    try{
        if($script:Displayed.Count-eq0){
            throw 'There are no displayed rows to export.'
        }

        $dlg=New-Object Windows.Forms.SaveFileDialog
        $dlg.Filter='CSV (*.csv)|*.csv'
        $dlg.FileName="Certificate-Expiration-Audit-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"

        if($dlg.ShowDialog()-eq[Windows.Forms.DialogResult]::OK){
            $script:Displayed|
                Select-Object Name,Extension,ObjectType,Status,Subject,Issuer,Thumbprint,
                    NotBefore,NotAfter,DaysRemaining,SizeKB,SourcePath,SHA256,LastWriteTime,Detail|
                Export-Csv -LiteralPath $dlg.FileName -NoTypeInformation -Encoding UTF8

            Write-AppLog "Exported displayed audit rows to '$($dlg.FileName)'." SUCCESS
        }
    }catch{
        Show-AppMessage "Export failed: $($_.Exception.Message)" Error
    }
})

# =====================================================================================
# Main
# =====================================================================================
try{
    Write-AppLog "Starting $($script:ScriptName)." INFO
    Write-AppLog ("Host PowerShell: {0}; OS: {1}"-f
        $PSVersionTable.PSVersion,[Environment]::OSVersion.VersionString) INFO

    [void]$form.ShowDialog()
}catch{
    Write-AppLog "Fatal startup error: $($_.Exception.Message)" ERROR
    [void][Windows.Forms.MessageBox]::Show(
        "Fatal startup error:`r`n$($_.Exception.Message)",
        'Certificate Repository Expiration Audit & Cleanup',
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Error
    )
}finally{
    Write-AppLog "Closing $($script:ScriptName)." INFO
}

# End of script
