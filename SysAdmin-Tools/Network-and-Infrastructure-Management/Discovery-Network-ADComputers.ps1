<#
.SYNOPSIS
    Workstation Discovery Tool - Active Directory Workstation Inventory and List Export (GUI)

.DESCRIPTION
    Provides a Windows Forms GUI to query Active Directory for Windows workstations (non-server),
    resolve IPv4 addresses (AD attribute → DNS → optional ping fallback), and export clean lists
    in a user-selected format:
      - Unique IPv4 addresses (TXT)
      - Short computer names / NetBIOS (TXT)
      - Fully qualified domain names / FQDN (TXT)
      - Full detailed report (CSV)

.AUTHOR
    Luiz Hamilton Silva - 

.VERSION
    1.3 - January 2026
    - Full Windows PowerShell 5.1 compatibility
    - Current domain, specific domain, and forest-wide scope support
    - Smart output naming based on scope and selected export format

.NOTES
    Requirements:
      - RSAT / ActiveDirectory module available on the machine running the script
      - DNS resolution permissions as required by your environment
#>

# ===========================
#   Hide PowerShell Console
# ===========================
Add-Type -TypeDefinition @"
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
        ShowWindow(handle, 0); // SW_HIDE
    }
}
"@
[Window]::Hide()

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ===========================
#          Logging
# ===========================
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "{0}_{1}.log" -f $scriptName, (Get-Date -Format 'yyyyMMdd_HHmmss')
$logPath = Join-Path $logDir $logFileName

if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR')][string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    ("[{0}] [{1}] {2}" -f $timestamp, $Level, $Message) | Add-Content -Path $logPath -ErrorAction SilentlyContinue
}

function Show-Message {
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Title = 'Information',
        [ValidateSet('Information', 'Warning', 'Error')][string]$Icon = 'Information'
    )

    $mbIcon = [System.Windows.Forms.MessageBoxIcon]::$Icon
    [void][System.Windows.Forms.MessageBox]::Show($Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $mbIcon)

    $lvl = switch ($Icon) {
        'Error' { 'ERROR' }
        'Warning' { 'WARNING' }
        default { 'INFO' }
    }
    Write-Log -Message ("{0} - {1}" -f $Title, $Text) -Level $lvl
}

# ===========================
#      Domain Discovery
# ===========================
function Get-CurrentDomainFQDN {
    try {
        $cs = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
        if ($cs.Domain -and $cs.Domain.Trim() -ne '') {
            return $cs.Domain.Trim()
        }
        throw "Domain was not returned by Win32_ComputerSystem."
    }
    catch {
        Write-Log -Message ("Current domain detection via WMI failed: {0}" -f $_.Exception.Message) -Level 'WARNING'
        if ($env:USERDNSDOMAIN -and $env:USERDNSDOMAIN.Trim() -ne '') {
            return $env:USERDNSDOMAIN.Trim()
        }
        return 'UnknownDomain'
    }
}

# ===========================
#   Workstation Collection
# ===========================
function Get-WorkstationData {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Current', 'Specific', 'Forest')]
        [string]$Scope,

        [string]$SpecificDomain = '',
        [string]$SearchBase = '',

        [bool]$OnlyEnabled = $true,
        [bool]$SkipPing = $true,

        [int]$PingTimeoutMs = 1200
    )

    $domains = @()

    switch ($Scope) {
        'Current' { $domains += (Get-CurrentDomainFQDN) }
        'Specific' {
            if ([string]::IsNullOrWhiteSpace($SpecificDomain)) {
                throw 'No specific domain was selected.'
            }
            $domains += $SpecificDomain.Trim()
        }
        'Forest' {
            try {
                $forest = Get-ADForest -ErrorAction Stop
                $domains = @($forest.Domains)
                Write-Log -Message ("Forest scope selected. Domains discovered: {0}" -f $domains.Count) -Level 'INFO'
            }
            catch {
                throw ("Failed to retrieve forest domains: {0}" -f $_.Exception.Message)
            }
        }
    }

    $allResults = @()

    foreach ($domain in $domains) {
        Write-Log -Message ("Querying Active Directory domain: {0}" -f $domain) -Level 'INFO'

        $adFilter = "OperatingSystem -notlike '*server*' -and OperatingSystem -like 'Windows*'"
        if ($OnlyEnabled) { $adFilter += " -and Enabled -eq 'true'" }

        $adParams = @{
            Filter = $adFilter
            Properties = 'Name', 'DNSHostName', 'IPv4Address', 'Enabled', 'LastLogonDate', 'DistinguishedName'
            Server = $domain
            ErrorAction = 'Stop'
        }
        if (-not [string]::IsNullOrWhiteSpace($SearchBase)) {
            $adParams.SearchBase = $SearchBase.Trim()
        }

        try {
            $computers = Get-ADComputer @adParams
        }
        catch {
            Write-Log -Message ("Active Directory query failed for {0}: {1}" -f $domain, $_.Exception.Message) -Level 'ERROR'
            continue
        }

        $total = @($computers).Count
        if ($total -eq 0) {
            Write-Log -Message ("No matching workstations found in domain: {0}" -f $domain) -Level 'WARNING'
            continue
        }

        $i = 0
        foreach ($comp in $computers) {
            $i++
            $pct = [math]::Round(($i * 100) / $total)

            if ($script:form -and $script:form.IsHandleCreated) {
                $script:form.Invoke([Action] {
                        $script:progressBar.Value = [Math]::Min([Math]::Max($pct, 0), 100)
                        $script:lblStatus.Text = ("Domain {0} - {1}/{2} ({3}%) - {4}" -f $domain, $i, $total, $pct, $comp.Name)
                    })
            }

            $name = $comp.Name
            $fqdn = $comp.DNSHostName
            $ip = $comp.IPv4Address
            $source = if ($ip) { 'AD' } else { $null }

            # DNS resolution (preferred)
            if (-not $ip -and $fqdn) {
                try {
                    # Note: PowerShell 5.1 Resolve-DnsName does not support -DnsTimeoutSeconds.
                    # Using -QuickTimeout for better responsiveness when applicable.
                    $dns = Resolve-DnsName -Name $fqdn -Type A -QuickTimeout -ErrorAction Stop -WarningAction SilentlyContinue
                    $ip = $dns | Where-Object { $_.IPAddress -match '^\d{1,3}(\.\d{1,3}){3}$' } | Select-Object -First 1 -ExpandProperty IPAddress
                    if ($ip) { $source = 'DNS' }
                }
                catch {
                    # Silent by design (fall through to ping if enabled)
                }
            }

            # Ping fallback (optional)
            if (-not $ip -and -not $SkipPing -and $fqdn) {
                try {
                    $timeoutSec = [math]::Ceiling($PingTimeoutMs / 1000)
                    $pingOk = Test-Connection -ComputerName $fqdn -Count 1 -Quiet -IPv4 -TimeoutSeconds $timeoutSec -ErrorAction SilentlyContinue
                    if ($pingOk) {
                        $addr = [System.Net.Dns]::GetHostAddresses($fqdn) |
                            Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                            Select-Object -First 1 -ExpandProperty IPAddressToString

                        if ($addr) {
                            $ip = $addr
                            $source = 'Ping+DNS'
                        }
                    }
                }
                catch {
                    # Silent by design
                }
            }

            if (-not $ip) { $source = 'Not Resolved' }

            $allResults += [PSCustomObject]@{
                ComputerName = $name
                FQDN = $fqdn
                IPv4Address = $ip
                IP_Source = $source
                Enabled = $comp.Enabled
                Domain = $domain
                DistinguishedName = $comp.DistinguishedName
            }
        }
    }

    # Return both the data and the domain list (for accurate summaries)
    return [PSCustomObject]@{
        Domains = $domains
        Data = $allResults
    }
}

# ==================================================
#                 GUI CONSTRUCTION
# ==================================================
$script:form = New-Object System.Windows.Forms.Form
$script:form.Text = 'Workstation Discovery and List Export'
$script:form.Size = New-Object System.Drawing.Size(680, 600)
$script:form.StartPosition = 'CenterScreen'
$script:form.FormBorderStyle = 'FixedDialog'
$script:form.MaximizeBox = $false

# Controls
$lblScope = New-Object System.Windows.Forms.Label
$lblScope.Text = 'Search scope:'
$lblScope.Location = New-Object System.Drawing.Point(20, 20)
$lblScope.Size = New-Object System.Drawing.Size(120, 20)
$script:form.Controls.Add($lblScope)

$cmbScope = New-Object System.Windows.Forms.ComboBox
$cmbScope.Location = New-Object System.Drawing.Point(150, 18)
$cmbScope.Size = New-Object System.Drawing.Size(300, 21)
$cmbScope.DropDownStyle = 'DropDownList'
$cmbScope.Items.AddRange(@('Current domain', 'Specific domain', 'All domains in forest'))
$cmbScope.SelectedIndex = 0
$script:form.Controls.Add($cmbScope)

$lblDomain = New-Object System.Windows.Forms.Label
$lblDomain.Text = 'Domain:'
$lblDomain.Location = New-Object System.Drawing.Point(20, 50)
$lblDomain.Size = New-Object System.Drawing.Size(120, 20)
$lblDomain.Enabled = $false
$script:form.Controls.Add($lblDomain)

$cmbDomain = New-Object System.Windows.Forms.ComboBox
$cmbDomain.Location = New-Object System.Drawing.Point(150, 48)
$cmbDomain.Size = New-Object System.Drawing.Size(480, 21)
$cmbDomain.DropDownStyle = 'DropDownList'
$cmbDomain.Enabled = $false
$script:form.Controls.Add($cmbDomain)

$lblOU = New-Object System.Windows.Forms.Label
$lblOU.Text = 'OU / Search base (optional):'
$lblOU.Location = New-Object System.Drawing.Point(20, 80)
$lblOU.Size = New-Object System.Drawing.Size(140, 20)
$script:form.Controls.Add($lblOU)

$txtOU = New-Object System.Windows.Forms.TextBox
$txtOU.Location = New-Object System.Drawing.Point(170, 78)
$txtOU.Size = New-Object System.Drawing.Size(460, 20)
$script:form.Controls.Add($txtOU)

$chkEnabled = New-Object System.Windows.Forms.CheckBox
$chkEnabled.Text = 'Only enabled computer accounts'
$chkEnabled.Checked = $true
$chkEnabled.Location = New-Object System.Drawing.Point(20, 110)
$chkEnabled.Size = New-Object System.Drawing.Size(260, 20)
$script:form.Controls.Add($chkEnabled)

$chkNoPing = New-Object System.Windows.Forms.CheckBox
$chkNoPing.Text = 'Skip ping fallback (faster)'
$chkNoPing.Checked = $true
$chkNoPing.Location = New-Object System.Drawing.Point(20, 135)
$chkNoPing.Size = New-Object System.Drawing.Size(260, 20)
$script:form.Controls.Add($chkNoPing)

$lblFormat = New-Object System.Windows.Forms.Label
$lblFormat.Text = 'Export format:'
$lblFormat.Location = New-Object System.Drawing.Point(20, 165)
$lblFormat.Size = New-Object System.Drawing.Size(120, 20)
$script:form.Controls.Add($lblFormat)

$cmbFormat = New-Object System.Windows.Forms.ComboBox
$cmbFormat.Location = New-Object System.Drawing.Point(150, 163)
$cmbFormat.Size = New-Object System.Drawing.Size(480, 21)
$cmbFormat.DropDownStyle = 'DropDownList'
$cmbFormat.Items.AddRange(@(
        'Unique IPv4 addresses (TXT)',
        'Short computer names / NetBIOS (TXT)',
        'Fully qualified domain names / FQDN (TXT)',
        'Full report (CSV)'
    ))
$cmbFormat.SelectedIndex = 0
$script:form.Controls.Add($cmbFormat)

$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Text = 'Output file:'
$lblPath.Location = New-Object System.Drawing.Point(20, 195)
$lblPath.Size = New-Object System.Drawing.Size(120, 20)
$script:form.Controls.Add($lblPath)

$txtPath = New-Object System.Windows.Forms.TextBox
$txtPath.Location = New-Object System.Drawing.Point(150, 193)
$txtPath.Size = New-Object System.Drawing.Size(400, 20)
$txtPath.Text = 'C:\temp\workstations_list.txt'
$script:form.Controls.Add($txtPath)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = 'Browse...'
$btnBrowse.Size = New-Object System.Drawing.Size(80, 23)
$btnBrowse.Location = New-Object System.Drawing.Point(550, 192)
$btnBrowse.Add_Click({
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = 'Text files (*.txt)|*.txt|CSV files (*.csv)|*.csv|All files (*.*)|*.*'
        $sfd.FileName = [System.IO.Path]::GetFileName($txtPath.Text)
        if ($sfd.ShowDialog() -eq 'OK') {
            $txtPath.Text = $sfd.FileName
        }
    })
$script:form.Controls.Add($btnBrowse)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = 'Generate'
$btnRun.Size = New-Object System.Drawing.Size(480, 40)
$btnRun.Location = New-Object System.Drawing.Point(150, 230)
$btnRun.BackColor = [System.Drawing.Color]::LightGreen
$btnRun.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$script:form.Controls.Add($btnRun)

$script:progressBar = New-Object System.Windows.Forms.ProgressBar
$script:progressBar.Location = New-Object System.Drawing.Point(20, 280)
$script:progressBar.Size = New-Object System.Drawing.Size(610, 25)
$script:progressBar.Style = 'Continuous'
$script:form.Controls.Add($script:progressBar)

$script:lblStatus = New-Object System.Windows.Forms.Label
$script:lblStatus.Text = 'Ready.'
$script:lblStatus.Location = New-Object System.Drawing.Point(20, 310)
$script:lblStatus.Size = New-Object System.Drawing.Size(610, 30)
$script:form.Controls.Add($script:lblStatus)

$txtSummary = New-Object System.Windows.Forms.TextBox
$txtSummary.Multiline = $true
$txtSummary.ReadOnly = $true
$txtSummary.ScrollBars = 'Vertical'
$txtSummary.Location = New-Object System.Drawing.Point(20, 350)
$txtSummary.Size = New-Object System.Drawing.Size(610, 190)
$script:form.Controls.Add($txtSummary)

# ===========================
#   ActiveDirectory Module
# ===========================
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log -Message 'ActiveDirectory module loaded successfully.' -Level 'INFO'
}
catch {
    Show-Message -Text ("ActiveDirectory module could not be loaded. Install RSAT / AD tools and try again.`n`n{0}" -f $_.Exception.Message) -Title 'Dependency Missing' -Icon 'Error'
    Write-Log -Message ('ActiveDirectory module load failed: {0}' -f $_.Exception.Message) -Level 'ERROR'
    return
}

# Populate domains when "Specific domain" is selected
$cmbScope.Add_SelectedIndexChanged({
        $isSpecific = ($cmbScope.SelectedItem -eq 'Specific domain')
        $cmbDomain.Enabled = $isSpecific
        $lblDomain.Enabled = $isSpecific

        if ($isSpecific -and $cmbDomain.Items.Count -eq 0) {
            try {
                $forest = Get-ADForest -ErrorAction Stop
                $forest.Domains | ForEach-Object { [void]$cmbDomain.Items.Add($_) }
                if ($forest.Domains.Count -gt 0) { $cmbDomain.SelectedIndex = 0 }
            }
            catch {
                Show-Message -Text ("Failed to load forest domains.`n`n{0}" -f $_.Exception.Message) -Title 'Error' -Icon 'Error'
                $cmbDomain.Enabled = $false
                $lblDomain.Enabled = $false
            }
        }
    })

# ===========================
#     Main Execution Logic
# ===========================
$btnRun.Add_Click({
        $btnRun.Enabled = $false
        $script:progressBar.Value = 0
        $txtSummary.Clear()
        $script:lblStatus.Text = 'Querying Active Directory...'
        Write-Log -Message 'User initiated workstation discovery.' -Level 'INFO'

        try {
            $scopeUi = [string]$cmbScope.SelectedItem
            $searchBase = $txtOU.Text.Trim()
            $onlyEnabled = [bool]$chkEnabled.Checked
            $skipPing = [bool]$chkNoPing.Checked
            $formatUi = [string]$cmbFormat.SelectedItem
            $userPath = $txtPath.Text.Trim()

            $scope = switch ($scopeUi) {
                'Current domain' { 'Current' }
                'Specific domain' { 'Specific' }
                'All domains in forest' { 'Forest' }
                default { 'Current' }
            }

            $domain = if ($scope -eq 'Specific') { [string]$cmbDomain.SelectedItem } else { '' }

            $result = Get-WorkstationData -Scope $scope -SpecificDomain $domain -SearchBase $searchBase -OnlyEnabled $onlyEnabled -SkipPing $skipPing
            $data = @($result.Data)
            $usedDomains = @($result.Domains)

            if ($data.Count -eq 0) {
                throw 'No matching workstations were found for the selected criteria.'
            }

            # Smart output naming (only when user keeps the default path)
            $effectiveDomain = if ($domain) { $domain } elseif ($scope -eq 'Current') { Get-CurrentDomainFQDN } else { 'Forest' }

            $baseDir = 'C:\temp'
            if (-not (Test-Path $baseDir)) { New-Item -Path $baseDir -ItemType Directory -Force | Out-Null }

            $isDefaultPath = ($userPath -match '^C:\\temp\\workstations_list\.txt$') -or [string]::IsNullOrWhiteSpace($userPath)

            $fileName = switch ($formatUi) {
                'Unique IPv4 addresses (TXT)' { "IPAddress-$effectiveDomain-workstations_list.txt" }
                'Short computer names / NetBIOS (TXT)' { "HostName-$effectiveDomain-workstations_list.txt" }
                'Fully qualified domain names / FQDN (TXT)' { "FQDN-$effectiveDomain-workstations_list.txt" }
                'Full report (CSV)' { "FullReport-$effectiveDomain-workstations_list.csv" }
                default { "workstations_list-$effectiveDomain.txt" }
            }

            $outPath = if ($isDefaultPath) { Join-Path $baseDir $fileName } else { $userPath }

            # Export by selected format
            switch ($formatUi) {
                'Unique IPv4 addresses (TXT)' {
                    $data | Where-Object { $_.IPv4Address } |
                        Select-Object -ExpandProperty IPv4Address -Unique |
                        Sort-Object |
                        Out-File -FilePath $outPath -Encoding ascii -Force
                }
                'Short computer names / NetBIOS (TXT)' {
                    $data | Select-Object -ExpandProperty ComputerName -Unique |
                        Sort-Object |
                        Out-File -FilePath $outPath -Encoding ascii -Force
                }
                'Fully qualified domain names / FQDN (TXT)' {
                    $data | Where-Object { $_.FQDN } |
                        Select-Object -ExpandProperty FQDN -Unique |
                        Sort-Object |
                        Out-File -FilePath $outPath -Encoding ascii -Force
                }
                'Full report (CSV)' {
                    $data | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8 -Force
                }
            }

            # Summary
            $summaryLines = @(
                'Operation completed successfully.',
                ("Total workstations found: {0}" -f $data.Count),
                ("Domain(s): {0}" -f ($usedDomains -join ', ')),
                ("Output file: {0}" -f $outPath),
                ''
            )

            $summaryLines += ($data | Group-Object IP_Source | Sort-Object Count -Descending | ForEach-Object {
                    "{0,-18}: {1,5}" -f $_.Name, $_.Count
                })

            $txtSummary.Text = ($summaryLines -join "`r`n")
            $script:lblStatus.Text = ("Completed. File saved to: {0}" -f $outPath)

            Show-Message -Text ("Success!`n`nTotal entries: {0}`nSaved to: {1}" -f $data.Count, $outPath) -Title 'Completed' -Icon 'Information'
            Write-Log -Message ("Export completed. Entries: {0}. Output: {1}" -f $data.Count, $outPath) -Level 'INFO'
        }
        catch {
            $txtSummary.Text = ("ERROR: {0}" -f $_.Exception.Message)
            $script:lblStatus.Text = 'Operation failed.'
            Show-Message -Text $_.Exception.Message -Title 'Error' -Icon 'Error'
            Write-Log -Message $_.Exception.Message -Level 'ERROR'
        }
        finally {
            $btnRun.Enabled = $true
            $script:progressBar.Value = 0
        }
    })

# Show GUI
[void]$script:form.ShowDialog()
Write-Log -Message 'GUI session ended.' -Level 'INFO'

# End of script
