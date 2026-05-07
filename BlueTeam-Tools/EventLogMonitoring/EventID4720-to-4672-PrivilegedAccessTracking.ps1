<#
.SYNOPSIS
    PowerShell Script for forensic-grade tracking of privileged access-related Security events.

.DESCRIPTION
    This WS2019-compatible revision analyzes privileged access-related Security events
    from the live Security channel or archived .evtx files. In live mode, it exports
    a temporary snapshot with wevtutil and parses it using Log Parser COM SQL with
    INTO-based CSV output, Get-WinEvent XML fallback, date range filtering, and user
    filtering. The consolidated CSV report is exported to My Documents by default.
    All rows are normalized into a fixed forensic evidence schema before export.
    v1.0.3 hardens heterogeneous XML EventData normalization by canonicalizing nulls,
    XML nodes, arrays, SID-like values, multiline strings, and per-event parsing failures.

    Tracked Event IDs:
    - 4720: User account created
    - 4724: Password reset attempted
    - 4728: Member added to global security-enabled group
    - 4732: Member added to local security-enabled group
    - 4735: Local security-enabled group changed
    - 4756: Member added to universal security-enabled group
    - 4672: Special privileges assigned to new logon

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
   2026-05-06-v1.0.8-PRODUCTION-PATH-AGNOSTIC-ARCHIVE-PIPELINE
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Automatically open the generated CSV file after processing.")]
    [bool]$AutoOpen = $true,

    [switch]$ShowConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Native console visibility
try {
    $consoleType = [System.Management.Automation.PSTypeName]'Win32Console'
    if (-not $consoleType.Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class Win32Console {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@ -ErrorAction Stop
    }

    if (-not $ShowConsole.IsPresent) {
        $consoleHandle = [Win32Console]::GetConsoleWindow()
        if ($consoleHandle -ne [IntPtr]::Zero) {
            [void][Win32Console]::ShowWindow($consoleHandle, 0)
        }
    }
}
catch {
    Write-Error "Failed to initialize console visibility helpers. $($_.Exception.Message)"
    exit 1
}
#endregion

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
}
catch {
    Write-Error "Failed to load required assemblies. $($_.Exception.Message)"
    exit 1
}

#region Variables
$scriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$computerName = [Environment]::MachineName
$script:defaultOutputFolder = [Environment]::GetFolderPath('MyDocuments')
$script:defaultLogFolder = 'C:\Logs-TEMP'
$script:logPath = Join-Path $script:defaultLogFolder ($scriptName + '.log')
$script:tempArtifacts = New-Object System.Collections.ArrayList
$script:progressBar = $null
$script:statusLabel = $null
$script:form = $null
#endregion

#region Helpers
function Initialize-LogDirectory {
    if (-not (Test-Path -LiteralPath $script:defaultLogFolder -PathType Container)) {
        New-Item -Path $script:defaultLogFolder -ItemType Directory -Force | Out-Null
    }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARNING', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message
    try {
        Add-Content -LiteralPath $script:logPath -Value $entry -Encoding UTF8
    } catch {
    }
}


function Test-IsFileLocked {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        return $false
    }
    catch {
        return $true
    }
    finally {
        if ($stream) { $stream.Dispose() }
    }
}

function Test-IsLikelyActiveEvtxFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)

    $activeNames = @(
        'Application.evtx',
        'Security.evtx',
        'System.evtx',
        'Setup.evtx',
        'Microsoft-Windows-PrintService-Operational.evtx',
        'Active Directory Web Services.evtx',
        'State.evtx'
    )

    return ($activeNames -contains $File.Name)
}

function Get-ArchiveSafeEvtxFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Files)

    $safeFiles = New-Object System.Collections.Generic.List[object]
    foreach ($file in @($Files)) {
        if ($null -eq $file -or [string]::IsNullOrWhiteSpace([string]$file.FullName)) { continue }
        if (Test-IsLikelyActiveEvtxFile -File $file) {
            Write-Log "Skipped likely active/canonical EVTX in archived mode to avoid file-lock errors: '$($file.FullName)'" 'WARNING'
            continue
        }
        if (Test-IsFileLocked -Path $file.FullName) {
            Write-Log "Skipped locked EVTX file in archived mode: '$($file.FullName)'" 'WARNING'
            continue
        }
        [void]$safeFiles.Add($file)
    }
    return @($safeFiles)
}

function Show-Info {
    param([string]$Message, [string]$Title = 'Information')
    [void][System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

function Show-ErrorBox {
    param([string]$Message, [string]$Title = 'Error')
    [void][System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}


function Register-WinFormsExceptionHandlers {
    [CmdletBinding()]
    param()

    try {
        [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
        [System.Windows.Forms.Application]::add_ThreadException({
            param($sender, $eventArgs)
            try {
                Write-Log -Level 'ERROR' -Message ("Unhandled GUI exception: {0}" -f $eventArgs.Exception.Message)
                Show-ErrorBox -Message ("Unhandled GUI exception.`r`n{0}" -f $eventArgs.Exception.Message) -Title 'Unhandled GUI Exception'
            }
            catch { }
        })
        [AppDomain]::CurrentDomain.add_UnhandledException({
            param($sender, $eventArgs)
            try {
                $exception = $eventArgs.ExceptionObject
                if ($exception -is [System.Exception]) {
                    Write-Log -Level 'ERROR' -Message ("Unhandled AppDomain exception: {0}" -f $exception.Message)
                } else {
                    Write-Log -Level 'ERROR' -Message ("Unhandled AppDomain exception: {0}" -f [string]$exception)
                }
            }
            catch { }
        })
        Write-Log -Message 'WinForms JIT-safe exception handlers registered.'
    }
    catch {
        Write-Log -Level 'WARNING' -Message "Unable to register WinForms exception handlers: $($_.Exception.Message)"
    }
}

function Resolve-SecurityEvtxFolder {
    [CmdletBinding()]
    param()

    $candidateFiles = New-Object System.Collections.Generic.List[string]

    try {
        $classicKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Security'
        if (Test-Path -LiteralPath $classicKey) {
            $classicFile = (Get-ItemProperty -LiteralPath $classicKey -Name File -ErrorAction SilentlyContinue).File
            if (-not [string]::IsNullOrWhiteSpace([string]$classicFile)) {
                [void]$candidateFiles.Add([Environment]::ExpandEnvironmentVariables([string]$classicFile))
            }
        }
    }
    catch {
        Write-Log -Level 'WARNING' -Message "Classic Security EventLog registry lookup failed: $($_.Exception.Message)"
    }

    try {
        $winevtKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Security'
        if (Test-Path -LiteralPath $winevtKey) {
            $winevtFile = (Get-ItemProperty -LiteralPath $winevtKey -Name File -ErrorAction SilentlyContinue).File
            if (-not [string]::IsNullOrWhiteSpace([string]$winevtFile)) {
                [void]$candidateFiles.Add([Environment]::ExpandEnvironmentVariables([string]$winevtFile))
            }
        }
    }
    catch {
        Write-Log -Level 'WARNING' -Message "WINEVT Security channel registry lookup failed: $($_.Exception.Message)"
    }

    foreach ($filePath in @($candidateFiles)) {
        try {
            if ([string]::IsNullOrWhiteSpace([string]$filePath)) { continue }
            $folder = Split-Path -Path ([string]$filePath) -Parent
            if (-not [string]::IsNullOrWhiteSpace($folder) -and (Test-Path -LiteralPath $folder -PathType Container)) {
                Write-Log -Message "Security EVTX folder resolved: $folder"
                return $folder
            }
        }
        catch {
            Write-Log -Level 'WARNING' -Message "Failed to validate Security EVTX folder candidate '$filePath'. $($_.Exception.Message)"
        }
    }

    $fallback = Join-Path $env:SystemRoot 'System32\winevt\Logs'
    if (Test-Path -LiteralPath $fallback -PathType Container) {
        Write-Log -Level 'WARNING' -Message "Security EVTX folder could not be resolved from registry. Using fallback: $fallback"
        return $fallback
    }

    return $null
}

function Update-ProgressSafe {
    param([int]$Value, [string]$StatusText)

    if ($script:progressBar) {
        $bounded = [Math]::Max(0, [Math]::Min(100, $Value))
        $script:progressBar.Value = $bounded
    }
    if ($script:statusLabel -and $StatusText) {
        $script:statusLabel.Text = $StatusText
    }
    if ($script:form) {
        $script:form.Refresh()
    }
}

function Resolve-OutputFolder {
    param([string]$Candidate)

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return $script:defaultOutputFolder
    }
    if (-not (Test-Path -LiteralPath $Candidate -PathType Container)) {
        New-Item -Path $Candidate -ItemType Directory -Force | Out-Null
    }
    return $Candidate
}

function New-FolderPicker {
    param([string]$Description)
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    return $dialog
}

function Register-TempArtifact {
    param([string]$Path)
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        [void]$script:tempArtifacts.Add($Path)
    }
}

function Remove-TempArtifacts {
    foreach ($artifact in @($script:tempArtifacts)) {
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                if (Test-Path -LiteralPath $artifact) {
                    Remove-Item -LiteralPath $artifact -Force -ErrorAction Stop
                }
                break
            }
            catch {
                if ($attempt -eq 3) {
                    Write-Log -Level 'WARNING' -Message "Unable to remove temporary artifact: $artifact. Error: $($_.Exception.Message)"
                } else {
                    Start-Sleep -Milliseconds 250
                    [System.GC]::Collect()
                    [System.GC]::WaitForPendingFinalizers()
                }
            }
        }
    }
    $script:tempArtifacts.Clear() | Out-Null
}

function New-LogParserObjects {
    [CmdletBinding()]
    param()

    return [ordered]@{
        Query        = New-Object -ComObject 'MSUtil.LogQuery'
        InputFormat  = New-Object -ComObject 'MSUtil.LogQuery.EventLogInputFormat'
        OutputFormat = New-Object -ComObject 'MSUtil.LogQuery.CSVOutputFormat'
    }
}

function Release-LogParserObjects {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Objects)

    foreach ($key in @('OutputFormat','InputFormat','Query')) {
        if ($Objects.Contains($key)) {
            $obj = $Objects[$key]
            if ($null -ne $obj -and [System.Runtime.InteropServices.Marshal]::IsComObject($obj)) {
                try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($obj) } catch { }
            }
        }
    }
}

function Export-LiveChannelSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ChannelName)

    $wevtutil = Join-Path $env:SystemRoot 'System32\wevtutil.exe'
    if (-not (Test-Path -LiteralPath $wevtutil -PathType Leaf)) {
        throw "wevtutil.exe was not found at '$wevtutil'."
    }

    $snapshotPath = Join-Path $env:TEMP ('{0}-{1}.evtx' -f ($ChannelName -replace '[\\/:*?"<>|]', '_'), (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
    Register-TempArtifact -Path $snapshotPath

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $wevtutil
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $quotedChannel = '"' + ($ChannelName -replace '"','\"') + '"'
    $quotedDestination = '"' + ($snapshotPath -replace '"','\"') + '"'
    $psi.Arguments = ('epl {0} {1} /ow:true' -f $quotedChannel, $quotedDestination)

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    [void]$process.Start()
    $stdErr = $process.StandardError.ReadToEnd()
    $null = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()

    if ($process.ExitCode -ne 0) {
        throw "wevtutil export failed. ExitCode=$($process.ExitCode). StdErr=$stdErr"
    }
    if (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
        throw "Snapshot export did not create '$snapshotPath'."
    }

    Write-Log "Live channel snapshot exported to '$snapshotPath'."
    return $snapshotPath
}

function Get-ForensicCsvColumns {
    [CmdletBinding()]
    param()

    return @(
        'EvidenceId',
        'SourceEngine',
        'SourceFile',
        'ComputerName',
        'EventId',
        'EventCategory',
        'RecordId',
        'TimeCreated',
        'ProviderName',
        'ActorUser',
        'ActorDomain',
        'TargetUser',
        'TargetDomain',
        'GroupName',
        'GroupDomain',
        'PrivilegeList',
        'SubjectLogonId',
        'RawEventData',
        'IntegrityHash'
    )
}

function New-HeaderOnlyCsv {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $header = (Get-ForensicCsvColumns) -join ','
    Set-Content -LiteralPath $Path -Value $header -Encoding UTF8
}

function ConvertTo-CanonicalString {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }

    try {
        if ($Value -is [System.Array]) {
            $items = New-Object System.Collections.Generic.List[string]
            foreach ($item in @($Value)) {
                $canonicalItem = ConvertTo-CanonicalString -Value $item
                if (-not [string]::IsNullOrWhiteSpace($canonicalItem)) {
                    [void]$items.Add($canonicalItem)
                }
            }
            return ([regex]::Replace((@($items) -join '; '), "[`r`n`t]+", ' ')).Trim()
        }

        if ($Value -is [System.Xml.XmlNode]) {
            if ($Value.PSObject.Properties.Match('InnerText').Count -gt 0) {
                return (ConvertTo-CanonicalString -Value $Value.InnerText)
            }
            if ($Value.PSObject.Properties.Match('#text').Count -gt 0) {
                return (ConvertTo-CanonicalString -Value $Value.'#text')
            }
        }

        if ($Value.PSObject -and $Value.PSObject.Properties.Match('InnerText').Count -gt 0) {
            return (ConvertTo-CanonicalString -Value $Value.InnerText)
        }

        if ($Value.PSObject -and $Value.PSObject.Properties.Match('#text').Count -gt 0) {
            return (ConvertTo-CanonicalString -Value $Value.'#text')
        }

        if ($Value.PSObject -and $Value.PSObject.Properties.Match('Value').Count -gt 0 -and $Value.Value -ne $Value) {
            return (ConvertTo-CanonicalString -Value $Value.Value)
        }

        $text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($text)) { return '' }
        return ([regex]::Replace($text, "[`r`n`t]+", ' ')).Trim()
    }
    catch {
        try { return ([regex]::Replace(([string]$Value), "[`r`n`t]+", ' ')).Trim() } catch { return '' }
    }
}

function ConvertTo-SafeString {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    return (ConvertTo-CanonicalString -Value $Value)
}

function Get-EventDataMap {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$XmlEvent)

    $map = @{}
    try {
        $dataNodes = @($XmlEvent.Event.EventData.Data)
        foreach ($dataNode in @($dataNodes)) {
            if ($null -eq $dataNode) { continue }

            $name = ''
            try {
                if ($dataNode.PSObject.Properties.Match('Name').Count -gt 0) {
                    $name = ConvertTo-CanonicalString -Value $dataNode.Name
                }
            } catch { $name = '' }

            if ([string]::IsNullOrWhiteSpace($name)) {
                try {
                    $name = ConvertTo-CanonicalString -Value $dataNode.GetAttribute('Name')
                } catch { $name = '' }
            }

            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $value = ''
            try { $value = ConvertTo-CanonicalString -Value $dataNode.'#text' } catch { $value = '' }
            if ([string]::IsNullOrWhiteSpace($value)) {
                try { $value = ConvertTo-CanonicalString -Value $dataNode.InnerText } catch { $value = '' }
            }

            if ($map.ContainsKey($name)) {
                $existing = ConvertTo-CanonicalString -Value $map[$name]
                if (-not [string]::IsNullOrWhiteSpace($existing) -and -not [string]::IsNullOrWhiteSpace($value)) {
                    $map[$name] = ('{0}; {1}' -f $existing, $value)
                }
                elseif (-not [string]::IsNullOrWhiteSpace($value)) {
                    $map[$name] = $value
                }
            }
            else {
                $map[$name] = $value
            }
        }
    }
    catch {
        Write-Log -Level 'WARNING' -Message "Unable to flatten XML EventData map. $($_.Exception.Message)"
    }
    return $map
}

function Get-MapValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Map,
        [Parameter(Mandatory)][string]$Name
    )

    if ($Map.ContainsKey($Name)) { return (ConvertTo-SafeString -Value $Map[$Name]) }
    return ''
}

function Convert-EventDataMapToRawString {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Map)

    $pairs = New-Object System.Collections.Generic.List[string]
    foreach ($key in @($Map.Keys | Sort-Object)) {
        $safeKey = ConvertTo-SafeString -Value $key
        $safeValue = ConvertTo-SafeString -Value $Map[$key]
        [void]$pairs.Add(('{0}={1}' -f $safeKey, $safeValue))
    }
    return ([string](@($pairs) -join '; '))
}

function New-IntegrityHash {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Material)

    $sha = $null
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Material)
        $hashBytes = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
    }
    finally {
        if ($sha) { $sha.Dispose() }
    }
}

function New-ForensicEvidenceRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceEngine,
        [Parameter(Mandatory)][string]$SourceFile,
        [Parameter()][string]$ComputerName,
        [Parameter(Mandatory)][int]$EventId,
        [Parameter()][string]$EventCategory,
        [Parameter()][Int64]$RecordId,
        [Parameter()][object]$TimeCreated,
        [Parameter()][string]$ProviderName,
        [Parameter()][string]$ActorUser,
        [Parameter()][string]$ActorDomain,
        [Parameter()][string]$TargetUser,
        [Parameter()][string]$TargetDomain,
        [Parameter()][string]$GroupName,
        [Parameter()][string]$GroupDomain,
        [Parameter()][string]$PrivilegeList,
        [Parameter()][string]$SubjectLogonId,
        [Parameter()][string]$RawEventData
    )

    $safeComputer = ConvertTo-SafeString -Value $ComputerName
    $safeSourceFile = ConvertTo-SafeString -Value $SourceFile
    $safeCategory = ConvertTo-SafeString -Value $EventCategory
    if ([string]::IsNullOrWhiteSpace($safeCategory)) { $safeCategory = Get-EventActionLabel -EventId $EventId }

    $timeText = ''
    try {
        if ($null -ne $TimeCreated -and -not [string]::IsNullOrWhiteSpace([string]$TimeCreated)) {
            $timeText = ([datetime]$TimeCreated).ToString('yyyy-MM-dd HH:mm:ss')
        }
    }
    catch { $timeText = ConvertTo-SafeString -Value $TimeCreated }

    $safeActorUser = ConvertTo-SafeString -Value $ActorUser
    $safeActorDomain = ConvertTo-SafeString -Value $ActorDomain
    $safeTargetUser = ConvertTo-SafeString -Value $TargetUser
    $safeTargetDomain = ConvertTo-SafeString -Value $TargetDomain
    $safeGroupName = ConvertTo-SafeString -Value $GroupName
    $safeGroupDomain = ConvertTo-SafeString -Value $GroupDomain
    $safePrivilegeList = ConvertTo-SafeString -Value $PrivilegeList
    $safeSubjectLogonId = ConvertTo-SafeString -Value $SubjectLogonId
    $safeRawEventData = ConvertTo-SafeString -Value $RawEventData
    $safeProviderName = ConvertTo-SafeString -Value $ProviderName
    $safeSourceEngine = ConvertTo-SafeString -Value $SourceEngine

    $evidenceId = '{0}-{1}-{2}' -f $safeComputer, $EventId, $RecordId
    $hashMaterial = @(
        $evidenceId, $safeSourceEngine, $safeSourceFile, $safeComputer, [string]$EventId,
        [string]$RecordId, $timeText, $safeProviderName, $safeActorUser, $safeActorDomain,
        $safeTargetUser, $safeTargetDomain, $safeGroupName, $safeGroupDomain, $safePrivilegeList,
        $safeSubjectLogonId, $safeRawEventData
    ) -join '|'

    return [PSCustomObject][ordered]@{
        EvidenceId     = [string]$evidenceId
        SourceEngine   = [string]$safeSourceEngine
        SourceFile     = [string]$safeSourceFile
        ComputerName   = [string]$safeComputer
        EventId        = [int]$EventId
        EventCategory  = [string]$safeCategory
        RecordId       = [Int64]$RecordId
        TimeCreated    = [string]$timeText
        ProviderName   = [string]$safeProviderName
        ActorUser      = [string]$safeActorUser
        ActorDomain    = [string]$safeActorDomain
        TargetUser     = [string]$safeTargetUser
        TargetDomain   = [string]$safeTargetDomain
        GroupName      = [string]$safeGroupName
        GroupDomain    = [string]$safeGroupDomain
        PrivilegeList  = [string]$safePrivilegeList
        SubjectLogonId = [string]$safeSubjectLogonId
        RawEventData   = [string]$safeRawEventData
        IntegrityHash  = [string](New-IntegrityHash -Material $hashMaterial)
    }
}

function Export-ForensicRowsToCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Rows,
        [Parameter(Mandatory)][string]$Path
    )

    $normalized = New-Object System.Collections.Generic.List[object]
    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }
        $obj = [PSCustomObject][ordered]@{}
        foreach ($column in @(Get-ForensicCsvColumns)) {
            $value = ''
            try {
                if ($row.PSObject.Properties.Match($column).Count -gt 0) { $value = $row.$column }
            }
            catch { $value = '' }
            $obj | Add-Member -NotePropertyName $column -NotePropertyValue $value
        }
        [void]$normalized.Add($obj)
    }

    if ((Get-SafeCount -InputObject $normalized) -gt 0) {
        @($normalized) | Select-Object (Get-ForensicCsvColumns) | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
    }
    else {
        New-HeaderOnlyCsv -Path $Path
    }
}

function Get-SafeCount {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline = $true)][object]$InputObject)

    if ($null -eq $InputObject) { return 0 }

    try {
        if ($InputObject -is [System.Collections.ICollection]) {
            return [int]$InputObject.Count
        }
    }
    catch { }

    $counter = 0
    try {
        foreach ($item in @($InputObject)) {
            if ($null -ne $item) { $counter++ }
        }
        return [int]$counter
    }
    catch {
        return 1
    }
}

function Get-RowCountSafe {
    param([string]$CsvPath)
    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) { return 0 }
    try {
        $rows = Import-Csv -LiteralPath $CsvPath
        return (Get-SafeCount -InputObject $rows)
    } catch {
        return 0
    }
}

function Build-UserFilterClause {
    param([string[]]$UserAccounts)

    $normalizedUsers = @($UserAccounts | ForEach-Object { "$($_)".Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ((Get-SafeCount -InputObject $normalizedUsers) -eq 0) { return '' }

    $clauses = New-Object System.Collections.Generic.List[string]
    foreach ($user in @($normalizedUsers)) {
        if ($user -eq '*') { return '' }
        $escapedLike = $user.Replace("'", "''").Replace('*', '%')
        for ($i = 0; $i -le 12; $i++) {
            [void]$clauses.Add(("EXTRACT_TOKEN(Strings, {0}, '|') LIKE '{1}'" -f $i, $escapedLike))
        }
    }

    if ((Get-SafeCount -InputObject $clauses) -eq 0) { return '' }
    return ('AND ({0})' -f (@($clauses) -join ' OR '))
}

function Build-EventActionExpression {
    return @"
CASE EventID
    WHEN 4720 THEN 'User account created'
    WHEN 4724 THEN 'Password reset attempted'
    WHEN 4728 THEN 'Member added to global security-enabled group'
    WHEN 4732 THEN 'Member added to local security-enabled group'
    WHEN 4735 THEN 'Local security-enabled group changed'
    WHEN 4756 THEN 'Member added to universal security-enabled group'
    WHEN 4672 THEN 'Special privileges assigned to new logon'
    ELSE 'Privileged access event'
END
"@
}

function Build-QueryForFile {
    param(
        [Parameter(Mandatory)][string]$EvtxPath,
        [Parameter(Mandatory)][string]$CsvPath,
        [Parameter()][string[]]$UserAccounts,
        [Parameter()][object]$StartTime,
        [Parameter()][object]$EndTime
    )

    $escapedEvtx = $EvtxPath.Replace("'", "''")
    $escapedCsv  = $CsvPath.Replace("'", "''")
    $userClause  = Build-UserFilterClause -UserAccounts $UserAccounts

$query = @"
SELECT
    TimeGenerated AS EventTime,
    EventID,
    'Privileged access event' AS EventAction,
    EXTRACT_TOKEN(Strings, 6, '|') AS SubjectUser,
    EXTRACT_TOKEN(Strings, 7, '|') AS SubjectDomain,
    EXTRACT_TOKEN(Strings, 0, '|') AS TargetUser,
    EXTRACT_TOKEN(Strings, 1, '|') AS TargetDomain,
    EXTRACT_TOKEN(Strings, 2, '|') AS GroupName,
    EXTRACT_TOKEN(Strings, 3, '|') AS GroupDomain,
    EXTRACT_TOKEN(Strings, 4, '|') AS PrivilegeList,
    ComputerName,
    '$escapedEvtx' AS SourceFile
INTO '$escapedCsv'
FROM '$escapedEvtx'
WHERE EventID IN (4720; 4724; 4728; 4732; 4735; 4756; 4672)
$userClause
"@
    return $query
}

function Merge-CsvFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$SourceCsvFiles,
        [Parameter(Mandatory)][string]$DestinationCsv
    )

    $existing = @(@($SourceCsvFiles) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and (Test-Path -LiteralPath ([string]$_) -PathType Leaf) })
    if ((Get-SafeCount -InputObject $existing) -eq 0) {
        New-HeaderOnlyCsv -Path $DestinationCsv
        return
    }

    $first = $true
    foreach ($csv in @($existing)) {
        if ($first) {
            Get-Content -LiteralPath $csv | Set-Content -LiteralPath $DestinationCsv -Encoding UTF8
            $first = $false
        } else {
            Get-Content -LiteralPath $csv | Select-Object -Skip 1 | Add-Content -LiteralPath $DestinationCsv -Encoding UTF8
        }
    }
}

function Test-PrivAccessUserMatch {
    [CmdletBinding()]
    param(
        [Parameter()][string]$SubjectUser,
        [Parameter()][string]$SubjectDomain,
        [Parameter()][string]$TargetUser,
        [Parameter()][string]$TargetDomain,
        [Parameter()][string]$GroupName,
        [Parameter()][string]$GroupDomain,
        [Parameter()][string[]]$UserAccounts
    )

    $normalizedUsers = @($UserAccounts | ForEach-Object { "$($_)".Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ((Get-SafeCount -InputObject $normalizedUsers) -eq 0) { return $true }
    if ((Get-SafeCount -InputObject @($normalizedUsers | Where-Object { $_ -eq '*' })) -gt 0) { return $true }

    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($item in @(
        [pscustomobject]@{ Domain = $SubjectDomain; Name = $SubjectUser },
        [pscustomobject]@{ Domain = $TargetDomain;  Name = $TargetUser  },
        [pscustomobject]@{ Domain = $GroupDomain;   Name = $GroupName   }
    )) {
        $domain = ConvertTo-CanonicalString -Value $item.Domain
        $name   = ConvertTo-CanonicalString -Value $item.Name
        if (-not [string]::IsNullOrWhiteSpace($name)) { [void]$candidates.Add($name) }
        if (-not [string]::IsNullOrWhiteSpace($domain) -and -not [string]::IsNullOrWhiteSpace($name)) { [void]$candidates.Add("$domain\$name") }
    }

    foreach ($filter in @($normalizedUsers)) {
        foreach ($candidate in @($candidates)) {
            if ([string]::Equals($candidate, (ConvertTo-CanonicalString -Value $filter), [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
            $safeFilter = ConvertTo-CanonicalString -Value $filter
            if ($safeFilter.Contains('*') -and ($candidate -like $safeFilter)) { return $true }
        }
    }
    return $false
}

function Get-EventDataValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$XmlEvent,
        [Parameter(Mandatory)][string]$Name
    )

    try {
        $node = @($XmlEvent.Event.EventData.Data | Where-Object {
            $nodeName = ''
            try { $nodeName = ConvertTo-CanonicalString -Value $_.Name } catch { $nodeName = '' }
            if ([string]::IsNullOrWhiteSpace($nodeName)) {
                try { $nodeName = ConvertTo-CanonicalString -Value $_.GetAttribute('Name') } catch { $nodeName = '' }
            }
            $nodeName -eq $Name
        } | Select-Object -First 1)
        if ((Get-SafeCount -InputObject $node) -gt 0) { return (ConvertTo-CanonicalString -Value $node[0]) }
    }
    catch { }
    return ''
}

function Get-EventActionLabel {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$EventId)

    switch ($EventId) {
        4720 { return 'User account created' }
        4724 { return 'Password reset attempted' }
        4728 { return 'Member added to global security-enabled group' }
        4732 { return 'Member added to local security-enabled group' }
        4735 { return 'Local security-enabled group changed' }
        4756 { return 'Member added to universal security-enabled group' }
        4672 { return 'Special privileges assigned to new logon' }
        default { return 'Privileged access event' }
    }
}

function Resolve-PrivilegedAccessFields {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$EventId,
        [Parameter(Mandatory)]$XmlEvent
    )

    $map = Get-EventDataMap -XmlEvent $XmlEvent

    $actorUser       = Get-MapValue -Map $map -Name 'SubjectUserName'
    $actorDomain     = Get-MapValue -Map $map -Name 'SubjectDomainName'
    $subjectLogonId  = Get-MapValue -Map $map -Name 'SubjectLogonId'
    $targetUser      = Get-MapValue -Map $map -Name 'TargetUserName'
    $targetDomain    = Get-MapValue -Map $map -Name 'TargetDomainName'
    $groupName       = ''
    $groupDomain     = ''
    $privileges      = Get-MapValue -Map $map -Name 'PrivilegeList'

    switch ($EventId) {
        4672 {
            # Special privileges assigned to new logon.
            $targetUser = $actorUser
            $targetDomain = $actorDomain
        }
        4720 {
            # User account created.
        }
        4724 {
            # Password reset attempted.
        }
        4728 {
            # Member added to global security-enabled group.
            $groupName = Get-MapValue -Map $map -Name 'TargetUserName'
            $groupDomain = Get-MapValue -Map $map -Name 'TargetDomainName'
            $targetUser = Get-MapValue -Map $map -Name 'MemberName'
            $targetDomain = Get-MapValue -Map $map -Name 'MemberSid'
        }
        4732 {
            # Member added to local security-enabled group.
            $groupName = Get-MapValue -Map $map -Name 'TargetUserName'
            $groupDomain = Get-MapValue -Map $map -Name 'TargetDomainName'
            $targetUser = Get-MapValue -Map $map -Name 'MemberName'
            $targetDomain = Get-MapValue -Map $map -Name 'MemberSid'
        }
        4735 {
            # Local security-enabled group changed.
            $groupName = Get-MapValue -Map $map -Name 'TargetUserName'
            $groupDomain = Get-MapValue -Map $map -Name 'TargetDomainName'
            $targetUser = ''
            $targetDomain = ''
        }
        4756 {
            # Member added to universal security-enabled group.
            $groupName = Get-MapValue -Map $map -Name 'TargetUserName'
            $groupDomain = Get-MapValue -Map $map -Name 'TargetDomainName'
            $targetUser = Get-MapValue -Map $map -Name 'MemberName'
            $targetDomain = Get-MapValue -Map $map -Name 'MemberSid'
        }
    }

    if ([string]::IsNullOrWhiteSpace($groupName)) {
        $groupName = Get-MapValue -Map $map -Name 'GroupName'
    }
    if ([string]::IsNullOrWhiteSpace($groupDomain)) {
        $groupDomain = Get-MapValue -Map $map -Name 'GroupDomainName'
    }

    return [pscustomobject]@{
        EventCategory  = Get-EventActionLabel -EventId $EventId
        ActorUser      = ConvertTo-SafeString -Value $actorUser
        ActorDomain    = ConvertTo-SafeString -Value $actorDomain
        TargetUser     = ConvertTo-SafeString -Value $targetUser
        TargetDomain   = ConvertTo-SafeString -Value $targetDomain
        GroupName      = ConvertTo-SafeString -Value $groupName
        GroupDomain    = ConvertTo-SafeString -Value $groupDomain
        PrivilegeList  = ConvertTo-SafeString -Value $privileges
        SubjectLogonId = ConvertTo-SafeString -Value $subjectLogonId
        RawEventData   = Convert-EventDataMapToRawString -Map $map
    }
}

function Invoke-GetWinEventFallbackToCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EvtxPath,
        [Parameter(Mandatory)][string]$CsvPath,
        [Parameter()][string[]]$UserAccounts,
        [Parameter()][object]$StartTime,
        [Parameter()][object]$EndTime
    )

    Write-Log "Get-WinEvent forensic fallback processing: $EvtxPath"

    $filter = @{
        Path = [string]$EvtxPath
        Id   = [int[]]@(4720, 4724, 4728, 4732, 4735, 4756, 4672)
    }

    if ($null -ne $StartTime -and -not [string]::IsNullOrWhiteSpace((ConvertTo-CanonicalString -Value $StartTime))) {
        try { $filter['StartTime'] = [datetime]$StartTime } catch { Write-Log -Level 'WARNING' -Message "Ignoring invalid StartTime value '$StartTime'." }
    }
    if ($null -ne $EndTime -and -not [string]::IsNullOrWhiteSpace((ConvertTo-CanonicalString -Value $EndTime))) {
        try { $filter['EndTime'] = [datetime]$EndTime } catch { Write-Log -Level 'WARNING' -Message "Ignoring invalid EndTime value '$EndTime'." }
    }

    $rows = New-Object System.Collections.Generic.List[object]
    $events = @()

    try {
        $events = @(Get-WinEvent -FilterHashtable $filter -ErrorAction SilentlyContinue)
    }
    catch [System.Diagnostics.Eventing.Reader.EventLogNotFoundException] {
        Write-Log -Level 'WARNING' -Message "Get-WinEvent fallback could not read '$EvtxPath'. $($_.Exception.Message)"
        $events = @()
    }
    catch {
        Write-Log -Level 'WARNING' -Message "Get-WinEvent event enumeration failed for '$EvtxPath'. $($_.Exception.Message)"
        $events = @()
    }

    $skipped = 0
    foreach ($eventRecord in @($events)) {
        if ($null -eq $eventRecord) { continue }

        try {
            $xmlText = ''
            try { $xmlText = ConvertTo-CanonicalString -Value $eventRecord.ToXml() } catch { $xmlText = '' }
            if ([string]::IsNullOrWhiteSpace($xmlText)) {
                $skipped++
                continue
            }

            $xml = [xml]$xmlText

            $eventId = 0
            try { $eventId = [int]$eventRecord.Id } catch { $eventId = 0 }
            if (@(4720, 4724, 4728, 4732, 4735, 4756, 4672) -notcontains $eventId) { continue }

            $fields = Resolve-PrivilegedAccessFields -EventId $eventId -XmlEvent $xml

            $actorUser      = ConvertTo-CanonicalString -Value $fields.ActorUser
            $actorDomain    = ConvertTo-CanonicalString -Value $fields.ActorDomain
            $targetUser     = ConvertTo-CanonicalString -Value $fields.TargetUser
            $targetDomain   = ConvertTo-CanonicalString -Value $fields.TargetDomain
            $groupName      = ConvertTo-CanonicalString -Value $fields.GroupName
            $groupDomain    = ConvertTo-CanonicalString -Value $fields.GroupDomain
            $privilegeList  = ConvertTo-CanonicalString -Value $fields.PrivilegeList
            $subjectLogonId = ConvertTo-CanonicalString -Value $fields.SubjectLogonId
            $rawEventData   = ConvertTo-CanonicalString -Value $fields.RawEventData
            $eventCategory  = ConvertTo-CanonicalString -Value $fields.EventCategory

            if (-not (Test-PrivAccessUserMatch -SubjectUser $actorUser -SubjectDomain $actorDomain -TargetUser $targetUser -TargetDomain $targetDomain -GroupName $groupName -GroupDomain $groupDomain -UserAccounts $UserAccounts)) { continue }

            $recordId = 0
            try { $recordId = [Int64]$eventRecord.RecordId } catch { $recordId = 0 }

            $providerName = ''
            try { $providerName = ConvertTo-CanonicalString -Value $eventRecord.ProviderName } catch { $providerName = '' }

            $machineName = ''
            try { $machineName = ConvertTo-CanonicalString -Value $eventRecord.MachineName } catch { $machineName = $computerName }
            if ([string]::IsNullOrWhiteSpace($machineName)) { $machineName = $computerName }

            $timeCreated = $null
            try { $timeCreated = $eventRecord.TimeCreated } catch { $timeCreated = $null }

            $row = New-ForensicEvidenceRow `
                -SourceEngine 'Get-WinEvent' `
                -SourceFile $EvtxPath `
                -ComputerName $machineName `
                -EventId $eventId `
                -EventCategory $eventCategory `
                -RecordId $recordId `
                -TimeCreated $timeCreated `
                -ProviderName $providerName `
                -ActorUser $actorUser `
                -ActorDomain $actorDomain `
                -TargetUser $targetUser `
                -TargetDomain $targetDomain `
                -GroupName $groupName `
                -GroupDomain $groupDomain `
                -PrivilegeList $privilegeList `
                -SubjectLogonId $subjectLogonId `
                -RawEventData $rawEventData

            [void]$rows.Add($row)
        }
        catch {
            $skipped++
            $rid = ''
            try { $rid = ConvertTo-CanonicalString -Value $eventRecord.RecordId } catch { $rid = '<unknown>' }
            Write-Log -Level 'WARNING' -Message "Skipped one event during forensic XML normalization. RecordId='$rid'; Error=$($_.Exception.Message)"
            continue
        }
    }

    $rowCount = Get-SafeCount -InputObject $rows
    Export-ForensicRowsToCsv -Rows @($rows) -Path $CsvPath
    Write-Log "Get-WinEvent forensic fallback completed. Records=$rowCount; SkippedEvents=$skipped"
    return $true
}

function Apply-CsvPostFilters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CsvPath,
        [Parameter()][string[]]$UserAccounts,
        [Parameter()][object]$StartTime,
        [Parameter()][object]$EndTime
    )

    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) { return }

    $rows = @(Import-Csv -LiteralPath $CsvPath)
    if ((Get-SafeCount -InputObject $rows) -eq 0) {
        New-HeaderOnlyCsv -Path $CsvPath
        return
    }

    $filtered = New-Object System.Collections.Generic.List[object]
    foreach ($row in @($rows)) {
        $keep = $true
        $dt = $null

        $timeText = ''
        try {
            if ($row.PSObject.Properties.Match('TimeCreated').Count -gt 0) { $timeText = [string]$row.TimeCreated }
            elseif ($row.PSObject.Properties.Match('EventTime').Count -gt 0) { $timeText = [string]$row.EventTime }
        } catch { $timeText = '' }

        if (-not [string]::IsNullOrWhiteSpace($timeText)) {
            try { $dt = [datetime]::Parse($timeText) } catch { $dt = $null }
        }

        if ($null -ne $StartTime -and $null -ne $dt -and $dt -lt ([datetime]$StartTime)) { $keep = $false }
        if ($null -ne $EndTime -and $null -ne $dt -and $dt -gt ([datetime]$EndTime)) { $keep = $false }

        $actorUser = ''
        $actorDomain = ''
        $targetUser = ''
        $targetDomain = ''
        $groupName = ''
        $groupDomain = ''
        try {
            if ($row.PSObject.Properties.Match('ActorUser').Count -gt 0) { $actorUser = [string]$row.ActorUser }
            elseif ($row.PSObject.Properties.Match('SubjectUser').Count -gt 0) { $actorUser = [string]$row.SubjectUser }
            if ($row.PSObject.Properties.Match('ActorDomain').Count -gt 0) { $actorDomain = [string]$row.ActorDomain }
            elseif ($row.PSObject.Properties.Match('SubjectDomain').Count -gt 0) { $actorDomain = [string]$row.SubjectDomain }
            if ($row.PSObject.Properties.Match('TargetUser').Count -gt 0) { $targetUser = [string]$row.TargetUser }
            if ($row.PSObject.Properties.Match('TargetDomain').Count -gt 0) { $targetDomain = [string]$row.TargetDomain }
            if ($row.PSObject.Properties.Match('GroupName').Count -gt 0) { $groupName = [string]$row.GroupName }
            if ($row.PSObject.Properties.Match('GroupDomain').Count -gt 0) { $groupDomain = [string]$row.GroupDomain }
        } catch { }

        if (-not (Test-PrivAccessUserMatch -SubjectUser $actorUser -SubjectDomain $actorDomain -TargetUser $targetUser -TargetDomain $targetDomain -GroupName $groupName -GroupDomain $groupDomain -UserAccounts $UserAccounts)) { $keep = $false }
        if ($keep) { [void]$filtered.Add($row) }
    }

    Export-ForensicRowsToCsv -Rows @($filtered) -Path $CsvPath
}

function Invoke-EventQueryToCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EvtxPath,
        [Parameter(Mandatory)][string]$CsvPath,
        [Parameter()][string[]]$UserAccounts,
        [Parameter()][object]$StartTime,
        [Parameter()][object]$EndTime
    )

    $lp = $null
    $query = Build-QueryForFile -EvtxPath $EvtxPath -CsvPath $CsvPath -UserAccounts $UserAccounts -StartTime $StartTime -EndTime $EndTime
    $executeResult = $false

    try {
        $lp = New-LogParserObjects

        # IMPORTANT: Log Parser COM CSVOutputFormat on Windows PowerShell 5.1 does not expose
        # a writable .fileName property in this execution context. The destination CSV is
        # controlled by the SQL INTO clause generated by Build-QueryForFile.
        $executeResult = $lp.Query.ExecuteBatch($query, $lp.InputFormat, $lp.OutputFormat)
        Write-Log "Log Parser COM SQL ExecuteBatch returned: $executeResult"
    }
    catch {
        Write-Log -Level 'WARNING' -Message "Log Parser COM failed for '$EvtxPath'. Error: $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $lp) { Release-LogParserObjects -Objects $lp }
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }

    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
        New-HeaderOnlyCsv -Path $CsvPath
    }

    $rowCount = Get-RowCountSafe -CsvPath $CsvPath
    if (($executeResult -eq $false) -or ($rowCount -eq 0)) {
        Write-Log -Level 'WARNING' -Message "Log Parser COM returned ExecuteBatch=$executeResult and RowCount=$rowCount for '$EvtxPath'. Running full Get-WinEvent forensic fallback."
        Remove-Item -LiteralPath $CsvPath -Force -ErrorAction SilentlyContinue
        return (Invoke-GetWinEventFallbackToCsv -EvtxPath $EvtxPath -CsvPath $CsvPath -UserAccounts $UserAccounts -StartTime $StartTime -EndTime $EndTime)
    }

    Write-Log "Log Parser COM output accepted. Records=$rowCount. Normalizing output schema."
    Apply-CsvPostFilters -CsvPath $CsvPath -UserAccounts $UserAccounts -StartTime $StartTime -EndTime $EndTime
    return $true
}

function New-EvtxSourceDescriptor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    return [PSCustomObject][ordered]@{
        FullName = [string]$fullPath
        Name     = [string][System.IO.Path]::GetFileName($fullPath)
    }
}

function Test-IsLikelyActiveEvtxPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $name = [System.IO.Path]::GetFileName($Path)
    $activeNames = @(
        'Application.evtx',
        'Security.evtx',
        'System.evtx',
        'Setup.evtx',
        'Microsoft-Windows-PrintService-Operational.evtx',
        'Active Directory Web Services.evtx',
        'State.evtx'
    )

    return ($activeNames -contains $name)
}

function Get-EvtxFilesSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][bool]$IncludeSubfolders
    )

    $resolvedRoot = ConvertTo-CanonicalString -Value $RootPath
    if ([string]::IsNullOrWhiteSpace($resolvedRoot)) {
        throw 'The EVTX folder path is empty.'
    }

    if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
        throw "The EVTX folder '$resolvedRoot' was not found."
    }

    Write-Log "Enumerating archived EVTX files. RootPath='$resolvedRoot'; IncludeSubfolders=$IncludeSubfolders"

    $rawFiles = @()
    try {
        if ($IncludeSubfolders) {
            $rawFiles = @(Get-ChildItem -LiteralPath $resolvedRoot -Filter '*.evtx' -File -Recurse -ErrorAction Stop)
        }
        else {
            $rawFiles = @(Get-ChildItem -LiteralPath $resolvedRoot -Filter '*.evtx' -File -ErrorAction Stop)
        }
    }
    catch {
        throw "Unable to enumerate EVTX files in '$resolvedRoot'. $($_.Exception.Message)"
    }

    # Path-agnostic archive mode:
    # return only absolute [string] paths. Do not return FileInfo, PSCustomObject,
    # generic lists, descriptors, or live-channel metadata objects.
    $selectedPaths = New-Object System.Collections.ArrayList
    $activeSkipped = 0
    $lockedSkipped = 0
    $invalidSkipped = 0

    foreach ($file in @($rawFiles)) {
        $path = ''
        try {
            if ($null -ne $file -and $file.PSObject.Properties.Match('FullName').Count -gt 0) {
                $path = [string]$file.FullName
            }
            else {
                $path = ConvertTo-CanonicalString -Value $file
            }
            if (-not [string]::IsNullOrWhiteSpace($path)) {
                $path = [System.IO.Path]::GetFullPath($path)
            }
        }
        catch {
            $path = ''
        }

        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $invalidSkipped++
            continue
        }

        if (Test-IsLikelyActiveEvtxPath -Path $path) {
            $activeSkipped++
            Write-Log -Level 'WARNING' -Message "Skipped likely active/canonical EVTX in archived mode to avoid file-lock errors: '$path'"
            continue
        }

        if (Test-IsFileLocked -Path $path) {
            $lockedSkipped++
            Write-Log -Level 'WARNING' -Message "Skipped locked EVTX file in archived mode: '$path'"
            continue
        }

        [void]$selectedPaths.Add([string]$path)
    }

    Write-Log "Archive-safe EVTX selection completed. Enumerated=$(Get-SafeCount -InputObject $rawFiles); Selected=$(Get-SafeCount -InputObject $selectedPaths); ActiveSkipped=$activeSkipped; LockedSkipped=$lockedSkipped; InvalidSkipped=$invalidSkipped"

    $result = New-Object System.Collections.ArrayList
    foreach ($selectedPath in @($selectedPaths)) {
        $cleanPath = ConvertTo-CanonicalString -Value $selectedPath
        if (-not [string]::IsNullOrWhiteSpace($cleanPath)) {
            [void]$result.Add([string]$cleanPath)
        }
    }

    return @($result | ForEach-Object { [string]$_ })
}

function Parse-DelimitedUsers {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Text
    )

    $rawText = if ($null -ne $Text) { [string]$Text } else { '' }
    if ([string]::IsNullOrWhiteSpace($rawText)) { return @() }

    $users = @(
        $rawText -split "[,;`r`n]+" |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    return @($users)
}
function Resolve-SecurityChannel {
    [CmdletBinding()]
    param()

    Update-ProgressSafe -Value 10 -StatusText 'Resolving Security channel via snapshot export...'
    $snapshot = Export-LiveChannelSnapshot -ChannelName 'Security'

    if (Test-Path -LiteralPath $snapshot -PathType Leaf) {
        Write-Log 'Live Security channel snapshot probe completed successfully. Privileged access row count is intentionally not required for channel validation.'
        Update-ProgressSafe -Value 0 -StatusText 'Ready.'
        return $snapshot
    }

    throw 'Live Security channel probe did not produce a snapshot file.'
}

function Process-PrivAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][bool]$UseLiveLog,
        [Parameter()][string]$EvtxFolder,
        [Parameter(Mandatory)][bool]$IncludeSubfolders,
        [Parameter()][string]$OutputFolder,
        [Parameter()][string[]]$UserAccounts,
        [Parameter()][object]$StartTime,
        [Parameter()][object]$EndTime
    )

    $resolvedOutput = Resolve-OutputFolder -Candidate $OutputFolder
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $finalCsv = Join-Path $resolvedOutput ('{0}-PrivilegedAccessTracking-{1}.csv' -f $computerName, $timestamp)
    $tempCsvFiles = New-Object System.Collections.ArrayList

    $normalizedUserAccounts = @($UserAccounts | ForEach-Object { if ($null -ne $_) { ([string]$_).Trim() } } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $userFilterCount = Get-SafeCount -InputObject $normalizedUserAccounts
    $userFilterDisplay = if ($userFilterCount -gt 0) { ($normalizedUserAccounts -join ', ') } else { '<none>' }
    Write-Log "Starting privileged access event processing. UseLiveLog=$UseLiveLog; Folder='$EvtxFolder'; IncludeSubfolders=$IncludeSubfolders; OutputFolder='$resolvedOutput'; StartTime=$StartTime; EndTime=$EndTime; UserFilterText='$userFilterDisplay'; UserFilterCount=$userFilterCount"
    $UserAccounts = @($normalizedUserAccounts)

    try {
        Update-ProgressSafe -Value 5 -StatusText 'Preparing...'

        $sourcePaths = New-Object System.Collections.ArrayList

        if ($UseLiveLog) {
            Update-ProgressSafe -Value 15 -StatusText 'Exporting Security snapshot...'
            $snapshot = Export-LiveChannelSnapshot -ChannelName 'Security'
            $snapshotPath = ConvertTo-CanonicalString -Value $snapshot
            if ([string]::IsNullOrWhiteSpace($snapshotPath) -or -not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
                throw "Live Security snapshot path is invalid: '$snapshotPath'"
            }
            [void]$sourcePaths.Add([string]$snapshotPath)
        }
        else {
            Update-ProgressSafe -Value 15 -StatusText 'Enumerating archived EVTX files...'
            Write-Log 'Archive mode selected. Using path-agnostic string-only EVTX pipeline.'
            $archivePaths = @(Get-EvtxFilesSafe -RootPath $EvtxFolder -IncludeSubfolders:$IncludeSubfolders)
            foreach ($archivePath in @($archivePaths)) {
                $candidatePath = ConvertTo-CanonicalString -Value $archivePath
                if ([string]::IsNullOrWhiteSpace($candidatePath)) { continue }
                if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
                    Write-Log -Level 'WARNING' -Message "Skipped invalid EVTX archive path after enumeration: '$candidatePath'"
                    continue
                }
                [void]$sourcePaths.Add([string]$candidatePath)
            }
        }

        $sourceCount = Get-SafeCount -InputObject $sourcePaths
        Write-Log "EVTX source path normalization completed. SourceCount=$sourceCount"
        if ($sourceCount -eq 0) {
            throw 'No .evtx files were found to process.'
        }

        $index = 0
        foreach ($sourcePathItem in @($sourcePaths)) {
            $index++
            $sourcePath = ConvertTo-CanonicalString -Value $sourcePathItem
            $sourceName = [System.IO.Path]::GetFileName($sourcePath)
            if ([string]::IsNullOrWhiteSpace($sourceName)) { $sourceName = 'EVTX' }

            try {
                $percent = 15 + [int]([Math]::Floor(([double]$index / [double]$sourceCount) * 65))
                Update-ProgressSafe -Value $percent -StatusText ("Processing {0} ({1} of {2})..." -f $sourceName, $index, $sourceCount)

                if ([string]::IsNullOrWhiteSpace($sourcePath) -or -not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                    Write-Log -Level 'WARNING' -Message "Skipped invalid EVTX source path at index $index."
                    continue
                }

                Write-Log ("Processing EVTX source {0} of {1}: '{2}'" -f $index, $sourceCount, $sourcePath)

                $tempCsv = Join-Path $env:TEMP ('PrivAccess-{0}-{1}.csv' -f $index, (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
                Register-TempArtifact -Path $tempCsv
                [void]$tempCsvFiles.Add([string]$tempCsv)

                $queryOk = Invoke-EventQueryToCsv -EvtxPath ([string]$sourcePath) -CsvPath ([string]$tempCsv) -UserAccounts @($UserAccounts) -StartTime $StartTime -EndTime $EndTime
                if ($queryOk -eq $false) {
                    Write-Log -Level 'WARNING' -Message "EVTX processing returned False for '$sourcePath'."
                    continue
                }

                Write-Log "Processed '$sourcePath'."
            }
            catch {
                Write-Log -Level 'WARNING' -Message "Skipped EVTX after non-fatal processing failure: '$sourcePath'. Stage='PerFileProcessing'; Error=$($_.Exception.Message)"
                continue
            }
        }

        Update-ProgressSafe -Value 88 -StatusText 'Merging CSV files...'
        Merge-CsvFiles -SourceCsvFiles @($tempCsvFiles) -DestinationCsv $finalCsv

        $rowCount = Get-RowCountSafe -CsvPath $finalCsv
        Update-ProgressSafe -Value 100 -StatusText ("Completed. Found {0} events. Report saved to '{1}'" -f $rowCount, $finalCsv)
        Write-Log "Found $rowCount privileged access records. Report exported to '$finalCsv'"

        if ($AutoOpen -and (Test-Path -LiteralPath $finalCsv -PathType Leaf)) {
            Start-Process -FilePath $finalCsv
        }

        Show-Info -Message ("Found {0} privileged access records.`r`nReport exported to:`r`n{1}" -f $rowCount, $finalCsv) -Title 'Success'
    }
    catch {
        Write-Log -Level 'ERROR' -Message "Error processing privileged access events. $($_.Exception.Message)"
        Update-ProgressSafe -Value 0 -StatusText 'Error occurred. Check log for details.'
        Show-ErrorBox -Message ("Error processing privileged access events.`r`n{0}" -f $_.Exception.Message)
    }
    finally {
        Remove-TempArtifacts
    }
}
#endregion

#region GUI
Initialize-LogDirectory
Write-Log '========== START: Privileged Access Tracking =========='
Write-Log "Script version: 2026-05-06-v1.0.8-PRODUCTION-PATH-AGNOSTIC-ARCHIVE-PIPELINE"
Write-Log "PowerShell version: $($PSVersionTable.PSVersion)"
Write-Log "Execution user: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Computer name: $computerName"
Write-Log "Log path: $script:logPath"
Register-WinFormsExceptionHandlers

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Privileged Access Tracking (4720/4724/4728/4732/4735/4756/4672)'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.ClientSize = New-Object System.Drawing.Size(760, 430)
$script:form = $form

$left = 14
$top = 16
$labelWidth = 165
$textWidth = 455
$buttonWidth = 92
$rowHeight = 38
$buttonGap = 10
$buttonX = ($left + $labelWidth + $textWidth + $buttonGap)
$currentY = $top

$checkUseLive = New-Object System.Windows.Forms.CheckBox
$checkUseLive.Location = New-Object System.Drawing.Point($left, $currentY)
$checkUseLive.Size = New-Object System.Drawing.Size(280, 24)
$checkUseLive.Text = 'Use live Security channel'
$checkUseLive.Checked = $true
$form.Controls.Add($checkUseLive)

$buttonResolve = New-Object System.Windows.Forms.Button
$buttonResolve.Location = New-Object System.Drawing.Point($buttonX, $currentY)
$buttonResolve.Size = New-Object System.Drawing.Size($buttonWidth, 24)
$buttonResolve.Text = 'Resolve'
$form.Controls.Add($buttonResolve)

$currentY = $currentY + $rowHeight

$labelEvtx = New-Object System.Windows.Forms.Label
$labelEvtx.Location = New-Object System.Drawing.Point($left, ($currentY + 3))
$labelEvtx.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelEvtx.Text = 'EVTX folder:'
$form.Controls.Add($labelEvtx)

$textEvtx = New-Object System.Windows.Forms.TextBox
$textEvtx.Location = New-Object System.Drawing.Point(($left + $labelWidth), $currentY)
$textEvtx.Size = New-Object System.Drawing.Size($textWidth, 24)
$textEvtx.Enabled = $false
$form.Controls.Add($textEvtx)

$buttonBrowseEvtx = New-Object System.Windows.Forms.Button
$buttonBrowseEvtx.Location = New-Object System.Drawing.Point($buttonX, $currentY)
$buttonBrowseEvtx.Size = New-Object System.Drawing.Size($buttonWidth, 24)
$buttonBrowseEvtx.Text = 'Browse'
$buttonBrowseEvtx.Enabled = $false
$form.Controls.Add($buttonBrowseEvtx)

$currentY = $currentY + $rowHeight

$checkIncludeSubfolders = New-Object System.Windows.Forms.CheckBox
$checkIncludeSubfolders.Location = New-Object System.Drawing.Point($left, $currentY)
$checkIncludeSubfolders.Size = New-Object System.Drawing.Size(240, 24)
$checkIncludeSubfolders.Text = 'Include subfolders'
$checkIncludeSubfolders.Checked = $true
$form.Controls.Add($checkIncludeSubfolders)

$currentY = $currentY + $rowHeight

$labelUsers = New-Object System.Windows.Forms.Label
$labelUsers.Location = New-Object System.Drawing.Point($left, ($currentY + 3))
$labelUsers.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelUsers.Text = 'User filter:'
$form.Controls.Add($labelUsers)

$textUsers = New-Object System.Windows.Forms.TextBox
$textUsers.Location = New-Object System.Drawing.Point(($left + $labelWidth), $currentY)
$textUsers.Size = New-Object System.Drawing.Size($textWidth, 24)
$textUsers.Text = [string]::Empty
$textUsers.AutoCompleteMode = [System.Windows.Forms.AutoCompleteMode]::None
$textUsers.AutoCompleteSource = [System.Windows.Forms.AutoCompleteSource]::None
$form.Controls.Add($textUsers)

$currentY = $currentY + 28

$labelUsersHint = New-Object System.Windows.Forms.Label
$labelUsersHint.Location = New-Object System.Drawing.Point(($left + $labelWidth), ($currentY + 2))
$labelUsersHint.Size = New-Object System.Drawing.Size(430, 18)
$labelUsersHint.Text = 'Separate multiple users with comma, semicolon, or line break.'
$form.Controls.Add($labelUsersHint)

$currentY = $currentY + 28

$checkDateRange = New-Object System.Windows.Forms.CheckBox
$checkDateRange.Location = New-Object System.Drawing.Point($left, $currentY)
$checkDateRange.Size = New-Object System.Drawing.Size(180, 24)
$checkDateRange.Text = 'Enable date range'
$checkDateRange.Checked = $false
$form.Controls.Add($checkDateRange)

$labelStartDate = New-Object System.Windows.Forms.Label
$labelStartDate.Location = New-Object System.Drawing.Point(($left + 190), ($currentY + 4))
$labelStartDate.Size = New-Object System.Drawing.Size(42, 20)
$labelStartDate.Text = 'Start:'
$form.Controls.Add($labelStartDate)

$dateStart = New-Object System.Windows.Forms.DateTimePicker
$dateStart.Location = New-Object System.Drawing.Point(($left + 235), $currentY)
$dateStart.Size = New-Object System.Drawing.Size(170, 24)
$dateStart.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$dateStart.CustomFormat = 'yyyy-MM-dd HH:mm'
$dateStart.Value = (Get-Date).Date
$dateStart.Enabled = $false
$form.Controls.Add($dateStart)

$labelEndDate = New-Object System.Windows.Forms.Label
$labelEndDate.Location = New-Object System.Drawing.Point(($left + 415), ($currentY + 4))
$labelEndDate.Size = New-Object System.Drawing.Size(36, 20)
$labelEndDate.Text = 'End:'
$form.Controls.Add($labelEndDate)

$dateEnd = New-Object System.Windows.Forms.DateTimePicker
$dateEnd.Location = New-Object System.Drawing.Point(($left + 455), $currentY)
$dateEnd.Size = New-Object System.Drawing.Size(170, 24)
$dateEnd.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$dateEnd.CustomFormat = 'yyyy-MM-dd HH:mm'
$dateEnd.Value = Get-Date
$dateEnd.Enabled = $false
$form.Controls.Add($dateEnd)

$currentY = $currentY + 38

$labelOutput = New-Object System.Windows.Forms.Label
$labelOutput.Location = New-Object System.Drawing.Point($left, ($currentY + 3))
$labelOutput.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelOutput.Text = 'CSV output folder:'
$form.Controls.Add($labelOutput)

$textOutput = New-Object System.Windows.Forms.TextBox
$textOutput.Location = New-Object System.Drawing.Point(($left + $labelWidth), $currentY)
$textOutput.Size = New-Object System.Drawing.Size($textWidth, 24)
$textOutput.Text = $script:defaultOutputFolder
$form.Controls.Add($textOutput)

$buttonBrowseOutput = New-Object System.Windows.Forms.Button
$buttonBrowseOutput.Location = New-Object System.Drawing.Point($buttonX, $currentY)
$buttonBrowseOutput.Size = New-Object System.Drawing.Size($buttonWidth, 24)
$buttonBrowseOutput.Text = 'Browse'
$form.Controls.Add($buttonBrowseOutput)

$currentY = $currentY + $rowHeight

$labelLog = New-Object System.Windows.Forms.Label
$labelLog.Location = New-Object System.Drawing.Point($left, ($currentY + 3))
$labelLog.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelLog.Text = 'Log folder:'
$form.Controls.Add($labelLog)

$textLog = New-Object System.Windows.Forms.TextBox
$textLog.Location = New-Object System.Drawing.Point(($left + $labelWidth), $currentY)
$textLog.Size = New-Object System.Drawing.Size($textWidth, 24)
$textLog.Text = $script:defaultLogFolder
$form.Controls.Add($textLog)

$buttonBrowseLog = New-Object System.Windows.Forms.Button
$buttonBrowseLog.Location = New-Object System.Drawing.Point($buttonX, $currentY)
$buttonBrowseLog.Size = New-Object System.Drawing.Size($buttonWidth, 24)
$buttonBrowseLog.Text = 'Browse'
$form.Controls.Add($buttonBrowseLog)

$currentY = $currentY + $rowHeight + 4

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point($left, $currentY)
$progressBar.Size = New-Object System.Drawing.Size(716, 22)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$form.Controls.Add($progressBar)
$script:progressBar = $progressBar

$currentY = $currentY + 28

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point($left, $currentY)
$statusLabel.Size = New-Object System.Drawing.Size(716, 32)
$statusLabel.Text = 'Ready.'
$form.Controls.Add($statusLabel)
$script:statusLabel = $statusLabel

$buttonStart = New-Object System.Windows.Forms.Button
$buttonStart.Size = New-Object System.Drawing.Size(150, 30)
$buttonStart.Location = New-Object System.Drawing.Point(420, 382)
$buttonStart.Text = 'Start Analysis'
$form.Controls.Add($buttonStart)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Size = New-Object System.Drawing.Size(120, 30)
$buttonClose.Location = New-Object System.Drawing.Point(590, 382)
$buttonClose.Text = 'Close'
$form.Controls.Add($buttonClose)

try {
    $initialSecurityFolder = Resolve-SecurityEvtxFolder
    if (-not [string]::IsNullOrWhiteSpace($initialSecurityFolder)) {
        $textEvtx.Text = $initialSecurityFolder
        Write-Log "Initial Security EVTX folder resolved: $initialSecurityFolder"
    }
}
catch {
    Write-Log -Level 'WARNING' -Message "Initial Security EVTX folder resolution failed: $($_.Exception.Message)"
}

$toggleInputs = {
    $isLive = $checkUseLive.Checked
    $textEvtx.Enabled = (-not $isLive)
    $buttonBrowseEvtx.Enabled = (-not $isLive)
}.GetNewClosure()
& $toggleInputs
$checkUseLive.Add_CheckedChanged($toggleInputs)

$toggleDateRange = {
    $dateStart.Enabled = $checkDateRange.Checked
    $dateEnd.Enabled = $checkDateRange.Checked
}.GetNewClosure()
$checkDateRange.Add_CheckedChanged($toggleDateRange)

$setBusyState = {
    param([bool]$IsBusy)

    $buttonStart.Enabled = (-not $IsBusy)
    $buttonClose.Enabled = (-not $IsBusy)
    $buttonResolve.Enabled = (-not $IsBusy)
    $buttonBrowseEvtx.Enabled = ((-not $IsBusy) -and (-not $checkUseLive.Checked))
    $buttonBrowseOutput.Enabled = (-not $IsBusy)
    $buttonBrowseLog.Enabled = (-not $IsBusy)
    $checkUseLive.Enabled = (-not $IsBusy)
    $checkIncludeSubfolders.Enabled = (-not $IsBusy)
    $textUsers.Enabled = (-not $IsBusy)
    $checkDateRange.Enabled = (-not $IsBusy)
    $dateStart.Enabled = ((-not $IsBusy) -and $checkDateRange.Checked)
    $dateEnd.Enabled = ((-not $IsBusy) -and $checkDateRange.Checked)
    $textOutput.Enabled = (-not $IsBusy)
    $textLog.Enabled = (-not $IsBusy)
}.GetNewClosure()

$buttonBrowseEvtx.Add_Click({
    $dialog = New-FolderPicker -Description 'Select a folder containing Security .evtx files'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textEvtx.Text = $dialog.SelectedPath
    }
    $dialog.Dispose()
})

$buttonBrowseOutput.Add_Click({
    $dialog = New-FolderPicker -Description 'Select the folder where the CSV report will be saved'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textOutput.Text = $dialog.SelectedPath
    }
    $dialog.Dispose()
})

$buttonBrowseLog.Add_Click({
    $dialog = New-FolderPicker -Description 'Select the log folder'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textLog.Text = $dialog.SelectedPath
        $script:defaultLogFolder = $dialog.SelectedPath
        $script:logPath = Join-Path $script:defaultLogFolder ($scriptName + '.log')
        Initialize-LogDirectory
    }
    $dialog.Dispose()
})

$buttonResolve.Add_Click({
    try {
        & $setBusyState $true
        $resolvedSecurityFolder = Resolve-SecurityEvtxFolder
        if (-not [string]::IsNullOrWhiteSpace($resolvedSecurityFolder)) {
            $textEvtx.Text = $resolvedSecurityFolder
        }

        $snapshotPath = Resolve-SecurityChannel

        if (-not [string]::IsNullOrWhiteSpace($resolvedSecurityFolder)) {
            Show-Info -Message ("Security channel validated successfully.`r`nEVTX folder:`r`n{0}`r`n`r`nSnapshot:`r`n{1}" -f $resolvedSecurityFolder, $snapshotPath) -Title 'Resolve Channel'
        }
        else {
            Show-Info -Message ("Security channel validated successfully, but the EVTX folder could not be resolved from registry.`r`nSnapshot:`r`n{0}" -f $snapshotPath) -Title 'Resolve Channel'
        }
    }
    catch {
        Write-Log -Level 'ERROR' -Message "Resolve Channel failed: $($_.Exception.Message)"
        Show-ErrorBox -Message ("Resolve Channel failed.`r`n{0}" -f $_.Exception.Message) -Title 'Resolve Channel'
    }
    finally {
        & $setBusyState $false
        & $toggleInputs
    }
}.GetNewClosure())

$buttonStart.Add_Click({
    try {
        & $setBusyState $true
        Write-Log 'GUI execution started.'
        $userFilterRawText = if ($null -ne $textUsers -and $null -ne $textUsers.Text) { [string]$textUsers.Text } else { '' }
        $users = Parse-DelimitedUsers -Text $userFilterRawText
        Write-Log ("GUI user filter captured. RawText='{0}'; ParsedCount={1}" -f $userFilterRawText, (Get-SafeCount -InputObject $users))
        $startFilter = $null
        $endFilter = $null
        if ($checkDateRange.Checked) {
            $startFilter = [datetime]$dateStart.Value
            $endFilter = [datetime]$dateEnd.Value
            if ($endFilter -lt $startFilter) {
                throw 'The end date/time cannot be earlier than the start date/time.'
            }
        }
        Process-PrivAccess -UseLiveLog:$checkUseLive.Checked -EvtxFolder $textEvtx.Text -IncludeSubfolders:$checkIncludeSubfolders.Checked -OutputFolder $textOutput.Text -UserAccounts $users -StartTime $startFilter -EndTime $endFilter
    }
    catch {
        Write-Log -Level 'ERROR' -Message "Start analysis failed: $($_.Exception.Message)"
        Show-ErrorBox -Message ("Start analysis failed.`r`n{0}" -f $_.Exception.Message)
    }
    finally {
        & $setBusyState $false
        & $toggleInputs
        Write-Log 'GUI execution finished.'
    }
}.GetNewClosure())

$buttonClose.Add_Click({
    $form.Close()
})

$form.Add_Shown({
    Write-Log 'GUI initialized successfully.'
})

$form.Add_FormClosed({
    Write-Log '========== END: Privileged Access Tracking =========='
})

[void]$form.ShowDialog()
#endregion

# End of script
