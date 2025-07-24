<#
.SYNOPSIS
    PowerShell Script for Creating New DHCP Reservations.

.DESCRIPTION
    This script streamlines the process of adding new DHCP reservations, allowing users to select domains, 
    DHCP scopes, and choose available IP addresses from the free range within a scope.

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

# Load Windows Forms assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Import necessary modules with error handling
try {
    Import-Module DHCPServer -ErrorAction Stop
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to import necessary modules: $_", "Module Import Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit
}

# Helper function to validate MAC address (must be 12 hexadecimal characters without separators)
function Validate-MACAddress {
    param (
        [string]$macAddress
    )
    if ($macAddress -match '^[A-Fa-f0-9]{12}$') {
        return $true
    } else {
        return $false
    }
}

# Helper functions for IP conversion
function Convert-IpToUInt32 {
    param (
        [string]$ip
    )
    try {
        $bytes = [System.Net.IPAddress]::Parse($ip).GetAddressBytes()
        [Array]::Reverse($bytes) # Convert to little-endian for UInt32
        return [BitConverter]::ToUInt32($bytes, 0)
    } catch {
        Write-Host "Invalid IP address format: $ip" -ForegroundColor Red
        return $null
    }
}

function Convert-UInt32ToIp {
    param (
        [UInt32]$int
    )
    try {
        $bytes = [BitConverter]::GetBytes($int)
        [Array]::Reverse($bytes) # Convert back to big-endian
        return [System.Net.IPAddress]::new($bytes).ToString()
    } catch {
        Write-Host "Failed to convert integer to IP: $int" -ForegroundColor Red
        return $null
    }
}

# Function to retrieve the full list of domains in the forest
function Get-ForestDomains {
    try {
        $forest = Get-ADForest
        return $forest.Domains
    } catch {
        Write-Host "Failed to retrieve forest domains: $_" -ForegroundColor Red
        return @()
    }
}

# Function to retrieve the DHCP server using Get-DhcpServerInDC for the selected domain
function Get-DHCPServerFromDomain {
    param (
        [string]$domain
    )

    try {
        $dhcpServers = Get-DhcpServerInDC
        if ($dhcpServers -and $dhcpServers.Count -gt 0) {
            foreach ($server in $dhcpServers) {
                if ($server.DNSName -like "*$domain*") {
                    return $server.DNSName  # Return the first matching server for the domain
                }
            }
            Write-Host "No authorized DHCP server found for domain ${domain}" -ForegroundColor Red
            return $null
        } else {
            Write-Host "No authorized DHCP servers found in Active Directory." -ForegroundColor Red
            return $null
        }
    } catch {
        Write-Host "Error retrieving DHCP server for domain ${domain}: $_" -ForegroundColor Red
        return $null
    }
}

# Function to add a new reservation
function Add-DhcpReservation {
    param (
        [string]$ScopeID,
        [string]$IPAddress,
        [string]$MACAddress,
        [string]$ReservationName,
        [string]$Description,
        [string]$dhcpServer
    )
    try {
        Add-DhcpServerv4Reservation -ComputerName $dhcpServer -ScopeId $ScopeID -IPAddress $IPAddress -ClientId $MACAddress -Name $ReservationName -Description $Description
        Write-Host "Reservation added for IP ${IPAddress} in Scope ${ScopeID}" -ForegroundColor Green
    } catch {
        Write-Host "Failed to add reservation: $_" -ForegroundColor Red
    }
}

# Function to gather available IPs for the DHCP scope
function Get-AvailableIPs {
    param (
        [string]$ScopeID,
        [string]$dhcpServer
    )

    try {
        # Retrieve used IPs from leases and reservations
        $usedIPs = (Get-DhcpServerv4Lease -ComputerName $dhcpServer -ScopeId $ScopeID | Select-Object -ExpandProperty IPAddress)
        $reservations = (Get-DhcpServerv4Reservation -ComputerName $dhcpServer -ScopeId $ScopeID | Select-Object -ExpandProperty IPAddress)
        $allUsedIPs = $usedIPs + $reservations

        # Retrieve DHCP scope details
        $scope = Get-DhcpServerv4Scope -ComputerName $dhcpServer -ScopeId $ScopeID
        if (-not $scope) {
            Write-Host "Scope ID $ScopeID not found on DHCP server $dhcpServer." -ForegroundColor Red
            return @()
        }

        # Convert StartRange and EndRange to strings if they are IPAddress objects
        $startIP = $scope.StartRange.ToString()
        $endIP = $scope.EndRange.ToString()

        # Convert IPs to UInt32 for iteration
        $startInt = Convert-IpToUInt32 $startIP
        $endInt = Convert-IpToUInt32 $endIP

        if ($startInt -eq $null -or $endInt -eq $null) {
            Write-Host "Invalid Start or End IP range." -ForegroundColor Red
            return @()
        }

        # Define the first available IP as x.x.x.11 based on the network
        $startOctets = ($startIP).Split(".")[0..2] -join "."
        $firstAvailableIP = "$startOctets.11"

        # Convert firstAvailableIP to UInt32
        $firstAvailableInt = Convert-IpToUInt32 $firstAvailableIP

        # Define end of available IPs as one IP before StartRange
        $endAvailableInt = $startInt - 1

        # Ensure that firstAvailableInt is less than or equal to endAvailableInt
        if ($firstAvailableInt > $endAvailableInt) {
            Write-Host "No available IPs in the specified range." -ForegroundColor Yellow
            return @()
        }

        # Generate list of available IPs, starting from $firstAvailableInt to $endAvailableInt
        $availableIPs = @()
        for ($i = $firstAvailableInt; $i -le $endAvailableInt; $i++) {
            $currentIP = Convert-UInt32ToIp $i
            if ($currentIP -and ($allUsedIPs -notcontains $currentIP)) {
                $availableIPs += $currentIP
            }
        }

        return $availableIPs
    } catch {
        Write-Host "Failed to retrieve available IPs for ScopeID ${ScopeID}: $_" -ForegroundColor Red
        return @()
    }
}

# Function to create the GUI
function Create-GUI {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'DHCP Reservation Tool'
    $form.Size = New-Object System.Drawing.Size(600, 550)
    $form.StartPosition = 'CenterScreen'

    # Title label
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = 'Manage DHCP Reservations'
    $lblTitle.Location = New-Object System.Drawing.Point(140, 10)
    $lblTitle.Size = New-Object System.Drawing.Size(320, 30)
    $lblTitle.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($lblTitle)

    # Domain Label and ComboBox
    $lblDomain = New-Object System.Windows.Forms.Label
    $lblDomain.Text = 'Select Domain:'
    $lblDomain.Location = New-Object System.Drawing.Point(30, 60)
    $lblDomain.Size = New-Object System.Drawing.Size(100, 30)
    $form.Controls.Add($lblDomain)

    $comboBoxDomains = New-Object System.Windows.Forms.ComboBox
    $comboBoxDomains.Location = New-Object System.Drawing.Point(150, 60)
    $comboBoxDomains.Size = New-Object System.Drawing.Size(400, 30)
    $comboBoxDomains.DropDownStyle = 'DropDownList'
    $domains = Get-ForestDomains
    foreach ($domain in $domains) {
        $comboBoxDomains.Items.Add($domain)
    }
    $form.Controls.Add($comboBoxDomains)

    # Scope Label and ComboBox
    $lblScope = New-Object System.Windows.Forms.Label
    $lblScope.Text = 'Select DHCP Scope:'
    $lblScope.Location = New-Object System.Drawing.Point(30, 110)
    $lblScope.Size = New-Object System.Drawing.Size(120, 30)
    $form.Controls.Add($lblScope)

    $comboBoxScopes = New-Object System.Windows.Forms.ComboBox
    $comboBoxScopes.Location = New-Object System.Drawing.Point(150, 110)
    $comboBoxScopes.Size = New-Object System.Drawing.Size(400, 30)
    $comboBoxScopes.DropDownStyle = 'DropDownList'
    $form.Controls.Add($comboBoxScopes)

    # IP Label and ComboBox
    $lblIP = New-Object System.Windows.Forms.Label
    $lblIP.Text = 'Select Available IP:'
    $lblIP.Location = New-Object System.Drawing.Point(30, 160)
    $lblIP.Size = New-Object System.Drawing.Size(120, 30)
    $form.Controls.Add($lblIP)

    $comboBoxIPs = New-Object System.Windows.Forms.ComboBox
    $comboBoxIPs.Location = New-Object System.Drawing.Point(150, 160)
    $comboBoxIPs.Size = New-Object System.Drawing.Size(400, 30)
    $comboBoxIPs.DropDownStyle = 'DropDownList'
    $form.Controls.Add($comboBoxIPs)

    # Button to find IPs
    $btnFindIPs = New-Object System.Windows.Forms.Button
    $btnFindIPs.Text = 'Find Available IPs'
    $btnFindIPs.Location = New-Object System.Drawing.Point(30, 210)
    $btnFindIPs.Size = New-Object System.Drawing.Size(200, 30)
    $form.Controls.Add($btnFindIPs)

    # Reservation Name, MAC Address, and Description Fields
    $lblName = New-Object System.Windows.Forms.Label
    $lblName.Text = 'Reservation Name:'
    $lblName.Location = New-Object System.Drawing.Point(30, 260)
    $lblName.Size = New-Object System.Drawing.Size(120, 30)
    $form.Controls.Add($lblName)

    $txtName = New-Object System.Windows.Forms.TextBox
    $txtName.Location = New-Object System.Drawing.Point(150, 260)
    $txtName.Size = New-Object System.Drawing.Size(400, 30)
    $form.Controls.Add($txtName)

    $lblMAC = New-Object System.Windows.Forms.Label
    $lblMAC.Text = 'MAC Address:'
    $lblMAC.Location = New-Object System.Drawing.Point(30, 310)
    $lblMAC.Size = New-Object System.Drawing.Size(120, 30)
    $form.Controls.Add($lblMAC)

    $txtMAC = New-Object System.Windows.Forms.TextBox
    $txtMAC.Location = New-Object System.Drawing.Point(150, 310)
    $txtMAC.Size = New-Object System.Drawing.Size(400, 30)
    $form.Controls.Add($txtMAC)

    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text = 'Description:'
    $lblDesc.Location = New-Object System.Drawing.Point(30, 360)
    $lblDesc.Size = New-Object System.Drawing.Size(120, 30)
    $form.Controls.Add($lblDesc)

    $txtDesc = New-Object System.Windows.Forms.TextBox
    $txtDesc.Location = New-Object System.Drawing.Point(150, 360)
    $txtDesc.Size = New-Object System.Drawing.Size(400, 30)
    $form.Controls.Add($txtDesc)

    # Button to Add Reservation
    $btnAddReservation = New-Object System.Windows.Forms.Button
    $btnAddReservation.Text = 'Add Reservation'
    $btnAddReservation.Location = New-Object System.Drawing.Point(30, 410)
    $btnAddReservation.Size = New-Object System.Drawing.Size(200, 40)
    $form.Controls.Add($btnAddReservation)

    # Button to close the script
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Close'
    $btnClose.Location = New-Object System.Drawing.Point(350, 410)
    $btnClose.Size = New-Object System.Drawing.Size(200, 40)
    $btnClose.Add_Click({
            $form.Close()
        })
    $form.Controls.Add($btnClose)

    # Event Handlers
    $comboBoxDomains.Add_SelectedIndexChanged({
            $selectedDomain = $comboBoxDomains.SelectedItem
            $dhcpServer = Get-DHCPServerFromDomain -domain $selectedDomain
            if ($dhcpServer) {
                $scopes = Get-DhcpServerv4Scope -ComputerName $dhcpServer
                $comboBoxScopes.Items.Clear()
                foreach ($scope in $scopes) {
                    # Ensure ScopeID is treated as string
                    $scopeID = $scope.ScopeId.ToString()
                    $scopeName = $scope.Name
                    $scopeStart = $scope.StartRange.ToString()
                    $scopeEnd = $scope.EndRange.ToString()
                    $comboBoxScopes.Items.Add("$scopeID - $scopeName - $scopeStart to $scopeEnd")
                }
            }
        })

    $btnFindIPs.Add_Click({
            $selectedScope = $comboBoxScopes.SelectedItem
            $selectedDomain = $comboBoxDomains.SelectedItem
            if ($selectedScope -and $selectedDomain) {
                $scopeID = $selectedScope.Split(" ")[0]
                $dhcpServer = Get-DHCPServerFromDomain -domain $selectedDomain
                if (-not $dhcpServer) {
                    [System.Windows.Forms.MessageBox]::Show("Failed to retrieve DHCP server.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    return
                }

                $availableIPs = Get-AvailableIPs -ScopeID $scopeID -dhcpServer $dhcpServer
                $comboBoxIPs.Items.Clear()
                if ($availableIPs.Count -gt 0) {
                    foreach ($ip in $availableIPs) {
                        $comboBoxIPs.Items.Add($ip)
                    }
                    [System.Windows.Forms.MessageBox]::Show("Available IPs retrieved successfully.", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                } else {
                    [System.Windows.Forms.MessageBox]::Show("No available IPs found in the selected scope.", "Information", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                }
            } else {
                [System.Windows.Forms.MessageBox]::Show("Please select a valid scope and domain.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            }
        })

    $btnAddReservation.Add_Click({
            $selectedScope = $comboBoxScopes.SelectedItem
            $selectedIP = $comboBoxIPs.SelectedItem
            $reservationName = $txtName.Text.Trim()
            $macAddress = $txtMAC.Text.Trim().Replace(":", "").Replace("-", "")
            $description = $txtDesc.Text.Trim()
            $selectedDomain = $comboBoxDomains.SelectedItem

            if (-not (Validate-MACAddress -macAddress $macAddress)) {
                [System.Windows.Forms.MessageBox]::Show("Invalid MAC Address. Use format: D8BBC1830F62", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }

            if ($selectedScope -and $selectedIP -and $reservationName -and $macAddress -and $description -and $selectedDomain) {
                $scopeID = $selectedScope.Split(" ")[0]
                $dhcpServer = Get-DHCPServerFromDomain -domain $selectedDomain
                if (-not $dhcpServer) {
                    [System.Windows.Forms.MessageBox]::Show("Failed to retrieve DHCP server.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    return
                }
                Add-DhcpReservation -ScopeID $scopeID -IPAddress $selectedIP -MACAddress $macAddress -ReservationName $reservationName -Description $description -dhcpServer $dhcpServer
                [System.Windows.Forms.MessageBox]::Show("Reservation added successfully.", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                # Clear input fields
                $txtName.Clear()
                $txtMAC.Clear()
                $txtDesc.Clear()
                $comboBoxIPs.SelectedIndex = -1
            } else {
                [System.Windows.Forms.MessageBox]::Show("Please complete all fields.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            }
        })

    # Show the form
    $form.ShowDialog()
}

# Run the GUI function
Create-GUI

# End of script
