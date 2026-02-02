<#
.SYNOPSIS
    PowerShell Script for Managing Disabled and Expired AD User Accounts.

.DESCRIPTION
    This script provides a GUI to manage Active Directory user accounts:
    - Lists expired (enabled) accounts and disables selected accounts.
    - Lists disabled accounts (excluding built-in/system accounts and CN=Users).
    - Removes selected disabled users from all groups (cross-domain safe).
    - Disables accounts from manual input (comma-separated) or from a .txt file (one per line).
    - Exports a Disabled Accounts report to CSV in the current user's Documents folder.
    - Generates an append-only log file in C:\Logs-TEMP.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: 2026-02-02
#>

#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------- Hide Console ----------------------------
try {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() {
        var handle = GetConsoleWindow();
        ShowWindow(handle, 0); // 0 = SW_HIDE
    }
    public static void Show() {
        var handle = GetConsoleWindow();
        ShowWindow(handle, 5); // 5 = SW_SHOW
    }
}
"@ -ErrorAction Stop

    [Window]::Hide()
} catch {}

# ---------------------------- Modules / Assemblies ----------------------------
try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    [void][System.Windows.Forms.MessageBox]::Show(
        "Failed to load ActiveDirectory module (RSAT required).`n$($_.Exception.Message)",
        "Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------------------------- Logging ----------------------------
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir     = 'C:\Logs-TEMP'
$logPath    = Join-Path $logDir "${scriptName}.log"

if (-not (Test-Path -LiteralPath $logDir)) {
    try { New-Item -Path $logDir -ItemType Directory -Force | Out-Null } catch {}
}

if (-not (Test-Path -LiteralPath $logDir)) {
    [void][System.Windows.Forms.MessageBox]::Show(
        "Failed to create log directory at ${logDir}. Logging will not be possible.",
        "Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    exit 1
}

function Log-Message {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARNING','ERROR','SUCCESS')][string]$MessageType = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[${timestamp}] [${MessageType}] ${Message}"
    try { Add-Content -Path $logPath -Value $entry -Encoding UTF8 -ErrorAction Stop } catch {}
}

function Show-ErrorMessage {
    param([Parameter(Mandatory=$true)][string]$Message)
    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,
        "Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    Log-Message -Message "${Message}" -MessageType 'ERROR'
}

function Show-InfoMessage {
    param([Parameter(Mandatory=$true)][string]$Message)
    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,
        "Information",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
    Log-Message -Message "${Message}" -MessageType 'INFO'
}

Log-Message -Message "==== Session started ====" -MessageType 'INFO'
Log-Message -Message "LogPath: ${logPath}" -MessageType 'INFO'

# ---------------------------- Helpers ----------------------------

function Normalize-AccountInput {
    param([Parameter(Mandatory=$true)][string[]]$Names)
    @(
        $Names |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
}

function Get-ForestDomains {
    try {
        $forest  = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
        $domains = @($forest.Domains | ForEach-Object { $_.Name })
        return $domains
    } catch {
        Show-ErrorMessage -Message "Unable to fetch domain names in the forest."
        return @()
    }
}

function Get-DomainFqdnFromDistinguishedName {
    param([Parameter(Mandatory=$true)][string]$DistinguishedName)

    $matches = [regex]::Matches($DistinguishedName, '(?i)DC=([^,]+)')
    if (-not $matches -or $matches.Count -eq 0) { return $null }

    $dcs = @()
    foreach ($m in $matches) { $dcs += $m.Groups[1].Value }
    return ($dcs -join '.')
}

# ---------------------------- Expired Users ----------------------------

function List-ExpiredAccounts {
    param(
        [Parameter(Mandatory=$true)][string]$domainFQDN,
        [Parameter(Mandatory=$true)][System.Windows.Forms.ListView]$listView
    )

    $listView.Items.Clear()
    $currentDate = Get-Date

    try {
        $expiredUsers = @(
            Get-ADUser -Server $domainFQDN `
                -Filter { Enabled -eq $true -and AccountExpirationDate -lt $currentDate } `
                -Properties SamAccountName, DisplayName, AccountExpirationDate
        )
    } catch {
        Show-ErrorMessage -Message "Failed to query expired users on ${domainFQDN}.`n$($_.Exception.Message)"
        return
    }

    if (-not $expiredUsers -or $expiredUsers.Count -eq 0) {
        Show-InfoMessage -Message "There are no expired user accounts to list."
        return
    }

    foreach ($u in $expiredUsers) {
        $item = New-Object System.Windows.Forms.ListViewItem
        $item.Text = $u.SamAccountName

        $displayName    = if ($u.DisplayName) { $u.DisplayName } else { 'N/A' }
        $expirationDate = if ($u.AccountExpirationDate) { ([DateTime]$u.AccountExpirationDate).ToString('yyyy-MM-dd') } else { 'N/A' }

        $null = $item.SubItems.Add($displayName)
        $null = $item.SubItems.Add($expirationDate)
        $null = $listView.Items.Add($item)
    }

    Log-Message -Message "Listed expired users on ${domainFQDN}: $($expiredUsers.Count)" -MessageType 'SUCCESS'
}

function Disable-ExpiredAccounts {
    param(
        [Parameter(Mandatory=$true)][string]$domainFQDN,
        [Parameter(Mandatory=$true)][System.Windows.Forms.ListView]$listView
    )

    if ($listView.CheckedItems.Count -eq 0) {
        Show-ErrorMessage -Message "No accounts selected. Please select at least one account to disable."
        return
    }

    $disabledCount = 0

    foreach ($row in $listView.CheckedItems) {
        $samAccountName = [string]$row.Text
        if ([string]::IsNullOrWhiteSpace($samAccountName)) { continue }

        try {
            Disable-ADAccount -Identity $samAccountName -Server $domainFQDN -ErrorAction Stop
            $disabledCount++
            Log-Message -Message "Disabled expired account: ${samAccountName} (${domainFQDN})" -MessageType 'INFO'
        } catch {
            Log-Message -Message "Failed to disable expired account '${samAccountName}' on ${domainFQDN}: $($_.Exception.Message)" -MessageType 'ERROR'
        }
    }

    List-ExpiredAccounts -domainFQDN $domainFQDN -listView $listView
    Show-InfoMessage -Message "${disabledCount} expired account(s) have been disabled.`nLog file: ${logPath}"
}

# ---------------------------- Disabled Users ----------------------------

function List-DisabledAccounts {
    param(
        [Parameter(Mandatory=$true)][string]$domainFQDN,
        [Parameter(Mandatory=$true)][System.Windows.Forms.ListView]$listView
    )

    $listView.Items.Clear()

    $excludeAccounts = @('Administrator','Guest','krbtgt','DefaultAccount','WDAGUtilityAccount')

    try {
        $disabledUsers = @(
            Get-ADUser -Server $domainFQDN -Filter { Enabled -eq $false } `
                -Properties SamAccountName, DisplayName, DistinguishedName, whenChanged |
            Where-Object {
                ($excludeAccounts -notcontains $_.SamAccountName) -and
                ($_.DistinguishedName -notmatch '^CN=Users,')
            }
        )
    } catch {
        Show-ErrorMessage -Message "Failed to query disabled users on ${domainFQDN}.`n$($_.Exception.Message)"
        return
    }

    if (-not $disabledUsers -or $disabledUsers.Count -eq 0) {
        Show-InfoMessage -Message "No disabled user accounts found outside the 'CN=Users' container."
        return
    }

    foreach ($u in $disabledUsers) {
        $item = New-Object System.Windows.Forms.ListViewItem
        $item.Text = $u.SamAccountName

        $displayName = if ($u.DisplayName) { $u.DisplayName } else { 'N/A' }
        $lastChanged = if ($u.whenChanged) { ([DateTime]$u.whenChanged).ToString('yyyy-MM-dd') } else { 'N/A' }

        $null = $item.SubItems.Add($displayName)
        $null = $item.SubItems.Add($lastChanged)
        $null = $listView.Items.Add($item)
    }

    Log-Message -Message "Listed disabled users on ${domainFQDN}: $($disabledUsers.Count)" -MessageType 'SUCCESS'
}

function Remove-UserFromGroups-CrossDomainSafe {
    param(
        [Parameter(Mandatory=$true)][string]${SamAccountName},
        [Parameter(Mandatory=$true)][string]${UserDomainFqdn}
    )

    try {
        ${userObj} = Get-ADUser -Identity ${SamAccountName} -Server ${UserDomainFqdn} -Properties MemberOf, DistinguishedName -ErrorAction Stop
    }
    catch {
        Log-Message -Message "Failed to retrieve user '${SamAccountName}' on ${UserDomainFqdn}: $($_.Exception.Message)" -MessageType 'ERROR'
        return
    }

    if ($null -eq ${userObj}.MemberOf -or ${userObj}.MemberOf.Count -eq 0) {
        Log-Message -Message "User '${SamAccountName}' has no removable group memberships on ${UserDomainFqdn}." -MessageType 'INFO'
        return
    }

    ${userDn} = [string]${userObj}.DistinguishedName
    if ([string]::IsNullOrWhiteSpace(${userDn})) {
        Log-Message -Message "User '${SamAccountName}' has no DistinguishedName (unexpected). Skipping." -MessageType 'ERROR'
        return
    }

    foreach (${groupDN} in ${userObj}.MemberOf) {

        ${groupDomain} = Get-DomainFqdnFromDistinguishedName -DistinguishedName ${groupDN}
        if ([string]::IsNullOrWhiteSpace(${groupDomain})) {
            Log-Message -Message "Failed to resolve group domain from DN '${groupDN}' for user '${SamAccountName}'." -MessageType 'WARNING'
            continue
        }

        # Attempt 1: Remove using the user's DistinguishedName (cross-domain safe)
        try {
            Remove-ADGroupMember -Identity ${groupDN} -Members ${userDn} -Confirm:$false -Server ${groupDomain} -ErrorAction Stop
            Log-Message -Message "Removed '${SamAccountName}' from group '${groupDN}' (server: ${groupDomain}, member: DN)." -MessageType 'INFO'
            continue
        }
        catch {
            ${err1} = $_.Exception.Message

            if (${err1} -match "refer" -or ${err1} -match "referência" -or ${err1} -match "referral") {
                Log-Message -Message "Remove-ADGroupMember returned referral for '${SamAccountName}' from '${groupDN}' via ${groupDomain}. Using ADSI fallback." -MessageType 'INFO'
            }
            else {
                Log-Message -Message "Remove-ADGroupMember failed for '${SamAccountName}' from '${groupDN}' via ${groupDomain} (DN attempt): ${err1}" -MessageType 'WARNING'
            }

            # Attempt 2 (fallback): ADSI direct removal from group "member" attribute
            try {
                ${groupPath}  = "LDAP://${groupDN}"
                ${groupEntry} = [ADSI]${groupPath}

                # Safety check: only proceed if the user DN is actually present in the group's member list
                if (${groupEntry}.Properties["member"] -notcontains ${userDn}) {
                    Log-Message -Message "User '${SamAccountName}' is not a member of '${groupDN}' (already clean)." -MessageType 'INFO'
                    continue
                }

                ${groupEntry}.Properties["member"].Remove(${userDn}) | Out-Null
                ${groupEntry}.CommitChanges()

                Log-Message -Message "Removed '${SamAccountName}' from group '${groupDN}' via ADSI fallback (member DN removed)." -MessageType 'INFO'
            }
            catch {
                ${err2} = $_.Exception.Message
                Log-Message -Message "ADSI fallback failed to remove '${SamAccountName}' from group '${groupDN}': ${err2}" -MessageType 'ERROR'
            }
        }
    }
}

function On-RemoveFromGroupsClick {
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.ListView]$listView,
        [Parameter(Mandatory=$true)][System.Windows.Forms.ProgressBar]$progressBar,
        [Parameter(Mandatory=$true)][string]$domainFQDN
    )

    if ($listView.CheckedItems.Count -eq 0) {
        Show-ErrorMessage -Message "No accounts selected. Please select at least one account to remove from groups."
        return
    }

    $progressBar.Minimum = 0
    $progressBar.Maximum = $listView.CheckedItems.Count
    $progressBar.Value   = 0
    $progressBar.Step    = 1

    $i = 0
    foreach ($row in $listView.CheckedItems) {
        $i++
        $samAccountName = [string]$row.Text
        if ([string]::IsNullOrWhiteSpace($samAccountName)) { continue }

        Remove-UserFromGroups-CrossDomainSafe -SamAccountName $samAccountName -UserDomainFqdn $domainFQDN

        $progressBar.Value = [Math]::Min($i, $progressBar.Maximum)
        [System.Windows.Forms.Application]::DoEvents()
    }

    List-DisabledAccounts -domainFQDN $domainFQDN -listView $listView
    Show-InfoMessage -Message "Selected accounts have been removed from their groups.`nLog file: ${logPath}"
}

# ---------------------------- Disable Users (Input/File) ----------------------------

function Disable-UserAccountsFromList {
    param(
        [Parameter(Mandatory=$true)][string[]]$accountNames,
        [Parameter(Mandatory=$true)][string]$domainFQDN
    )

    $names = Normalize-AccountInput -Names $accountNames
    if (-not $names -or $names.Count -eq 0) {
        Show-ErrorMessage -Message "No valid account names provided."
        return
    }

    $disabled = 0
    foreach ($name in $names) {
        try {
            Disable-ADAccount -Identity $name -Server $domainFQDN -ErrorAction Stop
            $disabled++
            Log-Message -Message "Disabled account: ${name} (${domainFQDN})" -MessageType 'INFO'
        } catch {
            Log-Message -Message "Failed to disable '${name}' on ${domainFQDN}: $($_.Exception.Message)" -MessageType 'ERROR'
        }
    }

    Show-InfoMessage -Message "Disable operation completed.`nDisabled: ${disabled}`nLog file: ${logPath}"
}

function On-DisableUsersClick {
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.TextBox]$inputTextBox,
        [Parameter(Mandatory=$true)][string]$domainFQDN
    )

    $input = $inputTextBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($input) -or $input -eq 'Type a user account or a .txt file name with full path') {
        Show-ErrorMessage -Message "Please type one or more account names (comma-separated) or a .txt file path."
        return
    }

    $usernames = @()

    if ([System.IO.File]::Exists($input)) {
        try {
            $usernames = Get-Content -Path $input -ErrorAction Stop
            Log-Message -Message "Disabling users from file: ${input}" -MessageType 'INFO'
        } catch {
            Show-ErrorMessage -Message "Failed to read file: ${input}`n$($_.Exception.Message)"
            return
        }
    } else {
        $usernames = $input -split ','
        Log-Message -Message "Disabling users from manual input." -MessageType 'INFO'
    }

    Disable-UserAccountsFromList -accountNames $usernames -domainFQDN $domainFQDN
}

# ---------------------------- Export Disabled CSV ----------------------------

function Export-DisabledAccountsReportCsv {
    param(
        [Parameter(Mandatory=$true)][string]$DomainFqdn,
        [Parameter(Mandatory=$true)][string]$OutputFolder
    )

    try {
        if (-not (Test-Path -LiteralPath $OutputFolder)) {
            New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
        }

        $excludeAccounts = @('Administrator','Guest','krbtgt','DefaultAccount','WDAGUtilityAccount')

        $disabledUsers = @(
            Get-ADUser -Server $DomainFqdn -Filter { Enabled -eq $false } `
                -Properties SamAccountName, DisplayName, DistinguishedName, whenChanged |
            Where-Object {
                ($excludeAccounts -notcontains $_.SamAccountName) -and
                ($_.DistinguishedName -notmatch '^CN=Users,')
            } |
            Select-Object SamAccountName, DisplayName, whenChanged, DistinguishedName
        )

        $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
        $safeDomain = $DomainFqdn.Replace('.','-')
        $csvPath = Join-Path $OutputFolder "DisabledAccounts_${safeDomain}_${ts}.csv"

        $disabledUsers | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

        Log-Message -Message "Disabled accounts report exported: ${csvPath}" -MessageType 'SUCCESS'
        Show-InfoMessage -Message "Disabled accounts report exported:`n${csvPath}"
    } catch {
        Log-Message -Message "Failed to export disabled accounts report for ${DomainFqdn}: $($_.Exception.Message)" -MessageType 'ERROR'
        Show-ErrorMessage -Message "Failed to export disabled accounts report:`n$($_.Exception.Message)"
    }
}

# ---------------------------- GUI ----------------------------

function Show-GUI {
    ${domains} = Get-ForestDomains
    if (-not ${domains} -or ${domains}.Count -eq 0) {
        Show-ErrorMessage -Message "No domains found in the forest."
        return
    }

    ${form} = New-Object System.Windows.Forms.Form
    ${form}.Text = 'AD User Management'
    ${form}.Size = New-Object System.Drawing.Size(620, 700)
    ${form}.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    ${form}.FormBorderStyle = 'FixedSingle'
    ${form}.MaximizeBox = $false

    ${tabControl} = New-Object System.Windows.Forms.TabControl
    ${tabControl}.Size = New-Object System.Drawing.Size(580, 640)
    ${tabControl}.Location = New-Object System.Drawing.Point(10, 10)

    ${tabExpiredUsers} = New-Object System.Windows.Forms.TabPage
    ${tabExpiredUsers}.Text = 'Expired Users'

    ${tabDisabledUsers} = New-Object System.Windows.Forms.TabPage
    ${tabDisabledUsers}.Text = 'Disabled Users'

    # -------------------- GLOBAL TAB LAYOUT CONSTANTS --------------------
    ${uiLeft}     = 10
    ${uiTopPad}   = 10
    ${uiBtnTop}   = 50
    ${uiListTop}  = 90
    ${uiListW}    = 540
    ${uiGap}      = 10
    ${uiBtnH}     = 32

    # Three top buttons must fit into 540px:
    # 3*170 + 2*10 = 530 => safe inside 540
    ${uiBtnW}     = 170
    ${uiBtnX1}    = ${uiLeft}
    ${uiBtnX2}    = ${uiBtnX1} + ${uiBtnW} + ${uiGap}
    ${uiBtnX3}    = ${uiBtnX2} + ${uiBtnW} + ${uiGap}

    # Bottom-right action buttons aligned to list width
    ${uiActionBtnW} = 170
    ${uiActionX}    = ${uiLeft} + ${uiListW} - ${uiActionBtnW}

    # -------------------- DOMAIN DROPDOWNS (FULL WIDTH / NO TRUNCATION) --------------------
    ${domainComboBoxExpired} = New-Object System.Windows.Forms.ComboBox
    ${domainComboBoxExpired}.Size = New-Object System.Drawing.Size(${uiListW}, 30)
    ${domainComboBoxExpired}.Location = New-Object System.Drawing.Point(${uiLeft}, ${uiTopPad})
    ${domainComboBoxExpired}.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    ${domainComboBoxExpired}.Items.AddRange(${domains})
    ${domainComboBoxExpired}.SelectedIndex = 0
    ${tabExpiredUsers}.Controls.Add(${domainComboBoxExpired})

    ${domainComboBoxDisabled} = New-Object System.Windows.Forms.ComboBox
    ${domainComboBoxDisabled}.Size = New-Object System.Drawing.Size(${uiListW}, 30)
    ${domainComboBoxDisabled}.Location = New-Object System.Drawing.Point(${uiLeft}, ${uiTopPad})
    ${domainComboBoxDisabled}.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    ${domainComboBoxDisabled}.Items.AddRange(${domains})
    ${domainComboBoxDisabled}.SelectedIndex = 0
    ${tabDisabledUsers}.Controls.Add(${domainComboBoxDisabled})

    # ---------------- TAB 1: Expired Users ----------------

    ${listExpiredButton} = New-Object System.Windows.Forms.Button
    ${listExpiredButton}.Text     = 'List Expired Users'
    ${listExpiredButton}.Size     = New-Object System.Drawing.Size(${uiBtnW}, ${uiBtnH})
    ${listExpiredButton}.Location = New-Object System.Drawing.Point(${uiBtnX1}, ${uiBtnTop})
    ${tabExpiredUsers}.Controls.Add(${listExpiredButton})

    ${disableExpiredButton} = New-Object System.Windows.Forms.Button
    ${disableExpiredButton}.Text     = 'Disable Expired Users'
    ${disableExpiredButton}.Size     = New-Object System.Drawing.Size(${uiBtnW}, ${uiBtnH})
    ${disableExpiredButton}.Location = New-Object System.Drawing.Point(${uiBtnX2}, ${uiBtnTop})
    ${tabExpiredUsers}.Controls.Add(${disableExpiredButton})

    ${selectAllExpiredButton} = New-Object System.Windows.Forms.Button
    ${selectAllExpiredButton}.Text     = 'Select All Expired Users'
    ${selectAllExpiredButton}.Size     = New-Object System.Drawing.Size(${uiBtnW}, ${uiBtnH})
    ${selectAllExpiredButton}.Location = New-Object System.Drawing.Point(${uiBtnX3}, ${uiBtnTop})
    ${tabExpiredUsers}.Controls.Add(${selectAllExpiredButton})

    ${expiredListView} = New-Object System.Windows.Forms.ListView
    ${expiredListView}.Size = New-Object System.Drawing.Size(${uiListW}, 400)
    ${expiredListView}.Location = New-Object System.Drawing.Point(${uiLeft}, ${uiListTop})
    ${expiredListView}.View = [System.Windows.Forms.View]::Details
    ${expiredListView}.CheckBoxes = $true
    ${expiredListView}.FullRowSelect = $true
    ${expiredListView}.GridLines = $true
    [void]${expiredListView}.Columns.Add('SAM Account Name', 150)
    [void]${expiredListView}.Columns.Add('Display Name', 250)
    [void]${expiredListView}.Columns.Add('Expiration Date', 150)
    ${tabExpiredUsers}.Controls.Add(${expiredListView})

    ${listExpiredButton}.Add_Click({
        List-ExpiredAccounts -domainFQDN ${domainComboBoxExpired}.SelectedItem -listView ${expiredListView}
    })

    ${disableExpiredButton}.Add_Click({
        Disable-ExpiredAccounts -domainFQDN ${domainComboBoxExpired}.SelectedItem -listView ${expiredListView}
    })

    ${selectAllExpiredButton}.Add_Click({
        foreach (${it} in ${expiredListView}.Items) { ${it}.Checked = $true }
    })

    # ---------------- TAB 2: Disabled Users ----------------

    ${listDisabledButton} = New-Object System.Windows.Forms.Button
    ${listDisabledButton}.Text     = 'List Disabled Users'
    ${listDisabledButton}.Size     = New-Object System.Drawing.Size(${uiBtnW}, ${uiBtnH})
    ${listDisabledButton}.Location = New-Object System.Drawing.Point(${uiBtnX1}, ${uiBtnTop})
    ${tabDisabledUsers}.Controls.Add(${listDisabledButton})

    ${removeFromGroupsButton} = New-Object System.Windows.Forms.Button
    ${removeFromGroupsButton}.Text     = 'Remove from Groups'
    ${removeFromGroupsButton}.Size     = New-Object System.Drawing.Size(${uiBtnW}, ${uiBtnH})
    ${removeFromGroupsButton}.Location = New-Object System.Drawing.Point(${uiBtnX2}, ${uiBtnTop})
    ${tabDisabledUsers}.Controls.Add(${removeFromGroupsButton})

    ${selectAllDisabledButton} = New-Object System.Windows.Forms.Button
    ${selectAllDisabledButton}.Text     = 'Select All Disabled Users'
    ${selectAllDisabledButton}.Size     = New-Object System.Drawing.Size(${uiBtnW}, ${uiBtnH})
    ${selectAllDisabledButton}.Location = New-Object System.Drawing.Point(${uiBtnX3}, ${uiBtnTop})
    ${tabDisabledUsers}.Controls.Add(${selectAllDisabledButton})

    ${disabledListView} = New-Object System.Windows.Forms.ListView
    ${disabledListView}.Size = New-Object System.Drawing.Size(${uiListW}, 400)
    ${disabledListView}.Location = New-Object System.Drawing.Point(${uiLeft}, ${uiListTop})
    ${disabledListView}.View = [System.Windows.Forms.View]::Details
    ${disabledListView}.CheckBoxes = $true
    ${disabledListView}.FullRowSelect = $true
    ${disabledListView}.GridLines = $true
    [void]${disabledListView}.Columns.Add('SAM Account Name', 150)
    [void]${disabledListView}.Columns.Add('Display Name', 250)
    [void]${disabledListView}.Columns.Add('Last Changed', 150)
    ${tabDisabledUsers}.Controls.Add(${disabledListView})

    ${progressBar} = New-Object System.Windows.Forms.ProgressBar
    ${progressBar}.Size = New-Object System.Drawing.Size(${uiListW}, 20)
    ${progressBar}.Location = New-Object System.Drawing.Point(${uiLeft}, 500)
    ${progressBar}.Step = 1
    ${tabDisabledUsers}.Controls.Add(${progressBar})

    # Bottom row: textbox meets the Disable Users button with a 10px gap
    ${uiBottomTextY} = 530
    ${uiTextW}       = (${uiActionX} - ${uiLeft} - ${uiGap})

    ${inputTextBox} = New-Object System.Windows.Forms.TextBox
    ${inputTextBox}.Size = New-Object System.Drawing.Size(${uiTextW}, 20)
    ${inputTextBox}.Location = New-Object System.Drawing.Point(${uiLeft}, ${uiBottomTextY})
    ${inputTextBox}.Text = 'Type a user account or a .txt file name with full path'
    ${inputTextBox}.ForeColor = [System.Drawing.Color]::Gray
    ${tabDisabledUsers}.Controls.Add(${inputTextBox})

    ${inputTextBox}.Add_GotFocus({
        if (${inputTextBox}.Text -eq 'Type a user account or a .txt file name with full path') {
            ${inputTextBox}.Text = ''
            ${inputTextBox}.ForeColor = [System.Drawing.Color]::Black
        }
    })

    ${inputTextBox}.Add_LostFocus({
        if (${inputTextBox}.Text.Trim() -eq '') {
            ${inputTextBox}.Text = 'Type a user account or a .txt file name with full path'
            ${inputTextBox}.ForeColor = [System.Drawing.Color]::Gray
        }
    })

    ${disableUsersButton} = New-Object System.Windows.Forms.Button
    ${disableUsersButton}.Text     = 'Disable Users'
    ${disableUsersButton}.Size     = New-Object System.Drawing.Size(${uiActionBtnW}, ${uiBtnH})
    ${disableUsersButton}.Location = New-Object System.Drawing.Point(${uiActionX}, (${uiBottomTextY} - 5))
    ${tabDisabledUsers}.Controls.Add(${disableUsersButton})

    ${exportDisabledCsvButton} = New-Object System.Windows.Forms.Button
    ${exportDisabledCsvButton}.Text     = 'Export to CSV'
    ${exportDisabledCsvButton}.Size     = New-Object System.Drawing.Size(${uiActionBtnW}, ${uiBtnH})
    ${exportDisabledCsvButton}.Location = New-Object System.Drawing.Point(${uiActionX}, (${disableUsersButton}.Bottom + ${uiGap}))
    ${tabDisabledUsers}.Controls.Add(${exportDisabledCsvButton})

    ${listDisabledButton}.Add_Click({
        List-DisabledAccounts -domainFQDN ${domainComboBoxDisabled}.SelectedItem -listView ${disabledListView}
    })

    ${removeFromGroupsButton}.Add_Click({
        On-RemoveFromGroupsClick -listView ${disabledListView} -progressBar ${progressBar} -domainFQDN ${domainComboBoxDisabled}.SelectedItem
    })

    ${selectAllDisabledButton}.Add_Click({
        foreach (${it} in ${disabledListView}.Items) { ${it}.Checked = $true }
    })

    ${disableUsersButton}.Add_Click({
        On-DisableUsersClick -inputTextBox ${inputTextBox} -domainFQDN ${domainComboBoxDisabled}.SelectedItem
    })

    ${exportDisabledCsvButton}.Add_Click({
        ${docs} = [Environment]::GetFolderPath('MyDocuments')
        Export-DisabledAccountsReportCsv -DomainFqdn ${domainComboBoxDisabled}.SelectedItem -OutputFolder ${docs}
    })

    # Finalize
    ${tabControl}.TabPages.AddRange(@(${tabExpiredUsers}, ${tabDisabledUsers}))
    ${form}.Controls.Add(${tabControl})

    ${form}.Add_FormClosing({
        Log-Message -Message "==== Session ended ====" -MessageType 'INFO'
    })

    [System.Windows.Forms.Application]::Run(${form})
}

# Main
Show-GUI

# End of Script
