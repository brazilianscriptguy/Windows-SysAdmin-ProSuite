<#
.SYNOPSIS
    Enterprise GUI tool for managing disabled and expired Active Directory user accounts.

.DESCRIPTION
    Windows PowerShell 5.1-compatible WinForms tool for Active Directory account operations:
    - Lists enabled accounts with expired AccountExpirationDate.
    - Disables selected expired accounts.
    - Lists disabled accounts outside the CN=Users container, excluding built-in accounts.
    - Removes selected disabled users from all direct group memberships using DN-safe logic.
    - Disables accounts from comma-separated input or a TXT file.
    - Exports disabled account reports to CSV.

    Refactor v2.1 focus:
    - PowerShell 5.1 compatibility.
    - StrictMode-safe object handling.
    - Safe scalar/array normalization for AD properties such as MemberOf.
    - No direct .Count assumptions on scalar AD-returned values.
    - Defensive WinForms event wrappers.
    - Clear logging to C:\Logs-TEMP.
    - Layout hardened with ClientSize and reduced ListView height so bottom buttons remain visible on PS 5.1/WinForms scaling.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    2026-04-28-v2.1.0-ENTERPRISE-PS51-LAYOUT-FIXED
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------- Assemblies First ----------------------------
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
} catch {
    Write-Error "Failed to load required .NET assemblies: $($_.Exception.Message)"
    exit 1
}

[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------- Optional Console Hide ----------------------------
try {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class ConsoleWindowManager {
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() {
        IntPtr handle = GetConsoleWindow();
        if (handle != IntPtr.Zero) { ShowWindow(handle, 0); }
    }
}
"@ -ErrorAction Stop
    [ConsoleWindowManager]::Hide()
} catch {
    # Non-fatal. GUI can run with console visible.
}

# ---------------------------- Logging ----------------------------
$Script:ScriptName = if ($MyInvocation.MyCommand.Name) {
    [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
} else {
    'Manage-Disabled-Expired-ADUserAccounts-v2'
}

$Script:LogDir  = 'C:\Logs-TEMP'
$Script:LogPath = Join-Path -Path $Script:LogDir -ChildPath ("{0}.log" -f $Script:ScriptName)

try {
    if (-not (Test-Path -LiteralPath $Script:LogDir)) {
        New-Item -Path $Script:LogDir -ItemType Directory -Force | Out-Null
    }
} catch {
    [void][System.Windows.Forms.MessageBox]::Show(
        "Failed to create log directory: $Script:LogDir`r`n$($_.Exception.Message)",
        'AD User Management',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    exit 1
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO','WARNING','ERROR','SUCCESS')][string]$Level = 'INFO'
    )

    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try {
        Add-Content -LiteralPath $Script:LogPath -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Logging must never crash the GUI.
    }
}

function Show-AppMessage {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Information','Warning','Error')][string]$Type = 'Information'
    )

    $icon = switch ($Type) {
        'Information' { [System.Windows.Forms.MessageBoxIcon]::Information }
        'Warning'     { [System.Windows.Forms.MessageBoxIcon]::Warning }
        'Error'       { [System.Windows.Forms.MessageBoxIcon]::Error }
    }

    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,
        'AD User Management',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $icon
    )

    $level = if ($Type -eq 'Error') { 'ERROR' } elseif ($Type -eq 'Warning') { 'WARNING' } else { 'INFO' }
    Write-Log -Message $Message.Replace("`r", ' ').Replace("`n", ' ') -Level $level
}

function Invoke-GuiSafe {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [string]$Context = 'GUI operation'
    )

    try {
        & $ScriptBlock
    } catch {
        $msg = "Unexpected GUI operation failure during: $Context`r`n$($_.Exception.Message)"
        Write-Log -Message $msg.Replace("`r", ' ').Replace("`n", ' ') -Level 'ERROR'
        Show-AppMessage -Message $msg -Type Error
    }
}

Write-Log -Message '==== Session started ====' -Level INFO
Write-Log -Message ("Script: {0}" -f $PSCommandPath) -Level INFO
Write-Log -Message ("LogPath: {0}" -f $Script:LogPath) -Level INFO

# ---------------------------- PS 5.1 Safe Object Helpers ----------------------------
function ConvertTo-SafeArray {
    param([AllowNull()]$InputObject)

    if ($null -eq $InputObject) { return @() }

    if ($InputObject -is [System.Array]) { return @($InputObject) }

    # Strings implement IEnumerable, but must be treated as scalar values.
    if ($InputObject -is [string]) { return @($InputObject) }

    # WinForms collections and AD collections are safe to enumerate once normalized.
    return @($InputObject)
}

function Get-SafeCount {
    param([AllowNull()]$InputObject)

    return @(ConvertTo-SafeArray -InputObject $InputObject).Count
}

function Test-HasItems {
    param([AllowNull()]$InputObject)
    return ((Get-SafeCount -InputObject $InputObject) -gt 0)
}

function Get-ListViewCheckedItemsSafe {
    param([Parameter(Mandatory = $true)][System.Windows.Forms.ListView]$ListView)

    $items = New-Object System.Collections.Generic.List[System.Windows.Forms.ListViewItem]
    foreach ($item in $ListView.Items) {
        if ($item.Checked) { [void]$items.Add($item) }
    }
    return @($items.ToArray())
}

function Set-StatusText {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Label]$Label,
        [Parameter(Mandatory = $true)][string]$Text
    )
    $Label.Text = $Text
    [System.Windows.Forms.Application]::DoEvents()
}

function Confirm-Action {
    param([Parameter(Mandatory = $true)][string]$Message)

    $result = [System.Windows.Forms.MessageBox]::Show(
        $Message,
        'Confirm operation',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )

    return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Get-DomainFqdnFromDistinguishedName {
    param([Parameter(Mandatory = $true)][string]$DistinguishedName)

    $matches = [regex]::Matches($DistinguishedName, '(?i)DC=([^,]+)')
    if ((Get-SafeCount -InputObject $matches) -eq 0) { return $null }

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($match in $matches) {
        [void]$parts.Add([string]$match.Groups[1].Value)
    }

    return ($parts.ToArray() -join '.')
}

function Normalize-AccountInput {
    param([AllowNull()][string[]]$Names)

    $normalized = New-Object System.Collections.Generic.List[string]
    foreach ($name in (ConvertTo-SafeArray -InputObject $Names)) {
        $value = [string]$name
        $value = $value.Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            [void]$normalized.Add($value)
        }
    }

    return @($normalized.ToArray() | Sort-Object -Unique)
}

# ---------------------------- Module Validation ----------------------------
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log -Message 'ActiveDirectory module loaded successfully.' -Level SUCCESS
} catch {
    Show-AppMessage -Message "Failed to load the ActiveDirectory module. Install RSAT / Active Directory module for Windows PowerShell 5.1.`r`n$($_.Exception.Message)" -Type Error
    exit 1
}

function Get-ForestDomainsSafe {
    try {
        $forest = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
        $domains = New-Object System.Collections.Generic.List[string]

        foreach ($domain in $forest.Domains) {
            if (-not [string]::IsNullOrWhiteSpace([string]$domain.Name)) {
                [void]$domains.Add([string]$domain.Name)
            }
        }

        return @($domains.ToArray() | Sort-Object)
    } catch {
        Write-Log -Message "Unable to enumerate forest domains: $($_.Exception.Message)" -Level ERROR
        return @()
    }
}

# ---------------------------- AD Query Functions ----------------------------
function Get-ExpiredAdUsers {
    param([Parameter(Mandatory = $true)][string]$DomainFqdn)

    $now = Get-Date
    $users = @(
        Get-ADUser -Server $DomainFqdn `
            -Filter { Enabled -eq $true -and AccountExpirationDate -lt $now } `
            -Properties SamAccountName,DisplayName,AccountExpirationDate,DistinguishedName `
            -ErrorAction Stop |
        Sort-Object SamAccountName
    )

    return @(ConvertTo-SafeArray -InputObject $users)
}

function Get-DisabledAdUsers {
    param([Parameter(Mandatory = $true)][string]$DomainFqdn)

    $exclude = @('Administrator','Guest','krbtgt','DefaultAccount','WDAGUtilityAccount')

    $users = @(
        Get-ADUser -Server $DomainFqdn `
            -Filter { Enabled -eq $false } `
            -Properties SamAccountName,DisplayName,DistinguishedName,whenChanged `
            -ErrorAction Stop |
        Where-Object {
            ($exclude -notcontains [string]$_.SamAccountName) -and
            ([string]$_.DistinguishedName -notmatch '(?i)^CN=[^,]+,CN=Users,')
        } |
        Sort-Object SamAccountName
    )

    return @(ConvertTo-SafeArray -InputObject $users)
}

function Add-UserToListView {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.ListView]$ListView,
        [Parameter(Mandatory = $true)]$User,
        [Parameter(Mandatory = $true)][ValidateSet('Expired','Disabled')][string]$Mode
    )

    $sam = [string]$User.SamAccountName
    if ([string]::IsNullOrWhiteSpace($sam)) { return }

    $item = New-Object System.Windows.Forms.ListViewItem($sam)

    $displayName = if ([string]::IsNullOrWhiteSpace([string]$User.DisplayName)) { 'N/A' } else { [string]$User.DisplayName }
    [void]$item.SubItems.Add($displayName)

    if ($Mode -eq 'Expired') {
        $value = 'N/A'
        if ($null -ne $User.AccountExpirationDate) {
            $value = ([DateTime]$User.AccountExpirationDate).ToString('yyyy-MM-dd HH:mm')
        }
        [void]$item.SubItems.Add($value)
    } else {
        $value = 'N/A'
        if ($null -ne $User.whenChanged) {
            $value = ([DateTime]$User.whenChanged).ToString('yyyy-MM-dd HH:mm')
        }
        [void]$item.SubItems.Add($value)
    }

    $item.Tag = [string]$User.DistinguishedName
    [void]$ListView.Items.Add($item)
}

function List-ExpiredAccounts {
    param(
        [Parameter(Mandatory = $true)][string]$DomainFqdn,
        [Parameter(Mandatory = $true)][System.Windows.Forms.ListView]$ListView,
        [Parameter(Mandatory = $true)][System.Windows.Forms.Label]$StatusLabel
    )

    $ListView.BeginUpdate()
    try {
        $ListView.Items.Clear()
        Set-StatusText -Label $StatusLabel -Text "Querying expired users on $DomainFqdn..."

        $users = Get-ExpiredAdUsers -DomainFqdn $DomainFqdn
        foreach ($user in (ConvertTo-SafeArray -InputObject $users)) {
            Add-UserToListView -ListView $ListView -User $user -Mode Expired
        }

        $count = Get-SafeCount -InputObject $users
        Set-StatusText -Label $StatusLabel -Text "Expired users listed: $count"
        Write-Log -Message "Listed expired users on ${DomainFqdn}: ${count}" -Level SUCCESS

        if ($count -eq 0) {
            Show-AppMessage -Message "No expired enabled accounts were found on ${DomainFqdn}." -Type Information
        }
    } finally {
        $ListView.EndUpdate()
    }
}

function List-DisabledAccounts {
    param(
        [Parameter(Mandatory = $true)][string]$DomainFqdn,
        [Parameter(Mandatory = $true)][System.Windows.Forms.ListView]$ListView,
        [Parameter(Mandatory = $true)][System.Windows.Forms.Label]$StatusLabel
    )

    $ListView.BeginUpdate()
    try {
        $ListView.Items.Clear()
        Set-StatusText -Label $StatusLabel -Text "Querying disabled users on $DomainFqdn..."

        $users = Get-DisabledAdUsers -DomainFqdn $DomainFqdn
        foreach ($user in (ConvertTo-SafeArray -InputObject $users)) {
            Add-UserToListView -ListView $ListView -User $user -Mode Disabled
        }

        $count = Get-SafeCount -InputObject $users
        Set-StatusText -Label $StatusLabel -Text "Disabled users listed: $count"
        Write-Log -Message "Listed disabled users on ${DomainFqdn}: ${count}" -Level SUCCESS

        if ($count -eq 0) {
            Show-AppMessage -Message "No disabled user accounts were found outside the CN=Users container on ${DomainFqdn}." -Type Information
        }
    } finally {
        $ListView.EndUpdate()
    }
}

# ---------------------------- AD Action Functions ----------------------------
function Disable-UserBySam {
    param(
        [Parameter(Mandatory = $true)][string]$SamAccountName,
        [Parameter(Mandatory = $true)][string]$DomainFqdn
    )

    try {
        $user = Get-ADUser -Identity $SamAccountName -Server $DomainFqdn -Properties DistinguishedName -ErrorAction Stop
        Disable-ADAccount -Identity ([string]$user.DistinguishedName) -Server $DomainFqdn -ErrorAction Stop
        Write-Log -Message "Disabled account '${SamAccountName}' on ${DomainFqdn}." -Level SUCCESS
        return $true
    } catch {
        Write-Log -Message "Failed to disable '${SamAccountName}' on ${DomainFqdn}: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Disable-ExpiredAccounts {
    param(
        [Parameter(Mandatory = $true)][string]$DomainFqdn,
        [Parameter(Mandatory = $true)][System.Windows.Forms.ListView]$ListView,
        [Parameter(Mandatory = $true)][System.Windows.Forms.Label]$StatusLabel
    )

    $checked = Get-ListViewCheckedItemsSafe -ListView $ListView
    $count = Get-SafeCount -InputObject $checked

    if ($count -eq 0) {
        Show-AppMessage -Message 'No expired accounts selected. Select at least one account to disable.' -Type Warning
        return
    }

    if (-not (Confirm-Action -Message "Disable ${count} selected expired account(s)?")) {
        Write-Log -Message 'Disable expired accounts operation cancelled by operator.' -Level WARNING
        return
    }

    $disabled = 0
    foreach ($row in (ConvertTo-SafeArray -InputObject $checked)) {
        $sam = [string]$row.Text
        if ([string]::IsNullOrWhiteSpace($sam)) { continue }
        Set-StatusText -Label $StatusLabel -Text "Disabling $sam..."
        if (Disable-UserBySam -SamAccountName $sam -DomainFqdn $DomainFqdn) { $disabled++ }
    }

    List-ExpiredAccounts -DomainFqdn $DomainFqdn -ListView $ListView -StatusLabel $StatusLabel
    Show-AppMessage -Message "Disable operation completed.`r`nDisabled: ${disabled} of ${count}`r`nLog file: $Script:LogPath" -Type Information
}

function Remove-UserFromGroupsCrossDomainSafe {
    param(
        [Parameter(Mandatory = $true)][string]$SamAccountName,
        [Parameter(Mandatory = $true)][string]$UserDomainFqdn
    )

    $result = [ordered]@{
        UserSamAccountName = $SamAccountName
        GroupsFound        = 0
        Removed            = 0
        Failed             = 0
        Skipped            = 0
    }

    try {
        $user = Get-ADUser -Identity $SamAccountName -Server $UserDomainFqdn -Properties MemberOf,DistinguishedName -ErrorAction Stop
    } catch {
        Write-Log -Message "Failed to retrieve user '${SamAccountName}' on ${UserDomainFqdn}: $($_.Exception.Message)" -Level ERROR
        $result.Failed++
        return [pscustomobject]$result
    }

    $userDn = [string]$user.DistinguishedName
    if ([string]::IsNullOrWhiteSpace($userDn)) {
        Write-Log -Message "User '${SamAccountName}' has empty DistinguishedName. Skipping." -Level ERROR
        $result.Failed++
        return [pscustomobject]$result
    }

    $memberOf = ConvertTo-SafeArray -InputObject $user.MemberOf
    $result.GroupsFound = Get-SafeCount -InputObject $memberOf

    if ($result.GroupsFound -eq 0) {
        Write-Log -Message "User '${SamAccountName}' has no direct removable group memberships." -Level INFO
        return [pscustomobject]$result
    }

    foreach ($groupDnObj in (ConvertTo-SafeArray -InputObject $memberOf)) {
        $groupDn = [string]$groupDnObj
        if ([string]::IsNullOrWhiteSpace($groupDn)) {
            $result.Skipped++
            continue
        }

        $groupDomain = Get-DomainFqdnFromDistinguishedName -DistinguishedName $groupDn
        if ([string]::IsNullOrWhiteSpace($groupDomain)) {
            Write-Log -Message "Could not resolve domain for group DN '${groupDn}'. User '${SamAccountName}' skipped for this group." -Level WARNING
            $result.Skipped++
            continue
        }

        try {
            Remove-ADGroupMember -Identity $groupDn -Members $userDn -Server $groupDomain -Confirm:$false -ErrorAction Stop
            Write-Log -Message "Removed '${SamAccountName}' from '${groupDn}' using Remove-ADGroupMember via ${groupDomain}." -Level SUCCESS
            $result.Removed++
            continue
        } catch {
            $adError = $_.Exception.Message
            Write-Log -Message "Remove-ADGroupMember failed for '${SamAccountName}' from '${groupDn}' via ${groupDomain}: ${adError}. Trying ADSI fallback." -Level WARNING
        }

        try {
            $entry = [ADSI]("LDAP://{0}" -f $groupDn)
            $members = ConvertTo-SafeArray -InputObject $entry.Properties['member']
            $hasMember = $false

            foreach ($member in (ConvertTo-SafeArray -InputObject $members)) {
                if ([string]$member -ieq $userDn) {
                    $hasMember = $true
                    break
                }
            }

            if (-not $hasMember) {
                Write-Log -Message "User '${SamAccountName}' was not present in '${groupDn}' during ADSI fallback. Already clean." -Level INFO
                $result.Skipped++
                continue
            }

            [void]$entry.Properties['member'].Remove($userDn)
            $entry.CommitChanges()
            Write-Log -Message "Removed '${SamAccountName}' from '${groupDn}' using ADSI fallback." -Level SUCCESS
            $result.Removed++
        } catch {
            Write-Log -Message "ADSI fallback failed for '${SamAccountName}' from '${groupDn}': $($_.Exception.Message)" -Level ERROR
            $result.Failed++
        }
    }

    return [pscustomobject]$result
}

function Remove-SelectedDisabledUsersFromGroups {
    param(
        [Parameter(Mandatory = $true)][string]$DomainFqdn,
        [Parameter(Mandatory = $true)][System.Windows.Forms.ListView]$ListView,
        [Parameter(Mandatory = $true)][System.Windows.Forms.ProgressBar]$ProgressBar,
        [Parameter(Mandatory = $true)][System.Windows.Forms.Label]$StatusLabel
    )

    $checked = Get-ListViewCheckedItemsSafe -ListView $ListView
    $count = Get-SafeCount -InputObject $checked

    if ($count -eq 0) {
        Show-AppMessage -Message 'No disabled accounts selected. Select at least one account to remove from groups.' -Type Warning
        return
    }

    if (-not (Confirm-Action -Message "Remove all direct group memberships from ${count} selected disabled account(s)?`r`nThis operation changes group membership in Active Directory.")) {
        Write-Log -Message 'Remove from groups operation cancelled by operator.' -Level WARNING
        return
    }

    $ProgressBar.Minimum = 0
    $ProgressBar.Maximum = [Math]::Max(1, $count)
    $ProgressBar.Value = 0
    $ProgressBar.Step = 1

    $totalRemoved = 0
    $totalFailed = 0
    $processed = 0

    foreach ($row in (ConvertTo-SafeArray -InputObject $checked)) {
        $processed++
        $sam = [string]$row.Text
        if ([string]::IsNullOrWhiteSpace($sam)) { continue }

        Set-StatusText -Label $StatusLabel -Text "Removing group memberships for $sam ($processed/$count)..."
        $operation = Remove-UserFromGroupsCrossDomainSafe -SamAccountName $sam -UserDomainFqdn $DomainFqdn
        $totalRemoved += [int]$operation.Removed
        $totalFailed  += [int]$operation.Failed

        $ProgressBar.Value = [Math]::Min($processed, $ProgressBar.Maximum)
        [System.Windows.Forms.Application]::DoEvents()
    }

    Set-StatusText -Label $StatusLabel -Text "Group cleanup completed. Users processed: ${processed}. Removed links: ${totalRemoved}. Failures: ${totalFailed}."
    List-DisabledAccounts -DomainFqdn $DomainFqdn -ListView $ListView -StatusLabel $StatusLabel

    Show-AppMessage -Message "Group cleanup completed.`r`nUsers processed: ${processed}`r`nMemberships removed: ${totalRemoved}`r`nFailures: ${totalFailed}`r`nLog file: $Script:LogPath" -Type Information
}

function Disable-UserAccountsFromInput {
    param(
        [Parameter(Mandatory = $true)][string[]]$AccountNames,
        [Parameter(Mandatory = $true)][string]$DomainFqdn
    )

    $names = Normalize-AccountInput -Names $AccountNames
    $count = Get-SafeCount -InputObject $names

    if ($count -eq 0) {
        Show-AppMessage -Message 'No valid account names were provided.' -Type Warning
        return
    }

    if (-not (Confirm-Action -Message "Disable ${count} account(s) on ${DomainFqdn}?")) {
        Write-Log -Message 'Manual/file disable operation cancelled by operator.' -Level WARNING
        return
    }

    $disabled = 0
    foreach ($name in (ConvertTo-SafeArray -InputObject $names)) {
        if (Disable-UserBySam -SamAccountName ([string]$name) -DomainFqdn $DomainFqdn) { $disabled++ }
    }

    Show-AppMessage -Message "Disable operation completed.`r`nDisabled: ${disabled} of ${count}`r`nLog file: $Script:LogPath" -Type Information
}

function Start-DisableUsersFromTextBox {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.TextBox]$TextBox,
        [Parameter(Mandatory = $true)][string]$DomainFqdn
    )

    $placeholder = 'Type a user account, comma-separated users, or a full .txt file path'
    $rawInput = [string]$TextBox.Text
    $rawInput = $rawInput.Trim()

    if ([string]::IsNullOrWhiteSpace($rawInput) -or $rawInput -eq $placeholder) {
        Show-AppMessage -Message 'Type one or more account names, comma-separated, or provide a full TXT file path.' -Type Warning
        return
    }

    $accounts = @()

    if ([System.IO.File]::Exists($rawInput)) {
        try {
            $accounts = @(Get-Content -LiteralPath $rawInput -ErrorAction Stop)
            Write-Log -Message "Loaded account list from file: ${rawInput}" -Level INFO
        } catch {
            Show-AppMessage -Message "Failed to read TXT file:`r`n${rawInput}`r`n$($_.Exception.Message)" -Type Error
            return
        }
    } else {
        $accounts = @($rawInput -split ',')
        Write-Log -Message 'Loaded account list from manual input.' -Level INFO
    }

    Disable-UserAccountsFromInput -AccountNames $accounts -DomainFqdn $DomainFqdn
}

function Export-DisabledAccountsReportCsv {
    param(
        [Parameter(Mandatory = $true)][string]$DomainFqdn,
        [Parameter(Mandatory = $true)][string]$OutputFolder
    )

    try {
        if (-not (Test-Path -LiteralPath $OutputFolder)) {
            New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
        }

        $users = Get-DisabledAdUsers -DomainFqdn $DomainFqdn

        $report = foreach ($user in (ConvertTo-SafeArray -InputObject $users)) {
            [pscustomobject]@{
                SamAccountName    = [string]$user.SamAccountName
                DisplayName       = [string]$user.DisplayName
                LastChanged       = if ($null -ne $user.whenChanged) { ([DateTime]$user.whenChanged).ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
                DistinguishedName = [string]$user.DistinguishedName
            }
        }

        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $safeDomain = $DomainFqdn.Replace('.', '-')
        $csvPath = Join-Path -Path $OutputFolder -ChildPath ("DisabledAccounts_{0}_{1}.csv" -f $safeDomain, $timestamp)

        @($report) | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-Log -Message "Disabled accounts report exported: ${csvPath}" -Level SUCCESS
        Show-AppMessage -Message "Disabled accounts report exported:`r`n${csvPath}" -Type Information
    } catch {
        Write-Log -Message "Failed to export disabled accounts report for ${DomainFqdn}: $($_.Exception.Message)" -Level ERROR
        Show-AppMessage -Message "Failed to export disabled accounts report:`r`n$($_.Exception.Message)" -Type Error
    }
}

# ---------------------------- GUI Construction ----------------------------
function New-StandardButton {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][int]$X,
        [Parameter(Mandatory = $true)][int]$Y,
        [int]$Width = 170,
        [int]$Height = 32
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Size = New-Object System.Drawing.Size($Width, $Height)
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    return $button
}

function New-UserListView {
    param(
        [Parameter(Mandatory = $true)][string[]]$Columns,
        [Parameter(Mandatory = $true)][int[]]$Widths,
        [Parameter(Mandatory = $true)][int]$X,
        [Parameter(Mandatory = $true)][int]$Y,
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height
    )

    $lv = New-Object System.Windows.Forms.ListView
    $lv.Size = New-Object System.Drawing.Size($Width, $Height)
    $lv.Location = New-Object System.Drawing.Point($X, $Y)
    $lv.View = [System.Windows.Forms.View]::Details
    $lv.CheckBoxes = $true
    $lv.FullRowSelect = $true
    $lv.GridLines = $true
    $lv.HideSelection = $false

    for ($i = 0; $i -lt $Columns.Count; $i++) {
        [void]$lv.Columns.Add($Columns[$i], $Widths[$i])
    }

    return $lv
}

function Set-AllListViewChecks {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.ListView]$ListView,
        [Parameter(Mandatory = $true)][bool]$Checked
    )

    $ListView.BeginUpdate()
    try {
        foreach ($item in $ListView.Items) {
            $item.Checked = $Checked
        }
    } finally {
        $ListView.EndUpdate()
    }
}

function Show-Gui {
    $domains = Get-ForestDomainsSafe
    if ((Get-SafeCount -InputObject $domains) -eq 0) {
        Show-AppMessage -Message 'No Active Directory domains were found in the current forest context.' -Type Error
        return
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'AD User Management'
    $form.ClientSize = New-Object System.Drawing.Size(690, 730)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
    $form.MaximizeBox = $false
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None

    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Size = New-Object System.Drawing.Size(650, 690)
    $tabControl.Location = New-Object System.Drawing.Point(15, 15)

    $tabExpired = New-Object System.Windows.Forms.TabPage
    $tabExpired.Text = 'Expired Users'

    $tabDisabled = New-Object System.Windows.Forms.TabPage
    $tabDisabled.Text = 'Disabled Users'

    $left = 15
    $top = 15
    $listWidth = 600
    $buttonWidth = 185
    $buttonHeight = 32
    $gap = 15
    $buttonTop = 55
    $listTop = 100
    $listHeight = 400

    # Expired tab controls
    $comboExpired = New-Object System.Windows.Forms.ComboBox
    $comboExpired.Size = New-Object System.Drawing.Size($listWidth, 25)
    $comboExpired.Location = New-Object System.Drawing.Point($left, $top)
    $comboExpired.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$comboExpired.Items.AddRange([object[]]$domains)
    $comboExpired.SelectedIndex = 0
    $tabExpired.Controls.Add($comboExpired)

    $btnListExpired = New-StandardButton -Text 'List Expired Users' -X $left -Y $buttonTop -Width $buttonWidth -Height $buttonHeight
    $btnDisableExpired = New-StandardButton -Text 'Disable Selected' -X ($left + $buttonWidth + $gap) -Y $buttonTop -Width $buttonWidth -Height $buttonHeight
    $btnSelectExpired = New-StandardButton -Text 'Select All' -X ($left + (($buttonWidth + $gap) * 2)) -Y $buttonTop -Width $buttonWidth -Height $buttonHeight
    $tabExpired.Controls.AddRange(@($btnListExpired, $btnDisableExpired, $btnSelectExpired))

    $lvExpired = New-UserListView -Columns @('SAM Account Name','Display Name','Expiration Date') -Widths @((160),(270),(160)) -X $left -Y $listTop -Width $listWidth -Height $listHeight
    $tabExpired.Controls.Add($lvExpired)

    $statusExpired = New-Object System.Windows.Forms.Label
    $statusExpired.BorderStyle = [System.Windows.Forms.BorderStyle]::Fixed3D
    $statusExpired.Size = New-Object System.Drawing.Size($listWidth, 24)
    $statusExpired.Location = New-Object System.Drawing.Point($left, ($listTop + $listHeight + 12))
    $statusExpired.Text = 'Ready.'
    $tabExpired.Controls.Add($statusExpired)

    # Disabled tab controls
    $comboDisabled = New-Object System.Windows.Forms.ComboBox
    $comboDisabled.Size = New-Object System.Drawing.Size($listWidth, 25)
    $comboDisabled.Location = New-Object System.Drawing.Point($left, $top)
    $comboDisabled.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$comboDisabled.Items.AddRange([object[]]$domains)
    $comboDisabled.SelectedIndex = 0
    $tabDisabled.Controls.Add($comboDisabled)

    $btnListDisabled = New-StandardButton -Text 'List Disabled Users' -X $left -Y $buttonTop -Width $buttonWidth -Height $buttonHeight
    $btnRemoveGroups = New-StandardButton -Text 'Remove from Groups' -X ($left + $buttonWidth + $gap) -Y $buttonTop -Width $buttonWidth -Height $buttonHeight
    $btnSelectDisabled = New-StandardButton -Text 'Select All' -X ($left + (($buttonWidth + $gap) * 2)) -Y $buttonTop -Width $buttonWidth -Height $buttonHeight
    $tabDisabled.Controls.AddRange(@($btnListDisabled, $btnRemoveGroups, $btnSelectDisabled))

    $lvDisabled = New-UserListView -Columns @('SAM Account Name','Display Name','Last Changed') -Widths @((160),(270),(160)) -X $left -Y $listTop -Width $listWidth -Height $listHeight
    $tabDisabled.Controls.Add($lvDisabled)

    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Size = New-Object System.Drawing.Size($listWidth, 20)
    $progress.Location = New-Object System.Drawing.Point($left, ($listTop + $listHeight + 10))
    $tabDisabled.Controls.Add($progress)

    $statusDisabled = New-Object System.Windows.Forms.Label
    $statusDisabled.BorderStyle = [System.Windows.Forms.BorderStyle]::Fixed3D
    $statusDisabled.Size = New-Object System.Drawing.Size($listWidth, 24)
    $statusDisabled.Location = New-Object System.Drawing.Point($left, ($progress.Bottom + 8))
    $statusDisabled.Text = 'Ready.'
    $tabDisabled.Controls.Add($statusDisabled)

    $placeholder = 'Type a user account, comma-separated users, or a full .txt file path'
    $inputBox = New-Object System.Windows.Forms.TextBox
    $inputBox.Size = New-Object System.Drawing.Size(400, 22)
    $inputBox.Location = New-Object System.Drawing.Point($left, ($statusDisabled.Bottom + 18))
    $inputBox.Text = $placeholder
    $inputBox.ForeColor = [System.Drawing.Color]::Gray
    $tabDisabled.Controls.Add($inputBox)

    $btnDisableInput = New-StandardButton -Text 'Disable Users' -X ($inputBox.Right + 15) -Y ($inputBox.Top - 5) -Width 185 -Height 32
    $tabDisabled.Controls.Add($btnDisableInput)

    $btnExport = New-StandardButton -Text 'Export to CSV' -X $btnDisableInput.Left -Y ($btnDisableInput.Bottom + 10) -Width 185 -Height 32
    $tabDisabled.Controls.Add($btnExport)

    # Events
    $inputBox.Add_GotFocus({
        Invoke-GuiSafe -Context 'InputBox GotFocus' -ScriptBlock {
            if ($inputBox.Text -eq $placeholder) {
                $inputBox.Text = ''
                $inputBox.ForeColor = [System.Drawing.Color]::Black
            }
        }
    })

    $inputBox.Add_LostFocus({
        Invoke-GuiSafe -Context 'InputBox LostFocus' -ScriptBlock {
            if ([string]::IsNullOrWhiteSpace($inputBox.Text)) {
                $inputBox.Text = $placeholder
                $inputBox.ForeColor = [System.Drawing.Color]::Gray
            }
        }
    })

    $btnListExpired.Add_Click({
        Invoke-GuiSafe -Context 'List expired users' -ScriptBlock {
            List-ExpiredAccounts -DomainFqdn ([string]$comboExpired.SelectedItem) -ListView $lvExpired -StatusLabel $statusExpired
        }
    })

    $btnDisableExpired.Add_Click({
        Invoke-GuiSafe -Context 'Disable selected expired users' -ScriptBlock {
            Disable-ExpiredAccounts -DomainFqdn ([string]$comboExpired.SelectedItem) -ListView $lvExpired -StatusLabel $statusExpired
        }
    })

    $btnSelectExpired.Add_Click({
        Invoke-GuiSafe -Context 'Select all expired users' -ScriptBlock {
            Set-AllListViewChecks -ListView $lvExpired -Checked $true
            Set-StatusText -Label $statusExpired -Text ("Selected expired users: {0}" -f (Get-SafeCount -InputObject (Get-ListViewCheckedItemsSafe -ListView $lvExpired)))
        }
    })

    $btnListDisabled.Add_Click({
        Invoke-GuiSafe -Context 'List disabled users' -ScriptBlock {
            List-DisabledAccounts -DomainFqdn ([string]$comboDisabled.SelectedItem) -ListView $lvDisabled -StatusLabel $statusDisabled
        }
    })

    $btnRemoveGroups.Add_Click({
        Invoke-GuiSafe -Context 'Remove selected disabled users from groups' -ScriptBlock {
            Remove-SelectedDisabledUsersFromGroups -DomainFqdn ([string]$comboDisabled.SelectedItem) -ListView $lvDisabled -ProgressBar $progress -StatusLabel $statusDisabled
        }
    })

    $btnSelectDisabled.Add_Click({
        Invoke-GuiSafe -Context 'Select all disabled users' -ScriptBlock {
            Set-AllListViewChecks -ListView $lvDisabled -Checked $true
            Set-StatusText -Label $statusDisabled -Text ("Selected disabled users: {0}" -f (Get-SafeCount -InputObject (Get-ListViewCheckedItemsSafe -ListView $lvDisabled)))
        }
    })

    $btnDisableInput.Add_Click({
        Invoke-GuiSafe -Context 'Disable users from text box' -ScriptBlock {
            Start-DisableUsersFromTextBox -TextBox $inputBox -DomainFqdn ([string]$comboDisabled.SelectedItem)
        }
    })

    $btnExport.Add_Click({
        Invoke-GuiSafe -Context 'Export disabled users CSV' -ScriptBlock {
            $documents = [Environment]::GetFolderPath('MyDocuments')
            Export-DisabledAccountsReportCsv -DomainFqdn ([string]$comboDisabled.SelectedItem) -OutputFolder $documents
        }
    })

    $form.Add_FormClosing({
        Write-Log -Message '==== Session ended ====' -Level INFO
    })

    [void]$tabControl.TabPages.Add($tabExpired)
    [void]$tabControl.TabPages.Add($tabDisabled)
    $form.Controls.Add($tabControl)

    [void][System.Windows.Forms.Application]::Run($form)
}

Show-Gui

# End of Script
