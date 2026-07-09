<#
.SYNOPSIS
  Interactive PowerShell Script Caller - searchable, sortable and folder-grouped .ps1 launcher.

.DESCRIPTION
  Compact Windows Forms GUI tool for interactively calling PowerShell scripts from a repository folder.

  Implements:
  - Hidden PowerShell console by default, with optional -ShowConsole switch
  - Safe STA relaunch using hidden window style
  - Automatic repository scan for .ps1 files below the launcher root
  - Main ListView separated by folder using native ListView groups
  - Folder name appears only once as the group header, not repeated in each script row
  - Clickable column headers with ascending/descending ordering
  - Search filter across script name, folder, path and synopsis
  - Double-click execution and explicit Run / Run as Administrator buttons
  - External PowerShell process execution with captured output for non-elevated runs
  - Runtime output panel and daily structured logs under Logs
  - Stop button for the currently running child process
  - Details panel for selected script metadata
  - No ComboBox dependency, eliminating SelectedItem/SelectedIndex type mismatch errors
  - Native PowerShell array-based repository index to avoid Generic.List assignment/conversion failures
  - Folder sorting rewritten without Generic.List return conversion

.AUTHOR
  Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
  2026-07-09-v3.1.9-ENTERPRISE-STABLE-LAUNCHER
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RootPath,

    [Parameter(Mandatory = $false)]
    [string]$LogDirectory,

    [Parameter(Mandatory = $false)]
    [switch]$ShowConsole,

    [Parameter(Mandatory = $false)]
    [switch]$NoExecutionPolicyBypass,

    [Parameter(Mandatory = $false)]
    [switch]$NoSTAReLaunch,

    [Parameter(Mandatory = $false)]
    [switch]$UsePwsh
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

#region Bootstrap

function Get-LauncherScriptPath {
    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) { return $PSCommandPath }
    if ($MyInvocation -and $MyInvocation.MyCommand -and -not [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path)) { return $MyInvocation.MyCommand.Path }
    return $null
}

function Get-LauncherBasePath {
    param([string]$CandidateRootPath)

    if (-not [string]::IsNullOrWhiteSpace($CandidateRootPath)) {
        return (Resolve-Path -LiteralPath $CandidateRootPath -ErrorAction Stop).Path
    }

    $scriptPath = Get-LauncherScriptPath
    if (-not [string]::IsNullOrWhiteSpace($scriptPath)) {
        return (Split-Path -Parent $scriptPath)
    }

    return (Get-Location).Path
}

function Get-PowerShellHostPath {
    param([switch]$PreferPwsh)

    if ($PreferPwsh) {
        $cmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }

    $cmd = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $cmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    throw 'Neither powershell.exe nor pwsh.exe was found.'
}

function Hide-ConsoleWindow {
    if ($ShowConsole) { return }

    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class LHConsoleWindowManager315 {
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public static void Hide() {
        IntPtr handle = GetConsoleWindow();
        if (handle != IntPtr.Zero) { ShowWindow(handle, 0); }
    }
}
"@ -ErrorAction SilentlyContinue
        [LHConsoleWindowManager315]::Hide()
    }
    catch { }
}


function ConvertTo-ProcessArgument {
    param([AllowEmptyString()][string]$Value)

    if ($null -eq $Value) { return '""' }
    if ($Value -notmatch '[\s"`]') { return $Value }

    # Windows command-line quoting compatible with powershell.exe/pwsh.exe child process calls.
    $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
    return '"{0}"' -f $escaped
}

function Restart-InSTAIfRequired {
    if ($NoSTAReLaunch) { return }
    if ([System.Threading.Thread]::CurrentThread.ApartmentState -eq [System.Threading.ApartmentState]::STA) { return }

    $scriptPath = Get-LauncherScriptPath
    if ([string]::IsNullOrWhiteSpace($scriptPath)) { return }

    $hostPath = Get-PowerShellHostPath -PreferPwsh:$UsePwsh
    $argList = New-Object System.Collections.ArrayList
    [void]$argList.Add('-NoProfile')
    [void]$argList.Add('-STA')
    if (-not $NoExecutionPolicyBypass) {
        [void]$argList.Add('-ExecutionPolicy')
        [void]$argList.Add('Bypass')
    }
    [void]$argList.Add('-File')
    [void]$argList.Add((ConvertTo-ProcessArgument -Value $scriptPath))

    if (-not [string]::IsNullOrWhiteSpace($RootPath)) {
        [void]$argList.Add('-RootPath')
        [void]$argList.Add((ConvertTo-ProcessArgument -Value $RootPath))
    }
    if (-not [string]::IsNullOrWhiteSpace($LogDirectory)) {
        [void]$argList.Add('-LogDirectory')
        [void]$argList.Add((ConvertTo-ProcessArgument -Value $LogDirectory))
    }
    if ($ShowConsole) { [void]$argList.Add('-ShowConsole') }
    if ($NoExecutionPolicyBypass) { [void]$argList.Add('-NoExecutionPolicyBypass') }
    if ($UsePwsh) { [void]$argList.Add('-UsePwsh') }
    [void]$argList.Add('-NoSTAReLaunch')

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $hostPath
    $psi.Arguments = ($argList -join ' ')
    $psi.UseShellExecute = $true
    $psi.WindowStyle = if ($ShowConsole) { [System.Diagnostics.ProcessWindowStyle]::Normal } else { [System.Diagnostics.ProcessWindowStyle]::Hidden }
    [void][System.Diagnostics.Process]::Start($psi)
    exit
}

Restart-InSTAIfRequired
Hide-ConsoleWindow

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException({
    param($sender, $eventArgs)
    try { Write-LauncherLog -Message ('Unhandled UI exception: {0}' -f $eventArgs.Exception.Message) -Level ERROR } catch { }
    try {
        [void][System.Windows.Forms.MessageBox]::Show(('Unhandled UI exception:{0}{1}' -f [Environment]::NewLine, $eventArgs.Exception.Message), 'Launcher UI Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    } catch { }
})
[AppDomain]::CurrentDomain.add_UnhandledException({
    param($sender, $eventArgs)
    try { Write-LauncherLog -Message ('Unhandled application exception: {0}' -f $eventArgs.ExceptionObject.ToString()) -Level ERROR } catch { }
})

$script:AppRoot = Get-LauncherBasePath -CandidateRootPath $RootPath
if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
    $script:LogRoot = Join-Path -Path $script:AppRoot -ChildPath 'Logs'
}
else {
    $script:LogRoot = $LogDirectory
}
if (-not (Test-Path -LiteralPath $script:LogRoot)) {
    [void](New-Item -Path $script:LogRoot -ItemType Directory -Force)
}

$script:LogFile = Join-Path -Path $script:LogRoot -ChildPath ('ScriptLauncher-{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))
$script:ScriptIndex = @()
$script:CurrentProcess = $null
$script:CurrentScript = $null
$script:Ui = @{}
$script:SearchTimer = $null
$script:ProcessTimer = $null
$script:SortKey = 'Name'
$script:SortDescending = $false
$script:SearchText = ''
$script:SuppressFatalDialog = $false
$script:Columns = @(
    [pscustomobject]@{ Header = 'Script';      Key = 'Name';          Width = 390 },
    [pscustomobject]@{ Header = 'Modified';    Key = 'LastWriteTime'; Width = 145 },
    [pscustomobject]@{ Header = 'KB';          Key = 'SizeKB';        Width = 80  },
    [pscustomobject]@{ Header = 'Admin';       Key = 'RequiresAdmin'; Width = 80  },
    [pscustomobject]@{ Header = 'Description'; Key = 'Synopsis';      Width = 610 }
)

#endregion Bootstrap

#region Utility

function Invoke-OnUI {
    param([scriptblock]$Action)

    try {
        if ($script:Ui.ContainsKey('Form') -and $script:Ui.Form -and $script:Ui.Form.InvokeRequired) {
            [void]$script:Ui.Form.BeginInvoke([System.Action]{ & $Action })
        }
        else {
            & $Action
        }
    }
    catch { }
}

function Write-LauncherLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS')][string]$Level = 'INFO'
    )

    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch { }

    Invoke-OnUI -Action {
        if ($script:Ui.ContainsKey('OutputBox') -and $script:Ui.OutputBox) {
            $script:Ui.OutputBox.AppendText($line + [Environment]::NewLine)
            $script:Ui.OutputBox.SelectionStart = $script:Ui.OutputBox.TextLength
            $script:Ui.OutputBox.ScrollToCaret()
        }
    }
}

function Set-Status {
    param([string]$Text)
    Invoke-OnUI -Action {
        if ($script:Ui.ContainsKey('StatusLabel') -and $script:Ui.StatusLabel) {
            $script:Ui.StatusLabel.Text = $Text
        }
    }
}

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function Get-RelativePathSafe {
    param([string]$BasePath, [string]$FullPath)

    try {
        $baseUri = New-Object System.Uri(($BasePath.TrimEnd('\') + '\'))
        $fullUri = New-Object System.Uri($FullPath)
        return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($fullUri).ToString()).Replace('/', '\')
    }
    catch { return $FullPath }
}

function Get-ScriptSynopsis {
    param([string]$Path)

    try {
        $content = Get-Content -LiteralPath $Path -TotalCount 90 -ErrorAction Stop
        for ($i = 0; $i -lt $content.Count; $i++) {
            if ($content[$i] -match '^\s*\.SYNOPSIS\s*$') {
                for ($j = $i + 1; $j -lt $content.Count; $j++) {
                    $line = $content[$j].Trim()
                    if ($line -and $line -notmatch '^\.') { return $line }
                    if ($line -match '^\.DESCRIPTION') { break }
                }
            }
        }
        return 'No synopsis found.'
    }
    catch { return 'Unable to read script header.' }
}

function Get-ScriptRequiresAdminHint {
    param([string]$Path)

    try {
        $content = Get-Content -LiteralPath $Path -TotalCount 120 -ErrorAction Stop | Out-String
        if ($content -match '(?im)^\s*#requires\s+-RunAsAdministrator') { return $true }
        if ($content -match '(?im)^\s*\.RequiresAdmin\s*$') { return $true }
        if ($content -match '(?im)RequiresAdmin\s*[:=]\s*(True|Yes|1)') { return $true }
        return $false
    }
    catch { return $false }
}

function New-ScriptItem {
    param([System.IO.FileInfo]$File)

    $relative = Get-RelativePathSafe -BasePath $script:AppRoot -FullPath $File.FullName
    $folder = Split-Path -Parent $relative
    if ([string]::IsNullOrWhiteSpace($folder)) { $folder = 'Root' }

    [pscustomobject]@{
        Name          = $File.Name
        BaseName      = $File.BaseName
        FullName      = $File.FullName
        RelativePath  = $relative
        Folder        = $folder
        LastWriteTime = $File.LastWriteTime
        SizeKB        = [math]::Round(($File.Length / 1KB), 2)
        RequiresAdmin = Get-ScriptRequiresAdminHint -Path $File.FullName
        Synopsis      = Get-ScriptSynopsis -Path $File.FullName
    }
}

function Refresh-ScriptIndex {
    $script:ScriptIndex = @()
    Write-LauncherLog -Message ('Scanning repository: {0}' -f $script:AppRoot) -Level INFO

    $launcherPath = Get-LauncherScriptPath
    $logRootResolved = try { (Resolve-Path -LiteralPath $script:LogRoot -ErrorAction Stop).Path } catch { $script:LogRoot }
    $logPrefix = $logRootResolved.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

    $files = @(Get-ChildItem -LiteralPath $script:AppRoot -Filter '*.ps1' -File -Recurse -ErrorAction Stop |
        Where-Object {
            (-not $_.FullName.StartsWith($logPrefix, [System.StringComparison]::OrdinalIgnoreCase)) -and
            ([string]::IsNullOrWhiteSpace($launcherPath) -or -not $_.FullName.Equals($launcherPath, [System.StringComparison]::OrdinalIgnoreCase))
        } |
        Sort-Object DirectoryName, Name)

    $index = New-Object System.Collections.ArrayList
    foreach ($file in $files) {
        [void]$index.Add((New-ScriptItem -File $file))
    }

    # Store as a plain PowerShell object array. This avoids Generic.List enumeration/conversion
    # issues in Windows PowerShell 5.1 WinForms event scopes.
    $script:ScriptIndex = @($index.ToArray())

    Write-LauncherLog -Message ('Loaded {0} script(s).' -f $script:ScriptIndex.Count) -Level SUCCESS
}

function Get-FilteredScripts {
    $source = @()
    if ($null -ne $script:ScriptIndex) {
        $source = @($script:ScriptIndex)
    }

    $text = [string]$script:SearchText
    if ([string]::IsNullOrWhiteSpace($text)) {
        return @($source)
    }

    $terms = @($text.Trim().ToLowerInvariant().Split([char]' ', [System.StringSplitOptions]::RemoveEmptyEntries))
    $result = New-Object System.Collections.ArrayList

    foreach ($scriptItem in $source) {
        if ($null -eq $scriptItem) { continue }

        $name     = ([string]$scriptItem.Name).ToLowerInvariant()
        $folder   = ([string]$scriptItem.Folder).ToLowerInvariant()
        $relPath  = ([string]$scriptItem.RelativePath).ToLowerInvariant()
        $synopsis = ([string]$scriptItem.Synopsis).ToLowerInvariant()

        $matchedAllTerms = $true
        foreach ($term in $terms) {
            if (-not ($name.Contains($term) -or $folder.Contains($term) -or $relPath.Contains($term) -or $synopsis.Contains($term))) {
                $matchedAllTerms = $false
                break
            }
        }

        if ($matchedAllTerms) {
            [void]$result.Add($scriptItem)
        }
    }

    return @($result.ToArray())
}

function ConvertTo-ScriptItemArray {
    param([object]$Items)

    $normalized = New-Object System.Collections.ArrayList

    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }

        # Defensive flattening: earlier builds could accidentally pass a nested Object[]
        # when a single search result was wrapped with a unary comma.
        if (($item -is [System.Array]) -and -not ($item -is [string])) {
            foreach ($child in $item) {
                if ($null -eq $child) { continue }
                if ($child.PSObject.Properties.Match('Folder').Count -gt 0) {
                    [void]$normalized.Add($child)
                }
            }
            continue
        }

        if ($item.PSObject.Properties.Match('Folder').Count -gt 0) {
            [void]$normalized.Add($item)
        }
    }

    return @($normalized.ToArray())
}

function Get-ItemFolderValue {
    param([object]$Item)

    if ($null -eq $Item) { return '_Root' }
    if ($Item.PSObject.Properties.Match('Folder').Count -eq 0) { return '_Root' }

    $value = [string]$Item.Folder
    if ([string]::IsNullOrWhiteSpace($value)) { return '_Root' }
    return $value
}

function Sort-ScriptsWithinFolders {
    param([object[]]$Items)

    $safeItems = @(ConvertTo-ScriptItemArray -Items $Items)
    $ordered = New-Object System.Collections.ArrayList
    $folders = @($safeItems | ForEach-Object { Get-ItemFolderValue -Item $_ } | Sort-Object -Unique)

    foreach ($folder in $folders) {
        $folderItems = @($safeItems | Where-Object { (Get-ItemFolderValue -Item $_) -eq $folder })

        switch ($script:SortKey) {
            'LastWriteTime' { $folderItems = @($folderItems | Sort-Object -Property LastWriteTime, Name -Descending:$script:SortDescending) }
            'SizeKB'        { $folderItems = @($folderItems | Sort-Object -Property SizeKB, Name -Descending:$script:SortDescending) }
            'RequiresAdmin' { $folderItems = @($folderItems | Sort-Object -Property RequiresAdmin, Name -Descending:$script:SortDescending) }
            'Synopsis'      { $folderItems = @($folderItems | Sort-Object -Property Synopsis, Name -Descending:$script:SortDescending) }
            default         { $folderItems = @($folderItems | Sort-Object -Property Name -Descending:$script:SortDescending) }
        }

        foreach ($item in $folderItems) { [void]$ordered.Add($item) }
    }

    return @($ordered.ToArray())
}

#endregion Utility

#region UI Update

function Update-ColumnHeaders {
    $list = $script:Ui.ScriptList
    if (-not $list) { return }

    for ($i = 0; $i -lt $script:Columns.Count; $i++) {
        $header = $script:Columns[$i].Header
        if ($script:Columns[$i].Key -eq $script:SortKey) {
            if ($script:SortDescending) { $header = '{0} ▼' -f $header } else { $header = '{0} ▲' -f $header }
        }
        $list.Columns[$i].Text = $header
    }
}

function Update-ScriptList {
    $list = $script:Ui.ScriptList
    if (-not $list) { return }

    # CRITICAL: PowerShell unwraps single-item arrays returned from functions.
    # Force array context here or a one-result search causes: property 'Count' not found.
    $filtered = @(Get-FilteredScripts)
    $sorted = @(Sort-ScriptsWithinFolders -Items $filtered)

    $list.BeginUpdate()
    try {
        $list.Items.Clear()
        $list.Groups.Clear()

        $groupMap = @{}
        $filtered = @(ConvertTo-ScriptItemArray -Items $filtered)
        $folders = @($filtered | ForEach-Object { Get-ItemFolderValue -Item $_ } | Sort-Object -Unique)
        foreach ($folder in $folders) {
            $count = @($filtered | Where-Object { (Get-ItemFolderValue -Item $_) -eq $folder }).Count
            $suffix = if ($count -eq 1) { 'script' } else { 'scripts' }
            $title = '{0}  ({1} {2})' -f $folder, $count, $suffix
            $group = New-Object System.Windows.Forms.ListViewGroup
            $group.Header = $title
            $group.HeaderAlignment = [System.Windows.Forms.HorizontalAlignment]::Left
            [void]$list.Groups.Add($group)
            $groupMap[$folder] = $group
        }

        foreach ($scriptItem in $sorted) {
            $row = New-Object System.Windows.Forms.ListViewItem
            $row.Text = [string]$scriptItem.Name
            [void]$row.SubItems.Add($scriptItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
            [void]$row.SubItems.Add(('{0:N2}' -f $scriptItem.SizeKB))
            [void]$row.SubItems.Add($(if ($scriptItem.RequiresAdmin) { 'Yes' } else { 'No' }))
            [void]$row.SubItems.Add([string]$scriptItem.Synopsis)
            $row.Tag = $scriptItem

            $scriptFolder = Get-ItemFolderValue -Item $scriptItem
            if ($groupMap.ContainsKey($scriptFolder)) {
                $row.Group = $groupMap[$scriptFolder]
            }
            if ($scriptItem.RequiresAdmin) {
                $row.Font = New-Object System.Drawing.Font($list.Font, [System.Drawing.FontStyle]::Bold)
            }
            [void]$list.Items.Add($row)
        }

        Update-ColumnHeaders
    }
    finally {
        $list.EndUpdate()
    }

    Set-Status -Text ('Ready | {0} displayed | {1} indexed | Sorted by {2} {3} | Root: {4}' -f $filtered.Count, $script:ScriptIndex.Count, $script:SortKey, $(if ($script:SortDescending) { 'DESC' } else { 'ASC' }), $script:AppRoot)
}

function Set-SortColumn {
    param([int]$ColumnIndex)

    if ($ColumnIndex -lt 0 -or $ColumnIndex -ge $script:Columns.Count) { return }

    $key = [string]$script:Columns[$ColumnIndex].Key
    if ($script:SortKey -eq $key) {
        $script:SortDescending = -not $script:SortDescending
    }
    else {
        $script:SortKey = $key
        $script:SortDescending = $false
    }
    Update-ScriptList
}

function Get-SelectedScriptItem {
    $list = $script:Ui.ScriptList
    if (-not $list -or $list.SelectedItems.Count -eq 0) { return $null }
    return $list.SelectedItems[0].Tag
}

function Update-DetailsPanel {
    param($ScriptItem)

    if (-not $script:Ui.ContainsKey('DetailsBox')) { return }

    if ($null -eq $ScriptItem) {
        $script:Ui.DetailsBox.Text = 'Select a script to view details.'
        return
    }

    $details = @(
        ('Name          : {0}' -f $ScriptItem.Name),
        ('Folder        : {0}' -f $ScriptItem.Folder),
        ('Relative Path : {0}' -f $ScriptItem.RelativePath),
        ('Full Path     : {0}' -f $ScriptItem.FullName),
        ('Last Modified : {0}' -f $ScriptItem.LastWriteTime),
        ('Size          : {0:N2} KB' -f $ScriptItem.SizeKB),
        ('Requires Admin: {0}' -f $ScriptItem.RequiresAdmin),
        '',
        'Synopsis:',
        $ScriptItem.Synopsis
    )
    $script:Ui.DetailsBox.Text = ($details -join [Environment]::NewLine)
}

function Set-ExecutionUiState {
    param([bool]$IsRunning)

    Invoke-OnUI -Action {
        $script:Ui.RunButton.Enabled = -not $IsRunning
        $script:Ui.RunAdminButton.Enabled = -not $IsRunning
        $script:Ui.RefreshButton.Enabled = -not $IsRunning
        $script:Ui.SearchBox.Enabled = -not $IsRunning
        $script:Ui.ScriptList.Enabled = -not $IsRunning
        $script:Ui.StopButton.Enabled = $IsRunning
    }
}

#endregion UI Update

#region Execution

function Start-SelectedScript {
    param([switch]$AsAdministrator)

    $scriptItem = Get-SelectedScriptItem
    if ($null -eq $scriptItem) {
        [void][System.Windows.Forms.MessageBox]::Show('Select one script first.', 'No Script Selected', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }

    if (-not (Test-Path -LiteralPath $scriptItem.FullName -PathType Leaf)) {
        [void][System.Windows.Forms.MessageBox]::Show('Script file was not found.', 'File Missing', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }

    $adminText = if ($AsAdministrator) { ' as Administrator' } else { '' }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        ('Run this script{0}?{1}{1}{2}' -f $adminText, [Environment]::NewLine, $scriptItem.FullName),
        'Confirm Script Execution',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $hostPath = Get-PowerShellHostPath -PreferPwsh:$UsePwsh
    $argList = New-Object System.Collections.ArrayList
    [void]$argList.Add('-NoProfile')
    if (-not $NoExecutionPolicyBypass) {
        [void]$argList.Add('-ExecutionPolicy')
        [void]$argList.Add('Bypass')
    }
    [void]$argList.Add('-File')
    [void]$argList.Add((ConvertTo-ProcessArgument -Value $scriptItem.FullName))

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $hostPath
        $psi.Arguments = ($argList -join ' ')

        $script:CurrentScript = $scriptItem
        Write-LauncherLog -Message ('Starting script: {0}' -f $scriptItem.FullName) -Level INFO

        if ($AsAdministrator) {
            $psi.UseShellExecute = $true
            $psi.Verb = 'runas'
            $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal
            $script:CurrentProcess = [System.Diagnostics.Process]::Start($psi)
            Write-LauncherLog -Message 'Elevated process started. Output capture is not available for elevated execution.' -Level WARN
            Set-ExecutionUiState -IsRunning $true
            Set-Status -Text ('Elevated process running: {0}' -f $scriptItem.Name)
            if ($script:CurrentProcess) { $script:ProcessTimer.Start() }
            return
        }

        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        $proc.EnableRaisingEvents = $true
        $proc.add_OutputDataReceived({
            param($sender, $eventArgs)
            if ($eventArgs -and $null -ne $eventArgs.Data) {
                Write-LauncherLog -Message ('OUT | {0}' -f $eventArgs.Data) -Level INFO
            }
        })
        $proc.add_ErrorDataReceived({
            param($sender, $eventArgs)
            if ($eventArgs -and $null -ne $eventArgs.Data) {
                Write-LauncherLog -Message ('ERR | {0}' -f $eventArgs.Data) -Level ERROR
            }
        })

        [void]$proc.Start()
        $proc.BeginOutputReadLine()
        $proc.BeginErrorReadLine()
        $script:CurrentProcess = $proc

        Set-ExecutionUiState -IsRunning $true
        Set-Status -Text ('Running: {0}' -f $scriptItem.Name)
        $script:ProcessTimer.Start()
    }
    catch {
        Write-LauncherLog -Message ('Failed to start script: {0}' -f $_.Exception.Message) -Level ERROR
        [void][System.Windows.Forms.MessageBox]::Show(('Failed to start script:{0}{1}' -f [Environment]::NewLine, $_.Exception.Message), 'Execution Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        Set-ExecutionUiState -IsRunning $false
        $script:CurrentProcess = $null
        $script:CurrentScript = $null
    }
}

function Stop-CurrentScript {
    if ($null -eq $script:CurrentProcess) { return }
    try {
        if (-not $script:CurrentProcess.HasExited) {
            $answer = [System.Windows.Forms.MessageBox]::Show('Stop the running script process?', 'Confirm Stop', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
            $script:CurrentProcess.Kill()
            Write-LauncherLog -Message ('Stopped script: {0}' -f $script:CurrentScript.FullName) -Level WARN
        }
    }
    catch {
        Write-LauncherLog -Message ('Failed to stop process: {0}' -f $_.Exception.Message) -Level ERROR
    }
}

function Watch-CurrentProcess {
    if ($null -eq $script:CurrentProcess) { return }

    try {
        if ($script:CurrentProcess.HasExited) {
            $exitCode = $script:CurrentProcess.ExitCode
            $name = if ($script:CurrentScript) { $script:CurrentScript.Name } else { 'Unknown' }
            if ($script:ProcessTimer) { $script:ProcessTimer.Stop() }

            if ($exitCode -eq 0) {
                Write-LauncherLog -Message ('Completed script successfully: {0}' -f $name) -Level SUCCESS
            }
            else {
                Write-LauncherLog -Message ('Script finished with exit code {0}: {1}' -f $exitCode, $name) -Level ERROR
            }

            Set-ExecutionUiState -IsRunning $false
            Set-Status -Text ('Finished: {0} | ExitCode: {1}' -f $name, $exitCode)
            $script:CurrentProcess.Dispose()
            $script:CurrentProcess = $null
            $script:CurrentScript = $null
        }
    }
    catch {
        Write-LauncherLog -Message ('Process monitor error: {0}' -f $_.Exception.Message) -Level ERROR
        try { if ($script:ProcessTimer) { $script:ProcessTimer.Stop() } } catch { }
        Set-ExecutionUiState -IsRunning $false
        try { if ($script:CurrentProcess) { $script:CurrentProcess.Dispose() } } catch { }
        $script:CurrentProcess = $null
        $script:CurrentScript = $null
    }
}

#endregion Execution

#region GUI

function New-LauncherForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Enterprise Interactive .PS1 Caller'
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.Size = New-Object System.Drawing.Size(1240, 780)
    $form.MinimumSize = New-Object System.Drawing.Size(1000, 640)
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $main = New-Object System.Windows.Forms.TableLayoutPanel
    $main.Dock = [System.Windows.Forms.DockStyle]::Fill
    $main.ColumnCount = 1
    $main.RowCount = 4
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 52)))
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 58)))
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 42)))
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 24)))
    [void]$form.Controls.Add($main)

    $top = New-Object System.Windows.Forms.FlowLayoutPanel
    $top.Dock = [System.Windows.Forms.DockStyle]::Fill
    $top.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $top.WrapContents = $false
    $top.Padding = New-Object System.Windows.Forms.Padding(8, 9, 8, 6)
    [void]$main.Controls.Add($top, 0, 0)

    $searchLabel = New-Object System.Windows.Forms.Label
    $searchLabel.Text = 'Search:'
    $searchLabel.AutoSize = $true
    $searchLabel.Margin = New-Object System.Windows.Forms.Padding(0, 7, 6, 0)
    [void]$top.Controls.Add($searchLabel)

    $searchBox = New-Object System.Windows.Forms.TextBox
    $searchBox.Width = 470
    $searchBox.Margin = New-Object System.Windows.Forms.Padding(0, 4, 12, 0)
    [void]$top.Controls.Add($searchBox)

    $runButton = New-Object System.Windows.Forms.Button
    $runButton.Text = 'Run'
    $runButton.Width = 90
    $runButton.Height = 28
    $runButton.Margin = New-Object System.Windows.Forms.Padding(0, 2, 6, 0)
    [void]$top.Controls.Add($runButton)

    $runAdminButton = New-Object System.Windows.Forms.Button
    $runAdminButton.Text = 'Run as Admin'
    $runAdminButton.Width = 120
    $runAdminButton.Height = 28
    $runAdminButton.Margin = New-Object System.Windows.Forms.Padding(0, 2, 6, 0)
    [void]$top.Controls.Add($runAdminButton)

    $stopButton = New-Object System.Windows.Forms.Button
    $stopButton.Text = 'Stop'
    $stopButton.Width = 90
    $stopButton.Height = 28
    $stopButton.Enabled = $false
    $stopButton.Margin = New-Object System.Windows.Forms.Padding(0, 2, 6, 0)
    [void]$top.Controls.Add($stopButton)

    $refreshButton = New-Object System.Windows.Forms.Button
    $refreshButton.Text = 'Refresh'
    $refreshButton.Width = 90
    $refreshButton.Height = 28
    $refreshButton.Margin = New-Object System.Windows.Forms.Padding(0, 2, 6, 0)
    [void]$top.Controls.Add($refreshButton)

    $openLogsButton = New-Object System.Windows.Forms.Button
    $openLogsButton.Text = 'Open Logs'
    $openLogsButton.Width = 100
    $openLogsButton.Height = 28
    $openLogsButton.Margin = New-Object System.Windows.Forms.Padding(0, 2, 6, 0)
    [void]$top.Controls.Add($openLogsButton)

    $scriptList = New-Object System.Windows.Forms.ListView
    $scriptList.Dock = [System.Windows.Forms.DockStyle]::Fill
    $scriptList.View = [System.Windows.Forms.View]::Details
    $scriptList.FullRowSelect = $true
    $scriptList.GridLines = $true
    $scriptList.HideSelection = $false
    $scriptList.ShowGroups = $true
    $scriptList.MultiSelect = $false
    foreach ($column in $script:Columns) {
        [void]$scriptList.Columns.Add([string]$column.Header, [int]$column.Width)
    }
    [void]$main.Controls.Add($scriptList, 0, 1)

    $bottomSplit = New-Object System.Windows.Forms.SplitContainer
    $bottomSplit.Dock = [System.Windows.Forms.DockStyle]::Fill
    $bottomSplit.Orientation = [System.Windows.Forms.Orientation]::Horizontal
    $bottomSplit.SplitterDistance = 150
    [void]$main.Controls.Add($bottomSplit, 0, 2)

    $detailsBox = New-Object System.Windows.Forms.TextBox
    $detailsBox.Dock = [System.Windows.Forms.DockStyle]::Fill
    $detailsBox.Multiline = $true
    $detailsBox.ReadOnly = $true
    $detailsBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $detailsBox.Font = New-Object System.Drawing.Font('Consolas', 9)
    $detailsBox.Text = 'Select a script to view details.'
    [void]$bottomSplit.Panel1.Controls.Add($detailsBox)

    $outputBox = New-Object System.Windows.Forms.TextBox
    $outputBox.Dock = [System.Windows.Forms.DockStyle]::Fill
    $outputBox.Multiline = $true
    $outputBox.ReadOnly = $true
    $outputBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
    $outputBox.WordWrap = $false
    $outputBox.Font = New-Object System.Drawing.Font('Consolas', 9)
    [void]$bottomSplit.Panel2.Controls.Add($outputBox)

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
    $statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $statusLabel.BorderStyle = [System.Windows.Forms.BorderStyle]::Fixed3D
    $statusLabel.Text = 'Ready'
    [void]$main.Controls.Add($statusLabel, 0, 3)

    $script:Ui = @{
        Form           = $form
        SearchBox      = $searchBox
        ScriptList     = $scriptList
        DetailsBox     = $detailsBox
        OutputBox      = $outputBox
        StatusLabel    = $statusLabel
        RunButton      = $runButton
        RunAdminButton = $runAdminButton
        StopButton     = $stopButton
        RefreshButton  = $refreshButton
        OpenLogsButton = $openLogsButton
    }

    $script:SearchTimer = New-Object System.Windows.Forms.Timer
    $script:SearchTimer.Interval = 250
    $script:SearchTimer.Add_Tick({
        $script:SearchTimer.Stop()
        $script:SearchText = [string]$script:Ui.SearchBox.Text
        Update-ScriptList
    })

    $script:ProcessTimer = New-Object System.Windows.Forms.Timer
    $script:ProcessTimer.Interval = 400
    $script:ProcessTimer.Add_Tick({ Watch-CurrentProcess })

    $searchBox.Add_TextChanged({
        $script:SearchTimer.Stop()
        $script:SearchTimer.Start()
    })

    $scriptList.Add_ColumnClick({
        param($sender, $eventArgs)
        Set-SortColumn -ColumnIndex ([int]$eventArgs.Column)
    })

    $scriptList.Add_SelectedIndexChanged({
        Update-DetailsPanel -ScriptItem (Get-SelectedScriptItem)
    })

    $scriptList.Add_DoubleClick({ Start-SelectedScript })
    $runButton.Add_Click({ Start-SelectedScript })
    $runAdminButton.Add_Click({ Start-SelectedScript -AsAdministrator })
    $stopButton.Add_Click({ Stop-CurrentScript })
    $refreshButton.Add_Click({
        try {
            Refresh-ScriptIndex
            Update-ScriptList
        }
        catch {
            Write-LauncherLog -Message ('Refresh failed: {0}' -f $_.Exception.Message) -Level ERROR
        }
    })
    $openLogsButton.Add_Click({
        try { Start-Process explorer.exe -ArgumentList (ConvertTo-ProcessArgument -Value $script:LogRoot) } catch { }
    })

    $form.Add_FormClosing({
        param($sender, $eventArgs)
        if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
            $answer = [System.Windows.Forms.MessageBox]::Show('A script is still running. Close anyway and terminate it?', 'Script Running', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
                $eventArgs.Cancel = $true
                return
            }
            try { $script:CurrentProcess.Kill() } catch { }
        }
    })

    return $form
}

#endregion GUI

#region Main

try {
    $form = New-LauncherForm
    Refresh-ScriptIndex
    Update-ScriptList
    Write-LauncherLog -Message 'Interactive .ps1 caller started.' -Level SUCCESS
    [void]$form.ShowDialog()
}
catch {
    $message = $_.Exception.Message
    $details = $_ | Out-String
    try {
        Add-Content -LiteralPath $script:LogFile -Value ('[{0}] [ERROR] Fatal launcher error: {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $details) -Encoding UTF8
    }
    catch { }
    [void][System.Windows.Forms.MessageBox]::Show(('Fatal launcher error:{0}{1}{0}{0}Check the daily log for details:{0}{2}' -f [Environment]::NewLine, $message, $script:LogFile), 'Launcher Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}
finally {
    try { Write-LauncherLog -Message 'Interactive .ps1 caller closed.' -Level INFO } catch { }
}

#endregion Main

# End of script
