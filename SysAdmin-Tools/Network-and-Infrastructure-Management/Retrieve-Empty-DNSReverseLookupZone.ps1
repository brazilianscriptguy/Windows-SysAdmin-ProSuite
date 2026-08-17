<#
.SYNOPSIS
  Enterprise DNS Reverse Lookup Zone Audit and Cleanup Tool.

.DESCRIPTION
  Audits reverse lookup zones on a Windows DNS server and identifies zones that
  contain no substantive DNS records beyond zone infrastructure records such as
  SOA and NS.

  IMPORTANT CORRECTION:
  The legacy script considered a zone "empty" when it contained no timestamped
  (dynamic) records. That can incorrectly classify a valid reverse zone containing
  static PTR records as empty. This version does NOT use timestamp presence as the
  emptiness criterion.

  A reverse lookup zone is considered EMPTY only when, after excluding SOA and NS
  infrastructure records, no substantive records remain.

  Designed for Windows PowerShell 5.1 and Windows Server 2019.

.AUTHOR
  Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
  2026-08-17-v2.0.2-ENTERPRISE-IP-AUDIT

.REQUIREMENTS
  - Windows PowerShell 5.1
  - Windows Server 2019
  - DnsServer PowerShell module
  - DNS query permissions
  - DNS administrative rights for zone deletion

.SAFETY
  - Audit is read-only.
  - Dry Run enabled by default.
  - Only explicitly checked EMPTY zones are eligible for deletion.
  - Zone identity/state is revalidated immediately before deletion.
  - Zone is re-audited immediately before deletion.
  - Forward lookup zones are never included.
  - Root hints / non-reverse zones are excluded by IsReverseLookupZone.
  - Per-zone SUCCESS / FAILED / SKIPPED accounting.
  - Audit/export reports use direct IP/network notation as the primary address field.
  - Reverse-zone DNS names are retained only for traceability and DNS operations.
#>

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param([switch]$ShowConsole)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

# =====================================================================================
# Console suppression / initialization
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

    if(-not(Get-Module -ListAvailable -Name DnsServer)){
        throw 'The DnsServer PowerShell module is not installed or available.'
    }
    Import-Module DnsServer -ErrorAction Stop
}catch{
    Write-Error "Initialization failed: $($_.Exception.Message)"
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

    try{
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    }catch{}

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

# =====================================================================================
# Reverse-zone to direct IP/network conversion
# =====================================================================================
function Convert-ReverseZoneToDirectAddress {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ZoneName)

    $name = $ZoneName.Trim().TrimEnd('.')

    # Standard IPv4 reverse zones: e.g. 0.10.10.in-addr.arpa -> 10.10.0.0/24
    if($name -match '(?i)\.in-addr\.arpa$'){
        $prefix = $name -replace '(?i)\.in-addr\.arpa$',''
        $labels = @($prefix -split '\.')

        # Standard octet-aligned reverse zone.
        $octets = New-Object Collections.Generic.List[int]
        $standard = $true

        foreach($label in $labels){
            $value = 0
            if([int]::TryParse($label,[ref]$value) -and $value -ge 0 -and $value -le 255){
                $octets.Add($value)
            }else{
                $standard = $false
                break
            }
        }

        if($standard -and $octets.Count -ge 1 -and $octets.Count -le 4){
            $direct = @($octets)
            [array]::Reverse($direct)

            while($direct.Count -lt 4){
                $direct += 0
            }

            $prefixLength = $octets.Count * 8
            return ("{0}.{1}.{2}.{3}/{4}" -f
                $direct[0],$direct[1],$direct[2],$direct[3],$prefixLength)
        }

        # RFC 2317 / classless delegation names are not safely reducible to one
        # canonical CIDR without interpreting the delegation label. Keep a clear
        # direct-analysis marker instead of inventing an address.
        return "CLASSLESS/RFC2317: $ZoneName"
    }

    # IPv6 nibble-reversed zones: produce a canonical IPv6 prefix when possible.
    if($name -match '(?i)\.ip6\.arpa$'){
        $prefix = $name -replace '(?i)\.ip6\.arpa$',''
        $nibbles = @($prefix -split '\.')

        if($nibbles.Count -ge 1 -and
           @($nibbles | Where-Object { $_ -notmatch '^[0-9A-Fa-f]$' }).Count -eq 0){

            [array]::Reverse($nibbles)
            $hex = ($nibbles -join '')

            # Pad to full 128-bit address for deterministic display.
            $padded = $hex.PadRight(32,'0')
            $groups = New-Object Collections.Generic.List[string]

            for($i=0;$i-lt32;$i+=4){
                $groups.Add($padded.Substring($i,4))
            }

            $prefixLength = $nibbles.Count * 4
            return (($groups -join ':') + "/$prefixLength")
        }

        return "IPV6-REVERSE-UNPARSED: $ZoneName"
    }

    return "UNSUPPORTED-REVERSE-ZONE: $ZoneName"
}

# =====================================================================================
# DNS helpers
# =====================================================================================
function Get-LocalFqdn {
    try{
        return [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName
    }catch{
        return $env:COMPUTERNAME
    }
}

function Get-ReverseZoneAuditRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)]$Zone
    )

    $records=@()
    $queryStatus='SUCCESS'
    $detail=''

    try{
        $records=@(
            Get-DnsServerResourceRecord -ComputerName $ComputerName `
                -ZoneName $Zone.ZoneName -ErrorAction Stop
        )
    }catch{
        $queryStatus='FAILED'
        $detail=$_.Exception.Message
        Write-AppLog "Record query failed for zone '$($Zone.ZoneName)': $detail" ERROR
    }

    $soa=@($records|Where-Object{$_.RecordType-eq'SOA'})
    $ns=@($records|Where-Object{$_.RecordType-eq'NS'})

    # Substantive records are all records other than SOA and NS.
    # Static PTRs absolutely count as substantive records.
    $substantive=@(
        $records|Where-Object{
            $_.RecordType-ne'SOA' -and
            $_.RecordType-ne'NS'
        }
    )

    $ptr=@($substantive|Where-Object{$_.RecordType-eq'PTR'})
    $dynamic=@($substantive|Where-Object{$null-ne$_.TimeStamp})
    $static=@($substantive|Where-Object{$null-eq$_.TimeStamp})

    $status=if($queryStatus-ne'SUCCESS'){
        'QUERY FAILED'
    }elseif($substantive.Count-eq0){
        'EMPTY'
    }else{
        'IN USE'
    }

    [pscustomobject]@{
        DirectIPAddress=(Convert-ReverseZoneToDirectAddress -ZoneName ([string]$Zone.ZoneName))
        ZoneName=[string]$Zone.ZoneName
        ZoneType=[string]$Zone.ZoneType
        IsDsIntegrated=[bool]$Zone.IsDsIntegrated
        IsAutoCreated=[bool]$Zone.IsAutoCreated
        IsPaused=[bool]$Zone.IsPaused
        IsShutdown=[bool]$Zone.IsShutdown
        DynamicUpdate=[string]$Zone.DynamicUpdate
        TotalRecords=[int]$records.Count
        SOARecords=[int]$soa.Count
        NSRecords=[int]$ns.Count
        SubstantiveRecords=[int]$substantive.Count
        PTRRecords=[int]$ptr.Count
        StaticRecords=[int]$static.Count
        DynamicRecords=[int]$dynamic.Count
        Status=[string]$status
        QueryStatus=[string]$queryStatus
        Detail=[string]$detail
        DnsServer=[string]$ComputerName
    }
}

function Invoke-ReverseZoneAudit {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ComputerName)

    Write-AppLog "Starting reverse-zone audit on DNS server '$ComputerName'." INFO
    Set-AppStatus "Querying DNS zones on $ComputerName..."

    $zones=@(
        Get-DnsServerZone -ComputerName $ComputerName -ErrorAction Stop |
        Where-Object{$_.IsReverseLookupZone-eq$true} |
        Sort-Object ZoneName
    )

    $records=New-Object Collections.ArrayList
    $i=0
    foreach($zone in $zones){
        $i++
        Set-AppStatus ("Auditing reverse zone {0} of {1}: {2}"-f$i,$zones.Count,$zone.ZoneName)
        [void]$records.Add((Get-ReverseZoneAuditRecord -ComputerName $ComputerName -Zone $zone))
        [Windows.Forms.Application]::DoEvents()
    }

    Write-AppLog ("Reverse-zone audit completed. ReverseZones={0}; Empty={1}; InUse={2}; QueryFailed={3}."-f
        $zones.Count,
        @($records|Where-Object{$_.Status-eq'EMPTY'}).Count,
        @($records|Where-Object{$_.Status-eq'IN USE'}).Count,
        @($records|Where-Object{$_.Status-eq'QUERY FAILED'}).Count
    ) SUCCESS

    return @($records)
}

function Test-ZoneStillEligibleForDeletion {
    param(
        [Parameter(Mandatory=$true)]$Record,
        [Parameter(Mandatory=$true)][string]$ComputerName
    )

    try{
        $zone=Get-DnsServerZone -ComputerName $ComputerName `
            -Name $Record.ZoneName -ErrorAction Stop

        if(-not$zone.IsReverseLookupZone){
            return [pscustomobject]@{Eligible=$false;Detail='Zone is no longer a reverse lookup zone.'}
        }

        $current=Get-ReverseZoneAuditRecord -ComputerName $ComputerName -Zone $zone

        if($current.QueryStatus-ne'SUCCESS'){
            return [pscustomobject]@{Eligible=$false;Detail='Zone record query failed during revalidation.'}
        }

        if($current.Status-ne'EMPTY'){
            return [pscustomobject]@{
                Eligible=$false
                Detail="Zone is no longer empty. SubstantiveRecords=$($current.SubstantiveRecords); PTR=$($current.PTRRecords)."
            }
        }

        return [pscustomobject]@{Eligible=$true;Detail='Zone remains empty.'}
    }catch{
        return [pscustomobject]@{Eligible=$false;Detail=$_.Exception.Message}
    }
}

# =====================================================================================
# Searchable/sortable grid
# =====================================================================================
function Set-ZoneList {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [object[]]$Rows
    )

    $checked=@{}
    foreach($i in $script:listView.CheckedItems){
        if($i.Tag){$checked[[string]$i.Tag.ZoneName]=$true}
    }

    $script:listView.BeginUpdate()
    try{
        $script:listView.Items.Clear()

        foreach($r in $Rows){
            $item=New-Object Windows.Forms.ListViewItem([string]$r.DirectIPAddress)
            [void]$item.SubItems.Add([string]$r.ZoneName)
            [void]$item.SubItems.Add([string]$r.Status)
            [void]$item.SubItems.Add([string]$r.ZoneType)
            [void]$item.SubItems.Add([string]$r.IsDsIntegrated)
            [void]$item.SubItems.Add([string]$r.DynamicUpdate)
            [void]$item.SubItems.Add([string]$r.TotalRecords)
            [void]$item.SubItems.Add([string]$r.SOARecords)
            [void]$item.SubItems.Add([string]$r.NSRecords)
            [void]$item.SubItems.Add([string]$r.SubstantiveRecords)
            [void]$item.SubItems.Add([string]$r.PTRRecords)
            [void]$item.SubItems.Add([string]$r.StaticRecords)
            [void]$item.SubItems.Add([string]$r.DynamicRecords)
            [void]$item.SubItems.Add([string]$r.QueryStatus)
            [void]$item.SubItems.Add([string]$r.Detail)
            $item.Tag=$r

            if($r.Status-eq'EMPTY'-and$checked.ContainsKey([string]$r.ZoneName)){
                $item.Checked=$true
            }

            [void]$script:listView.Items.Add($item)
        }
    }finally{
        $script:listView.EndUpdate()
    }
}

function Test-ZoneMatchesFilter {
    param($Zone,[string]$Filter)

    if([string]::IsNullOrWhiteSpace($Filter)){return $true}
    $needle=$Filter.Trim()

    foreach($v in @(
        $Zone.DirectIPAddress,$Zone.ZoneName,$Zone.Status,$Zone.ZoneType,[string]$Zone.IsDsIntegrated,
        $Zone.DynamicUpdate,[string]$Zone.TotalRecords,[string]$Zone.SOARecords,
        [string]$Zone.NSRecords,[string]$Zone.SubstantiveRecords,[string]$Zone.PTRRecords,
        [string]$Zone.StaticRecords,[string]$Zone.DynamicRecords,$Zone.QueryStatus,
        $Zone.Detail,$Zone.DnsServer
    )){
        if(([string]$v).IndexOf($needle,[StringComparison]::OrdinalIgnoreCase)-ge0){
            return $true
        }
    }
    return $false
}

function Apply-ZoneFilter {
    param([string]$Filter)

    $script:Displayed=@(
        $script:Inventory|Where-Object{
            Test-ZoneMatchesFilter -Zone $_ -Filter $Filter
        }
    )

    Set-ZoneList -Rows $script:Displayed

    $empty=@($script:Inventory|Where-Object{$_.Status-eq'EMPTY'}).Count
    $inuse=@($script:Inventory|Where-Object{$_.Status-eq'IN USE'}).Count
    $failed=@($script:Inventory|Where-Object{$_.Status-eq'QUERY FAILED'}).Count

    $summaryLabel.Text="Total reverse zones: $($script:Inventory.Count) | Empty: $empty | In use: $inuse | Query failed: $failed | Displayed: $($script:Displayed.Count)"
}

function Sort-Zones {
    param([int]$Column)

    if($script:SortColumn-eq$Column){
        $script:SortDescending=-not$script:SortDescending
    }else{
        $script:SortColumn=$Column
        $script:SortDescending=$false
    }

    switch($Column){
        0{$p='DirectIPAddress'}1{$p='ZoneName'}2{$p='Status'}3{$p='ZoneType'}
        4{$p='IsDsIntegrated'}5{$p='DynamicUpdate'}6{$p='TotalRecords'}7{$p='SOARecords'}
        8{$p='NSRecords'}9{$p='SubstantiveRecords'}10{$p='PTRRecords'}11{$p='StaticRecords'}
        12{$p='DynamicRecords'}13{$p='QueryStatus'}14{$p='Detail'}
        default{$p='DirectIPAddress'}
    }

    $script:Inventory=@(
        $script:Inventory|Sort-Object -Property $p -Descending:$script:SortDescending
    )
    Apply-ZoneFilter -Filter $txtFilter.Text
}

function Get-CheckedEmptyZones {
    $rows=New-Object Collections.ArrayList
    foreach($i in $script:listView.CheckedItems){
        if($i.Tag-and$i.Tag.Status-eq'EMPTY'){
            [void]$rows.Add($i.Tag)
        }
    }
    return @($rows)
}

# =====================================================================================
# Controlled deletion
# =====================================================================================
function Remove-EmptyReverseZonesControlled {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)][object[]]$Zones,
        [Parameter(Mandatory=$true)][string]$ComputerName
    )

    $results=New-Object Collections.ArrayList

    foreach($z in $Zones){
        try{
            if($z.Status-ne'EMPTY'){
                [void]$results.Add([pscustomobject]@{
                    ZoneName=$z.ZoneName;Result='SKIPPED';Detail='Zone is not classified EMPTY.'
                })
                continue
            }

            $validation=Test-ZoneStillEligibleForDeletion -Record $z -ComputerName $ComputerName
            if(-not$validation.Eligible){
                Write-AppLog "Skipped '$($z.ZoneName)': $($validation.Detail)" WARN
                [void]$results.Add([pscustomobject]@{
                    ZoneName=$z.ZoneName;Result='SKIPPED';Detail=$validation.Detail
                })
                continue
            }

            $target="$($z.ZoneName) on $ComputerName"

            if($PSCmdlet.ShouldProcess($target,'Remove empty reverse lookup zone')){
                Remove-DnsServerZone -Name $z.ZoneName -ComputerName $ComputerName `
                    -Force -ErrorAction Stop

                # Verify the zone no longer exists.
                $stillExists=$false
                try{
                    $null=Get-DnsServerZone -Name $z.ZoneName -ComputerName $ComputerName -ErrorAction Stop
                    $stillExists=$true
                }catch{
                    $stillExists=$false
                }

                if($stillExists){
                    throw 'Post-delete verification failed: zone still exists.'
                }

                Write-AppLog "Removed and verified empty reverse zone '$($z.ZoneName)' on '$ComputerName'." SUCCESS
                [void]$results.Add([pscustomobject]@{
                    ZoneName=$z.ZoneName;Result='SUCCESS';Detail='Zone removed and verified.'
                })
            }
        }catch{
            Write-AppLog "Zone removal failed for '$($z.ZoneName)': $($_.Exception.Message)" ERROR
            [void]$results.Add([pscustomobject]@{
                ZoneName=$z.ZoneName;Result='FAILED';Detail=$_.Exception.Message
            })
        }
    }

    return @($results)
}

# =====================================================================================
# GUI
# =====================================================================================
$form=New-Object Windows.Forms.Form
$form.Text='DNS Reverse Lookup Zone Audit & Cleanup - Enterprise Edition'
$form.Size=New-Object Drawing.Size(1500,850)
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

# Server / action row
$p1=New-Object Windows.Forms.TableLayoutPanel
$p1.Dock='Fill';$p1.AutoSize=$true;$p1.ColumnCount=6;$p1.RowCount=1
$p1.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$p1.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
$p1.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$p1.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$p1.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$p1.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))

$lblServer=New-Object Windows.Forms.Label
$lblServer.Text='DNS Server:';$lblServer.AutoSize=$true;$lblServer.Anchor='Left';$lblServer.Margin=New-Object Windows.Forms.Padding(3,7,8,3)
$p1.Controls.Add($lblServer,0,0)

$txtServer=New-Object Windows.Forms.TextBox
$txtServer.Dock='Fill'
$txtServer.Text=Get-LocalFqdn
$p1.Controls.Add($txtServer,1,0)

$btnAudit=New-Object Windows.Forms.Button
$btnAudit.Text='Audit Reverse Zones';$btnAudit.Width=125
$p1.Controls.Add($btnAudit,2,0)

$btnSelectEmpty=New-Object Windows.Forms.Button
$btnSelectEmpty.Text='Select All Empty';$btnSelectEmpty.Width=115
$p1.Controls.Add($btnSelectEmpty,3,0)

$btnDelete=New-Object Windows.Forms.Button
$btnDelete.Text='Delete Selected';$btnDelete.Width=115
$p1.Controls.Add($btnDelete,4,0)

$chkDryRun=New-Object Windows.Forms.CheckBox
$chkDryRun.Text='Dry Run';$chkDryRun.Checked=$true;$chkDryRun.AutoSize=$true;$chkDryRun.Margin=New-Object Windows.Forms.Padding(18,7,3,3)
$script:chkDryRun=$chkDryRun
$p1.Controls.Add($chkDryRun,5,0)

$main.Controls.Add($p1,0,0)

# Preview/export row
$p2=New-Object Windows.Forms.FlowLayoutPanel
$p2.Dock='Fill';$p2.AutoSize=$true;$p2.WrapContents=$false

$btnPreview=New-Object Windows.Forms.Button
$btnPreview.Text='Preview Deletion';$btnPreview.Width=115
$p2.Controls.Add($btnPreview)

$btnExport=New-Object Windows.Forms.Button
$btnExport.Text='Export Displayed';$btnExport.Width=120
$p2.Controls.Add($btnExport)

$btnExportEmpty=New-Object Windows.Forms.Button
$btnExportEmpty.Text='Export Empty Zones';$btnExportEmpty.Width=130
$p2.Controls.Add($btnExportEmpty)

$main.Controls.Add($p2,0,1)

# Filter row
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

# Results grid
$listView=New-Object Windows.Forms.ListView
$listView.Dock='Fill'
$listView.View='Details'
$listView.CheckBoxes=$true
$listView.FullRowSelect=$true
$listView.GridLines=$true
$listView.HideSelection=$false
$script:listView=$listView

[void]$listView.Columns.Add('Direct IP / Network',180)
[void]$listView.Columns.Add('Reverse Zone Name',220)
[void]$listView.Columns.Add('Status',90)
[void]$listView.Columns.Add('Zone Type',90)
[void]$listView.Columns.Add('AD Integrated',95)
[void]$listView.Columns.Add('Dynamic Update',105)
[void]$listView.Columns.Add('Total',65)
[void]$listView.Columns.Add('SOA',55)
[void]$listView.Columns.Add('NS',55)
[void]$listView.Columns.Add('Substantive',85)
[void]$listView.Columns.Add('PTR',55)
[void]$listView.Columns.Add('Static',65)
[void]$listView.Columns.Add('Dynamic',70)
[void]$listView.Columns.Add('Query',80)
[void]$listView.Columns.Add('Detail',310)

$main.Controls.Add($listView,0,3)

$summaryLabel=New-Object Windows.Forms.Label
$summaryLabel.AutoSize=$true
$summaryLabel.Text='No reverse-zone audit has been run.'
$main.Controls.Add($summaryLabel,0,4)

$txtRuntimeLog=New-Object Windows.Forms.TextBox
$txtRuntimeLog.Dock='Fill'
$txtRuntimeLog.Multiline=$true
$txtRuntimeLog.ReadOnly=$true
$txtRuntimeLog.ScrollBars='Vertical'
$txtRuntimeLog.Font=New-Object Drawing.Font('Consolas',8.5)
$script:txtRuntimeLog=$txtRuntimeLog
$main.Controls.Add($txtRuntimeLog,0,5)

$statusStrip=New-Object Windows.Forms.StatusStrip
$statusMain=New-Object Windows.Forms.ToolStripStatusLabel
$statusMain.Spring=$true
$statusMain.Text='Ready'
$script:statusMain=$statusMain
[void]$statusStrip.Items.Add($statusMain)

$statusMode=New-Object Windows.Forms.ToolStripStatusLabel
$statusMode.Text='Mode: DRY RUN'
[void]$statusStrip.Items.Add($statusMode)

$main.Controls.Add($statusStrip,0,6)

# =====================================================================================
# GUI events
# =====================================================================================
$chkDryRun.Add_CheckedChanged({
    $statusMode.Text=if($chkDryRun.Checked){'Mode: DRY RUN'}else{'Mode: COMMIT'}
})

$txtFilter.Add_TextChanged({
    Apply-ZoneFilter -Filter $txtFilter.Text
})

$btnClear.Add_Click({$txtFilter.Clear()})

$listView.Add_ColumnClick({
    param($sender,$e)
    Sort-Zones -Column $e.Column
})

# Only EMPTY zones may be selected for deletion.
$listView.Add_ItemCheck({
    param($sender,$e)
    try{
        $item=$listView.Items[$e.Index]
        if($item.Tag-and$item.Tag.Status-ne'EMPTY'-and
           $e.NewValue-eq[Windows.Forms.CheckState]::Checked){
            $e.NewValue=[Windows.Forms.CheckState]::Unchecked
            Set-AppStatus "Selection blocked: '$($item.Tag.ZoneName)' is $($item.Tag.Status). Only EMPTY reverse zones can be deleted."
        }
    }catch{}
})

$btnSelectEmpty.Add_Click({
    $selected=0
    foreach($i in $listView.Items){
        if($i.Tag-and$i.Tag.Status-eq'EMPTY'){
            $i.Checked=$true
            $selected++
        }else{
            $i.Checked=$false
        }
    }
    Set-AppStatus "Selected $selected displayed EMPTY reverse zone(s)."
})

$btnAudit.Add_Click({
    try{
        $server=$txtServer.Text.Trim()
        if([string]::IsNullOrWhiteSpace($server)){
            throw 'Enter a DNS server name or FQDN.'
        }

        $script:Inventory=@(
            Invoke-ReverseZoneAudit -ComputerName $server
        )

        $script:Displayed=@($script:Inventory)
        $txtFilter.Clear()
        Set-ZoneList -Rows $script:Displayed
        Apply-ZoneFilter -Filter ''

        Set-AppStatus 'Reverse-zone audit completed.'
    }catch{
        Show-AppMessage "Reverse-zone audit failed: $($_.Exception.Message)" Error
    }
})

$btnPreview.Add_Click({
    $selected=@(Get-CheckedEmptyZones)
    if($selected.Count-eq0){
        Show-AppMessage 'Select at least one EMPTY reverse zone.' Information
        return
    }

    $names=($selected | ForEach-Object {
        "{0}    [{1}]" -f $_.DirectIPAddress,$_.ZoneName
    }) -join [Environment]::NewLine

    $message=@"
Mode: $(if($chkDryRun.Checked){'DRY RUN'}else{'COMMIT'})

Selected EMPTY reverse zones: $($selected.Count)

$names

Each zone will be re-audited immediately before deletion.
Any substantive record, including a STATIC PTR, will block deletion.
"@

    [void][Windows.Forms.MessageBox]::Show(
        $message,'Deletion Preview',
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Information
    )
})

$btnDelete.Add_Click({
    try{
        $selected=@(Get-CheckedEmptyZones)
        if($selected.Count-eq0){
            Show-AppMessage 'Select at least one EMPTY reverse zone.' Information
            return
        }

        $server=$txtServer.Text.Trim()

        if($chkDryRun.Checked){
            foreach($z in $selected){
                $validation=Test-ZoneStillEligibleForDeletion -Record $z -ComputerName $server
                if($validation.Eligible){
                    Write-AppLog "DRY RUN: Would remove EMPTY reverse zone '$($z.ZoneName)' from '$server'." INFO
                }else{
                    Write-AppLog "DRY RUN BLOCKED: '$($z.ZoneName)' - $($validation.Detail)" WARN
                }
            }
            Show-AppMessage 'Dry Run completed. No DNS zones were removed.' Information
            return
        }

        $confirm=[Windows.Forms.MessageBox]::Show(
            "Delete $($selected.Count) selected EMPTY reverse lookup zone(s) from '$server'?`r`n`r`nEach zone will be revalidated immediately before deletion.",
            'Confirm Reverse Zone Deletion',
            [Windows.Forms.MessageBoxButtons]::YesNo,
            [Windows.Forms.MessageBoxIcon]::Warning,
            [Windows.Forms.MessageBoxDefaultButton]::Button2
        )

        if($confirm-ne[Windows.Forms.DialogResult]::Yes){
            Write-AppLog 'Zone deletion cancelled by operator.' WARN
            return
        }

        Set-AppStatus 'Deleting and verifying selected empty reverse zones...'
        $results=@(
            Remove-EmptyReverseZonesControlled -Zones $selected `
                -ComputerName $server -Confirm:$false
        )

        $success=@($results|Where-Object{$_.Result-eq'SUCCESS'}).Count
        $failed=@($results|Where-Object{$_.Result-eq'FAILED'}).Count
        $skipped=@($results|Where-Object{$_.Result-eq'SKIPPED'}).Count

        Write-AppLog ("Zone deletion summary: Success={0}; Failed={1}; Skipped={2}"-f
            $success,$failed,$skipped) INFO

        $script:Inventory=@(
            Invoke-ReverseZoneAudit -ComputerName $server
        )
        Apply-ZoneFilter -Filter $txtFilter.Text

        $message="Execution completed.`r`n`r`nDeleted: $success`r`nFailed: $failed`r`nSkipped: $skipped"
        if($failed-gt0){
            Show-AppMessage $message Warning
        }else{
            Show-AppMessage $message Information
        }
    }catch{
        Show-AppMessage "Zone deletion failed: $($_.Exception.Message)" Error
    }
})

$btnExportEmpty.Add_Click({
    try{
        # Export EMPTY zones from the complete audit inventory, not merely the
        # currently filtered/displayed rows. This makes the export operationally
        # deterministic regardless of the active GUI search filter.
        $emptyZones=@(
            $script:Inventory |
            Where-Object { $_.Status -eq 'EMPTY' } |
            Sort-Object ZoneName
        )

        if($emptyZones.Count -eq 0){
            Show-AppMessage 'There are no EMPTY reverse lookup zones in the current audit inventory.' Information
            return
        }

        $dlg=New-Object Windows.Forms.SaveFileDialog
        $dlg.Filter='CSV (*.csv)|*.csv'
        $dlg.FileName="DNS-Empty-Reverse-Zones-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"

        if($dlg.ShowDialog()-eq[Windows.Forms.DialogResult]::OK){
            $emptyZones |
                Select-Object DirectIPAddress,DnsServer,ZoneName,Status,ZoneType,IsDsIntegrated,IsAutoCreated,
                    IsPaused,IsShutdown,DynamicUpdate,TotalRecords,SOARecords,NSRecords,
                    SubstantiveRecords,PTRRecords,StaticRecords,DynamicRecords,QueryStatus,Detail |
                Export-Csv -LiteralPath $dlg.FileName -NoTypeInformation -Encoding UTF8

            Write-AppLog ("Exported {0} EMPTY reverse lookup zone(s) to '{1}'." -f
                $emptyZones.Count,$dlg.FileName) SUCCESS

            Set-AppStatus "Exported $($emptyZones.Count) EMPTY reverse lookup zone(s)."

            [void][Windows.Forms.MessageBox]::Show(
                "Export completed successfully.`r`n`r`nEmpty zones exported: $($emptyZones.Count)`r`nFile: $($dlg.FileName)",
                'Export Empty Zones',
                [Windows.Forms.MessageBoxButtons]::OK,
                [Windows.Forms.MessageBoxIcon]::Information
            )
        }
    }catch{
        Show-AppMessage "Empty-zone export failed: $($_.Exception.Message)" Error
    }
})

$btnExport.Add_Click({
    try{
        if($script:Displayed.Count-eq0){
            throw 'There are no displayed rows to export.'
        }

        $dlg=New-Object Windows.Forms.SaveFileDialog
        $dlg.Filter='CSV (*.csv)|*.csv'
        $dlg.FileName="DNS-Reverse-Zone-Audit-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"

        if($dlg.ShowDialog()-eq[Windows.Forms.DialogResult]::OK){
            $script:Displayed|
                Select-Object DirectIPAddress,DnsServer,ZoneName,Status,ZoneType,IsDsIntegrated,IsAutoCreated,
                    IsPaused,IsShutdown,DynamicUpdate,TotalRecords,SOARecords,NSRecords,
                    SubstantiveRecords,PTRRecords,StaticRecords,DynamicRecords,QueryStatus,Detail|
                Export-Csv -LiteralPath $dlg.FileName -NoTypeInformation -Encoding UTF8

            Write-AppLog "Exported displayed reverse-zone audit to '$($dlg.FileName)'." SUCCESS
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
        'DNS Reverse Lookup Zone Audit & Cleanup',
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Error
    )
}finally{
    Write-AppLog "Closing $($script:ScriptName)." INFO
}

# End of Script
