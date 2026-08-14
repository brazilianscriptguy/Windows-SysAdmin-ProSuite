<#
.SYNOPSIS
  Default Active Directory OU Structure Manager v2.0.0 Enterprise Edition.

.DESCRIPTION
  Enterprise Windows Forms tool for previewing, creating, and verifying a standardized
  Active Directory Organizational Unit structure.

  The tool:
  - Supports Windows PowerShell 5.1 and Windows Server 2019
  - Hides the PowerShell console before importing the ActiveDirectory module
  - Discovers all forest domains and explicitly targets the selected domain
  - Lists the domain root and existing OUs as possible parent locations
  - Provides client-side filtering across every displayed column
  - Provides ascending/descending sorting by clicking column headers
  - Uses Dry Run by default
  - Previews all planned OU operations before commit
  - Creates the parent OU and the standard child OUs idempotently
  - Preserves existing OUs instead of failing when they already exist
  - Protects newly created OUs from accidental deletion
  - Re-queries Active Directory after each creation to verify the resulting object
  - Produces timestamped audit logs in C:\Logs-TEMP
  - Uses explicit -Server targeting for all Active Directory operations

  Standard child OUs:
    - Computers
    - Printers
    - Groups
    - Users

.AUTHOR
  Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
  2026-08-14-v2.0.0-ENTERPRISE-EDITION

.REQUIREMENTS
  - Windows PowerShell 5.1
  - Windows Server 2019
  - RSAT ActiveDirectory PowerShell module
  - Network connectivity and permissions to query/modify the selected Active Directory domain
#>

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [switch]$ShowConsole
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# =====================================================================================
# Assemblies and process mode
# =====================================================================================
try {
    if (-not $ShowConsole) {
        try {
            Add-Type -Name Win32ShowWindowAsync -Namespace ConsoleControl -MemberDefinition @"
[DllImport("user32.dll")]
public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
[DllImport("kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
"@
            $consolePtr = [ConsoleControl.Win32ShowWindowAsync]::GetConsoleWindow()
            if ($consolePtr -ne [IntPtr]::Zero) {
                [void][ConsoleControl.Win32ShowWindowAsync]::ShowWindowAsync($consolePtr, 0)
            }
        } catch { }
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw 'The ActiveDirectory PowerShell module is not installed or available.'
    }

    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Error "Failed to initialize required components: $($_.Exception.Message)"
    return
}

# =====================================================================================
# Globals
# =====================================================================================
$script:ScriptName       = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:LogRoot          = 'C:\Logs-TEMP'
$script:RunStamp         = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:LogFile          = Join-Path $script:LogRoot "$($script:ScriptName)-$($script:RunStamp).log"
$script:StandardChildOUs = @('Computers', 'Printers', 'Groups', 'Users')

$script:CurrentDomain    = $null
$script:TargetLocations  = @()
$script:DisplayedTargets = @()
$script:SortColumn       = -1
$script:SortDescending   = $false

$script:listViewTargets  = $null
$script:txtLog           = $null
$script:statusMain       = $null
$script:statusMode       = $null
$script:chkDryRun        = $null

if (-not (Test-Path -LiteralPath $script:LogRoot)) {
    New-Item -ItemType Directory -Path $script:LogRoot -Force | Out-Null
}

# =====================================================================================
# Basic helpers
# =====================================================================================
function Write-AppLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO','SUCCESS','WARN','ERROR')][string]$Level = 'INFO'
    )

    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message

    try {
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Warning "Unable to write log file: $($_.Exception.Message)"
    }

    if ($script:txtLog -and -not $script:txtLog.IsDisposed) {
        $script:txtLog.AppendText($line + [Environment]::NewLine)
        $script:txtLog.SelectionStart = $script:txtLog.Text.Length
        $script:txtLog.ScrollToCaret()
    } elseif ($ShowConsole) {
        Write-Host $line
    }
}

function Show-AppMessage {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Information','Warning','Error')][string]$Type = 'Information'
    )

    switch ($Type) {
        'Error' {
            Write-AppLog -Message $Message -Level ERROR
            [void][System.Windows.Forms.MessageBox]::Show(
                $Message, 'Error',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
        'Warning' {
            Write-AppLog -Message $Message -Level WARN
            [void][System.Windows.Forms.MessageBox]::Show(
                $Message, 'Warning',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
        }
        default {
            Write-AppLog -Message $Message -Level INFO
            [void][System.Windows.Forms.MessageBox]::Show(
                $Message, 'Information',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
    }
}

function Set-AppStatus {
    param([Parameter(Mandatory = $true)][string]$Text)

    if ($script:statusMain -and -not $script:statusMain.IsDisposed) {
        $script:statusMain.Text = $Text
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Get-ExecutionModeLabel {
    if ($script:chkDryRun -and -not $script:chkDryRun.IsDisposed -and $script:chkDryRun.Checked) {
        return 'DRY RUN'
    }
    return 'COMMIT'
}

function ConvertTo-LdapFilterValue {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    # Explicit string overloads are required to avoid String.Replace(char,char)
    # overload ambiguity under Windows PowerShell 5.1.
    $escaped = $Value.Replace([string]'\', [string]'\5c')
    $escaped = $escaped.Replace([string]'*', [string]'\2a')
    $escaped = $escaped.Replace([string]'(', [string]'\28')
    $escaped = $escaped.Replace([string]')', [string]'\29')
    $escaped = $escaped.Replace([string][char]0, [string]'\00')
    return $escaped
}

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

# =====================================================================================
# Active Directory discovery and validation
# =====================================================================================
function Get-ForestDomains {
    try {
        $forest = Get-ADForest -ErrorAction Stop
        return @($forest.Domains | Sort-Object)
    } catch {
        throw "Unable to discover Active Directory forest domains. $($_.Exception.Message)"
    }
}

function Get-DomainContext {
    param([Parameter(Mandatory = $true)][string]$Server)

    try {
        return Get-ADDomain -Server $Server -ErrorAction Stop
    } catch {
        throw "Unable to query domain '$Server'. $($_.Exception.Message)"
    }
}

function Get-TargetLocations {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Server)

    $domain = Get-DomainContext -Server $Server

    $locations = New-Object System.Collections.ArrayList

    [void]$locations.Add([pscustomobject]@{
        Name                      = $domain.DNSRoot
        Type                      = 'Domain Root'
        DistinguishedName         = $domain.DistinguishedName
        ProtectedFromDeletion     = 'N/A'
        ObjectGUID                = $null
    })

    $ous = @(
        Get-ADOrganizationalUnit -Server $Server -Filter * `
            -Properties ProtectedFromAccidentalDeletion, ObjectGUID `
            -ErrorAction Stop |
        Sort-Object DistinguishedName
    )

    foreach ($ou in $ous) {
        [void]$locations.Add([pscustomobject]@{
            Name                  = [string]$ou.Name
            Type                  = 'OU'
            DistinguishedName     = [string]$ou.DistinguishedName
            ProtectedFromDeletion = [string]$ou.ProtectedFromAccidentalDeletion
            ObjectGUID            = [Guid]$ou.ObjectGUID
        })
    }

    Write-AppLog -Message ("Loaded target locations from '{0}': DomainRoot=1; OUs={1}" -f $Server, $ous.Count) -Level SUCCESS
    return @($locations)
}

function Test-TargetLocationStillExists {
    param(
        [Parameter(Mandatory = $true)]$Target,
        [Parameter(Mandatory = $true)][string]$Server
    )

    if ($Target.Type -eq 'Domain Root') {
        $domain = Get-DomainContext -Server $Server
        return ($domain.DistinguishedName -eq $Target.DistinguishedName)
    }

    try {
        $current = Get-ADOrganizationalUnit -Identity $Target.DistinguishedName -Server $Server `
            -Properties ObjectGUID -ErrorAction Stop
        return ([Guid]$current.ObjectGUID -eq [Guid]$Target.ObjectGUID)
    } catch {
        return $false
    }
}

function Get-ExistingChildOU {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Server
    )

    $escaped = ConvertTo-LdapFilterValue -Value $Name
    $matches = @(
        Get-ADOrganizationalUnit -Server $Server `
            -SearchBase $Path `
            -SearchScope OneLevel `
            -LDAPFilter "(ou=$escaped)" `
            -Properties ProtectedFromAccidentalDeletion, ObjectGUID `
            -ErrorAction Stop
    )

    if ($matches.Count -gt 1) {
        throw "More than one immediate child OU named '$Name' was returned under '$Path'."
    }

    if ($matches.Count -eq 1) {
        return $matches[0]
    }

    return $null
}

function Test-OUName {
    param([Parameter(Mandatory = $true)][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    # AD DS supports a broad range of RDN characters; reject only values that are
    # operationally unsafe or meaningless for this management tool.
    if ($Name.Trim().Length -gt 64) {
        return $false
    }

    if ($Name.IndexOf([char]0) -ge 0) {
        return $false
    }

    return $true
}

# =====================================================================================
# Searchable / sortable target browser
# =====================================================================================
function Set-TargetListViewData {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Targets
    )

    $script:listViewTargets.BeginUpdate()
    try {
        $script:listViewTargets.Items.Clear()

        foreach ($target in $Targets) {
            $item = New-Object System.Windows.Forms.ListViewItem([string]$target.Name)
            [void]$item.SubItems.Add([string]$target.Type)
            [void]$item.SubItems.Add([string]$target.DistinguishedName)
            [void]$item.SubItems.Add([string]$target.ProtectedFromDeletion)
            $item.Tag = $target
            [void]$script:listViewTargets.Items.Add($item)
        }
    } finally {
        $script:listViewTargets.EndUpdate()
    }
}

function Test-TargetMatchesFilter {
    param(
        [Parameter(Mandatory = $true)]$Target,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$FilterText
    )

    if ([string]::IsNullOrWhiteSpace($FilterText)) {
        return $true
    }

    $needle = $FilterText.Trim()
    $values = @(
        [string]$Target.Name,
        [string]$Target.Type,
        [string]$Target.DistinguishedName,
        [string]$Target.ProtectedFromDeletion
    )

    foreach ($value in $values) {
        if ($null -ne $value -and
            $value.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }

    return $false
}

function Apply-TargetFilter {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$FilterText)

    $selectedDn = $null
    if ($script:listViewTargets.SelectedItems.Count -gt 0 -and
        $null -ne $script:listViewTargets.SelectedItems[0].Tag) {
        $selectedDn = [string]$script:listViewTargets.SelectedItems[0].Tag.DistinguishedName
    }

    $filtered = @(
        $script:TargetLocations | Where-Object {
            Test-TargetMatchesFilter -Target $_ -FilterText $FilterText
        }
    )

    $script:DisplayedTargets = $filtered
    Set-TargetListViewData -Targets $filtered

    if ($selectedDn) {
        foreach ($item in $script:listViewTargets.Items) {
            if ($null -ne $item.Tag -and
                [string]$item.Tag.DistinguishedName -eq $selectedDn) {
                $item.Selected = $true
                $item.Focused = $true
                $item.EnsureVisible()
                break
            }
        }
    }

    Set-AppStatus ("Displayed {0} of {1} target location(s)." -f
        $filtered.Count, $script:TargetLocations.Count)
}

function Sort-TargetLocations {
    param(
        [Parameter(Mandatory = $true)][int]$ColumnIndex,
        [Parameter(Mandatory = $true)][bool]$Descending
    )

    switch ($ColumnIndex) {
        0 { $property = 'Name' }
        1 { $property = 'Type' }
        2 { $property = 'DistinguishedName' }
        3 { $property = 'ProtectedFromDeletion' }
        default { $property = 'Name' }
    }

    $script:TargetLocations = @(
        $script:TargetLocations |
        Sort-Object -Property $property -Descending:$Descending
    )
}

function Get-SelectedTarget {
    if ($script:listViewTargets.SelectedItems.Count -ne 1) {
        return $null
    }

    return $script:listViewTargets.SelectedItems[0].Tag
}

# =====================================================================================
# Preview / commit / verification
# =====================================================================================
function New-OUStructurePreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Target,
        [Parameter(Mandatory = $true)][string]$ParentOUName,
        [Parameter(Mandatory = $true)][string]$Server
    )

    if (-not (Test-TargetLocationStillExists -Target $Target -Server $Server)) {
        throw 'The selected target location no longer matches the object discovered during refresh. Refresh the list and select it again.'
    }

    $preview = New-Object System.Collections.ArrayList

    $existingParent = Get-ExistingChildOU -Name $ParentOUName -Path $Target.DistinguishedName -Server $Server

    if ($null -ne $existingParent) {
        $parentStatus = 'EXISTS'
        $parentDn = [string]$existingParent.DistinguishedName
        $parentGuid = [Guid]$existingParent.ObjectGUID
        $parentDetail = 'Existing parent OU will be preserved.'
    } else {
        $parentStatus = 'CREATE'
        $parentDn = '(created during commit)'
        $parentGuid = $null
        $parentDetail = 'Parent OU does not exist and will be created.'
    }

    [void]$preview.Add([pscustomobject]@{
        Level      = 'Parent'
        Name       = $ParentOUName
        ParentPath = $Target.DistinguishedName
        Status     = $parentStatus
        ResultDN   = $parentDn
        ObjectGUID = $parentGuid
        Detail     = $parentDetail
    })

    # Child state can only be queried immediately if the parent already exists.
    foreach ($child in $script:StandardChildOUs) {
        if ($null -ne $existingParent) {
            $existingChild = Get-ExistingChildOU -Name $child -Path $existingParent.DistinguishedName -Server $Server
            if ($null -ne $existingChild) {
                [void]$preview.Add([pscustomobject]@{
                    Level      = 'Child'
                    Name       = $child
                    ParentPath = $existingParent.DistinguishedName
                    Status     = 'EXISTS'
                    ResultDN   = [string]$existingChild.DistinguishedName
                    ObjectGUID = [Guid]$existingChild.ObjectGUID
                    Detail     = 'Existing child OU will be preserved.'
                })
            } else {
                [void]$preview.Add([pscustomobject]@{
                    Level      = 'Child'
                    Name       = $child
                    ParentPath = $existingParent.DistinguishedName
                    Status     = 'CREATE'
                    ResultDN   = '(created during commit)'
                    ObjectGUID = $null
                    Detail     = 'Child OU does not exist and will be created.'
                })
            }
        } else {
            [void]$preview.Add([pscustomobject]@{
                Level      = 'Child'
                Name       = $child
                ParentPath = "(new parent: $ParentOUName)"
                Status     = 'CREATE'
                ResultDN   = '(created during commit)'
                ObjectGUID = $null
                Detail     = 'Child OU will be evaluated after the parent OU is created.'
            })
        }
    }

    return @($preview)
}

function Show-PreviewDialog {
    param(
        [Parameter(Mandatory = $true)][object[]]$Preview,
        [Parameter(Mandatory = $true)][string]$Mode
    )

    $createCount = @($Preview | Where-Object { $_.Status -eq 'CREATE' }).Count
    $existsCount = @($Preview | Where-Object { $_.Status -eq 'EXISTS' }).Count

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Execution mode : $Mode")
    $lines.Add("Create         : $createCount")
    $lines.Add("Already exists : $existsCount")
    $lines.Add('')
    $lines.Add(("{0,-8} {1,-24} {2,-8} {3}" -f 'LEVEL','NAME','STATUS','PARENT PATH'))
    $lines.Add(('-' * 110))

    foreach ($entry in $Preview) {
        $lines.Add(("{0,-8} {1,-24} {2,-8} {3}" -f
            $entry.Level, $entry.Name, $entry.Status, $entry.ParentPath))
    }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'OU Structure Preview'
    $dialog.Size = New-Object System.Drawing.Size(960, 540)
    $dialog.StartPosition = 'CenterParent'
    $dialog.MinimizeBox = $false
    $dialog.MaximizeBox = $false

    $box = New-Object System.Windows.Forms.TextBox
    $box.Multiline = $true
    $box.ReadOnly = $true
    $box.ScrollBars = 'Both'
    $box.WordWrap = $false
    $box.Font = New-Object System.Drawing.Font('Consolas', 9)
    $box.Dock = 'Fill'
    $box.Text = ($lines -join [Environment]::NewLine)
    $dialog.Controls.Add($box)

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Height = 45
    $panel.Dock = 'Bottom'

    $close = New-Object System.Windows.Forms.Button
    $close.Text = 'Close'
    $close.Width = 100
    $close.Height = 28
    $close.Left = 825
    $close.Top = 8
    $close.Anchor = 'Right,Top'
    $close.Add_Click({ $dialog.Close() })
    $panel.Controls.Add($close)
    $dialog.Controls.Add($panel)

    [void]$dialog.ShowDialog()
}

function Ensure-OrganizationalUnit {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Server
    )

    $existing = Get-ExistingChildOU -Name $Name -Path $Path -Server $Server
    if ($null -ne $existing) {
        Write-AppLog -Message "Preserved existing OU '$($existing.DistinguishedName)'." -Level INFO
        return [pscustomobject]@{
            Name              = $Name
            Result            = 'EXISTS'
            DistinguishedName = [string]$existing.DistinguishedName
            ObjectGUID        = [Guid]$existing.ObjectGUID
            Detail            = 'OU already existed; no change required.'
        }
    }

    $target = "$Name under $Path"
    $action = 'Create protected Active Directory Organizational Unit'

    if (-not $PSCmdlet.ShouldProcess($target, $action)) {
        return [pscustomobject]@{
            Name              = $Name
            Result            = 'SKIPPED'
            DistinguishedName = $null
            ObjectGUID        = $null
            Detail            = 'ShouldProcess declined the operation.'
        }
    }

    try {
        $created = New-ADOrganizationalUnit -Name $Name -Path $Path -Server $Server `
            -ProtectedFromAccidentalDeletion $true -PassThru -ErrorAction Stop

        $verified = Get-ADOrganizationalUnit -Identity $created.DistinguishedName -Server $Server `
            -Properties ProtectedFromAccidentalDeletion, ObjectGUID -ErrorAction Stop

        if ([string]$verified.Name -ne $Name) {
            throw "Verification failed. Returned OU name '$($verified.Name)' does not match '$Name'."
        }

        if (-not $verified.ProtectedFromAccidentalDeletion) {
            throw 'Verification failed. The OU is not protected from accidental deletion.'
        }

        Write-AppLog -Message ("Created and verified OU '{0}' on '{1}'." -f
            $verified.DistinguishedName, $Server) -Level SUCCESS

        return [pscustomobject]@{
            Name              = $Name
            Result            = 'SUCCESS'
            DistinguishedName = [string]$verified.DistinguishedName
            ObjectGUID        = [Guid]$verified.ObjectGUID
            Detail            = 'OU created and verified.'
        }
    } catch {
        Write-AppLog -Message "Failed to create OU '$Name' under '$Path': $($_.Exception.Message)" -Level ERROR
        return [pscustomobject]@{
            Name              = $Name
            Result            = 'FAILED'
            DistinguishedName = $null
            ObjectGUID        = $null
            Detail            = $_.Exception.Message
        }
    }
}

function Invoke-OUStructureCreation {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]$Target,
        [Parameter(Mandatory = $true)][string]$ParentOUName,
        [Parameter(Mandatory = $true)][string]$Server
    )

    $results = New-Object System.Collections.ArrayList

    if (-not (Test-TargetLocationStillExists -Target $Target -Server $Server)) {
        [void]$results.Add([pscustomobject]@{
            Level  = 'Parent'
            Name   = $ParentOUName
            Result = 'FAILED'
            Detail = 'Selected target location changed or no longer exists. Refresh required.'
        })
        return @($results)
    }

    $parentResult = Ensure-OrganizationalUnit -Name $ParentOUName `
        -Path $Target.DistinguishedName -Server $Server -Confirm:$false

    [void]$results.Add([pscustomobject]@{
        Level  = 'Parent'
        Name   = $ParentOUName
        Result = $parentResult.Result
        Detail = $parentResult.Detail
    })

    if ($parentResult.Result -in @('FAILED','SKIPPED') -or
        [string]::IsNullOrWhiteSpace([string]$parentResult.DistinguishedName)) {
        foreach ($child in $script:StandardChildOUs) {
            [void]$results.Add([pscustomobject]@{
                Level  = 'Child'
                Name   = $child
                Result = 'SKIPPED'
                Detail = 'Parent OU was not available.'
            })
        }
        return @($results)
    }

    foreach ($child in $script:StandardChildOUs) {
        $childResult = Ensure-OrganizationalUnit -Name $child `
            -Path $parentResult.DistinguishedName -Server $Server -Confirm:$false

        [void]$results.Add([pscustomobject]@{
            Level  = 'Child'
            Name   = $child
            Result = $childResult.Result
            Detail = $childResult.Detail
        })
    }

    return @($results)
}

# =====================================================================================
# GUI
# =====================================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Default AD OU Structure Manager - Enterprise Edition'
$form.Size = New-Object System.Drawing.Size(1080, 760)
$form.MinimumSize = New-Object System.Drawing.Size(920, 680)
$form.StartPosition = 'CenterScreen'

$main = New-Object System.Windows.Forms.TableLayoutPanel
$main.Dock = 'Fill'
$main.Padding = New-Object System.Windows.Forms.Padding(10)
$main.ColumnCount = 1
$main.RowCount = 8
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 60)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 40)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$form.Controls.Add($main)

$domainPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$domainPanel.Dock = 'Fill'
$domainPanel.AutoSize = $true
$domainPanel.WrapContents = $false

$labelDomain = New-Object System.Windows.Forms.Label
$labelDomain.Text = 'Domain:'
$labelDomain.AutoSize = $true
$labelDomain.Margin = New-Object System.Windows.Forms.Padding(3, 7, 3, 3)
$domainPanel.Controls.Add($labelDomain)

$comboDomain = New-Object System.Windows.Forms.ComboBox
$comboDomain.Width = 340
$comboDomain.DropDownStyle = 'DropDownList'
$domainPanel.Controls.Add($comboDomain)

$buttonRefresh = New-Object System.Windows.Forms.Button
$buttonRefresh.Text = 'Refresh Targets'
$buttonRefresh.Width = 120
$domainPanel.Controls.Add($buttonRefresh)

$chkDryRun = New-Object System.Windows.Forms.CheckBox
$chkDryRun.Text = 'Dry Run'
$chkDryRun.Checked = $true
$chkDryRun.AutoSize = $true
$chkDryRun.Margin = New-Object System.Windows.Forms.Padding(25, 6, 3, 3)
$script:chkDryRun = $chkDryRun
$domainPanel.Controls.Add($chkDryRun)

$main.Controls.Add($domainPanel, 0, 0)

$filterPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$filterPanel.Dock = 'Fill'
$filterPanel.AutoSize = $true
$filterPanel.WrapContents = $false

$labelFilter = New-Object System.Windows.Forms.Label
$labelFilter.Text = 'Filter displayed columns:'
$labelFilter.AutoSize = $true
$labelFilter.Margin = New-Object System.Windows.Forms.Padding(3, 7, 3, 3)
$filterPanel.Controls.Add($labelFilter)

$textFilter = New-Object System.Windows.Forms.TextBox
$textFilter.Width = 520
$filterPanel.Controls.Add($textFilter)

$buttonClearFilter = New-Object System.Windows.Forms.Button
$buttonClearFilter.Text = 'Clear Filter'
$buttonClearFilter.Width = 100
$filterPanel.Controls.Add($buttonClearFilter)

$main.Controls.Add($filterPanel, 0, 1)

$structurePanel = New-Object System.Windows.Forms.FlowLayoutPanel
$structurePanel.Dock = 'Fill'
$structurePanel.AutoSize = $true
$structurePanel.WrapContents = $false

$labelParent = New-Object System.Windows.Forms.Label
$labelParent.Text = 'Parent OU Name:'
$labelParent.AutoSize = $true
$labelParent.Margin = New-Object System.Windows.Forms.Padding(3, 7, 3, 3)
$structurePanel.Controls.Add($labelParent)

$textParentOU = New-Object System.Windows.Forms.TextBox
$textParentOU.Width = 300
$structurePanel.Controls.Add($textParentOU)

$buttonPreview = New-Object System.Windows.Forms.Button
$buttonPreview.Text = 'Preview Structure'
$buttonPreview.Width = 130
$structurePanel.Controls.Add($buttonPreview)

$buttonExecute = New-Object System.Windows.Forms.Button
$buttonExecute.Text = 'Execute'
$buttonExecute.Width = 100
$structurePanel.Controls.Add($buttonExecute)

$main.Controls.Add($structurePanel, 0, 2)

$listViewTargets = New-Object System.Windows.Forms.ListView
$listViewTargets.Dock = 'Fill'
$listViewTargets.View = 'Details'
$listViewTargets.FullRowSelect = $true
$listViewTargets.MultiSelect = $false
$listViewTargets.GridLines = $true
$listViewTargets.HideSelection = $false
[void]$listViewTargets.Columns.Add('Name', 210)
[void]$listViewTargets.Columns.Add('Type', 100)
[void]$listViewTargets.Columns.Add('DistinguishedName', 590)
[void]$listViewTargets.Columns.Add('Protected', 100)
$script:listViewTargets = $listViewTargets
$main.Controls.Add($listViewTargets, 0, 3)

$childLabel = New-Object System.Windows.Forms.Label
$childLabel.AutoSize = $true
$childLabel.Text = 'Standard child OUs: ' + ($script:StandardChildOUs -join ' | ')
$main.Controls.Add($childLabel, 0, 4)

$logLabel = New-Object System.Windows.Forms.Label
$logLabel.AutoSize = $true
$logLabel.Text = 'Runtime log:'
$main.Controls.Add($logLabel, 0, 5)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Dock = 'Fill'
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$script:txtLog = $txtLog
$main.Controls.Add($txtLog, 0, 6)

$statusStrip = New-Object System.Windows.Forms.StatusStrip

$statusMain = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusMain.Spring = $true
$statusMain.TextAlign = 'MiddleLeft'
$statusMain.Text = 'Ready'
$script:statusMain = $statusMain
[void]$statusStrip.Items.Add($statusMain)

$statusMode = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusMode.Text = 'Mode: DRY RUN'
$script:statusMode = $statusMode
[void]$statusStrip.Items.Add($statusMode)

$main.Controls.Add($statusStrip, 0, 7)

# =====================================================================================
# GUI event handlers
# =====================================================================================
function Refresh-TargetBrowser {
    try {
        $domain = [string]$comboDomain.SelectedItem
        if ([string]::IsNullOrWhiteSpace($domain)) {
            Show-AppMessage -Message 'Select an Active Directory domain.' -Type Warning
            return
        }

        Set-AppStatus "Loading target locations from $domain..."
        $script:CurrentDomain = $domain
        $script:TargetLocations = @(Get-TargetLocations -Server $domain)
        $script:DisplayedTargets = @($script:TargetLocations)
        $textFilter.Clear()
        Set-TargetListViewData -Targets $script:DisplayedTargets
        Set-AppStatus ("Loaded {0} target location(s)." -f $script:TargetLocations.Count)
    } catch {
        Show-AppMessage -Message "Unable to refresh target locations: $($_.Exception.Message)" -Type Error
        Set-AppStatus 'Refresh failed.'
    }
}

$chkDryRun.Add_CheckedChanged({
    $script:statusMode.Text = 'Mode: ' + (Get-ExecutionModeLabel)
})

$comboDomain.Add_SelectedIndexChanged({
    if ($comboDomain.SelectedIndex -ge 0) {
        Refresh-TargetBrowser
    }
})

$buttonRefresh.Add_Click({
    Refresh-TargetBrowser
})

$textFilter.Add_TextChanged({
    try {
        Apply-TargetFilter -FilterText $textFilter.Text
    } catch {
        Write-AppLog -Message "Target filter failed: $($_.Exception.Message)" -Level ERROR
        Set-AppStatus 'Target filter failed.'
    }
})

$buttonClearFilter.Add_Click({
    $textFilter.Clear()
})

$listViewTargets.Add_ColumnClick({
    param($sender, $eventArgs)

    if ($script:SortColumn -eq $eventArgs.Column) {
        $script:SortDescending = -not $script:SortDescending
    } else {
        $script:SortColumn = $eventArgs.Column
        $script:SortDescending = $false
    }

    Sort-TargetLocations -ColumnIndex $script:SortColumn -Descending $script:SortDescending
    Apply-TargetFilter -FilterText $textFilter.Text
})

$buttonPreview.Add_Click({
    try {
        $target = Get-SelectedTarget
        if ($null -eq $target) {
            Show-AppMessage -Message 'Select exactly one target location in the table.' -Type Warning
            return
        }

        $parentName = $textParentOU.Text.Trim()
        if (-not (Test-OUName -Name $parentName)) {
            Show-AppMessage -Message 'Enter a valid Parent OU name (1-64 characters).' -Type Warning
            return
        }

        if ([string]::IsNullOrWhiteSpace([string]$script:CurrentDomain)) {
            Show-AppMessage -Message 'Refresh the target list before previewing changes.' -Type Warning
            return
        }

        Set-AppStatus 'Building OU structure preview...'
        $preview = @(New-OUStructurePreview -Target $target -ParentOUName $parentName -Server $script:CurrentDomain)
        Show-PreviewDialog -Preview $preview -Mode (Get-ExecutionModeLabel)
        Set-AppStatus 'OU structure preview completed.'
    } catch {
        Show-AppMessage -Message "Preview failed: $($_.Exception.Message)" -Type Error
        Set-AppStatus 'Preview failed.'
    }
})

$buttonExecute.Add_Click({
    try {
        $target = Get-SelectedTarget
        if ($null -eq $target) {
            Show-AppMessage -Message 'Select exactly one target location in the table.' -Type Warning
            return
        }

        $parentName = $textParentOU.Text.Trim()
        if (-not (Test-OUName -Name $parentName)) {
            Show-AppMessage -Message 'Enter a valid Parent OU name (1-64 characters).' -Type Warning
            return
        }

        if ([string]::IsNullOrWhiteSpace([string]$script:CurrentDomain)) {
            Show-AppMessage -Message 'Refresh the target list before executing changes.' -Type Warning
            return
        }

        $preview = @(New-OUStructurePreview -Target $target -ParentOUName $parentName -Server $script:CurrentDomain)
        $createCount = @($preview | Where-Object { $_.Status -eq 'CREATE' }).Count

        if ($chkDryRun.Checked) {
            Write-AppLog -Message ("DRY RUN: Target='{0}'; Parent='{1}'; OUs to create={2}." -f
                $target.DistinguishedName, $parentName, $createCount)
            Show-PreviewDialog -Preview $preview -Mode 'DRY RUN'
            Show-AppMessage -Message ("Dry Run completed. {0} OU object(s) would be created; Active Directory was not modified." -f $createCount) -Type Information
            Set-AppStatus 'Dry Run completed; no changes committed.'
            return
        }

        if ($createCount -eq 0) {
            Show-AppMessage -Message 'The complete requested OU structure already exists. No changes are required.' -Type Information
            Set-AppStatus 'Structure already compliant.'
            return
        }

        $confirmation = @"
COMMIT the requested Active Directory OU structure?

Domain: $($script:CurrentDomain)
Target: $($target.DistinguishedName)
Parent OU: $parentName
New OUs required: $createCount

New OUs will be protected from accidental deletion.
"@

        $answer = [System.Windows.Forms.MessageBox]::Show(
            $confirmation,
            'Confirm Active Directory OU Creation',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2
        )

        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            Write-AppLog -Message 'OU structure commit cancelled by operator.' -Level WARN
            Set-AppStatus 'Commit cancelled.'
            return
        }

        Set-AppStatus 'Creating and verifying OU structure...'
        $results = @(Invoke-OUStructureCreation -Target $target -ParentOUName $parentName `
            -Server $script:CurrentDomain -Confirm:$false)

        $success = @($results | Where-Object { $_.Result -eq 'SUCCESS' }).Count
        $exists  = @($results | Where-Object { $_.Result -eq 'EXISTS' }).Count
        $failed  = @($results | Where-Object { $_.Result -eq 'FAILED' }).Count
        $skipped = @($results | Where-Object { $_.Result -eq 'SKIPPED' }).Count

        Refresh-TargetBrowser

        $summary = @"
Execution completed.

Created: $success
Already existed: $exists
Failed: $failed
Skipped: $skipped

Log: $($script:LogFile)
"@

        if ($failed -gt 0) {
            Show-AppMessage -Message $summary -Type Warning
        } else {
            Write-AppLog -Message ("Commit summary: Created={0}; Existing={1}; Failed={2}; Skipped={3}" -f
                $success, $exists, $failed, $skipped) -Level SUCCESS

            [void][System.Windows.Forms.MessageBox]::Show(
                $summary,
                'Execution Summary',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }

        Set-AppStatus ("Completed: Created={0}, Existing={1}, Failed={2}, Skipped={3}" -f
            $success, $exists, $failed, $skipped)
    } catch {
        Show-AppMessage -Message "Execution failed: $($_.Exception.Message)" -Type Error
        Set-AppStatus 'Execution failed.'
    }
})

# =====================================================================================
# Main execution
# =====================================================================================
try {
    Write-AppLog -Message "Starting $($script:ScriptName)."
    Write-AppLog -Message ("Host PowerShell: {0}; OS: {1}" -f
        $PSVersionTable.PSVersion, [Environment]::OSVersion.VersionString)

    if (-not (Test-IsAdministrator)) {
        Write-AppLog -Message 'Process is not elevated. AD modification may still succeed with delegated rights; local elevation is not treated as equivalent to AD authorization.' -Level WARN
    }

    $domains = @(Get-ForestDomains)
    foreach ($domain in $domains) {
        [void]$comboDomain.Items.Add($domain)
    }

    if ($comboDomain.Items.Count -eq 0) {
        throw 'No Active Directory domains were discovered.'
    }

    Write-AppLog -Message ("Discovered forest domains: {0}" -f ($domains -join ', ')) -Level SUCCESS
    $comboDomain.SelectedIndex = 0

    [void]$form.ShowDialog()
} catch {
    Write-AppLog -Message "Fatal startup error: $($_.Exception.Message)" -Level ERROR
    [void][System.Windows.Forms.MessageBox]::Show(
        "Fatal startup error:`r`n$($_.Exception.Message)",
        'Default AD OU Structure Manager',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
} finally {
    Write-AppLog -Message "Closing $($script:ScriptName)."
}

# End of script
