<#
.SYNOPSIS
    PowerShell Script for Retrieving Information on All AD Groups and Their Members.

.DESCRIPTION
    This script retrieves detailed information about all Active Directory (AD) groups and their members across specified domains, 
    assisting administrators in auditing and compliance reporting, with results exported to a single CSV via a user-configurable GUI.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: February 25, 2025
#>

[CmdletBinding()]
Param (
    [Parameter(HelpMessage = "Automatically open the generated CSV file after processing.")]
    [bool]$AutoOpen = $true
)

#region Initialization
Add-Type -Name Window -Namespace Console -MemberDefinition @"
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() {
        ShowWindow(GetConsoleWindow(), 0); // 0 = SW_HIDE
    }
"@ -ErrorAction Stop
[Console.Window]::Hide()

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
#endregion

#region Functions
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Message,
        [ValidateSet('Info', 'Error', 'Warning')]
        [string]$Level = 'Info'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    try {
        $logEntry | Out-File -FilePath $script:logPath -Append -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Warning "Failed to write to log at '$script:logPath': $_"
    }
}

function Show-MessageBox {
    param (
        [string]$Message,
        [string]$Title,
        [System.Windows.Forms.MessageBoxButtons]$Buttons = 'OK',
        [System.Windows.Forms.MessageBoxIcon]$Icon = 'Information'
    )
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, $Buttons, $Icon)
}

function Update-ProgressBar {
    param (
        [ValidateRange(0, 100)]
        [int]$Value
    )
    $script:progressBar.Value = $Value
    $script:form.Refresh()
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

# Process all AD groups and members in a domain
function Get-ADGroupInfo {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string[]]$DomainFQDNs,
        [Parameter(Mandatory)]
        [string]$OutputFolder
    )
    Write-Log "Starting AD group info retrieval across domains: $($DomainFQDNs -join ', ')"

    try {
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $csvPath = Join-Path $OutputFolder "$DomainServerName-ADGroupInfo-AllGroups-$timestamp.csv"
        $groupInfo = [System.Collections.Generic.List[PSObject]]::new()
        $totalDomains = $DomainFQDNs.Count
        $processedDomains = 0

        foreach ($domainFQDN in $DomainFQDNs) {
            $processedDomains++
            $domainProgress = [math]::Round(($processedDomains / $totalDomains) * 20)
            Update-ProgressBar -Value $domainProgress
            $script:statusLabel.Text = "Processing domain $processedDomains of $totalDomains: $domainFQDN..."
            $script:form.Refresh()

            try {
                Write-Log "Fetching all groups from domain '$domainFQDN'"
                $groups = Get-ADGroup -Filter * -Server $domainFQDN -ErrorAction Stop
                if (-not $groups) {
                    Write-Log "No groups found in domain '$domainFQDN'" -Level Warning
                    continue
                }

                $totalGroups = $groups.Count
                $processedGroups = 0

                foreach ($group in $groups) {
                    $processedGroups++
                    $groupProgress = [math]::Round(($processedGroups / $totalGroups) * 60 / $totalDomains) + $domainProgress
                    Update-ProgressBar -Value $groupProgress
                    $script:statusLabel.Text = "Processing group $processedGroups of $totalGroups in $domainFQDN: $($group.Name)..."
                    $script:form.Refresh()

                    try {
                        $groupMembers = Get-ADGroupMember -Identity $group -Recursive -Server $domainFQDN -ErrorAction Stop
                        if (-not $groupMembers) {
                            Write-Log "No members found for group '$($group.Name)' in domain '$domainFQDN'" -Level Info
                        }

                        foreach ($member in $groupMembers) {
                            try {
                                $user = Get-ADUser -Identity $member.DistinguishedName -Server $domainFQDN -Properties Enabled, AccountLockoutTime, LastLogonDate, Created -ErrorAction Stop
                                $accountStatus = Get-AccountStatus -User $user

                                $groupInfo.Add([PSCustomObject]@{
                                    DomainFQDN       = $domainFQDN
                                    GroupName        = $group.Name
                                    MemberName       = $member.Name
                                    SamAccountName   = $member.SamAccountName
                                    AccountStatus    = $accountStatus
                                    LastLogonDate    = $user.LastLogonDate
                                    CreationDate     = $user.Created
                                    DistinguishedName = $member.DistinguishedName
                                })
                            } catch {
                                Write-Log "Error processing member '$($member.Name)' in group '$($group.Name)' (domain '$domainFQDN'): $_" -Level Error
                            }
                        }
                    } catch {
                        Write-Log "Error retrieving members for group '$($group.Name)' in domain '$domainFQDN': $_" -Level Error
                    }
                }
            } catch {
                Write-Log "Error processing domain '$domainFQDN': $_" -Level Error
            }
        }

        Update-ProgressBar -Value 80
        $script:statusLabel.Text = "Exporting results to '$csvPath'..."
        $script:form.Refresh()

        if ($groupInfo.Count -gt 0) {
            $groupInfo | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -Force
            Write-Log "Exported $(${groupInfo}.Count) group entries to '$csvPath'"
            Update-ProgressBar -Value 100
            Show-MessageBox -Message "Found $(${groupInfo}.Count) group entries across domains.`nReport exported to:`n$csvPath" -Title "Success"
            if ($AutoOpen -and (Test-Path $csvPath)) { Start-Process -FilePath $csvPath }
        } else {
            Write-Log "No group data to export across specified domains" -Level Warning
            Show-MessageBox -Message "No group data found across specified domains." -Title "No Results" -Icon Warning
        }
    } catch {
        Write-Log "Error during group processing: $_" -Level Error
        Show-MessageBox -Message "Error during group processing: $_" -Title "Error" -Icon Error
    } finally {
        Update-ProgressBar -Value 0
        $script:statusLabel.Text = "Ready"
    }
}
#endregion

#region GUI Setup
$form = New-Object System.Windows.Forms.Form -Property @{
    Text          = 'AD Group Auditor (All Groups)'
    Size          = [System.Drawing.Size]::new(450, 350)
    StartPosition = 'CenterScreen'
    FormBorderStyle = 'FixedSingle'
    MaximizeBox     = $false
}

# Domain Selector
$labelDomains = New-Object System.Windows.Forms.Label -Property @{
    Location = [System.Drawing.Point]::new(10, 20)
    Size     = [System.Drawing.Size]::new(100, 20)
    Text     = "Domain FQDNs:"
}
$form.Controls.Add($labelDomains)

$textBoxDomains = New-Object System.Windows.Forms.TextBox -Property @{
    Location = [System.Drawing.Point]::new(120, 20)
    Size     = [System.Drawing.Size]::new(320, 40)
    Multiline = $true
    Text     = (Get-AllDomainFQDNs -join ", ")
}
$form.Controls.Add($textBoxDomains)

# Log Directory
$labelLogDir = New-Object System.Windows.Forms.Label -Property @{
    Location = [System.Drawing.Point]::new(10, 70)
    Size     = [System.Drawing.Size]::new(100, 20)
    Text     = "Log Directory:"
}
$form.Controls.Add($labelLogDir)

$textBoxLogDir = New-Object System.Windows.Forms.TextBox -Property @{
    Location = [System.Drawing.Point]::new(120, 70)
    Size     = [System.Drawing.Size]::new(200, 20)
    Text     = $logDir
}
$form.Controls.Add($textBoxLogDir)

$buttonBrowseLogDir = New-Object System.Windows.Forms.Button -Property @{
    Location = [System.Drawing.Point]::new(330, 70)
    Size     = [System.Drawing.Size]::new(100, 20)
    Text     = "Browse"
}
$buttonBrowseLogDir.Add_Click({
    $folder = Select-Folder
    if ($folder) { 
        $textBoxLogDir.Text = $folder 
        Write-Log "Log Directory updated to: '$folder' via browse"
    }
})
$form.Controls.Add($buttonBrowseLogDir)

# Output Folder
$labelOutputDir = New-Object System.Windows.Forms.Label -Property @{
    Location = [System.Drawing.Point]::new(10, 100)
    Size     = [System.Drawing.Size]::new(100, 20)
    Text     = "Output Folder:"
}
$form.Controls.Add($labelOutputDir)

$textBoxOutputDir = New-Object System.Windows.Forms.TextBox -Property @{
    Location = [System.Drawing.Point]::new(120, 100)
    Size     = [System.Drawing.Size]::new(200, 20)
    Text     = $outputFolderDefault
}
$form.Controls.Add($textBoxOutputDir)

$buttonBrowseOutputDir = New-Object System.Windows.Forms.Button -Property @{
    Location = [System.Drawing.Point]::new(330, 100)
    Size     = [System.Drawing.Size]::new(100, 20)
    Text     = "Browse"
}
$buttonBrowseOutputDir.Add_Click({
    $folder = Select-Folder
    if ($folder) { 
        $textBoxOutputDir.Text = $folder 
        Write-Log "Output Folder updated to: '$folder' via browse"
    }
})
$form.Controls.Add($buttonBrowseOutputDir)

# Status Label
$statusLabel = New-Object System.Windows.Forms.Label -Property @{
    Location = [System.Drawing.Point]::new(10, 130)
    Size     = [System.Drawing.Size]::new(430, 20)
    Text     = "Ready"
}
$form.Controls.Add($statusLabel)

# Progress Bar
$progressBar = New-Object System.Windows.Forms.ProgressBar -Property @{
    Location = [System.Drawing.Point]::new(10, 160)
    Size     = [System.Drawing.Size]::new(430, 20)
}
$form.Controls.Add($progressBar)

# Start Button
$buttonStartAnalysis = New-Object System.Windows.Forms.Button -Property @{
    Location = [System.Drawing.Point]::new(10, 190)
    Size     = [System.Drawing.Size]::new(100, 30)
    Text     = "Start Analysis"
}
$buttonStartAnalysis.Add_Click({
    $script:logDir = $textBoxLogDir.Text
    $script:logPath = Join-Path $script:logDir "${scriptName}.log"
    $outputFolder = $textBoxOutputDir.Text
    $domains = $textBoxDomains.Text -split ',\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

    if (-not (Test-Path $script:logDir)) {
        New-Item -Path $script:logDir -ItemType Directory -Force | Out-Null
    }

    if (-not $domains) {
        Show-MessageBox -Message "Please specify at least one domain FQDN." -Title "Input Required" -Icon Warning
        $script:statusLabel.Text = "Ready"
        return
    }

    Get-ADGroupInfo -DomainFQDNs $domains -OutputFolder $outputFolder
})
$form.Controls.Add($buttonStartAnalysis)

# Close Button
$buttonClose = New-Object System.Windows.Forms.Button -Property @{
    Location = [System.Drawing.Point]::new(120, 190)
    Size     = [System.Drawing.Size]::new(100, 30)
    Text     = "Close"
}
$buttonClose.Add_Click({ $form.Close() })
$form.Controls.Add($buttonClose)

# Script scope variables
$script:form = $form
$script:progressBar = $progressBar
$script:statusLabel = $statusLabel

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
#endregion
