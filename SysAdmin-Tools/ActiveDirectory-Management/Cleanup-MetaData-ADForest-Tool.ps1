<#
.SYNOPSIS
    PowerShell Tool for Cleaning Up Metadata in Active Directory Forest.

.DESCRIPTION
    This user-friendly tool is designed to clean up your AD forest by removing orphaned 
    objects, synchronizing Domain Controllers, and managing unnecessary CNs. It helps 
    maintain a secure and optimized AD environment, particularly after incidents or 
    maintenance activities.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: October 22, 2024
#>

# Hide the PowerShell console window for a cleaner UI
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
"@
[Window]::Hide()

# Import necessary modules
if (-not (Get-Module -Name ActiveDirectory)) {
    Import-Module ActiveDirectory -ErrorAction Stop
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Global Variables Initialization
$global:logBox = New-Object System.Windows.Forms.ListBox
$logDir = 'C:\Logs-TEMP'
$global:logPath = Join-Path $logDir "ADForestSyncTool_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Failed to create log directory at $logDir. Logging will not be possible."
        return
    }
}

# Centralized logging function
function Write-Log {
    param (
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $false)][ValidateSet("INFO", "ERROR", "WARNING")][string]$Type = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Type] $Message"
    try {
        Add-Content -Path $global:logPath -Value "$logEntry`r`n" -ErrorAction Stop
        if ($global:logBox -ne $null) {
            $global:logBox.Items.Add($logEntry)
            $global:logBox.TopIndex = $global:logBox.Items.Count - 1
        }
    } catch {
        Write-Error "Failed to write to log: $_"
    }
    Write-Output $logEntry
}

# Unified error handling
function Handle-Error {
    param (
        [Parameter(Mandatory = $true)][string]$ErrorMessage
    )
    Write-Log -Message "ERROR: $ErrorMessage" -Type "ERROR"
    [System.Windows.Forms.MessageBox]::Show($ErrorMessage, "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

# Function to convert a domain name in format 'DomainName.ForestRootName.ForestSufix' to 'DC=DomainName,DC=ForestRootName,DC=ForestSufix'
function Convert-ToDCFormat {
    param (
        [Parameter(Mandatory = $true)][string]$domainName
    )
    # Split the domain name and convert each part to the required format
    $dcComponents = $domainName -split '\.' | ForEach-Object { "DC=$($_.ToUpper())" }
    # Join the components together with commas
    return $dcComponents -join ","
}

# Function to identify the Domain Naming Master
function Get-DomainNamingMaster {
    try {
        $domainNamingMaster = (Get-ADForest).DomainNamingMaster
        Write-Log -Message "Domain Naming Master is: $domainNamingMaster"
        return $domainNamingMaster
    } catch {
        Handle-Error "Failed to identify the Domain Naming Master. Error: $($_)"
    }
}

# Function to remove an orphaned domain using ntdsutil
function Remove-OrphanedDomain {
    param (
        [Parameter(Mandatory = $true)][string]$orphanedDomain
    )

    $domainNamingMaster = Get-DomainNamingMaster
    if (-not $domainNamingMaster) {
        Handle-Error "Domain Naming Master not found. Cannot proceed with removing orphaned domain."
        return
    }

    Write-Log "Starting removal of orphaned domain: $orphanedDomain on Domain Naming Master: $domainNamingMaster"

    $ntdsutilCommands = @"
activate instance ntds
partition management
connections
connect to server $domainNamingMaster
q
list
delete nc DC=DomainDNSZones,DC=$orphanedDomain
list
delete nc DC=$orphanedDomain
qqq
"@

    try {
        $ntdsutilFilePath = [System.IO.Path]::GetTempFileName()
        $ntdsutilCommands | Out-File -FilePath $ntdsutilFilePath -Encoding ascii

        Start-Process -FilePath "ntdsutil.exe" -ArgumentList "batch", $ntdsutilFilePath -NoNewWindow -Wait
        Write-Log "Orphaned domain $orphanedDomain removed successfully."
    } catch {
        Handle-Error "Failed to remove orphaned domain $orphanedDomain. Error: $($_)"
    } finally {
        Remove-Item -Path $ntdsutilFilePath -Force -ErrorAction SilentlyContinue
    }
}

# Function to clean up and remove orphaned domains, followed by syncing all DCs
function Clean-And-SyncOrphanedDomain {
    param (
        [Parameter(Mandatory = $true)][string]$orphanedDomain
    )

    # Clean up orphaned domain
    Remove-OrphanedDomain -orphanedDomain $orphanedDomain

    # Force replication after cleaning up the domain
    Sync-AllDCs
}

# Function to take ownership of the object and remove protection from accidental deletion
function Take-OwnershipAndRemoveProtection {
    param (
        [Parameter(Mandatory = $true)][string]$distinguishedName
    )

    try {
        # Get the AD object
        $adObject = Get-ADObject -Identity $distinguishedName -Properties ntSecurityDescriptor -ErrorAction Stop

        # Take ownership
        $currentOwner = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $adObject.psbase.ObjectSecurity.SetOwner($currentOwner)

        # Remove protection from accidental deletion
        $acl = Get-ACL -Path ("AD:" + $distinguishedName)
        $acl.SetAccessRuleProtection($false, $true)
        Set-ACL -Path ("AD:" + $distinguishedName) -ACLObject $acl

        Write-Log -Message "Successfully took ownership and removed protection from accidental deletion for CN: $distinguishedName"
    } catch {
        Handle-Error "Failed to take ownership or remove protection for CN: $distinguishedName. Error: $_"
    }
}

# Function to clean up the environment (remove metadata, trusts, domain partitions)
function Clean-Environment {
    Write-Log "Starting cleaning operations..."

    # Remove metadata for the specified domain
    Remove-Metadata

    # Remove trust relationships for the specified domain
    Remove-Trusts

    # Remove the domain partition from ADSI
    Remove-DomainPartition

    Write-Log "Cleaning operations completed."
    [System.Windows.Forms.MessageBox]::Show("Cleaning operations completed.", "Info", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

# Function to remove metadata for a non-existent DC
function Remove-Metadata {
    $metadataPartition = Convert-ToDCFormat "$global:domainToRemove.$global:forestRootDomain"
    foreach ($dc in $allDCs) {
        $dcName = $dc.HostName
        Write-Log "Removing metadata on ${dcName} for ${metadataPartition}"
        try {
            $removeResult = & repadmin /removelingeringobjects $dcName $metadataPartition
            $removeResult = $removeResult -replace "`r`n", " "
            Write-Log "Remove metadata result for ${dcName} for ${metadataPartition}: $removeResult"
        } catch {
            Handle-Error "Error removing metadata on ${dcName} for ${metadataPartition}: $($_)"
        }
    }
    Write-Log "Metadata removal process completed"
}

# Function to remove trust relationships
function Remove-Trusts {
    try {
        $trusts = Get-ADTrust -Filter { TargetDomainName -eq $global:domainToRemove }
        foreach ($trust in $trusts) {
            try {
                Remove-ADTrust -Identity $trust.Name -Confirm:$false
                Write-Log "Removed trust relationship with $global:domainToRemove"
            } catch {
                Handle-Error "Failed to remove trust relationship with $global:domainToRemove: $($_)"
            }
        }
    } catch {
        Handle-Error "Error retrieving trusts for $global:domainToRemove: $($_)"
    }
}

# Function to remove domain partitions using ADSIEdit
function Remove-DomainPartition {
    try {
        $adsi = [ADSI]"LDAP://CN=Partitions,CN=Configuration,$(Convert-ToDCFormat $global:forestRootDomain)"
        $partitions = $adsi.psbase.children
        foreach ($partition in $partitions) {
            if ($partition.Name -like "CN=$global:domainToRemove") {
                $partition.psbase.DeleteTree()
                Write-Log "Deleted partition CN=$global:domainToRemove from ADSIEdit"
            }
        }
    } catch {
        Handle-Error "Failed to remove domain partition $global:domainToRemove: $($_)"
    }
}

# Function to synchronize all DCs in the Forest across all sites
function Sync-AllDCs {
    Write-Log "Starting Active Directory synchronization process..."

    # Get a list of all domains in the forest
    try {
        $forest = Get-ADForest
        $allDomains = $forest.Domains
    } catch {
        Handle-Error "Error retrieving forest domains: $($_)"
        return
    }

    # Collect all domain controllers from all domains
    $allDCs = @()
    foreach ($domain in $allDomains) {
        try {
            $domainDCs = Get-ADDomainController -Filter * -Server $domain
            $allDCs += $domainDCs
        } catch {
            Handle-Error "Error retrieving domain controllers from ${domain}: $($_)"
        }
    }

    # Force synchronization on all domain controllers
    foreach ($dc in $allDCs) {
        $dcName = $dc.HostName
        Write-Log "Forcing synchronization on ${dcName}"
        try {
            # Perform the synchronization
            $syncResult = & repadmin /syncall /e /A /P /d /q $dcName
            $syncResult = $syncResult -replace "`r`n", " "
            Write-Log "Synchronization result for ${dcName}: $syncResult"
        } catch {
            Handle-Error "Error synchronizing ${dcName}: $($_)"
        }
    }

    Write-Log "Active Directory synchronization process completed."
    [System.Windows.Forms.MessageBox]::Show("Synchronization process completed.", "Info", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

# Function to initiate an authoritative DNS update
function Initiate-DNSUpdate {
    $dnsServers = Get-DnsServer | Select-Object -ExpandProperty Name
    foreach ($server in $dnsServers) {
        try {
            dnscmd $server /ZoneReload $global:forestRootDomain
            Write-Log "Initiated authoritative DNS update on server: $server"
        } catch {
            Handle-Error "Failed to initiate DNS update on server ${server}: $($_)"
        }
    }
}

# Function to locate and remove specified domain and DC
function Locate-Domain {
    $partition = Convert-ToDCFormat "$global:domainToRemove.$global:forestRootDomain"
    $locationsFound = @()
    foreach ($dc in $allDCs) {
        $dcName = $dc.HostName
        Write-Log "Checking ${dcName} for ${partition}"
        try {
            $searchResult = Get-ADObject -LDAPFilter "(distinguishedName=$partition)" -Server $dcName
            if ($searchResult) {
                $locationsFound += $dcName
                Write-Log "Partition ${partition} found on ${dcName}"
            } else {
                Write-Log "Partition ${partition} not found on ${dcName}"
            }
        } catch {
            Handle-Error "Error checking ${dcName} for ${partition}: $($_)"
        }
    }

    if ($locationsFound) {
        $foundMsg = "Partition ${partition} found on the following DCs: " + ($locationsFound -join ", ")
        [System.Windows.Forms.MessageBox]::Show($foundMsg, "Info", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        Write-Log $foundMsg
    } else {
        $notFoundMsg = "Partition ${partition} not found on any DCs."
        [System.Windows.Forms.MessageBox]::Show($notFoundMsg, "Info", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        Write-Log $notFoundMsg
    }
}

# Function to remove a CN
function Remove-CN {
    param (
        [Parameter(Mandatory = $true)][string]$distinguishedName
    )

    try {
        Take-OwnershipAndRemoveProtection -distinguishedName $distinguishedName

        $confirmation = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to delete CN: $distinguishedName?", "Confirm Deletion", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)

        if ($confirmation -eq [System.Windows.Forms.DialogResult]::Yes) {
            Remove-ADObject -Identity $distinguishedName -Confirm:$false -ErrorAction Stop
            Write-Log "Successfully deleted CN: $distinguishedName"
        } else {
            Write-Log "Deletion of CN: $distinguishedName was cancelled by the user."
        }
    } catch {
        Handle-Error "Failed to delete CN: $distinguishedName. Error: $($_)"
    }
}

# Function to display the log file
function Show-Log {
    notepad $global:logPath
}

# GUI Initialization
$form = New-Object System.Windows.Forms.Form
$form.Text = "AD Forest and DC Management Tool"
$form.Size = New-Object System.Drawing.Size(800, 720)
$form.StartPosition = "CenterScreen"

# Initialize the TabControl and Tabs
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Size = New-Object System.Drawing.Size(780, 680)
$tabControl.Location = New-Object System.Drawing.Point(10, 10)

$tabSync = New-Object System.Windows.Forms.TabPage
$tabSync.Text = "Sync and Clean DCs"
$tabControl.TabPages.Add($tabSync)

$tabRemoveCN = New-Object System.Windows.Forms.TabPage
$tabRemoveCN.Text = "Remove CN"
$tabControl.TabPages.Add($tabRemoveCN)

$tabOrphanedDomain = New-Object System.Windows.Forms.TabPage
$tabOrphanedDomain.Text = "Remove Orphaned Domain"
$tabControl.TabPages.Add($tabOrphanedDomain)

$tabLog = New-Object System.Windows.Forms.TabPage
$tabLog.Text = "View Log"
$tabControl.TabPages.Add($tabLog)

$form.Controls.Add($tabControl)

# Tab 1: Sync and Clean DCs
$domainLabel = New-Object System.Windows.Forms.Label
$domainLabel.Location = New-Object System.Drawing.Point(10, 10)
$domainLabel.Size = New-Object System.Drawing.Size(200, 20)
$domainLabel.Text = "Domain to Remove:"
$tabSync.Controls.Add($domainLabel)

$domainInput = New-Object System.Windows.Forms.TextBox
$domainInput.Location = New-Object System.Drawing.Point(220, 10)
$domainInput.Size = New-Object System.Drawing.Size(300, 20)
$tabSync.Controls.Add($domainInput)

$dcLabel = New-Object System.Windows.Forms.Label
$dcLabel.Location = New-Object System.Drawing.Point(10, 40)
$dcLabel.Size = New-Object System.Drawing.Size(200, 20)
$dcLabel.Text = "DC to Remove:"
$tabSync.Controls.Add($dcLabel)

$dcInput = New-Object System.Windows.Forms.TextBox
$dcInput.Location = New-Object System.Drawing.Point(220, 40)
$dcInput.Size = New-Object System.Drawing.Size(300, 20)
$tabSync.Controls.Add($dcInput)

$forestLabel = New-Object System.Windows.Forms.Label
$forestLabel.Location = New-Object System.Drawing.Point(10, 70)
$forestLabel.Size = New-Object System.Drawing.Size(200, 20)
$forestLabel.Text = "Forest Root Domain:"
$tabSync.Controls.Add($forestLabel)

$forestInput = New-Object System.Windows.Forms.TextBox
$forestInput.Location = New-Object System.Drawing.Point(220, 70)
$forestInput.Size = New-Object System.Drawing.Size(300, 20)
$tabSync.Controls.Add($forestInput)

$global:logBox.Location = New-Object System.Drawing.Point(10, 100)
$global:logBox.Size = New-Object System.Drawing.Size(760, 500)
$tabSync.Controls.Add($global:logBox)

# Clean Button
$cleanButton = New-Object System.Windows.Forms.Button
$cleanButton.Location = New-Object System.Drawing.Point(50, 620)
$cleanButton.Size = New-Object System.Drawing.Size(150, 50)
$cleanButton.Text = "Clean Environment"
$cleanButton.Add_Click({
    $global:domainToRemove = $domainInput.Text
    $global:dcToRemove = $dcInput.Text
    $global:forestRootDomain = $forestInput.Text

    Clean-Environment
})
$tabSync.Controls.Add($cleanButton)

# Sync Button
$syncButton = New-Object System.Windows.Forms.Button
$syncButton.Location = New-Object System.Drawing.Point(250, 620)
$syncButton.Size = New-Object System.Drawing.Size(150, 50)
$syncButton.Text = "Sync DCs"
$syncButton.Add_Click({
    $global:domainToRemove = $domainInput.Text
    $global:dcToRemove = $dcInput.Text
    $global:forestRootDomain = $forestInput.Text

    Sync-AllDCs
})
$tabSync.Controls.Add($syncButton)

# Tab 2: Remove CN
$dnLabel = New-Object System.Windows.Forms.Label
$dnLabel.Location = New-Object System.Drawing.Point(10, 10)
$dnLabel.Size = New-Object System.Drawing.Size(200, 20)
$dnLabel.Text = "Distinguished Name (DN) to Remove:"
$tabRemoveCN.Controls.Add($dnLabel)

$dnInput = New-Object System.Windows.Forms.TextBox
$dnInput.Location = New-Object System.Drawing.Point(220, 10)
$dnInput.Size = New-Object System.Drawing.Size(500, 20)
$tabRemoveCN.Controls.Add($dnInput)

$removeCNButton = New-Object System.Windows.Forms.Button
$removeCNButton.Location = New-Object System.Drawing.Point(10, 40)
$removeCNButton.Size = New-Object System.Drawing.Size(150, 30)
$removeCNButton.Text = "Remove CN"
$removeCNButton.Add_Click({
    # Convert the DN from the user input format (e.g., bossalesoffice.scriptguy.hq) to the required AD format (DC=scriptguy,DC=hq)
    $domainFormatDN = Convert-ToDCFormat -domainName $dnInput.Text
    if (-not [string]::IsNullOrWhiteSpace($domainFormatDN)) {
        Remove-CN -distinguishedName $domainFormatDN
    } else {
        Handle-Error "Please enter a valid Distinguished Name."
    }
})
$tabRemoveCN.Controls.Add($removeCNButton)

# Tab 3: Remove Orphaned Domain
$orphanedDomainLabel = New-Object System.Windows.Forms.Label
$orphanedDomainLabel.Location = New-Object System.Drawing.Point(10, 10)
$orphanedDomainLabel.Size = New-Object System.Drawing.Size(250, 20)
$orphanedDomainLabel.Text = "Orphaned Domain to Remove:"
$tabOrphanedDomain.Controls.Add($orphanedDomainLabel)

$orphanedDomainInput = New-Object System.Windows.Forms.TextBox
$orphanedDomainInput.Location = New-Object System.Drawing.Point(260, 10)
$orphanedDomainInput.Size = New-Object System.Drawing.Size(300, 20)
$tabOrphanedDomain.Controls.Add($orphanedDomainInput)

$removeOrphanedDomainButton = New-Object System.Windows.Forms.Button
$removeOrphanedDomainButton.Location = New-Object System.Drawing.Point(10, 40)
$removeOrphanedDomainButton.Size = New-Object System.Drawing.Size(150, 30)
$removeOrphanedDomainButton.Text = "Remove Orphaned Domain"
$removeOrphanedDomainButton.Add_Click({
    $orphanedDomain = $orphanedDomainInput.Text
    if (-not [string]::IsNullOrWhiteSpace($orphanedDomain)) {
        Clean-And-SyncOrphanedDomain -orphanedDomain $orphanedDomain
    } else {
        Handle-Error "Please enter a valid orphaned domain name."
    }
})
$tabOrphanedDomain.Controls.Add($removeOrphanedDomainButton)

# Tab 4: View Log
$logButton = New-Object System.Windows.Forms.Button
$logButton.Location = New-Object System.Drawing.Point(10, 10)
$logButton.Size = New-Object System.Drawing.Size(150, 50)
$logButton.Text = "View Output Log"
$logButton.Add_Click({
    Show-Log
})
$tabLog.Controls.Add($logButton)

# Show the form
$form.Add_Shown({$form.Activate()})
[void] $form.ShowDialog()

# End of script
