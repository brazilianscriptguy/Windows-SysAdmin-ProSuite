<#
.SYNOPSIS
    Enterprise Service Port Connectivity Tester.

.DESCRIPTION
    Modernized Windows PowerShell 5.1 / Windows Server 2019 compatible GUI tool
    for testing service endpoint connectivity.

    Enterprise capabilities:
      - Structured one-endpoint-per-row service catalog.
      - Explicit TCP / UDP protocol awareness.
      - Searchable and sortable DataGridView.
      - Service profiles for common infrastructure roles.
      - Simplified operator identity model: Target and Resolved As; detailed identity remains available in logs/exports.
      - Bidirectional resolution: hostname/FQDN -> IP and IP -> reverse DNS/FQDN when PTR data is available.
      - Configurable timeout.
      - Explicit row selection.
      - TCP connect latency measurement.
      - UDP probing without falsely classifying timeout as "closed".
      - Complete result retention: successes, failures, skipped and indeterminate.
      - CSV and JSON export.
      - ProgramData-based timestamped logging.
      - No recursive logging/error-message path.
      - Cancellation between endpoint tests.
      - Console hidden by default.

    UDP NOTE:
      A generic UDP send/timeout cannot prove that a UDP port is closed.
      Therefore generic UDP tests report:
        RESPONDED       - a UDP response was received.
        INDETERMINATE   - probe sent, no response received before timeout.
        ERROR           - the local UDP operation itself failed.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    2026-08-19-v2.2.0-ENTERPRISE-AD-FOREST-PROFILES
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$ShowConsole
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# =====================================================================================
# INITIALIZATION
# =====================================================================================
try{
    if(-not $ShowConsole){
        try{
            if(-not ('NativeConsoleWindow' -as [type])){
                Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeConsoleWindow {
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public static void Hide() {
        IntPtr hWnd = GetConsoleWindow();
        if(hWnd != IntPtr.Zero) {
            ShowWindow(hWnd, 0);
        }
    }
}
"@
            }

            [NativeConsoleWindow]::Hide()
        }catch{}
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()
}
catch{
    Write-Error "Initialization failed: $($_.Exception.Message)"
    return
}

# =====================================================================================
# APPLICATION STATE
# =====================================================================================
$script:AppName = 'Enterprise Service Port Connectivity Tester'
$script:AppVersion = '2.2.0'

$script:LogRoot = Join-Path `
    ([Environment]::GetFolderPath('CommonApplicationData')) `
    'ServicePortConnectivity\Logs'

if(-not (Test-Path -LiteralPath $script:LogRoot)){
    New-Item -Path $script:LogRoot -ItemType Directory -Force | Out-Null
}

$script:LogPath = Join-Path `
    $script:LogRoot `
    ("ServicePortConnectivity-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

$script:Results = New-Object Collections.ArrayList
$script:CancelRequested = $false
$script:IsBusy = $false

$script:Grid = $null
$script:TxtLog = $null
$script:StatusMain = $null
$script:Progress = $null

# =====================================================================================
# LOGGING / UI HELPERS
# =====================================================================================
function Write-AppLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [ValidateSet('DEBUG','INFO','SUCCESS','WARN','ERROR')]
        [string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f `
        (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),
        $Level,
        $Message

    try{
        Add-Content `
            -LiteralPath $script:LogPath `
            -Value $line `
            -Encoding UTF8 `
            -ErrorAction Stop
    }catch{
        # Deliberately do not call a message function from the logger.
        if($ShowConsole){
            Write-Warning "Logging failure: $($_.Exception.Message)"
        }
    }

    if($script:TxtLog -and -not $script:TxtLog.IsDisposed){
        try{
            $script:TxtLog.AppendText($line + [Environment]::NewLine)
            $script:TxtLog.SelectionStart = $script:TxtLog.Text.Length
            $script:TxtLog.ScrollToCaret()
        }catch{}
    }
}

function Set-AppStatus {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Text
    )

    if($script:StatusMain -and -not $script:StatusMain.IsDisposed){
        $script:StatusMain.Text = $Text
        [Windows.Forms.Application]::DoEvents()
    }
}

function Show-AppMessage {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [ValidateSet('Information','Warning','Error')]
        [string]$Type = 'Information',

        [string]$Title = $script:AppName
    )

    $icon = switch($Type){
        'Warning' { [Windows.Forms.MessageBoxIcon]::Warning }
        'Error'   { [Windows.Forms.MessageBoxIcon]::Error }
        default   { [Windows.Forms.MessageBoxIcon]::Information }
    }

    [void][Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [Windows.Forms.MessageBoxButtons]::OK,
        $icon
    )
}

# =====================================================================================
# STRUCTURED SERVICE CATALOG
# =====================================================================================
function New-ServiceEndpoint {
    param(
        [string]$Profile,
        [string]$Category,
        [string]$Service,
        [ValidateSet('TCP','UDP')][string]$Protocol,
        [int]$Port,
        [bool]$Required,
        [string]$Notes = ''
    )

    [pscustomobject]@{
        Profile  = $Profile
        Category = $Category
        Service  = $Service
        Protocol = $Protocol
        Port     = $Port
        Required = $Required
        Notes    = $Notes
    }
}

$script:ServiceCatalog = @(
    # ======================================================================
    # AD FOREST - CORE CLIENT/DC SERVICES
    # ======================================================================
    New-ServiceEndpoint 'AD Forest - Core' 'AD DS' 'DNS' 'TCP' 53 $true 'Core AD DNS service.'
    New-ServiceEndpoint 'AD Forest - Core' 'AD DS' 'DNS' 'UDP' 53 $true 'Generic UDP probe can be indeterminate without a protocol response.'
    New-ServiceEndpoint 'AD Forest - Core' 'AD DS' 'Kerberos Authentication' 'TCP' 88 $true
    New-ServiceEndpoint 'AD Forest - Core' 'AD DS' 'Kerberos Authentication' 'UDP' 88 $true
    New-ServiceEndpoint 'AD Forest - Core' 'AD DS' 'RPC Endpoint Mapper' 'TCP' 135 $true 'AD operations also use dynamic RPC TCP 49152-65535; port 135 alone does not validate the dynamic range.'
    New-ServiceEndpoint 'AD Forest - Core' 'AD DS' 'LDAP' 'TCP' 389 $true
    New-ServiceEndpoint 'AD Forest - Core' 'AD DS' 'CLDAP / DC Locator' 'UDP' 389 $false 'Protocol-specific UDP response is not guaranteed with a generic probe.'
    New-ServiceEndpoint 'AD Forest - Core' 'AD DS' 'SMB / SYSVOL / NETLOGON' 'TCP' 445 $true
    New-ServiceEndpoint 'AD Forest - Core' 'AD DS' 'Kerberos Password Change' 'TCP' 464 $true
    New-ServiceEndpoint 'AD Forest - Core' 'AD DS' 'Kerberos Password Change' 'UDP' 464 $true
    New-ServiceEndpoint 'AD Forest - Core' 'AD DS' 'Windows Time' 'UDP' 123 $true 'Important for Kerberos time synchronization.'
    New-ServiceEndpoint 'AD Forest - Core' 'AD DS' 'AD Web Services' 'TCP' 9389 $false 'Used by AD Administrative Center and AD PowerShell web services.'

    # ======================================================================
    # DOMAIN CONTROLLER - FULL FIXED-PORT BASELINE
    # ======================================================================
    New-ServiceEndpoint 'Domain Controller - Full' 'AD DS' 'DNS' 'TCP' 53 $true
    New-ServiceEndpoint 'Domain Controller - Full' 'AD DS' 'DNS' 'UDP' 53 $true
    New-ServiceEndpoint 'Domain Controller - Full' 'AD DS' 'Kerberos' 'TCP' 88 $true
    New-ServiceEndpoint 'Domain Controller - Full' 'AD DS' 'Kerberos' 'UDP' 88 $true
    New-ServiceEndpoint 'Domain Controller - Full' 'AD DS' 'Windows Time' 'UDP' 123 $true
    New-ServiceEndpoint 'Domain Controller - Full' 'AD DS' 'RPC Endpoint Mapper' 'TCP' 135 $true 'Dynamic RPC TCP 49152-65535 is additionally required for multiple AD/DC operations.'
    New-ServiceEndpoint 'Domain Controller - Full' 'AD DS' 'LDAP' 'TCP' 389 $true
    New-ServiceEndpoint 'Domain Controller - Full' 'AD DS' 'CLDAP / DC Locator' 'UDP' 389 $false
    New-ServiceEndpoint 'Domain Controller - Full' 'AD DS' 'SMB / SYSVOL / NETLOGON' 'TCP' 445 $true
    New-ServiceEndpoint 'Domain Controller - Full' 'AD DS' 'Kerberos Password Change' 'TCP' 464 $true
    New-ServiceEndpoint 'Domain Controller - Full' 'AD DS' 'Kerberos Password Change' 'UDP' 464 $true
    New-ServiceEndpoint 'Domain Controller - Full' 'AD DS' 'LDAPS' 'TCP' 636 $false 'Required when LDAPS is deployed.'
    New-ServiceEndpoint 'Domain Controller - Full' 'Global Catalog' 'Global Catalog LDAP' 'TCP' 3268 $false 'Expected on Global Catalog DCs.'
    New-ServiceEndpoint 'Domain Controller - Full' 'Global Catalog' 'Global Catalog LDAPS' 'TCP' 3269 $false 'Expected on GC DCs when TLS is configured.'
    New-ServiceEndpoint 'Domain Controller - Full' 'AD DS' 'AD Web Services' 'TCP' 9389 $false

    # ======================================================================
    # FOREST GLOBAL CATALOG / LDAP
    # ======================================================================
    New-ServiceEndpoint 'Forest Global Catalog / LDAP' 'Directory' 'LDAP' 'TCP' 389 $true
    New-ServiceEndpoint 'Forest Global Catalog / LDAP' 'Directory' 'LDAPS' 'TCP' 636 $false
    New-ServiceEndpoint 'Forest Global Catalog / LDAP' 'Global Catalog' 'Global Catalog LDAP' 'TCP' 3268 $true
    New-ServiceEndpoint 'Forest Global Catalog / LDAP' 'Global Catalog' 'Global Catalog LDAPS' 'TCP' 3269 $false
    New-ServiceEndpoint 'Forest Global Catalog / LDAP' 'Directory' 'DNS' 'TCP' 53 $true
    New-ServiceEndpoint 'Forest Global Catalog / LDAP' 'Directory' 'Kerberos' 'TCP' 88 $true

    # ======================================================================
    # AD CS / PKI
    # ======================================================================
    New-ServiceEndpoint 'AD CS / PKI' 'PKI' 'RPC Endpoint Mapper / DCOM Enrollment' 'TCP' 135 $true 'Classic AD CS RPC/DCOM enrollment also depends on dynamic RPC TCP 49152-65535.'
    New-ServiceEndpoint 'AD CS / PKI' 'PKI' 'HTTP - Web Enrollment / CRL / AIA' 'TCP' 80 $false 'Only when HTTP publication or Web Enrollment is deployed.'
    New-ServiceEndpoint 'AD CS / PKI' 'PKI' 'HTTPS - CES / CEP / PKI Web' 'TCP' 443 $false 'Certificate Enrollment Web Service and Policy Web Service commonly use HTTPS.'
    New-ServiceEndpoint 'AD CS / PKI' 'Management' 'SMB Administration' 'TCP' 445 $false 'Administrative/file-share reachability only; not a universal enrollment requirement.'

    # ======================================================================
    # SMB / FILE SERVER
    # ======================================================================
    New-ServiceEndpoint 'SMB / File Server' 'File Services' 'SMB' 'TCP' 445 $true 'Primary modern Windows file-sharing port.'
    New-ServiceEndpoint 'SMB / File Server' 'File Services' 'RPC Endpoint Mapper' 'TCP' 135 $false 'Useful for remote management and DFS-related RPC scenarios; dynamic RPC may also be required.'
    New-ServiceEndpoint 'SMB / File Server' 'Legacy' 'NetBIOS Session Service' 'TCP' 139 $false 'Legacy/compatibility only.'
    New-ServiceEndpoint 'SMB / File Server' 'Legacy' 'NetBIOS Name Service' 'UDP' 137 $false 'Legacy/compatibility only.'
    New-ServiceEndpoint 'SMB / File Server' 'Legacy' 'NetBIOS Datagram Service' 'UDP' 138 $false 'Legacy/compatibility only.'
    New-ServiceEndpoint 'SMB / File Server' 'DFSR' 'DFSR Explicit/Legacy RPC Port' 'TCP' 5722 $false 'Not a universal modern DFSR requirement; use only when explicitly configured/applicable.'

    # ======================================================================
    # PRINT SERVER
    # ======================================================================
    New-ServiceEndpoint 'Print Server' 'Printing' 'RPC Endpoint Mapper' 'TCP' 135 $true 'Print Spooler remote operations also use dynamic RPC TCP 49152-65535.'
    New-ServiceEndpoint 'Print Server' 'Printing' 'SMB Print Sharing' 'TCP' 445 $true
    New-ServiceEndpoint 'Print Server' 'Printing' 'NetBIOS Session Service' 'TCP' 139 $false 'Legacy only.'
    New-ServiceEndpoint 'Print Server' 'Printing' 'NetBIOS Name Service' 'UDP' 137 $false 'Legacy only.'
    New-ServiceEndpoint 'Print Server' 'Printing' 'NetBIOS Datagram Service' 'UDP' 138 $false 'Legacy only.'
    New-ServiceEndpoint 'Print Server' 'Printing' 'LPD' 'TCP' 515 $false 'Only when LPD service is installed/enabled.'
    New-ServiceEndpoint 'Print Server' 'Printing' 'IPP' 'TCP' 631 $false 'Only when IPP is deployed.'

    # ======================================================================
    # NETWORK PRINTER / DIRECT PRINTING
    # ======================================================================
    New-ServiceEndpoint 'Network Printer' 'Printing' 'RAW / JetDirect' 'TCP' 9100 $true
    New-ServiceEndpoint 'Network Printer' 'Printing' 'LPD' 'TCP' 515 $false
    New-ServiceEndpoint 'Network Printer' 'Printing' 'IPP' 'TCP' 631 $false
    New-ServiceEndpoint 'Network Printer' 'Management' 'HTTP' 'TCP' 80 $false
    New-ServiceEndpoint 'Network Printer' 'Management' 'HTTPS' 'TCP' 443 $false
    New-ServiceEndpoint 'Network Printer' 'Management' 'SNMP' 'UDP' 161 $false 'Generic UDP probe can be indeterminate without a valid SNMP request.'

    # ======================================================================
    # WSUS
    # ======================================================================
    New-ServiceEndpoint 'WSUS Server' 'WSUS' 'WSUS HTTP' 'TCP' 8530 $true 'Default WSUS client/content HTTP port.'
    New-ServiceEndpoint 'WSUS Server' 'WSUS' 'WSUS HTTPS' 'TCP' 8531 $false 'Used when WSUS TLS/HTTPS is configured; HTTP 8530 may still be required for content.'
    New-ServiceEndpoint 'WSUS Server' 'Web' 'HTTP 80' 'TCP' 80 $false 'Custom/legacy WSUS or IIS configuration only.'
    New-ServiceEndpoint 'WSUS Server' 'Web' 'HTTPS 443' 'TCP' 443 $false 'Custom/legacy WSUS or IIS configuration only.'

    # ======================================================================
    # WINDOWS REMOTE ADMINISTRATION
    # ======================================================================
    New-ServiceEndpoint 'Windows Remote Administration' 'Management' 'WinRM HTTP' 'TCP' 5985 $true
    New-ServiceEndpoint 'Windows Remote Administration' 'Management' 'WinRM HTTPS' 'TCP' 5986 $false
    New-ServiceEndpoint 'Windows Remote Administration' 'Management' 'Remote Desktop' 'TCP' 3389 $false
    New-ServiceEndpoint 'Windows Remote Administration' 'Management' 'RPC Endpoint Mapper' 'TCP' 135 $false 'Many MMC/WMI/RPC administration scenarios also require dynamic RPC.'
    New-ServiceEndpoint 'Windows Remote Administration' 'Management' 'SMB Administrative Shares' 'TCP' 445 $false

    # ======================================================================
    # ENTERPRISE AD FOREST - COMBINED BASELINE
    # Fixed ports only. Dynamic RPC is documented but not blindly enumerated.
    # ======================================================================
    New-ServiceEndpoint 'Enterprise AD Forest - Combined' 'AD DS' 'DNS' 'TCP' 53 $true
    New-ServiceEndpoint 'Enterprise AD Forest - Combined' 'AD DS' 'DNS' 'UDP' 53 $true
    New-ServiceEndpoint 'Enterprise AD Forest - Combined' 'AD DS' 'Kerberos' 'TCP' 88 $true
    New-ServiceEndpoint 'Enterprise AD Forest - Combined' 'AD DS' 'Kerberos' 'UDP' 88 $true
    New-ServiceEndpoint 'Enterprise AD Forest - Combined' 'AD DS' 'Windows Time' 'UDP' 123 $true
    New-ServiceEndpoint 'Enterprise AD Forest - Combined' 'AD DS' 'RPC Endpoint Mapper' 'TCP' 135 $true 'Dynamic RPC TCP 49152-65535 remains a separate firewall requirement.'
    New-ServiceEndpoint 'Enterprise AD Forest - Combined' 'AD DS' 'LDAP' 'TCP' 389 $true
    New-ServiceEndpoint 'Enterprise AD Forest - Combined' 'AD DS' 'SMB' 'TCP' 445 $true
    New-ServiceEndpoint 'Enterprise AD Forest - Combined' 'AD DS' 'Kerberos Password Change' 'TCP' 464 $true
    New-ServiceEndpoint 'Enterprise AD Forest - Combined' 'AD DS' 'LDAPS' 'TCP' 636 $false
    New-ServiceEndpoint 'Enterprise AD Forest - Combined' 'Global Catalog' 'GC LDAP' 'TCP' 3268 $false
    New-ServiceEndpoint 'Enterprise AD Forest - Combined' 'Global Catalog' 'GC LDAPS' 'TCP' 3269 $false
    New-ServiceEndpoint 'Enterprise AD Forest - Combined' 'Management' 'WinRM HTTP' 'TCP' 5985 $false
    New-ServiceEndpoint 'Enterprise AD Forest - Combined' 'Management' 'WinRM HTTPS' 'TCP' 5986 $false
    New-ServiceEndpoint 'Enterprise AD Forest - Combined' 'AD DS' 'AD Web Services' 'TCP' 9389 $false
)


# =====================================================================================
# TARGET RESOLUTION
# =====================================================================================
function Resolve-Target {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Target
    )

    $value = $Target.Trim()

    if([string]::IsNullOrWhiteSpace($value)){
        throw 'Target is empty.'
    }

    $parsedIP = $null
    $isIPAddress = [Net.IPAddress]::TryParse($value,[ref]$parsedIP)

    if($isIPAddress){
        $reverseName = ''
        $allNames = @()

        try{
            $entry = [Net.Dns]::GetHostEntry($parsedIP)

            if($entry){
                if(-not [string]::IsNullOrWhiteSpace([string]$entry.HostName)){
                    $reverseName = [string]$entry.HostName
                }

                $allNames = @(
                    @($entry.HostName) +
                    @($entry.Aliases)
                ) |
                    Where-Object {
                        -not [string]::IsNullOrWhiteSpace([string]$_)
                    } |
                    Select-Object -Unique
            }
        }
        catch{
            Write-AppLog (
                "Reverse DNS lookup did not return a hostname for IP='{0}'; Error='{1}'." -f
                $value,
                $_.Exception.Message
            ) WARN
        }

        return [pscustomobject]@{
            Input              = $value
            InputType          = 'IP'
            Target             = $value
            PrimaryIP          = $value
            AllIPs             = $value
            ResolvedName       = $reverseName
            ResolvedFQDN       = $reverseName
            AllNames           = ($allNames -join ', ')
            AddressCount       = 1
            ReverseLookup      = $(if($reverseName){'SUCCESS'}else{'NOT FOUND'})
        }
    }

    try{
        $addresses = @(
            [Net.Dns]::GetHostAddresses($value) |
            Where-Object {
                $_.AddressFamily -in @(
                    [Net.Sockets.AddressFamily]::InterNetwork,
                    [Net.Sockets.AddressFamily]::InterNetworkV6
                )
            }
        )

        if($addresses.Count -eq 0){
            throw "No IPv4/IPv6 address was returned for '$value'."
        }

        $canonicalName = ''

        try{
            $entry = [Net.Dns]::GetHostEntry($value)

            if(
                $entry -and
                -not [string]::IsNullOrWhiteSpace([string]$entry.HostName)
            ){
                $canonicalName = [string]$entry.HostName
            }
        }
        catch{
            # Forward resolution already succeeded. Canonical-name lookup is secondary.
        }

        return [pscustomobject]@{
            Input              = $value
            InputType          = 'HOSTNAME/FQDN'
            Target             = $value
            PrimaryIP          = [string]$addresses[0].IPAddressToString
            AllIPs             = (($addresses | ForEach-Object {$_.IPAddressToString}) -join ', ')
            ResolvedName       = $(if($canonicalName){$canonicalName}else{$value})
            ResolvedFQDN       = $(if($canonicalName){$canonicalName}else{$value})
            AllNames           = $(if($canonicalName){$canonicalName}else{$value})
            AddressCount       = $addresses.Count
            ReverseLookup      = 'N/A'
        }
    }
    catch{
        throw "Unable to resolve target '$value': $($_.Exception.Message)"
    }
}

# =====================================================================================
# CONNECTIVITY ENGINE
# =====================================================================================
function Test-TcpEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Target,
        [Parameter(Mandatory=$true)][int]$Port,
        [Parameter(Mandatory=$true)][int]$TimeoutMs
    )

    $client = New-Object Net.Sockets.TcpClient
    $watch = [Diagnostics.Stopwatch]::StartNew()

    try{
        $iar = $client.BeginConnect($Target,$Port,$null,$null)

        if(-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs,$false)){
            $watch.Stop()

            return [pscustomobject]@{
                Status    = 'FAILED'
                Reachable = $false
                LatencyMs = [int]$watch.ElapsedMilliseconds
                Detail    = "TCP connect timeout after ${TimeoutMs}ms."
            }
        }

        $client.EndConnect($iar)
        $watch.Stop()

        return [pscustomobject]@{
            Status    = 'OPEN'
            Reachable = $true
            LatencyMs = [int]$watch.ElapsedMilliseconds
            Detail    = 'TCP connection established.'
        }
    }
    catch{
        $watch.Stop()

        return [pscustomobject]@{
            Status    = 'FAILED'
            Reachable = $false
            LatencyMs = [int]$watch.ElapsedMilliseconds
            Detail    = $_.Exception.Message
        }
    }
    finally{
        try{$client.Close()}catch{}
    }
}

function Test-UdpEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Target,
        [Parameter(Mandatory=$true)][int]$Port,
        [Parameter(Mandatory=$true)][int]$TimeoutMs
    )

    $udp = New-Object Net.Sockets.UdpClient
    $watch = [Diagnostics.Stopwatch]::StartNew()

    try{
        $udp.Client.ReceiveTimeout = $TimeoutMs
        $udp.Connect($Target,$Port)

        # A minimal generic probe. Success only proves the local UDP send path.
        $payload = [byte[]](0)
        [void]$udp.Send($payload,$payload.Length)

        try{
            $remote = New-Object Net.IPEndPoint([Net.IPAddress]::Any,0)
            $response = $udp.Receive([ref]$remote)

            $watch.Stop()

            return [pscustomobject]@{
                Status    = 'RESPONDED'
                Reachable = $true
                LatencyMs = [int]$watch.ElapsedMilliseconds
                Detail    = "UDP response received from $($remote.Address):$($remote.Port); Bytes=$($response.Length)."
            }
        }
        catch [Net.Sockets.SocketException]{
            $watch.Stop()

            return [pscustomobject]@{
                Status    = 'INDETERMINATE'
                Reachable = $null
                LatencyMs = [int]$watch.ElapsedMilliseconds
                Detail    = 'UDP probe sent; no application response received before timeout. This does not prove that the port is closed.'
            }
        }
    }
    catch{
        $watch.Stop()

        return [pscustomobject]@{
            Status    = 'ERROR'
            Reachable = $false
            LatencyMs = [int]$watch.ElapsedMilliseconds
            Detail    = $_.Exception.Message
        }
    }
    finally{
        try{$udp.Close()}catch{}
    }
}

function Invoke-EndpointTest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Endpoint,
        [Parameter(Mandatory=$true)][string]$Target,
        [Parameter(Mandatory=$true)][string]$ResolvedIP,
        [Parameter(Mandatory=$true)][int]$TimeoutMs
    )

    $started = Get-Date

    $probe = if($Endpoint.Protocol -eq 'TCP'){
        Test-TcpEndpoint `
            -Target $Target `
            -Port ([int]$Endpoint.Port) `
            -TimeoutMs $TimeoutMs
    }else{
        Test-UdpEndpoint `
            -Target $Target `
            -Port ([int]$Endpoint.Port) `
            -TimeoutMs $TimeoutMs
    }

    [pscustomobject]@{
        Timestamp        = $started
        InputTarget      = $Target
        Target           = $Target
        ResolvedIP       = $ResolvedIP
        ResolvedFQDN     = ''
        ResolvedName     = ''
        InputType        = ''
        Profile        = $Endpoint.Profile
        Category   = $Endpoint.Category
        Service    = $Endpoint.Service
        Protocol   = $Endpoint.Protocol
        Port       = [int]$Endpoint.Port
        Required   = [bool]$Endpoint.Required
        Status     = [string]$probe.Status
        Reachable  = $probe.Reachable
        LatencyMs  = [int]$probe.LatencyMs
        Detail     = [string]$probe.Detail
        Notes      = [string]$Endpoint.Notes
    }
}

# =====================================================================================
# EXPORT
# =====================================================================================
function Export-ResultSet {
    [CmdletBinding()]
    param(
        [ValidateSet('CSV','JSON')]
        [string]$Format
    )

    if($script:Results.Count -eq 0){
        Show-AppMessage 'There are no test results to export.' Warning
        return
    }

    $dialog = New-Object Windows.Forms.SaveFileDialog

    if($Format -eq 'CSV'){
        $dialog.Filter = 'CSV files (*.csv)|*.csv'
        $dialog.FileName = "Service-Port-Connectivity-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss')
    }else{
        $dialog.Filter = 'JSON files (*.json)|*.json'
        $dialog.FileName = "Service-Port-Connectivity-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss')
    }

    if($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){
        return
    }

    try{
        if($Format -eq 'CSV'){
            $script:Results |
                Export-Csv `
                    -LiteralPath $dialog.FileName `
                    -NoTypeInformation `
                    -Encoding UTF8
        }else{
            [pscustomobject]@{
                Generated = (Get-Date).ToString('o')
                Application = $script:AppName
                Version = $script:AppVersion
                Results = @($script:Results)
            } |
                ConvertTo-Json -Depth 5 |
                Set-Content -LiteralPath $dialog.FileName -Encoding UTF8
        }

        Write-AppLog "$Format results exported to '$($dialog.FileName)'." SUCCESS
        Show-AppMessage "$Format results exported successfully.`r`n`r`n$($dialog.FileName)" Information
    }
    catch{
        Write-AppLog "$Format export failed: $($_.Exception.Message)" ERROR
        Show-AppMessage "$Format export failed:`r`n`r`n$($_.Exception.Message)" Error
    }
}

# =====================================================================================
# GUI
# =====================================================================================
$form = New-Object Windows.Forms.Form
$form.Text = "$($script:AppName) - v$($script:AppVersion)"
$form.Size = New-Object Drawing.Size(1280,820)
$form.MinimumSize = New-Object Drawing.Size(1080,700)
$form.StartPosition = 'CenterScreen'

$main = New-Object Windows.Forms.TableLayoutPanel
$main.Dock = 'Fill'
$main.Padding = New-Object Windows.Forms.Padding(10)
$main.ColumnCount = 1
$main.RowCount = 6

$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',65)))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',35)))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))

$form.Controls.Add($main)

# Target row
$pTarget = New-Object Windows.Forms.TableLayoutPanel
$pTarget.Dock = 'Fill'
$pTarget.AutoSize = $true
$pTarget.ColumnCount = 8
$pTarget.RowCount = 1

$pTarget.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pTarget.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',55)))
$pTarget.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pTarget.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',45)))
$pTarget.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pTarget.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pTarget.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pTarget.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))

$lblTarget = New-Object Windows.Forms.Label
$lblTarget.Text = 'Target:'
$lblTarget.AutoSize = $true
$lblTarget.Anchor = 'Left'
$pTarget.Controls.Add($lblTarget,0,0)

$txtTarget = New-Object Windows.Forms.TextBox
$txtTarget.Dock = 'Fill'
$pTarget.Controls.Add($txtTarget,1,0)

$lblResolved = New-Object Windows.Forms.Label
$lblResolved.Text = 'Resolved As:'
$lblResolved.AutoSize = $true
$lblResolved.Anchor = 'Left'
$pTarget.Controls.Add($lblResolved,2,0)

$txtResolved = New-Object Windows.Forms.TextBox
$txtResolved.Dock = 'Fill'
$txtResolved.ReadOnly = $true
$pTarget.Controls.Add($txtResolved,3,0)

$lblTimeout = New-Object Windows.Forms.Label
$lblTimeout.Text = 'Timeout ms:'
$lblTimeout.AutoSize = $true
$lblTimeout.Anchor = 'Left'
$pTarget.Controls.Add($lblTimeout,4,0)

$numTimeout = New-Object Windows.Forms.NumericUpDown
$numTimeout.Minimum = 250
$numTimeout.Maximum = 30000
$numTimeout.Increment = 250
$numTimeout.Value = 2500
$numTimeout.Width = 80
$pTarget.Controls.Add($numTimeout,5,0)

$btnResolve = New-Object Windows.Forms.Button
$btnResolve.Text = 'Resolve'
$btnResolve.Width = 85
$pTarget.Controls.Add($btnResolve,6,0)

$btnClearTarget = New-Object Windows.Forms.Button
$btnClearTarget.Text = 'Clear'
$btnClearTarget.Width = 70
$pTarget.Controls.Add($btnClearTarget,7,0)

$main.Controls.Add($pTarget,0,0)

# Filter/profile row
$pFilter = New-Object Windows.Forms.TableLayoutPanel
$pFilter.Dock = 'Fill'
$pFilter.AutoSize = $true
$pFilter.ColumnCount = 10
$pFilter.RowCount = 1

$pFilter.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pFilter.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pFilter.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pFilter.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
for($i=4;$i -lt 10;$i++){
    $pFilter.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
}

$lblProfile = New-Object Windows.Forms.Label
$lblProfile.Text = 'Profile:'
$lblProfile.AutoSize = $true
$lblProfile.Anchor = 'Left'
$pFilter.Controls.Add($lblProfile,0,0)

$cmbProfile = New-Object Windows.Forms.ComboBox
$cmbProfile.DropDownStyle = 'DropDownList'
$cmbProfile.Width = 220

$profiles = @('All') + @(
    $script:ServiceCatalog |
    Select-Object -ExpandProperty Profile -Unique |
    Sort-Object
)

foreach($profile in $profiles){
    [void]$cmbProfile.Items.Add($profile)
}

$cmbProfile.SelectedIndex = 0
$pFilter.Controls.Add($cmbProfile,1,0)

$lblFilter = New-Object Windows.Forms.Label
$lblFilter.Text = 'Filter all columns:'
$lblFilter.AutoSize = $true
$lblFilter.Anchor = 'Left'
$pFilter.Controls.Add($lblFilter,2,0)

$txtFilter = New-Object Windows.Forms.TextBox
$txtFilter.Dock = 'Fill'
$pFilter.Controls.Add($txtFilter,3,0)

$btnClearFilter = New-Object Windows.Forms.Button
$btnClearFilter.Text = 'Clear Filter'
$btnClearFilter.Width = 85
$pFilter.Controls.Add($btnClearFilter,4,0)

$btnSelectRequired = New-Object Windows.Forms.Button
$btnSelectRequired.Text = 'Select Required'
$btnSelectRequired.Width = 100
$pFilter.Controls.Add($btnSelectRequired,5,0)

$btnSelectAll = New-Object Windows.Forms.Button
$btnSelectAll.Text = 'Select All'
$btnSelectAll.Width = 75
$pFilter.Controls.Add($btnSelectAll,6,0)

$btnSelectNone = New-Object Windows.Forms.Button
$btnSelectNone.Text = 'Select None'
$btnSelectNone.Width = 80
$pFilter.Controls.Add($btnSelectNone,7,0)

$btnRun = New-Object Windows.Forms.Button
$btnRun.Text = 'Run Selected'
$btnRun.Width = 95
$pFilter.Controls.Add($btnRun,8,0)

$btnCancel = New-Object Windows.Forms.Button
$btnCancel.Text = 'Cancel'
$btnCancel.Width = 70
$pFilter.Controls.Add($btnCancel,9,0)

$main.Controls.Add($pFilter,0,1)

# DataGridView
$grid = New-Object Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.AllowUserToOrderColumns = $true
$grid.MultiSelect = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.AutoSizeColumnsMode = 'None'
$grid.RowHeadersVisible = $false
$grid.EditMode = 'EditOnEnter'
$script:Grid = $grid

$columns = @(
    @{Name='Selected'; Header='Run'; Width=45; Type='CheckBox'},
    @{Name='Profile'; Header='Profile'; Width=180},
    @{Name='Category'; Header='Category'; Width=105},
    @{Name='Service'; Header='Service'; Width=210},
    @{Name='Protocol'; Header='Protocol'; Width=70},
    @{Name='Port'; Header='Port'; Width=65},
    @{Name='Required'; Header='Required'; Width=70},
    @{Name='Status'; Header='Status'; Width=105},
    @{Name='LatencyMs'; Header='Latency ms'; Width=80},
    @{Name='InputTarget'; Header='Target'; Width=190},
    @{Name='ResolvedAs'; Header='Resolved As'; Width=210},
    @{Name='Detail'; Header='Detail'; Width=380}
)

foreach($col in $columns){
    # Under Set-StrictMode, reading a non-existent hashtable key as a property
    # (for example $col.Type when Type was not defined) throws PropertyNotFoundStrict.
    # Use ContainsKey() so ordinary text-column definitions do not require Type.
    if($col.ContainsKey('Type') -and $col['Type'] -eq 'CheckBox'){
        $c = New-Object Windows.Forms.DataGridViewCheckBoxColumn
    }else{
        $c = New-Object Windows.Forms.DataGridViewTextBoxColumn
        $c.ReadOnly = $true
        $c.SortMode = 'Automatic'
    }

    $c.Name = $col.Name
    $c.HeaderText = $col.Header
    $c.Width = $col.Width
    [void]$grid.Columns.Add($c)
}

$main.Controls.Add($grid,0,2)

# Action/export row
$pActions = New-Object Windows.Forms.FlowLayoutPanel
$pActions.Dock = 'Fill'
$pActions.AutoSize = $true
$pActions.FlowDirection = 'LeftToRight'

$btnExportCsv = New-Object Windows.Forms.Button
$btnExportCsv.Text = 'Export CSV'
$btnExportCsv.Width = 90
$pActions.Controls.Add($btnExportCsv)

$btnExportJson = New-Object Windows.Forms.Button
$btnExportJson.Text = 'Export JSON'
$btnExportJson.Width = 90
$pActions.Controls.Add($btnExportJson)

$btnClearResults = New-Object Windows.Forms.Button
$btnClearResults.Text = 'Clear Results'
$btnClearResults.Width = 95
$pActions.Controls.Add($btnClearResults)

$btnOpenLog = New-Object Windows.Forms.Button
$btnOpenLog.Text = 'Open Log'
$btnOpenLog.Width = 80
$pActions.Controls.Add($btnOpenLog)

$lblSummary = New-Object Windows.Forms.Label
$lblSummary.AutoSize = $true
$lblSummary.Margin = New-Object Windows.Forms.Padding(20,7,0,0)
$lblSummary.Text = 'Results: 0'
$pActions.Controls.Add($lblSummary)

$main.Controls.Add($pActions,0,3)

# Runtime log
$txtLog = New-Object Windows.Forms.TextBox
$txtLog.Dock = 'Fill'
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Both'
$txtLog.WordWrap = $false
$txtLog.Font = New-Object Drawing.Font('Consolas',8.5)
$script:TxtLog = $txtLog
$main.Controls.Add($txtLog,0,4)

# Status strip
$statusStrip = New-Object Windows.Forms.StatusStrip

$statusMain = New-Object Windows.Forms.ToolStripStatusLabel
$statusMain.Spring = $true
$statusMain.Text = 'Ready'
$script:StatusMain = $statusMain
[void]$statusStrip.Items.Add($statusMain)

$progress = New-Object Windows.Forms.ToolStripProgressBar
$progress.Minimum = 0
$progress.Maximum = 1
$progress.Value = 0
$progress.Width = 180
$script:Progress = $progress
[void]$statusStrip.Items.Add($progress)

$statusLog = New-Object Windows.Forms.ToolStripStatusLabel
$statusLog.Text = "Log: $([IO.Path]::GetFileName($script:LogPath))"
[void]$statusStrip.Items.Add($statusLog)

$main.Controls.Add($statusStrip,0,5)

# =====================================================================================
# GRID / FILTER HELPERS
# =====================================================================================
function Get-VisibleCatalog {
    $profile = [string]$cmbProfile.SelectedItem
    $filter = $txtFilter.Text.Trim()

    @(
        $script:ServiceCatalog |
        Where-Object {
            ($profile -eq 'All' -or $_.Profile -eq $profile) -and
            (
                [string]::IsNullOrWhiteSpace($filter) -or
                $_.Profile.IndexOf($filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                $_.Category.IndexOf($filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                $_.Service.IndexOf($filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                $_.Protocol.IndexOf($filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                ([string]$_.Port).IndexOf($filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                ([string]$_.Required).IndexOf($filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                $_.Notes.IndexOf($filter,[StringComparison]::OrdinalIgnoreCase) -ge 0
            )
        }
    )
}

function Refresh-Grid {
    $selectionState = @{}

    foreach($row in $grid.Rows){
        if($row.Tag){
            $key = '{0}|{1}|{2}|{3}' -f `
                $row.Tag.Profile,
                $row.Tag.Service,
                $row.Tag.Protocol,
                $row.Tag.Port

            $selectionState[$key] = [bool]$row.Cells['Selected'].Value
        }
    }

    $grid.Rows.Clear()

    foreach($endpoint in @(Get-VisibleCatalog)){
        $key = '{0}|{1}|{2}|{3}' -f `
            $endpoint.Profile,
            $endpoint.Service,
            $endpoint.Protocol,
            $endpoint.Port

        $selected = if($selectionState.ContainsKey($key)){
            $selectionState[$key]
        }else{
            [bool]$endpoint.Required
        }

        $index = $grid.Rows.Add(
            $selected,
            $endpoint.Profile,
            $endpoint.Category,
            $endpoint.Service,
            $endpoint.Protocol,
            $endpoint.Port,
            $endpoint.Required,
            '',
            '',
            '',
            '',
            $endpoint.Notes
        )

        $grid.Rows[$index].Tag = $endpoint
    }

    Set-AppStatus "Displayed $($grid.Rows.Count) service endpoint(s)."
}

function Set-GridSelection {
    param(
        [ValidateSet('All','None','Required')]
        [string]$Mode
    )

    foreach($row in $grid.Rows){
        switch($Mode){
            'All'      { $row.Cells['Selected'].Value = $true }
            'None'     { $row.Cells['Selected'].Value = $false }
            'Required' { $row.Cells['Selected'].Value = [bool]$row.Tag.Required }
        }
    }
}

function Update-ResultSummary {
    $total = $script:Results.Count
    $open = @($script:Results | Where-Object {$_.Status -in @('OPEN','RESPONDED')}).Count
    $failed = @($script:Results | Where-Object {$_.Status -in @('FAILED','ERROR')}).Count
    $indeterminate = @($script:Results | Where-Object {$_.Status -eq 'INDETERMINATE'}).Count

    $lblSummary.Text = (
        "Results: {0} | Open/Responded: {1} | Failed/Error: {2} | UDP Indeterminate: {3}" -f
        $total,$open,$failed,$indeterminate
    )
}

function Apply-ResultToRow {
    param(
        [Parameter(Mandatory=$true)]$GridRow,
        [Parameter(Mandatory=$true)]$Result
    )

    $GridRow.Cells['Status'].Value = $Result.Status
    $GridRow.Cells['LatencyMs'].Value = $Result.LatencyMs
    $GridRow.Cells['InputTarget'].Value = $Result.InputTarget
    $GridRow.Cells['ResolvedAs'].Value = if($Result.InputType -eq 'IP'){
        if([string]::IsNullOrWhiteSpace($Result.ResolvedFQDN)){'NOT FOUND'}else{$Result.ResolvedFQDN}
    }else{
        $Result.ResolvedIP
    }
    $GridRow.Cells['Detail'].Value = $Result.Detail

    switch($Result.Status){
        'OPEN' {
            $GridRow.DefaultCellStyle.BackColor = [Drawing.Color]::Honeydew
        }
        'RESPONDED' {
            $GridRow.DefaultCellStyle.BackColor = [Drawing.Color]::Honeydew
        }
        'INDETERMINATE' {
            $GridRow.DefaultCellStyle.BackColor = [Drawing.Color]::LemonChiffon
        }
        default {
            $GridRow.DefaultCellStyle.BackColor = [Drawing.Color]::MistyRose
        }
    }
}

# =====================================================================================
# EVENTS
# =====================================================================================
$btnResolve.Add_Click({
    try{
        $resolved = Resolve-Target -Target $txtTarget.Text

        $txtResolved.Text = if($resolved.InputType -eq 'IP'){
            if([string]::IsNullOrWhiteSpace($resolved.ResolvedFQDN)){'NOT FOUND'}else{$resolved.ResolvedFQDN}
        }else{
            $resolved.AllIPs
        }

        Write-AppLog (
            "Target identity resolved: InputTarget='{0}'; InputType='{1}'; ResolvedFQDN='{2}'; PrimaryIP='{3}'; AllResolvedIPs='{4}'; ReverseLookup='{5}'." -f
            $resolved.Input,
            $resolved.InputType,
            $resolved.ResolvedFQDN,
            $resolved.PrimaryIP,
            $resolved.AllIPs,
            $resolved.ReverseLookup
        ) SUCCESS

        if($resolved.InputType -eq 'IP'){
            Set-AppStatus (
                "IP '$($resolved.Input)' -> Name '$($resolved.ResolvedFQDN)'"
            )
        }else{
            Set-AppStatus (
                "Name '$($resolved.Input)' -> IP '$($resolved.PrimaryIP)'"
            )
        }
    }
    catch{
        $txtResolved.Clear()
        Write-AppLog "Target resolution failed: $($_.Exception.Message)" ERROR
        Show-AppMessage $_.Exception.Message Error
    }
})

$btnClearTarget.Add_Click({
    $txtTarget.Clear()
    $txtResolved.Clear()
})

$cmbProfile.Add_SelectedIndexChanged({
    Refresh-Grid
})

$txtFilter.Add_TextChanged({
    Refresh-Grid
})

$btnClearFilter.Add_Click({
    $txtFilter.Clear()
})

$btnSelectRequired.Add_Click({
    Set-GridSelection Required
})

$btnSelectAll.Add_Click({
    Set-GridSelection All
})

$btnSelectNone.Add_Click({
    Set-GridSelection None
})

$btnCancel.Add_Click({
    if($script:IsBusy){
        $script:CancelRequested = $true
        Write-AppLog 'Cancellation requested by operator.' WARN
        Set-AppStatus 'Cancellation requested...'
    }
})

$btnRun.Add_Click({
    if($script:IsBusy){
        return
    }

    try{
        $selectedRows = @(
            $grid.Rows |
            Where-Object {
                $_.Tag -and
                [bool]$_.Cells['Selected'].Value
            }
        )

        if($selectedRows.Count -eq 0){
            Show-AppMessage 'Select at least one service endpoint to test.' Warning
            return
        }

        $resolved = Resolve-Target -Target $txtTarget.Text
        $txtResolved.Text = if($resolved.InputType -eq 'IP'){
            if([string]::IsNullOrWhiteSpace($resolved.ResolvedFQDN)){'NOT FOUND'}else{$resolved.ResolvedFQDN}
        }else{
            $resolved.AllIPs
        }

        $script:IsBusy = $true
        $script:CancelRequested = $false

        $script:Progress.Maximum = [Math]::Max(1,$selectedRows.Count)
        $script:Progress.Value = 0

        $timeout = [int]$numTimeout.Value
        $index = 0

        Write-AppLog (
            "Connectivity run started. InputTarget='{0}'; InputType='{1}'; ResolvedFQDN='{2}'; ResolvedIP='{3}'; Endpoints={4}; TimeoutMs={5}." -f
            $resolved.Input,
            $resolved.InputType,
            $resolved.ResolvedFQDN,
            $resolved.PrimaryIP,
            $selectedRows.Count,
            $timeout
        ) INFO

        foreach($row in $selectedRows){
            if($script:CancelRequested){
                Write-AppLog 'Connectivity run cancelled by operator.' WARN
                Set-AppStatus 'Connectivity run cancelled.'
                break
            }

            $index++
            $endpoint = $row.Tag

            Set-AppStatus (
                "Testing {0}/{1}: {2} {3}/{4}" -f
                $index,
                $selectedRows.Count,
                $endpoint.Service,
                $endpoint.Protocol,
                $endpoint.Port
            )

            $script:Progress.Value = $index
            [Windows.Forms.Application]::DoEvents()

            $result = Invoke-EndpointTest `
                -Endpoint $endpoint `
                -Target $resolved.Target `
                -ResolvedIP $resolved.PrimaryIP `
                -TimeoutMs $timeout

            $result.ResolvedFQDN = $resolved.ResolvedFQDN
            $result.ResolvedName = $resolved.ResolvedFQDN
            $result.InputType = $resolved.InputType

            [void]$script:Results.Add($result)
            Apply-ResultToRow -GridRow $row -Result $result

            $level = switch($result.Status){
                'OPEN'          {'SUCCESS'}
                'RESPONDED'     {'SUCCESS'}
                'INDETERMINATE' {'WARN'}
                default         {'ERROR'}
            }

            Write-AppLog (
                "Test: InputTarget='{0}'; ResolvedIP='{1}'; ResolvedFQDN='{2}'; Service='{3}'; Protocol='{4}'; Port={5}; Status='{6}'; LatencyMs={7}; Detail='{8}'." -f
                $result.InputTarget,
                $result.ResolvedIP,
                $result.ResolvedFQDN,
                $result.Service,
                $result.Protocol,
                $result.Port,
                $result.Status,
                $result.LatencyMs,
                $result.Detail
            ) $level

            Update-ResultSummary
        }

        if(-not $script:CancelRequested){
            Set-AppStatus 'Connectivity run completed.'
            Write-AppLog 'Connectivity run completed.' SUCCESS
        }
    }
    catch{
        Write-AppLog "Connectivity run failed: $($_.Exception.Message)" ERROR
        Set-AppStatus 'Connectivity run failed.'
        Show-AppMessage "Connectivity run failed:`r`n`r`n$($_.Exception.Message)" Error
    }
    finally{
        $script:IsBusy = $false
        $script:CancelRequested = $false
        $script:Progress.Value = 0
    }
})

$btnExportCsv.Add_Click({
    Export-ResultSet CSV
})

$btnExportJson.Add_Click({
    Export-ResultSet JSON
})

$btnClearResults.Add_Click({
    $script:Results.Clear()

    foreach($row in $grid.Rows){
        $row.Cells['Status'].Value = ''
        $row.Cells['LatencyMs'].Value = ''
        $row.Cells['InputTarget'].Value = ''
        $row.Cells['ResolvedAs'].Value = ''
        $row.Cells['Detail'].Value = $row.Tag.Notes
        $row.DefaultCellStyle.BackColor = [Drawing.Color]::White
    }

    Update-ResultSummary
    Write-AppLog 'Runtime result set cleared.' INFO
})

$btnOpenLog.Add_Click({
    try{
        Start-Process notepad.exe -ArgumentList $script:LogPath
    }
    catch{
        Show-AppMessage "Unable to open the log:`r`n$($_.Exception.Message)" Error
    }
})

$form.Add_Shown({
    Write-AppLog 'Starting Enterprise Service Port Connectivity Tester.' INFO
    Write-AppLog (
        "Management Computer: {0}; PowerShell: {1}; OS: {2}" -f
        $env:COMPUTERNAME,
        $PSVersionTable.PSVersion,
        [Environment]::OSVersion.VersionString
    ) INFO

    Refresh-Grid
    Update-ResultSummary
    Set-AppStatus 'Ready. Enter a target, select endpoints, and run the test.'
})

$form.Add_FormClosed({
    Write-AppLog 'Closing Enterprise Service Port Connectivity Tester.' INFO
})

# =====================================================================================
# MAIN
# =====================================================================================
try{
    [void]$form.ShowDialog()
}
catch{
    Write-AppLog "Fatal error: $($_.Exception.Message)" ERROR

    Show-AppMessage (
        "Fatal error:`r`n`r`n$($_.Exception.Message)"
    ) Error
}

# End of script
