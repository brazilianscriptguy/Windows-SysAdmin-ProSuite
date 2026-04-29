<#
.SYNOPSIS
    Unified GUI tool for SMB share access remediation and NTFS group permission discovery.

.DESCRIPTION
    Provides a Windows Forms interface with two separated workflows:

    1. SMB Share Access
       - Lists local SMB shares.
       - Detects Deny entries at SMB share level.
       - Finds SMB share Deny entries by user account across local shares.
       - Unblocks selected accounts from SMB share Deny rules.
       - Reviews SMB share access entries for a specified account.

    2. NTFS Group Permission Scanner
       - Resolves an AD group, DOMAIN\Group, distinguished name, or SID using forest-aware AD discovery logic.
       - Gathers local NTFS-backed SMB share paths as scan targets.
       - Scans NTFS folder ACLs using SID-based matching.
       - Supports root-only, first-level, or bounded recursive scanning.
       - Exports evidence to CSV and TXT reports.

    This script is designed for PowerShell 5.1, Windows Server administration, and portfolio-ready enterprise automation.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    2026.04.29-v2.3-Enterprise-PS51-DataGridBeginUpdateFixed-FINAL
#>

[CmdletBinding()]
param(
    [switch]$ShowConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =========================
# Console visibility
# =========================
if (-not $ShowConsole) {
    try {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class ConsoleWindowManager {
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() {
        IntPtr handle = GetConsoleWindow();
        if (handle != IntPtr.Zero) { ShowWindow(handle, 0); }
    }
}
"@
        [ConsoleWindowManager]::Hide()
    } catch { }
}

# =========================
# Assemblies
# =========================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# =========================
# Script identity and logging
# =========================
$script:ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:LogDir = 'C:\Logs-TEMP'
$script:LogPath = Join-Path $script:LogDir ("{0}.log" -f $script:ScriptName)
$script:LastNtfsScanResults = @()
$script:LastNtfsBasePath = ""
$script:LastNtfsScanErrors = @()
$script:LastResolvedGroup = $null
$script:LastSharePathInventory = @()
$script:LoadedGroupLookup = @{}

if (-not (Test-Path -LiteralPath $script:LogDir)) {
    New-Item -Path $script:LogDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$timestamp] [$Level] $Message"
    try { Add-Content -Path $script:LogPath -Value $entry -Encoding UTF8 } catch { }
}

function Show-Info {
    param([string]$Message)
    Write-Log -Message $Message -Level INFO
    [System.Windows.Forms.MessageBox]::Show($Message, 'Information', 'OK', 'Information') | Out-Null
}

function Show-Warning {
    param([string]$Message)
    Write-Log -Message $Message -Level WARN
    [System.Windows.Forms.MessageBox]::Show($Message, 'Warning', 'OK', 'Warning') | Out-Null
}

function Show-ErrorDialog {
    param([string]$Message)
    Write-Log -Message $Message -Level ERROR
    [System.Windows.Forms.MessageBox]::Show($Message, 'Error', 'OK', 'Error') | Out-Null
}

function Add-UiLog {
    param(
        [System.Windows.Forms.TextBox]$TextBox,
        [string]$Message,
        [string]$Level = 'INFO'
    )

    Write-Log -Message $Message -Level $Level
    if ($null -ne $TextBox) {
        $line = "[{0}] [{1}] {2}{3}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message, [Environment]::NewLine
        $TextBox.AppendText($line)
    }
}

function New-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 120, [int]$H = 22)
    $c = New-Object System.Windows.Forms.Label
    $c.Text = $Text
    $c.Location = New-Object System.Drawing.Point($X,$Y)
    $c.Size = New-Object System.Drawing.Size($W,$H)
    return $c
}

function New-Button {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 120, [int]$H = 30)
    $c = New-Object System.Windows.Forms.Button
    $c.Text = $Text
    $c.Location = New-Object System.Drawing.Point($X,$Y)
    $c.Size = New-Object System.Drawing.Size($W,$H)
    return $c
}

function New-TextBox {
    param([int]$X, [int]$Y, [int]$W = 200, [int]$H = 22, [bool]$Multiline = $false)
    $c = New-Object System.Windows.Forms.TextBox
    $c.Location = New-Object System.Drawing.Point($X,$Y)
    $c.Size = New-Object System.Drawing.Size($W,$H)
    $c.Multiline = $Multiline
    if ($Multiline) {
        $c.ScrollBars = 'Vertical'
        $c.WordWrap = $false
    }
    return $c
}

function Add-ListViewRowSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.ListView]$ListView,
        [Parameter(Mandatory=$true)][object[]]$Values
    )

    $safeValues = @($Values | ForEach-Object {
        if ($null -eq $_) { '' } else { [string]$_ }
    })

    if ($safeValues.Count -eq 0) { return }

    $item = New-Object System.Windows.Forms.ListViewItem -ArgumentList ([string]$safeValues[0])
    if ($safeValues.Count -gt 1) {
        for ($i = 1; $i -lt $safeValues.Count; $i++) {
            [void]$item.SubItems.Add([string]$safeValues[$i])
        }
    }
    [void]$ListView.Items.Add($item)
}

function New-NtfsResultsDataTable {
    [CmdletBinding()]
    param()

    $table = New-Object System.Data.DataTable 'NtfsPermissionResults'
    [void]$table.Columns.Add('Folder Path', [string])
    [void]$table.Columns.Add('Rights', [string])
    [void]$table.Columns.Add('Inherited', [string])
    [void]$table.Columns.Add('Inheritance', [string])
    [void]$table.Columns.Add('Propagation', [string])
    return $table
}

function ConvertTo-SafeString {
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    return [string]$Value
}

function Add-DataGridTextColumn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.DataGridView]$Grid,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$HeaderText,
        [Parameter(Mandatory=$true)][int]$Width
    )

    $column = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $column.Name = $Name
    $column.HeaderText = $HeaderText
    $column.Width = $Width
    $column.ReadOnly = $true
    $column.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
    [void]$Grid.Columns.Add($column)
}

function Initialize-NtfsResultsGrid {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][System.Windows.Forms.DataGridView]$Grid)

    $Grid.AutoGenerateColumns = $false
    $Grid.DataSource = $null
    $Grid.Rows.Clear()
    $Grid.Columns.Clear()

    Add-DataGridTextColumn -Grid $Grid -Name 'FolderPath'   -HeaderText 'Folder Path'  -Width 395
    Add-DataGridTextColumn -Grid $Grid -Name 'Rights'       -HeaderText 'Rights'       -Width 210
    Add-DataGridTextColumn -Grid $Grid -Name 'Inherited'    -HeaderText 'Inherited'    -Width 75
    Add-DataGridTextColumn -Grid $Grid -Name 'Inheritance'  -HeaderText 'Inheritance'  -Width 130
    Add-DataGridTextColumn -Grid $Grid -Name 'Propagation'  -HeaderText 'Propagation'  -Width 130
}

function Add-NtfsResultGridRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.DataGridView]$Grid,
        [object]$FolderPath,
        [object]$Rights,
        [object]$Inherited,
        [object]$Inheritance,
        [object]$Propagation
    )

    $row = New-Object System.Windows.Forms.DataGridViewRow

    foreach ($value in @($FolderPath, $Rights, $Inherited, $Inheritance, $Propagation)) {
        $cell = New-Object System.Windows.Forms.DataGridViewTextBoxCell
        $cell.Value = (ConvertTo-SafeString $value)
        [void]$row.Cells.Add($cell)
    }

    [void]$Grid.Rows.Add($row)
}

function Test-CommandAvailable {
    param([string]$CommandName)
    return [bool](Get-Command -Name $CommandName -ErrorAction SilentlyContinue)
}


function ConvertTo-LdapEscapedValue {
    param([Parameter(Mandatory=$true)][string]$Value)
    return ($Value -replace '\\','\5c' -replace '\*','\2a' -replace '\(','\28' -replace '\)','\29' -replace ([string][char]0),'\00')
}

function Get-ForestDomainsSafe {
    [CmdletBinding()]
    param()

    $domains = New-Object System.Collections.Generic.List[string]

    # Primary path: current AD forest.
    if (Test-CommandAvailable -CommandName 'Get-ADForest') {
        try {
            foreach ($domain in @((Get-ADForest -ErrorAction Stop).Domains)) {
                if (-not [string]::IsNullOrWhiteSpace($domain)) { $domains.Add([string]$domain) }
            }
        } catch {
            Write-Log -Level WARN -Message ("Unable to enumerate forest domains using Get-ADForest. {0}" -f $_.Exception.Message)
        }
    }

    # Fallback: current AD domain from RSAT.
    if (Test-CommandAvailable -CommandName 'Get-ADDomain') {
        try {
            $currentDomain = (Get-ADDomain -ErrorAction Stop).DNSRoot
            if (-not [string]::IsNullOrWhiteSpace($currentDomain)) { $domains.Add([string]$currentDomain) }
        } catch {
            Write-Log -Level DEBUG -Message ("Unable to determine current AD domain using Get-ADDomain. {0}" -f $_.Exception.Message)
        }
    }

    # Fallback: environment variable from an interactive/domain context.
    if (-not [string]::IsNullOrWhiteSpace($env:USERDNSDOMAIN)) { $domains.Add([string]$env:USERDNSDOMAIN) }

    # Fallback: RootDSE defaultNamingContext converted to DNS format.
    try {
        $rootDse = [ADSI]'LDAP://RootDSE'
        $defaultNamingContext = [string]$rootDse.defaultNamingContext
        if (-not [string]::IsNullOrWhiteSpace($defaultNamingContext)) {
            $dns = (($defaultNamingContext -split ',') | Where-Object { $_ -match '^DC=' } | ForEach-Object { $_.Substring(3) }) -join '.'
            if (-not [string]::IsNullOrWhiteSpace($dns)) { $domains.Add($dns) }
        }
    } catch {
        Write-Log -Level DEBUG -Message ("Unable to determine domain from RootDSE. {0}" -f $_.Exception.Message)
    }

    return @($domains | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
}

function Get-AdDomainInventory {
    [CmdletBinding()]
    param()

    $rows = New-Object System.Collections.Generic.List[object]

    # Add an all-domain scope for forest-wide searches.
    $rows.Add([pscustomobject]@{
        Display   = '[All available domains]'
        DomainDns = ''
        NetBIOS   = ''
        Scope     = 'All'
    })

    foreach ($domain in @(Get-ForestDomainsSafe)) {
        $netbios = ''
        try {
            if (Test-CommandAvailable -CommandName 'Get-ADDomain') {
                $netbios = (Get-ADDomain -Server $domain -ErrorAction Stop).NetBIOSName
            }
        } catch {
            Write-Log -Level DEBUG -Message ("Unable to retrieve NetBIOS name for domain '{0}'. {1}" -f $domain, $_.Exception.Message)
        }

        $display = $domain
        if (-not [string]::IsNullOrWhiteSpace($netbios)) { $display = $netbios }

        $rows.Add([pscustomobject]@{
            Display   = $display
            DomainDns = $domain
            NetBIOS   = $netbios
            Scope     = 'Domain'
        })
    }

    $sortedDomainRows = @($rows.ToArray() | Sort-Object Scope, DomainDns -Unique)
    return $sortedDomainRows
}

function Get-DomainDnsFromComboText {
    param([string]$ComboText)
    if ([string]::IsNullOrWhiteSpace($ComboText)) { return "" }
    $value = $ComboText.Trim()
    if ($value -eq "[All available domains]") { return "" }
    if ($script:LoadedDomainLookup -and $script:LoadedDomainLookup.ContainsKey($value)) { return [string]$script:LoadedDomainLookup[$value].DomainDns }
    return $value
}

function Get-DomainSearchScopeDescription {
    param([string]$DomainDns)
    if ([string]::IsNullOrWhiteSpace($DomainDns)) { return 'all available domains' }
    return $DomainDns
}

# =========================
# SMB access functions
# =========================
function Get-ManagedSmbShares {
    if (-not (Test-CommandAvailable -CommandName 'Get-SmbShare')) {
        throw 'Get-SmbShare is not available. Run this tool on a Windows host with the SMBShare module available.'
    }

    @(Get-SmbShare -ErrorAction Stop | Where-Object { -not $_.Special } | Sort-Object Name)
}

function Get-DeniedSmbShareUsers {
    param([Parameter(Mandatory=$true)][string]$ShareName)

    if (-not (Test-CommandAvailable -CommandName 'Get-SmbShareAccess')) {
        throw 'Get-SmbShareAccess is not available. Run this tool on a Windows host with the SMBShare module available.'
    }

    @(Get-SmbShareAccess -Name $ShareName -ErrorAction Stop |
        Where-Object { $_.AccessControlType -eq 'Deny' } |
        Sort-Object AccountName)
}

function Resolve-AdUserAcrossForest {
    param([Parameter(Mandatory=$true)][string]$UserIdentity)

    $identity = $UserIdentity.Trim()
    if ([string]::IsNullOrWhiteSpace($identity)) { throw 'User identity cannot be empty.' }

    $samCandidate = $identity
    if ($identity -match '^[^\\]+\\(.+)$') { $samCandidate = $Matches[1] }
    if ($identity -match '^([^@]+)@.+$') { $samCandidate = $Matches[1] }

    if (-not (Test-CommandAvailable -CommandName 'Get-ADUser')) {
        return [pscustomobject]@{
            Input = $identity
            SamAccountName = $samCandidate
            DomainNetBIOS = ''
            DomainDns = ''
            DistinguishedName = ''
            Sid = ''
            CandidateNames = @($identity, $samCandidate)
            ResolutionMethod = 'TextOnly'
        }
    }

    $domains = @(Get-ForestDomainsSafe)
    foreach ($domain in $domains) {
        try {
            $user = $null
            try {
                $user = Get-ADUser -Identity $identity -Server $domain -Properties SID,SamAccountName,UserPrincipalName,DistinguishedName -ErrorAction Stop
            } catch {
                $escaped = ConvertTo-LdapEscapedValue -Value $samCandidate
                $user = Get-ADUser -LDAPFilter "(|(sAMAccountName=$escaped)(userPrincipalName=$escaped)(name=$escaped))" -Server $domain -Properties SID,SamAccountName,UserPrincipalName,DistinguishedName -ErrorAction Stop | Select-Object -First 1
            }

            if ($null -ne $user) {
                $netbios = ''
                try { $netbios = (Get-ADDomain -Server $domain -ErrorAction Stop).NetBIOSName } catch { }
                $candidates = New-Object System.Collections.Generic.List[string]
                $candidates.Add($identity)
                $candidates.Add($user.SamAccountName)
                if (-not [string]::IsNullOrWhiteSpace($netbios)) { $candidates.Add(("{0}\{1}" -f $netbios, $user.SamAccountName)) }
                if (-not [string]::IsNullOrWhiteSpace($user.UserPrincipalName)) { $candidates.Add($user.UserPrincipalName) }

                return [pscustomobject]@{
                    Input = $identity
                    SamAccountName = $user.SamAccountName
                    DomainNetBIOS = $netbios
                    DomainDns = $domain
                    DistinguishedName = $user.DistinguishedName
                    Sid = $user.SID.Value
                    CandidateNames = @($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
                    ResolutionMethod = 'ActiveDirectoryForest'
                }
            }
        } catch {
            Write-Log -Level DEBUG -Message ("Unable to resolve user '{0}' in domain '{1}'. {2}" -f $identity, $domain, $_.Exception.Message)
        }
    }

    return [pscustomobject]@{
        Input = $identity
        SamAccountName = $samCandidate
        DomainNetBIOS = ''
        DomainDns = ''
        DistinguishedName = ''
        Sid = ''
        CandidateNames = @($identity, $samCandidate)
        ResolutionMethod = 'TextOnlyFallback'
    }
}

function Test-SmbAccountMatch {
    param(
        [Parameter(Mandatory=$true)][string]$SmbAccountName,
        [Parameter(Mandatory=$true)]$ResolvedUser
    )

    $entry = $SmbAccountName.Trim()
    foreach ($candidate in @($ResolvedUser.CandidateNames)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and $entry.Equals($candidate, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }

    if ($entry -match '^[^\\]+\\(.+)$') {
        if ($Matches[1].Equals($ResolvedUser.SamAccountName, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }

    if (-not [string]::IsNullOrWhiteSpace($ResolvedUser.Sid)) {
        try {
            $ntAccount = New-Object System.Security.Principal.NTAccount($entry)
            $sid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
            if ($sid -eq $ResolvedUser.Sid) { return $true }
        } catch { }
    }

    return $false
}

function Find-DeniedSmbShareEntriesByUser {
    param([Parameter(Mandatory=$true)][string]$UserIdentity)

    $resolvedUser = Resolve-AdUserAcrossForest -UserIdentity $UserIdentity
    $rows = New-Object System.Collections.Generic.List[object]
    $shares = @(Get-ManagedSmbShares)

    foreach ($share in $shares) {
        try {
            $denies = @(Get-SmbShareAccess -Name $share.Name -ErrorAction Stop | Where-Object { $_.AccessControlType -eq 'Deny' })
            foreach ($deny in $denies) {
                if (Test-SmbAccountMatch -SmbAccountName $deny.AccountName -ResolvedUser $resolvedUser) {
                    $rows.Add([pscustomobject]@{
                        Share = $share.Name
                        Path = $share.Path
                        AccountName = $deny.AccountName
                        AccessControlType = $deny.AccessControlType
                        AccessRight = $deny.AccessRight
                        MatchMethod = $resolvedUser.ResolutionMethod
                    })
                }
            }
        } catch {
            $rows.Add([pscustomobject]@{
                Share = $share.Name
                Path = $share.Path
                AccountName = $UserIdentity
                AccessControlType = 'Error'
                AccessRight = $_.Exception.Message
                MatchMethod = 'Error'
            })
        }
    }

    return [pscustomobject]@{ User = $resolvedUser; Rows = @($rows.ToArray()) }
}

function Unlock-SmbShareDeniedAccounts {
    param(
        [Parameter(Mandatory=$true)][string]$ShareName,
        [Parameter(Mandatory=$true)][string[]]$Accounts
    )

    if (-not (Test-CommandAvailable -CommandName 'Unblock-SmbShareAccess')) {
        throw 'Unblock-SmbShareAccess is not available. Run this tool on a Windows host with the SMBShare module available.'
    }

    $results = New-Object System.Collections.ArrayList
    foreach ($account in $Accounts) {
        try {
            Unblock-SmbShareAccess -Name $ShareName -AccountName $account -Force -ErrorAction Stop | Out-Null
            $results.Add([pscustomobject]@{ Account = $account; Share = $ShareName; Status = 'Unlocked'; Error = '' })
        } catch {
            $results.Add([pscustomobject]@{ Account = $account; Share = $ShareName; Status = 'Failed'; Error = $_.Exception.Message })
        }
    }
    return @($results)
}

function Get-AccountSmbShareAccess {
    param([Parameter(Mandatory=$true)][string]$AccountName)

    if (-not (Test-CommandAvailable -CommandName 'Get-SmbShareAccess')) {
        throw 'Get-SmbShareAccess is not available. Run this tool on a Windows host with the SMBShare module available.'
    }

    $resolvedUser = Resolve-AdUserAcrossForest -UserIdentity $AccountName
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($share in (Get-ManagedSmbShares)) {
        try {
            $accessRows = @(Get-SmbShareAccess -Name $share.Name -ErrorAction Stop | Where-Object { Test-SmbAccountMatch -SmbAccountName $_.AccountName -ResolvedUser $resolvedUser })
            foreach ($entry in $accessRows) {
                $rows.Add([pscustomobject]@{
                    Share = $share.Name
                    Path = $share.Path
                    AccountName = $entry.AccountName
                    AccessControlType = $entry.AccessControlType
                    AccessRight = $entry.AccessRight
                    MatchMethod = $resolvedUser.ResolutionMethod
                })
            }
        } catch {
            $rows.Add([pscustomobject]@{
                Share = $share.Name
                Path = $share.Path
                AccountName = $AccountName
                AccessControlType = 'Error'
                AccessRight = $_.Exception.Message
                MatchMethod = 'Error'
            })
        }
    }
    return @($rows.ToArray())
}

# =========================
# NTFS permission functions
# =========================
function Get-AdGroupsAcrossForest {
    [CmdletBinding()]
    param(
        [string]$FilterText = '*',
        [string]$DomainDns = ''
    )

    if (-not (Test-CommandAvailable -CommandName 'Get-ADGroup')) {
        throw 'Get-ADGroup is not available. Install or load the ActiveDirectory module, or enter a SID manually.'
    }

    $groups = New-Object System.Collections.Generic.List[object]
    $domains = @(if (-not [string]::IsNullOrWhiteSpace($DomainDns)) { $DomainDns } else { Get-ForestDomainsSafe })
    $domainCount = @($domains).Count
    if ($domainCount -eq 0) { throw 'Unable to determine Active Directory domains for group discovery.' }

    $filterRaw = $FilterText
    if ([string]::IsNullOrWhiteSpace($filterRaw)) { $filterRaw = '*' }
    $filterRaw = $filterRaw.Trim()

    foreach ($domain in $domains) {
        try {
            $query = '*'
            if ($filterRaw -ne '*') {
                # Same discovery posture as NEW-FindPermissions: locate by SamAccountName or Name.
                $safe = $filterRaw.Replace("'", "''")
                $query = "SamAccountName -like '*$safe*' -or Name -like '*$safe*'"
            }

            foreach ($g in @(Get-ADGroup -Filter $query -Server $domain -Properties SID,SamAccountName,DistinguishedName,Name -ResultSetSize 5000 -ErrorAction Stop)) {
                $domainLabel = $domain
                try {
                    $adDomain = Get-ADDomain -Server $domain -ErrorAction Stop
                    if (-not [string]::IsNullOrWhiteSpace($adDomain.NetBIOSName)) { $domainLabel = $adDomain.NetBIOSName }
                } catch { }

                $groups.Add([pscustomobject]@{
                    Display           = $g.SamAccountName
                    Name              = $g.Name
                    SamAccountName    = $g.SamAccountName
                    Domain            = $domain
                    DomainLabel       = $domainLabel
                    DistinguishedName = $g.DistinguishedName
                    Sid               = $g.SID.Value
                })
            }
        } catch {
            Write-Log -Level WARN -Message ("Unable to enumerate AD groups from domain '{0}'. {1}" -f $domain, $_.Exception.Message)
        }
    }

    $sortedGroups = @($groups.ToArray() | Sort-Object Domain, SamAccountName -Unique)
    return $sortedGroups
}

function Resolve-GroupIdentityToSid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$GroupIdentity,
        [string]$DomainDns = ''
    )

    $identity = $GroupIdentity.Trim()
    if ([string]::IsNullOrWhiteSpace($identity)) { throw 'Group identity cannot be empty.' }

    # Accept direct SID input exactly like the original scanner module.
    if ($identity -match '^S-\d-\d+-.+') {
        return [pscustomobject]@{
            Input = $identity
            Name = $identity
            SamAccountName = ''
            Domain = ''
            DistinguishedName = ''
            Sid = $identity
            ResolutionMethod = 'SID'
        }
    }

    # If the user selected a ComboBox item in the form "DOMAIN\sam | Name", keep only DOMAIN\sam.
    if ($identity -match '^(.+?)\s+\|') { $identity = $Matches[1].Trim() }

    if (Test-CommandAvailable -CommandName 'Get-ADGroup') {
        $candidate = $identity
        $explicitServer = $null

        # Same resolution technique used in NEW-FindPermissions:
        # - DOMAIN\Group overrides the selected domain and is passed to -Server.
        # - plain Group uses selected domain, then all available domains.
        # - DN is accepted by -Identity.
        if ($candidate -match '^(?<dom>[^\\]+)\\(?<name>.+)$') {
            $explicitServer = $Matches['dom']
            $candidate = $Matches['name']
        }

        $domains = New-Object System.Collections.Generic.List[string]
        if (-not [string]::IsNullOrWhiteSpace($explicitServer)) {
            $domains.Add($explicitServer)
        } elseif (-not [string]::IsNullOrWhiteSpace($DomainDns)) {
            $domains.Add($DomainDns)
        } else {
            foreach ($domain in @(Get-ForestDomainsSafe)) { $domains.Add($domain) }
        }

        if ($domains.Count -eq 0) { throw 'Unable to determine an Active Directory domain for group resolution.' }

        foreach ($domain in @($domains)) {
            try {
                $group = $null
                try {
                    $group = Get-ADGroup -Identity $candidate -Server $domain -Properties SID, DistinguishedName, Name, SamAccountName -ErrorAction Stop
                } catch {
                    $escaped = ConvertTo-LdapEscapedValue -Value $candidate
                    $group = Get-ADGroup -LDAPFilter "(|(sAMAccountName=$escaped)(name=$escaped))" -Server $domain -Properties SID, DistinguishedName, Name, SamAccountName -ErrorAction Stop | Select-Object -First 1
                }

                if ($null -ne $group) {
                    return [pscustomobject]@{
                        Input = $GroupIdentity
                        Name = $group.Name
                        SamAccountName = $group.SamAccountName
                        Domain = $domain
                        DistinguishedName = $group.DistinguishedName
                        Sid = $group.SID.Value
                        ResolutionMethod = 'ActiveDirectorySmartLookup'
                    }
                }
            } catch {
                Write-Log -Level DEBUG -Message ("Unable to resolve group '{0}' in domain/server '{1}'. {2}" -f $GroupIdentity, $domain, $_.Exception.Message)
            }
        }
    }

    # Last fallback: Windows account translation.
    try {
        $ntAccount = New-Object System.Security.Principal.NTAccount($identity)
        $sid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])
        return [pscustomobject]@{
            Input = $GroupIdentity
            Name = $identity
            SamAccountName = ''
            Domain = ''
            DistinguishedName = ''
            Sid = $sid.Value
            ResolutionMethod = 'NTAccount'
        }
    } catch {
        throw "Unable to resolve group identity '$GroupIdentity' to a SID. Use Group, DOMAIN\Group, distinguished name, or SID. $($_.Exception.Message)"
    }
}

function Convert-IdleStringToMinutes {
    param([string]$IdleString)
    if ([string]::IsNullOrWhiteSpace($IdleString)) { return 0 }
    $value = $IdleString.Trim()
    switch -Regex ($value) {
        '^(none|nenhum|\.)$' { return 0 }
        '^\d+$' { return [int]$value }
        '^\d+\+\d{1,2}:\d{2}$' {
            $parts = $value -split '\+'
            $hm = $parts[1] -split ':'
            return ([int]$parts[0] * 1440) + ([int]$hm[0] * 60) + [int]$hm[1]
        }
        '^\d{1,2}:\d{2}$' {
            $hm = $value -split ':'
            return ([int]$hm[0] * 60) + [int]$hm[1]
        }
        default { return 0 }
    }
}

function Get-LocalNtfsSharePaths {
    $rows = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    function Add-SharePathRow {
        param(
            [string]$Name,
            [string]$Path,
            [string]$Description,
            [string]$Source
        )

        if ([string]::IsNullOrWhiteSpace($Name) -or [string]::IsNullOrWhiteSpace($Path)) { return }
        if ($Name -match '^(ADMIN\$|IPC\$|PRINT\$)$') { return }
        if ($Name -match '^[A-Z]\$$') { return }
        if ($Path -notmatch '^[A-Za-z]:\\') { return }
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }

        $key = ("{0}|{1}" -f $Name, $Path)
        if (-not $seen.Add($key)) { return }

        $rows.Add([pscustomobject]@{
            Name = $Name
            LocalPath = $Path
            UncPath = ("\\{0}\{1}" -f $env:COMPUTERNAME, $Name)
            Description = $Description
            Source = $Source
        })
    }

    if (Test-CommandAvailable -CommandName 'Get-SmbShare') {
        try {
            foreach ($share in @(Get-SmbShare -ErrorAction Stop | Sort-Object Name)) {
                try {
                    if ($share.Special) { continue }
                    Add-SharePathRow -Name ([string]$share.Name) -Path ([string]$share.Path) -Description ([string]$share.Description) -Source 'Get-SmbShare'
                } catch {
                    Write-Log -Level DEBUG -Message ("Unable to evaluate SMB share '{0}' through Get-SmbShare. {1}" -f $share.Name, $_.Exception.Message)
                }
            }
        } catch {
            Write-Log -Level WARN -Message ("Unable to enumerate local SMB shares through Get-SmbShare. {0}" -f $_.Exception.Message)
        }
    }

    try {
        foreach ($share in @(Get-CimInstance -ClassName Win32_Share -ErrorAction Stop | Where-Object { $_.Type -eq 0 } | Sort-Object Name)) {
            try {
                Add-SharePathRow -Name ([string]$share.Name) -Path ([string]$share.Path) -Description ([string]$share.Description) -Source 'Win32_Share'
            } catch {
                Write-Log -Level DEBUG -Message ("Unable to evaluate SMB share '{0}' through Win32_Share. {1}" -f $share.Name, $_.Exception.Message)
            }
        }
    } catch {
        Write-Log -Level WARN -Message ("Unable to enumerate local SMB shares through Win32_Share. {0}" -f $_.Exception.Message)
    }

    return @($rows.ToArray() | Sort-Object Name, LocalPath -Unique)
}

function Get-FolderScanTargets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$RootPath,
        [bool]$Recurse,
        [int]$MaxDepth = 1
    )

    $root = [string]$RootPath
    if ([string]::IsNullOrWhiteSpace($root)) {
        throw 'Path not provided.'
    }

    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "Path not found or inaccessible: $root"
    }

    $targets = New-Object System.Collections.ArrayList
    $errors = New-Object System.Collections.ArrayList
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    function Add-TargetPath {
        param([string]$PathValue)
        if ([string]::IsNullOrWhiteSpace($PathValue)) { return }
        $normalizedPath = [string]$PathValue
        if ($seen.Add($normalizedPath)) {
            [void]$targets.Add($normalizedPath)
        }
    }

    $rootItem = Get-Item -LiteralPath $root -ErrorAction Stop
    Add-TargetPath -PathValue ([string]$rootItem.FullName)

    if (-not $Recurse) {
        try {
            $children = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction Stop)
            foreach ($folder in $children) {
                Add-TargetPath -PathValue ([string]$folder.FullName)
            }
        } catch {
            [void]$errors.Add([pscustomobject]@{ Path = $root; Stage = 'EnumerateFirstLevel'; Error = $_.Exception.Message })
        }
        return [pscustomobject]@{ Targets = @($targets.ToArray()); Errors = @($errors.ToArray()) }
    }

    $queue = New-Object System.Collections.Queue
    $queue.Enqueue([pscustomobject]@{ Path = [string]$rootItem.FullName; Depth = 0 })

    while ($queue.Count -gt 0) {
        $node = $queue.Dequeue()
        $nodePath = [string]$node.Path
        $nodeDepth = [int]$node.Depth
        if ($nodeDepth -ge $MaxDepth) { continue }

        try {
            $children = @(Get-ChildItem -LiteralPath $nodePath -Directory -ErrorAction Stop)
            foreach ($folder in $children) {
                $childPath = [string]$folder.FullName
                Add-TargetPath -PathValue $childPath
                $queue.Enqueue([pscustomobject]@{ Path = $childPath; Depth = ($nodeDepth + 1) })
            }
        } catch {
            [void]$errors.Add([pscustomobject]@{ Path = $nodePath; Stage = 'EnumerateRecursive'; Error = $_.Exception.Message })
        }
    }

    return [pscustomobject]@{ Targets = @($targets.ToArray()); Errors = @($errors.ToArray()) }
}

function Find-GroupNtfsPermissions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$FolderPath,
        [Parameter(Mandatory=$true)][string]$GroupSid
    )

    $folder = [string]$FolderPath
    $sid = [string]$GroupSid
    $rows = New-Object System.Collections.ArrayList

    try {
        $acl = Get-Acl -LiteralPath $folder -ErrorAction Stop

        # Use the Access collection instead of GetAccessRules(Type) to avoid
        # WinForms/PowerShell 5.1 overload issues that may surface as:
        # "argument types do not match" on some folders/providers.
        foreach ($rule in @($acl.Access)) {
            try {
                if ($null -eq $rule) { continue }
                if ($rule.AccessControlType.ToString() -ne 'Allow') { continue }

                $ruleSid = $null
                try {
                    if ($rule.IdentityReference -is [System.Security.Principal.SecurityIdentifier]) {
                        $ruleSid = [string]$rule.IdentityReference.Value
                    }
                    else {
                        $ruleSid = [string]($rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier])).Value
                    }
                } catch {
                    # If the identity cannot be translated, skip it safely.
                    continue
                }

                if ($ruleSid -eq $sid) {
                    [void]$rows.Add([pscustomobject]@{
                        FolderPath = [string]$folder
                        IdentitySid = [string]$ruleSid
                        AccessControlType = [string]$rule.AccessControlType.ToString()
                        FileSystemRights = [string]$rule.FileSystemRights.ToString()
                        IsInherited = [string]([bool]$rule.IsInherited)
                        InheritanceFlags = [string]$rule.InheritanceFlags.ToString()
                        PropagationFlags = [string]$rule.PropagationFlags.ToString()
                    })
                }
            } catch {
                # Continue scanning other ACEs on the same folder.
                continue
            }
        }
    } catch {
        throw $_
    }

    return @($rows.ToArray())
}

function Export-NtfsScanCsv {
    param([Parameter(Mandatory=$true)][object[]]$Rows)
    $path = Join-Path ([Environment]::GetFolderPath('MyDocuments')) ("NTFS_Group_Permissions_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $Rows | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
    return $path
}

function Export-NtfsScanTxt {
    param(
        [Parameter(Mandatory=$true)][object[]]$Rows,
        [object[]]$Errors = @(),
        [object]$ResolvedGroup,
        [string]$BasePath
    )

    $path = Join-Path ([Environment]::GetFolderPath('MyDocuments')) ("NTFS_Group_Permissions_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $content = New-Object System.Collections.Generic.List[string]
    $content.Add('============================================================')
    $content.Add('NTFS GROUP PERMISSION SCAN REPORT')
    $content.Add('============================================================')
    $content.Add(('Generated: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    $content.Add(('Group Input: {0}' -f $ResolvedGroup.Input))
    $content.Add(('Group Name: {0}' -f $ResolvedGroup.Name))
    $content.Add(('Group SID: {0}' -f $ResolvedGroup.Sid))
    $content.Add(('Base Path: {0}' -f $BasePath))
    $content.Add(('Matching ACE Rows: {0}' -f $Rows.Count))
    $content.Add(('Enumeration/ACL Errors: {0}' -f $Errors.Count))
    $content.Add('')
    $content.Add('MATCHING PERMISSIONS')
    $content.Add('------------------------------------------------------------')

    if ($Rows.Count -eq 0) {
        $content.Add('No matching NTFS Allow ACEs were found for this group SID.')
    } else {
        foreach ($row in $Rows) {
            $content.Add(('Folder: {0}' -f $row.FolderPath))
            $content.Add(('Rights: {0}' -f $row.FileSystemRights))
            $content.Add(('Inherited: {0}' -f $row.IsInherited))
            $content.Add(('InheritanceFlags: {0}' -f $row.InheritanceFlags))
            $content.Add(('PropagationFlags: {0}' -f $row.PropagationFlags))
            $content.Add('')
        }
    }

    if ($Errors.Count -gt 0) {
        $content.Add('SCAN ERRORS')
        $content.Add('------------------------------------------------------------')
        foreach ($err in $Errors) {
            $content.Add(('Path: {0} | Stage: {1} | Error: {2}' -f $err.Path, $err.Stage, $err.Error))
        }
    }

    $content | Set-Content -Path $path -Encoding UTF8
    return $path
}

# =========================
# GUI
# =========================
Write-Log -Message ("===== START {0} =====" -f $script:ScriptName)

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Manage SMB Share and NTFS Permissions'
$form.Size = New-Object System.Drawing.Size(1030, 720)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(1030, 720)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(10,10)
$tabs.Size = New-Object System.Drawing.Size(995,620)

# -------------------------
# Tab 1: SMB Share Access
# -------------------------
$tabSmb = New-Object System.Windows.Forms.TabPage
$tabSmb.Text = 'SMB Share Access'

# Section: SMB Share
$gbSmbShare = New-Object System.Windows.Forms.GroupBox
$gbSmbShare.Text = 'SMB Share'
$gbSmbShare.Location = New-Object System.Drawing.Point(10,5)
$gbSmbShare.Size = New-Object System.Drawing.Size(960,60)
$tabSmb.Controls.Add($gbSmbShare)

$gbSmbShare.Controls.Add((New-Label 'SMB Share:' 15 24 100 22))
$cmbShares = New-Object System.Windows.Forms.ComboBox
$cmbShares.Location = New-Object System.Drawing.Point(115,21)
$cmbShares.Size = New-Object System.Drawing.Size(390,24)
$cmbShares.DropDownStyle = 'DropDownList'
$gbSmbShare.Controls.Add($cmbShares)

$btnLoadShares = New-Button 'Load Shares' 520 18 130 30
$gbSmbShare.Controls.Add($btnLoadShares)

$btnLoadDenied = New-Button 'Load Denied for Share' 660 18 170 30
$gbSmbShare.Controls.Add($btnLoadDenied)

$progressSmb = New-Object System.Windows.Forms.ProgressBar
$progressSmb.Location = New-Object System.Drawing.Point(840,24)
$progressSmb.Size = New-Object System.Drawing.Size(105,18)
$progressSmb.Minimum = 0
$progressSmb.Maximum = 100
$progressSmb.Value = 0
$gbSmbShare.Controls.Add($progressSmb)

# Section: Denied AD Accounts
$gbDeniedAccounts = New-Object System.Windows.Forms.GroupBox
$gbDeniedAccounts.Text = 'Denied AD Accounts'
$gbDeniedAccounts.Location = New-Object System.Drawing.Point(10,75)
$gbDeniedAccounts.Size = New-Object System.Drawing.Size(960,195)
$tabSmb.Controls.Add($gbDeniedAccounts)

$clbDeniedAccounts = New-Object System.Windows.Forms.CheckedListBox
$clbDeniedAccounts.Location = New-Object System.Drawing.Point(15,25)
$clbDeniedAccounts.Size = New-Object System.Drawing.Size(420,155)
$clbDeniedAccounts.CheckOnClick = $true
$gbDeniedAccounts.Controls.Add($clbDeniedAccounts)

$btnUnlock = New-Button 'Unblock Selected' 450 25 170 34
$gbDeniedAccounts.Controls.Add($btnUnlock)

# Section: User AD Account
$gbUserAccount = New-Object System.Windows.Forms.GroupBox
$gbUserAccount.Text = 'User AD Account'
$gbUserAccount.Location = New-Object System.Drawing.Point(10,280)
$gbUserAccount.Size = New-Object System.Drawing.Size(960,205)
$tabSmb.Controls.Add($gbUserAccount)

$gbUserAccount.Controls.Add((New-Label 'Account:' 15 27 120 22))
$txtAccountReview = New-TextBox 135 24 345 24
$gbUserAccount.Controls.Add($txtAccountReview)

$btnFindBlocksByUser = New-Button 'Find Blocks by User' 495 20 185 34
$gbUserAccount.Controls.Add($btnFindBlocksByUser)

$btnReviewAccount = New-Button 'Load All Access' 690 20 140 34
$gbUserAccount.Controls.Add($btnReviewAccount)

$lvSmbAccess = New-Object System.Windows.Forms.ListView
$lvSmbAccess.Location = New-Object System.Drawing.Point(15,65)
$lvSmbAccess.Size = New-Object System.Drawing.Size(930,125)
$lvSmbAccess.View = 'Details'
$lvSmbAccess.FullRowSelect = $true
$lvSmbAccess.GridLines = $true
[void]$lvSmbAccess.Columns.Add('Share',120)
[void]$lvSmbAccess.Columns.Add('Path',280)
[void]$lvSmbAccess.Columns.Add('Account',190)
[void]$lvSmbAccess.Columns.Add('Type',100)
[void]$lvSmbAccess.Columns.Add('Right / Status',150)
[void]$lvSmbAccess.Columns.Add('Match',70)
$gbUserAccount.Controls.Add($lvSmbAccess)

$txtSmbLog = New-TextBox 15 500 950 70 $true
$txtSmbLog.ReadOnly = $true
$tabSmb.Controls.Add($txtSmbLog)

# -------------------------
# Tab 2: NTFS Group Permission Scanner
# -------------------------
$tabNtfs = New-Object System.Windows.Forms.TabPage
$tabNtfs.Text = 'NTFS Group Permission Scanner'

$tabNtfs.Controls.Add((New-Label 'Domain:' 15 18 120 22))
$cmbDomain = New-Object System.Windows.Forms.ComboBox
$cmbDomain.Location = New-Object System.Drawing.Point(135,15)
$cmbDomain.Size = New-Object System.Drawing.Size(300,24)
$cmbDomain.DropDownStyle = 'DropDownList'
$tabNtfs.Controls.Add($cmbDomain)

$btnLoadDomains = New-Button 'Load Domains' 445 12 120 30
$tabNtfs.Controls.Add($btnLoadDomains)

$tabNtfs.Controls.Add((New-Label 'Filter:' 575 18 45 22))
$txtGroupFilter = New-TextBox 620 15 170 24
$txtGroupFilter.Text = '*'
$tabNtfs.Controls.Add($txtGroupFilter)

$btnLoadGroups = New-Button 'Load AD Groups' 805 12 160 30
$tabNtfs.Controls.Add($btnLoadGroups)

$tabNtfs.Controls.Add((New-Label 'AD Group / SID:' 15 52 120 22))
$cmbGroup = New-Object System.Windows.Forms.ComboBox
$cmbGroup.Location = New-Object System.Drawing.Point(135,49)
$cmbGroup.Size = New-Object System.Drawing.Size(655,24)
$cmbGroup.DropDownStyle = 'DropDown'
$cmbGroup.AutoCompleteMode = 'SuggestAppend'
$cmbGroup.AutoCompleteSource = 'ListItems'
$tabNtfs.Controls.Add($cmbGroup)

$tabNtfs.Controls.Add((New-Label 'Path:' 15 86 120 22))
$cmbPath = New-Object System.Windows.Forms.ComboBox
$cmbPath.Location = New-Object System.Drawing.Point(135,83)
$cmbPath.Size = New-Object System.Drawing.Size(655,24)
$cmbPath.DropDownStyle = 'DropDown'
$tabNtfs.Controls.Add($cmbPath)

$btnLoadPaths = New-Button 'Load Local Share Paths' 805 80 160 30
$tabNtfs.Controls.Add($btnLoadPaths)

$chkRecurse = New-Object System.Windows.Forms.CheckBox
$chkRecurse.Text = 'Recurse'
$chkRecurse.Location = New-Object System.Drawing.Point(135,119)
$chkRecurse.Size = New-Object System.Drawing.Size(80,22)
$tabNtfs.Controls.Add($chkRecurse)

$tabNtfs.Controls.Add((New-Label 'Depth:' 225 121 45 22))
$numDepth = New-Object System.Windows.Forms.NumericUpDown
$numDepth.Location = New-Object System.Drawing.Point(270,118)
$numDepth.Size = New-Object System.Drawing.Size(55,24)
$numDepth.Minimum = 1
$numDepth.Maximum = 20
$numDepth.Value = 2
$tabNtfs.Controls.Add($numDepth)

$btnScan = New-Button 'Scan Permissions' 340 113 160 34
$tabNtfs.Controls.Add($btnScan)
$btnExportCsv = New-Button 'Export CSV' 510 113 120 34
$tabNtfs.Controls.Add($btnExportCsv)
$btnExportTxt = New-Button 'Export TXT' 640 113 120 34
$tabNtfs.Controls.Add($btnExportTxt)

$progressNtfs = New-Object System.Windows.Forms.ProgressBar
$progressNtfs.Location = New-Object System.Drawing.Point(775,122)
$progressNtfs.Size = New-Object System.Drawing.Size(190,18)
$progressNtfs.Minimum = 0
$progressNtfs.Maximum = 100
$progressNtfs.Value = 0
$tabNtfs.Controls.Add($progressNtfs)

$gridNtfs = New-Object System.Windows.Forms.DataGridView
$gridNtfs.Location = New-Object System.Drawing.Point(15,160)
$gridNtfs.Size = New-Object System.Drawing.Size(950,325)
$gridNtfs.AllowUserToAddRows = $false
$gridNtfs.AllowUserToDeleteRows = $false
$gridNtfs.AllowUserToResizeRows = $false
$gridNtfs.ReadOnly = $true
$gridNtfs.MultiSelect = $false
$gridNtfs.SelectionMode = 'FullRowSelect'
$gridNtfs.RowHeadersVisible = $false
$gridNtfs.AutoSizeColumnsMode = 'None'
Initialize-NtfsResultsGrid -Grid $gridNtfs
$tabNtfs.Controls.Add($gridNtfs)

$txtNtfsLog = New-TextBox 15 500 950 70 $true
$txtNtfsLog.ReadOnly = $true
$tabNtfs.Controls.Add($txtNtfsLog)

$tabs.Controls.Add($tabSmb)
$tabs.Controls.Add($tabNtfs)
$form.Controls.Add($tabs)

$btnClose = New-Button 'Close' 870 642 135 32
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)

# =========================
# Events
# =========================
$btnLoadShares.Add_Click({
    try {
        $progressSmb.Value = 10
        $cmbShares.Items.Clear()
        $shares = @(Get-ManagedSmbShares)
        foreach ($share in $shares) { [void]$cmbShares.Items.Add($share.Name) }
        if ($cmbShares.Items.Count -gt 0) { $cmbShares.SelectedIndex = 0 }
        $progressSmb.Value = 100
        Add-UiLog -TextBox $txtSmbLog -Message ("Loaded {0} SMB share(s)." -f $shares.Count)
    } catch {
        $progressSmb.Value = 0
        Add-UiLog -TextBox $txtNtfsLog -Level 'ERROR' -Message ("{0}: {1}" -f $_.Exception.GetType().FullName, $_.Exception.Message)
        Show-ErrorDialog $_.Exception.Message
    }
})

$btnLoadDenied.Add_Click({
    try {
        if ($null -eq $cmbShares.SelectedItem) { Show-Warning 'Select an SMB share first.'; return }
        $progressSmb.Value = 20
        $shareName = [string]$cmbShares.SelectedItem
        $clbDeniedAccounts.Items.Clear()
        $denied = @(Get-DeniedSmbShareUsers -ShareName $shareName)
        foreach ($entry in $denied) { [void]$clbDeniedAccounts.Items.Add($entry.AccountName) }
        $progressSmb.Value = 100
        Add-UiLog -TextBox $txtSmbLog -Message ("Loaded {0} denied account(s) for share '{1}'." -f $denied.Count, $shareName)
        if ($denied.Count -eq 0) { Show-Info "No denied accounts found for share '$shareName'." }
    } catch {
        $progressSmb.Value = 0
        Show-ErrorDialog $_.Exception.Message
    }
})

$btnFindBlocksByUser.Add_Click({
    try {
        $account = $txtAccountReview.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($account)) { Show-Warning 'Enter an account name to find SMB Deny blocks.'; return }

        $progressSmb.Value = 5
        $lvSmbAccess.Items.Clear()
        Add-UiLog -TextBox $txtSmbLog -Message ("Finding SMB Deny blocks for account '{0}' across local shares." -f $account)
        $result = Find-DeniedSmbShareEntriesByUser -UserIdentity $account
        $rows = @($result.Rows)
        $progressSmb.Value = 80

        foreach ($row in $rows) {
            $item = New-Object System.Windows.Forms.ListViewItem -ArgumentList @([string]$row.Share)
            [void]$item.SubItems.Add([string]$row.Path)
            [void]$item.SubItems.Add([string]$row.AccountName)
            [void]$item.SubItems.Add([string]$row.AccessControlType)
            [void]$item.SubItems.Add([string]$row.AccessRight)
            [void]$item.SubItems.Add([string]$row.MatchMethod)
            [void]$lvSmbAccess.Items.Add($item)
        }

        $progressSmb.Value = 100
        Add-UiLog -TextBox $txtSmbLog -Message ("Deny block search completed. Matches={0}; Resolution={1}." -f $rows.Count, $result.User.ResolutionMethod)
        if ($rows.Count -eq 0) { Show-Info ("No SMB Deny blocks found for account '{0}'." -f $account) }
    } catch {
        $progressSmb.Value = 0
        Show-ErrorDialog $_.Exception.Message
    }
})

$btnUnlock.Add_Click({
    try {
        if ($null -eq $cmbShares.SelectedItem) { Show-Warning 'Select an SMB share first.'; return }
        $shareName = [string]$cmbShares.SelectedItem
        $accounts = @($clbDeniedAccounts.CheckedItems | ForEach-Object { [string]$_ })
        if ($accounts.Count -eq 0) { Show-Warning 'Select at least one denied account to unblock.'; return }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            ("Unblock {0} account(s) from SMB share '{1}'?" -f $accounts.Count, $shareName),
            'Confirm SMB Access Change',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $progressSmb.Value = 20
        $results = @(Unlock-SmbShareDeniedAccounts -ShareName $shareName -Accounts $accounts)
        $progressSmb.Value = 80
        foreach ($result in $results) {
            Add-UiLog -TextBox $txtSmbLog -Message ("{0}: {1} on {2}. {3}" -f $result.Status, $result.Account, $result.Share, $result.Error) -Level ($(if ($result.Status -eq 'Unlocked') { 'INFO' } else { 'ERROR' }))
        }

        $progressSmb.Value = 100
        $btnLoadDenied.PerformClick()
    } catch {
        $progressSmb.Value = 0
        Show-ErrorDialog $_.Exception.Message
    }
})

$btnReviewAccount.Add_Click({
    try {
        $account = $txtAccountReview.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($account)) { Show-Warning 'Enter an account name to review.'; return }

        $progressSmb.Value = 5
        $lvSmbAccess.Items.Clear()
        $rows = @(Get-AccountSmbShareAccess -AccountName $account)
        $progressSmb.Value = 80
        foreach ($row in $rows) {
            $item = New-Object System.Windows.Forms.ListViewItem -ArgumentList @([string]$row.Share)
            [void]$item.SubItems.Add([string]$row.Path)
            [void]$item.SubItems.Add([string]$row.AccountName)
            [void]$item.SubItems.Add([string]$row.AccessControlType)
            [void]$item.SubItems.Add([string]$row.AccessRight)
            [void]$item.SubItems.Add([string]$row.MatchMethod)
            [void]$lvSmbAccess.Items.Add($item)
        }
        $progressSmb.Value = 100
        $rowCount = @($rows).Count
        $accessMessage = "Loaded {0} SMB access entry/entries for account '{1}'." -f $rowCount, $account
        Add-UiLog -TextBox $txtSmbLog -Message $accessMessage
        Show-Info $accessMessage
    } catch {
        $progressSmb.Value = 0
        Show-ErrorDialog $_.Exception.Message
    }
})

$btnLoadDomains.Add_Click({
    try {
        $progressNtfs.Value = 5
        $cmbDomain.Items.Clear()
        $script:LoadedDomainLookup = @{}
        Add-UiLog -TextBox $txtNtfsLog -Message 'Loading available Active Directory domains using forest-aware discovery.'
        $domains = @(Get-AdDomainInventory)
        foreach ($domain in $domains) {
            $domainDisplay = [string]$domain.Display
            if (-not $script:LoadedDomainLookup.ContainsKey($domainDisplay)) {
                $script:LoadedDomainLookup[$domainDisplay] = $domain
                [void]$cmbDomain.Items.Add($domainDisplay)
            }
        }
        if ($cmbDomain.Items.Count -gt 0) { $cmbDomain.SelectedIndex = 0 }
        $progressNtfs.Value = 100
        Add-UiLog -TextBox $txtNtfsLog -Message ("Loaded {0} domain scope item(s). Select a specific domain or keep all domains for group discovery." -f $domains.Count)
    } catch {
        $progressNtfs.Value = 0
        Add-UiLog -TextBox $txtNtfsLog -Message ("ERROR: {0}" -f $_.Exception.Message) -Level 'ERROR'
        Show-ErrorDialog $_.Exception.Message
    }
})

$btnLoadGroups.Add_Click({
    try {
        $progressNtfs.Value = 5
        $cmbGroup.Items.Clear()
        $script:LoadedGroupLookup = @{}
        $filter = $txtGroupFilter.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($filter)) { $filter = '*' }
        $selectedDomain = Get-DomainDnsFromComboText -ComboText $cmbDomain.Text
        $scopeDescription = Get-DomainSearchScopeDescription -DomainDns $selectedDomain
        Add-UiLog -TextBox $txtNtfsLog -Message ("Loading AD groups from {0}. Filter='{1}'." -f $scopeDescription, $filter)
        $groups = @(Get-AdGroupsAcrossForest -FilterText $filter -DomainDns $selectedDomain)
        $groupCount = @($groups).Count
        $i = 0
        foreach ($group in @($groups)) {
            $i++
            if ($groupCount -gt 0) { $progressNtfs.Value = [Math]::Min(95, [int](($i / $groupCount) * 95)) }
            $displayName = [string]$group.Display
            if (-not $script:LoadedGroupLookup.ContainsKey($displayName)) {
                $script:LoadedGroupLookup[$displayName] = New-Object System.Collections.Generic.List[object]
                [void]$cmbGroup.Items.Add($displayName)
            }
            $script:LoadedGroupLookup[$displayName].Add($group)
        }
        $progressNtfs.Value = 100
        Add-UiLog -TextBox $txtNtfsLog -Message ("Loaded {0} AD group(s) from {1}." -f $groupCount, $scopeDescription)
    } catch {
        $progressNtfs.Value = 0
        Show-ErrorDialog $_.Exception.Message
    }
})

$btnLoadPaths.Add_Click({
    try {
        $progressNtfs.Value = 10
        $cmbPath.Items.Clear()
        $paths = @(Get-LocalNtfsSharePaths)
        $script:LastSharePathInventory = $paths
        $script:LoadedSharePathLookup = @{}
        foreach ($p in $paths) {
            $shareName = [string]$p.Name
            if (-not $script:LoadedSharePathLookup.ContainsKey($shareName)) {
                $script:LoadedSharePathLookup[$shareName] = $p
                [void]$cmbPath.Items.Add($shareName)
            }
        }
        if ($cmbPath.Items.Count -gt 0) { $cmbPath.SelectedIndex = 0 }
        $progressNtfs.Value = 100
        Add-UiLog -TextBox $txtNtfsLog -Message ("Loaded {0} local NTFS-backed SMB/DFS share path(s)." -f $paths.Count)
    } catch {
        $progressNtfs.Value = 0
        Show-ErrorDialog $_.Exception.Message
    }
})

$btnScan.Add_Click({
    try {
        $groupInput = $cmbGroup.Text.Trim()
        $basePathInput = $cmbPath.Text.Trim()
        $basePath = $basePathInput
        if ($script:LoadedSharePathLookup -and $script:LoadedSharePathLookup.ContainsKey($basePathInput)) {
            $basePath = [string]$script:LoadedSharePathLookup[$basePathInput].LocalPath
        }
        elseif ($basePath -match '^.+?\s+\|\s+(.+)$') { $basePath = $Matches[1].Trim() }
        $selectedDomain = Get-DomainDnsFromComboText -ComboText $cmbDomain.Text
        if ([string]::IsNullOrWhiteSpace($groupInput)) { Show-Warning 'Enter or select an AD group, DOMAIN\Group, distinguished name, or SID.'; return }
        if ([string]::IsNullOrWhiteSpace($basePath)) { Show-Warning 'Enter or select a local/UNC path to scan.'; return }

        if ($script:LoadedGroupLookup.ContainsKey($groupInput)) {
            $matchingLoadedGroups = @($script:LoadedGroupLookup[$groupInput].ToArray())
            if ($matchingLoadedGroups.Count -eq 1) {
                $groupInput = [string]$matchingLoadedGroups[0].DistinguishedName
            }
            elseif ($matchingLoadedGroups.Count -gt 1 -and -not [string]::IsNullOrWhiteSpace($selectedDomain)) {
                $domainMatch = @($matchingLoadedGroups | Where-Object { $_.Domain -eq $selectedDomain })
                if ($domainMatch.Count -eq 1) {
                    $groupInput = [string]$domainMatch[0].DistinguishedName
                }
                else {
                    Show-Warning ("Multiple AD groups named '{0}' were found. Select a specific target domain or type DOMAIN\\Group." -f $groupInput)
                    return
                }
            }
            elseif ($matchingLoadedGroups.Count -gt 1) {
                Show-Warning ("Multiple AD groups named '{0}' were found across domains. Select a specific target domain or type DOMAIN\\Group." -f $groupInput)
                return
            }
        }

        if ($groupInput -match '^(.+?)\s+\|') {
            $groupInput = $Matches[1].Trim()
        }

        $gridNtfs.Rows.Clear()
        $progressNtfs.Value = 0
        Add-UiLog -TextBox $txtNtfsLog -Message ("Resolving group identity '{0}' using scope '{1}'." -f $groupInput, (Get-DomainSearchScopeDescription -DomainDns $selectedDomain))
        $resolved = Resolve-GroupIdentityToSid -GroupIdentity $groupInput -DomainDns $selectedDomain
        $script:LastResolvedGroup = $resolved
        $script:LastNtfsBasePath = $basePath
        Add-UiLog -TextBox $txtNtfsLog -Message ("Resolved group SID: {0} using {1}." -f $resolved.Sid, $resolved.ResolutionMethod)

        $basePath = [string]$basePath
        Add-UiLog -TextBox $txtNtfsLog -Message ("Scanning NTFS path '{0}'." -f $basePath)
        $targetInfo = Get-FolderScanTargets -RootPath $basePath -Recurse ([bool]$chkRecurse.Checked) -MaxDepth ([int]$numDepth.Value)
        $targets = @($targetInfo.Targets | ForEach-Object { [string]$_ })
        $errors = New-Object System.Collections.ArrayList
        foreach ($err in @($targetInfo.Errors)) { [void]$errors.Add($err) }
        Add-UiLog -TextBox $txtNtfsLog -Message ("Collected {0} folder target(s) for ACL scanning." -f $targets.Count)

        $results = New-Object System.Collections.ArrayList
        $index = 0
        foreach ($target in $targets) {
            $index++
            if ($targets.Count -gt 0) { $progressNtfs.Value = [Math]::Min(100, [int](($index / $targets.Count) * 100)) }
            [System.Windows.Forms.Application]::DoEvents()
            try {
                $matches = @(Find-GroupNtfsPermissions -FolderPath $target -GroupSid $resolved.Sid)
                foreach ($match in $matches) { [void]$results.Add($match) }
            } catch {
                [void]$errors.Add([pscustomobject]@{ Path = $target; Stage = 'ReadAcl'; Error = $_.Exception.Message })
            }
        }

        $script:LastNtfsScanResults = @($results.ToArray())
        $script:LastNtfsScanErrors = @($errors.ToArray())

        # DataGridView does not implement BeginUpdate()/EndUpdate().
        # SuspendLayout()/ResumeLayout() is the safe WinForms pattern here.
        $gridNtfs.SuspendLayout()
        try {
            $gridNtfs.Rows.Clear()
            foreach ($row in @($results.ToArray())) {
                Add-NtfsResultGridRow `
                    -Grid $gridNtfs `
                    -FolderPath $row.FolderPath `
                    -Rights $row.FileSystemRights `
                    -Inherited $row.IsInherited `
                    -Inheritance $row.InheritanceFlags `
                    -Propagation $row.PropagationFlags
            }
        }
        finally {
            $gridNtfs.ResumeLayout()
        }

        $progressNtfs.Value = 100
        Add-UiLog -TextBox $txtNtfsLog -Message ("Scan completed. Matches={0}; Errors={1}." -f $results.Count, $errors.Count)
        if ($results.Count -eq 0) { Show-Info 'Scan completed. No matching NTFS Allow ACEs were found for this group.' }
    } catch {
        $progressNtfs.Value = 0
        Show-ErrorDialog $_.Exception.Message
    }
})

$btnExportCsv.Add_Click({
    try {
        if ($script:LastNtfsScanResults.Count -eq 0) { Show-Warning 'No NTFS scan results are available to export.'; return }
        $path = Export-NtfsScanCsv -Rows $script:LastNtfsScanResults
        Add-UiLog -TextBox $txtNtfsLog -Message "CSV report exported to: $path"
        Show-Info "CSV report exported to:`n$path"
    } catch {
        Show-ErrorDialog $_.Exception.Message
    }
})

$btnExportTxt.Add_Click({
    try {
        if ($null -eq $script:LastResolvedGroup) { Show-Warning 'No NTFS scan context is available to export.'; return }
        $path = Export-NtfsScanTxt -Rows $script:LastNtfsScanResults -Errors $script:LastNtfsScanErrors -ResolvedGroup $script:LastResolvedGroup -BasePath $script:LastNtfsBasePath
        Add-UiLog -TextBox $txtNtfsLog -Message "TXT report exported to: $path"
        Show-Info "TXT report exported to:`n$path"
    } catch {
        Show-ErrorDialog $_.Exception.Message
    }
})

$form.Add_Shown({
    try { $btnLoadShares.PerformClick() } catch { }
})

try {
    [void]$form.ShowDialog()
} catch {
    Write-Log -Message ("Unhandled GUI error: {0}" -f $_.Exception.Message) -Level ERROR
    Show-ErrorDialog $_.Exception.Message
} finally {
    Write-Log -Message ("===== END {0} =====" -f $script:ScriptName)
    try { $form.Dispose() } catch { }
}

# End of script
