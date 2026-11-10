#requires -Version 5.1
<#
.SYNOPSIS
    Unified AD Computer Discovery & Inventory Tool v1.2.1 (READ-ONLY).

.DESCRIPTION
    GUI and CLI tool for forest-wide Active Directory computer discovery,
    workstation/server inventory, OU identification, DNS resolution, and
    optional ICMP connectivity testing.

    Features sortable GUI columns, search filters, hidden PowerShell
    console, execution statistics, and automated CSV/TXT reporting.

.PARAMETER NoGui
    Runs inventory without the graphical interface.

.EXAMPLE
    .\Unified-ADComputer-Discovery-Inventory-v1.2.1.ps1

.EXAMPLE
    .\Unified-ADComputer-Discovery-Inventory-v1.2.1.ps1 `
        -NoGui -Scope Forest -ComputerType Workstations `
        -AccountState All -ResolveDNS

.OUTPUTS
    Consolidated and per-domain CSV/TXT inventory reports.
    Domain-specific FQDN workstation lists and execution logs.

.NOTES
    Version      : 1.2.1
    Requirements : Windows PowerShell 5.1, RSAT ActiveDirectory
    Interface    : Windows Forms GUI / CLI
    Operation    : READ-ONLY; no Active Directory modifications.
    Reports      : C:\Scripts-LOGS\Unified-ADComputer-Inventory

    OS classification relies on AD attributes. DNS/ICMP results
    do not conclusively establish endpoint availability.
#>

[CmdletBinding()]
param(
 [ValidateSet('Forest','Current','Specific')][string]$Scope='Forest',
 [string]$Domain='',
 [string]$SearchBase='',
 [ValidateSet('All','Workstations','Servers','Unknown')][string]$ComputerType='Workstations',
 [ValidateSet('All','Enabled','Disabled')][string]$AccountState='All',
 [switch]$ResolveDNS,
 [switch]$TestPing,
 [ValidateRange(100,10000)][int]$PingTimeoutMs=1200,
 [string]$OutputDirectory='C:\Scripts-LOGS\Unified-ADComputer-Inventory',
 [switch]$NoGui,
 [switch]$HiddenChild
)
# GUI bootstrap: launch hidden child without hiding the calling console.
if (-not $NoGui -and -not $HiddenChild -and -not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
 try {
  $exe=Join-Path $PSHOME 'powershell.exe'
  $quoted='"' + ($PSCommandPath -replace '"','\"') + '"'
  $outQuoted='"' + ($OutputDirectory -replace '"','\"') + '"'
  $argsLine='-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -File {0} -OutputDirectory {1} -HiddenChild' -f $quoted,$outQuoted
  Start-Process -FilePath $exe -ArgumentList $argsLine -WindowStyle Hidden -ErrorAction Stop | Out-Null
  return
 } catch { Write-Warning ("Hidden GUI launch failed: {0}" -f $_.Exception.Message) }
}
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module ActiveDirectory -ErrorAction Stop
$script:RunPath=Join-Path $OutputDirectory (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
New-Item -ItemType Directory -Path $script:RunPath -Force | Out-Null
$script:LogFile=Join-Path $script:RunPath 'Execution.log'
function Write-AuditLog { param([string]$Message,[string]$Level='INFO')
 $line='{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message
 Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
 if($NoGui){Write-Host $line}
}
function Get-Domains { param([string]$RequestedScope,[string]$RequestedDomain)
 switch($RequestedScope){
  'Forest' { @( (Get-ADForest -ErrorAction Stop).Domains | Sort-Object ) }
  'Current' { @((Get-ADDomain -ErrorAction Stop).DNSRoot) }
  'Specific' { if([string]::IsNullOrWhiteSpace($RequestedDomain)){throw 'Specific scope requires -Domain.'}; @((Get-ADDomain -Identity $RequestedDomain -ErrorAction Stop).DNSRoot) }
 }
}
function Get-ComputerClass { param([string]$OS)
 if([string]::IsNullOrWhiteSpace($OS)){return 'Unknown'}
 if($OS -match '(?i)windows\s+server|server\s+20\d\d|server\s+202\d'){return 'Servers'}
 if($OS -match '(?i)windows' -and $OS -notmatch '(?i)server'){return 'Workstations'}
 return 'Unknown'
}
function Get-ParentPath {param([string]$DN)
 # Remove the leading RDN while preserving escaped commas.
 if([string]::IsNullOrWhiteSpace($DN)){return ''}
 $escaped=$false
 for($i=0;$i -lt $DN.Length;$i++){
  if($escaped){$escaped=$false;continue}
  if($DN[$i] -eq '\'){$escaped=$true;continue}
  if($DN[$i] -eq ','){return $DN.Substring($i+1)}
 }
 return ''
}
function Resolve-ComputerIPv4 {param([string]$FQDN,[string]$ADIPv4,[bool]$DoResolve)
 $ip='';$source='NotResolved'
 if($ADIPv4 -and $ADIPv4 -as [ipaddress]){
  $parsed=[ipaddress]$ADIPv4
  if($parsed.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork){$ip=$ADIPv4;$source='AD'}
 }
 if($DoResolve -and $FQDN){
  try {
   $addresses=@(Resolve-DnsName -Name $FQDN -Type A -QuickTimeout -ErrorAction Stop | Where-Object {$_.Type -eq 'A' -and $_.IPAddress} | Select-Object -ExpandProperty IPAddress -Unique)
   if($addresses.Count -gt 0){$ip=($addresses -join ';');$source='DNS'}
  }catch{if(-not $ip){$source='DNSFailed'}}
 }
 [pscustomobject]@{IPv4=$ip;Source=$source}
}
function Test-ComputerICMP {param([string]$Target,[int]$Timeout)
 if(-not $Target){return 'NotTested-NoName'}
 $p=$null
 try{
  $p=New-Object System.Net.NetworkInformation.Ping
  $reply=$p.Send($Target,$Timeout)
  if($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success){return 'Reachable'}
  return [string]$reply.Status
 }catch{return 'Error'}finally{if($p){$p.Dispose()}}
}
function Invoke-Inventory {param([string]$SelectedScope,[string]$SelectedDomain,[string]$Base,[string]$Type,[string]$State,[bool]$DNS,[bool]$Ping,[int]$Timeout,[scriptblock]$ProgressCallback)
 $domains=@(Get-Domains -RequestedScope $SelectedScope -RequestedDomain $SelectedDomain)
 $results=New-Object 'System.Collections.Generic.List[object]'
 $errors=New-Object 'System.Collections.Generic.List[object]'
 $index=0
 foreach($d in $domains){
  $index++
  if($ProgressCallback){& $ProgressCallback $index $domains.Count $d}
  Write-AuditLog "Query domain $d"
  try{
   $query=@{Server=$d;Filter='*';Properties=@('DNSHostName','IPv4Address','Enabled','OperatingSystem','OperatingSystemVersion','LastLogonDate','PasswordLastSet','whenCreated','whenChanged','DistinguishedName');ErrorAction='Stop'}
   if($Base){
    $dn=(Get-ADDomain -Server $d -ErrorAction Stop).DistinguishedName
    if(-not ($Base -eq $dn -or $Base.EndsWith(','+$dn,[StringComparison]::OrdinalIgnoreCase))){throw "SearchBase is outside domain ${d}: $Base"}
    $query.SearchBase=$Base
   }
   $computers=@(Get-ADComputer @query)
   foreach($c in $computers){
    $class=Get-ComputerClass ([string]$c.OperatingSystem)
    if($Type -ne 'All' -and $Type -ne $class){continue}
    if($State -eq 'Enabled' -and -not $c.Enabled){continue}
    if($State -eq 'Disabled' -and $c.Enabled){continue}
    $fqdn=[string]$c.DNSHostName
    if(-not $fqdn){$fqdn='{0}.{1}' -f $c.Name,$d;$fqdnSource='Constructed'}else{$fqdnSource='AD'}
    $network=Resolve-ComputerIPv4 -FQDN $fqdn -ADIPv4 ([string]$c.IPv4Address) -DoResolve $DNS
    $icmp=if($Ping){Test-ComputerICMP -Target $fqdn -Timeout $Timeout}else{'NotTested'}
    $results.Add([pscustomobject]@{
     Domain=$d;ComputerName=[string]$c.Name;FQDN=$fqdn;FQDNSource=$fqdnSource
     ComputerType=$class;Enabled=[bool]$c.Enabled;OperatingSystem=[string]$c.OperatingSystem
     OperatingSystemVersion=[string]$c.OperatingSystemVersion;IPv4Address=$network.IPv4;IPSource=$network.Source
     ICMPStatus=$icmp;LastLogonDate=$c.LastLogonDate;PasswordLastSet=$c.PasswordLastSet
     WhenCreated=$c.whenCreated;WhenChanged=$c.whenChanged;OUPath=(Get-ParentPath ([string]$c.DistinguishedName))
     DistinguishedName=[string]$c.DistinguishedName
    })
   }
   Write-AuditLog "Domain ${d}: queried=$($computers.Count) selected=$(@($results | Where-Object Domain -eq $d).Count)"
  }catch{
   $msg=$_.Exception.Message
   Write-AuditLog "Domain $d failed: $msg" 'ERROR'
   $errors.Add([pscustomobject]@{Domain=$d;Error=$msg})
  }
 }
 [pscustomobject]@{Domains=$domains;Rows=@($results.ToArray());Errors=@($errors.ToArray())}
}
function Write-TextFile {param([string]$Path,[object[]]$Values)
 $lines=@($Values | Where-Object {-not [string]::IsNullOrWhiteSpace([string]$_)} | ForEach-Object {[string]$_} | Sort-Object -Unique)
 [System.IO.File]::WriteAllLines($Path,[string[]]$lines,(New-Object System.Text.UTF8Encoding($false)))
}
function Export-Inventory {param($Inventory,[string]$TargetDirectory)
 New-Item -ItemType Directory -Path $TargetDirectory -Force | Out-Null
 $rows=@($Inventory.Rows)
 $columns=@('Domain','ComputerName','FQDN','FQDNSource','ComputerType','Enabled','OperatingSystem','OperatingSystemVersion','IPv4Address','IPSource','ICMPStatus','LastLogonDate','PasswordLastSet','WhenCreated','WhenChanged','OUPath','DistinguishedName')
 $csv=Join-Path $TargetDirectory 'Forest-Computers-Detailed.csv'
 if($rows.Count){$rows | Select-Object $columns | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8}
 else{('"'+($columns -join '","')+'"') | Set-Content -LiteralPath $csv -Encoding UTF8}
 if(@($Inventory.Errors).Count){$Inventory.Errors | Export-Csv -LiteralPath (Join-Path $TargetDirectory 'Domain-Errors.csv') -NoTypeInformation -Encoding UTF8}else{'"Domain","Error"' | Set-Content -LiteralPath (Join-Path $TargetDirectory 'Domain-Errors.csv') -Encoding UTF8}
 Write-TextFile (Join-Path $TargetDirectory 'Forest-Hostnames.txt') @($rows | ForEach-Object {$_.ComputerName})
 Write-TextFile (Join-Path $TargetDirectory 'Forest-FQDNs.txt') @($rows | ForEach-Object {$_.FQDN})
 Write-TextFile (Join-Path $TargetDirectory 'FQDN-forest-workstations_list.txt') @($rows | Where-Object { $_.ComputerType -eq 'Workstations' } | ForEach-Object FQDN)
 Write-TextFile (Join-Path $TargetDirectory 'Forest-IPv4.txt') @($rows | ForEach-Object {$_.IPv4Address -split ';'})
 foreach($d in $Inventory.Domains){
  $safe=$d -replace '[^a-zA-Z0-9._-]','_'
  $subset=@($rows | Where-Object {$_.Domain -eq $d})
  if($subset.Count){$subset | Select-Object $columns | Export-Csv -LiteralPath (Join-Path $TargetDirectory "$safe-Computers.csv") -NoTypeInformation -Encoding UTF8}
  Write-TextFile (Join-Path $TargetDirectory "$safe-Enabled-Hostnames.txt") @($subset | Where-Object Enabled | ForEach-Object ComputerName)
  Write-TextFile (Join-Path $TargetDirectory "$safe-Disabled-Hostnames.txt") @($subset | Where-Object {-not $_.Enabled} | ForEach-Object ComputerName)
  Write-TextFile (Join-Path $TargetDirectory "$safe-Enabled-FQDNs.txt") @($subset | Where-Object Enabled | ForEach-Object FQDN)
  # Requested machine-readable FQDN list; one record per line, no header.
  Write-TextFile (Join-Path $TargetDirectory ("FQDN-{0}-workstations_list.txt" -f $safe.ToLowerInvariant())) @($subset | Where-Object { $_.ComputerType -eq 'Workstations' } | ForEach-Object FQDN)
 }
 $summary=@($rows | Group-Object Domain,ComputerType,Enabled | ForEach-Object {[pscustomobject]@{Group=$_.Name;Count=$_.Count}})
 if($summary.Count){$summary | Export-Csv -LiteralPath (Join-Path $TargetDirectory 'Summary.csv') -NoTypeInformation -Encoding UTF8}
 Write-AuditLog "Export completed: $TargetDirectory; records=$($rows.Count); domainErrors=$(@($Inventory.Errors).Count)"
}
if($NoGui){
 $data=Invoke-Inventory -SelectedScope $Scope -SelectedDomain $Domain -Base $SearchBase -Type $ComputerType -State $AccountState -DNS ([bool]$ResolveDNS) -Ping ([bool]$TestPing) -Timeout $PingTimeoutMs
 Export-Inventory -Inventory $data -TargetDirectory $script:RunPath
 Write-Host "Records: $(@($data.Rows).Count) | Domain errors: $(@($data.Errors).Count) | Output: $script:RunPath"
 if(@($data.Errors).Count){exit 2};exit 0
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:LastData=$null
$script:LastReportPath=$script:RunPath
$script:AllRows=@()
$script:Busy=$false
$form=New-Object System.Windows.Forms.Form
$form.Text='AD Computer Discovery & Inventory  |  v1.2.1  |  READ-ONLY'
$form.Size=New-Object System.Drawing.Size(1390,870)
$form.MinimumSize=New-Object System.Drawing.Size(1080,720)
$form.StartPosition='CenterScreen'
$form.BackColor=[System.Drawing.Color]::FromArgb(241,245,249)
$form.Font=New-Object System.Drawing.Font('Segoe UI',9)
$form.AutoScaleMode='Font'
$navy=[System.Drawing.Color]::FromArgb(20,38,65)
$blue=[System.Drawing.Color]::FromArgb(27,99,191)
$muted=[System.Drawing.Color]::FromArgb(87,103,122)
$white=[System.Drawing.Color]::White
function UiLabel {param($Parent,[string]$Text,[int]$X,[int]$Y,[int]$W=170,[int]$H=22,[bool]$Bold=$false)
 $c=New-Object System.Windows.Forms.Label;$c.Text=$Text;$c.SetBounds($X,$Y,$W,$H)
 if($Bold){$c.Font=New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)}
 $Parent.Controls.Add($c);return $c
}
function UiCombo {param($Parent,[object[]]$Items,[int]$X,[int]$Y,[int]$W,[int]$Index=0)
 $c=New-Object System.Windows.Forms.ComboBox;$c.DropDownStyle='DropDownList';$c.SetBounds($X,$Y,$W,28)
 [void]$c.Items.AddRange($Items);if($c.Items.Count -gt $Index){$c.SelectedIndex=$Index};$Parent.Controls.Add($c);return $c
}
function UiButton {param($Parent,[string]$Text,[int]$X,[int]$Y,[int]$W,[bool]$Primary=$false)
 $c=New-Object System.Windows.Forms.Button;$c.Text=$Text;$c.SetBounds($X,$Y,$W,36);$c.FlatStyle='Flat'
 if($Primary){$c.BackColor=$blue;$c.ForeColor=$white;$c.FlatAppearance.BorderSize=0}
 else{$c.BackColor=$white;$c.ForeColor=$navy;$c.FlatAppearance.BorderColor=[System.Drawing.Color]::FromArgb(194,207,223)}
 $Parent.Controls.Add($c);return $c
}
$top=New-Object System.Windows.Forms.Panel;$top.Dock='Top';$top.Height=64;$top.BackColor=$navy;$form.Controls.Add($top)
$brand=UiLabel $top 'ACTIVE DIRECTORY  /  COMPUTER DISCOVERY & INVENTORY' 20 13 900 25 $true
$brand.ForeColor=$white;$brand.Font=New-Object System.Drawing.Font('Segoe UI',13,[System.Drawing.FontStyle]::Bold)
$sub=UiLabel $top 'Forest-aware inventory  |  DNS / ICMP discovery  |  No directory modifications' 22 40 850 18
$sub.ForeColor=[System.Drawing.Color]::FromArgb(190,209,230)
$bottom=New-Object System.Windows.Forms.Panel;$bottom.Dock='Bottom';$bottom.Height=64;$bottom.BackColor=$white;$form.Controls.Add($bottom)
$filters=New-Object System.Windows.Forms.Panel;$filters.Dock='Top';$filters.Height=210;$filters.BackColor=$white;$form.Controls.Add($filters)
$summary=New-Object System.Windows.Forms.Panel;$summary.Dock='Top';$summary.Height=93;$summary.BackColor=[System.Drawing.Color]::FromArgb(241,245,249);$form.Controls.Add($summary)
$content=New-Object System.Windows.Forms.Panel;$content.Dock='Fill';$content.Padding=New-Object System.Windows.Forms.Padding(12,0,12,8);$form.Controls.Add($content)
$content.BringToFront()
[void](UiLabel $filters 'INVENTORY CONFIGURATION' 18 10 400 23 $true)
[void](UiLabel $filters 'Scope' 18 40 120)
$scopeBox=UiCombo $filters @('Forest','Current','Specific') 18 64 170 0
[void](UiLabel $filters 'Domain (Specific)' 205 40 180)
$domainBox=UiCombo $filters @('') 205 64 350 0
try{foreach($d in @(Get-Domains Forest '')){[void]$domainBox.Items.Add($d)}}catch{Write-AuditLog $_.Exception.Message 'WARN'}
[void](UiLabel $filters 'Computer type' 574 40 180)
$typeBox=UiCombo $filters @('Workstations','Servers','All','Unknown') 574 64 165 0
[void](UiLabel $filters 'Account state' 757 40 160)
$stateBox=UiCombo $filters @('All','Enabled','Disabled') 757 64 140 0
[void](UiLabel $filters 'Ping timeout (ms)' 915 40 160)
$timeoutBox=New-Object System.Windows.Forms.NumericUpDown;$timeoutBox.Minimum=100;$timeoutBox.Maximum=10000;$timeoutBox.Value=$PingTimeoutMs;$timeoutBox.SetBounds(915,64,125,28);$filters.Controls.Add($timeoutBox)
[void](UiLabel $filters 'Search base DN (optional; Current/Specific scope)' 18 106 470)
$baseBox=New-Object System.Windows.Forms.TextBox;$baseBox.SetBounds(18,130,720,28);$baseBox.Anchor='Top,Left,Right';$filters.Controls.Add($baseBox)
$dnsBox=New-Object System.Windows.Forms.CheckBox;$dnsBox.Text='Resolve DNS (A records)';$dnsBox.SetBounds(18,174,220,25);$dnsBox.Checked=[bool]$ResolveDNS;$filters.Controls.Add($dnsBox)
$pingBox=New-Object System.Windows.Forms.CheckBox;$pingBox.Text='Test ICMP (slower)';$pingBox.SetBounds(250,174,205,25);$pingBox.Checked=[bool]$TestPing;$filters.Controls.Add($pingBox)
$readOnly=UiLabel $filters 'READ-ONLY  -  No AD changes' 800 177 350 22 $true;$readOnly.ForeColor=[System.Drawing.Color]::FromArgb(26,128,77)
$domainBox.Enabled=$false
$scopeBox.Add_SelectedIndexChanged({$domainBox.Enabled=([string]$scopeBox.SelectedItem -eq 'Specific');$baseBox.Enabled=([string]$scopeBox.SelectedItem -ne 'Forest')})
$baseBox.Enabled=$false
$stats=@()
foreach($spec in @(@('Records','0'),@('Enabled','0'),@('Disabled','0'),@('Domains / Errors','0 / 0'))){
 $p=New-Object System.Windows.Forms.Panel;$p.BackColor=$white;$p.BorderStyle='FixedSingle';$summary.Controls.Add($p)
 $l=UiLabel $p $spec[0] 13 8 230 20;$l.ForeColor=$muted
 $v=UiLabel $p $spec[1] 13 29 240 38 $true;$v.Font=New-Object System.Drawing.Font('Segoe UI',17,[System.Drawing.FontStyle]::Bold);$v.ForeColor=$navy
 $stats+=@([pscustomobject]@{Panel=$p;Value=$v})
}
function Resize-Stats {
 $width=[math]::Max(160,[int](($summary.ClientSize.Width-60)/4))
 for($i=0;$i -lt 4;$i++){$stats[$i].Panel.SetBounds((12+$i*($width+12)),8,$width,76)}
}
$summary.Add_Resize({Resize-Stats});Resize-Stats
$toolbar=New-Object System.Windows.Forms.Panel;$toolbar.Dock='Top';$toolbar.Height=54;$toolbar.BackColor=$white;$content.Controls.Add($toolbar)
[void](UiLabel $toolbar 'INVENTORY RESULTS' 12 14 180 25 $true)
$searchBox=New-Object System.Windows.Forms.TextBox;$searchBox.SetBounds(200,12,350,27);$searchBox.Anchor='Top,Left';$toolbar.Controls.Add($searchBox)
$hint=UiLabel $toolbar 'Filter by name, domain, FQDN, IP or OS' 565 15 360 22;$hint.ForeColor=$muted
$grid=New-Object System.Windows.Forms.DataGridView;$grid.Dock='Fill';$grid.BackgroundColor=$white;$grid.BorderStyle='None'
$grid.RowHeadersVisible=$false;$grid.ReadOnly=$true;$grid.AllowUserToAddRows=$false;$grid.AllowUserToDeleteRows=$false
$grid.SelectionMode='FullRowSelect';$grid.MultiSelect=$true;$grid.AutoSizeColumnsMode='None';$grid.RowTemplate.Height=27
$grid.AlternatingRowsDefaultCellStyle.BackColor=[System.Drawing.Color]::FromArgb(246,249,253)
$grid.ColumnHeadersDefaultCellStyle.BackColor=$navy;$grid.ColumnHeadersDefaultCellStyle.ForeColor=$white
$grid.EnableHeadersVisualStyles=$false;$grid.ColumnHeadersHeight=34;$grid.ColumnHeadersHeightSizeMode='DisableResizing'
$content.Controls.Add($grid);$grid.BringToFront()
$progress=New-Object System.Windows.Forms.ProgressBar;$progress.SetBounds(15,10,210,12);$bottom.Controls.Add($progress)
$status=UiLabel $bottom 'Ready. Select filters and run inventory.' 15 30 740 23;$status.ForeColor=$muted
$run=UiButton $bottom 'Run inventory & export' 770 14 210 $true
$open=UiButton $bottom 'Open reports' 990 14 140
$close=UiButton $bottom 'Close' 1140 14 105
function Resize-Footer {
 $right=$bottom.ClientSize.Width-15
 $close.Left=$right-$close.Width;$open.Left=$close.Left-10-$open.Width;$run.Left=$open.Left-10-$run.Width
 $status.Width=[math]::Max(240,$run.Left-30)
}
$bottom.Add_Resize({Resize-Footer});Resize-Footer
function Set-GridRows {param([object[]]$Rows)
 $grid.SuspendLayout()
 try{
  $grid.DataSource=$null
  $table=New-Object System.Data.DataTable
  $columns=@('Domain','ComputerName','FQDN','ComputerType','Enabled','OperatingSystem','OperatingSystemVersion','IPv4Address','IPSource','ICMPStatus','LastLogonDate','OUPath')
  foreach($col in $columns){
   $kind=if($col -eq 'Enabled'){[bool]}elseif($col -eq 'LastLogonDate'){[datetime]}else{[string]}
   [void]$table.Columns.Add($col,$kind)
  }
  foreach($r in $Rows){
   $dr=$table.NewRow()
   foreach($col in $columns){
    $value=$r.$col
    if($null -eq $value -or [string]$value -eq ''){$dr[$col]=[DBNull]::Value}
    elseif($col -eq 'Enabled'){$dr[$col]=[bool]$value}
    elseif($col -eq 'LastLogonDate'){
     $parsed=[datetime]::MinValue
     if($value -is [datetime]){$dr[$col]=$value}
     elseif([datetime]::TryParse([string]$value,[ref]$parsed)){$dr[$col]=$parsed}
     else{$dr[$col]=[DBNull]::Value}
    }else{$dr[$col]=[string]$value}
   }
   [void]$table.Rows.Add($dr)
  }
  $grid.DataSource=$table
  $grid.AllowUserToOrderColumns=$true
  foreach($col in $grid.Columns){$col.SortMode=[System.Windows.Forms.DataGridViewColumnSortMode]::Automatic;$col.Width=if($col.Name -in @('FQDN','OUPath')){320}elseif($col.Name -eq 'OperatingSystem'){220}elseif($col.Name -eq 'Domain'){190}else{145}}
 }finally{$grid.ResumeLayout()}
}
$searchBox.Add_TextChanged({
 if($null -eq $grid.DataSource){return}
 $term=$searchBox.Text.Trim().Replace("'","''").Replace('[','[[]').Replace('%','[%]').Replace('*','[*]')
 $view=([System.Data.DataTable]$grid.DataSource).DefaultView
 if(-not $term){$view.RowFilter='';return}
 $parts=@();foreach($name in @('Domain','ComputerName','FQDN','OperatingSystem','IPv4Address','OUPath')){$parts+="[$name] LIKE '%$term%'"}
 try{$view.RowFilter=($parts -join ' OR ')}catch{$view.RowFilter=''}
})
$close.Add_Click({if(-not $script:Busy){$form.Close()}})
$open.Add_Click({if(Test-Path -LiteralPath $script:LastReportPath){Start-Process explorer.exe -ArgumentList ('"'+$script:LastReportPath+'"')}else{[void][System.Windows.Forms.MessageBox]::Show('No report folder is available yet.','Reports')}})
$run.Add_Click({
 if($script:Busy){return};$script:Busy=$true;$run.Enabled=$false;$form.Cursor=[System.Windows.Forms.Cursors]::WaitCursor
 try{
  $chosen=[string]$scopeBox.SelectedItem
  if($baseBox.Text.Trim() -and $chosen -eq 'Forest'){throw 'Search base DN requires Current or Specific scope.'}
  $chosenDomain=if($chosen -eq 'Specific'){[string]$domainBox.SelectedItem}else{''}
  if($chosen -eq 'Specific' -and -not $chosenDomain){throw 'Select a domain for Specific scope.'}
  $script:RunPath=Join-Path $OutputDirectory (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
  New-Item -ItemType Directory -Path $script:RunPath -Force | Out-Null
  $script:LogFile=Join-Path $script:RunPath 'Execution.log'
  $progress.Value=0
  $callback={param($n,$total,$d)
   $progress.Maximum=[math]::Max(1,$total);$progress.Value=[math]::Min($n,$progress.Maximum)
   $status.Text="Scanning ${d} ($n/$total)...";$status.Refresh();$progress.Refresh();[System.Windows.Forms.Application]::DoEvents()
  }
  $data=Invoke-Inventory -SelectedScope $chosen -SelectedDomain $chosenDomain -Base $baseBox.Text.Trim() -Type ([string]$typeBox.SelectedItem) -State ([string]$stateBox.SelectedItem) -DNS $dnsBox.Checked -Ping $pingBox.Checked -Timeout ([int]$timeoutBox.Value) -ProgressCallback $callback
  Export-Inventory -Inventory $data -TargetDirectory $script:RunPath
  $script:LastData=$data;$script:LastReportPath=$script:RunPath;$script:AllRows=@($data.Rows)
  $searchBox.Clear();Set-GridRows -Rows $script:AllRows
  $count=$script:AllRows.Count;$failed=@($data.Errors).Count
  $enabled=@($script:AllRows | Where-Object Enabled).Count
  $stats[0].Value.Text=[string]$count;$stats[1].Value.Text=[string]$enabled;$stats[2].Value.Text=[string]($count-$enabled)
  $stats[3].Value.Text='{0} / {1}' -f @($data.Domains).Count,$failed
  $status.Text="Complete: $count computers; $failed domain errors. Reports saved."
  $icon=if($failed){[System.Windows.Forms.MessageBoxIcon]::Warning}else{[System.Windows.Forms.MessageBoxIcon]::Information}
  [void][System.Windows.Forms.MessageBox]::Show("Records: $count`nDomain errors: $failed`nReport directory: $script:RunPath",'Inventory complete',[System.Windows.Forms.MessageBoxButtons]::OK,$icon)
 }catch{
  Write-AuditLog $_.Exception.Message 'ERROR';$status.Text='Inventory failed. Check execution log.'
  [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Inventory failed',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
 }finally{$script:Busy=$false;$run.Enabled=$true;$form.Cursor=[System.Windows.Forms.Cursors]::Default}
})
[void]$form.ShowDialog()
$form.Dispose()

# End of script
