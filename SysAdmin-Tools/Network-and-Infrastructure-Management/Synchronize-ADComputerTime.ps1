<#
.SYNOPSIS
  Windows Time Configuration and Synchronization Tool v2.0.0 Enterprise Edition.

.DESCRIPTION
  Enterprise Windows Forms tool for auditing and configuring the local Windows Server
  time zone and Windows Time (W32Time) synchronization settings.

  The tool:
  - Supports Windows PowerShell 5.1 and Windows Server 2019
  - Hides the PowerShell console before GUI initialization
  - Audits current time zone, Windows Time service, source, configuration, and status
  - Enumerates native Windows time-zone IDs without parsing display strings
  - Supports domain hierarchy (NT5DS) as the recommended default for domain members
  - Supports explicit manual NTP peers when intentionally required
  - Uses Dry Run by default
  - Provides Preview before Commit
  - Requires local administrative privileges for configuration changes
  - Executes native tools with captured exit codes/stdout/stderr
  - Verifies effective time zone and W32Time configuration after changes
  - Does not mark ordinary domain members as reliable time sources
  - Produces timestamped audit logs in C:\Logs-TEMP

  IMPORTANT:
  The legacy script used $env:USERDNSDOMAIN as a "Local Domain Server" and configured it
  as a manual NTP peer. A DNS domain name is not a specific time server, and domain-joined
  Windows systems normally synchronize through the AD domain hierarchy (NT5DS).

  The legacy script also used /reliable:yes. That setting is not appropriate for ordinary
  member servers/workstations. This version uses domain hierarchy by default and does not
  advertise the local computer as a reliable time source.

.AUTHOR
  Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
  2026-08-14-v2.0.0-ENTERPRISE-EDITION

.REQUIREMENTS
  - Windows PowerShell 5.1
  - Windows Server 2019
  - Local administrative privileges for configuration changes
  - Windows Time (W32Time) service
#>

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [switch]$ShowConsole
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

try {
    if (-not $ShowConsole) {
        try {
            Add-Type -Name Win32ShowWindowAsync -Namespace ConsoleControl -MemberDefinition @"
[DllImport("user32.dll")]
public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
[DllImport("kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
"@
            $ptr = [ConsoleControl.Win32ShowWindowAsync]::GetConsoleWindow()
            if ($ptr -ne [IntPtr]::Zero) {
                [void][ConsoleControl.Win32ShowWindowAsync]::ShowWindowAsync($ptr, 0)
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

$script:ScriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:LogRoot = 'C:\Logs-TEMP'
$script:RunStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:LogFile = Join-Path $script:LogRoot "$($script:ScriptName)-$($script:RunStamp).log"
$script:txtRuntimeLog = $null
$script:statusMain = $null
$script:chkDryRun = $null
$script:CurrentAudit = $null

if (-not (Test-Path -LiteralPath $script:LogRoot)) {
    New-Item -ItemType Directory -Path $script:LogRoot -Force | Out-Null
}

function Write-AppLog {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','SUCCESS','WARN','ERROR')][string]$Level='INFO'
    )
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch { }
    if ($script:txtRuntimeLog -and -not $script:txtRuntimeLog.IsDisposed) {
        $script:txtRuntimeLog.AppendText($line + [Environment]::NewLine)
        $script:txtRuntimeLog.SelectionStart = $script:txtRuntimeLog.Text.Length
        $script:txtRuntimeLog.ScrollToCaret()
    } elseif ($ShowConsole) { Write-Host $line }
}

function Set-AppStatus {
    param([string]$Text)
    if ($script:statusMain -and -not $script:statusMain.IsDisposed) {
        $script:statusMain.Text = $Text
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Show-AppMessage {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('Information','Warning','Error')][string]$Type='Information'
    )
    $icon = [System.Windows.Forms.MessageBoxIcon]::$Type
    if ($Type -eq 'Error') { Write-AppLog $Message ERROR }
    elseif ($Type -eq 'Warning') { Write-AppLog $Message WARN }
    else { Write-AppLog $Message INFO }
    [void][System.Windows.Forms.MessageBox]::Show(
        $Message, $Type, [System.Windows.Forms.MessageBoxButtons]::OK, $icon
    )
}

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$ArgumentList
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = ($ArgumentList | ForEach-Object {
        if ($_ -match '\s') { '"' + ($_ -replace '"','\"') + '"' } else { $_ }
    }) -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut   = $stdout.Trim()
        StdErr   = $stderr.Trim()
        Command  = "$FilePath $($psi.Arguments)"
    }
}

function Invoke-W32tm {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    $result = Invoke-NativeCommand -FilePath "$env:SystemRoot\System32\w32tm.exe" -ArgumentList $Arguments
    Write-AppLog -Message ("Executed: {0}; ExitCode={1}" -f $result.Command, $result.ExitCode)
    if ($result.ExitCode -ne 0) {
        $detail = if ($result.StdErr) { $result.StdErr } else { $result.StdOut }
        throw "w32tm failed with exit code $($result.ExitCode). $detail"
    }
    return $result
}

function Get-ComputerDomainRole {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $roleMap = @{
            0='Standalone Workstation'; 1='Member Workstation'; 2='Standalone Server'
            3='Member Server'; 4='Backup Domain Controller'; 5='Primary Domain Controller'
        }
        return [pscustomobject]@{
            Domain = [string]$cs.Domain
            PartOfDomain = [bool]$cs.PartOfDomain
            DomainRoleNumber = [int]$cs.DomainRole
            DomainRole = $roleMap[[int]$cs.DomainRole]
        }
    } catch {
        return [pscustomobject]@{
            Domain='Unknown'; PartOfDomain=$false; DomainRoleNumber=-1; DomainRole='Unknown'
        }
    }
}

function Get-TimeAudit {
    $tz = [System.TimeZoneInfo]::Local
    $svc = Get-Service -Name W32Time -ErrorAction SilentlyContinue
    $role = Get-ComputerDomainRole

    $source = ''
    $status = ''
    $config = ''

    try {
        $r = Invoke-W32tm -Arguments @('/query','/source')
        $source = $r.StdOut
    } catch { $source = "ERROR: $($_.Exception.Message)" }

    try {
        $r = Invoke-W32tm -Arguments @('/query','/status')
        $status = $r.StdOut
    } catch { $status = "ERROR: $($_.Exception.Message)" }

    try {
        $r = Invoke-W32tm -Arguments @('/query','/configuration')
        $config = $r.StdOut
    } catch { $config = "ERROR: $($_.Exception.Message)" }

    $type = ''
    $ntpServer = ''
    try {
        $type = [string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' -Name Type -ErrorAction Stop).Type
    } catch { }
    try {
        $ntpServer = [string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' -Name NtpServer -ErrorAction Stop).NtpServer
    } catch { }

    return [pscustomobject]@{
        TimeZoneId       = [string]$tz.Id
        TimeZoneDisplay  = [string]$tz.DisplayName
        ServiceStatus    = if ($svc) { [string]$svc.Status } else { 'NOT INSTALLED' }
        ServiceStartType = if ($svc) { [string]$svc.StartType } else { 'N/A' }
        Source            = $source
        SyncType          = $type
        ManualPeerList    = $ntpServer
        Domain            = $role.Domain
        PartOfDomain      = $role.PartOfDomain
        DomainRole        = $role.DomainRole
        StatusText        = $status
        ConfigurationText = $config
    }
}

function Set-AuditDisplay {
    param([Parameter(Mandatory=$true)]$Audit)

    $txtCurrent.Text = @"
Computer          : $env:COMPUTERNAME
Domain            : $($Audit.Domain)
Domain Role       : $($Audit.DomainRole)
Domain Joined     : $($Audit.PartOfDomain)

Time Zone ID      : $($Audit.TimeZoneId)
Time Zone         : $($Audit.TimeZoneDisplay)

W32Time Status    : $($Audit.ServiceStatus)
W32Time StartType : $($Audit.ServiceStartType)
Sync Type         : $($Audit.SyncType)
Current Source    : $($Audit.Source)
Manual Peer List  : $($Audit.ManualPeerList)
"@

    $txtDetails.Text = "W32TM STATUS`r`n=============`r`n$($Audit.StatusText)`r`n`r`nW32TM CONFIGURATION`r`n=====================`r`n$($Audit.ConfigurationText)"
}

function Refresh-TimeAudit {
    try {
        Set-AppStatus 'Auditing Windows Time configuration...'
        $script:CurrentAudit = Get-TimeAudit
        Set-AuditDisplay -Audit $script:CurrentAudit
        Write-AppLog -Message ("Audit: TimeZone='{0}'; W32Time={1}; Type='{2}'; Source='{3}'; DomainRole='{4}'." -f
            $script:CurrentAudit.TimeZoneId, $script:CurrentAudit.ServiceStatus,
            $script:CurrentAudit.SyncType, ($script:CurrentAudit.Source -replace "`r|`n",' '),
            $script:CurrentAudit.DomainRole) -Level SUCCESS
        Set-AppStatus 'Audit completed.'
    } catch {
        Show-AppMessage -Message "Time audit failed: $($_.Exception.Message)" -Type Error
    }
}

function Get-SelectedTimeZoneId {
    if ($null -eq $comboTimeZone.SelectedItem) { return $null }
    return [string]$comboTimeZone.SelectedItem.Id
}

function Get-DesiredConfiguration {
    $tzId = Get-SelectedTimeZoneId
    if ([string]::IsNullOrWhiteSpace($tzId)) {
        throw 'Select a time zone.'
    }

    if ($radioDomain.Checked) {
        return [pscustomobject]@{
            TimeZoneId = $tzId
            Mode = 'Domain Hierarchy'
            SyncType = 'NT5DS'
            PeerList = ''
        }
    }

    $peer = $txtPeer.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($peer)) {
        throw 'Enter at least one manual NTP peer.'
    }

    return [pscustomobject]@{
        TimeZoneId = $tzId
        Mode = 'Manual NTP'
        SyncType = 'NTP'
        PeerList = $peer
    }
}

function Show-Preview {
    param([Parameter(Mandatory=$true)]$Desired)

    $mode = if ($script:chkDryRun.Checked) { 'DRY RUN' } else { 'COMMIT' }
    $before = $script:CurrentAudit
    $text = @"
Execution Mode : $mode

CURRENT
-------
Time Zone ID   : $($before.TimeZoneId)
Sync Type      : $($before.SyncType)
Source         : $($before.Source)
Manual Peers   : $($before.ManualPeerList)

REQUESTED
---------
Time Zone ID   : $($Desired.TimeZoneId)
Sync Mode      : $($Desired.Mode)
Sync Type      : $($Desired.SyncType)
Manual Peers   : $($Desired.PeerList)

Domain Role    : $($before.DomainRole)
Domain Joined  : $($before.PartOfDomain)
"@
    [void][System.Windows.Forms.MessageBox]::Show(
        $text, 'Windows Time Configuration Preview',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
}

function Set-TimeConfigurationControlled {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param([Parameter(Mandatory=$true)]$Desired)

    if (-not (Test-IsAdministrator)) {
        throw 'Local administrative privileges are required.'
    }

    if ($Desired.Mode -eq 'Domain Hierarchy' -and -not $script:CurrentAudit.PartOfDomain) {
        throw 'Domain Hierarchy (NT5DS) was selected, but this computer is not domain joined.'
    }

    $target = $env:COMPUTERNAME
    $action = "Set time zone '$($Desired.TimeZoneId)' and W32Time mode '$($Desired.Mode)'"

    if (-not $PSCmdlet.ShouldProcess($target, $action)) {
        return 'SKIPPED'
    }

    # Time zone: use the Windows API through tzutil and verify its exit code.
    $tzResult = Invoke-NativeCommand -FilePath "$env:SystemRoot\System32\tzutil.exe" `
        -ArgumentList @('/s', $Desired.TimeZoneId)
    Write-AppLog -Message ("Executed: {0}; ExitCode={1}" -f $tzResult.Command, $tzResult.ExitCode)
    if ($tzResult.ExitCode -ne 0) {
        throw "tzutil failed with exit code $($tzResult.ExitCode). $($tzResult.StdErr)"
    }

    $svc = Get-Service -Name W32Time -ErrorAction Stop
    if ($svc.StartType -eq 'Disabled') {
        Set-Service -Name W32Time -StartupType Automatic -ErrorAction Stop
        Write-AppLog -Message 'W32Time startup type changed from Disabled to Automatic.' -Level WARN
    }
    if ((Get-Service W32Time).Status -ne 'Running') {
        Start-Service W32Time -ErrorAction Stop
        (Get-Service W32Time).WaitForStatus('Running',[TimeSpan]::FromSeconds(30))
    }

    if ($Desired.Mode -eq 'Domain Hierarchy') {
        [void](Invoke-W32tm -Arguments @('/config','/syncfromflags:domhier','/update'))
        Write-AppLog -Message 'Configured W32Time to synchronize from the Active Directory domain hierarchy (NT5DS).' -Level SUCCESS
    } else {
        $peerArg = "/manualpeerlist:$($Desired.PeerList)"
        [void](Invoke-W32tm -Arguments @('/config',$peerArg,'/syncfromflags:manual','/update'))
        Write-AppLog -Message ("Configured manual NTP peer list: {0}" -f $Desired.PeerList) -Level SUCCESS
    }

    Restart-Service -Name W32Time -Force -ErrorAction Stop
    (Get-Service W32Time).WaitForStatus('Running',[TimeSpan]::FromSeconds(30))

    if ($Desired.Mode -eq 'Domain Hierarchy') {
        [void](Invoke-W32tm -Arguments @('/resync','/rediscover'))
    } else {
        [void](Invoke-W32tm -Arguments @('/resync'))
    }

    Start-Sleep -Seconds 2
    $after = Get-TimeAudit

    if ($after.TimeZoneId -ne $Desired.TimeZoneId) {
        throw "Post-change time-zone verification failed. Effective ID='$($after.TimeZoneId)'."
    }

    if ($Desired.Mode -eq 'Domain Hierarchy' -and $after.SyncType -ne 'NT5DS') {
        throw "Post-change W32Time verification failed. Expected Type=NT5DS; effective Type='$($after.SyncType)'."
    }

    if ($Desired.Mode -eq 'Manual NTP' -and $after.SyncType -ne 'NTP') {
        throw "Post-change W32Time verification failed. Expected Type=NTP; effective Type='$($after.SyncType)'."
    }

    Write-AppLog -Message ("Configuration verified: TimeZone='{0}'; Type='{1}'; Source='{2}'." -f
        $after.TimeZoneId, $after.SyncType, ($after.Source -replace "`r|`n",' ')) -Level SUCCESS

    return 'SUCCESS'
}

# =====================================================================================
# GUI
# =====================================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Windows Time Configuration and Synchronization - Enterprise Edition'
$form.Size = New-Object System.Drawing.Size(950, 790)
$form.MinimumSize = New-Object System.Drawing.Size(850, 700)
$form.StartPosition = 'CenterScreen'

$main = New-Object System.Windows.Forms.TableLayoutPanel
$main.Dock = 'Fill'
$main.Padding = New-Object System.Windows.Forms.Padding(10)
$main.ColumnCount = 1
$main.RowCount = 7
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',35)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',35)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',30)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$form.Controls.Add($main)

$configPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$configPanel.Dock = 'Fill'
$configPanel.AutoSize = $true
$configPanel.WrapContents = $true

$labelTZ = New-Object System.Windows.Forms.Label
$labelTZ.Text = 'Time Zone:'
$labelTZ.AutoSize = $true
$labelTZ.Margin = New-Object System.Windows.Forms.Padding(3,7,3,3)
$configPanel.Controls.Add($labelTZ)

$comboTimeZone = New-Object System.Windows.Forms.ComboBox
$comboTimeZone.Width = 480
$comboTimeZone.DropDownStyle = 'DropDownList'
$comboTimeZone.DisplayMember = 'Display'
$configPanel.Controls.Add($comboTimeZone)

$chkDryRun = New-Object System.Windows.Forms.CheckBox
$chkDryRun.Text = 'Dry Run'
$chkDryRun.Checked = $true
$chkDryRun.AutoSize = $true
$chkDryRun.Margin = New-Object System.Windows.Forms.Padding(20,6,3,3)
$script:chkDryRun = $chkDryRun
$configPanel.Controls.Add($chkDryRun)

$main.Controls.Add($configPanel,0,0)

$syncPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$syncPanel.Dock = 'Fill'
$syncPanel.AutoSize = $true
$syncPanel.WrapContents = $true

$radioDomain = New-Object System.Windows.Forms.RadioButton
$radioDomain.Text = 'Active Directory Domain Hierarchy (NT5DS)'
$radioDomain.Checked = $true
$radioDomain.AutoSize = $true
$syncPanel.Controls.Add($radioDomain)

$radioManual = New-Object System.Windows.Forms.RadioButton
$radioManual.Text = 'Manual NTP Peer(s)'
$radioManual.AutoSize = $true
$radioManual.Margin = New-Object System.Windows.Forms.Padding(20,3,3,3)
$syncPanel.Controls.Add($radioManual)

$txtPeer = New-Object System.Windows.Forms.TextBox
$txtPeer.Width = 300
$txtPeer.Enabled = $false
$syncPanel.Controls.Add($txtPeer)

$main.Controls.Add($syncPanel,0,1)

$txtCurrent = New-Object System.Windows.Forms.TextBox
$txtCurrent.Dock = 'Fill'
$txtCurrent.Multiline = $true
$txtCurrent.ReadOnly = $true
$txtCurrent.ScrollBars = 'Vertical'
$txtCurrent.Font = New-Object System.Drawing.Font('Consolas',9)
$main.Controls.Add($txtCurrent,0,2)

$buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$buttonPanel.Dock = 'Fill'
$buttonPanel.AutoSize = $true

$buttonAudit = New-Object System.Windows.Forms.Button
$buttonAudit.Text = 'Refresh Audit'
$buttonAudit.Width = 110
$buttonPanel.Controls.Add($buttonAudit)

$buttonPreview = New-Object System.Windows.Forms.Button
$buttonPreview.Text = 'Preview'
$buttonPreview.Width = 100
$buttonPanel.Controls.Add($buttonPreview)

$buttonApply = New-Object System.Windows.Forms.Button
$buttonApply.Text = 'Apply / Synchronize'
$buttonApply.Width = 140
$buttonPanel.Controls.Add($buttonApply)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Text = 'Close'
$buttonClose.Width = 100
$buttonPanel.Controls.Add($buttonClose)

$main.Controls.Add($buttonPanel,0,3)

$txtDetails = New-Object System.Windows.Forms.TextBox
$txtDetails.Dock = 'Fill'
$txtDetails.Multiline = $true
$txtDetails.ReadOnly = $true
$txtDetails.ScrollBars = 'Both'
$txtDetails.WordWrap = $false
$txtDetails.Font = New-Object System.Drawing.Font('Consolas',8.5)
$main.Controls.Add($txtDetails,0,4)

$txtRuntimeLog = New-Object System.Windows.Forms.TextBox
$txtRuntimeLog.Dock = 'Fill'
$txtRuntimeLog.Multiline = $true
$txtRuntimeLog.ReadOnly = $true
$txtRuntimeLog.ScrollBars = 'Vertical'
$txtRuntimeLog.Font = New-Object System.Drawing.Font('Consolas',8.5)
$script:txtRuntimeLog = $txtRuntimeLog
$main.Controls.Add($txtRuntimeLog,0,5)

$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusMain = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusMain.Spring = $true
$statusMain.TextAlign = 'MiddleLeft'
$statusMain.Text = 'Ready'
$script:statusMain = $statusMain
[void]$statusStrip.Items.Add($statusMain)

$statusMode = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusMode.Text = 'Mode: DRY RUN'
[void]$statusStrip.Items.Add($statusMode)
$main.Controls.Add($statusStrip,0,6)

# Time zones: retain objects, not formatted strings.
$zones = @(
    [System.TimeZoneInfo]::GetSystemTimeZones() | ForEach-Object {
        [pscustomobject]@{
            Id = $_.Id
            Display = "$($_.DisplayName) [$($_.Id)]"
        }
    }
)
foreach ($zone in $zones) { [void]$comboTimeZone.Items.Add($zone) }

$currentZoneId = [System.TimeZoneInfo]::Local.Id
for ($i=0; $i -lt $comboTimeZone.Items.Count; $i++) {
    if ($comboTimeZone.Items[$i].Id -eq $currentZoneId) {
        $comboTimeZone.SelectedIndex = $i
        break
    }
}

$radioDomain.Add_CheckedChanged({
    if ($radioDomain.Checked) { $txtPeer.Enabled = $false }
})
$radioManual.Add_CheckedChanged({
    if ($radioManual.Checked) { $txtPeer.Enabled = $true; $txtPeer.Focus() }
})
$chkDryRun.Add_CheckedChanged({
    $statusMode.Text = if ($chkDryRun.Checked) { 'Mode: DRY RUN' } else { 'Mode: COMMIT' }
})
$buttonAudit.Add_Click({ Refresh-TimeAudit })
$buttonPreview.Add_Click({
    try {
        $desired = Get-DesiredConfiguration
        Show-Preview -Desired $desired
    } catch {
        Show-AppMessage -Message $_.Exception.Message -Type Warning
    }
})
$buttonApply.Add_Click({
    try {
        $desired = Get-DesiredConfiguration
        Show-Preview -Desired $desired

        if ($chkDryRun.Checked) {
            Write-AppLog -Message ("DRY RUN: TimeZone='{0}'; Mode='{1}'; PeerList='{2}'. No changes made." -f
                $desired.TimeZoneId, $desired.Mode, $desired.PeerList)
            Show-AppMessage -Message 'Dry Run completed. No time configuration was changed.' -Type Information
            return
        }

        if (-not (Test-IsAdministrator)) {
            Show-AppMessage -Message 'Configuration changes require an elevated PowerShell session.' -Type Error
            return
        }

        if ($desired.Mode -eq 'Domain Hierarchy' -and -not $script:CurrentAudit.PartOfDomain) {
            Show-AppMessage -Message 'Domain Hierarchy cannot be selected because this computer is not domain joined.' -Type Error
            return
        }

        $warning = @"
COMMIT Windows Time configuration?

Time Zone: $($desired.TimeZoneId)
Synchronization: $($desired.Mode)
Manual Peers: $($desired.PeerList)

This changes the local server's time-zone/W32Time configuration and initiates synchronization.
"@
        $answer = [System.Windows.Forms.MessageBox]::Show(
            $warning, 'Confirm Windows Time Configuration',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2
        )
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            Write-AppLog -Message 'Commit cancelled by operator.' -Level WARN
            return
        }

        Set-AppStatus 'Applying and verifying Windows Time configuration...'
        $result = Set-TimeConfigurationControlled -Desired $desired -Confirm:$false
        Refresh-TimeAudit

        if ($result -eq 'SUCCESS') {
            [void][System.Windows.Forms.MessageBox]::Show(
                "Windows Time configuration was applied and verified.`r`n`r`nEffective source:`r`n$($script:CurrentAudit.Source)",
                'Configuration Verified',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
    } catch {
        Show-AppMessage -Message "Configuration failed: $($_.Exception.Message)" -Type Error
        Set-AppStatus 'Configuration failed.'
    }
})
$buttonClose.Add_Click({ $form.Close() })

try {
    Write-AppLog -Message "Starting $($script:ScriptName)."
    Write-AppLog -Message ("Host PowerShell: {0}; OS: {1}" -f
        $PSVersionTable.PSVersion, [Environment]::OSVersion.VersionString)

    if (-not (Test-IsAdministrator)) {
        Write-AppLog -Message 'Process is not elevated. Audit is available; configuration changes will be blocked.' -Level WARN
    }

    Refresh-TimeAudit
    [void]$form.ShowDialog()
} catch {
    Write-AppLog -Message "Fatal startup error: $($_.Exception.Message)" -Level ERROR
    [void][System.Windows.Forms.MessageBox]::Show(
        "Fatal startup error:`r`n$($_.Exception.Message)",
        'Windows Time Configuration and Synchronization',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
} finally {
    Write-AppLog -Message "Closing $($script:ScriptName)."
}

# End of script
