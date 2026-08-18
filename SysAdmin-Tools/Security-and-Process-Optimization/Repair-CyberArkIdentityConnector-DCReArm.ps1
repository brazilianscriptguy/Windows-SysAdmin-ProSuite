<#
.SYNOPSIS
    Remotely validates and re-arms the CyberArk Identity Connector installed on
    a selected writable Active Directory Domain Controller.

.DESCRIPTION
    Windows PowerShell 5.1 / Windows Server 2019 compatible.

    This tool is designed for environments where CyberArk Identity Connector
    is installed only on Domain Controllers.

    Workflow:
      1. Discover every writable DC in every domain of the current forest.
      2. Display only Domain Controllers.
      3. Select one DC.
      4. Validate remote management.
      5. Validate CyberArk service:
           Service Name : IdaptiveConnector
           Display Name : CyberArk Identity Connector
      6. Resolve the service executable from Win32_Service.PathName.
      7. Validate ProxyHost.exe exists on the selected DC.
      8. Test AD connectivity ports against the selected DC.
      9. Configure service startup/recovery.
     10. Restart IdaptiveConnector remotely.
     11. Verify the service returns to Running state.

    IMPORTANT:
      A Domain Controller does not use the same workstation/member-server
      secure-channel repair workflow. Therefore this tool DOES NOT execute
      nltest /sc_reset or Test-ComputerSecureChannel against the selected DC.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    2026-08-18-v1.4.0

.REQUIREMENTS
    - Windows PowerShell 5.1
    - Windows Server 2019
    - ActiveDirectory PowerShell module
    - Administrative rights on the selected DC
    - WinRM / PowerShell Remoting enabled to the selected DC
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$ShowConsole
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ==============================================================================
# INITIALIZATION
# ==============================================================================
try {
    if(-not $ShowConsole){
        try{
            if(-not ('NativeConsoleWindow' -as [type])){
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
        if(h != IntPtr.Zero) { ShowWindow(h, 0); }
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

    if(-not (Get-Module -ListAvailable -Name ActiveDirectory)){
        throw 'The ActiveDirectory PowerShell module is not available.'
    }

    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Error "Initialization failed: $($_.Exception.Message)"
    return
}

$script:AppName = 'CyberArk Identity Connector - DC Re-Arm'
$script:AppVersion = '1.4.0'
$script:LogRoot = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'CyberArkIdentityConnector-ReArm\Logs'
$script:LogFile = Join-Path $script:LogRoot ("CyberArk-DC-ReArm-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$script:DCInventory = @()
$script:DisplayedDCs = @()
$script:txtLog = $null
$script:statusMain = $null

if(-not (Test-Path -LiteralPath $script:LogRoot)){
    New-Item -Path $script:LogRoot -ItemType Directory -Force | Out-Null
}

# ==============================================================================
# LOGGING / UI HELPERS
# ==============================================================================
function Write-AppLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','SUCCESS','WARN','ERROR')][string]$Level='INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message

    try{
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    }catch{}

    if($script:txtLog -and -not $script:txtLog.IsDisposed){
        $script:txtLog.AppendText($line + [Environment]::NewLine)
        $script:txtLog.SelectionStart = $script:txtLog.Text.Length
        $script:txtLog.ScrollToCaret()
    }
    elseif($ShowConsole){
        Write-Host $line
    }
}

function Set-AppStatus {
    param([string]$Text)

    if($script:statusMain -and -not $script:statusMain.IsDisposed){
        $script:statusMain.Text = $Text
        [Windows.Forms.Application]::DoEvents()
    }
}

function Show-AppMessage {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('Information','Warning','Error')][string]$Type='Information'
    )

    $icon = switch($Type){
        'Warning' { [Windows.Forms.MessageBoxIcon]::Warning }
        'Error'   { [Windows.Forms.MessageBoxIcon]::Error }
        default   { [Windows.Forms.MessageBoxIcon]::Information }
    }

    [void][Windows.Forms.MessageBox]::Show(
        $Message,
        $script:AppName,
        [Windows.Forms.MessageBoxButtons]::OK,
        $icon
    )
}

# ==============================================================================
# FOREST / DOMAIN CONTROLLER DISCOVERY
# ==============================================================================
function Get-ForestWritableDomainControllers {
    [CmdletBinding()]
    param()

    $forest = Get-ADForest -ErrorAction Stop
    $rows = New-Object Collections.ArrayList

    foreach($domainName in @($forest.Domains)){
        Write-AppLog "Enumerating writable DCs for '$domainName'." INFO

        $domainDCs = @(
            Get-ADDomainController `
                -Filter * `
                -Server ([string]$domainName) `
                -ErrorAction Stop |
            Where-Object {
                -not $_.IsReadOnly
            } |
            Sort-Object HostName
        )

        foreach($dc in $domainDCs){
            $fqdn = [string](@($dc.HostName)[0])
            $ipv4 = [string](@($dc.IPv4Address)[0])

            [void]$rows.Add([pscustomobject]@{
                Domain             = [string]$domainName
                DCFqdn             = $fqdn
                IPv4               = $ipv4
                Site               = [string]$dc.Site
                GlobalCatalog      = [bool]$dc.IsGlobalCatalog
                Writable           = (-not [bool]$dc.IsReadOnly)
                ConnectorService   = 'NOT TESTED'
                ConnectorState     = ''
                ProxyHostPath       = ''
                ProxyHostPresent    = ''
                RemoteManagement   = ''
                LastConnectorCheck = $null
            })
        }
    }

    return @($rows)
}

# ==============================================================================
# CONNECTIVITY
# ==============================================================================
function Test-TcpPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)][int]$Port,
        [int]$TimeoutMs=2500
    )

    $client = New-Object Net.Sockets.TcpClient

    try{
        $iar = $client.BeginConnect($ComputerName,$Port,$null,$null)

        if(-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs,$false)){
            return $false
        }

        $client.EndConnect($iar)
        return $true
    }
    catch{
        return $false
    }
    finally{
        $client.Close()
    }
}

function Test-DomainControllerPorts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$DCFqdn
    )

    $ports = [ordered]@{
        Kerberos = 88
        LDAP     = 389
        SMB      = 445
        LDAPS    = 636
        GC       = 3268
        GCSSL    = 3269
    }

    $results = New-Object Collections.ArrayList

    foreach($name in $ports.Keys){
        $port = [int]$ports[$name]
        $ok = Test-TcpPort -ComputerName $DCFqdn -Port $port

        [void]$results.Add([pscustomobject]@{
            Test      = $name
            Port      = $port
            Reachable = $ok
        })
    }

    return @($results)
}

function Test-RemoteManagement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName
    )

    Test-WSMan -ComputerName $ComputerName -ErrorAction Stop | Out-Null
    return $true
}

# ==============================================================================
# CYBERARK REMOTE INSPECTION
# ==============================================================================
function Get-RemoteCyberArkConnectorState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName
    )

    Invoke-Command `
        -ComputerName $ComputerName `
        -ErrorAction Stop `
        -ScriptBlock {

            $service = Get-CimInstance `
                -ClassName Win32_Service `
                -Filter "Name='IdaptiveConnector'" `
                -ErrorAction SilentlyContinue

            if(-not $service){
                $service = Get-CimInstance Win32_Service |
                    Where-Object {
                        $_.DisplayName -eq 'CyberArk Identity Connector'
                    } |
                    Select-Object -First 1
            }

            if(-not $service){
                return [pscustomobject]@{
                    ComputerName     = $env:COMPUTERNAME
                    ServiceFound     = $false
                    ServiceName      = ''
                    DisplayName      = ''
                    State            = ''
                    StartMode        = ''
                    StartName        = ''
                    ProcessId        = 0
                    ServicePathName  = ''
                    ExecutablePath   = ''
                    ExecutableExists = $false
                }
            }

            $pathName = [string]$service.PathName
            $exePath = $null

            if($pathName.StartsWith('"')){
                $match = [regex]::Match(
                    $pathName,
                    '^"([^"]+\.exe)"',
                    [Text.RegularExpressions.RegexOptions]::IgnoreCase
                )

                if($match.Success){
                    $exePath = $match.Groups[1].Value
                }
            }

            if(-not $exePath){
                $match = [regex]::Match(
                    $pathName,
                    '^(.*?\.exe)(?:\s|$)',
                    [Text.RegularExpressions.RegexOptions]::IgnoreCase
                )

                if($match.Success){
                    $exePath = $match.Groups[1].Value.Trim().Trim('"')
                }
            }

            [pscustomobject]@{
                ComputerName     = $env:COMPUTERNAME
                ServiceFound     = $true
                ServiceName      = [string]$service.Name
                DisplayName      = [string]$service.DisplayName
                State            = [string]$service.State
                StartMode        = [string]$service.StartMode
                StartName        = [string]$service.StartName
                ProcessId        = [int]$service.ProcessId
                ServicePathName  = $pathName
                ExecutablePath   = [string]$exePath
                ExecutableExists = $(if($exePath){
                    Test-Path -LiteralPath $exePath -PathType Leaf
                }else{
                    $false
                })
            }
        }
}

function Update-DCConnectorState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$DCRecord,
        [switch]$Quiet
    )

    try{
        Test-RemoteManagement -ComputerName $DCRecord.DCFqdn | Out-Null
        $DCRecord.RemoteManagement = 'OK'

        $state = Get-RemoteCyberArkConnectorState -ComputerName $DCRecord.DCFqdn

        if(-not $state.ServiceFound){
            $DCRecord.ConnectorService = 'NOT INSTALLED'
            $DCRecord.ConnectorState = ''
            $DCRecord.ProxyHostPath = ''
            $DCRecord.ProxyHostPresent = 'NO'
            $DCRecord.LastConnectorCheck = Get-Date

            if(-not $Quiet){
                Write-AppLog "CyberArk Identity Connector not found on '$($DCRecord.DCFqdn)'." WARN
            }

            return $DCRecord
        }

        $DCRecord.ConnectorService = $state.ServiceName
        $DCRecord.ConnectorState = $state.State
        $DCRecord.ProxyHostPath = $state.ExecutablePath
        $DCRecord.ProxyHostPresent = $(if($state.ExecutableExists){'YES'}else{'NO'})
        $DCRecord.LastConnectorCheck = Get-Date

        if(-not $Quiet){
            Write-AppLog ("CyberArk live check. DC='{0}'; Service='{1}'; State='{2}'; ProxyHost='{3}'; Exists={4}." -f
                $DCRecord.DCFqdn,$state.ServiceName,$state.State,$state.ExecutablePath,$state.ExecutableExists) `
                $(if($state.ExecutableExists){'SUCCESS'}else{'WARN'})
        }

        return $DCRecord
    }
    catch{
        $DCRecord.RemoteManagement = 'FAILED'
        $DCRecord.ConnectorService = 'UNREACHABLE'
        $DCRecord.ConnectorState = ''
        $DCRecord.ProxyHostPath = ''
        $DCRecord.ProxyHostPresent = 'UNKNOWN'
        $DCRecord.LastConnectorCheck = Get-Date

        if(-not $Quiet){
            Write-AppLog "CyberArk live check failed on '$($DCRecord.DCFqdn)': $($_.Exception.Message)" WARN
        }

        return $DCRecord
    }
}

function Update-AllDCConnectorStates {
    [CmdletBinding()]
    param()

    $count = $script:DCInventory.Count
    $i = 0

    foreach($dc in @($script:DCInventory)){
        $i++
        Set-AppStatus "Testing CyberArk Connector on DC $i of ${count}: $($dc.DCFqdn)"
        [void](Update-DCConnectorState -DCRecord $dc -Quiet)
        [Windows.Forms.Application]::DoEvents()
    }

    Write-AppLog "CyberArk live inventory completed across $count writable DC(s)." SUCCESS
}

# ==============================================================================
# CYBERARK REMOTE RE-ARM
# ==============================================================================
function Invoke-RemoteCyberArkReArm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName
    )

    Invoke-Command `
        -ComputerName $ComputerName `
        -ErrorAction Stop `
        -ScriptBlock {

            $ErrorActionPreference = 'Stop'

            $service = Get-CimInstance `
                -ClassName Win32_Service `
                -Filter "Name='IdaptiveConnector'" `
                -ErrorAction SilentlyContinue

            if(-not $service){
                $service = Get-CimInstance Win32_Service |
                    Where-Object {
                        $_.DisplayName -eq 'CyberArk Identity Connector'
                    } |
                    Select-Object -First 1
            }

            if(-not $service){
                throw "CyberArk Identity Connector service 'IdaptiveConnector' was not found on '$env:COMPUTERNAME'."
            }

            $pathName = [string]$service.PathName
            $exePath = $null

            if($pathName.StartsWith('"')){
                $match = [regex]::Match(
                    $pathName,
                    '^"([^"]+\.exe)"',
                    [Text.RegularExpressions.RegexOptions]::IgnoreCase
                )

                if($match.Success){
                    $exePath = $match.Groups[1].Value
                }
            }

            if(-not $exePath){
                $match = [regex]::Match(
                    $pathName,
                    '^(.*?\.exe)(?:\s|$)',
                    [Text.RegularExpressions.RegexOptions]::IgnoreCase
                )

                if($match.Success){
                    $exePath = $match.Groups[1].Value.Trim().Trim('"')
                }
            }

            if(-not $exePath){
                throw "Could not resolve the CyberArk executable from service PathName '$pathName'."
            }

            if(-not (Test-Path -LiteralPath $exePath -PathType Leaf)){
                throw "CyberArk service '$($service.Name)' exists, but executable '$exePath' was not found."
            }

            # Ensure Automatic startup.
            Set-Service `
                -Name $service.Name `
                -StartupType Automatic `
                -ErrorAction Stop

            # Windows Service recovery:
            # restart after 5 seconds on first, second and subsequent failure.
            & sc.exe failure $service.Name `
                reset= 86400 `
                actions= restart/5000/restart/5000/restart/5000 |
                Out-Null

            if($LASTEXITCODE -ne 0){
                throw "Unable to configure service recovery for '$($service.Name)'."
            }

            & sc.exe failureflag $service.Name 1 | Out-Null

            if($LASTEXITCODE -ne 0){
                throw "Unable to enable service failure actions for '$($service.Name)'."
            }

            $before = Get-Service -Name $service.Name -ErrorAction Stop
            $beforeState = [string]$before.Status

            if($before.Status -ne 'Stopped'){
                Stop-Service `
                    -Name $service.Name `
                    -Force `
                    -ErrorAction Stop

                (Get-Service -Name $service.Name).WaitForStatus(
                    'Stopped',
                    [TimeSpan]::FromSeconds(30)
                )
            }

            Start-Service `
                -Name $service.Name `
                -ErrorAction Stop

            (Get-Service -Name $service.Name).WaitForStatus(
                'Running',
                [TimeSpan]::FromSeconds(30)
            )

            Start-Sleep -Seconds 2

            $finalService = Get-Service -Name $service.Name -ErrorAction Stop
            $finalCim = Get-CimInstance `
                -ClassName Win32_Service `
                -Filter "Name='$($service.Name)'" `
                -ErrorAction Stop

            $process = $null

            if($finalCim.ProcessId -gt 0){
                $process = Get-Process `
                    -Id $finalCim.ProcessId `
                    -ErrorAction SilentlyContinue
            }

            [pscustomobject]@{
                ComputerName     = $env:COMPUTERNAME
                ServiceName      = [string]$service.Name
                DisplayName      = [string]$service.DisplayName
                ExecutablePath   = $exePath
                ExecutableExists = (Test-Path -LiteralPath $exePath -PathType Leaf)
                PreviousState    = $beforeState
                FinalState       = [string]$finalService.Status
                StartMode        = [string]$finalCim.StartMode
                ProcessId        = [int]$finalCim.ProcessId
                ProcessRunning   = ($null -ne $process)
                Success          = (
                    $finalService.Status -eq 'Running' -and
                    $finalCim.ProcessId -gt 0 -and
                    $null -ne $process
                )
            }
        }
}

# ==============================================================================
# GUI
# ==============================================================================
$form = New-Object Windows.Forms.Form
$form.Text = "$($script:AppName) - v$($script:AppVersion)"
$form.Size = New-Object Drawing.Size(1080,760)
$form.MinimumSize = New-Object Drawing.Size(920,650)
$form.StartPosition = 'CenterScreen'

$main = New-Object Windows.Forms.TableLayoutPanel
$main.Dock = 'Fill'
$main.Padding = New-Object Windows.Forms.Padding(10)
$main.ColumnCount = 1
$main.RowCount = 6

$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',62)))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',38)))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))

$form.Controls.Add($main)

# Compact header
$pHeader = New-Object Windows.Forms.TableLayoutPanel
$pHeader.Dock='Fill'
$pHeader.AutoSize=$true
$pHeader.ColumnCount=4
$pHeader.RowCount=1

$pHeader.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pHeader.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
$pHeader.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pHeader.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))

$lblHeader=New-Object Windows.Forms.Label
$lblHeader.Text='Forest Domain Controllers:'
$lblHeader.AutoSize=$true
$lblHeader.Anchor='Left'
$pHeader.Controls.Add($lblHeader,0,0)

$lblHeaderInfo=New-Object Windows.Forms.Label
$lblHeaderInfo.Text='Select one DC directly in the list below.'
$lblHeaderInfo.AutoSize=$true
$lblHeaderInfo.Anchor='Left'
$pHeader.Controls.Add($lblHeaderInfo,1,0)

$btnRefreshConnectorState=New-Object Windows.Forms.Button
$btnRefreshConnectorState.Text='Refresh CyberArk State'
$btnRefreshConnectorState.Width=135
$pHeader.Controls.Add($btnRefreshConnectorState,2,0)

$btnRefreshAll=New-Object Windows.Forms.Button
$btnRefreshAll.Text='Refresh All'
$btnRefreshAll.Width=90
$pHeader.Controls.Add($btnRefreshAll,3,0)

$main.Controls.Add($pHeader,0,0)

# Actions.
$pActions = New-Object Windows.Forms.TableLayoutPanel
$pActions.Dock='Fill'
$pActions.AutoSize=$true
$pActions.ColumnCount=5
$pActions.RowCount=1

$pActions.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pActions.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
$pActions.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pActions.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pActions.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))

$lblFilter=New-Object Windows.Forms.Label
$lblFilter.Text='Filter DCs:'
$lblFilter.AutoSize=$true
$lblFilter.Anchor='Left'
$pActions.Controls.Add($lblFilter,0,0)

$txtFilter=New-Object Windows.Forms.TextBox
$txtFilter.Dock='Fill'
$pActions.Controls.Add($txtFilter,1,0)

$btnTest=New-Object Windows.Forms.Button
$btnTest.Text='Test Connector'
$btnTest.Width=100
$pActions.Controls.Add($btnTest,2,0)

$btnPorts=New-Object Windows.Forms.Button
$btnPorts.Text='Test DC Ports'
$btnPorts.Width=100
$pActions.Controls.Add($btnPorts,3,0)

$btnReArm=New-Object Windows.Forms.Button
$btnReArm.Text='Re-Arm Connector'
$btnReArm.Width=115
$pActions.Controls.Add($btnReArm,4,0)

$main.Controls.Add($pActions,0,1)

# DC list.
$listDC = New-Object Windows.Forms.ListView
$listDC.Dock='Fill'
$listDC.View='Details'
$listDC.FullRowSelect=$true
$listDC.GridLines=$true
$listDC.HideSelection=$false

[void]$listDC.Columns.Add('Domain',170)
[void]$listDC.Columns.Add('DC FQDN',225)
[void]$listDC.Columns.Add('IPv4',95)
[void]$listDC.Columns.Add('Site',110)
[void]$listDC.Columns.Add('GC',45)
[void]$listDC.Columns.Add('CyberArk Service',120)
[void]$listDC.Columns.Add('State',70)
[void]$listDC.Columns.Add('ProxyHost Present',105)
[void]$listDC.Columns.Add('ProxyHost Path',320)

$main.Controls.Add($listDC,0,2)

$lblSelected=New-Object Windows.Forms.Label
$lblSelected.AutoSize=$true
$lblSelected.Text='Select one Domain Controller to test or re-arm its CyberArk Connector.'
$main.Controls.Add($lblSelected,0,3)

# Log.
$txtLog=New-Object Windows.Forms.TextBox
$txtLog.Dock='Fill'
$txtLog.Multiline=$true
$txtLog.ReadOnly=$true
$txtLog.ScrollBars='Vertical'
$txtLog.Font=New-Object Drawing.Font('Consolas',8.5)
$script:txtLog=$txtLog

$main.Controls.Add($txtLog,0,4)

# Status.
$statusStrip=New-Object Windows.Forms.StatusStrip

$statusMain=New-Object Windows.Forms.ToolStripStatusLabel
$statusMain.Spring=$true
$statusMain.Text='Ready'
$script:statusMain=$statusMain
[void]$statusStrip.Items.Add($statusMain)

$statusLog=New-Object Windows.Forms.ToolStripStatusLabel
$statusLog.Text="Log: $([IO.Path]::GetFileName($script:LogFile))"
[void]$statusStrip.Items.Add($statusLog)

$main.Controls.Add($statusStrip,0,5)

# ==============================================================================
# GUI DATA HELPERS
# ==============================================================================
function Refresh-DCGrid {
    param([string]$Filter='')

    $rows = @(
        $script:DCInventory |
        Where-Object {
            [string]::IsNullOrWhiteSpace($Filter) -or
            $_.Domain.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.DCFqdn.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.IPv4.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.Site.IndexOf($Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0
        }
    )

    $script:DisplayedDCs=$rows

    $listDC.BeginUpdate()

    try{
        $listDC.Items.Clear()

        foreach($row in $rows){
            $item = New-Object Windows.Forms.ListViewItem($row.Domain)
            [void]$item.SubItems.Add($row.DCFqdn)
            [void]$item.SubItems.Add($row.IPv4)
            [void]$item.SubItems.Add($row.Site)
            [void]$item.SubItems.Add([string]$row.GlobalCatalog)
            [void]$item.SubItems.Add([string]$row.ConnectorService)
            [void]$item.SubItems.Add([string]$row.ConnectorState)
            [void]$item.SubItems.Add([string]$row.ProxyHostPresent)
            [void]$item.SubItems.Add([string]$row.ProxyHostPath)
            $item.Tag=$row

            [void]$listDC.Items.Add($item)
        }
    }
    finally{
        $listDC.EndUpdate()
    }

    Set-AppStatus "Displayed $($rows.Count) writable forest DC(s)."
}

function Get-SelectedDC {
    if($listDC.SelectedItems.Count -ne 1){
        throw 'Select exactly one Domain Controller.'
    }

    return $listDC.SelectedItems[0].Tag
}

function Clear-ConnectorDisplay {
    $txtService.Clear()
    $txtState.Clear()
    $txtPath.Clear()
    $txtRemote.Clear()
}

# ==============================================================================
# EVENTS
# ==============================================================================
$listDC.Add_SelectedIndexChanged({
    if($listDC.SelectedItems.Count -eq 1){
        $dc=$listDC.SelectedItems[0].Tag

        $lblSelected.Text="Selected DC: $($dc.DCFqdn) | Domain: $($dc.Domain) | Site: $($dc.Site)"

        # Live validation on selection.
        Set-AppStatus "Checking CyberArk Connector on '$($dc.DCFqdn)'..."
        [void](Update-DCConnectorState -DCRecord $dc)
        Refresh-DCGrid -Filter $txtFilter.Text

        # Restore selection after grid refresh.
        foreach($item in $listDC.Items){
            if($item.Tag.DCFqdn -eq $dc.DCFqdn){
                $item.Selected=$true
                $item.Focused=$true
                $item.EnsureVisible()
                break
            }
        }

        Set-AppStatus "CyberArk state refreshed for '$($dc.DCFqdn)'."
    }
})
$txtFilter.Add_TextChanged({
    Refresh-DCGrid -Filter $txtFilter.Text
})

$btnRefreshAll.Add_Click({
    try{
        Set-AppStatus 'Refreshing forest Domain Controllers...'
        $script:DCInventory=@(Get-ForestWritableDomainControllers)

        Set-AppStatus 'Testing CyberArk Connector state on all writable DCs...'
        Update-AllDCConnectorStates

        Refresh-DCGrid -Filter $txtFilter.Text
        Write-AppLog "Full DC + CyberArk inventory refreshed. WritableDCs=$($script:DCInventory.Count)." SUCCESS
        Set-AppStatus 'Full inventory refresh completed.'
    }
    catch{
        Show-AppMessage "Full refresh failed: $($_.Exception.Message)" Error
        Write-AppLog "Full refresh failed: $($_.Exception.Message)" ERROR
    }
})

$btnRefreshConnectorState.Add_Click({
    try{
        if($listDC.SelectedItems.Count -eq 1){
            $dc=Get-SelectedDC
            Set-AppStatus "Refreshing CyberArk state on '$($dc.DCFqdn)'..."
            [void](Update-DCConnectorState -DCRecord $dc)
        }else{
            Set-AppStatus 'Refreshing CyberArk state on all writable DCs...'
            Update-AllDCConnectorStates
        }

        Refresh-DCGrid -Filter $txtFilter.Text
        Set-AppStatus 'CyberArk state refresh completed.'
    }
    catch{
        Show-AppMessage "CyberArk state refresh failed: $($_.Exception.Message)" Error
        Write-AppLog "CyberArk state refresh failed: $($_.Exception.Message)" ERROR
    }
})

$btnPorts.Add_Click({
    try{
        $dc=Get-SelectedDC

        Set-AppStatus "Testing AD ports on '$($dc.DCFqdn)'..."

        $results=@(Test-DomainControllerPorts -DCFqdn $dc.DCFqdn)

        foreach($result in $results){
            Write-AppLog (
                "Connectivity {0} TCP/{1} => {2}" -f
                $result.Test,$result.Port,$result.Reachable
            ) $(if($result.Reachable){'SUCCESS'}else{'WARN'})
        }

        $lines = @(
            $results |
            ForEach-Object {
                "{0,-10} TCP/{1,-5} {2}" -f
                $_.Test,$_.Port,$_.Reachable
            }
        )

        $failed=@($results|Where-Object{-not $_.Reachable})

        if($failed.Count -gt 0){
            Show-AppMessage (
                "Selected DC has connectivity failures:`r`n`r`n" +
                ($lines -join [Environment]::NewLine)
            ) Warning
        }
        else{
            Show-AppMessage (
                "Selected DC connectivity passed:`r`n`r`n" +
                ($lines -join [Environment]::NewLine)
            ) Information
        }

        Set-AppStatus "DC port test completed for '$($dc.DCFqdn)'."
    }
    catch{
        Show-AppMessage "DC port test failed: $($_.Exception.Message)" Error
        Write-AppLog "DC port test failed: $($_.Exception.Message)" ERROR
    }
})

$btnTest.Add_Click({
    try{
        $dc=Get-SelectedDC

        Set-AppStatus "Testing CyberArk Connector on '$($dc.DCFqdn)'..."

        Test-RemoteManagement -ComputerName $dc.DCFqdn | Out-Null

        $state=Get-RemoteCyberArkConnectorState -ComputerName $dc.DCFqdn

        if(-not $state.ServiceFound){
                        throw "CyberArk Identity Connector service 'IdaptiveConnector' was not found on '$($dc.DCFqdn)'."
        }

                                
        Write-AppLog (
            "Remote connector validated. DC='{0}'; Service='{1}'; State='{2}'; Executable='{3}'; Exists={4}." -f
            $dc.DCFqdn,$state.ServiceName,$state.State,$state.ExecutablePath,$state.ExecutableExists
        ) SUCCESS

        if(-not $state.ExecutableExists){
            Show-AppMessage (
                "CyberArk service was found on '$($dc.DCFqdn)', but ProxyHost.exe was not found at:`r`n`r`n" +
                $state.ExecutablePath
            ) Warning
            return
        }

        Show-AppMessage (
            "CyberArk Connector validated.`r`n`r`n" +
            "DC: $($dc.DCFqdn)`r`n" +
            "Service: $($state.ServiceName)`r`n" +
            "State: $($state.State)`r`n" +
            "ProxyHost: $($state.ExecutablePath)`r`n" +
            "Path Exists: $($state.ExecutableExists)"
        ) Information

        Set-AppStatus "CyberArk Connector validated on '$($dc.DCFqdn)'."
    }
    catch{
        Show-AppMessage "Connector test failed: $($_.Exception.Message)" Error
        Write-AppLog "Connector test failed: $($_.Exception.Message)" ERROR
        Set-AppStatus 'Connector validation failed.'
    }
})

$btnReArm.Add_Click({
    try{
        $dc=Get-SelectedDC

        Set-AppStatus "Pre-validating CyberArk Connector on '$($dc.DCFqdn)'..."

        Test-RemoteManagement -ComputerName $dc.DCFqdn | Out-Null

        $state=Get-RemoteCyberArkConnectorState -ComputerName $dc.DCFqdn

        if(-not $state.ServiceFound){
            throw "CyberArk Identity Connector service 'IdaptiveConnector' was not found on '$($dc.DCFqdn)'."
        }

        if(-not $state.ExecutableExists){
            throw "CyberArk service exists on '$($dc.DCFqdn)', but ProxyHost.exe was not found at '$($state.ExecutablePath)'."
        }

        $ports=@(Test-DomainControllerPorts -DCFqdn $dc.DCFqdn)

        $requiredFailures=@(
            $ports |
            Where-Object {
                $_.Test -in @('Kerberos','LDAP','SMB') -and
                -not $_.Reachable
            }
        )

        if($requiredFailures.Count -gt 0){
            $failedText=(
                $requiredFailures |
                ForEach-Object {
                    "$($_.Test) TCP/$($_.Port)"
                }
            ) -join ', '

            throw "Required DC connectivity failed: $failedText."
        }

        $answer=[Windows.Forms.MessageBox]::Show(
            "Re-arm CyberArk Identity Connector on the selected Domain Controller?`r`n`r`n" +
            "DC: $($dc.DCFqdn)`r`n" +
            "Domain: $($dc.Domain)`r`n" +
            "Service: $($state.ServiceName)`r`n" +
            "Current State: $($state.State)`r`n" +
            "ProxyHost: $($state.ExecutablePath)`r`n`r`n" +
            "The service will be configured for Automatic startup, recovery actions will be refreshed, and the service will be restarted.`r`n`r`n" +
            "NO domain-controller secure-channel reset will be performed.",
            'Confirm CyberArk Connector Re-Arm',
            [Windows.Forms.MessageBoxButtons]::YesNo,
            [Windows.Forms.MessageBoxIcon]::Warning,
            [Windows.Forms.MessageBoxDefaultButton]::Button2
        )

        if($answer -ne [Windows.Forms.DialogResult]::Yes){
            Write-AppLog "Re-arm cancelled by operator for '$($dc.DCFqdn)'." WARN
            return
        }

        Set-AppStatus "Re-arming CyberArk Connector on '$($dc.DCFqdn)'..."

        $result=Invoke-RemoteCyberArkReArm -ComputerName $dc.DCFqdn

                                
        if(-not $result.Success){
            throw "CyberArk service did not return to a healthy Running state."
        }

        Write-AppLog (
            "CyberArk Connector re-arm SUCCESS. DC='{0}'; Service='{1}'; PreviousState='{2}'; FinalState='{3}'; PID={4}; ProxyHost='{5}'." -f
            $dc.DCFqdn,$result.ServiceName,$result.PreviousState,$result.FinalState,$result.ProcessId,$result.ExecutablePath
        ) SUCCESS

        [void](Update-DCConnectorState -DCRecord $dc -Quiet)
        Refresh-DCGrid -Filter $txtFilter.Text

        Show-AppMessage (
            "CyberArk Identity Connector re-armed successfully.`r`n`r`n" +
            "DC: $($dc.DCFqdn)`r`n" +
            "Service: $($result.ServiceName)`r`n" +
            "Final State: $($result.FinalState)`r`n" +
            "Process ID: $($result.ProcessId)`r`n" +
            "ProxyHost: $($result.ExecutablePath)"
        ) Information

        Set-AppStatus "CyberArk Connector re-arm completed on '$($dc.DCFqdn)'."
    }
    catch{
        Show-AppMessage "Connector re-arm failed: $($_.Exception.Message)" Error
        Write-AppLog "Connector re-arm failed: $($_.Exception.Message)" ERROR
        Set-AppStatus 'Connector re-arm failed.'
    }
})

# ==============================================================================
# MAIN
# ==============================================================================
try{
    Write-AppLog 'Starting CyberArk Identity Connector DC re-arm tool.' INFO
    Write-AppLog (
        "Management Computer: {0}; Domain: {1}" -f
        $env:COMPUTERNAME,$env:USERDNSDOMAIN
    ) INFO

    Write-AppLog (
        "Host PowerShell: {0}; OS: {1}" -f
        $PSVersionTable.PSVersion,[Environment]::OSVersion.VersionString
    ) INFO

    Set-AppStatus 'Discovering writable forest Domain Controllers...'

    $script:DCInventory=@(Get-ForestWritableDomainControllers)

    Write-AppLog "Discovered writable forest DCs: $($script:DCInventory.Count)." SUCCESS

    Set-AppStatus 'Testing CyberArk Connector presence on writable DCs...'
    Update-AllDCConnectorStates

    Refresh-DCGrid

    Set-AppStatus 'Select one Domain Controller to validate or re-arm its CyberArk Connector.'

    [void]$form.ShowDialog()
}
catch{
    Write-AppLog "Fatal startup error: $($_.Exception.Message)" ERROR

    [void][Windows.Forms.MessageBox]::Show(
        "Fatal startup error:`r`n$($_.Exception.Message)",
        $script:AppName,
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Error
    )
}
finally{
    Write-AppLog 'Closing CyberArk Identity Connector DC re-arm tool.' INFO
}
