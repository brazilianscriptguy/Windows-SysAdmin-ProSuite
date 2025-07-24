<#
.SYNOPSIS
    PowerShell Script for Retrieving Information on AD Groups and Their Members.

.DESCRIPTION
    This script retrieves detailed information about Active Directory (AD) groups and their members 
    from a selected domain, allowing users to choose specific groups or all groups via a GUI with 
    checkbox selection, exporting results to a single CSV.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: February 26, 2025
#>

[CmdletBinding()]
Param (
    [Parameter(HelpMessage = "Automatically open the generated CSV file after processing.")]
    [bool]$AutoOpen = $true
)

# Hide the PowerShell console window
Add-Type -Name ConsoleUtils -Namespace HideConsole -MemberDefinition @"
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public static void HideConsoleWindow() {
        IntPtr hWnd = GetConsoleWindow();
        if (hWnd != IntPtr.Zero) {
            ShowWindow(hWnd, 0); // 0 = SW_HIDE
        }
    }
"@
try {
    [HideConsole.ConsoleUtils]::HideConsoleWindow()
} catch {
    Write-Warning "Failed to hide console window: $_"
}

try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Error "Failed to load required assemblies or module: $_"
    exit 1
}

$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$DomainServerName = [System.Environment]::MachineName

# Define default paths
$logDir = "C:\Logs-TEMP"
$outputFolderDefault = [Environment]::GetFolderPath('MyDocuments')
$logPath = Join-Path $logDir "${scriptName}.log"

if (-not (Test-Path $logDir -PathType Container)) {
    try {
        New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Failed to create log directory at '$logDir': $_"
        exit 1
    }
}

#region Functions
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Message,
        [ValidateSet('Info', 'Error', 'Warning')]
        [string]$Level = 'Info'
    )
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $logEntry = "[$timestamp] [$Level] $Message"
    try {
        $logEntry | Out-File -FilePath $logPath -Append -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Warning "Failed to write to log at '$logPath': $_"
    }
}

function Show-MessageBox {
    param (
        [string]$Message,
        [string]$Title,
        [System.Windows.Forms.MessageBoxButtons]$Buttons = 'OK',
        [System.Windows.Forms.MessageBoxIcon]$Icon = 'Information'
    )
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, $Buttons, $Icon) | Out-Null
}

function Update-ProgressBar {
    param (
        [ValidateRange(0, 100)]
        [int]$Value
    )
    $progressBar.Value = $Value
    $form.Refresh()
}

function Select-Folder {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
        Description = "Select a folder for output CSV"
        ShowNewFolderButton = $true
    }
    if ($dialog.ShowDialog() -eq 'OK') {
        return $dialog.SelectedPath
    }
    return $null
}

# Retrieve all domain FQDNs in the forest
function Get-AllDomainFQDNs {
    try {
        $forest = Get-ADForest -ErrorAction Stop
        return $forest.Domains
    } catch {
        Write-Log "Failed to retrieve domain FQDNs: $_" -Level Error
        return @()
    }
}

# Determine account status
function Get-AccountStatus {
    param (
        [object]$User
    )
    if ($User.AccountLockoutTime) { return "Blocked" }
    elseif (-not $User.Enabled) { return "Disabled" }
    else { return "Enabled" }
}

# List all groups in the domain
function List-DomainGroups {
    param (
        [string]$DomainFQDN,
        [System.Windows.Forms.ListView]$ListView
    )
    $ListView.Items.Clear()
    try {
        $groups = Get-ADGroup -Filter * -Server $DomainFQDN -Properties Name, Description -ErrorAction Stop | Sort-Object Name
        foreach ($group in $groups) {
            $listItem = New-Object System.Windows.Forms.ListViewItem
            $listItem.Text = $group.Name
            $description = if ($group.Description) { $group.Description } else { "N/A" }
            $listItem.SubItems.Add($description)
            $ListView.Items.Add($listItem) | Out-Null
        }
        Write-Log "Loaded $($ListView.Items.Count) groups from domain '$DomainFQDN'"
        $statusLabel.Text = "Loaded $($ListView.Items.Count) groups."
    } catch {
        Write-Log "Error loading groups from '$DomainFQDN': $_" -Level Error
        Show-MessageBox -Message "Error loading groups: $_" -Title "Error" -Icon Error
        $statusLabel.Text = "Error loading groups."
    }
}

# Process AD groups and members in a domain
function Get-ADGroupInfo {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$DomainFQDN,
        [Parameter(Mandatory)]
        [string]$OutputFolder,
        [System.Windows.Forms.ListView]$ListView
    )
    Write-Log "Starting AD group info retrieval for domain: $DomainFQDN"

    try {
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $csvPath = Join-Path $OutputFolder "${DomainFQDN}-ADGroupsInfo-$timestamp.csv"
        $groupInfo = [System.Collections.Generic.List[PSObject]]::new()

        # Check if any groups are selected
        $selectedGroups = $ListView.CheckedItems | ForEach-Object { $_.Text }
        if ($selectedGroups.Count -eq 0) {
            Show-MessageBox -Message "No groups selected. Please select at least one group to process." -Title "Input Required" -Icon Warning
            return
        }

        Update-ProgressBar -Value 10
        $statusLabel.Text = "Processing selected groups from domain '$DomainFQDN'..."
        $form.Refresh()

        $totalGroups = $selectedGroups.Count
        $processedGroups = 0

        foreach ($groupName in $selectedGroups) {
            $processedGroups++
            $groupProgress = [math]::Round(($processedGroups / $totalGroups) * 70) + 10
            Update-ProgressBar -Value $groupProgress
            $statusLabel.Text = "Processing group ${processedGroups} of ${totalGroups}: $groupName..."
            $form.Refresh()

            try {
                $group = Get-ADGroup -Filter "Name -eq '$groupName'" -Server $DomainFQDN -ErrorAction Stop
                $groupMembers = Get-ADGroupMember -Identity $group -Recursive -Server $DomainFQDN -ErrorAction Stop
                if (-not $groupMembers) {
                    Write-Log "No members found for group '$groupName' in domain '$DomainFQDN'" -Level Info
                }

                foreach ($member in $groupMembers) {
                    try {
                        $user = Get-ADUser -Identity $member.DistinguishedName -Server $DomainFQDN -Properties Enabled, AccountLockoutTime, LastLogonDate, Created -ErrorAction Stop
                        $accountStatus = Get-AccountStatus -User $user

                        $groupInfo.Add([PSCustomObject]@{
                                DomainFQDN = $DomainFQDN
                                GroupName = $group.Name
                                MemberName = $member.Name
                                SamAccountName = $member.SamAccountName
                                AccountStatus = $accountStatus
                                LastLogonDate = $user.LastLogonDate
                                CreationDate = $user.Created
                                DistinguishedName = $member.DistinguishedName
                            })
                    } catch {
                        Write-Log "Error processing member '$($member.Name)' in group '$groupName' (domain '$DomainFQDN'): $_" -Level Error
                    }
                }
            } catch {
                Write-Log "Error retrieving members for group '$groupName' in domain '$DomainFQDN': $_" -Level Error
            }
        }

        Update-ProgressBar -Value 80
        $statusLabel.Text = "Exporting results to '$csvPath'..."
        $form.Refresh()

        if ($groupInfo.Count -gt 0) {
            $groupInfo | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -Force
            Write-Log "Exported $(${groupInfo}.Count) group entries to '$csvPath'"
            Update-ProgressBar -Value 100
            Show-MessageBox -Message "Found $(${groupInfo}.Count) group entries in domain '$DomainFQDN'.`nReport exported to:`n$csvPath" -Title "Success"
            if ($AutoOpen -and (Test-Path $csvPath)) { Start-Process -FilePath $csvPath }
        } else {
            Write-Log "No group data to export for domain '$DomainFQDN'" -Level Warning
            Show-MessageBox -Message "No group data found for selected groups in domain '$DomainFQDN'." -Title "No Results" -Icon Warning
        }
    } catch {
        Write-Log "Error during group processing: $_" -Level Error
        Show-MessageBox -Message "Error during group processing: $_" -Title "Error" -Icon Error
    } finally {
        Update-ProgressBar -Value 0
        $statusLabel.Text = "Process complete."
    }
}
#endregion

#region GUI Setup
$form = New-Object System.Windows.Forms.Form
$form.Text = "AD Group Search Tool"
$form.Size = New-Object Drawing.Size(500, 450)
$form.StartPosition = "CenterScreen"

# Domain dropdown
$labelDomain = New-Object System.Windows.Forms.Label
$labelDomain.Text = "Select Domain FQDN:"
$labelDomain.Location = New-Object Drawing.Point(10, 20)
$labelDomain.AutoSize = $true
$form.Controls.Add($labelDomain)

$comboBoxDomain = New-Object System.Windows.Forms.ComboBox
$comboBoxDomain.Location = New-Object Drawing.Point(10, 50)
$comboBoxDomain.Size = New-Object Drawing.Size(460, 20)
$comboBoxDomain.DropDownStyle = 'DropDownList'
$comboBoxDomain.Items.AddRange((Get-AllDomainFQDNs))
if ($comboBoxDomain.Items.Count -gt 0) {
    $comboBoxDomain.SelectedIndex = 0
}
$form.Controls.Add($comboBoxDomain)

# Group ListView
$labelGroups = New-Object System.Windows.Forms.Label
$labelGroups.Text = "Select Groups to Inventory:"
$labelGroups.Location = New-Object Drawing.Point(10, 80)
$labelGroups.AutoSize = $true
$form.Controls.Add($labelGroups)

$listViewGroups = New-Object System.Windows.Forms.ListView
$listViewGroups.Location = New-Object Drawing.Point(10, 110)
$listViewGroups.Size = New-Object Drawing.Size(460, 100)
$listViewGroups.View = [System.Windows.Forms.View]::Details
[void]$listViewGroups.Columns.Add("Group Name", 200)
[void]$listViewGroups.Columns.Add("Description", 240)
$listViewGroups.CheckBoxes = $true
$form.Controls.Add($listViewGroups)

# Select All Button
$buttonSelectAll = New-Object System.Windows.Forms.Button
$buttonSelectAll.Text = "Select All Groups"
$buttonSelectAll.Location = New-Object Drawing.Point(10, 215)
$buttonSelectAll.Size = New-Object Drawing.Size(120, 20)
$buttonSelectAll.Add_Click({
        $selectAll = $buttonSelectAll.Text -eq "Select All Groups"
        $listViewGroups.Items | ForEach-Object { $_.Checked = $selectAll }
        $buttonSelectAll.Text = if ($selectAll) { "Clear Selection" } else { "Select All Groups" }
    })
$form.Controls.Add($buttonSelectAll)

# Output Folder
$labelOutputDir = New-Object System.Windows.Forms.Label
$labelOutputDir.Text = "Output Folder:"
$labelOutputDir.Location = New-Object Drawing.Point(10, 240)
$labelOutputDir.AutoSize = $true
$form.Controls.Add($labelOutputDir)

$textBoxOutputDir = New-Object System.Windows.Forms.TextBox
$textBoxOutputDir.Location = New-Object Drawing.Point(10, 260)
$textBoxOutputDir.Size = New-Object Drawing.Size(400, 20)
$textBoxOutputDir.Text = $outputFolderDefault
$form.Controls.Add($textBoxOutputDir)

$buttonBrowseOutputDir = New-Object System.Windows.Forms.Button
$buttonBrowseOutputDir.Text = "Browse"
$buttonBrowseOutputDir.Location = New-Object Drawing.Point(420, 260)
$buttonBrowseOutputDir.Size = New-Object Drawing.Size(50, 20)
$buttonBrowseOutputDir.Add_Click({
        $folder = Select-Folder
        if ($folder) { 
            $textBoxOutputDir.Text = $folder 
            Write-Log "Output Folder updated to: '$folder' via browse"
        }
    })
$form.Controls.Add($buttonBrowseOutputDir)

# Start button
$buttonStartAnalysis = New-Object System.Windows.Forms.Button
$buttonStartAnalysis.Text = "Start Analysis"
$buttonStartAnalysis.Location = New-Object Drawing.Point(10, 290)
$buttonStartAnalysis.Size = New-Object Drawing.Size(85, 23)
$form.Controls.Add($buttonStartAnalysis)

# Progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object Drawing.Point(10, 320)
$progressBar.Size = New-Object Drawing.Size(460, 20)
$form.Controls.Add($progressBar)

# Status label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object Drawing.Point(10, 350)
$statusLabel.Size = New-Object Drawing.Size(460, 20)
$statusLabel.Text = ""
$form.Controls.Add($statusLabel)

# Close button
$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Text = "Close"
$buttonClose.Location = New-Object Drawing.Point(390, 290)
$buttonClose.Size = New-Object Drawing.Size(80, 23)
$buttonClose.Add_Click({ $form.Close() })
$form.Controls.Add($buttonClose)

# Domain selection event handler to populate groups
$comboBoxDomain.Add_SelectedIndexChanged({
        $domainFQDN = $comboBoxDomain.SelectedItem
        if ($domainFQDN) {
            $statusLabel.Text = "Loading groups from '$domainFQDN'..."
            $form.Refresh()
            List-DomainGroups -DomainFQDN $domainFQDN -ListView $listViewGroups
            $buttonSelectAll.Text = "Select All Groups"  # Reset button text
        }
    })

# Start button event handler
$buttonStartAnalysis.Add_Click({
        $domainFQDN = $comboBoxDomain.SelectedItem
        $outputFolder = $textBoxOutputDir.Text

        if ([string]::IsNullOrWhiteSpace($domainFQDN)) {
            Show-MessageBox -Message "Please select a Domain FQDN." -Title "Input Required" -Icon Warning
            return
        }

        if (-not (Test-Path $outputFolder)) {
            try {
                New-Item -Path $outputFolder -ItemType Directory -Force | Out-Null
            } catch {
                Show-MessageBox -Message "Failed to create output folder '$outputFolder': $_" -Title "Error" -Icon Error
                return
            }
        }

        Get-ADGroupInfo -DomainFQDN $domainFQDN -OutputFolder $outputFolder -ListView $listViewGroups
    })

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
#endregion
