<#
.SYNOPSIS
  Active Directory Bulk Password Reset Manager v2.0.0 Enterprise Edition.

.DESCRIPTION
  Enterprise Windows Forms tool for controlled bulk password resets of selected
  Active Directory user accounts within a selected domain and OU.

  The tool:
  - Supports Windows PowerShell 5.1 and Windows Server 2019
  - Hides the PowerShell console before importing ActiveDirectory
  - Discovers all domains in the current forest
  - Lists OUs for the selected domain
  - Provides live OU search/filtering by Name and DistinguishedName
  - Inventories users before any reset operation
  - Provides searchable/filterable and sortable user columns
  - Uses DistinguishedName + ObjectGUID stable identity
  - Uses Dry Run by default
  - Requires explicit per-user selection
  - Blocks adminCount=1 accounts by default
  - Blocks disabled accounts by default
  - Never writes the password value to logs
  - Converts the entered password to SecureString only at execution time
  - Resets password and optionally enforces ChangePasswordAtLogon
  - Re-reads the user after reset and verifies pwdLastSet/change-at-logon state
  - Uses explicit -Server targeting for all AD reads/writes
  - Produces SUCCESS / FAILED / SKIPPED counts
  - Produces timestamped audit logs in C:\Logs-TEMP

.AUTHOR
  Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
  2026-08-14-v2.1.0-ENTERPRISE-EDITION

.REQUIREMENTS
  - Windows PowerShell 5.1
  - Windows Server 2019
  - RSAT ActiveDirectory PowerShell module
  - Delegated rights sufficient to reset passwords on selected users
#>

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param([switch]$ShowConsole)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

try {
    if (-not $ShowConsole) {
        try {
            Add-Type -Name Win32ShowWindowAsync -Namespace ConsoleControl -MemberDefinition @"
[DllImport("user32.dll")]
public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
[DllImport("kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
"@
            $ptr=[ConsoleControl.Win32ShowWindowAsync]::GetConsoleWindow()
            if($ptr-ne[IntPtr]::Zero){[void][ConsoleControl.Win32ShowWindowAsync]::ShowWindowAsync($ptr,0)}
        } catch {}
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    if(-not(Get-Module -ListAvailable ActiveDirectory)){throw 'ActiveDirectory module is not available.'}
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Error "Initialization failed: $($_.Exception.Message)"
    return
}

$script:ScriptName=[IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:LogRoot='C:\Logs-TEMP'
$script:RunStamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$script:LogFile=Join-Path $script:LogRoot "$($script:ScriptName)-$($script:RunStamp).log"
$script:Users=@()
$script:DisplayedUsers=@()
$script:OUs=@()
$script:SortColumn=-1
$script:SortDescending=$false
$script:CurrentDomain=$null
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
    try{Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8}catch{}
    if($script:txtRuntimeLog-and-not$script:txtRuntimeLog.IsDisposed){
        $script:txtRuntimeLog.AppendText($line+[Environment]::NewLine)
        $script:txtRuntimeLog.SelectionStart=$script:txtRuntimeLog.Text.Length
        $script:txtRuntimeLog.ScrollToCaret()
    }elseif($ShowConsole){Write-Host $line}
}

function Set-AppStatus {
    param([string]$Text)
    if($script:statusMain-and-not$script:statusMain.IsDisposed){
        $script:statusMain.Text=$Text
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Show-AppMessage {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('Information','Warning','Error')][string]$Type='Information'
    )
    switch($Type){
        'Error'{$icon=[System.Windows.Forms.MessageBoxIcon]::Error;Write-AppLog $Message ERROR}
        'Warning'{$icon=[System.Windows.Forms.MessageBoxIcon]::Warning;Write-AppLog $Message WARN}
        default{$icon=[System.Windows.Forms.MessageBoxIcon]::Information;Write-AppLog $Message INFO}
    }
    [void][System.Windows.Forms.MessageBox]::Show($Message,$Type,[System.Windows.Forms.MessageBoxButtons]::OK,$icon)
}

function Get-ForestDomains {
    $forest=Get-ADForest -ErrorAction Stop
    return @($forest.Domains|Sort-Object)
}

function Get-DomainOUs {
    param([Parameter(Mandatory=$true)][string]$Server)
    return @(
        Get-ADOrganizationalUnit -Server $Server -Filter * -ErrorAction Stop|
        Select-Object Name,DistinguishedName,ObjectGUID|
        Sort-Object DistinguishedName
    )
}

function Get-OUUsers {
    param(
        [Parameter(Mandatory=$true)][string]$Server,
        [Parameter(Mandatory=$true)][string]$SearchBase
    )

    $users=@(
        Get-ADUser -Server $Server -SearchBase $SearchBase -SearchScope Subtree -Filter * `
          -Properties DisplayName,Enabled,Title,Description,adminCount,pwdLastSet,
                      PasswordNeverExpires,LockedOut,DistinguishedName,ObjectGUID `
          -ErrorAction Stop |
        Sort-Object SamAccountName
    )

    return @(
        foreach($u in $users){
            [pscustomobject]@{
                SamAccountName=[string]$u.SamAccountName
                DisplayName=[string]$u.DisplayName
                Enabled=[bool]$u.Enabled
                Title=[string]$u.Title
                Description=[string]$u.Description
                AdminCount=if($null-eq$u.adminCount){0}else{[int]$u.adminCount}
                LockedOut=[bool]$u.LockedOut
                PasswordNeverExpires=[bool]$u.PasswordNeverExpires
                PwdLastSet=[Int64]$u.pwdLastSet
                DistinguishedName=[string]$u.DistinguishedName
                ObjectGUID=[Guid]$u.ObjectGUID
            }
        }
    )
}

function Set-UserList {
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Users)

    $checked=@{}
    foreach($i in $script:listView.CheckedItems){
        if($i.Tag){$checked[[string]$i.Tag.ObjectGUID]=$true}
    }

    $script:listView.BeginUpdate()
    try{
        $script:listView.Items.Clear()
        foreach($u in $Users){
            $item=New-Object System.Windows.Forms.ListViewItem($u.SamAccountName)
            [void]$item.SubItems.Add($u.DisplayName)
            [void]$item.SubItems.Add([string]$u.Enabled)
            [void]$item.SubItems.Add($u.Title)
            [void]$item.SubItems.Add($u.Description)
            [void]$item.SubItems.Add([string]$u.AdminCount)
            [void]$item.SubItems.Add([string]$u.LockedOut)
            [void]$item.SubItems.Add([string]$u.PasswordNeverExpires)
            [void]$item.SubItems.Add($u.DistinguishedName)
            $item.Tag=$u
            if($checked.ContainsKey([string]$u.ObjectGUID)){$item.Checked=$true}
            [void]$script:listView.Items.Add($item)
        }
    }finally{$script:listView.EndUpdate()}
}

function Test-UserMatchesFilter {
    param($User,[string]$Filter)
    if([string]::IsNullOrWhiteSpace($Filter)){return $true}
    $n=$Filter.Trim()
    foreach($v in @(
        $User.SamAccountName,$User.DisplayName,[string]$User.Enabled,$User.Title,
        $User.Description,[string]$User.AdminCount,[string]$User.LockedOut,
        [string]$User.PasswordNeverExpires,$User.DistinguishedName
    )){
        if(([string]$v).IndexOf($n,[StringComparison]::OrdinalIgnoreCase)-ge 0){return $true}
    }
    return $false
}

function Apply-UserFilter {
    param([string]$Filter)
    $script:DisplayedUsers=@($script:Users|Where-Object{Test-UserMatchesFilter $_ $Filter})
    Set-UserList -Users $script:DisplayedUsers
    Set-AppStatus ("Displayed {0} of {1} user(s)."-f$script:DisplayedUsers.Count,$script:Users.Count)
}

function Sort-Users {
    param([int]$Column,[bool]$Descending)
    switch($Column){
        0{$p='SamAccountName'}1{$p='DisplayName'}2{$p='Enabled'}3{$p='Title'}
        4{$p='Description'}5{$p='AdminCount'}6{$p='LockedOut'}7{$p='PasswordNeverExpires'}
        8{$p='DistinguishedName'}default{$p='SamAccountName'}
    }
    $script:Users=@($script:Users|Sort-Object -Property $p -Descending:$Descending)
}

function Get-CheckedUsers {
    $a=New-Object System.Collections.ArrayList
    foreach($i in $script:listView.CheckedItems){if($i.Tag){[void]$a.Add($i.Tag)}}
    return @($a)
}

function Test-ResetEligibility {
    param(
        [Parameter(Mandatory=$true)]$User,
        [switch]$AllowDisabled,
        [switch]$AllowAdminCount
    )

    if(-not$AllowAdminCount-and$User.AdminCount-eq 1){
        return [pscustomobject]@{Eligible=$false;Reason='adminCount=1 protected/sensitive account.'}
    }
    if(-not$AllowDisabled-and-not$User.Enabled){
        return [pscustomobject]@{Eligible=$false;Reason='Account is disabled.'}
    }
    return [pscustomobject]@{Eligible=$true;Reason='Eligible.'}
}

function Show-Preview {
    param([object[]]$Users,[bool]$AllowDisabled,[bool]$AllowAdminCount)

    $lines=New-Object System.Collections.Generic.List[string]
    $eligible=0;$blocked=0
    foreach($u in $Users){
        $e=Test-ResetEligibility -User $u -AllowDisabled:$AllowDisabled -AllowAdminCount:$AllowAdminCount
        if($e.Eligible){$eligible++}else{$blocked++}
        $lines.Add(("{0,-24} {1,-8} adminCount={2}  {3}"-f$u.SamAccountName,
            $(if($e.Eligible){'READY'}else{'BLOCKED'}),$u.AdminCount,$e.Reason))
    }

    $text="Mode: $(if($script:chkDryRun.Checked){'DRY RUN'}else{'COMMIT'})`r`nSelected: $($Users.Count)`r`nEligible: $eligible`r`nBlocked: $blocked`r`n`r`n"+($lines-join"`r`n")
    $dlg=New-Object System.Windows.Forms.Form
    $dlg.Text='Password Reset Preview';$dlg.Size=New-Object System.Drawing.Size(850,550);$dlg.StartPosition='CenterParent'
    $box=New-Object System.Windows.Forms.TextBox
    $box.Multiline=$true;$box.ReadOnly=$true;$box.ScrollBars='Both';$box.WordWrap=$false
    $box.Font=New-Object System.Drawing.Font('Consolas',9);$box.Dock='Fill';$box.Text=$text
    $dlg.Controls.Add($box)
    [void]$dlg.ShowDialog()
}

function Reset-SelectedUserPasswords {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)][object[]]$Users,
        [Parameter(Mandatory=$true)][string]$Server,
        [Parameter(Mandatory=$true)][Security.SecureString]$Password,
        [Parameter(Mandatory=$true)][bool]$ChangeAtLogon,
        [Parameter(Mandatory=$true)][bool]$AllowDisabled,
        [Parameter(Mandatory=$true)][bool]$AllowAdminCount
    )

    $results=New-Object System.Collections.ArrayList

    foreach($record in $Users){
        try{
            $eligibility=Test-ResetEligibility -User $record -AllowDisabled:$AllowDisabled -AllowAdminCount:$AllowAdminCount
            if(-not$eligibility.Eligible){
                Write-AppLog "Skipped '$($record.SamAccountName)': $($eligibility.Reason)" WARN
                [void]$results.Add([pscustomobject]@{User=$record.SamAccountName;Result='SKIPPED';Detail=$eligibility.Reason})
                continue
            }

            $current=Get-ADUser -Identity $record.DistinguishedName -Server $Server `
                -Properties ObjectGUID,Enabled,adminCount,pwdLastSet -ErrorAction Stop

            if([Guid]$current.ObjectGUID-ne[Guid]$record.ObjectGUID){
                throw 'ObjectGUID changed since discovery.'
            }

            if(-not$AllowAdminCount-and$current.adminCount-eq 1){throw 'Account became adminCount=1 before commit.'}
            if(-not$AllowDisabled-and-not$current.Enabled){throw 'Account became disabled before commit.'}

            $beforePwdLastSet=[Int64]$current.pwdLastSet
            $target="$($record.SamAccountName) [$($record.DistinguishedName)]"

            if($PSCmdlet.ShouldProcess($target,'Reset AD password')){
                Set-ADAccountPassword -Identity $record.DistinguishedName -Server $Server `
                    -Reset -NewPassword $Password -ErrorAction Stop

                Set-ADUser -Identity $record.DistinguishedName -Server $Server `
                    -ChangePasswordAtLogon:$ChangeAtLogon -ErrorAction Stop

                $verified=Get-ADUser -Identity $record.DistinguishedName -Server $Server `
                    -Properties ObjectGUID,pwdLastSet -ErrorAction Stop

                if([Guid]$verified.ObjectGUID-ne[Guid]$record.ObjectGUID){
                    throw 'Post-reset ObjectGUID verification failed.'
                }

                $afterPwdLastSet=[Int64]$verified.pwdLastSet

                if($ChangeAtLogon){
                    if($afterPwdLastSet-ne 0){
                        throw "Verification failed: ChangePasswordAtLogon expected pwdLastSet=0; effective value=$afterPwdLastSet."
                    }
                }else{
                    if($afterPwdLastSet-eq$beforePwdLastSet){
                        Write-AppLog "Password reset for '$($record.SamAccountName)' completed; pwdLastSet value did not visibly change during immediate verification." WARN
                    }
                }

                Write-AppLog "Password reset verified for '$($record.SamAccountName)'. ChangeAtLogon=$ChangeAtLogon." SUCCESS
                [void]$results.Add([pscustomobject]@{User=$record.SamAccountName;Result='SUCCESS';Detail='Password reset completed and AD state verified.'})
            }
        }catch{
            Write-AppLog "Password reset failed for '$($record.SamAccountName)': $($_.Exception.Message)" ERROR
            [void]$results.Add([pscustomobject]@{User=$record.SamAccountName;Result='FAILED';Detail=$_.Exception.Message})
        }
    }
    return @($results)
}

# =====================================================================================
# GUI
# =====================================================================================
$form=New-Object System.Windows.Forms.Form
$form.Text='AD Bulk Password Reset Manager - Enterprise Edition'
$form.Size=New-Object System.Drawing.Size(1320,840)
$form.MinimumSize=New-Object System.Drawing.Size(1080,720)
$form.StartPosition='CenterScreen'

$main=New-Object System.Windows.Forms.TableLayoutPanel
$main.Dock='Fill';$main.Padding=New-Object System.Windows.Forms.Padding(10);$main.ColumnCount=1;$main.RowCount=8
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',60)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',40)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$form.Controls.Add($main)

$p1=New-Object System.Windows.Forms.FlowLayoutPanel;$p1.Dock='Fill';$p1.AutoSize=$true;$p1.WrapContents=$true
$l=New-Object System.Windows.Forms.Label;$l.Text='Domain:';$l.AutoSize=$true;$l.Margin=New-Object System.Windows.Forms.Padding(3,7,3,3);$p1.Controls.Add($l)
$cmbDomain=New-Object System.Windows.Forms.ComboBox;$cmbDomain.Width=300;$cmbDomain.DropDownStyle='DropDownList';$p1.Controls.Add($cmbDomain)

$lOUSearch=New-Object System.Windows.Forms.Label;$lOUSearch.Text='OU Search:';$lOUSearch.AutoSize=$true;$lOUSearch.Margin=New-Object System.Windows.Forms.Padding(20,7,3,3);$p1.Controls.Add($lOUSearch)
$txtOUSearch=New-Object System.Windows.Forms.TextBox;$txtOUSearch.Width=260;$p1.Controls.Add($txtOUSearch)
$btnClearOUSearch=New-Object System.Windows.Forms.Button;$btnClearOUSearch.Text='Clear OU Search';$btnClearOUSearch.Width=120;$p1.Controls.Add($btnClearOUSearch)

$l2=New-Object System.Windows.Forms.Label;$l2.Text='OU:';$l2.AutoSize=$true;$l2.Margin=New-Object System.Windows.Forms.Padding(20,7,3,3);$p1.Controls.Add($l2)
$cmbOU=New-Object System.Windows.Forms.ComboBox;$cmbOU.Width=620;$cmbOU.DropDownStyle='DropDownList';$cmbOU.DisplayMember='DistinguishedName';$p1.Controls.Add($cmbOU)
$btnLoad=New-Object System.Windows.Forms.Button;$btnLoad.Text='Load Users';$btnLoad.Width=100;$p1.Controls.Add($btnLoad)
$main.Controls.Add($p1,0,0)

$p2=New-Object System.Windows.Forms.FlowLayoutPanel;$p2.Dock='Fill';$p2.AutoSize=$true
$l3=New-Object System.Windows.Forms.Label;$l3.Text='Filter displayed columns:';$l3.AutoSize=$true;$l3.Margin=New-Object System.Windows.Forms.Padding(3,7,3,3);$p2.Controls.Add($l3)
$txtFilter=New-Object System.Windows.Forms.TextBox;$txtFilter.Width=500;$p2.Controls.Add($txtFilter)
$btnClear=New-Object System.Windows.Forms.Button;$btnClear.Text='Clear Filter';$btnClear.Width=100;$p2.Controls.Add($btnClear)
$btnSelect=New-Object System.Windows.Forms.Button;$btnSelect.Text='Select All';$btnSelect.Width=100;$p2.Controls.Add($btnSelect)
$main.Controls.Add($p2,0,1)

$p3=New-Object System.Windows.Forms.FlowLayoutPanel;$p3.Dock='Fill';$p3.AutoSize=$true
$l4=New-Object System.Windows.Forms.Label;$l4.Text='Default Password:';$l4.AutoSize=$true;$l4.Margin=New-Object System.Windows.Forms.Padding(3,7,3,3);$p3.Controls.Add($l4)
$txtPassword=New-Object System.Windows.Forms.TextBox;$txtPassword.Width=280;$txtPassword.UseSystemPasswordChar=$true;$p3.Controls.Add($txtPassword)
$chkChange=New-Object System.Windows.Forms.CheckBox;$chkChange.Text='Require change at next logon';$chkChange.Checked=$true;$chkChange.AutoSize=$true;$p3.Controls.Add($chkChange)
$chkAllowDisabled=New-Object System.Windows.Forms.CheckBox;$chkAllowDisabled.Text='Allow disabled accounts';$chkAllowDisabled.AutoSize=$true;$p3.Controls.Add($chkAllowDisabled)
$chkAllowAdmin=New-Object System.Windows.Forms.CheckBox;$chkAllowAdmin.Text='Allow adminCount=1 accounts';$chkAllowAdmin.AutoSize=$true;$p3.Controls.Add($chkAllowAdmin)
$chkDryRun=New-Object System.Windows.Forms.CheckBox;$chkDryRun.Text='Dry Run';$chkDryRun.Checked=$true;$chkDryRun.AutoSize=$true;$script:chkDryRun=$chkDryRun;$p3.Controls.Add($chkDryRun)
$btnPreview=New-Object System.Windows.Forms.Button;$btnPreview.Text='Preview';$btnPreview.Width=90;$p3.Controls.Add($btnPreview)
$btnReset=New-Object System.Windows.Forms.Button;$btnReset.Text='Reset Selected';$btnReset.Width=115;$p3.Controls.Add($btnReset)
$main.Controls.Add($p3,0,2)

$listView=New-Object System.Windows.Forms.ListView
$listView.Dock='Fill';$listView.View='Details';$listView.CheckBoxes=$true;$listView.FullRowSelect=$true;$listView.GridLines=$true
[void]$listView.Columns.Add('sAMAccountName',145)
[void]$listView.Columns.Add('Display Name',180)
[void]$listView.Columns.Add('Enabled',70)
[void]$listView.Columns.Add('Title',160)
[void]$listView.Columns.Add('Description',190)
[void]$listView.Columns.Add('adminCount',80)
[void]$listView.Columns.Add('LockedOut',75)
[void]$listView.Columns.Add('PwdNeverExpires',100)
[void]$listView.Columns.Add('DistinguishedName',420)
$script:listView=$listView
$main.Controls.Add($listView,0,3)

$summary=New-Object System.Windows.Forms.Label;$summary.AutoSize=$true;$summary.Text='No user inventory loaded.';$main.Controls.Add($summary,0,4)
$note=New-Object System.Windows.Forms.Label;$note.AutoSize=$true;$note.MaximumSize=New-Object System.Drawing.Size(1240,0)
$note.Text='Safety defaults: Dry Run enabled; disabled users blocked; adminCount=1 accounts blocked; only explicitly checked users are eligible. Password values are never written to the log.'
$main.Controls.Add($note,0,5)

$txtRuntimeLog=New-Object System.Windows.Forms.TextBox;$txtRuntimeLog.Dock='Fill';$txtRuntimeLog.Multiline=$true;$txtRuntimeLog.ReadOnly=$true;$txtRuntimeLog.ScrollBars='Vertical';$txtRuntimeLog.Font=New-Object System.Drawing.Font('Consolas',8.5);$script:txtRuntimeLog=$txtRuntimeLog
$main.Controls.Add($txtRuntimeLog,0,6)

$statusStrip=New-Object System.Windows.Forms.StatusStrip
$statusMain=New-Object System.Windows.Forms.ToolStripStatusLabel;$statusMain.Spring=$true;$statusMain.Text='Ready';$script:statusMain=$statusMain;[void]$statusStrip.Items.Add($statusMain)
$statusMode=New-Object System.Windows.Forms.ToolStripStatusLabel;$statusMode.Text='Mode: DRY RUN';[void]$statusStrip.Items.Add($statusMode)
$main.Controls.Add($statusStrip,0,7)

function Refresh-OUCombo {
    param([AllowEmptyString()][string]$FilterText='')

    $selectedDn=$null
    if($null-ne$cmbOU.SelectedItem){
        $selectedDn=[string]$cmbOU.SelectedItem.DistinguishedName
    }

    $filtered=@(
        $script:OUs | Where-Object {
            if([string]::IsNullOrWhiteSpace($FilterText)){
                $true
            }else{
                ([string]$_.Name).IndexOf($FilterText,[StringComparison]::OrdinalIgnoreCase)-ge 0 -or
                ([string]$_.DistinguishedName).IndexOf($FilterText,[StringComparison]::OrdinalIgnoreCase)-ge 0
            }
        }
    )

    $cmbOU.BeginUpdate()
    try{
        $cmbOU.Items.Clear()
        foreach($ou in $filtered){[void]$cmbOU.Items.Add($ou)}

        $restored=$false
        if($selectedDn){
            for($i=0;$i-lt$cmbOU.Items.Count;$i++){
                if([string]$cmbOU.Items[$i].DistinguishedName-eq$selectedDn){
                    $cmbOU.SelectedIndex=$i
                    $restored=$true
                    break
                }
            }
        }

        if(-not$restored-and$cmbOU.Items.Count-gt 0){
            $cmbOU.SelectedIndex=0
        }
    }finally{
        $cmbOU.EndUpdate()
    }

    Set-AppStatus ("Displayed {0} of {1} OU(s)."-f$filtered.Count,$script:OUs.Count)
}

function Load-OUs {
    try{
        $d=[string]$cmbDomain.SelectedItem
        if([string]::IsNullOrWhiteSpace($d)){return}
        Set-AppStatus "Loading OUs from $d..."
        $script:OUs=@(Get-DomainOUs -Server $d)
        $txtOUSearch.Clear()
        Refresh-OUCombo
        Write-AppLog "Loaded $($script:OUs.Count) OUs from '$d'." SUCCESS
    }catch{Show-AppMessage "OU discovery failed: $($_.Exception.Message)" Error}
}

$cmbDomain.Add_SelectedIndexChanged({Load-OUs})

$txtOUSearch.Add_TextChanged({
    try{
        Refresh-OUCombo -FilterText $txtOUSearch.Text.Trim()
    }catch{
        Write-AppLog "OU search failed: $($_.Exception.Message)" ERROR
    }
})

$btnClearOUSearch.Add_Click({
    $txtOUSearch.Clear()
})
$chkDryRun.Add_CheckedChanged({$statusMode.Text=if($chkDryRun.Checked){'Mode: DRY RUN'}else{'Mode: COMMIT'}})
$txtFilter.Add_TextChanged({Apply-UserFilter -Filter $txtFilter.Text;$summary.Text="Displayed: $($script:DisplayedUsers.Count) | Total: $($script:Users.Count)"})
$btnClear.Add_Click({$txtFilter.Clear()})
$btnSelect.Add_Click({foreach($i in $script:listView.Items){$i.Checked=$true}})
$listView.Add_ColumnClick({
    param($sender,$e)
    if($script:SortColumn-eq$e.Column){$script:SortDescending=-not$script:SortDescending}else{$script:SortColumn=$e.Column;$script:SortDescending=$false}
    Sort-Users -Column $script:SortColumn -Descending $script:SortDescending
    Apply-UserFilter -Filter $txtFilter.Text
})
$btnLoad.Add_Click({
    try{
        if($null-eq$cmbOU.SelectedItem){throw 'Select an OU.'}
        $script:CurrentDomain=[string]$cmbDomain.SelectedItem
        $ou=[string]$cmbOU.SelectedItem.DistinguishedName
        Set-AppStatus 'Loading users...'
        $script:Users=@(Get-OUUsers -Server $script:CurrentDomain -SearchBase $ou)
        $script:DisplayedUsers=@($script:Users)
        $txtFilter.Clear()
        Set-UserList -Users $script:DisplayedUsers
        $summary.Text="Users loaded: $($script:Users.Count)"
        Write-AppLog "Loaded $($script:Users.Count) users from OU '$ou' in '$($script:CurrentDomain)'." SUCCESS
    }catch{Show-AppMessage "User inventory failed: $($_.Exception.Message)" Error}
})
$btnPreview.Add_Click({
    $u=@(Get-CheckedUsers)
    if($u.Count-eq 0){Show-AppMessage 'Select at least one user.' Warning;return}
    Show-Preview -Users $u -AllowDisabled:$chkAllowDisabled.Checked -AllowAdminCount:$chkAllowAdmin.Checked
})
$btnReset.Add_Click({
    try{
        $u=@(Get-CheckedUsers)
        if($u.Count-eq 0){throw 'Select at least one user.'}
        if([string]::IsNullOrWhiteSpace($txtPassword.Text)){throw 'Enter the default password.'}

        Show-Preview -Users $u -AllowDisabled:$chkAllowDisabled.Checked -AllowAdminCount:$chkAllowAdmin.Checked

        if($chkDryRun.Checked){
            Write-AppLog "DRY RUN: Selected=$($u.Count); no passwords reset."
            Show-AppMessage 'Dry Run completed. No passwords were changed.' Information
            return
        }

        $eligible=@($u|Where-Object{(Test-ResetEligibility $_ -AllowDisabled:$chkAllowDisabled.Checked -AllowAdminCount:$chkAllowAdmin.Checked).Eligible})
        if($eligible.Count-eq 0){throw 'No selected users are eligible under the current safety settings.'}

        $confirm=@"
COMMIT bulk password reset?

Domain: $($script:CurrentDomain)
Selected users: $($u.Count)
Eligible users: $($eligible.Count)
Require change at next logon: $($chkChange.Checked)
Allow disabled accounts: $($chkAllowDisabled.Checked)
Allow adminCount=1: $($chkAllowAdmin.Checked)

The password value will not be written to the audit log.
"@
        $ans=[System.Windows.Forms.MessageBox]::Show($confirm,'Confirm Bulk Password Reset',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
        if($ans-ne[System.Windows.Forms.DialogResult]::Yes){Write-AppLog 'Commit cancelled by operator.' WARN;return}

        $secure=ConvertTo-SecureString -String $txtPassword.Text -AsPlainText -Force
        $txtPassword.Clear()

        Set-AppStatus 'Resetting selected user passwords...'
        $r=@(Reset-SelectedUserPasswords -Users $u -Server $script:CurrentDomain -Password $secure `
            -ChangeAtLogon:$chkChange.Checked -AllowDisabled:$chkAllowDisabled.Checked `
            -AllowAdminCount:$chkAllowAdmin.Checked -Confirm:$false)

        $success=@($r|Where-Object Result -eq 'SUCCESS').Count
        $failed=@($r|Where-Object Result -eq 'FAILED').Count
        $skipped=@($r|Where-Object Result -eq 'SKIPPED').Count

        $msg="Execution completed.`r`n`r`nSuccess: $success`r`nFailed: $failed`r`nSkipped: $skipped`r`n`r`nLog: $($script:LogFile)"
        if($failed-gt 0){Show-AppMessage $msg Warning}else{
            Write-AppLog ("Reset summary: Success={0}; Failed={1}; Skipped={2}"-f$success,$failed,$skipped) SUCCESS
            [void][System.Windows.Forms.MessageBox]::Show($msg,'Execution Summary',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)
        }
        Set-AppStatus ("Completed: Success={0}, Failed={1}, Skipped={2}"-f$success,$failed,$skipped)
    }catch{Show-AppMessage "Execution failed: $($_.Exception.Message)" Error}
})

try{
    Write-AppLog "Starting $($script:ScriptName)."
    Write-AppLog ("Host PowerShell: {0}; OS: {1}"-f$PSVersionTable.PSVersion,[Environment]::OSVersion.VersionString)
    $domains=@(Get-ForestDomains)
    foreach($d in $domains){[void]$cmbDomain.Items.Add($d)}
    if($cmbDomain.Items.Count-eq 0){throw 'No AD domains discovered.'}
    $cmbDomain.SelectedIndex=0
    Write-AppLog ("Discovered forest domains: {0}"-f($domains-join', ')) SUCCESS
    [void]$form.ShowDialog()
}catch{
    Write-AppLog "Fatal startup error: $($_.Exception.Message)" ERROR
    [void][System.Windows.Forms.MessageBox]::Show("Fatal startup error:`r`n$($_.Exception.Message)",'AD Bulk Password Reset Manager',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
}finally{
    Write-AppLog "Closing $($script:ScriptName)."
}

# End of script
