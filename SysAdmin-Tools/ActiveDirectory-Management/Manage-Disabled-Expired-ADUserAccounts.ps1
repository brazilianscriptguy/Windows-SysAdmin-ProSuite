<#
.SYNOPSIS
  Manage Disabled and Expired AD User Accounts v4.1.9 - Stable Enterprise Edition.

.DESCRIPTION
  Windows PowerShell 5.1 WinForms application for controlled management of
  disabled and expired Active Directory user accounts across the current forest.

  Implements:
  - Automatic forest-domain discovery at startup
  - Selection of the authoritative target domain for each operation
  - Discovery of enabled accounts whose AccountExpirationDate has expired
  - Manual selection and disabling of expired user accounts
  - Discovery of disabled accounts outside the default CN=Users container
  - Exclusion of built-in and protected default identities
  - DN-safe removal of direct group memberships, including cross-domain groups
  - Account disabling from direct input, comma-separated input, or TXT files
  - CSV export of disabled-account inventory
  - Move selected disabled accounts to an Inactive User Accounts OU while preserving the disabled date
  - Delete disabled accounts whose recorded disabled age reaches a configured threshold
  - Mandatory pre-deletion CSV evidence and live revalidation
  - Enterprise session logging with script-name-derived paths
  - GUI-safe exception handling and operation status reporting
  - Hidden-console bootstrap for GUI-first execution
  - Single-window enterprise console aligned with the inactive-computer cleanup tool
  - Sortable DataGridView columns
  - Domain-aware organizational-unit search dialog
  - Dedicated deletion-eligible disabled-account list

.AUTHOR
  Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
  2026-07-28-v4.1.9-STABLE-ENTERPRISE-EDITION

.REQUIREMENTS
  - Windows PowerShell 5.1
  - RSAT ActiveDirectory PowerShell module
  - Appropriate Active Directory read, disable, move, delete, and group-management permissions
  - Network and DNS connectivity to all selected forest domains

.NOTES
  Validate all destructive operations in a controlled organizational unit before
  production use.
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$OutputDirectory = 'C:\Logs-TEMP',

    # Internal bootstrap switch. Do not specify manually.
    [switch]$HiddenChild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =====================================================================================
# Hidden-console bootstrap
# =====================================================================================

if (-not $HiddenChild -and -not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
    try {
        $powerShellExe = Join-Path -Path $PSHOME -ChildPath 'powershell.exe'
        $quotedScriptPath = '"' + ($PSCommandPath -replace '"', '""') + '"'
        $quotedOutputPath = '"' + ($OutputDirectory -replace '"', '""') + '"'

        $argumentLine = @(
            '-NoLogo'
            '-NoProfile'
            '-NonInteractive'
            '-ExecutionPolicy Bypass'
            '-WindowStyle Hidden'
            '-File'
            $quotedScriptPath
            '-OutputDirectory'
            $quotedOutputPath
            '-HiddenChild'
        ) -join ' '

        Start-Process `
            -FilePath $powerShellExe `
            -ArgumentList $argumentLine `
            -WindowStyle Hidden `
            -ErrorAction Stop | Out-Null

        exit
    }
    catch {
        # Continue in the current process if hidden relaunch fails.
    }
}

# =====================================================================================
# Required assemblies
# =====================================================================================

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
}
catch {
    Write-Error "Failed to load required .NET assemblies: $($_.Exception.Message)"
    exit 1
}

[System.Windows.Forms.Application]::EnableVisualStyles()

# =====================================================================================
# Application metadata and paths
# =====================================================================================

$Script:AppName = 'Manage Disabled and Expired AD User Accounts'
$Script:AppVersion = '4.1.9'
$Script:SessionId = [guid]::NewGuid().ToString()
$Script:ScriptPath = $PSCommandPath

$Script:ScriptName = if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
    [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
}
else {
    'Manage-Disabled-Expired-ADUserAccounts'
}

$Script:LogDir = $OutputDirectory
$Script:LogPath = Join-Path -Path $Script:LogDir -ChildPath ("{0}.log" -f $Script:ScriptName)
$Script:EvidenceDirectory = Join-Path -Path $Script:LogDir -ChildPath ("{0}-evidence" -f $Script:ScriptName)
$Script:DeletionJournalPath = Join-Path -Path $Script:LogDir -ChildPath ("{0}-deletion-journal.csv" -f $Script:ScriptName)

try {
    if (-not (Test-Path -LiteralPath $Script:LogDir)) {
        New-Item -Path $Script:LogDir -ItemType Directory -Force | Out-Null
    }
}
catch {
    [void][System.Windows.Forms.MessageBox]::Show(
        "Failed to create log directory: $Script:LogDir`r`n$($_.Exception.Message)",
        $Script:AppName,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    exit 1
}

# =====================================================================================
# Logging and GUI-safe helpers
# =====================================================================================

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
        $Script:AppName,
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
Write-Log -Message (
    "Application={0} | Version={1} | SessionId={2} | Operator={3} | Host={4}" -f
    $Script:AppName,
    $Script:AppVersion,
    $Script:SessionId,
    [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
    $env:COMPUTERNAME
) -Level INFO
Write-Log -Message ("Script={0}" -f $Script:ScriptPath) -Level INFO
Write-Log -Message (
    "HostMode=HiddenConsole | ProcessId={0} | HiddenChild={1}" -f
    $PID,
    [bool]$HiddenChild
) -Level INFO
Write-Log -Message ("LogPath={0}" -f $Script:LogPath) -Level INFO

# =====================================================================================
# PowerShell 5.1-safe collection helpers
# =====================================================================================
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

# =====================================================================================
# Active Directory module initialization
# =====================================================================================
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

# =====================================================================================
# Active Directory query functions
# =====================================================================================
function Get-ExpiredAdUsers {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainFqdn
    )

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

function Get-DisabledTimestampInfo {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Info,

        [AllowNull()]
        [object]$WhenChanged
    )

    $timestamp = $null
    $source = 'Unavailable'

    if (-not [string]::IsNullOrWhiteSpace($Info)) {
        $match = [regex]::Match(
            $Info,
            '(?im)^\[AD-USER-LIFECYCLE\]\s*DisabledOn=(?<value>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:Z|[+\-]\d{2}:\d{2})?)\s*$'
        )

        if ($match.Success) {
            $parsed = [datetimeoffset]::MinValue
            if ([datetimeoffset]::TryParse($match.Groups['value'].Value, [ref]$parsed)) {
                $timestamp = $parsed.LocalDateTime
                $source = 'LifecycleMarker'
            }
        }
    }

    if ($null -eq $timestamp -and $null -ne $WhenChanged) {
        try {
            $candidateWhenChanged = [datetime]$WhenChanged

            if ($candidateWhenChanged -ne [datetime]::MinValue) {
                $timestamp = $candidateWhenChanged
                $source = 'whenChanged-fallback'
            }
        }
        catch {
            Write-Log -Message (
                "Unable to parse whenChanged value '{0}': {1}" -f
                [string]$WhenChanged,
                $_.Exception.Message
            ) -Level WARNING
        }
    }

    $ageDays = $null
    if ($null -ne $timestamp) {
        $ageDays = [math]::Max(0, [int][math]::Floor(((Get-Date) - $timestamp).TotalDays))
    }

    [pscustomobject]@{
        DisabledDate       = $timestamp
        DisabledAgeDays    = $ageDays
        DisabledDateSource = $source
    }
}

function Set-UserLifecycleDisabledMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DistinguishedName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainFqdn,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$DisabledOn
    )

    $user = Get-ADUser `
        -Identity $DistinguishedName `
        -Server $DomainFqdn `
        -Properties info `
        -ErrorAction Stop

    $existing = [string]$user.info
    $clean = [regex]::Replace(
        $existing,
        '(?im)^\[AD-USER-LIFECYCLE\]\s*DisabledOn=.*?(?:\r?\n|$)',
        ''
    ).Trim()

    $effectiveDisabledOn = Get-Date

    if ($null -ne $DisabledOn) {
        try {
            $candidateDisabledOn = [datetime]$DisabledOn

            if ($candidateDisabledOn -ne [datetime]::MinValue) {
                $effectiveDisabledOn = $candidateDisabledOn
            }
        }
        catch {
            throw "Unable to parse the supplied disabled date '$DisabledOn': $($_.Exception.Message)"
        }
    }

    $offset = [System.TimeZoneInfo]::Local.GetUtcOffset($effectiveDisabledOn)
    $disabledDateOffset = New-Object System.DateTimeOffset(
        $effectiveDisabledOn,
        $offset
    )

    $marker = '[AD-USER-LIFECYCLE] DisabledOn={0}' -f (
        $disabledDateOffset.ToString('yyyy-MM-ddTHH:mm:sszzz')
    )

    $newValue = if ([string]::IsNullOrWhiteSpace($clean)) {
        $marker
    }
    else {
        "{0}`r`n{1}" -f $clean, $marker
    }

    Set-ADUser `
        -Identity $DistinguishedName `
        -Server $DomainFqdn `
        -Replace @{ info = $newValue } `
        -ErrorAction Stop
}

function Get-DisabledAdUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainFqdn
    )

    $exclude = @(
        'Administrator'
        'Guest'
        'krbtgt'
        'DefaultAccount'
        'WDAGUtilityAccount'
    )

    $rawUsers = @(
        Get-ADUser `
            -Server $DomainFqdn `
            -Filter { Enabled -eq $false } `
            -Properties SamAccountName,DisplayName,DistinguishedName,whenChanged,info,ObjectGuid,ProtectedFromAccidentalDeletion `
            -ResultPageSize 500 `
            -ResultSetSize $null `
            -ErrorAction Stop |
        Where-Object {
            ($exclude -notcontains [string]$_.SamAccountName) -and
            ([string]$_.DistinguishedName -notmatch '(?i)^CN=[^,]+,CN=Users,')
        }
    )

    $users = foreach ($user in $rawUsers) {
        $disabledInfo = Get-DisabledTimestampInfo `
            -Info ([string]$user.info) `
            -WhenChanged $user.whenChanged

        [pscustomobject]@{
            Domain                          = $DomainFqdn
            SamAccountName                  = [string]$user.SamAccountName
            DisplayName                     = [string]$user.DisplayName
            DistinguishedName               = [string]$user.DistinguishedName
            ObjectGuid                      = [guid]$user.ObjectGuid
            WhenChanged                     = $user.whenChanged
            DisabledDate                    = $disabledInfo.DisabledDate
            DisabledAgeDays                 = $disabledInfo.DisabledAgeDays
            DisabledDateSource              = $disabledInfo.DisabledDateSource
            ProtectedFromAccidentalDeletion = [bool]$user.ProtectedFromAccidentalDeletion
        }
    }

    return @($users | Sort-Object SamAccountName)
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
        $disabledDate = 'N/A'
        if ($null -ne $User.DisabledDate) {
            $disabledDate = ([DateTime]$User.DisabledDate).ToString('yyyy-MM-dd HH:mm')
        }

        $disabledAge = if ($null -eq $User.DisabledAgeDays) {
            'N/A'
        }
        else {
            [string]$User.DisabledAgeDays
        }

        [void]$item.SubItems.Add($disabledDate)
        [void]$item.SubItems.Add($disabledAge)
        [void]$item.SubItems.Add([string]$User.DisabledDateSource)
        [void]$item.SubItems.Add([string]$User.DistinguishedName)
    }

    $item.Tag = $User
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

# =====================================================================================
# Active Directory action functions
# =====================================================================================
function Disable-UserBySam {
    param(
        [Parameter(Mandatory = $true)][string]$SamAccountName,
        [Parameter(Mandatory = $true)][string]$DomainFqdn
    )

    try {
        $user = Get-ADUser -Identity $SamAccountName -Server $DomainFqdn -Properties DistinguishedName -ErrorAction Stop
        Disable-ADAccount -Identity ([string]$user.DistinguishedName) -Server $DomainFqdn -ErrorAction Stop

        try {
            Set-UserLifecycleDisabledMarker `
                -DistinguishedName ([string]$user.DistinguishedName) `
                -DomainFqdn $DomainFqdn

            Write-Log -Message "Lifecycle disabled-date marker written for '${SamAccountName}' on ${DomainFqdn}." -Level SUCCESS
        }
        catch {
            Write-Log -Message "Account '${SamAccountName}' was disabled, but the lifecycle marker could not be written: $($_.Exception.Message)" -Level WARNING
        }

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
        $record = $row.Tag
        $sam = if ($null -ne $record -and $null -ne $record.PSObject.Properties['SamAccountName']) {
            [string]$record.SamAccountName
        }
        else {
            [string]$row.Text
        }

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
        $record = $row.Tag
        $sam = if ($null -ne $record -and $null -ne $record.PSObject.Properties['SamAccountName']) {
            [string]$record.SamAccountName
        }
        else {
            [string]$row.Text
        }

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

function Get-InactiveUsersOu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DomainFqdn
    )

    $domain = Get-ADDomain -Identity $DomainFqdn -Server $DomainFqdn -ErrorAction Stop
    $preferredDn = 'OU=Inactive User Accounts,{0}' -f $domain.DistinguishedName

    try {
        return Get-ADOrganizationalUnit `
            -Identity $preferredDn `
            -Server $DomainFqdn `
            -Properties DistinguishedName `
            -ErrorAction Stop
    }
    catch {
        $matches = @(
            Get-ADOrganizationalUnit `
                -Server $DomainFqdn `
                -Filter "Name -eq 'Inactive User Accounts'" `
                -Properties DistinguishedName `
                -ErrorAction Stop
        )

        if ($matches.Count -eq 1) {
            return $matches[0]
        }

        if ($matches.Count -gt 1) {
            throw "Multiple OUs named 'Inactive User Accounts' exist in ${DomainFqdn}. Specify an exact distinguished name."
        }

        return $null
    }
}

function Resolve-InactiveUsersOuDn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DomainFqdn,
        [AllowNull()][string]$RequestedOuDn
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedOuDn)) {
        $ou = Get-ADOrganizationalUnit `
            -Identity $RequestedOuDn.Trim() `
            -Server $DomainFqdn `
            -ErrorAction Stop

        return [string]$ou.DistinguishedName
    }

    $resolved = Get-InactiveUsersOu -DomainFqdn $DomainFqdn
    if ($null -eq $resolved) {
        throw (
            "The OU 'Inactive User Accounts' was not found in domain '{0}'. " +
            "Use 'Search OU...' to select the destination organizational unit before moving accounts."
        ) -f $DomainFqdn
    }

    return [string]$resolved.DistinguishedName
}

function Move-SelectedDisabledUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DomainFqdn,
        [Parameter(Mandatory = $true)][System.Windows.Forms.ListView]$ListView,
        [AllowNull()][string]$TargetOuDn,
        [Parameter(Mandatory = $true)][System.Windows.Forms.ProgressBar]$ProgressBar,
        [Parameter(Mandatory = $true)][System.Windows.Forms.Label]$StatusLabel
    )

    $checked = @(Get-ListViewCheckedItemsSafe -ListView $ListView)
    if ($checked.Count -eq 0) {
        Show-AppMessage -Message 'No disabled accounts selected.' -Type Warning
        return
    }

    if ([string]::IsNullOrWhiteSpace($TargetOuDn)) {
        Write-Log -Message (
            "Inactive OU field is empty. Attempting domain-aware automatic resolution. Domain={0}" -f
            $DomainFqdn
        ) -Level INFO
    }

    $resolvedOuDn = Resolve-InactiveUsersOuDn `
        -DomainFqdn $DomainFqdn `
        -RequestedOuDn $TargetOuDn

    if (-not (Confirm-Action -Message (
        "Move {0} selected disabled account(s) to:`r`n{1}?" -f
        $checked.Count,
        $resolvedOuDn
    ))) {
        Write-Log -Message 'Move disabled users operation cancelled by operator.' -Level WARNING
        return
    }

    $ProgressBar.Minimum = 0
    $ProgressBar.Maximum = [math]::Max(1, $checked.Count)
    $ProgressBar.Value = 0

    $moved = 0
    $skipped = 0
    $failed = 0
    $index = 0

    foreach ($item in $checked) {
        $index++
        $record = $item.Tag

        if ($null -eq $record -or $null -eq $record.PSObject.Properties['DistinguishedName']) {
            $failed++
            continue
        }

        $sam = [string]$record.SamAccountName
        Set-StatusText -Label $StatusLabel -Text (
            "Moving {0} ({1}/{2})..." -f $sam, $index, $checked.Count
        )

        try {
            $live = Get-ADUser `
                -Identity ([guid]$record.ObjectGuid) `
                -Server $DomainFqdn `
                -Properties Enabled,DistinguishedName,whenChanged,info `
                -ErrorAction Stop

            if ([bool]$live.Enabled) {
                $skipped++
                Write-Log -Message "Move skipped. Account '${sam}' is enabled during live validation." -Level WARNING
                continue
            }

            if ([string]$live.DistinguishedName -like "*,$resolvedOuDn") {
                $skipped++
                Write-Log -Message "Move skipped. Account '${sam}' is already in '${resolvedOuDn}'." -Level INFO
                continue
            }

            Move-ADObject `
                -Identity ([string]$live.DistinguishedName) `
                -TargetPath $resolvedOuDn `
                -Server $DomainFqdn `
                -Confirm:$false `
                -ErrorAction Stop

            $moved++
            Write-Log -Message "Disabled account '${sam}' moved to '${resolvedOuDn}'." -Level SUCCESS
        }
        catch {
            $failed++
            Write-Log -Message "Failed to move '${sam}' to '${resolvedOuDn}': $($_.Exception.Message)" -Level ERROR
        }
        finally {
            $ProgressBar.Value = [math]::Min($index, $ProgressBar.Maximum)
            [System.Windows.Forms.Application]::DoEvents()
        }
    }

    List-DisabledAccounts `
        -DomainFqdn $DomainFqdn `
        -ListView $ListView `
        -StatusLabel $StatusLabel

    Show-AppMessage -Message (
        "Move operation completed.`r`nMoved: {0}`r`nSkipped: {1}`r`nFailed: {2}" -f
        $moved,
        $skipped,
        $failed
    ) -Type Information
}

function Export-DisabledDeletionEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Records,
        [Parameter(Mandatory = $true)][int]$ThresholdDays
    )

    if (-not (Test-Path -LiteralPath $Script:EvidenceDirectory)) {
        New-Item -Path $Script:EvidenceDirectory -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path = Join-Path `
        -Path $Script:EvidenceDirectory `
        -ChildPath ("{0}-predelete-{1}-{2}.csv" -f $Script:ScriptName, $timestamp, $Script:SessionId.Substring(0,8))

    $Records |
        Select-Object Domain,SamAccountName,DisplayName,DisabledDate,DisabledAgeDays,DisabledDateSource,ProtectedFromAccidentalDeletion,ObjectGuid,DistinguishedName,
            @{Name='ThresholdDays';Expression={$ThresholdDays}},
            @{Name='EvidenceCreatedAt';Expression={(Get-Date).ToString('o')}} |
        Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

    Write-Log -Message "Pre-deletion evidence exported. Path=${path} | Records=$($Records.Count) | ThresholdDays=${ThresholdDays}" -Level SUCCESS
    return $path
}

function Write-DisabledDeletionJournal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)][string]$Result,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][int]$ThresholdDays
    )

    $entry = [pscustomobject]@{
        Timestamp          = (Get-Date).ToString('o')
        SessionId          = $Script:SessionId
        Operator           = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        Domain             = [string]$Record.Domain
        SamAccountName     = [string]$Record.SamAccountName
        ObjectGuid         = [string]$Record.ObjectGuid
        DistinguishedName  = [string]$Record.DistinguishedName
        DisabledDate       = if ($null -ne $Record.DisabledDate) { ([datetime]$Record.DisabledDate).ToString('o') } else { '' }
        DisabledAgeDays    = $Record.DisabledAgeDays
        DisabledDateSource = [string]$Record.DisabledDateSource
        ThresholdDays      = $ThresholdDays
        Result             = $Result
        Message            = $Message
    }

    $exists = Test-Path -LiteralPath $Script:DeletionJournalPath
    $entry | Export-Csv `
        -LiteralPath $Script:DeletionJournalPath `
        -NoTypeInformation `
        -Encoding UTF8 `
        -Append:$exists `
        -ErrorAction Stop
}

function Remove-SelectedAgedDisabledUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DomainFqdn,
        [Parameter(Mandatory = $true)][System.Windows.Forms.ListView]$ListView,
        [Parameter(Mandatory = $true)][int]$DisabledAgeDays,
        [Parameter(Mandatory = $true)][System.Windows.Forms.ProgressBar]$ProgressBar,
        [Parameter(Mandatory = $true)][System.Windows.Forms.Label]$StatusLabel
    )

    $checked = @(Get-ListViewCheckedItemsSafe -ListView $ListView)
    if ($checked.Count -eq 0) {
        Show-AppMessage -Message 'No disabled accounts selected for deletion.' -Type Warning
        return
    }

    $eligible = New-Object System.Collections.Generic.List[object]
    foreach ($item in $checked) {
        $record = $item.Tag
        if (
            $null -ne $record -and
            $null -ne $record.DisabledAgeDays -and
            [int]$record.DisabledAgeDays -ge $DisabledAgeDays
        ) {
            $eligible.Add($record)
        }
    }

    if ($eligible.Count -eq 0) {
        Show-AppMessage -Message (
            "None of the selected disabled accounts has a disabled age of at least {0} days." -f
            $DisabledAgeDays
        ) -Type Warning
        return
    }

    $evidencePath = Export-DisabledDeletionEvidence `
        -Records $eligible.ToArray() `
        -ThresholdDays $DisabledAgeDays

    $fallbackCount = @($eligible | Where-Object { $_.DisabledDateSource -eq 'whenChanged-fallback' }).Count

    $warning = @"
Delete $($eligible.Count) disabled AD user account(s)?

Required disabled age: $DisabledAgeDays days
Evidence: $evidencePath
Fallback-date records: $fallbackCount

IMPORTANT:
'whenChanged' is not an authoritative disable timestamp. It changes whenever the
object is modified. Accounts disabled by this tool receive a lifecycle marker,
which is used preferentially.

Deletion is permanent and cannot be undone.
"@

    if (-not (Confirm-Action -Message $warning)) {
        Write-Log -Message 'Disabled user deletion cancelled by operator.' -Level WARNING
        return
    }

    $ProgressBar.Minimum = 0
    $ProgressBar.Maximum = [math]::Max(1, $eligible.Count)
    $ProgressBar.Value = 0

    $deleted = 0
    $skipped = 0
    $failed = 0
    $index = 0

    foreach ($record in $eligible) {
        $index++
        $sam = [string]$record.SamAccountName
        Set-StatusText -Label $StatusLabel -Text (
            "Live validating and deleting {0} ({1}/{2})..." -f
            $sam,
            $index,
            $eligible.Count
        )

        try {
            $live = Get-ADUser `
                -Identity ([guid]$record.ObjectGuid) `
                -Server $DomainFqdn `
                -Properties Enabled,whenChanged,info,ProtectedFromAccidentalDeletion,DistinguishedName,ObjectGuid `
                -ErrorAction Stop

            if ([bool]$live.Enabled) {
                $skipped++
                Write-DisabledDeletionJournal -Record $record -Result 'SKIPPED' -Message 'Account is enabled during live validation.' -ThresholdDays $DisabledAgeDays
                Write-Log -Message "Deletion skipped. Account '${sam}' is enabled." -Level WARNING
                continue
            }

            $liveAge = Get-DisabledTimestampInfo `
                -Info ([string]$live.info) `
                -WhenChanged $live.whenChanged

            if ($null -eq $liveAge.DisabledAgeDays -or [int]$liveAge.DisabledAgeDays -lt $DisabledAgeDays) {
                $skipped++
                Write-DisabledDeletionJournal -Record $record -Result 'SKIPPED' -Message "Live disabled age is below ${DisabledAgeDays} days." -ThresholdDays $DisabledAgeDays
                Write-Log -Message "Deletion skipped. '${sam}' no longer meets the disabled-age threshold." -Level WARNING
                continue
            }

            if ([bool]$live.ProtectedFromAccidentalDeletion) {
                $skipped++
                Write-DisabledDeletionJournal -Record $record -Result 'SKIPPED' -Message 'ProtectedFromAccidentalDeletion is enabled.' -ThresholdDays $DisabledAgeDays
                Write-Log -Message "Deletion skipped. '${sam}' is protected from accidental deletion." -Level WARNING
                continue
            }

            Remove-ADUser `
                -Identity ([string]$live.DistinguishedName) `
                -Server $DomainFqdn `
                -Confirm:$false `
                -ErrorAction Stop

            $deleted++
            Write-DisabledDeletionJournal -Record $record -Result 'DELETED' -Message 'Account deleted successfully.' -ThresholdDays $DisabledAgeDays
            Write-Log -Message "Disabled account '${sam}' deleted successfully. DisabledAgeDays=$($liveAge.DisabledAgeDays)." -Level SUCCESS
        }
        catch {
            $failed++
            Write-DisabledDeletionJournal -Record $record -Result 'FAILED' -Message $_.Exception.Message -ThresholdDays $DisabledAgeDays
            Write-Log -Message "Failed to delete disabled account '${sam}': $($_.Exception.Message)" -Level ERROR
        }
        finally {
            $ProgressBar.Value = [math]::Min($index, $ProgressBar.Maximum)
            [System.Windows.Forms.Application]::DoEvents()
        }
    }

    List-DisabledAccounts `
        -DomainFqdn $DomainFqdn `
        -ListView $ListView `
        -StatusLabel $StatusLabel

    Show-AppMessage -Message (
        "Deletion batch completed.`r`nEligible: {0}`r`nDeleted: {1}`r`nSkipped: {2}`r`nFailed: {3}`r`nEvidence: {4}" -f
        $eligible.Count,
        $deleted,
        $skipped,
        $failed,
        $evidencePath
    ) -Type Information
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
                DisabledDate       = if ($null -ne $user.DisabledDate) { ([DateTime]$user.DisabledDate).ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
                DisabledAgeDays    = $user.DisabledAgeDays
                DisabledDateSource = [string]$user.DisabledDateSource
                Protected          = [bool]$user.ProtectedFromAccidentalDeletion
                ObjectGuid         = [string]$user.ObjectGuid
                DistinguishedName  = [string]$user.DistinguishedName
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


# =====================================================================================
# Unified DataGridView helpers
# =====================================================================================

function New-EnterpriseDataGridView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable[]]$Columns
    )

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AllowUserToOrderColumns = $true
    $grid.AllowUserToResizeColumns = $true
    $grid.AllowUserToResizeRows = $false
    $grid.AutoGenerateColumns = $false
    $grid.AutoSizeRowsMode = [System.Windows.Forms.DataGridViewAutoSizeRowsMode]::None
    $grid.BackgroundColor = [System.Drawing.SystemColors]::Window
    $grid.BorderStyle = [System.Windows.Forms.BorderStyle]::Fixed3D
    $grid.ColumnHeadersHeightSizeMode = [System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::AutoSize
    $grid.EditMode = [System.Windows.Forms.DataGridViewEditMode]::EditOnEnter
    $grid.MultiSelect = $false
    $grid.ReadOnly = $false
    $grid.RowHeadersVisible = $false
    $grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $grid.StandardTab = $true

    $selectColumn = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $selectColumn.Name = 'Selected'
    $selectColumn.HeaderText = ''
    $selectColumn.Width = 34
    $selectColumn.MinimumWidth = 34
    $selectColumn.ReadOnly = $false
    $selectColumn.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
    $selectColumn.TrueValue = $true
    $selectColumn.FalseValue = $false
    $selectColumn.IndeterminateValue = $false
    $selectColumn.ThreeState = $false
    $selectColumn.DefaultCellStyle.NullValue = $false
    [void]$grid.Columns.Add($selectColumn)

    foreach ($definition in $Columns) {
        $column = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $column.Name = [string]$definition.Name
        $column.HeaderText = [string]$definition.Header
        $column.Width = [int]$definition.Width
        $column.MinimumWidth = 60
        $column.ReadOnly = $true
        $column.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Automatic

        if ([string]$definition.Name -eq 'DistinguishedName') {
            $column.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
            $column.FillWeight = 100
        }
        else {
            $column.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::None
        }

        [void]$grid.Columns.Add($column)
    }

    $grid.Add_CurrentCellDirtyStateChanged({
        param($sender, $eventArgs)

        $dataGridView = $sender -as [System.Windows.Forms.DataGridView]
        if ($null -ne $dataGridView -and $dataGridView.IsCurrentCellDirty) {
            [void]$dataGridView.CommitEdit(
                [System.Windows.Forms.DataGridViewDataErrorContexts]::Commit
            )
        }
    })

    $grid.Add_DataError({
        param($sender, $eventArgs)

        $eventArgs.ThrowException = $false

        Write-Log -Message (
            "DataGridView data error suppressed. Row={0} | Column={1} | Context={2} | Error={3}" -f
            $eventArgs.RowIndex,
            $eventArgs.ColumnIndex,
            $eventArgs.Context,
            $eventArgs.Exception.Message
        ) -Level WARNING
    })

    return $grid
}

function Add-RecordToGrid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.DataGridView]$Grid,
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)][ValidateSet('Expired','Disabled')][string]$Mode
    )

    $index = $Grid.Rows.Add()
    $row = $Grid.Rows[$index]
    $row.Tag = $Record
    $row.Cells['Selected'].Value = [bool]$false

    $row.Cells['Domain'].Value = [string]$Record.Domain
    $row.Cells['SamAccountName'].Value = [string]$Record.SamAccountName
    $row.Cells['DisplayName'].Value = [string]$Record.DisplayName

    if ($Mode -eq 'Expired') {
        $row.Cells['AccountExpirationDate'].Value = if ($null -ne $Record.AccountExpirationDate) {
            ([datetime]$Record.AccountExpirationDate).ToString('yyyy-MM-dd HH:mm')
        }
        else {
            ''
        }

        $row.Cells['DistinguishedName'].Value = [string]$Record.DistinguishedName
    }
    else {
        $row.Cells['DisabledDate'].Value = if ($null -ne $Record.DisabledDate) {
            ([datetime]$Record.DisabledDate).ToString('yyyy-MM-dd HH:mm')
        }
        else {
            ''
        }

        $row.Cells['DisabledAgeDays'].Value = if ($null -ne $Record.DisabledAgeDays) {
            [int]$Record.DisabledAgeDays
        }
        else {
            $null
        }

        $row.Cells['DisabledDateSource'].Value = [string]$Record.DisabledDateSource
        $row.Cells['Protected'].Value = [bool]$Record.ProtectedFromAccidentalDeletion
        $row.Cells['DistinguishedName'].Value = [string]$Record.DistinguishedName
    }
}

function Get-CheckedGridRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.DataGridView]$Grid
    )

    if ($Grid.IsCurrentCellDirty) {
        [void]$Grid.CommitEdit(
            [System.Windows.Forms.DataGridViewDataErrorContexts]::Commit
        )
    }

    [void]$Grid.EndEdit()

    $records = New-Object System.Collections.Generic.List[object]

    foreach ($row in $Grid.Rows) {
        if (
            -not $row.IsNewRow -and
            $null -ne $row.Tag -and
            [bool]$row.Cells['Selected'].Value
        ) {
            $records.Add($row.Tag)
        }
    }

    return $records.ToArray()
}

function Set-AllGridChecks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.DataGridView]$Grid,
        [Parameter(Mandatory = $true)][bool]$Checked
    )

    foreach ($row in $Grid.Rows) {
        if (-not $row.IsNewRow) {
            $row.Cells['Selected'].Value = $Checked
        }
    }

    $Grid.Refresh()
}

function Update-GridSelectionSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.ToolStripStatusLabel]$StatusLabel,
        [Parameter(Mandatory = $true)][System.Windows.Forms.DataGridView]$ExpiredGrid,
        [Parameter(Mandatory = $true)][System.Windows.Forms.DataGridView]$DisabledGrid,
        [Parameter(Mandatory = $true)][System.Windows.Forms.DataGridView]$EligibleGrid
    )

    $expiredSelected = @(Get-CheckedGridRecords -Grid $ExpiredGrid).Count
    $disabledSelected = @(Get-CheckedGridRecords -Grid $DisabledGrid).Count
    $eligibleSelected = @(Get-CheckedGridRecords -Grid $EligibleGrid).Count

    $StatusLabel.Text = (
        "Expired: {0} ({1} selected) | Disabled: {2} ({3} selected) | Eligible: {4} ({5} selected)" -f
        $ExpiredGrid.Rows.Count,
        $expiredSelected,
        $DisabledGrid.Rows.Count,
        $disabledSelected,
        $EligibleGrid.Rows.Count,
        $eligibleSelected
    )
}

function Get-DomainOrganizationalUnits {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DomainFqdn
    )

    return @(
        Get-ADOrganizationalUnit `
            -Server $DomainFqdn `
            -Filter * `
            -Properties DistinguishedName,Name `
            -ResultPageSize 500 `
            -ResultSetSize $null `
            -ErrorAction Stop |
        Sort-Object DistinguishedName
    )
}

function Show-OrganizationalUnitSearchDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DomainFqdn,
        [AllowNull()][string]$CurrentOuDn
    )

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Select Organizational Unit - $DomainFqdn"
    $dialog.ClientSize = New-Object System.Drawing.Size(860, 560)
    $dialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dialog.MinimizeBox = $false
    $dialog.MaximizeBox = $true
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable

    $label = New-Object System.Windows.Forms.Label
    $label.Text = 'Search by OU name or distinguished name:'
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(12, 15)

    $searchBox = New-Object System.Windows.Forms.TextBox
    $searchBox.Location = New-Object System.Drawing.Point(12, 38)
    $searchBox.Size = New-Object System.Drawing.Size(830, 24)

    $list = New-Object System.Windows.Forms.ListBox
    $list.Location = New-Object System.Drawing.Point(12, 72)
    $list.Size = New-Object System.Drawing.Size(830, 420)
    $list.Anchor = (
        [System.Windows.Forms.AnchorStyles]::Top -bor
        [System.Windows.Forms.AnchorStyles]::Bottom -bor
        [System.Windows.Forms.AnchorStyles]::Left -bor
        [System.Windows.Forms.AnchorStyles]::Right
    )

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Select OU'
    $ok.Location = New-Object System.Drawing.Point(642, 510)
    $ok.Size = New-Object System.Drawing.Size(95, 32)
    $ok.Anchor = (
        [System.Windows.Forms.AnchorStyles]::Bottom -bor
        [System.Windows.Forms.AnchorStyles]::Right
    )

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.Location = New-Object System.Drawing.Point(747, 510)
    $cancel.Size = New-Object System.Drawing.Size(95, 32)
    $cancel.Anchor = (
        [System.Windows.Forms.AnchorStyles]::Bottom -bor
        [System.Windows.Forms.AnchorStyles]::Right
    )

    $dialog.Controls.AddRange(@($label,$searchBox,$list,$ok,$cancel))

    $allOus = @(Get-DomainOrganizationalUnits -DomainFqdn $DomainFqdn)

    $refresh = {
        $needle = $searchBox.Text.Trim()
        $list.BeginUpdate()
        try {
            $list.Items.Clear()

            $filtered = if ([string]::IsNullOrWhiteSpace($needle)) {
                $allOus
            }
            else {
                @(
                    $allOus | Where-Object {
                        [string]$_.Name -like "*$needle*" -or
                        [string]$_.DistinguishedName -like "*$needle*"
                    }
                )
            }

            foreach ($ou in $filtered) {
                [void]$list.Items.Add([string]$ou.DistinguishedName)
            }

            if (
                -not [string]::IsNullOrWhiteSpace($CurrentOuDn) -and
                $list.Items.Contains($CurrentOuDn)
            ) {
                $list.SelectedItem = $CurrentOuDn
            }
        }
        finally {
            $list.EndUpdate()
        }
    }

    $searchBox.Add_TextChanged($refresh)
    $dialog.Add_Shown($refresh)

    $selectedDn = $null

    $ok.Add_Click({
        if ($null -eq $list.SelectedItem) {
            Show-AppMessage -Message 'Select an organizational unit.' -Type Warning
            return
        }

        $script:OuDialogSelection = [string]$list.SelectedItem
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dialog.Close()
    })

    $list.Add_DoubleClick({
        if ($null -ne $list.SelectedItem) {
            $script:OuDialogSelection = [string]$list.SelectedItem
            $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dialog.Close()
        }
    })

    $cancel.Add_Click({
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dialog.Close()
    })

    $script:OuDialogSelection = $null
    $result = $dialog.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $selectedDn = $script:OuDialogSelection
    }

    Remove-Variable -Name OuDialogSelection -Scope Script -ErrorAction SilentlyContinue
    $dialog.Dispose()

    return $selectedDn
}

function Refresh-UnifiedUserGrids {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DomainFqdn,
        [Parameter(Mandatory = $true)][int]$DisabledAgeDays,
        [Parameter(Mandatory = $true)][System.Windows.Forms.DataGridView]$ExpiredGrid,
        [Parameter(Mandatory = $true)][System.Windows.Forms.DataGridView]$DisabledGrid,
        [Parameter(Mandatory = $true)][System.Windows.Forms.DataGridView]$EligibleGrid,
        [Parameter(Mandatory = $true)][System.Windows.Forms.ToolStripStatusLabel]$StatusLabel,
        [Parameter(Mandatory = $true)][System.Windows.Forms.ToolStripProgressBar]$ProgressBar
    )

    $ProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $StatusLabel.Text = "Scanning expired and disabled accounts in $DomainFqdn..."
    Write-Log -Message "Unified scan started. Domain=${DomainFqdn} | ThresholdDays=${DisabledAgeDays}" -Level INFO
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $ExpiredGrid.Rows.Clear()
        $DisabledGrid.Rows.Clear()
        $EligibleGrid.Rows.Clear()

        $expiredUsers = @(Get-ExpiredAdUsers -DomainFqdn $DomainFqdn)
        foreach ($user in $expiredUsers) {
            Add-RecordToGrid -Grid $ExpiredGrid -Record $user -Mode Expired
        }

        $disabledUsers = @(Get-DisabledAdUsers -DomainFqdn $DomainFqdn)
        foreach ($user in $disabledUsers) {
            Add-RecordToGrid -Grid $DisabledGrid -Record $user -Mode Disabled

            if (
                $null -ne $user.DisabledAgeDays -and
                [int]$user.DisabledAgeDays -ge $DisabledAgeDays
            ) {
                Add-RecordToGrid -Grid $EligibleGrid -Record $user -Mode Disabled
            }
        }

        Set-AllGridChecks -Grid $ExpiredGrid -Checked $false
        Set-AllGridChecks -Grid $DisabledGrid -Checked $false
        Set-AllGridChecks -Grid $EligibleGrid -Checked $false

        $unavailableDisabledDates = @(
            $disabledUsers | Where-Object {
                $null -eq $_.DisabledDate -or
                $_.DisabledDateSource -eq 'Unavailable'
            }
        ).Count

        Write-Log -Message (
            "Unified scan completed. Domain={0} | Expired={1} | Disabled={2} | EligibleDisabled={3} | DisabledDateUnavailable={4} | ThresholdDays={5}" -f
            $DomainFqdn,
            $expiredUsers.Count,
            $disabledUsers.Count,
            $EligibleGrid.Rows.Count,
            $unavailableDisabledDates,
            $DisabledAgeDays
        ) -Level SUCCESS
    }
    finally {
        $ProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
        $ProgressBar.Value = 0
        Update-GridSelectionSummary `
            -StatusLabel $StatusLabel `
            -ExpiredGrid $ExpiredGrid `
            -DisabledGrid $DisabledGrid `
            -EligibleGrid $EligibleGrid
    }
}

function Disable-ExpiredGridRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DomainFqdn,
        [Parameter(Mandatory = $true)][System.Windows.Forms.DataGridView]$Grid
    )

    $records = @(Get-CheckedGridRecords -Grid $Grid)
    if ($records.Count -eq 0) {
        Show-AppMessage -Message 'No expired accounts selected.' -Type Warning
        return
    }

    if (-not (Confirm-Action -Message "Disable $($records.Count) selected expired account(s)?")) {
        return
    }

    $success = 0
    $failed = 0

    foreach ($record in $records) {
        if (Disable-UserBySam -SamAccountName ([string]$record.SamAccountName) -DomainFqdn $DomainFqdn) {
            $success++
        }
        else {
            $failed++
        }
    }

    Show-AppMessage -Message (
        "Expired-account operation completed.`r`nDisabled: {0}`r`nFailed: {1}" -f
        $success,
        $failed
    ) -Type Information
}

function Remove-DisabledGridRecordsFromGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DomainFqdn,
        [Parameter(Mandatory = $true)][System.Windows.Forms.DataGridView]$Grid,
        [Parameter(Mandatory = $true)][System.Windows.Forms.ToolStripProgressBar]$ProgressBar
    )

    $records = @(Get-CheckedGridRecords -Grid $Grid)
    if ($records.Count -eq 0) {
        Show-AppMessage -Message 'No disabled accounts selected.' -Type Warning
        return
    }

    if (-not (Confirm-Action -Message "Remove all direct group memberships from $($records.Count) selected disabled account(s)?")) {
        return
    }

    $ProgressBar.Maximum = [math]::Max(1, $records.Count)
    $ProgressBar.Value = 0

    $removed = 0
    $failed = 0
    $index = 0

    foreach ($record in $records) {
        $index++
        $result = Remove-UserFromGroupsCrossDomainSafe `
            -SamAccountName ([string]$record.SamAccountName) `
            -UserDomainFqdn $DomainFqdn

        $removed += [int]$result.Removed
        $failed += [int]$result.Failed
        $ProgressBar.Value = [math]::Min($index, $ProgressBar.Maximum)
        [System.Windows.Forms.Application]::DoEvents()
    }

    Show-AppMessage -Message (
        "Group cleanup completed.`r`nUsers processed: {0}`r`nMemberships removed: {1}`r`nFailures: {2}" -f
        $records.Count,
        $removed,
        $failed
    ) -Type Information
}

function Move-DisabledGridRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainFqdn,

        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.DataGridView]$Grid,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$TargetOuDn,

        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.ToolStripProgressBar]$ProgressBar
    )

    $records = @(Get-CheckedGridRecords -Grid $Grid)
    if ($records.Count -eq 0) {
        Show-AppMessage -Message 'No disabled accounts selected.' -Type Warning
        return
    }

    $resolvedOuDn = Resolve-InactiveUsersOuDn `
        -DomainFqdn $DomainFqdn `
        -RequestedOuDn $TargetOuDn

    if (-not (Confirm-Action -Message (
        "Move {0} selected disabled account(s) to:`r`n{1}?" -f
        $records.Count,
        $resolvedOuDn
    ))) {
        return
    }

    $ProgressBar.Maximum = [math]::Max(1, $records.Count)
    $ProgressBar.Value = 0

    $moved = 0
    $skipped = 0
    $failed = 0
    $index = 0

    foreach ($record in $records) {
        $index++

        try {
            $live = Get-ADUser `
                -Identity ([guid]$record.ObjectGuid) `
                -Server $DomainFqdn `
                -Properties Enabled,DistinguishedName `
                -ErrorAction Stop

            if ([bool]$live.Enabled) {
                $skipped++
                continue
            }

            if ([string]$live.DistinguishedName -like "*,$resolvedOuDn") {
                $skipped++
                continue
            }

            # Moving an AD object updates whenChanged. If the account still relies on
            # whenChanged-fallback, persist the currently calculated disabled date before
            # Move-ADObject so its lifecycle age is not reset by the OU movement.
            $markerInfo = Get-DisabledTimestampInfo `
                -Info ([string]$live.info) `
                -WhenChanged $live.whenChanged

            if ($markerInfo.DisabledDateSource -ne 'LifecycleMarker') {
                if ($null -ne $record.DisabledDate) {
                    Set-UserLifecycleDisabledMarker `
                        -DistinguishedName ([string]$live.DistinguishedName) `
                        -DomainFqdn $DomainFqdn `
                        -DisabledOn ([datetime]$record.DisabledDate)

                    Write-Log -Message (
                        "Preserved disabled date before OU movement. User={0} | DisabledOn={1:o} | Source={2}" -f
                        $record.SamAccountName,
                        ([datetime]$record.DisabledDate),
                        $record.DisabledDateSource
                    ) -Level SUCCESS
                }
                else {
                    Write-Log -Message (
                        "Disabled date is unavailable for '{0}'. OU movement will proceed, but this account will not be deletion-eligible until a lifecycle disabled-date marker exists." -f
                        $record.SamAccountName
                    ) -Level WARNING
                }
            }

            Move-ADObject `
                -Identity ([string]$live.DistinguishedName) `
                -TargetPath $resolvedOuDn `
                -Server $DomainFqdn `
                -Confirm:$false `
                -ErrorAction Stop

            $moved++
            Write-Log -Message (
                "Disabled account '{0}' moved to '{1}' with disabled date preserved." -f
                $record.SamAccountName,
                $resolvedOuDn
            ) -Level SUCCESS
        }
        catch {
            $failed++
            Write-Log -Message "Failed to move '$($record.SamAccountName)': $($_.Exception.Message)" -Level ERROR
        }
        finally {
            $ProgressBar.Value = [math]::Min($index, $ProgressBar.Maximum)
            [System.Windows.Forms.Application]::DoEvents()
        }
    }

    Show-AppMessage -Message (
        "Move operation completed.`r`nMoved: {0}`r`nSkipped: {1}`r`nFailed: {2}" -f
        $moved,
        $skipped,
        $failed
    ) -Type Information
}

function Remove-EligibleGridRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DomainFqdn,
        [Parameter(Mandatory = $true)][System.Windows.Forms.DataGridView]$Grid,
        [Parameter(Mandatory = $true)][int]$DisabledAgeDays,
        [Parameter(Mandatory = $true)][System.Windows.Forms.ToolStripProgressBar]$ProgressBar
    )

    $records = @(Get-CheckedGridRecords -Grid $Grid)
    if ($records.Count -eq 0) {
        Show-AppMessage -Message 'No deletion-eligible disabled accounts selected.' -Type Warning
        return
    }

    $evidencePath = Export-DisabledDeletionEvidence `
        -Records $records `
        -ThresholdDays $DisabledAgeDays

    if (-not (Confirm-Action -Message (
        "Permanently delete {0} selected disabled account(s)?`r`n`r`nThreshold: {1} days`r`nEvidence: {2}" -f
        $records.Count,
        $DisabledAgeDays,
        $evidencePath
    ))) {
        return
    }

    $ProgressBar.Maximum = [math]::Max(1, $records.Count)
    $ProgressBar.Value = 0

    $deleted = 0
    $skipped = 0
    $failed = 0
    $index = 0

    foreach ($record in $records) {
        $index++

        try {
            $live = Get-ADUser `
                -Identity ([guid]$record.ObjectGuid) `
                -Server $DomainFqdn `
                -Properties Enabled,whenChanged,info,ProtectedFromAccidentalDeletion,DistinguishedName `
                -ErrorAction Stop

            if ([bool]$live.Enabled) {
                $skipped++
                Write-DisabledDeletionJournal -Record $record -Result 'SKIPPED' -Message 'Account is enabled during live validation.' -ThresholdDays $DisabledAgeDays
                continue
            }

            $liveAge = Get-DisabledTimestampInfo `
                -Info ([string]$live.info) `
                -WhenChanged $live.whenChanged

            if (
                $null -eq $liveAge.DisabledAgeDays -or
                [int]$liveAge.DisabledAgeDays -lt $DisabledAgeDays
            ) {
                $skipped++
                Write-DisabledDeletionJournal -Record $record -Result 'SKIPPED' -Message 'Live disabled age is below threshold.' -ThresholdDays $DisabledAgeDays
                continue
            }

            if ([bool]$live.ProtectedFromAccidentalDeletion) {
                $skipped++
                Write-DisabledDeletionJournal -Record $record -Result 'SKIPPED' -Message 'ProtectedFromAccidentalDeletion is enabled.' -ThresholdDays $DisabledAgeDays
                continue
            }

            Remove-ADUser `
                -Identity ([string]$live.DistinguishedName) `
                -Server $DomainFqdn `
                -Confirm:$false `
                -ErrorAction Stop

            $deleted++
            Write-DisabledDeletionJournal -Record $record -Result 'DELETED' -Message 'Account deleted successfully.' -ThresholdDays $DisabledAgeDays
        }
        catch {
            $failed++
            Write-DisabledDeletionJournal -Record $record -Result 'FAILED' -Message $_.Exception.Message -ThresholdDays $DisabledAgeDays
            Write-Log -Message "Failed to delete '$($record.SamAccountName)': $($_.Exception.Message)" -Level ERROR
        }
        finally {
            $ProgressBar.Value = [math]::Min($index, $ProgressBar.Maximum)
            [System.Windows.Forms.Application]::DoEvents()
        }
    }

    Show-AppMessage -Message (
        "Deletion completed.`r`nDeleted: {0}`r`nSkipped: {1}`r`nFailed: {2}" -f
        $deleted,
        $skipped,
        $failed
    ) -Type Information
}


# =====================================================================================
# GUI construction
# =====================================================================================

function New-ToolbarButton {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [int]$Width = 140
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Width = $Width
    $button.Height = 30
    $button.Margin = New-Object System.Windows.Forms.Padding(3)
    return $button
}

function Set-SafeSplitterLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.SplitContainer]$SplitContainer,
        [Parameter(Mandatory = $true)][int]$Panel1Minimum,
        [Parameter(Mandatory = $true)][int]$Panel2Minimum,
        [Parameter(Mandatory = $true)][double]$Panel1Ratio
    )

    $available = if (
        $SplitContainer.Orientation -eq [System.Windows.Forms.Orientation]::Vertical
    ) {
        $SplitContainer.ClientSize.Width - $SplitContainer.SplitterWidth
    }
    else {
        $SplitContainer.ClientSize.Height - $SplitContainer.SplitterWidth
    }

    if ($available -le 0) {
        return
    }

    # WinForms requires:
    # Panel1MinSize <= SplitterDistance <= available - Panel2MinSize
    $effectivePanel1Min = [math]::Min(
        [math]::Max(0, $Panel1Minimum),
        [math]::Max(0, $available - 1)
    )

    $effectivePanel2Min = [math]::Min(
        [math]::Max(0, $Panel2Minimum),
        [math]::Max(0, $available - $effectivePanel1Min)
    )

    if (($effectivePanel1Min + $effectivePanel2Min) -ge $available) {
        $effectivePanel1Min = [math]::Max(0, [int][math]::Floor($available * 0.35))
        $effectivePanel2Min = [math]::Max(0, [int][math]::Floor($available * 0.35))
    }

    $SplitContainer.Panel1MinSize = $effectivePanel1Min
    $SplitContainer.Panel2MinSize = $effectivePanel2Min

    $minimumDistance = $SplitContainer.Panel1MinSize
    $maximumDistance = $available - $SplitContainer.Panel2MinSize

    if ($maximumDistance -lt $minimumDistance) {
        return
    }

    $desiredDistance = [int][math]::Round($available * $Panel1Ratio)
    $safeDistance = [math]::Min(
        $maximumDistance,
        [math]::Max($minimumDistance, $desiredDistance)
    )

    $SplitContainer.SplitterDistance = $safeDistance
}

function Update-MainActionButtonStates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.ComboBox]$DomainCombo,
        [Parameter(Mandatory = $true)][System.Windows.Forms.TextBox]$InactiveOuTextBox,
        [Parameter(Mandatory = $true)][System.Windows.Forms.DataGridView]$ExpiredGrid,
        [Parameter(Mandatory = $true)][System.Windows.Forms.DataGridView]$DisabledGrid,
        [Parameter(Mandatory = $true)][System.Windows.Forms.DataGridView]$EligibleGrid,
        [Parameter(Mandatory = $true)][System.Windows.Forms.Button]$ScanButton,
        [Parameter(Mandatory = $true)][System.Windows.Forms.Button]$SearchOuButton,
        [Parameter(Mandatory = $true)][System.Windows.Forms.Button]$SelectExpiredButton,
        [Parameter(Mandatory = $true)][System.Windows.Forms.Button]$DisableExpiredButton,
        [Parameter(Mandatory = $true)][System.Windows.Forms.Button]$SelectDisabledButton,
        [Parameter(Mandatory = $true)][System.Windows.Forms.Button]$ClearSelectionButton,
        [Parameter(Mandatory = $true)][System.Windows.Forms.Button]$RemoveGroupsButton,
        [Parameter(Mandatory = $true)][System.Windows.Forms.Button]$MoveOuButton,
        [Parameter(Mandatory = $true)][System.Windows.Forms.Button]$SelectEligibleButton,
        [Parameter(Mandatory = $true)][System.Windows.Forms.Button]$DeleteEligibleButton,
        [Parameter(Mandatory = $true)][System.Windows.Forms.Button]$ExportButton
    )

    $hasDomain = (
        $DomainCombo.SelectedIndex -ge 0 -and
        -not [string]::IsNullOrWhiteSpace([string]$DomainCombo.SelectedItem)
    )

    $expiredCount = $ExpiredGrid.Rows.Count
    $disabledCount = $DisabledGrid.Rows.Count
    $eligibleCount = $EligibleGrid.Rows.Count

    $expiredSelected = @(Get-CheckedGridRecords -Grid $ExpiredGrid).Count
    $disabledSelected = @(Get-CheckedGridRecords -Grid $DisabledGrid).Count
    $eligibleSelected = @(Get-CheckedGridRecords -Grid $EligibleGrid).Count

    $hasInactiveOu = -not [string]::IsNullOrWhiteSpace($InactiveOuTextBox.Text)

    $ScanButton.Enabled = $hasDomain
    $SearchOuButton.Enabled = $hasDomain

    $SelectExpiredButton.Enabled = $expiredCount -gt 0
    $DisableExpiredButton.Enabled = $expiredSelected -gt 0

    $SelectDisabledButton.Enabled = $disabledCount -gt 0
    $RemoveGroupsButton.Enabled = $disabledSelected -gt 0
    $MoveOuButton.Enabled = ($disabledSelected -gt 0 -and $hasInactiveOu)

    $SelectEligibleButton.Enabled = $eligibleCount -gt 0
    $DeleteEligibleButton.Enabled = $eligibleSelected -gt 0

    $ClearSelectionButton.Enabled = (
        $expiredSelected -gt 0 -or
        $disabledSelected -gt 0 -or
        $eligibleSelected -gt 0
    )

    $ExportButton.Enabled = ($hasDomain -and $disabledCount -gt 0)
}

function Show-Gui {
    $domains = @(Get-ForestDomainsSafe)
    if ($domains.Count -eq 0) {
        Show-AppMessage -Message 'No Active Directory domains were found in the current forest context.' -Type Error
        return
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = ('{0} v{1}' -f $Script:AppName, $Script:AppVersion)
    $form.ClientSize = New-Object System.Drawing.Size(1460, 860)
    $form.MinimumSize = New-Object System.Drawing.Size(1180, 760)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $form.MaximizeBox = $true
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

    $headerPanel = New-Object System.Windows.Forms.Panel
    $headerPanel.Dock = [System.Windows.Forms.DockStyle]::Top
    $headerPanel.Height = 58
    $headerPanel.Padding = New-Object System.Windows.Forms.Padding(10, 10, 10, 8)

    $headerLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $headerLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
    $headerLayout.RowCount = 1
    $headerLayout.ColumnCount = 7
    $headerLayout.Margin = New-Object System.Windows.Forms.Padding(0)
    $headerLayout.Padding = New-Object System.Windows.Forms.Padding(0)

    [void]$headerLayout.ColumnStyles.Add(
        (New-Object System.Windows.Forms.ColumnStyle(
            [System.Windows.Forms.SizeType]::AutoSize
        ))
    )
    [void]$headerLayout.ColumnStyles.Add(
        (New-Object System.Windows.Forms.ColumnStyle(
            [System.Windows.Forms.SizeType]::Absolute,
            285
        ))
    )
    [void]$headerLayout.ColumnStyles.Add(
        (New-Object System.Windows.Forms.ColumnStyle(
            [System.Windows.Forms.SizeType]::AutoSize
        ))
    )
    [void]$headerLayout.ColumnStyles.Add(
        (New-Object System.Windows.Forms.ColumnStyle(
            [System.Windows.Forms.SizeType]::Absolute,
            95
        ))
    )
    [void]$headerLayout.ColumnStyles.Add(
        (New-Object System.Windows.Forms.ColumnStyle(
            [System.Windows.Forms.SizeType]::AutoSize
        ))
    )
    [void]$headerLayout.ColumnStyles.Add(
        (New-Object System.Windows.Forms.ColumnStyle(
            [System.Windows.Forms.SizeType]::Percent,
            100
        ))
    )
    [void]$headerLayout.ColumnStyles.Add(
        (New-Object System.Windows.Forms.ColumnStyle(
            [System.Windows.Forms.SizeType]::Absolute,
            115
        ))
    )

    $labelDomain = New-Object System.Windows.Forms.Label
    $labelDomain.Text = 'Domain:'
    $labelDomain.AutoSize = $true
    $labelDomain.Anchor = [System.Windows.Forms.AnchorStyles]::Left
    $labelDomain.Margin = New-Object System.Windows.Forms.Padding(0, 7, 8, 0)

    $comboDomain = New-Object System.Windows.Forms.ComboBox
    $comboDomain.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $comboDomain.Dock = [System.Windows.Forms.DockStyle]::Fill
    $comboDomain.Margin = New-Object System.Windows.Forms.Padding(0, 3, 14, 3)
    [void]$comboDomain.Items.AddRange([object[]]$domains)
    $comboDomain.SelectedIndex = 0

    $labelAge = New-Object System.Windows.Forms.Label
    $labelAge.Text = 'Disabled days:'
    $labelAge.AutoSize = $true
    $labelAge.Anchor = [System.Windows.Forms.AnchorStyles]::Left
    $labelAge.Margin = New-Object System.Windows.Forms.Padding(0, 7, 8, 0)

    $numDisabledAge = New-Object System.Windows.Forms.NumericUpDown
    $numDisabledAge.Minimum = 30
    $numDisabledAge.Maximum = 3650
    $numDisabledAge.Value = 365
    $numDisabledAge.Dock = [System.Windows.Forms.DockStyle]::Fill
    $numDisabledAge.Margin = New-Object System.Windows.Forms.Padding(0, 3, 14, 3)

    $labelOu = New-Object System.Windows.Forms.Label
    $labelOu.Text = 'Inactive OU:'
    $labelOu.AutoSize = $true
    $labelOu.Anchor = [System.Windows.Forms.AnchorStyles]::Left
    $labelOu.Margin = New-Object System.Windows.Forms.Padding(0, 7, 8, 0)

    $txtInactiveOu = New-Object System.Windows.Forms.TextBox
    $txtInactiveOu.Dock = [System.Windows.Forms.DockStyle]::Fill
    $txtInactiveOu.Margin = New-Object System.Windows.Forms.Padding(0, 3, 8, 3)

    $btnSearchOu = New-Object System.Windows.Forms.Button
    $btnSearchOu.Text = 'Search OU...'
    $btnSearchOu.Dock = [System.Windows.Forms.DockStyle]::Fill
    $btnSearchOu.Margin = New-Object System.Windows.Forms.Padding(0, 1, 0, 1)

    $headerLayout.Controls.Add($labelDomain, 0, 0)
    $headerLayout.Controls.Add($comboDomain, 1, 0)
    $headerLayout.Controls.Add($labelAge, 2, 0)
    $headerLayout.Controls.Add($numDisabledAge, 3, 0)
    $headerLayout.Controls.Add($labelOu, 4, 0)
    $headerLayout.Controls.Add($txtInactiveOu, 5, 0)
    $headerLayout.Controls.Add($btnSearchOu, 6, 0)

    $headerPanel.Controls.Add($headerLayout)

    $toolbar = New-Object System.Windows.Forms.FlowLayoutPanel
    $toolbar.Dock = [System.Windows.Forms.DockStyle]::Top
    $toolbar.Height = 42
    $toolbar.Padding = New-Object System.Windows.Forms.Padding(8,4,8,4)
    $toolbar.WrapContents = $false
    $toolbar.AutoScroll = $true

    $btnScan = New-ToolbarButton -Text 'Scan Domain' -Width 125
    $btnSelectExpired = New-ToolbarButton -Text 'Select Expired' -Width 125
    $btnDisableExpired = New-ToolbarButton -Text 'Disable Expired' -Width 130
    $btnSelectDisabled = New-ToolbarButton -Text 'Select Disabled' -Width 130
    $btnClearAll = New-ToolbarButton -Text 'Clear Selection' -Width 125
    $btnRemoveGroups = New-ToolbarButton -Text 'Remove Groups' -Width 125
    $btnMoveOu = New-ToolbarButton -Text 'Move to Inactive OU' -Width 155
    $btnSelectEligible = New-ToolbarButton -Text 'Select Eligible' -Width 125
    $btnDeleteEligible = New-ToolbarButton -Text 'Delete Eligible' -Width 125
    $btnExport = New-ToolbarButton -Text 'Export Disabled CSV' -Width 150

    foreach ($actionButton in @(
        $btnSelectExpired,
        $btnDisableExpired,
        $btnSelectDisabled,
        $btnClearAll,
        $btnRemoveGroups,
        $btnMoveOu,
        $btnSelectEligible,
        $btnDeleteEligible,
        $btnExport
    )) {
        $actionButton.Enabled = $false
    }

    $toolbar.Controls.AddRange(@(
        $btnScan,$btnSelectExpired,$btnDisableExpired,$btnSelectDisabled,$btnClearAll,
        $btnRemoveGroups,$btnMoveOu,$btnSelectEligible,$btnDeleteEligible,$btnExport
    ))

    $mainSplit = New-Object System.Windows.Forms.SplitContainer
    $mainSplit.Dock = [System.Windows.Forms.DockStyle]::Fill
    $mainSplit.Orientation = [System.Windows.Forms.Orientation]::Horizontal
    # Splitter dimensions are applied after the form is shown and layout is complete.

    $upperSplit = New-Object System.Windows.Forms.SplitContainer
    $upperSplit.Dock = [System.Windows.Forms.DockStyle]::Fill
    $upperSplit.Orientation = [System.Windows.Forms.Orientation]::Vertical
    # Splitter dimensions are applied after the form is shown and layout is complete.

    $expiredGroup = New-Object System.Windows.Forms.GroupBox
    $expiredGroup.Text = 'Expired Accounts'
    $expiredGroup.Dock = [System.Windows.Forms.DockStyle]::Fill
    $expiredGroup.Padding = New-Object System.Windows.Forms.Padding(8)

    $disabledGroup = New-Object System.Windows.Forms.GroupBox
    $disabledGroup.Text = 'Disabled Accounts'
    $disabledGroup.Dock = [System.Windows.Forms.DockStyle]::Fill
    $disabledGroup.Padding = New-Object System.Windows.Forms.Padding(8)

    $eligibleGroup = New-Object System.Windows.Forms.GroupBox
    $eligibleGroup.Text = 'Disabled Accounts Eligible for Deletion'
    $eligibleGroup.Dock = [System.Windows.Forms.DockStyle]::Fill
    $eligibleGroup.Padding = New-Object System.Windows.Forms.Padding(8)

    $expiredColumns = @(
        @{Name='Domain'; Header='Domain'; Width=150},
        @{Name='SamAccountName'; Header='SAM Account Name'; Width=155},
        @{Name='DisplayName'; Header='Display Name'; Width=220},
        @{Name='AccountExpirationDate'; Header='Expiration Date'; Width=145},
        @{Name='DistinguishedName'; Header='Distinguished Name'; Width=320}
    )

    $disabledColumns = @(
        @{Name='Domain'; Header='Domain'; Width=145},
        @{Name='SamAccountName'; Header='SAM Account Name'; Width=145},
        @{Name='DisplayName'; Header='Display Name'; Width=190},
        @{Name='DisabledDate'; Header='Disabled Date'; Width=140},
        @{Name='DisabledAgeDays'; Header='Disabled Days'; Width=105},
        @{Name='DisabledDateSource'; Header='Date Source'; Width=125},
        @{Name='Protected'; Header='Protected'; Width=80},
        @{Name='DistinguishedName'; Header='Distinguished Name'; Width=330}
    )

    $expiredGrid = New-EnterpriseDataGridView -Columns $expiredColumns
    $expiredGrid.Dock = [System.Windows.Forms.DockStyle]::Fill
    $expiredGrid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None

    $disabledGrid = New-EnterpriseDataGridView -Columns $disabledColumns
    $disabledGrid.Dock = [System.Windows.Forms.DockStyle]::Fill
    $disabledGrid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None

    $eligibleGrid = New-EnterpriseDataGridView -Columns $disabledColumns
    $eligibleGrid.Dock = [System.Windows.Forms.DockStyle]::Fill
    $eligibleGrid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None

    $expiredGroup.Controls.Add($expiredGrid)
    $disabledGroup.Controls.Add($disabledGrid)
    $eligibleGroup.Controls.Add($eligibleGrid)

    $upperSplit.Panel1.Controls.Add($expiredGroup)
    $upperSplit.Panel2.Controls.Add($disabledGroup)
    $mainSplit.Panel1.Controls.Add($upperSplit)
    $mainSplit.Panel2.Controls.Add($eligibleGroup)

    $statusStrip = New-Object System.Windows.Forms.StatusStrip
    $statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
    $statusLabel.Spring = $true
    $statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $statusLabel.Text = 'Ready.'

    $progressBar = New-Object System.Windows.Forms.ToolStripProgressBar
    $progressBar.Width = 220
    $progressBar.Minimum = 0
    $progressBar.Maximum = 100
    $progressBar.Value = 0

    [void]$statusStrip.Items.Add($statusLabel)
    [void]$statusStrip.Items.Add($progressBar)

    $form.Controls.Add($mainSplit)
    $form.Controls.Add($toolbar)
    $form.Controls.Add($headerPanel)
    $form.Controls.Add($statusStrip)

    $refreshSelection = {
        Update-GridSelectionSummary `
            -StatusLabel $statusLabel `
            -ExpiredGrid $expiredGrid `
            -DisabledGrid $disabledGrid `
            -EligibleGrid $eligibleGrid

        Update-MainActionButtonStates `
            -DomainCombo $comboDomain `
            -InactiveOuTextBox $txtInactiveOu `
            -ExpiredGrid $expiredGrid `
            -DisabledGrid $disabledGrid `
            -EligibleGrid $eligibleGrid `
            -ScanButton $btnScan `
            -SearchOuButton $btnSearchOu `
            -SelectExpiredButton $btnSelectExpired `
            -DisableExpiredButton $btnDisableExpired `
            -SelectDisabledButton $btnSelectDisabled `
            -ClearSelectionButton $btnClearAll `
            -RemoveGroupsButton $btnRemoveGroups `
            -MoveOuButton $btnMoveOu `
            -SelectEligibleButton $btnSelectEligible `
            -DeleteEligibleButton $btnDeleteEligible `
            -ExportButton $btnExport
    }

    $expiredGrid.Add_CellValueChanged($refreshSelection)
    $disabledGrid.Add_CellValueChanged($refreshSelection)
    $eligibleGrid.Add_CellValueChanged($refreshSelection)

    $resolveDefaultOu = {
        try {
            $txtInactiveOu.Clear()
            $ou = Get-InactiveUsersOu -DomainFqdn ([string]$comboDomain.SelectedItem)
            if ($null -ne $ou) {
                $txtInactiveOu.Text = [string]$ou.DistinguishedName
            }

            & $refreshSelection
        }
        catch {
            Write-Log -Message "Unable to resolve default inactive OU: $($_.Exception.Message)" -Level WARNING
        }
    }

    $comboDomain.Add_SelectedIndexChanged({
        Invoke-GuiSafe -Context 'Change selected domain' -ScriptBlock {
            & $resolveDefaultOu
            $expiredGrid.Rows.Clear()
            $disabledGrid.Rows.Clear()
            $eligibleGrid.Rows.Clear()
            & $refreshSelection
        }
    })

    $numDisabledAge.Add_ValueChanged({
        Invoke-GuiSafe -Context 'Change disabled-age threshold' -ScriptBlock {
            $eligibleGrid.Rows.Clear()

            foreach ($row in $disabledGrid.Rows) {
                if (
                    -not $row.IsNewRow -and
                    $null -ne $row.Tag -and
                    $null -ne $row.Tag.DisabledAgeDays -and
                    [int]$row.Tag.DisabledAgeDays -ge [int]$numDisabledAge.Value
                ) {
                    Add-RecordToGrid -Grid $eligibleGrid -Record $row.Tag -Mode Disabled
                }
            }

            Set-AllGridChecks -Grid $eligibleGrid -Checked $false

            $eligibleGroup.Text = (
                'Deletion-Eligible Disabled Accounts (Days >= {0})' -f
                [int]$numDisabledAge.Value
            )

            & $refreshSelection
        }
    })

    $btnSearchOu.Add_Click({
        Invoke-GuiSafe -Context 'Search organizational unit' -ScriptBlock {
            $selectedOu = Show-OrganizationalUnitSearchDialog `
                -DomainFqdn ([string]$comboDomain.SelectedItem) `
                -CurrentOuDn ([string]$txtInactiveOu.Text)

            if (-not [string]::IsNullOrWhiteSpace($selectedOu)) {
                $txtInactiveOu.Text = $selectedOu
            }

            & $refreshSelection
        }
    })

    $txtInactiveOu.Add_TextChanged({
        & $refreshSelection
    })

    $btnScan.Add_Click({
        Invoke-GuiSafe -Context 'Unified domain scan' -ScriptBlock {
            Refresh-UnifiedUserGrids `
                -DomainFqdn ([string]$comboDomain.SelectedItem) `
                -DisabledAgeDays ([int]$numDisabledAge.Value) `
                -ExpiredGrid $expiredGrid `
                -DisabledGrid $disabledGrid `
                -EligibleGrid $eligibleGrid `
                -StatusLabel $statusLabel `
                -ProgressBar $progressBar
        }
    })

    $btnSelectExpired.Add_Click({
        if ($expiredGrid.Rows.Count -eq 0) {
            Show-AppMessage -Message 'There are no expired accounts to select.' -Type Warning
            return
        }

        Set-AllGridChecks -Grid $expiredGrid -Checked $true
        & $refreshSelection
    })

    $btnSelectDisabled.Add_Click({
        if ($disabledGrid.Rows.Count -eq 0) {
            Show-AppMessage -Message 'There are no disabled accounts to select.' -Type Warning
            return
        }

        Set-AllGridChecks -Grid $disabledGrid -Checked $true
        & $refreshSelection
    })

    $btnSelectEligible.Add_Click({
        if ($eligibleGrid.Rows.Count -eq 0) {
            Show-AppMessage -Message 'There are no deletion-eligible accounts to select.' -Type Warning
            return
        }

        Set-AllGridChecks -Grid $eligibleGrid -Checked $true
        & $refreshSelection
    })

    $btnClearAll.Add_Click({
        if (
            @(Get-CheckedGridRecords -Grid $expiredGrid).Count -eq 0 -and
            @(Get-CheckedGridRecords -Grid $disabledGrid).Count -eq 0 -and
            @(Get-CheckedGridRecords -Grid $eligibleGrid).Count -eq 0
        ) {
            Show-AppMessage -Message 'There are no selected accounts to clear.' -Type Warning
            return
        }

        Set-AllGridChecks -Grid $expiredGrid -Checked $false
        Set-AllGridChecks -Grid $disabledGrid -Checked $false
        Set-AllGridChecks -Grid $eligibleGrid -Checked $false
        & $refreshSelection
    })

    $btnDisableExpired.Add_Click({
        Invoke-GuiSafe -Context 'Disable selected expired users' -ScriptBlock {
            Disable-ExpiredGridRecords `
                -DomainFqdn ([string]$comboDomain.SelectedItem) `
                -Grid $expiredGrid

            Refresh-UnifiedUserGrids `
                -DomainFqdn ([string]$comboDomain.SelectedItem) `
                -DisabledAgeDays ([int]$numDisabledAge.Value) `
                -ExpiredGrid $expiredGrid `
                -DisabledGrid $disabledGrid `
                -EligibleGrid $eligibleGrid `
                -StatusLabel $statusLabel `
                -ProgressBar $progressBar
        }
    })

    $btnRemoveGroups.Add_Click({
        Invoke-GuiSafe -Context 'Remove group memberships' -ScriptBlock {
            Remove-DisabledGridRecordsFromGroups `
                -DomainFqdn ([string]$comboDomain.SelectedItem) `
                -Grid $disabledGrid `
                -ProgressBar $progressBar
        }
    })

    $btnMoveOu.Add_Click({
        Invoke-GuiSafe -Context 'Move selected disabled users' -ScriptBlock {
            $selectedDomain = [string]$comboDomain.SelectedItem
            $targetOu = [string]$txtInactiveOu.Text

            if ([string]::IsNullOrWhiteSpace($targetOu)) {
                $autoResolvedOu = Get-InactiveUsersOu -DomainFqdn $selectedDomain

                if ($null -ne $autoResolvedOu) {
                    $targetOu = [string]$autoResolvedOu.DistinguishedName
                    $txtInactiveOu.Text = $targetOu
                }
                else {
                    Show-AppMessage -Message (
                        "No destination OU is selected, and the default OU 'Inactive User Accounts' " +
                        "was not found in domain '{0}'.`r`n`r`nUse 'Search OU...' before moving accounts." -f
                        $selectedDomain
                    ) -Type Warning

                    return
                }
            }

            Move-DisabledGridRecords `
                -DomainFqdn $selectedDomain `
                -Grid $disabledGrid `
                -TargetOuDn $targetOu `
                -ProgressBar $progressBar

            Refresh-UnifiedUserGrids `
                -DomainFqdn $selectedDomain `
                -DisabledAgeDays ([int]$numDisabledAge.Value) `
                -ExpiredGrid $expiredGrid `
                -DisabledGrid $disabledGrid `
                -EligibleGrid $eligibleGrid `
                -StatusLabel $statusLabel `
                -ProgressBar $progressBar
        }
    })

    $btnDeleteEligible.Add_Click({
        Invoke-GuiSafe -Context 'Delete eligible disabled users' -ScriptBlock {
            Remove-EligibleGridRecords `
                -DomainFqdn ([string]$comboDomain.SelectedItem) `
                -Grid $eligibleGrid `
                -DisabledAgeDays ([int]$numDisabledAge.Value) `
                -ProgressBar $progressBar

            Refresh-UnifiedUserGrids `
                -DomainFqdn ([string]$comboDomain.SelectedItem) `
                -DisabledAgeDays ([int]$numDisabledAge.Value) `
                -ExpiredGrid $expiredGrid `
                -DisabledGrid $disabledGrid `
                -EligibleGrid $eligibleGrid `
                -StatusLabel $statusLabel `
                -ProgressBar $progressBar
        }
    })

    $btnExport.Add_Click({
        Invoke-GuiSafe -Context 'Export disabled users CSV' -ScriptBlock {
            if ($disabledGrid.Rows.Count -eq 0) {
                Show-AppMessage -Message 'Run a scan and load disabled accounts before exporting.' -Type Warning
                return
            }

            Export-DisabledAccountsReportCsv `
                -DomainFqdn ([string]$comboDomain.SelectedItem) `
                -OutputFolder ([Environment]::GetFolderPath('MyDocuments'))
        }
    })

    $form.Add_Shown({
        # At this point WinForms has calculated the actual client dimensions.
        Set-SafeSplitterLayout `
            -SplitContainer $mainSplit `
            -Panel1Minimum 300 `
            -Panel2Minimum 220 `
            -Panel1Ratio 0.55

        Set-SafeSplitterLayout `
            -SplitContainer $upperSplit `
            -Panel1Minimum 420 `
            -Panel2Minimum 550 `
            -Panel1Ratio 0.42

        & $resolveDefaultOu

        $eligibleGroup.Text = (
            'Deletion-Eligible Disabled Accounts (Disabled Days >= {0})' -f
            [int]$numDisabledAge.Value
        )

        & $refreshSelection
        $statusLabel.Text = 'Ready. Select a domain and click Scan Domain.'
    })

    $form.Add_Resize({
        if ($form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized) {
            Set-SafeSplitterLayout `
                -SplitContainer $mainSplit `
                -Panel1Minimum 300 `
                -Panel2Minimum 220 `
                -Panel1Ratio 0.55

            Set-SafeSplitterLayout `
                -SplitContainer $upperSplit `
                -Panel1Minimum 420 `
                -Panel2Minimum 550 `
                -Panel1Ratio 0.42
        }
    })

    $form.Add_FormClosing({
        Write-Log -Message '==== Session ended ====' -Level INFO
    })

    [void][System.Windows.Forms.Application]::Run($form)
}

try {
    Show-Gui
}
catch {
    $startupMessage = "Application startup failed.`r`n$($_.Exception.Message)"
    Write-Log -Message $startupMessage.Replace("`r", ' ').Replace("`n", ' ') -Level ERROR
    Show-AppMessage -Message $startupMessage -Type Error
}

# End of script
