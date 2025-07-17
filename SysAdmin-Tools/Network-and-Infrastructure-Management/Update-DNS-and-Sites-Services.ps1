<#
.SYNOPSIS
    PowerShell Script for Updating DNS Zones and AD Sites and Services Subnets.

.DESCRIPTION
    Automates the update of DNS reverse zones and Active Directory Sites and Services 
    subnets based on DHCP data.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: July 17, 2025
    Version: 2.4
#>

#region --- Global Setup and Logging

# Hide PowerShell window
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
        ShowWindow(handle, 0);
    }
    public static void Show() {
        var handle = GetConsoleWindow();
        ShowWindow(handle, 5);
    }
}
"@
[Window]::Hide()

# Load assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Configure logging with timestamped files
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logPath = Join-Path $logDir "$scriptName-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

if (-not (Test-Path $logDir)) {
    try { New-Item -Path $logDir -ItemType Directory -Force | Out-Null } catch { Write-Warning "Failed to create log directory: $_" }
}

function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$MessageType] $Message"
    if (Test-Path $logDir) {
        try { Add-Content -Path $logPath -Value $entry -ErrorAction Stop } catch { Write-Warning "Failed to write to log: $_" }
    } else {
        Write-Warning "Log directory missing; cannot write: $entry"
    }
}

Log-Message "Starting $scriptName execution."

#endregion

#region --- Module and Assembly Validation

# Import required modules with validation
foreach ($module in @("ActiveDirectory", "DhcpServer", "DnsServer")) {
    try {
        if (-not (Get-Module -Name $module -ListAvailable)) {
            throw "Module ${module} not found"
        }
        if (-not (Get-Module -Name $module)) {
            Import-Module $module -ErrorAction Stop
            Log-Message "${module} module loaded"
        }
    } catch {
        Log-Message "Failed to load ${module}: $($_.Exception.Message)" -MessageType "ERROR"
        Show-ErrorMessage "Missing or failed to load required module: ${module}. Please install it and retry."
        exit 1
    }
}

#endregion

#region --- Utility Functions

function Show-ErrorMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Error', 'OK', 'Error') | Out-Null
    Log-Message "ERROR: $message" -MessageType "ERROR"
}

function Get-FQDN {
    try {
        return ([System.Net.Dns]::GetHostEntry($env:COMPUTERNAME)).HostName
    } catch {
        Log-Message "WARNING: FQDN fallback to COMPUTERNAME" -MessageType "WARNING"
        return $env:COMPUTERNAME
    }
}

function Get-DomainName {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        return ($cs.Domain.Split('.')[0])
    } catch {
        Show-ErrorMessage "Unable to resolve domain. Set manually."
        return "YourDomainHere"
    }
}

function Get-PrefixLength {
    param ([string]$SubnetMask)
    $bin = ([Convert]::ToString(([IPAddress]$SubnetMask).Address, 2)).PadLeft(32, '0')
    return ($bin.ToCharArray() | Where-Object { $_ -eq '1' }).Count
}

function Get-NetworkId {
    param ([string]$IPAddress, [string]$SubnetMask)
    $ip = [IPAddress]::Parse($IPAddress)
    $mask = [IPAddress]::Parse($SubnetMask)
    $network = [byte[]]::new(4)
    for ($i = 0; $i -lt 4; $i++) {
        $network[$i] = $ip.GetAddressBytes()[$i] -band $mask.GetAddressBytes()[$i]
    }
    return [IPAddress]::new($network).ToString()
}

function Construct-ReverseZoneName {
    param ([string]$NetworkId, [int]$PrefixLength)
    $parts = $NetworkId.Split('.')
    switch ($PrefixLength) {
        24 { return "$($parts[2]).$($parts[1]).$($parts[0]).in-addr.arpa" }
        default {
            Log-Message "Unsupported CIDR: /$PrefixLength" -MessageType "WARNING"
            return ""
        }
    }
}

function Add-OrUpdate-ReverseDNSZone {
    param (
        [string]$SubnetCIDR,
        [string]$SubnetMask,
        [string]$dnsServer
    )
    if (-not [string]::IsNullOrWhiteSpace($SubnetCIDR)) {
        $subnet, $prefixLength = $SubnetCIDR -split '/'
        $networkId = Get-NetworkId -IPAddress $subnet -SubnetMask $SubnetMask

        $zoneNames = @()
        if ($prefixLength -eq 24) {
            $zoneNames += Construct-ReverseZoneName $networkId $prefixLength
        } elseif ($prefixLength -eq 22) {
            $ipBytes = [IPAddress]::Parse($networkId).GetAddressBytes()
            for ($i = 0; $i -lt 4; $i++) {
                $zoneNames += "$($ipBytes[2] + $i).$($ipBytes[1]).$($ipBytes[0]).in-addr.arpa"
            }
        } else {
            Log-Message "CIDR /$prefixLength not handled" -MessageType "WARNING"
            return
        }

        foreach ($zone in $zoneNames) {
            $existing = Get-DnsServerZone -Name $zone -ComputerName $dnsServer -ErrorAction SilentlyContinue
            try {
                if ($existing) {
                    Set-DnsServerPrimaryZone -Name $zone -DynamicUpdate NonsecureAndSecure -ComputerName $dnsServer -ErrorAction Stop
                    Log-Message "Updated DNS zone $zone"
                } else {
                    Add-DnsServerPrimaryZone -Name $zone -DynamicUpdate NonsecureAndSecure -ReplicationScope Forest -ComputerName $dnsServer -ErrorAction Stop
                    Log-Message "Created DNS zone $zone"
                }
            } catch {
                Log-Message "DNS zone failure ($zone): $($_.Exception.Message)" -MessageType "ERROR"
                Show-ErrorMessage "Failed to update/create DNS zone ${zone}: $($_.Exception.Message)"
            }
        }
    } else {
        Log-Message "Empty or invalid subnet received" -MessageType "WARNING"
    }
}

function Update-SitesAndServicesSubnets {
    param (
        [string]$SubnetCIDR,
        [string]$Location,
        [string]$Description,
        [string]$SitesAndServicesTarget
    )
    try {
        $subnet = Get-ADReplicationSubnet -Filter { Name -eq $SubnetCIDR } -ErrorAction SilentlyContinue
        if ($subnet) {
            Set-ADReplicationSubnet -Identity $subnet -Description $Description -Location $Location -Site $SitesAndServicesTarget -ErrorAction Stop
            Log-Message "Updated subnet $SubnetCIDR"
        } else {
            New-ADReplicationSubnet -Name $SubnetCIDR -Location $Location -Description $Description -Site $SitesAndServicesTarget -ErrorAction Stop
            Log-Message "Created subnet $SubnetCIDR"
        }
    } catch {
        Log-Message "AD subnet error ($SubnetCIDR): $($_.Exception.Message)" -MessageType "ERROR"
        Show-ErrorMessage "Failed to update/create AD subnet ${SubnetCIDR}: $($_.Exception.Message)"
    }
}

function Process-DHCPScopes {
    param (
        [string]$DHCPServer,
        [string]$DNSServer,
        [string]$SitesAndServicesTarget,
        [System.Windows.Forms.ProgressBar]$ProgressBar,
        [System.Windows.Forms.Label]$StatusLabel,
        [System.Windows.Forms.Button]$ExecuteButton,
        [System.Windows.Forms.Button]$CancelButton,
        [ref]$CancelRequested
    )
    try {
        Log-Message "Starting DHCP scope processing for $DHCPServer"
        $StatusLabel.Text = "Fetching DHCP scopes..."
        $scopes = Get-DhcpServerv4Scope -ComputerName $DHCPServer -ErrorAction Stop
        if (-not $scopes) {
            Show-ErrorMessage "No DHCP scopes found on server: $DHCPServer"
            return
        }

        $count = 0
        foreach ($scope in $scopes) {
            if ($CancelRequested.Value) {
                Log-Message "Process canceled by user"
                $StatusLabel.Text = "Canceled."
                return
            }

            $count++
            $subnet = $scope.ScopeId.IPAddressToString
            $mask = $scope.SubnetMask
            $cidr = "$subnet/$(Get-PrefixLength $mask)"
            $StatusLabel.Text = "Processing: $cidr ($count of $($scopes.Count))"
            $ProgressBar.Value = [math]::Round(($count / $scopes.Count) * 100)

            Log-Message "Processing subnet: $cidr"
            Add-OrUpdate-ReverseDNSZone -SubnetCIDR $cidr -SubnetMask $mask -dnsServer $DNSServer
            Update-SitesAndServicesSubnets -SubnetCIDR $cidr -Location $scope.Name -Description $scope.Description -SitesAndServicesTarget $SitesAndServicesTarget
        }

        $StatusLabel.Text = "Complete."
        $ProgressBar.Value = 100
        Log-Message "All scopes processed successfully"
    } catch {
        Log-Message "Error in Process-DHCPScopes: $($_.Exception.Message)" -MessageType "ERROR"
        $StatusLabel.Text = "Error: $($_.Exception.Message)"
        Show-ErrorMessage "Failed to process DHCP scopes: $($_.Exception.Message)"
    } finally {
        $ExecuteButton.Enabled = $true
        $CancelButton.Enabled = $false
    }
}

#endregion

#region --- GUI and Execution

# Initialize form
$form = New-Object Windows.Forms.Form
$form.Text = 'Update DNS & AD Sites'
$form.Size = New-Object System.Drawing.Size(500, 400)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

# Helper function to add controls
function Add-Control {
    param ([System.Windows.Forms.Control]$control)
    $form.Controls.Add($control)
}

# DHCP Server controls
$labelDHCP = New-Object Windows.Forms.Label; $labelDHCP.Text = 'DHCP Server:'; $labelDHCP.Location = New-Object System.Drawing.Point(10, 20); $labelDHCP.Size = New-Object System.Drawing.Size(220, 20); Add-Control $labelDHCP
$textBoxDHCP = New-Object Windows.Forms.TextBox; $textBoxDHCP.Location = New-Object System.Drawing.Point(240, 20); $textBoxDHCP.Size = New-Object System.Drawing.Size(240, 20); $textBoxDHCP.Text = Get-FQDN; Add-Control $textBoxDHCP

# DNS Server controls
$labelDNS = New-Object Windows.Forms.Label; $labelDNS.Text = 'DNS Server:'; $labelDNS.Location = New-Object System.Drawing.Point(10, 50); $labelDNS.Size = New-Object System.Drawing.Size(220, 20); Add-Control $labelDNS
$textBoxDNS = New-Object Windows.Forms.TextBox; $textBoxDNS.Location = New-Object System.Drawing.Point(240, 50); $textBoxDNS.Size = New-Object System.Drawing.Size(240, 20); $textBoxDNS.Text = Get-FQDN; Add-Control $textBoxDNS

# Sites and Services Target controls
$labelSite = New-Object Windows.Forms.Label; $labelSite.Text = 'Sites and Services Target:'; $labelSite.Location = New-Object System.Drawing.Point(10, 80); $labelSite.Size = New-Object System.Drawing.Size(220, 20); Add-Control $labelSite
$textBoxSites = New-Object Windows.Forms.TextBox; $textBoxSites.Location = New-Object System.Drawing.Point(240, 80); $textBoxSites.Size = New-Object System.Drawing.Size(240, 20); $textBoxSites.Text = Get-DomainName; Add-Control $textBoxSites

# Progress bar
$progressBar = New-Object Windows.Forms.ProgressBar; $progressBar.Location = New-Object System.Drawing.Point(10, 260); $progressBar.Size = New-Object System.Drawing.Size(470, 20); Add-Control $progressBar

# Status label
$statusLabel = New-Object Windows.Forms.Label; $statusLabel.Location = New-Object System.Drawing.Point(10, 290); $statusLabel.Size = New-Object System.Drawing.Size(470, 20); Add-Control $statusLabel

# Buttons
$cancelButton = New-Object Windows.Forms.Button; $cancelButton.Text = 'Cancel'; $cancelButton.Location = New-Object System.Drawing.Point(100, 320); $cancelButton.Size = New-Object System.Drawing.Size(75, 23); $cancelButton.Enabled = $false; Add-Control $cancelButton
$executeButton = New-Object Windows.Forms.Button; $executeButton.Text = 'Execute'; $executeButton.Location = New-Object System.Drawing.Point(10, 320); $executeButton.Size = New-Object System.Drawing.Size(75, 23); Add-Control $executeButton
$closeButton = New-Object Windows.Forms.Button; $closeButton.Text = 'Close'; $closeButton.Location = New-Object System.Drawing.Point(405, 320); $closeButton.Size = New-Object System.Drawing.Size(75, 23); Add-Control $closeButton

# Event handlers
$CancelRequested = $false

$executeButton.Add_Click({
    if ($textBoxDHCP.Text -and $textBoxDNS.Text -and $textBoxSites.Text) {
        $executeButton.Enabled = $false
        $cancelButton.Enabled = $true
        $CancelRequested = $false
        $statusLabel.Text = "Starting process..."
        Log-Message "Executing with DHCP: $($textBoxDHCP.Text), DNS: $($textBoxDNS.Text), Site: $($textBoxSites.Text)"
        Process-DHCPScopes -DHCPServer $textBoxDHCP.Text -DNSServer $textBoxDNS.Text -SitesAndServicesTarget $textBoxSites.Text `
            -ProgressBar $progressBar -StatusLabel $statusLabel -ExecuteButton $executeButton -CancelButton $cancelButton `
            -CancelRequested ([ref]$CancelRequested)
    } else {
        Show-ErrorMessage "Fill in all required fields."
    }
})

$cancelButton.Add_Click({
    $confirm = [System.Windows.Forms.MessageBox]::Show("Cancel the operation?", "Confirm", "YesNo", "Warning") | Out-Null
    if ($confirm -eq 'Yes') {
        $CancelRequested = $true
        Log-Message "User requested cancellation"
        $statusLabel.Text = "Canceling..."
    }
})

$closeButton.Add_Click({ $form.Close() })

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()

#endregion

# End of script
