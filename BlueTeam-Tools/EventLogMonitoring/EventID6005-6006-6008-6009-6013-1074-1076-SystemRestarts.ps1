<#
.SYNOPSIS
    System Restart Event Auditor for Event IDs 6005, 6006, 6008, 6009, 6013, 1074, and 1076.

.DESCRIPTION
    Production-grade PowerShell 5.1 compatible WinForms tool for auditing Windows restart,
    shutdown, uptime, and unexpected shutdown events from the live System log or archived
    EVTX files.

    This revision follows the project baseline used by the other EVTX tools:
      - Log Parser-first live processing by exporting the System channel to a temporary EVTX snapshot.
      - Log Parser-first archive processing using Log Parser COM SQL when available.
      - Safe Get-WinEvent fallback when Log Parser is unavailable or fails.
      - Archive-safe EVTX selection with active/canonical and locked file exclusion.
      - Stable event parsing with XML/EventData extraction.
      - Structured logging to C:\Logs-TEMP using one log file per script.
      - Count-safe enumeration, guarded execution, and no-surprises GUI behavior.
      - Optional event collapse for repeated events with the same EventId, computer, provider, and source file.
      - WinForms JIT-safe exception handling using ThreadException and AppDomain handlers.

.AUTHOR
    Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
    2026-05-06-v1.4.1-LOGPARSER-COM-SQL-HOTFIX
#>

[CmdletBinding()]
param(
    [bool]$AutoOpen = $true,
    [switch]$ShowConsole,
    [int]$MaxArchiveFiles = 5000,
    [int]$CollapseWindowMinutes = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Runtime globals
$script:ScriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
if ([string]::IsNullOrWhiteSpace($script:ScriptName)) { $script:ScriptName = 'SystemRestartEventAuditor' }

$script:LogDir = 'C:\Logs-TEMP'
$script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')
$script:DefaultOutputFolder = [Environment]::GetFolderPath('MyDocuments')
$script:ProgressBar = $null
$script:StatusLabel = $null
$script:Form = $null
$script:RunInProgress = $false
$script:WinFormsExceptionHandlersRegistered = $false
$script:EventIds = @(6005, 6006, 6008, 6009, 6013, 1074, 1076)
$script:LiveChannelName = 'System'
$script:SystemChannelName = 'System'
$script:GuiToggleInputs = $null
$script:GuiSetBusyState = $null
#endregion Runtime globals

#region Console visibility
function Initialize-ConsoleVisibility {
    [CmdletBinding()]
    param([switch]$Visible)

    if ($Visible.IsPresent) { return }

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

        $handle = [Win32Console]::GetConsoleWindow()
        if ($handle -ne [IntPtr]::Zero) {
            [void][Win32Console]::ShowWindow($handle, 0)
        }
    }
    catch {
        # Console hiding must never break the operational tool.
    }
}
#endregion Console visibility

#region WinForms runtime initialization
function Initialize-WinFormsRuntime {
    [CmdletBinding()]
    param()

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop

        if (-not $script:WinFormsExceptionHandlersRegistered) {
            try {
                [System.Windows.Forms.Application]::SetUnhandledExceptionMode(
                    [System.Windows.Forms.UnhandledExceptionMode]::CatchException
                )
            }
            catch {
                # This may happen when the script is rerun inside an existing PowerShell/ISE host
                # after a WinForms control has already been created. Thread/AppDomain handlers
                # are still registered below when possible.
                try { Write-Log -Level 'WARNING' -Message ('SetUnhandledExceptionMode could not be applied before control creation: {0}' -f $_.Exception.Message) } catch {}
            }

            [System.Windows.Forms.Application]::add_ThreadException({
                param($Sender, $EventArgs)
                try {
                    $message = 'Unhandled UI exception.'
                    if ($EventArgs -and $EventArgs.Exception) {
                        $message = 'Unhandled UI exception: {0}' -f $EventArgs.Exception.Message
                    }
                    Write-Log -Level 'ERROR' -Message $message
                    try { Update-ProgressSafe -Value 0 -StatusText 'Unhandled UI exception. Check the log file for details.' } catch {}
                    try { Show-ErrorBox -Message $message -Title 'Unhandled UI Exception' } catch {}
                } catch {}
            })

            [AppDomain]::CurrentDomain.add_UnhandledException({
                param($Sender, $EventArgs)
                try {
                    $exceptionObject = $null
                    if ($EventArgs) { $exceptionObject = $EventArgs.ExceptionObject }
                    $message = 'Unhandled application exception.'
                    if ($exceptionObject -is [System.Exception]) {
                        $message = 'Unhandled application exception: {0}' -f $exceptionObject.Message
                    }
                    elseif ($exceptionObject) {
                        $message = 'Unhandled application exception: {0}' -f ([string]$exceptionObject)
                    }
                    Write-Log -Level 'ERROR' -Message $message
                } catch {}
            })

            $script:WinFormsExceptionHandlersRegistered = $true
            try { Write-Log 'WinForms JIT-safe exception handlers registered.' } catch {}
        }

        [System.Windows.Forms.Application]::EnableVisualStyles()
    }
    catch {
        throw ('Failed to initialize WinForms runtime: {0}' -f $_.Exception.Message)
    }
}
#endregion WinForms runtime initialization

#region Logging and UI helpers
function Initialize-LogDirectory {
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($script:LogDir)) {
        throw 'The log directory path cannot be empty.'
    }

    if (-not (Test-Path -LiteralPath $script:LogDir -PathType Container)) {
        New-Item -Path $script:LogDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'DEBUG')][string]$Level = 'INFO'
    )

    $entry = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try {
        if (-not (Test-Path -LiteralPath $script:LogDir -PathType Container)) {
            New-Item -Path $script:LogDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        Add-Content -LiteralPath $script:LogPath -Value $entry -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # Logging must not crash the tool.
    }
}

function Start-LogSession {
    [CmdletBinding()]
    param()

    Initialize-LogDirectory
    Write-Log '========== START: System Restart Event Auditor =========='
    Write-Log ("Script version: 2026-05-06-v1.4.1-LOGPARSER-COM-SQL-HOTFIX")
    Write-Log ("PowerShell version: {0}" -f $PSVersionTable.PSVersion)
    Write-Log ("Execution user: {0}\{1}" -f $env:USERDOMAIN, $env:USERNAME)
    Write-Log ("Computer name: {0}" -f $env:COMPUTERNAME)
    Write-Log ("Log path: {0}" -f $script:LogPath)
}

function Show-InfoBox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Title = 'Information'
    )

    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
}

function Show-ErrorBox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Title = 'Error'
    )

    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}

function Initialize-WinFormsExceptionHandling {
    [CmdletBinding()]
    param()

    if ($script:WinFormsExceptionHandlersRegistered) { return }

    try {
        [System.Windows.Forms.Application]::SetUnhandledExceptionMode(
            [System.Windows.Forms.UnhandledExceptionMode]::CatchException
        )

        [System.Windows.Forms.Application]::add_ThreadException({
            param($Sender, $EventArgs)

            try {
                $message = 'Unhandled UI exception.'
                if ($EventArgs -and $EventArgs.Exception) {
                    $message = 'Unhandled UI exception: {0}' -f $EventArgs.Exception.Message
                }

                Write-Log -Level 'ERROR' -Message $message
                try { Update-ProgressSafe -Value 0 -StatusText 'Unhandled UI exception. Check the log file for details.' } catch {}
                try { Show-ErrorBox -Message $message -Title 'Unhandled UI Exception' } catch {}
            }
            catch {
                # Exception handlers must never throw.
            }
        })

        [AppDomain]::CurrentDomain.add_UnhandledException({
            param($Sender, $EventArgs)

            try {
                $exceptionObject = $null
                if ($EventArgs) { $exceptionObject = $EventArgs.ExceptionObject }

                $message = 'Unhandled application exception.'
                if ($exceptionObject -is [System.Exception]) {
                    $message = 'Unhandled application exception: {0}' -f $exceptionObject.Message
                }
                elseif ($exceptionObject) {
                    $message = 'Unhandled application exception: {0}' -f ([string]$exceptionObject)
                }

                Write-Log -Level 'ERROR' -Message $message
            }
            catch {
                # Exception handlers must never throw.
            }
        })

        $script:WinFormsExceptionHandlersRegistered = $true
        Write-Log 'WinForms JIT-safe exception handlers registered.'
    }
    catch {
        try { Write-Log -Level 'WARNING' -Message ('Unable to register WinForms exception handlers: {0}' -f $_.Exception.Message) } catch {}
    }
}

function Invoke-GuiSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [string]$ErrorPrefix = 'GUI operation failed'
    )

    try {
        & $Action
    }
    catch {
        $message = '{0}: {1}' -f $ErrorPrefix, $_.Exception.Message
        Write-Log -Level 'ERROR' -Message $message
        try { Update-ProgressSafe -Value 0 -StatusText 'GUI operation failed. Check the log file for details.' } catch {}
        try { Show-ErrorBox -Message $message -Title 'GUI Error' } catch {}
    }
}

function Update-ProgressSafe {
    [CmdletBinding()]
    param(
        [int]$Value,
        [string]$StatusText
    )

    try {
        if ($script:ProgressBar) {
            $script:ProgressBar.Value = [Math]::Max(0, [Math]::Min(100, $Value))
        }
        if ($script:StatusLabel -and -not [string]::IsNullOrWhiteSpace($StatusText)) {
            $script:StatusLabel.Text = $StatusText
        }
        if ($script:Form) {
            $script:Form.Refresh()
            [System.Windows.Forms.Application]::DoEvents()
        }
    }
    catch {
        # UI refresh must not interrupt processing.
    }
}
#endregion Logging and UI helpers

#region Validation and external command helpers
function Test-IsWindowsHost {
    [CmdletBinding()]
    param()

    return ([Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
}

function Resolve-OutputFolder {
    [CmdletBinding()]
    param([string]$Candidate)

    $resolved = $Candidate
    if ([string]::IsNullOrWhiteSpace($resolved)) { $resolved = $script:DefaultOutputFolder }
    if ([string]::IsNullOrWhiteSpace($resolved)) { throw 'The output folder path cannot be empty.' }

    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        New-Item -Path $resolved -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    return $resolved
}

function Test-IsFileLocked {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }

    $stream = $null
    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::None
        )
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
    param([Parameter(Mandatory)][object]$File)

    # PATH-AGNOSTIC ARCHIVE RULE:
    # Do not skip evidence files by canonical names such as Security.evtx/System.evtx.
    # Archived EVTX files may legitimately keep their original channel filename in any folder.
    return $false
}


function Get-ArchiveSafeEvtxFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Files)

    $safeFiles = New-Object System.Collections.Generic.List[string]
    $enumeratedCount = 0
    $selectedCount = 0
    $lockedSkippedCount = 0
    $invalidSkippedCount = 0

    foreach ($file in @($Files)) {
        $enumeratedCount++
        try {
            $path = $null
            if ($file -is [System.IO.FileInfo]) {
                $path = [string]$file.FullName
            }
            elseif ($file -and $file.PSObject.Properties['FullName']) {
                $path = [string]$file.FullName
            }
            else {
                $path = [string]$file
            }

            if ([string]::IsNullOrWhiteSpace($path)) {
                $invalidSkippedCount++
                continue
            }

            $absolutePath = [System.IO.Path]::GetFullPath($path)
            if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
                $invalidSkippedCount++
                continue
            }

            if ([System.IO.Path]::GetExtension($absolutePath) -ine '.evtx') {
                $invalidSkippedCount++
                continue
            }

            if (Test-IsFileLocked -Path $absolutePath) {
                Write-Log "Skipped locked EVTX file in archived mode: '$absolutePath'" 'WARNING'
                $lockedSkippedCount++
                continue
            }

            [void]$safeFiles.Add([string]$absolutePath)
            $selectedCount++
        }
        catch {
            $invalidSkippedCount++
            Write-Log "Skipped invalid EVTX source in archived mode. Error: $($_.Exception.Message)" 'WARNING'
        }
    }

    Write-Log "Archive-safe PATH-AGNOSTIC EVTX selection completed. Enumerated=$enumeratedCount; Selected=$selectedCount; LockedSkipped=$lockedSkippedCount; InvalidSkipped=$invalidSkippedCount"
    return @($safeFiles.ToArray())
}


function Resolve-LogParserPath {
    [CmdletBinding()]
    param()

    $candidates = New-Object System.Collections.Generic.List[string]

    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    $programFiles = [Environment]::GetEnvironmentVariable('ProgramFiles')

    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
        [void]$candidates.Add((Join-Path $programFilesX86 'Log Parser 2.2\LogParser.exe'))
    }
    if (-not [string]::IsNullOrWhiteSpace($programFiles)) {
        [void]$candidates.Add((Join-Path $programFiles 'Log Parser 2.2\LogParser.exe'))
    }

    [void]$candidates.Add('C:\Program Files (x86)\Log Parser 2.2\LogParser.exe')
    [void]$candidates.Add('C:\Program Files\Log Parser 2.2\LogParser.exe')

    foreach ($candidate in @($candidates)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }

    try {
        $cmd = Get-Command -Name 'LogParser.exe' -ErrorAction Stop
        if ($cmd -and (Test-Path -LiteralPath $cmd.Source -PathType Leaf)) { return $cmd.Source }
    }
    catch {}

    return $null
}


function Test-LogParserComAvailable {
    [CmdletBinding()]
    param()

    $query = $null
    $inputFormat = $null
    $outputFormat = $null

    try {
        $query = New-Object -ComObject 'MSUtil.LogQuery'
        $inputFormat = New-Object -ComObject 'MSUtil.LogQuery.EventLogInputFormat'
        $outputFormat = New-Object -ComObject 'MSUtil.LogQuery.CSVOutputFormat'
        return $true
    }
    catch {
        Write-Log -Level 'WARNING' -Message ("Log Parser COM is not available. Error: {0}" -f $_.Exception.Message)
        return $false
    }
    finally {
        foreach ($obj in @($outputFormat, $inputFormat, $query)) {
            if ($null -ne $obj -and [System.Runtime.InteropServices.Marshal]::IsComObject($obj)) {
                try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($obj) } catch {}
            }
        }
    }
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
                try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($obj) } catch {}
            }
        }
    }
}

function Escape-LogParserSqlLiteral {
    [CmdletBinding()]
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return '' }
    return $Value.Replace("'", "''")
}

function ConvertTo-ProcessArgumentString {
    [CmdletBinding()]
    param([string[]]$Arguments)

    $quoted = foreach ($arg in @($Arguments)) {
        if ($null -eq $arg) { continue }

        $value = [string]$arg
        if ($value.Length -eq 0) {
            '""'
        }
        elseif ($value -match '[\s"]') {
            '"' + ($value.Replace('\', '\\').Replace('"', '\"')) + '"'
        }
        else {
            $value
        }
    }

    return ($quoted -join ' ')
}

function Invoke-ExternalProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$TimeoutSeconds = 1800
    )

    if ([string]::IsNullOrWhiteSpace($FilePath)) {
        throw 'External process file path cannot be empty.'
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.Arguments = ConvertTo-ProcessArgumentString -Arguments $Arguments

    Write-Log -Level 'DEBUG' -Message ("Starting external process: {0} {1}" -f $FilePath, $psi.Arguments)

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    [void]$process.Start()
    $completed = $process.WaitForExit($TimeoutSeconds * 1000)

    if (-not $completed) {
        try { $process.Kill() } catch {}
        throw "External process timed out after $TimeoutSeconds seconds: $FilePath"
    }

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }
}
#endregion Validation and external command helpers

#region Event parsing
function Get-RestartEventDescription {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$EventId)

    switch ($EventId) {
        6005 { 'Event Log service started. Usually indicates system startup.' }
        6006 { 'Event Log service stopped. Usually indicates clean shutdown.' }
        6008 { 'Previous system shutdown was unexpected.' }
        6009 { 'Operating system version detected during startup.' }
        6013 { 'System uptime reported.' }
        1074 { 'Planned restart or shutdown initiated by a process or user.' }
        1076 { 'Reason supplied after an unexpected shutdown.' }
        default { 'Restart-related event.' }
    }
}

function Get-EventDataMap {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Event)

    $map = @{}
    try {
        [xml]$xml = $Event.ToXml()
        $index = 0
        foreach ($data in @($xml.Event.EventData.Data)) {
            $name = $data.Name
            if ([string]::IsNullOrWhiteSpace($name)) { $name = "Data$index" }
            $map[$name] = [string]$data.'#text'
            $index++
        }
    }
    catch {}

    return $map
}

function ConvertTo-RestartEventRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Event,
        [string]$SourceFile = 'Live System Log',
        [string]$Parser = 'Get-WinEvent'
    )

    $eventData = Get-EventDataMap -Event $Event
    $shutdownType = $null
    $shutdownReason = $null
    $shutdownProcess = $null
    $shutdownUser = $null
    $comment = $null

    if ($eventData.ContainsKey('param1')) { $shutdownProcess = $eventData['param1'] }
    if ($eventData.ContainsKey('param2')) { $shutdownUser = $eventData['param2'] }
    if ($eventData.ContainsKey('param3')) { $shutdownReason = $eventData['param3'] }
    if ($eventData.ContainsKey('param4')) { $shutdownType = $eventData['param4'] }
    if ($eventData.ContainsKey('param5')) { $comment = $eventData['param5'] }

    [pscustomobject]@{
        TimeCreated      = $Event.TimeCreated
        EventId          = [int]$Event.Id
        EventDescription = Get-RestartEventDescription -EventId ([int]$Event.Id)
        MachineName      = $Event.MachineName
        ProviderName     = $Event.ProviderName
        RecordId         = $Event.RecordId
        ShutdownProcess  = $shutdownProcess
        ShutdownUser     = $shutdownUser
        ShutdownReason   = $shutdownReason
        ShutdownType     = $shutdownType
        Comment          = $comment
        Parser           = $Parser
        SourceFile       = $SourceFile
        Message          = $Event.Message
    }
}

function ConvertFrom-LogParserCsvRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Row,
        [Parameter(Mandatory)][string]$SourceFile
    )

    $timeValue = $null
    try { $timeValue = [datetime]$Row.TimeGenerated } catch { $timeValue = $null }

    $eventId = 0
    [void][int]::TryParse([string]$Row.EventID, [ref]$eventId)

    [pscustomobject]@{
        TimeCreated      = $timeValue
        EventId          = $eventId
        EventDescription = Get-RestartEventDescription -EventId $eventId
        MachineName      = [string]$Row.ComputerName
        ProviderName     = [string]$Row.SourceName
        RecordId         = [string]$Row.RecordNumber
        ShutdownProcess  = $null
        ShutdownUser     = $null
        ShutdownReason   = $null
        ShutdownType     = $null
        Comment          = $null
        Parser           = 'LogParser'
        SourceFile       = $SourceFile
        Message          = [string]$Row.Message
    }
}
#endregion Event parsing


function Get-EventChannelLogPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ChannelName)

    $candidates = New-Object System.Collections.Generic.List[string]

    if ([string]::IsNullOrWhiteSpace($ChannelName)) {
        throw 'The event channel name cannot be empty.'
    }

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'wevtutil.exe'
        $psi.UseShellExecute = $false
        $psi.RedirectStandardError = $true
        $psi.RedirectStandardOutput = $true
        $psi.CreateNoWindow = $true
        $psi.Arguments = ('gl "{0}" /f:xml' -f $ChannelName)

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        [void]$process.Start()
        $stdOut = $process.StandardOutput.ReadToEnd()
        $stdErr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        if ($process.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($stdOut)) {
            try {
                [xml]$xml = $stdOut
                $xmlValue = $xml.SelectSingleNode('//logFileName')
                if ($null -ne $xmlValue -and -not [string]::IsNullOrWhiteSpace($xmlValue.InnerText)) {
                    [void]$candidates.Add($xmlValue.InnerText.Trim())
                }
            }
            catch {
                Write-Log -Level 'WARNING' -Message ("Unable to parse wevtutil XML output for channel '{0}': {1}" -f $ChannelName, $_.Exception.Message)
            }
        }
        else {
            Write-Log -Level 'WARNING' -Message ("wevtutil XML query did not return a log file for channel '{0}'. ExitCode={1}. StdErr={2}" -f $ChannelName, $process.ExitCode, $stdErr.Trim())
        }
    }
    catch {
        Write-Log -Level 'WARNING' -Message ("wevtutil XML query failed for channel '{0}': {1}" -f $ChannelName, $_.Exception.Message)
    }

    try {
        $classicName = if ($ChannelName -eq 'System') { 'System' } else { $ChannelName }
        $classicPath = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\$classicName"
        if (Test-Path -LiteralPath $classicPath) {
            $fileValue = (Get-ItemProperty -LiteralPath $classicPath -Name File -ErrorAction SilentlyContinue).File
            if (-not [string]::IsNullOrWhiteSpace($fileValue)) { [void]$candidates.Add($fileValue.Trim()) }
        }
    }
    catch {
        Write-Log -Level 'WARNING' -Message ("Classic EventLog registry lookup failed for channel '{0}': {1}" -f $ChannelName, $_.Exception.Message)
    }

    try {
        $winevtPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\$ChannelName"
        if (Test-Path -LiteralPath $winevtPath) {
            $fileValue = (Get-ItemProperty -LiteralPath $winevtPath -Name File -ErrorAction SilentlyContinue).File
            if (-not [string]::IsNullOrWhiteSpace($fileValue)) { [void]$candidates.Add($fileValue.Trim()) }
        }
    }
    catch {
        Write-Log -Level 'WARNING' -Message ("WINEVT registry lookup failed for channel '{0}': {1}" -f $ChannelName, $_.Exception.Message)
    }

    foreach ($candidate in @($candidates)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $expanded = [Environment]::ExpandEnvironmentVariables($candidate)
        if (-not [System.IO.Path]::IsPathRooted($expanded)) { $expanded = Join-Path -Path $env:SystemRoot -ChildPath $expanded }
        if (-not [string]::IsNullOrWhiteSpace($expanded)) {
            Write-Log ("Resolved channel '{0}' log path candidate: {1}" -f $ChannelName, $expanded)
            return $expanded
        }
    }

    return $null
}

function Resolve-EventChannelFolder {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ChannelName)

    $logPath = Get-EventChannelLogPath -ChannelName $ChannelName
    if ([string]::IsNullOrWhiteSpace($logPath)) { return $null }

    $folder = [System.IO.Path]::GetDirectoryName($logPath)
    if ([string]::IsNullOrWhiteSpace($folder)) { return $null }

    return $folder
}

function Export-LiveChannelSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ChannelName)

    $tempPath = Join-Path $env:TEMP ("{0}_{1}_{2}.evtx" -f $script:ScriptName, $ChannelName, (Get-Date -Format 'yyyyMMddHHmmss'))
    $args = @('epl', $ChannelName, $tempPath, '/ow:true')
    $execution = Invoke-ExternalProcess -FilePath 'wevtutil.exe' -Arguments $args -TimeoutSeconds 300
    if ($execution.ExitCode -ne 0) {
        throw ("wevtutil export failed for channel '{0}'. ExitCode={1}; StdErr={2}" -f $ChannelName, $execution.ExitCode, $execution.StdErr)
    }
    if (-not (Test-Path -LiteralPath $tempPath -PathType Leaf)) {
        throw "wevtutil reported success, but the snapshot file was not created: $tempPath"
    }
    return $tempPath
}


function Resolve-SystemEvtxFolder {
    [CmdletBinding()]
    param()

    return Resolve-EventChannelFolder -ChannelName 'System'
}

function Resolve-SystemChannel {
    [CmdletBinding()]
    param()

    $snapshot = Export-LiveChannelSnapshot -ChannelName 'System'
    return $snapshot
}

#region Event collection
function Get-RestartEventsLive {
    [CmdletBinding()]
    param()

    $snapshotPath = $null

    try {
        Write-Log 'Live System log processing started in Log Parser-first snapshot mode.'
        Update-ProgressSafe -Value 8 -StatusText 'Exporting live System channel snapshot...'

        $snapshotPath = Export-LiveChannelSnapshot -ChannelName 'System'
        Write-Log ("Live System channel snapshot created: {0}" -f $snapshotPath)

        $snapshotFile = Get-Item -LiteralPath $snapshotPath -ErrorAction Stop

        if (Test-LogParserComAvailable) {
            Write-Log 'Log Parser COM detected for live snapshot. SQL query mode enabled.'
            Update-ProgressSafe -Value 15 -StatusText 'Running Log Parser COM SQL against live snapshot...'

            $logParserEvents = @(Get-RestartEventsFromEvtxWithLogParser -Files @($snapshotFile))
            if ($logParserEvents.Count -gt 0) {
                Write-Log ("Live System snapshot Log Parser COM SQL processing completed. RawEvents={0}" -f $logParserEvents.Count)
                return $logParserEvents
            }

            Write-Log -Level 'WARNING' -Message 'Live System snapshot Log Parser COM SQL returned zero records or failed. Falling back to Get-WinEvent against snapshot.'
        }
        else {
            Write-Log -Level 'WARNING' -Message 'Log Parser COM was not detected. Live snapshot Get-WinEvent fallback mode will be used.'
        }

        Update-ProgressSafe -Value 20 -StatusText 'Running Get-WinEvent fallback against live snapshot...'
        $fallbackEvents = @(Get-RestartEventsFromEvtxWithGetWinEvent -Files @($snapshotFile))
        Write-Log ("Live System snapshot Get-WinEvent fallback completed. RawEvents={0}" -f $fallbackEvents.Count)
        return $fallbackEvents
    }
    catch {
        Write-Log -Level 'WARNING' -Message ("Live snapshot processing failed. Falling back to direct live Get-WinEvent. Error: {0}" -f $_.Exception.Message)
        Update-ProgressSafe -Value 20 -StatusText 'Running direct live Get-WinEvent fallback...'

        $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = $script:EventIds } -ErrorAction Stop)
        Write-Log ("Direct live System log fallback completed. RawEvents={0}" -f $events.Count)
        return @($events | ForEach-Object { ConvertTo-RestartEventRecord -Event $_ -SourceFile 'Live System Log' -Parser 'Get-WinEvent-LiveFallback' })
    }
    finally {
        if (-not [string]::IsNullOrWhiteSpace($snapshotPath) -and (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
            $removed = $false
            for ($attempt = 1; $attempt -le 5 -and -not $removed; $attempt++) {
                try {
                    [GC]::Collect()
                    [GC]::WaitForPendingFinalizers()
                    Start-Sleep -Milliseconds (150 * $attempt)
                    Remove-Item -LiteralPath $snapshotPath -Force -ErrorAction Stop
                    Write-Log ("Temporary live System snapshot removed: {0}" -f $snapshotPath)
                    $removed = $true
                }
                catch {
                    if ($attempt -eq 5) {
                        Write-Log -Level 'WARNING' -Message ("Unable to remove temporary live System snapshot after retries: {0}. Error: {1}" -f $snapshotPath, $_.Exception.Message)
                    }
                }
            }
        }
    }
}

function Get-RestartEventsFromEvtxWithGetWinEvent {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.IO.FileInfo[]]$Files)

    $results = New-Object System.Collections.ArrayList
    $index = 0

    foreach ($file in @($Files)) {
        $index++
        $percent = 10 + [int]([Math]::Floor(($index / [Math]::Max(1, $Files.Count)) * 75))
        Update-ProgressSafe -Value $percent -StatusText ("Get-WinEvent fallback: {0} ({1}/{2})" -f $file.Name, $index, $Files.Count)
        Write-Log ("Get-WinEvent processing: {0}" -f $file.FullName)

        try {
            $events = @(Get-WinEvent -FilterHashtable @{ Path = $file.FullName; Id = $script:EventIds } -ErrorAction Stop)
            foreach ($evt in $events) {
                [void]$results.Add((ConvertTo-RestartEventRecord -Event $evt -SourceFile $file.FullName -Parser 'Get-WinEvent'))
            }
        }
        catch {
            Write-Log -Level 'WARNING' -Message ("Skipped EVTX after Get-WinEvent failure: {0}. Error: {1}" -f $file.FullName, $_.Exception.Message)
        }
    }

    Write-Log ("Get-WinEvent archive processing completed. Records={0}" -f $results.Count)
    return @($results)
}

function Get-RestartEventsFromEvtxWithLogParser {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.IO.FileInfo[]]$Files)

    $results = New-Object System.Collections.ArrayList
    $tempRoot = Join-Path $env:TEMP ("{0}_{1}" -f $script:ScriptName, (Get-Date -Format 'yyyyMMddHHmmss'))
    New-Item -Path $tempRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null

    try {
        $index = 0
        foreach ($file in @($Files)) {
            $index++
            $percent = 10 + [int]([Math]::Floor(($index / [Math]::Max(1, $Files.Count)) * 75))
            Update-ProgressSafe -Value $percent -StatusText ("Log Parser COM SQL: {0} ({1}/{2})" -f $file.Name, $index, $Files.Count)
            Write-Log ("Log Parser COM SQL processing: {0}" -f $file.FullName)

            $safeName = ($file.BaseName -replace '[^a-zA-Z0-9_-]', '_') + '_' + $index + '.csv'
            $tempCsv = Join-Path $tempRoot $safeName
            $escapedCsv = Escape-LogParserSqlLiteral -Value $tempCsv
            $escapedEvtx = Escape-LogParserSqlLiteral -Value $file.FullName
            $eventIdList = ($script:EventIds -join ',')

            $query = @"
SELECT
    TimeGenerated,
    EventID,
    SourceName,
    ComputerName,
    RecordNumber,
    Message
INTO '$escapedCsv'
FROM '$escapedEvtx'
WHERE EventID IN ($eventIdList)
"@

            $lp = $null
            try {
                $lp = New-LogParserObjects
                $result = $lp.Query.ExecuteBatch($query, $lp.InputFormat, $lp.OutputFormat)
                Write-Log ("Log Parser COM ExecuteBatch returned for '{0}': {1}" -f $file.FullName, $result)

                if (Test-Path -LiteralPath $tempCsv -PathType Leaf) {
                    $rows = @(Import-Csv -LiteralPath $tempCsv -ErrorAction Stop)
                    foreach ($row in $rows) {
                        [void]$results.Add((ConvertFrom-LogParserCsvRow -Row $row -SourceFile $file.FullName))
                    }
                }
                else {
                    Write-Log -Level 'WARNING' -Message ("Log Parser COM SQL did not create the expected CSV for: {0}" -f $file.FullName)
                }
            }
            catch {
                Write-Log -Level 'WARNING' -Message ("Log Parser COM SQL failed for {0}. Error: {1}" -f $file.FullName, $_.Exception.Message)
                continue
            }
            finally {
                if ($null -ne $lp) { Release-LogParserObjects -Objects $lp }
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
            }
        }
    }
    finally {
        try { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }

    Write-Log ("Log Parser COM SQL archive processing completed. Records={0}" -f $results.Count)
    return @($results)
}

function Get-RestartEventsFromEvtx {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][bool]$IncludeSubfolders
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "The EVTX folder was not found: $Path"
    }

    Write-Log ("Starting archived EVTX scan. Folder='{0}'; IncludeSubfolders={1}; MaxArchiveFiles={2}" -f $Path, $IncludeSubfolders, $MaxArchiveFiles)

    if ($IncludeSubfolders) {
        $candidateFiles = @(Get-ChildItem -LiteralPath $Path -Filter '*.evtx' -File -Recurse -ErrorAction Stop)
    }
    else {
        $candidateFiles = @(Get-ChildItem -LiteralPath $Path -Filter '*.evtx' -File -ErrorAction Stop)
    }

    if ($candidateFiles.Count -eq 0) {
        throw "No .evtx files were found in: $Path"
    }

    $files = @(Get-ArchiveSafeEvtxFiles -Files $candidateFiles -MaximumFiles $MaxArchiveFiles)
    if ($files.Count -eq 0) {
        throw 'No archive-safe EVTX files are available for processing after validation.'
    }

    if (Test-LogParserComAvailable) {
        Write-Log 'Log Parser COM detected. Log Parser-first SQL mode enabled.'
        $logParserEvents = @(Get-RestartEventsFromEvtxWithLogParser -Files $files)

        if ($logParserEvents.Count -gt 0) {
            return $logParserEvents
        }

        Write-Log -Level 'WARNING' -Message 'Log Parser COM SQL returned zero records or failed for all files. Falling back to Get-WinEvent.'
    }
    else {
        Write-Log -Level 'WARNING' -Message 'Log Parser COM was not detected. Get-WinEvent fallback mode will be used.'
    }

    return @(Get-RestartEventsFromEvtxWithGetWinEvent -Files $files)
}
#endregion Event collection

#region Collapse and export
function Compress-RestartEventRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Records,
        [int]$WindowMinutes = 3
    )

    $sorted = @($Records | Sort-Object TimeCreated, EventId, MachineName, ProviderName, SourceFile)
    if ($sorted.Count -eq 0) { return @() }

    $collapsed = New-Object System.Collections.ArrayList
    $current = $null

    foreach ($record in $sorted) {
        if ($null -eq $record.TimeCreated) {
            [void]$collapsed.Add($record)
            continue
        }

        $sameGroup = $false
        if ($current) {
            $deltaMinutes = [Math]::Abs((New-TimeSpan -Start $current.LastTimeCreated -End $record.TimeCreated).TotalMinutes)
            $sameGroup = (
                $current.EventId -eq $record.EventId -and
                $current.MachineName -eq $record.MachineName -and
                $current.ProviderName -eq $record.ProviderName -and
                $current.SourceFile -eq $record.SourceFile -and
                $deltaMinutes -le $WindowMinutes
            )
        }

        if ($sameGroup) {
            $current.LastTimeCreated = $record.TimeCreated
            $current.Count++
            if (-not [string]::IsNullOrWhiteSpace($record.Message)) { $current.Message = $record.Message }
            continue
        }

        $current = [pscustomobject]@{
            FirstTimeCreated = $record.TimeCreated
            LastTimeCreated  = $record.TimeCreated
            Count            = 1
            EventId          = $record.EventId
            EventDescription = $record.EventDescription
            MachineName      = $record.MachineName
            ProviderName     = $record.ProviderName
            FirstRecordId    = $record.RecordId
            ShutdownProcess  = $record.ShutdownProcess
            ShutdownUser     = $record.ShutdownUser
            ShutdownReason   = $record.ShutdownReason
            ShutdownType     = $record.ShutdownType
            Comment          = $record.Comment
            Parser           = $record.Parser
            SourceFile       = $record.SourceFile
            Message          = $record.Message
        }
        [void]$collapsed.Add($current)
    }

    Write-Log ("Collapse completed. RawRecords={0}; CollapsedRecords={1}; WindowMinutes={2}" -f $sorted.Count, $collapsed.Count, $WindowMinutes)
    return @($collapsed)
}

function Export-RestartReports {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Records,
        [Parameter(Mandatory)][string]$OutputFolder,
        [bool]$Collapse,
        [int]$CollapseMinutes
    )

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $rawPath = Join-Path $OutputFolder ("{0}-SystemRestartEvents-RAW-{1}.csv" -f $env:COMPUTERNAME, $timestamp)
    $summaryPath = Join-Path $OutputFolder ("{0}-SystemRestartEvents-COLLAPSED-{1}.csv" -f $env:COMPUTERNAME, $timestamp)

    $rawRecords = @($Records | Sort-Object TimeCreated, EventId)
    $rawRecords | Export-Csv -LiteralPath $rawPath -NoTypeInformation -Encoding UTF8
    Write-Log ("Raw CSV exported: {0}" -f $rawPath)

    $collapsedRecords = @()
    if ($Collapse) {
        $collapsedRecords = @(Compress-RestartEventRecords -Records $rawRecords -WindowMinutes $CollapseMinutes)
        $collapsedRecords | Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8
        Write-Log ("Collapsed CSV exported: {0}" -f $summaryPath)
    }

    return [pscustomobject]@{
        RawPath        = $rawPath
        CollapsedPath  = $summaryPath
        RawCount       = $rawRecords.Count
        CollapsedCount = $collapsedRecords.Count
    }
}
#endregion Collapse and export

#region Main processing
function Process-SystemRestartEvents {
    [CmdletBinding()]
    param(
        [bool]$UseLiveLog,
        [string]$EvtxFolder,
        [bool]$IncludeSubfolders,
        [string]$OutputFolder,
        [bool]$CollapseEvents
    )

    $resolvedOutput = Resolve-OutputFolder -Candidate $OutputFolder
    Write-Log ("Processing started. UseLiveLog={0}; EvtxFolder='{1}'; IncludeSubfolders={2}; OutputFolder='{3}'; CollapseEvents={4}" -f $UseLiveLog, $EvtxFolder, $IncludeSubfolders, $resolvedOutput, $CollapseEvents)

    Update-ProgressSafe -Value 5 -StatusText 'Preparing event collection...'

    if ($UseLiveLog -or [string]::IsNullOrWhiteSpace($EvtxFolder)) {
        Update-ProgressSafe -Value 20 -StatusText 'Reading live System log...'
        $events = @(Get-RestartEventsLive)
    }
    else {
        Update-ProgressSafe -Value 10 -StatusText 'Scanning archived EVTX files...'
        $events = @(Get-RestartEventsFromEvtx -Path $EvtxFolder -IncludeSubfolders:$IncludeSubfolders)
    }

    Update-ProgressSafe -Value 88 -StatusText 'Sorting and exporting reports...'
    $events = @($events | Sort-Object TimeCreated, EventId)

    $report = Export-RestartReports -Records $events -OutputFolder $resolvedOutput -Collapse:$CollapseEvents -CollapseMinutes $CollapseWindowMinutes

    Update-ProgressSafe -Value 100 -StatusText ("Completed. Raw={0}; Collapsed={1}" -f $report.RawCount, $report.CollapsedCount)
    Write-Log ("Processing completed. Raw={0}; Collapsed={1}; RawPath='{2}'; CollapsedPath='{3}'" -f $report.RawCount, $report.CollapsedCount, $report.RawPath, $report.CollapsedPath)

    if ($AutoOpen -and (Test-Path -LiteralPath $report.RawPath -PathType Leaf)) {
        Start-Process -FilePath $report.RawPath
    }

    $message = "Processing completed successfully.`r`n`r`nRaw events: $($report.RawCount)`r`nRaw CSV:`r`n$($report.RawPath)"
    if ($CollapseEvents) {
        $message += "`r`n`r`nCollapsed records: $($report.CollapsedCount)`r`nCollapsed CSV:`r`n$($report.CollapsedPath)"
    }
    Show-InfoBox -Message $message -Title 'Success'
}
#endregion Main processing

#region GUI
function New-FolderPicker {
    [CmdletBinding()]
    param([string]$Description)

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    return $dialog
}

function Initialize-Gui {
    [CmdletBinding()]
    param()

    Initialize-WinFormsRuntime

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'System Restart Event Auditor - Production Baseline'
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $true
    $form.ClientSize = New-Object System.Drawing.Size(820, 450)
    $script:Form = $form

    $left = 16
    $top = 18
    $labelWidth = 170
    $textWidth = 500
    $buttonWidth = 96
    $buttonGap = 10
    $rowHeight = 38
    $buttonX = $left + $labelWidth + $textWidth + $buttonGap
    $currentY = $top

    $checkUseLive = New-Object System.Windows.Forms.CheckBox
    $checkUseLive.Location = New-Object System.Drawing.Point($left, $currentY)
    $checkUseLive.Size = New-Object System.Drawing.Size(260, 24)
    $checkUseLive.Text = 'Use live System log'
    $checkUseLive.Checked = $true
    $form.Controls.Add($checkUseLive)

    $checkCollapse = New-Object System.Windows.Forms.CheckBox
    $checkCollapse.Location = New-Object System.Drawing.Point(300, $currentY)
    $checkCollapse.Size = New-Object System.Drawing.Size(260, 24)
    $checkCollapse.Text = 'Generate collapsed summary'
    $checkCollapse.Checked = $true
    $form.Controls.Add($checkCollapse)

    $currentY += $rowHeight

    $labelEvtx = New-Object System.Windows.Forms.Label
    $labelEvtx.Location = New-Object System.Drawing.Point($left, ($currentY + 4))
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

    $buttonResolveChannel = New-Object System.Windows.Forms.Button
    $buttonResolveChannel.Location = New-Object System.Drawing.Point(($buttonX - 120), ($currentY + 28))
    $buttonResolveChannel.Size = New-Object System.Drawing.Size(216, 24)
    $buttonResolveChannel.Text = 'Resolve Channel'
    $form.Controls.Add($buttonResolveChannel)

    $currentY += ($rowHeight + 24)

    $checkIncludeSubfolders = New-Object System.Windows.Forms.CheckBox
    $checkIncludeSubfolders.Location = New-Object System.Drawing.Point($left, $currentY)
    $checkIncludeSubfolders.Size = New-Object System.Drawing.Size(260, 24)
    $checkIncludeSubfolders.Text = 'Include subfolders'
    $checkIncludeSubfolders.Checked = $true
    $checkIncludeSubfolders.Enabled = $false
    $form.Controls.Add($checkIncludeSubfolders)

    $labelCollapseWindow = New-Object System.Windows.Forms.Label
    $labelCollapseWindow.Location = New-Object System.Drawing.Point(300, ($currentY + 4))
    $labelCollapseWindow.Size = New-Object System.Drawing.Size(170, 20)
    $labelCollapseWindow.Text = 'Collapse window (min):'
    $form.Controls.Add($labelCollapseWindow)

    $numericCollapseWindow = New-Object System.Windows.Forms.NumericUpDown
    $numericCollapseWindow.Location = New-Object System.Drawing.Point(475, $currentY)
    $numericCollapseWindow.Size = New-Object System.Drawing.Size(70, 24)
    $numericCollapseWindow.Minimum = 1
    $numericCollapseWindow.Maximum = 60
    $numericCollapseWindow.Value = [Math]::Max(1, [Math]::Min(60, $CollapseWindowMinutes))
    $form.Controls.Add($numericCollapseWindow)

    $currentY += $rowHeight

    $labelOutput = New-Object System.Windows.Forms.Label
    $labelOutput.Location = New-Object System.Drawing.Point($left, ($currentY + 4))
    $labelOutput.Size = New-Object System.Drawing.Size($labelWidth, 20)
    $labelOutput.Text = 'CSV output folder:'
    $form.Controls.Add($labelOutput)

    $textOutput = New-Object System.Windows.Forms.TextBox
    $textOutput.Location = New-Object System.Drawing.Point(($left + $labelWidth), $currentY)
    $textOutput.Size = New-Object System.Drawing.Size($textWidth, 24)
    $textOutput.Text = $script:DefaultOutputFolder
    $form.Controls.Add($textOutput)

    $buttonBrowseOutput = New-Object System.Windows.Forms.Button
    $buttonBrowseOutput.Location = New-Object System.Drawing.Point($buttonX, $currentY)
    $buttonBrowseOutput.Size = New-Object System.Drawing.Size($buttonWidth, 24)
    $buttonBrowseOutput.Text = 'Browse'
    $form.Controls.Add($buttonBrowseOutput)

    $currentY += $rowHeight

    $labelLog = New-Object System.Windows.Forms.Label
    $labelLog.Location = New-Object System.Drawing.Point($left, ($currentY + 4))
    $labelLog.Size = New-Object System.Drawing.Size($labelWidth, 20)
    $labelLog.Text = 'Log folder:'
    $form.Controls.Add($labelLog)

    $textLog = New-Object System.Windows.Forms.TextBox
    $textLog.Location = New-Object System.Drawing.Point(($left + $labelWidth), $currentY)
    $textLog.Size = New-Object System.Drawing.Size($textWidth, 24)
    $textLog.Text = $script:LogDir
    $form.Controls.Add($textLog)

    $buttonBrowseLog = New-Object System.Windows.Forms.Button
    $buttonBrowseLog.Location = New-Object System.Drawing.Point($buttonX, $currentY)
    $buttonBrowseLog.Size = New-Object System.Drawing.Size($buttonWidth, 24)
    $buttonBrowseLog.Text = 'Browse'
    $form.Controls.Add($buttonBrowseLog)

    $currentY += $rowHeight + 8

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point($left, $currentY)
    $progressBar.Size = New-Object System.Drawing.Size(780, 22)
    $progressBar.Minimum = 0
    $progressBar.Maximum = 100
    $form.Controls.Add($progressBar)
    $script:ProgressBar = $progressBar

    $currentY += 30

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Location = New-Object System.Drawing.Point($left, $currentY)
    $statusLabel.Size = New-Object System.Drawing.Size(780, 54)
    $statusLabel.Text = 'Ready.'
    $form.Controls.Add($statusLabel)
    $script:StatusLabel = $statusLabel

    $buttonOpenOutput = New-Object System.Windows.Forms.Button
    $buttonOpenOutput.Size = New-Object System.Drawing.Size(150, 30)
    $buttonOpenOutput.Location = New-Object System.Drawing.Point(300, 396)
    $buttonOpenOutput.Text = 'Open Output Folder'
    $form.Controls.Add($buttonOpenOutput)

    $buttonStart = New-Object System.Windows.Forms.Button
    $buttonStart.Size = New-Object System.Drawing.Size(150, 30)
    $buttonStart.Location = New-Object System.Drawing.Point(470, 396)
    $buttonStart.Text = 'Start Analysis'
    $form.Controls.Add($buttonStart)

    $buttonClose = New-Object System.Windows.Forms.Button
    $buttonClose.Size = New-Object System.Drawing.Size(120, 30)
    $buttonClose.Location = New-Object System.Drawing.Point(640, 396)
    $buttonClose.Text = 'Close'
    $form.Controls.Add($buttonClose)

    # Keep GUI state handlers local to this initialized form. Do not route button actions
    # through script-scoped scriptblocks; under Set-StrictMode and WinForms closures this can
    # become null/stale across event callbacks in Windows PowerShell 5.1 hosts.
    $toggleInputs = {
        $isLive = [bool]$checkUseLive.Checked
        $archiveEnabled = (-not $isLive) -and (-not $script:RunInProgress)
        $textEvtx.Enabled = $archiveEnabled
        $buttonBrowseEvtx.Enabled = $archiveEnabled
        $checkIncludeSubfolders.Enabled = $archiveEnabled
    }.GetNewClosure()

    $setBusyState = {
        param([bool]$Busy)

        $script:RunInProgress = $Busy
        $form.UseWaitCursor = $Busy
        $buttonStart.Enabled = (-not $Busy)
        $buttonClose.Enabled = (-not $Busy)
        $buttonBrowseOutput.Enabled = (-not $Busy)
        $buttonBrowseLog.Enabled = (-not $Busy)
        $buttonOpenOutput.Enabled = (-not $Busy)
        $buttonResolveChannel.Enabled = (-not $Busy)
        $checkUseLive.Enabled = (-not $Busy)
        $checkCollapse.Enabled = (-not $Busy)
        $numericCollapseWindow.Enabled = (-not $Busy)
        [void]$toggleInputs.Invoke()
    }.GetNewClosure()

    [void]$toggleInputs.Invoke()

    $checkUseLive.Add_CheckedChanged({ Invoke-GuiSafe -ErrorPrefix 'Live/archive mode toggle failed' -Action $toggleInputs }.GetNewClosure())

    $buttonBrowseEvtx.Add_Click({
        Invoke-GuiSafe -ErrorPrefix 'Browse EVTX folder failed' -Action {
            $dialog = New-FolderPicker -Description 'Select the folder containing archived EVTX files'
            try {
                if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $textEvtx.Text = $dialog.SelectedPath
                }
            }
            finally { $dialog.Dispose() }
        }
    }.GetNewClosure())

    $buttonResolveChannel.Add_Click({
        Invoke-GuiSafe -ErrorPrefix 'Resolve Channel failed' -Action {
            Update-ProgressSafe -Value 15 -StatusText 'Resolving System channel...'
            $resolvedFolder = Resolve-SystemEvtxFolder
            if (-not [string]::IsNullOrWhiteSpace($resolvedFolder)) {
                $textEvtx.Text = $resolvedFolder
                Write-Log ("System channel EVTX folder resolved: {0}" -f $resolvedFolder)
            }

            $snapshot = $null
            try {
                $snapshot = Resolve-SystemChannel
                Write-Log ("Live System channel snapshot export test completed: {0}" -f $snapshot)

                $message = if (-not [string]::IsNullOrWhiteSpace($resolvedFolder)) {
                    "System channel resolved successfully.`r`n`r`nEVTX folder:`r`n$resolvedFolder`r`n`r`nSnapshot export test succeeded."
                }
                else {
                    'System channel snapshot export succeeded, but the configured EVTX folder could not be resolved from registry.'
                }
                Show-InfoBox -Message $message -Title 'Resolve Channel'
            }
            finally {
                if ($snapshot -and (Test-Path -LiteralPath $snapshot -PathType Leaf)) {
                    Remove-Item -LiteralPath $snapshot -Force -ErrorAction SilentlyContinue
                }
                Update-ProgressSafe -Value 0 -StatusText 'Ready.'
            }
        }
    }.GetNewClosure())

    $buttonBrowseOutput.Add_Click({
        Invoke-GuiSafe -ErrorPrefix 'Browse output folder failed' -Action {
            $dialog = New-FolderPicker -Description 'Select the folder where CSV reports will be saved'
            try {
                if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $textOutput.Text = $dialog.SelectedPath
                }
            }
            finally { $dialog.Dispose() }
        }
    }.GetNewClosure())

    $buttonBrowseLog.Add_Click({
        Invoke-GuiSafe -ErrorPrefix 'Browse log folder failed' -Action {
            $dialog = New-FolderPicker -Description 'Select the log folder'
            try {
                if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $textLog.Text = $dialog.SelectedPath
                    $script:LogDir = $dialog.SelectedPath
                    Initialize-LogDirectory
                    Write-Log ("Log directory changed from GUI: {0}" -f $script:LogDir)
                }
            }
            finally { $dialog.Dispose() }
        }
    }.GetNewClosure())

    $buttonOpenOutput.Add_Click({
        Invoke-GuiSafe -ErrorPrefix 'Open output folder failed' -Action {
            $folder = Resolve-OutputFolder -Candidate $textOutput.Text
            Start-Process -FilePath $folder
        }
    }.GetNewClosure())

    $buttonStart.Add_Click({
        Invoke-GuiSafe -ErrorPrefix 'Start analysis failed' -Action {
            if ($script:RunInProgress) { return }
            [void]$setBusyState.Invoke($true)

            try {
                $script:LogDir = $textLog.Text
                Initialize-LogDirectory
                Write-Log 'GUI execution started.'

                if ((-not $checkUseLive.Checked) -and [string]::IsNullOrWhiteSpace($textEvtx.Text)) {
                    throw 'Select an EVTX folder or enable live System log mode.'
                }

                $script:CollapseWindowMinutes = [int]$numericCollapseWindow.Value

                Process-SystemRestartEvents `
                    -UseLiveLog:$checkUseLive.Checked `
                    -EvtxFolder $textEvtx.Text `
                    -IncludeSubfolders:$checkIncludeSubfolders.Checked `
                    -OutputFolder $textOutput.Text `
                    -CollapseEvents:$checkCollapse.Checked
            }
            catch {
                Write-Log -Level 'ERROR' -Message $_.Exception.Message
                Update-ProgressSafe -Value 0 -StatusText 'Error occurred. Check the log file for details.'
                Show-ErrorBox -Message $_.Exception.Message
            }
            finally {
                [void]$setBusyState.Invoke($false)
                Write-Log 'GUI execution finished.'
            }
        }
    }.GetNewClosure())

    $buttonClose.Add_Click({
        Invoke-GuiSafe -ErrorPrefix 'Close action failed' -Action {
            if (-not $script:RunInProgress) { $form.Close() }
        }
    }.GetNewClosure())

    $form.Add_Shown({
        Invoke-GuiSafe -ErrorPrefix 'GUI shown initialization failed' -Action {
            $initialResolvedFolder = Resolve-SystemEvtxFolder
            if (-not [string]::IsNullOrWhiteSpace($initialResolvedFolder)) {
                $textEvtx.Text = $initialResolvedFolder
                Write-Log ("Initial System channel EVTX folder resolved: {0}" -f $initialResolvedFolder)
            }
            Update-ProgressSafe -Value 0 -StatusText 'Ready.'
            Write-Log 'GUI initialized successfully.'
        }
    }.GetNewClosure())

    return $form
}
#endregion GUI

#region Entrypoint
try {
    if (-not (Test-IsWindowsHost)) {
        throw 'This tool must be executed on Windows because it depends on WinForms and Windows Event Log APIs.'
    }

    Initialize-ConsoleVisibility -Visible:$ShowConsole
    Start-LogSession
    Initialize-WinFormsRuntime

    $mainForm = Initialize-Gui
    [void]$mainForm.ShowDialog()

    Write-Log '========== END: System Restart Event Auditor =========='
}
catch {
    try { Write-Log -Level 'ERROR' -Message $_.Exception.Message } catch {}
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        Show-ErrorBox -Message $_.Exception.Message -Title 'Fatal Error'
    }
    catch {
        Write-Error $_.Exception.Message
    }
    exit 1
}
#endregion Entrypoint

# End of script
