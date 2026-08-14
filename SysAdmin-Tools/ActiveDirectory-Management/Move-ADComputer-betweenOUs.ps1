<#
.SYNOPSIS
  Active Directory Computer OU Move Manager v2.0.0 Enterprise Edition.

.DESCRIPTION
  Enterprise Windows Forms tool for safely moving Active Directory computer accounts
  between Organizational Units.

  Supported workflows:
    - Load computer names from a TXT file, resolve them in the selected domain, review
      the resolved accounts, and move selected computers to a target OU.
    - Load computer accounts from a selected source OU, review them, and move selected
      computers to a target OU.

  The tool:
  - Supports Windows PowerShell 5.1 and Windows Server 2019
  - Hides the console before importing ActiveDirectory
  - Discovers all forest domains
  - Provides live source/target OU search by Name and DistinguishedName
  - Provides searchable/filterable and sortable computer result columns
  - Uses DistinguishedName + ObjectGUID stable identity
  - Uses Dry Run by default
  - Requires explicit per-computer checkbox selection
  - Validates that source and target OUs are different
  - Revalidates object identity immediately before every move
  - Skips computers already located in the target OU
  - Uses explicit -Server targeting for every AD read/write
  - Re-reads each computer after Move-ADObject and verifies the new parent OU
  - Continues processing when an individual computer fails
  - Produces SUCCESS / FAILED / SKIPPED counts
  - Produces timestamped audit logs in C:\Logs-TEMP

.AUTHOR
  Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
  2026-08-14-v2.0.1-ENTERPRISE-STABLE

.REQUIREMENTS
  - Windows PowerShell 5.1
  - Windows Server 2019
  - RSAT ActiveDirectory PowerShell module
  - Rights to read and move computer objects in the selected AD domain
#>

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param([switch]$ShowConsole)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

# =====================================================================================
# Assemblies and process mode
# =====================================================================================
try {
    if(-not$ShowConsole){
        try{
            Add-Type -Name Win32ShowWindowAsync -Namespace ConsoleControl -MemberDefinition @"
[DllImport("user32.dll")]
public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
[DllImport("kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
"@
            $ptr=[ConsoleControl.Win32ShowWindowAsync]::GetConsoleWindow()
            if($ptr-ne[IntPtr]::Zero){
                [void][ConsoleControl.Win32ShowWindowAsync]::ShowWindowAsync($ptr,0)
            }
        }catch{}
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    if(-not(Get-Module -ListAvailable -Name ActiveDirectory)){
        throw 'The ActiveDirectory PowerShell module is not installed or available.'
    }
    Import-Module ActiveDirectory -ErrorAction Stop
}catch{
    Write-Error "Initialization failed: $($_.Exception.Message)"
    return
}

# =====================================================================================
# Globals
# =====================================================================================
$script:ScriptName=[IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:LogRoot='C:\Logs-TEMP'
$script:RunStamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$script:LogFile=Join-Path $script:LogRoot "$($script:ScriptName)-$($script:RunStamp).log"

$script:AllOUs=@()
$script:ComputerCandidates=@()
$script:DisplayedComputers=@()
$script:CurrentDomain=$null
$script:SortColumn=-1
$script:SortDescending=$false

$script:listView=$null
$script:txtRuntimeLog=$null
$script:statusMain=$null
$script:statusMode=$null
$script:chkDryRun=$null

if(-not(Test-Path -LiteralPath $script:LogRoot)){
    New-Item -ItemType Directory -Path $script:LogRoot -Force|Out-Null
}

# =====================================================================================
# Logging / UI helpers
# =====================================================================================
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

function Get-ExecutionModeLabel {
    if($script:chkDryRun-and$script:chkDryRun.Checked){return 'DRY RUN'}
    return 'COMMIT'
}

# =====================================================================================
# AD discovery
# =====================================================================================
function Get-ForestDomains {
    $forest=Get-ADForest -ErrorAction Stop
    return @($forest.Domains|Sort-Object)
}

function Get-DomainOUs {
    param([Parameter(Mandatory=$true)][string]$Server)

    return @(
        Get-ADOrganizationalUnit -Server $Server -Filter * `
            -Properties ObjectGUID,ProtectedFromAccidentalDeletion `
            -ErrorAction Stop |
        Select-Object Name,DistinguishedName,ObjectGUID,ProtectedFromAccidentalDeletion |
        Sort-Object DistinguishedName
    )
}

function Get-ParentDN {
    param([Parameter(Mandatory=$true)][string]$DistinguishedName)

    $parts=$DistinguishedName -split '(?<!\\),',2
    if($parts.Count-lt 2){return ''}
    return $parts[1]
}

function Test-OUStillExists {
    param(
        [Parameter(Mandatory=$true)]$OU,
        [Parameter(Mandatory=$true)][string]$Server
    )
    try{
        $current=Get-ADOrganizationalUnit -Identity $OU.DistinguishedName -Server $Server `
            -Properties ObjectGUID -ErrorAction Stop
        return ([Guid]$current.ObjectGUID-eq[Guid]$OU.ObjectGUID)
    }catch{return $false}
}

# =====================================================================================
# OU search/filter helpers
# =====================================================================================
function Get-FilteredOUs {
    param([AllowEmptyString()][string]$FilterText)

    if([string]::IsNullOrWhiteSpace($FilterText)){return @($script:AllOUs)}

    $needle=$FilterText.Trim()
    return @(
        $script:AllOUs|Where-Object{
            ([string]$_.Name).IndexOf($needle,[StringComparison]::OrdinalIgnoreCase)-ge 0 -or
            ([string]$_.DistinguishedName).IndexOf($needle,[StringComparison]::OrdinalIgnoreCase)-ge 0
        }
    )
}

function Refresh-OUCombo {
    param(
        [Parameter(Mandatory=$true)][Windows.Forms.ComboBox]$ComboBox,
        [AllowEmptyString()][string]$FilterText
    )

    $selectedDn=$null
    if($null-ne$ComboBox.SelectedItem){
        $selectedDn=[string]$ComboBox.SelectedItem.DistinguishedName
    }

    $filtered=@(Get-FilteredOUs -FilterText $FilterText)

    $ComboBox.BeginUpdate()
    try{
        $ComboBox.Items.Clear()
        foreach($ou in $filtered){[void]$ComboBox.Items.Add($ou)}

        $restored=$false
        if($selectedDn){
            for($i=0;$i-lt$ComboBox.Items.Count;$i++){
                if([string]$ComboBox.Items[$i].DistinguishedName-eq$selectedDn){
                    $ComboBox.SelectedIndex=$i
                    $restored=$true
                    break
                }
            }
        }

        if(-not$restored-and$ComboBox.Items.Count-gt 0){
            $ComboBox.SelectedIndex=0
        }
    }finally{
        $ComboBox.EndUpdate()
    }
}

# =====================================================================================
# Candidate inventory
# =====================================================================================
function ConvertTo-ComputerNameList {
    param([Parameter(Mandatory=$true)][string]$Path)

    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){
        throw "TXT file not found: $Path"
    }

    return @(
        Get-Content -LiteralPath $Path -ErrorAction Stop |
        ForEach-Object {$_.Trim()} |
        Where-Object {-not[string]::IsNullOrWhiteSpace($_)} |
        Sort-Object -Unique
    )
}

function Resolve-ComputersFromTXT {
    param(
        [Parameter(Mandatory=$true)][string]$Server,
        [Parameter(Mandatory=$true)][string]$Path
    )

    $names=@(ConvertTo-ComputerNameList -Path $Path)
    if($names.Count-eq 0){throw 'The TXT file contains no computer names.'}

    $results=New-Object Collections.ArrayList

    foreach($name in $names){
        try{
            $c=Get-ADComputer -Identity $name -Server $Server `
                -Properties DNSHostName,OperatingSystem,Enabled,Description,ObjectGUID `
                -ErrorAction Stop

            [void]$results.Add([pscustomobject]@{
                Name=[string]$c.Name
                DNSHostName=[string]$c.DNSHostName
                OperatingSystem=[string]$c.OperatingSystem
                Enabled=[bool]$c.Enabled
                Description=[string]$c.Description
                CurrentOU=(Get-ParentDN -DistinguishedName $c.DistinguishedName)
                DistinguishedName=[string]$c.DistinguishedName
                ObjectGUID=[Guid]$c.ObjectGUID
                ResolveStatus='RESOLVED'
                ResolveDetail=''
            })
        }catch{
            [void]$results.Add([pscustomobject]@{
                Name=[string]$name
                DNSHostName=''
                OperatingSystem=''
                Enabled=$false
                Description=''
                CurrentOU=''
                DistinguishedName=''
                ObjectGUID=[Guid]::Empty
                ResolveStatus='NOT FOUND'
                ResolveDetail=$_.Exception.Message
            })
            Write-AppLog "TXT computer '$name' could not be resolved: $($_.Exception.Message)" WARN
        }
    }

    return @($results)
}

function Get-ComputersFromSourceOU {
    param(
        [Parameter(Mandatory=$true)][string]$Server,
        [Parameter(Mandatory=$true)][string]$SourceOU
    )

    return @(
        Get-ADComputer -Server $Server -SearchBase $SourceOU -SearchScope OneLevel -Filter * `
            -Properties DNSHostName,OperatingSystem,Enabled,Description,ObjectGUID `
            -ErrorAction Stop |
        Sort-Object Name |
        ForEach-Object{
            [pscustomobject]@{
                Name=[string]$_.Name
                DNSHostName=[string]$_.DNSHostName
                OperatingSystem=[string]$_.OperatingSystem
                Enabled=[bool]$_.Enabled
                Description=[string]$_.Description
                CurrentOU=(Get-ParentDN -DistinguishedName $_.DistinguishedName)
                DistinguishedName=[string]$_.DistinguishedName
                ObjectGUID=[Guid]$_.ObjectGUID
                ResolveStatus='RESOLVED'
                ResolveDetail=''
            }
        }
    )
}

# =====================================================================================
# Searchable / sortable computer browser
# =====================================================================================
function Set-ComputerList {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [object[]]$Computers
    )

    $checked=@{}
    foreach($i in $script:listView.CheckedItems){
        if($i.Tag-and$i.Tag.ObjectGUID-ne[Guid]::Empty){
            $checked[[string]$i.Tag.ObjectGUID]=$true
        }
    }

    $script:listView.BeginUpdate()
    try{
        $script:listView.Items.Clear()

        foreach($c in $Computers){
            $item=New-Object Windows.Forms.ListViewItem([string]$c.Name)
            [void]$item.SubItems.Add([string]$c.DNSHostName)
            [void]$item.SubItems.Add([string]$c.OperatingSystem)
            [void]$item.SubItems.Add([string]$c.Enabled)
            [void]$item.SubItems.Add([string]$c.Description)
            [void]$item.SubItems.Add([string]$c.CurrentOU)
            [void]$item.SubItems.Add([string]$c.ResolveStatus)
            [void]$item.SubItems.Add([string]$c.ResolveDetail)
            $item.Tag=$c

            if($c.ObjectGUID-ne[Guid]::Empty-and$checked.ContainsKey([string]$c.ObjectGUID)){
                $item.Checked=$true
            }

            [void]$script:listView.Items.Add($item)
        }
    }finally{
        $script:listView.EndUpdate()
    }
}

function Test-ComputerMatchesFilter {
    param($Computer,[string]$Filter)

    if([string]::IsNullOrWhiteSpace($Filter)){return $true}
    $needle=$Filter.Trim()

    foreach($v in @(
        $Computer.Name,$Computer.DNSHostName,$Computer.OperatingSystem,
        [string]$Computer.Enabled,$Computer.Description,$Computer.CurrentOU,
        $Computer.ResolveStatus,$Computer.ResolveDetail
    )){
        if(([string]$v).IndexOf($needle,[StringComparison]::OrdinalIgnoreCase)-ge 0){
            return $true
        }
    }
    return $false
}

function Apply-ComputerFilter {
    param([string]$Filter)

    $script:DisplayedComputers=@(
        $script:ComputerCandidates|Where-Object{Test-ComputerMatchesFilter $_ $Filter}
    )
    Set-ComputerList -Computers $script:DisplayedComputers
    Set-AppStatus ("Displayed {0} of {1} candidate(s)."-f
        $script:DisplayedComputers.Count,$script:ComputerCandidates.Count)
}

function Sort-Computers {
    param([int]$Column,[bool]$Descending)

    switch($Column){
        0{$p='Name'}
        1{$p='DNSHostName'}
        2{$p='OperatingSystem'}
        3{$p='Enabled'}
        4{$p='Description'}
        5{$p='CurrentOU'}
        6{$p='ResolveStatus'}
        7{$p='ResolveDetail'}
        default{$p='Name'}
    }

    $script:ComputerCandidates=@(
        $script:ComputerCandidates|Sort-Object -Property $p -Descending:$Descending
    )
}

function Get-CheckedComputers {
    $a=New-Object Collections.ArrayList
    foreach($i in $script:listView.CheckedItems){
        if($i.Tag){[void]$a.Add($i.Tag)}
    }
    return @($a)
}

# =====================================================================================
# Preview / move / verification
# =====================================================================================
function New-MovePreview {
    param(
        [Parameter(Mandatory=$true)][object[]]$Computers,
        [Parameter(Mandatory=$true)]$TargetOU,
        [Parameter(Mandatory=$true)][string]$Server
    )

    $preview=foreach($record in $Computers){
        if($record.ResolveStatus-ne'RESOLVED'){
            [pscustomobject]@{
                Name=$record.Name;CurrentOU=$record.CurrentOU;TargetOU=$TargetOU.DistinguishedName
                Status='BLOCKED';Detail='Computer was not resolved in Active Directory.'
            }
            continue
        }

        try{
            $current=Get-ADComputer -Identity $record.DistinguishedName -Server $Server `
                -Properties ObjectGUID -ErrorAction Stop

            if([Guid]$current.ObjectGUID-ne[Guid]$record.ObjectGUID){
                throw 'ObjectGUID changed since discovery.'
            }

            $currentParent=Get-ParentDN -DistinguishedName $current.DistinguishedName

            if($currentParent-eq$TargetOU.DistinguishedName){
                [pscustomobject]@{
                    Name=$record.Name;CurrentOU=$currentParent;TargetOU=$TargetOU.DistinguishedName
                    Status='NO CHANGE';Detail='Computer is already in the target OU.'
                }
            }else{
                [pscustomobject]@{
                    Name=$record.Name;CurrentOU=$currentParent;TargetOU=$TargetOU.DistinguishedName
                    Status='READY';Detail='Ready to move.'
                }
            }
        }catch{
            [pscustomobject]@{
                Name=$record.Name;CurrentOU=$record.CurrentOU;TargetOU=$TargetOU.DistinguishedName
                Status='BLOCKED';Detail=$_.Exception.Message
            }
        }
    }

    return @($preview)
}

function Show-MovePreview {
    param([object[]]$Preview)

    $ready=@($Preview | Where-Object { $_.Status -eq 'READY' }).Count
    $same=@($Preview | Where-Object { $_.Status -eq 'NO CHANGE' }).Count
    $blocked=@($Preview | Where-Object { $_.Status -eq 'BLOCKED' }).Count

    $lines=New-Object Collections.Generic.List[string]
    $lines.Add("Mode      : $(Get-ExecutionModeLabel)")
    $lines.Add("Ready     : $ready")
    $lines.Add("No change : $same")
    $lines.Add("Blocked   : $blocked")
    $lines.Add('')
    foreach($p in $Preview){
        $lines.Add(("{0,-22} [{1}]"-f$p.Name,$p.Status))
        $lines.Add("  From: $($p.CurrentOU)")
        $lines.Add("  To  : $($p.TargetOU)")
        if($p.Detail){$lines.Add("  Note: $($p.Detail)")}
        $lines.Add('')
    }

    $dlg=New-Object Windows.Forms.Form
    $dlg.Text='AD Computer Move Preview'
    $dlg.Size=New-Object Drawing.Size(980,620)
    $dlg.StartPosition='CenterParent'

    $box=New-Object Windows.Forms.TextBox
    $box.Multiline=$true;$box.ReadOnly=$true;$box.ScrollBars='Both';$box.WordWrap=$false
    $box.Font=New-Object Drawing.Font('Consolas',9);$box.Dock='Fill'
    $box.Text=$lines-join[Environment]::NewLine
    $dlg.Controls.Add($box)

    [void]$dlg.ShowDialog()
}

function Move-ComputersControlled {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)][object[]]$Computers,
        [Parameter(Mandatory=$true)]$TargetOU,
        [Parameter(Mandatory=$true)][string]$Server
    )

    $results=New-Object Collections.ArrayList

    foreach($record in $Computers){
        try{
            if($record.ResolveStatus-ne'RESOLVED'){
                [void]$results.Add([pscustomobject]@{
                    Name=$record.Name;Result='SKIPPED';Detail='Computer was not resolved.'
                })
                continue
            }

            $current=Get-ADComputer -Identity $record.DistinguishedName -Server $Server `
                -Properties ObjectGUID -ErrorAction Stop

            if([Guid]$current.ObjectGUID-ne[Guid]$record.ObjectGUID){
                throw 'ObjectGUID changed since discovery.'
            }

            $currentParent=Get-ParentDN -DistinguishedName $current.DistinguishedName
            if($currentParent-eq$TargetOU.DistinguishedName){
                Write-AppLog "Skipped '$($record.Name)': already in target OU." INFO
                [void]$results.Add([pscustomobject]@{
                    Name=$record.Name;Result='SKIPPED';Detail='Already in target OU.'
                })
                continue
            }

            $target="$($record.Name) [$($current.DistinguishedName)]"
            $action="Move computer to '$($TargetOU.DistinguishedName)'"

            if($PSCmdlet.ShouldProcess($target,$action)){
                Move-ADObject -Identity $current.DistinguishedName `
                    -TargetPath $TargetOU.DistinguishedName `
                    -Server $Server -ErrorAction Stop

                $verified=Get-ADComputer -Identity $record.ObjectGUID -Server $Server `
                    -Properties ObjectGUID -ErrorAction Stop

                if([Guid]$verified.ObjectGUID-ne[Guid]$record.ObjectGUID){
                    throw 'Post-move ObjectGUID verification failed.'
                }

                $verifiedParent=Get-ParentDN -DistinguishedName $verified.DistinguishedName
                if($verifiedParent-ne$TargetOU.DistinguishedName){
                    throw "Post-move verification failed. Effective parent OU='$verifiedParent'."
                }

                Write-AppLog ("Moved and verified '{0}' from '{1}' to '{2}'."-f
                    $record.Name,$currentParent,$TargetOU.DistinguishedName) SUCCESS

                [void]$results.Add([pscustomobject]@{
                    Name=$record.Name;Result='SUCCESS';Detail='Moved and verified.'
                })
            }else{
                [void]$results.Add([pscustomobject]@{
                    Name=$record.Name;Result='SKIPPED';Detail='ShouldProcess declined.'
                })
            }
        }catch{
            Write-AppLog "Move failed for '$($record.Name)': $($_.Exception.Message)" ERROR
            [void]$results.Add([pscustomobject]@{
                Name=$record.Name;Result='FAILED';Detail=$_.Exception.Message
            })
        }
    }

    return @($results)
}

# =====================================================================================
# GUI
# =====================================================================================
$form=New-Object Windows.Forms.Form
$form.Text='AD Computer OU Move Manager - Enterprise Edition'
$form.Size=New-Object Drawing.Size(1380,870)
$form.MinimumSize=New-Object Drawing.Size(1120,760)
$form.StartPosition='CenterScreen'

$main=New-Object Windows.Forms.TableLayoutPanel
$main.Dock='Fill';$main.Padding=New-Object Windows.Forms.Padding(10)
$main.ColumnCount=1;$main.RowCount=8
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',60)))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',40)))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$form.Controls.Add($main)

# Domain + mode
$p1=New-Object Windows.Forms.FlowLayoutPanel;$p1.Dock='Fill';$p1.AutoSize=$true
$lDomain=New-Object Windows.Forms.Label;$lDomain.Text='Domain:';$lDomain.AutoSize=$true;$lDomain.Margin=New-Object Windows.Forms.Padding(3,7,3,3);$p1.Controls.Add($lDomain)
$cmbDomain=New-Object Windows.Forms.ComboBox;$cmbDomain.Width=320;$cmbDomain.DropDownStyle='DropDownList';$p1.Controls.Add($cmbDomain)

$lMode=New-Object Windows.Forms.Label;$lMode.Text='Source Mode:';$lMode.AutoSize=$true;$lMode.Margin=New-Object Windows.Forms.Padding(20,7,3,3);$p1.Controls.Add($lMode)
$cmbMode=New-Object Windows.Forms.ComboBox;$cmbMode.Width=180;$cmbMode.DropDownStyle='DropDownList'
[void]$cmbMode.Items.AddRange(@('Source OU','TXT File'))
$cmbMode.SelectedIndex=0
$p1.Controls.Add($cmbMode)

$chkDryRun=New-Object Windows.Forms.CheckBox;$chkDryRun.Text='Dry Run';$chkDryRun.Checked=$true;$chkDryRun.AutoSize=$true;$chkDryRun.Margin=New-Object Windows.Forms.Padding(20,6,3,3)
$script:chkDryRun=$chkDryRun;$p1.Controls.Add($chkDryRun)
$main.Controls.Add($p1,0,0)

# Source controls
$p2=New-Object Windows.Forms.FlowLayoutPanel;$p2.Dock='Fill';$p2.AutoSize=$true;$p2.WrapContents=$true

$lSrcSearch=New-Object Windows.Forms.Label;$lSrcSearch.Text='Source OU Search:';$lSrcSearch.AutoSize=$true;$lSrcSearch.Margin=New-Object Windows.Forms.Padding(3,7,3,3);$p2.Controls.Add($lSrcSearch)
$txtSourceSearch=New-Object Windows.Forms.TextBox;$txtSourceSearch.Width=280;$p2.Controls.Add($txtSourceSearch)
$cmbSourceOU=New-Object Windows.Forms.ComboBox;$cmbSourceOU.Width=600;$cmbSourceOU.DropDownStyle='DropDownList';$cmbSourceOU.DisplayMember='DistinguishedName';$p2.Controls.Add($cmbSourceOU)

$lTXT=New-Object Windows.Forms.Label;$lTXT.Text='TXT File:';$lTXT.AutoSize=$true;$lTXT.Margin=New-Object Windows.Forms.Padding(20,7,3,3);$p2.Controls.Add($lTXT)
$txtFile=New-Object Windows.Forms.TextBox;$txtFile.Width=420;$txtFile.Enabled=$false;$p2.Controls.Add($txtFile)
$btnBrowse=New-Object Windows.Forms.Button;$btnBrowse.Text='Browse';$btnBrowse.Width=85;$btnBrowse.Enabled=$false;$p2.Controls.Add($btnBrowse)

$btnLoad=New-Object Windows.Forms.Button;$btnLoad.Text='Load Candidates';$btnLoad.Width=120;$p2.Controls.Add($btnLoad)
$main.Controls.Add($p2,0,1)

# Target + result filter
$p3=New-Object Windows.Forms.FlowLayoutPanel;$p3.Dock='Fill';$p3.AutoSize=$true;$p3.WrapContents=$true
$lTargetSearch=New-Object Windows.Forms.Label;$lTargetSearch.Text='Target OU Search:';$lTargetSearch.AutoSize=$true;$lTargetSearch.Margin=New-Object Windows.Forms.Padding(3,7,3,3);$p3.Controls.Add($lTargetSearch)
$txtTargetSearch=New-Object Windows.Forms.TextBox;$txtTargetSearch.Width=280;$p3.Controls.Add($txtTargetSearch)
$cmbTargetOU=New-Object Windows.Forms.ComboBox;$cmbTargetOU.Width=600;$cmbTargetOU.DropDownStyle='DropDownList';$cmbTargetOU.DisplayMember='DistinguishedName';$p3.Controls.Add($cmbTargetOU)

$lFilter=New-Object Windows.Forms.Label;$lFilter.Text='Filter columns:';$lFilter.AutoSize=$true;$lFilter.Margin=New-Object Windows.Forms.Padding(20,7,3,3);$p3.Controls.Add($lFilter)
$txtFilter=New-Object Windows.Forms.TextBox;$txtFilter.Width=260;$p3.Controls.Add($txtFilter)
$btnClear=New-Object Windows.Forms.Button;$btnClear.Text='Clear Filter';$btnClear.Width=95;$p3.Controls.Add($btnClear)
$btnSelect=New-Object Windows.Forms.Button;$btnSelect.Text='Select All';$btnSelect.Width=90;$p3.Controls.Add($btnSelect)
$btnPreview=New-Object Windows.Forms.Button;$btnPreview.Text='Preview';$btnPreview.Width=90;$p3.Controls.Add($btnPreview)
$btnMove=New-Object Windows.Forms.Button;$btnMove.Text='Move Selected';$btnMove.Width=110;$p3.Controls.Add($btnMove)
$main.Controls.Add($p3,0,2)

$listView=New-Object Windows.Forms.ListView
$listView.Dock='Fill';$listView.View='Details';$listView.CheckBoxes=$true
$listView.FullRowSelect=$true;$listView.GridLines=$true;$listView.HideSelection=$false
[void]$listView.Columns.Add('Name',135)
[void]$listView.Columns.Add('DNSHostName',190)
[void]$listView.Columns.Add('Operating System',190)
[void]$listView.Columns.Add('Enabled',70)
[void]$listView.Columns.Add('Description',190)
[void]$listView.Columns.Add('Current OU',360)
[void]$listView.Columns.Add('Resolve',90)
[void]$listView.Columns.Add('Detail',300)
$script:listView=$listView
$main.Controls.Add($listView,0,3)

$summary=New-Object Windows.Forms.Label;$summary.AutoSize=$true;$summary.Text='No candidates loaded.';$main.Controls.Add($summary,0,4)
$note=New-Object Windows.Forms.Label;$note.AutoSize=$true;$note.MaximumSize=New-Object Drawing.Size(1300,0)
$note.Text='Safety defaults: Dry Run enabled; exact checked-object selection required; source and target OUs cannot be the same; each computer is revalidated and post-move verified.'
$main.Controls.Add($note,0,5)

$txtRuntimeLog=New-Object Windows.Forms.TextBox
$txtRuntimeLog.Dock='Fill';$txtRuntimeLog.Multiline=$true;$txtRuntimeLog.ReadOnly=$true;$txtRuntimeLog.ScrollBars='Vertical';$txtRuntimeLog.Font=New-Object Drawing.Font('Consolas',8.5)
$script:txtRuntimeLog=$txtRuntimeLog
$main.Controls.Add($txtRuntimeLog,0,6)

$statusStrip=New-Object Windows.Forms.StatusStrip
$statusMain=New-Object Windows.Forms.ToolStripStatusLabel;$statusMain.Spring=$true;$statusMain.Text='Ready';$script:statusMain=$statusMain;[void]$statusStrip.Items.Add($statusMain)
$statusMode=New-Object Windows.Forms.ToolStripStatusLabel;$statusMode.Text='Mode: DRY RUN';$script:statusMode=$statusMode;[void]$statusStrip.Items.Add($statusMode)
$main.Controls.Add($statusStrip,0,7)

# =====================================================================================
# GUI event handlers
# =====================================================================================
function Load-DomainOUs {
    try{
        $d=[string]$cmbDomain.SelectedItem
        if([string]::IsNullOrWhiteSpace($d)){return}
        $script:CurrentDomain=$d
        Set-AppStatus "Loading OUs from $d..."
        $script:AllOUs=@(Get-DomainOUs -Server $d)
        $txtSourceSearch.Clear();$txtTargetSearch.Clear()
        Refresh-OUCombo -ComboBox $cmbSourceOU -FilterText ''
        Refresh-OUCombo -ComboBox $cmbTargetOU -FilterText ''
        Write-AppLog "Loaded $($script:AllOUs.Count) OUs from '$d'." SUCCESS
    }catch{Show-AppMessage "OU discovery failed: $($_.Exception.Message)" Error}
}

$cmbDomain.Add_SelectedIndexChanged({Load-DomainOUs})

$cmbMode.Add_SelectedIndexChanged({
    $isOU=($cmbMode.SelectedItem-eq'Source OU')
    $txtSourceSearch.Enabled=$isOU
    $cmbSourceOU.Enabled=$isOU
    $txtFile.Enabled=-not$isOU
    $btnBrowse.Enabled=-not$isOU
})

$txtSourceSearch.Add_TextChanged({
    Refresh-OUCombo -ComboBox $cmbSourceOU -FilterText $txtSourceSearch.Text.Trim()
})

$txtTargetSearch.Add_TextChanged({
    Refresh-OUCombo -ComboBox $cmbTargetOU -FilterText $txtTargetSearch.Text.Trim()
})

$btnBrowse.Add_Click({
    $ofd=New-Object Windows.Forms.OpenFileDialog
    $ofd.Filter='Text Files (*.txt)|*.txt|All Files (*.*)|*.*'
    if($ofd.ShowDialog()-eq[Windows.Forms.DialogResult]::OK){$txtFile.Text=$ofd.FileName}
})

$chkDryRun.Add_CheckedChanged({
    $statusMode.Text=if($chkDryRun.Checked){'Mode: DRY RUN'}else{'Mode: COMMIT'}
})

$txtFilter.Add_TextChanged({
    Apply-ComputerFilter -Filter $txtFilter.Text
    $summary.Text="Displayed: $($script:DisplayedComputers.Count) | Total: $($script:ComputerCandidates.Count)"
})

$btnClear.Add_Click({$txtFilter.Clear()})
$btnSelect.Add_Click({
    foreach($i in $script:listView.Items){
        if($i.Tag-and$i.Tag.ResolveStatus-eq'RESOLVED'){$i.Checked=$true}
    }
})

$listView.Add_ColumnClick({
    param($sender,$e)
    if($script:SortColumn-eq$e.Column){
        $script:SortDescending=-not$script:SortDescending
    }else{
        $script:SortColumn=$e.Column
        $script:SortDescending=$false
    }
    Sort-Computers -Column $script:SortColumn -Descending $script:SortDescending
    Apply-ComputerFilter -Filter $txtFilter.Text
})

$btnLoad.Add_Click({
    try{
        if([string]::IsNullOrWhiteSpace([string]$script:CurrentDomain)){throw 'Select a domain.'}

        Set-AppStatus 'Loading computer candidates...'

        if($cmbMode.SelectedItem-eq'Source OU'){
            if($null-eq$cmbSourceOU.SelectedItem){throw 'Select a source OU.'}
            $source=[string]$cmbSourceOU.SelectedItem.DistinguishedName
            $script:ComputerCandidates=@(
                Get-ComputersFromSourceOU -Server $script:CurrentDomain -SourceOU $source
            )
            Write-AppLog "Loaded $($script:ComputerCandidates.Count) computer(s) from source OU '$source'." SUCCESS
        }else{
            if([string]::IsNullOrWhiteSpace($txtFile.Text)){throw 'Select a TXT file.'}
            $script:ComputerCandidates=@(
                Resolve-ComputersFromTXT -Server $script:CurrentDomain -Path $txtFile.Text
            )
            Write-AppLog "Resolved $($script:ComputerCandidates.Count) TXT candidate row(s)." SUCCESS
        }

        $script:DisplayedComputers=@($script:ComputerCandidates)
        $txtFilter.Clear()
        Set-ComputerList -Computers $script:DisplayedComputers

        $resolved=@($script:ComputerCandidates | Where-Object { $_.ResolveStatus -eq 'RESOLVED' }).Count
        $unresolved=$script:ComputerCandidates.Count-$resolved
        $summary.Text="Candidates: $($script:ComputerCandidates.Count) | Resolved: $resolved | Unresolved: $unresolved"
        Set-AppStatus 'Candidate load completed.'
    }catch{
        Show-AppMessage "Candidate load failed: $($_.Exception.Message)" Error
    }
})

$btnPreview.Add_Click({
    try{
        $selected=@(Get-CheckedComputers)
        if($selected.Count-eq 0){throw 'Select at least one computer.'}
        if($null-eq$cmbTargetOU.SelectedItem){throw 'Select a target OU.'}

        $target=$cmbTargetOU.SelectedItem
        if(-not(Test-OUStillExists -OU $target -Server $script:CurrentDomain)){
            throw 'Target OU no longer matches the discovered object. Reload the domain OUs.'
        }

        if($cmbMode.SelectedItem-eq'Source OU'-and$null-ne$cmbSourceOU.SelectedItem){
            if([string]$cmbSourceOU.SelectedItem.DistinguishedName-eq[string]$target.DistinguishedName){
                throw 'Source and target OUs cannot be the same.'
            }
        }

        $preview=@(New-MovePreview -Computers $selected -TargetOU $target -Server $script:CurrentDomain)
        Show-MovePreview -Preview $preview
    }catch{Show-AppMessage $_.Exception.Message Warning}
})

$btnMove.Add_Click({
    try{
        $selected=@(Get-CheckedComputers)
        if($selected.Count-eq 0){throw 'Select at least one computer.'}
        if($null-eq$cmbTargetOU.SelectedItem){throw 'Select a target OU.'}

        $target=$cmbTargetOU.SelectedItem
        if(-not(Test-OUStillExists -OU $target -Server $script:CurrentDomain)){
            throw 'Target OU changed or no longer exists. Reload the domain.'
        }

        if($cmbMode.SelectedItem-eq'Source OU'-and$null-ne$cmbSourceOU.SelectedItem){
            if([string]$cmbSourceOU.SelectedItem.DistinguishedName-eq[string]$target.DistinguishedName){
                throw 'Source and target OUs cannot be the same.'
            }
        }

        $preview=@(New-MovePreview -Computers $selected -TargetOU $target -Server $script:CurrentDomain)
        $ready=@($preview | Where-Object { $_.Status -eq 'READY' }).Count
        $blocked=@($preview | Where-Object { $_.Status -eq 'BLOCKED' }).Count

        if($blocked-gt 0){
            Show-MovePreview -Preview $preview
            Show-AppMessage "$blocked selected computer(s) failed pre-commit validation." Error
            return
        }

        if($chkDryRun.Checked){
            Show-MovePreview -Preview $preview
            Write-AppLog "DRY RUN: Selected=$($selected.Count); Ready=$ready; TargetOU='$($target.DistinguishedName)'."
            Show-AppMessage "Dry Run completed. $ready computer(s) would be moved; Active Directory was not modified." Information
            return
        }

        if($ready-eq 0){
            Show-AppMessage 'No selected computers require a move.' Information
            return
        }

        $confirm=@"
COMMIT Active Directory computer moves?

Domain: $($script:CurrentDomain)
Target OU: $($target.DistinguishedName)
Selected: $($selected.Count)
Moves required: $ready
"@
        $answer=[Windows.Forms.MessageBox]::Show(
            $confirm,'Confirm Computer OU Move',
            [Windows.Forms.MessageBoxButtons]::YesNo,
            [Windows.Forms.MessageBoxIcon]::Warning,
            [Windows.Forms.MessageBoxDefaultButton]::Button2
        )

        if($answer-ne[Windows.Forms.DialogResult]::Yes){
            Write-AppLog 'Commit cancelled by operator.' WARN
            return
        }

        Set-AppStatus 'Moving and verifying selected computer accounts...'
        $results=@(
            Move-ComputersControlled -Computers $selected -TargetOU $target `
                -Server $script:CurrentDomain -Confirm:$false
        )

        $success=@($results | Where-Object { $_.Result -eq 'SUCCESS' }).Count
        $failed=@($results | Where-Object { $_.Result -eq 'FAILED' }).Count
        $skipped=@($results | Where-Object { $_.Result -eq 'SKIPPED' }).Count

        $msg="Execution completed.`r`n`r`nSuccess: $success`r`nFailed: $failed`r`nSkipped: $skipped`r`n`r`nLog: $($script:LogFile)"

        if($failed-gt 0){
            Show-AppMessage $msg Warning
        }else{
            Write-AppLog ("Move summary: Success={0}; Failed={1}; Skipped={2}"-f$success,$failed,$skipped) SUCCESS
            [void][Windows.Forms.MessageBox]::Show(
                $msg,'Execution Summary',
                [Windows.Forms.MessageBoxButtons]::OK,
                [Windows.Forms.MessageBoxIcon]::Information
            )
        }

        Set-AppStatus ("Completed: Success={0}, Failed={1}, Skipped={2}"-f$success,$failed,$skipped)
    }catch{
        Show-AppMessage "Execution failed: $($_.Exception.Message)" Error
    }
})

# =====================================================================================
# Main
# =====================================================================================
try{
    Write-AppLog "Starting $($script:ScriptName)."
    Write-AppLog ("Host PowerShell: {0}; OS: {1}"-f
        $PSVersionTable.PSVersion,[Environment]::OSVersion.VersionString)

    $domains=@(Get-ForestDomains)
    foreach($d in $domains){[void]$cmbDomain.Items.Add($d)}
    if($cmbDomain.Items.Count-eq 0){throw 'No Active Directory domains discovered.'}
    $cmbDomain.SelectedIndex=0
    Write-AppLog ("Discovered forest domains: {0}"-f($domains-join', ')) SUCCESS

    [void]$form.ShowDialog()
}catch{
    Write-AppLog "Fatal startup error: $($_.Exception.Message)" ERROR
    [void][Windows.Forms.MessageBox]::Show(
        "Fatal startup error:`r`n$($_.Exception.Message)",
        'AD Computer OU Move Manager',
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Error
    )
}finally{
    Write-AppLog "Closing $($script:ScriptName)."
}

# End of script
