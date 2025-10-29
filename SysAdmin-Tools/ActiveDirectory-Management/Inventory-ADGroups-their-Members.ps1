<#
.SYNOPSIS
    GUI-based PowerShell tool to retrieve and export Active Directory group membership details.

.DESCRIPTION
    Provides a Windows Forms graphical interface for querying and exporting Active Directory (AD)
    group membership details to CSV. Supports domain selection, real-time search, multiple group
    selection, customizable attributes, structured logging, and Global Catalog (GC) querying for
    full forest coverage. Automatically skips invalid or orphaned AD objects and produces a summary
    report upon completion.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    2025-10-29 (Global Catalog integrated)
#>

# --- Hide Console ---
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
[Window]::ShowWindow([Window]::GetConsoleWindow(), 0)

# --- Load Libraries ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try { Import-Module ActiveDirectory -ErrorAction Stop } catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to load ActiveDirectory module.`r`n$($_.Exception.Message)",
        "Initialization Error",[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    return
}

# --- Logging Setup ---
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir  = "C:\Logs-TEMP"
$logPath = Join-Path $logDir "$scriptName.log"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

function Write-Log {
    param([string]$Message,[ValidateSet("INFO","WARNING","ERROR")]$Level="INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    try {
        if ($script:logBox -and -not $script:logBox.IsDisposed) {
            $script:logBox.SelectionStart = $script:logBox.TextLength
            $script:logBox.SelectionColor = switch ($Level) {
                "ERROR"   { 'Red' }
                "WARNING" { 'DarkOrange' }
                default   { 'Black' }
            }
            $script:logBox.AppendText("$entry`r`n")
            $script:logBox.ScrollToCaret()
        }
    } catch { }
    try { $entry | Out-File -FilePath $logPath -Append -Encoding UTF8 } catch { }
}

function Show-MessageBox {
    param([string]$Message,[string]$Title="Message",[Windows.Forms.MessageBoxIcon]$Icon=[Windows.Forms.MessageBoxIcon]::Information)
    [System.Windows.Forms.MessageBox]::Show($Message,$Title,[Windows.Forms.MessageBoxButtons]::OK,$Icon) | Out-Null
}

# --- GUI Setup ---
$form = New-Object Windows.Forms.Form -Property @{
    Text="Export Active Directory Group Members"
    Size=[System.Drawing.Size]::new(700,780)
    StartPosition='CenterScreen'
    FormBorderStyle='FixedSingle'
    MaximizeBox=$false
}

# Domain Selector
$comboDomain = New-Object Windows.Forms.ComboBox -Property @{
    Location=[System.Drawing.Point]::new(10,30)
    Size=[System.Drawing.Size]::new(660,25)
    DropDownStyle='DropDownList'
}
try {
    $domains = (Get-ADForest).Domains
    if ($domains) { $comboDomain.Items.AddRange($domains) }
} catch {
    Show-MessageBox "Unable to enumerate forest domains.`r`n$($_.Exception.Message)" "Domain Error" ([Windows.Forms.MessageBoxIcon]::Warning)
}
if ($comboDomain.Items.Count -gt 0) { $comboDomain.SelectedIndex = 0 }
$form.Controls.AddRange(@(
    (New-Object Windows.Forms.Label -Property @{Text="Select Domain:";Location=[System.Drawing.Point]::new(10,10);Size=[System.Drawing.Size]::new(300,20)}),
    $comboDomain
))

# Search Box
$txtSearch = New-Object Windows.Forms.TextBox -Property @{Location=[System.Drawing.Point]::new(10,80);Size=[System.Drawing.Size]::new(660,25)}
$btnClearSearch = New-Object Windows.Forms.Button -Property @{Text="Clear Search";Location=[System.Drawing.Point]::new(580,110);Size=[System.Drawing.Size]::new(90,25)}
$form.Controls.AddRange(@(
    (New-Object Windows.Forms.Label -Property @{Text="Search Groups:";Location=[System.Drawing.Point]::new(10,60);Size=[System.Drawing.Size]::new(300,20)}),
    $txtSearch,$btnClearSearch
))

# Group List
$listGroups = New-Object Windows.Forms.ListView -Property @{
    Location=[System.Drawing.Point]::new(10,140)
    Size=[System.Drawing.Size]::new(660,200)
    View='Details'
    CheckBoxes=$true
    FullRowSelect=$true
}
$listGroups.GetType().GetProperty('DoubleBuffered',[Reflection.BindingFlags]'NonPublic,Instance').SetValue($listGroups,$true,$null)|Out-Null
[void]$listGroups.Columns.Add("Group Name",640)
$chkSelectAll = New-Object Windows.Forms.CheckBox -Property @{Text="Select All";Location=[System.Drawing.Point]::new(10,120);Size=[System.Drawing.Size]::new(200,20)}
$form.Controls.AddRange(@($chkSelectAll,$listGroups))

# Attributes
$listAttr = New-Object Windows.Forms.CheckedListBox -Property @{Location=[System.Drawing.Point]::new(10,360);Size=[System.Drawing.Size]::new(660,100)}
[void]$listAttr.Items.AddRange(@(
    'Name','SamAccountName','UserPrincipalName','EmailAddress','DisplayName','Title',
    'Department','Company','Manager','Enabled','AccountLockoutTime','LastLogonDate','WhenCreated'
))
$form.Controls.AddRange(@(
    (New-Object Windows.Forms.Label -Property @{Text="Select Attributes:";Location=[System.Drawing.Point]::new(10,340);Size=[System.Drawing.Size]::new(300,20)}),
    $listAttr
))

# Output Folder
$txtOut = New-Object Windows.Forms.TextBox -Property @{Location=[System.Drawing.Point]::new(10,480);Size=[System.Drawing.Size]::new(560,25);Text=[Environment]::GetFolderPath("MyDocuments")}
$btnBrowse = New-Object Windows.Forms.Button -Property @{Text="Browse";Location=[System.Drawing.Point]::new(580,480);Size=[System.Drawing.Size]::new(90,25)}
$btnBrowse.Add_Click({$fbd=New-Object Windows.Forms.FolderBrowserDialog;if($fbd.ShowDialog() -eq "OK"){$txtOut.Text=$fbd.SelectedPath};$fbd.Dispose()})
$form.Controls.AddRange(@(
    (New-Object Windows.Forms.Label -Property @{Text="Output Folder:";Location=[System.Drawing.Point]::new(10,460);Size=[System.Drawing.Size]::new(300,20)}),
    $txtOut,$btnBrowse
))

# Log Box
$script:logBox = New-Object Windows.Forms.RichTextBox -Property @{
    Location=[System.Drawing.Point]::new(10,520);Size=[System.Drawing.Size]::new(660,80)
    ReadOnly=$true;ScrollBars='Vertical'
}
$form.Controls.AddRange(@(
    (New-Object Windows.Forms.Label -Property @{Text="Log:";Location=[System.Drawing.Point]::new(10,500);Size=[System.Drawing.Size]::new(200,20)}),
    $script:logBox
))

# Bottom Controls
$progress  = New-Object Windows.Forms.ProgressBar -Property @{Location=[System.Drawing.Point]::new(10,610);Size=[System.Drawing.Size]::new(660,15)}
$lblStatus = New-Object Windows.Forms.Label -Property @{Text="Ready";Location=[System.Drawing.Point]::new(10,630);Size=[System.Drawing.Size]::new(660,20)}
$btnExport = New-Object Windows.Forms.Button -Property @{Text="Export CSV";Location=[System.Drawing.Point]::new(10,660);Size=[System.Drawing.Size]::new(100,30)}
$btnClose  = New-Object Windows.Forms.Button -Property @{Text="Close";Location=[System.Drawing.Point]::new(570,660);Size=[System.Drawing.Size]::new(100,30)}
$btnClose.Add_Click({$form.Close()})
$form.Controls.AddRange(@($progress,$lblStatus,$btnExport,$btnClose))

# Data State
$script:allGroups=@()
$checkedGroups=New-Object 'System.Collections.Generic.HashSet[string]'

function Load-Groups {
    $listGroups.BeginUpdate();$listGroups.Items.Clear();$checkedGroups.Clear()
    try {
        $script:allGroups = Get-ADGroup -Server $comboDomain.SelectedItem -Filter * | Sort-Object Name
        foreach ($g in $script:allGroups) { if($g.Name){$item=New-Object Windows.Forms.ListViewItem $g.Name;$listGroups.Items.Add($item)|Out-Null}}
        $lblStatus.Text="$($script:allGroups.Count) groups loaded."
        Write-Log "Loaded $($script:allGroups.Count) groups from domain '$($comboDomain.SelectedItem)'."
    } catch {
        Write-Log "Error loading groups: $($_.Exception.Message)" "ERROR"
        Show-MessageBox "Error loading groups.`r`n$($_.Exception.Message)" "Load Error" ([Windows.Forms.MessageBoxIcon]::Error)
    }
    $listGroups.EndUpdate()
}
$comboDomain.Add_SelectedIndexChanged({Load-Groups})

# Debounced Search
$searchTimer=New-Object Windows.Forms.Timer; $searchTimer.Interval=300
$searchTimer.Add_Tick({
    $searchTimer.Stop();if(-not $script:allGroups){return}
    $s=$txtSearch.Text.ToLower().Trim()
    $listGroups.BeginUpdate();$listGroups.Items.Clear()
    foreach($g in $script:allGroups){
        if($g.Name -and ($s.Length -eq 0 -or $g.Name.ToLower().Contains($s))){
            $i=New-Object Windows.Forms.ListViewItem $g.Name
            if($checkedGroups.Contains($g.Name)){$i.Checked=$true}
            $listGroups.Items.Add($i)|Out-Null
        }
    };$listGroups.EndUpdate()
})
$txtSearch.Add_TextChanged({$searchTimer.Stop();$searchTimer.Start()})
$listGroups.Add_ItemChecked({
    param($s,$e)
    try{if($e.Item.Text){if($e.Item.Checked){$checkedGroups.Add($e.Item.Text)|Out-Null}else{$checkedGroups.Remove($e.Item.Text)|Out-Null}}}catch{}
})
$chkSelectAll.Add_CheckedChanged({
    $listGroups.BeginUpdate()
    foreach($i in $listGroups.Items){$i.Checked=$chkSelectAll.Checked;if($chkSelectAll.Checked){$checkedGroups.Add($i.Text)|Out-Null}else{$checkedGroups.Remove($i.Text)|Out-Null}}
    $listGroups.EndUpdate()
})
$btnClearSearch.Add_Click({$txtSearch.Text=""})

# --- Export Logic with Global Catalog ---
$btnExport.Add_Click({
    $domain=$comboDomain.SelectedItem
    if(-not $domain){Show-MessageBox "Select a domain." "Validation" ([Windows.Forms.MessageBoxIcon]::Warning);return}
    $attrs=@($listAttr.CheckedItems)
    $output=$txtOut.Text
    if(-not(Test-Path $output)){Show-MessageBox "Output folder does not exist." "Validation" ([Windows.Forms.MessageBoxIcon]::Warning);return}
    if($checkedGroups.Count -eq 0){Show-MessageBox "Select at least one group." "Validation" ([Windows.Forms.MessageBoxIcon]::Warning);return}
    if($attrs.Count -eq 0){Show-MessageBox "Select at least one attribute." "Validation" ([Windows.Forms.MessageBoxIcon]::Warning);return}

    $csvPath=Join-Path $output ("{0}_Export_{1}.csv" -f $domain,(Get-Date -Format 'yyyyMMdd_HHmmss'))
    $progress.Maximum=$checkedGroups.Count;$progress.Value=0;$lblStatus.Text="Exporting..."
    Write-Log "Starting export to '$csvPath' with $($checkedGroups.Count) group(s)."

    $results=New-Object System.Collections.Generic.List[object]
    $totalUsers=0;$totalSkipped=0;$errorGroups=0
    $gcServer=(Get-ADForest).RootDomain + ":3268"

    foreach($group in $checkedGroups){
        Write-Log "Processing group '$group'..." "INFO"
        $members=@()
        try {
            $members=Get-ADGroupMember -Identity $group -Server $domain -Recursive -ErrorAction Stop | Where-Object{$_.objectClass -eq 'user'}
        } catch {
            $errorGroups++;Write-Log "Failed to read group '$group': $($_.Exception.Message)" "WARNING"
        }

        foreach($m in $members){
            try{
                $user=Get-ADUser -Identity $m.DistinguishedName -Server $gcServer -Properties $attrs -ErrorAction Stop
                $obj=[ordered]@{Domain=$domain;Group=$group;UserDN=$m.DistinguishedName}
                foreach($a in $attrs){$obj[$a]=$user.$a}
                $results.Add([PSCustomObject]$obj);$totalUsers++
            }catch{$totalSkipped++}
        }

        Write-Log "Processed group '$group' with $($members.Count) member(s)." "INFO"
        if($progress.Value -lt $progress.Maximum){$progress.Value++}
        $lblStatus.Text="Processing group $($progress.Value) of $($progress.Maximum)..."
        [System.Windows.Forms.Application]::DoEvents()
    }

    try {
        Write-Log "Preparing to write CSV with $($results.Count) entries..." "INFO"
        $results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -Force
        if (Test-Path $csvPath) {
            Write-Log "CSV successfully created at: $csvPath"
            Write-Log "Summary: Groups=$($checkedGroups.Count) | Users=$totalUsers | Skipped=$totalSkipped | Errors=$errorGroups"
            $msg = "Export completed successfully.`r`nCSV: $csvPath`r`nGroups: $($checkedGroups.Count)`r`nUsers exported: $totalUsers`r`nSkipped: $totalSkipped`r`nErrors: $errorGroups"
            Show-MessageBox $msg "Export Summary" ([Windows.Forms.MessageBoxIcon]::Information)
            Start-Process $csvPath
        } else {
            Write-Log "CSV file was not created. Check permissions or path access." "ERROR"
            Show-MessageBox "The CSV file was not created. Verify permissions or path access." "Error" ([Windows.Forms.MessageBoxIcon]::Error)
        }
    } catch {
        Write-Log "Failed to write CSV: $($_.Exception.Message)" "ERROR"
        Show-MessageBox "Failed to write CSV.`r`n$($_.Exception.Message)" "Write Error" ([Windows.Forms.MessageBoxIcon]::Error)
    } finally {
        $lblStatus.Text="Ready"
    }
})

# --- Initial Load ---
Load-Groups
$form.Add_Shown({$form.Activate()})
[void]$form.ShowDialog()

# End of script
