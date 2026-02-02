<#
.SYNOPSIS
    PowerShell GUI launcher to browse, search, and execute categorized .ps1 scripts from a root folder.

.DESCRIPTION
    This tool builds a tabbed WinForms interface where each tab represents a script category (folder).
    It supports debounced real-time search, multi-select execution, robust logging, and a fixed layout.

    Enterprise standards applied (Windows-SysAdmin-ProSuite style):
    - StrictMode enabled and predictable error behavior
    - Optional console hiding (-ShowConsole)
    - Single log file per run under C:\Logs-TEMP
    - MessageBox feedback for operators
    - Debounced search (prevents UI lag on large script sets)
    - Idempotent catalog generation (stable keys + stable ordering) for any folder structure
    - Exclude patterns for common noise trees (GUID folders, node_modules, bin/obj, src, etc.)
    - Optional flatten rules to collapse micro-folder structures into one category tab
    - Safe script execution with explicit PowerShell host selection (pwsh preferred, fallback to powershell.exe)
    - Root directory resolution is PS 5.1-safe and avoids $MyInvocation.MyCommand.Path null edge cases
    - Execute button always visible; enabled only when at least 1 script is checked

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    3.6 - 2026-02-02
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]${RootDirectory} = $null,

    [Parameter(Mandatory = $false)]
    [switch]${ShowConsole},

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10)]
    [int]${CategoryDepth} = 4,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'WindowsPowerShell', 'PowerShell7')]
    [string]${ExecutionHost} = 'Auto',

    [Parameter(Mandatory = $false)]
    [string[]]${ExcludeRelativePathRegex} = @(
        '\\\.git(\\|$)',
        '\\node_modules(\\|$)',
        '\\bin(\\|$)',
        '\\obj(\\|$)',
        '\\dist(\\|$)',
        '\\target(\\|$)',
        '\\\.venv(\\|$)',
        '\\venv(\\|$)',
        '\\__pycache__(\\|$)',
        '\\\.idea(\\|$)',
        '\\\.vs(\\|$)',
        '\\packages(\\|$)',
        '\\vendor(\\|$)',
        '\\coverage(\\|$)',
        '\\logs?(\\|$)',
        '\\temp(\\|$)',
        '\\tmp(\\|$)',
        '\\debug(\\|$)',
        '\\release(\\|$)',
        '\\\{[0-9A-Fa-f\-]{36}\}(\\|$)',
        '\\src(\\|$)',
        '\\controllers(\\|$)',
        '\\middleware(\\|$)',
        '\\routes(\\|$)',
        '\\utils(\\|$)',
        '\\public(\\|$)',
        '\\config(\\|$)',
        '\\models(\\|$)',
        '\\services(\\|$)',
        '\\tests?(\\|$)'
    ),

    [Parameter(Mandatory = $false)]
    [switch]${EnableDefaultFlattenRules}
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------- OS DETECTION (PS 5.1 SAFE) ----------------------------
function Test-IsWindows {
    return ($env:OS -eq 'Windows_NT' -or $PSVersionTable.PSEdition -eq 'Desktop')
}

# ---------------------------- ROOT DIRECTORY RESOLUTION (PS 5.1 SAFE) ----------------------------
function Resolve-ScriptRoot {
    try {
        if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot) -and (Test-Path -LiteralPath $PSScriptRoot -PathType Container)) {
            return $PSScriptRoot
        }
    } catch {}

    try {
        if ($MyInvocation -and $MyInvocation.MyCommand -and -not [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path)) {
            ${p} = Split-Path -Parent $MyInvocation.MyCommand.Path
            if (Test-Path -LiteralPath ${p} -PathType Container) { return ${p} }
        }
    } catch {}

    try { return (Get-Location).Path } catch { return $env:SystemDrive }
}

if ([string]::IsNullOrWhiteSpace(${RootDirectory})) {
    ${RootDirectory} = Resolve-ScriptRoot
}

# Safety: avoid scanning Windows folder by accident
if (${RootDirectory} -match '^[A-Za-z]:\\Windows(\\|$)') {
    ${RootDirectory} = $env:USERPROFILE
}

# ---------------------------- CONSOLE VISIBILITY (OPTIONAL) ----------------------------
function Set-ConsoleVisibility {
    param([Parameter(Mandatory = $true)][bool]${Visible})

    if (-not (Test-IsWindows)) { return }

    try {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinConsole {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void SetVisible(bool visible) {
        var handle = GetConsoleWindow();
        if (handle == IntPtr.Zero) return;
        ShowWindow(handle, visible ? 5 : 0);
    }
}
"@ -ErrorAction Stop
        [WinConsole]::SetVisible(${Visible})
    } catch {}
}

if (-not ${ShowConsole}) { Set-ConsoleVisibility -Visible $false }

# ---------------------------- ASSEMBLIES ----------------------------
if (-not (Test-IsWindows)) {
    throw "This GUI tool requires Windows (WinForms)."
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------- LOGGING (PROSUITE) ----------------------------
${script:ScriptName} = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
${script:LogDir} = 'C:\Logs-TEMP'
${script:LogPath} = $null

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]${Message},
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DEBUG')][string]${Level} = 'INFO'
    )
    ${ts} = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    ${entry} = "[${ts}] [${Level}] ${Message}"
    try { Add-Content -Path ${script:LogPath} -Value ${entry} -Encoding UTF8 -ErrorAction Stop } catch {}
}

function Initialize-Log {
    try {
        if (-not (Test-Path -LiteralPath ${script:LogDir})) {
            New-Item -Path ${script:LogDir} -ItemType Directory -Force | Out-Null
        }
    } catch {
        ${script:LogDir} = $env:TEMP
    }

    ${script:LogPath} = Join-Path ${script:LogDir} ("{0}.log" -f ${script:ScriptName})

    Write-Log -Message "==== Session started ====" -Level 'INFO'
    Write-Log -Message ("RootDirectory='{0}' | CategoryDepth={1} | ExecutionHost={2} | ShowConsole={3}" -f ${RootDirectory}, ${CategoryDepth}, ${ExecutionHost}, ${ShowConsole}) -Level 'INFO'
    Write-Log -Message ("ExcludeRelativePathRegex count: {0}" -f @(${ExcludeRelativePathRegex}).Count) -Level 'DEBUG'
    Write-Log -Message ("EnableDefaultFlattenRules={0}" -f [bool]${EnableDefaultFlattenRules}) -Level 'DEBUG'
    Write-Log -Message ("LogPath: {0}" -f ${script:LogPath}) -Level 'INFO'
}

function Show-InfoBox {
    param([Parameter(Mandatory = $true)][string]${Message})
    [void][System.Windows.Forms.MessageBox]::Show(
        ${Message},
        'Information',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
}

function Show-ErrorBox {
    param([Parameter(Mandatory = $true)][string]${Message})
    [void][System.Windows.Forms.MessageBox]::Show(
        ${Message},
        'Error',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}

Initialize-Log

# ---------------------------- DISCOVERY HELPERS ----------------------------
function Get-ExecutionBinary {
    param([Parameter(Mandatory = $true)][string]${Mode})

    if (${Mode} -eq 'WindowsPowerShell') { return 'powershell.exe' }
    if (${Mode} -eq 'PowerShell7') { return 'pwsh.exe' }

    try {
        ${pwsh} = Get-Command -Name 'pwsh.exe' -ErrorAction SilentlyContinue
        if (${pwsh}) { return 'pwsh.exe' }
    } catch {}
    return 'powershell.exe'
}

function Get-DefaultFlattenRules {
    return @(
        [PSCustomObject]@{
            MatchPrefix = 'ITSM-Templates-WKS\Assets\AdditionalSupportScipts'
            OutputKey = 'ITSM-Templates-WKS\AdditionalSupportScripts'
            Recurse = $true
        }
    )
}

function Get-ScriptCatalogV3 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]${BasePath},

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 10)]
        [int]${MaxDepth} = 4,

        [Parameter(Mandatory = $false)]
        [bool]${IncludeRootCategory} = $true,

        [Parameter(Mandatory = $false)]
        [bool]${OnlyFoldersWithScripts} = $true,

        [Parameter(Mandatory = $false)]
        [string[]]${ExcludeRelPathRegex} = @(),

        [Parameter(Mandatory = $false)]
        [object[]]${FlattenRules} = @()
    )

    ${resolvedBase} = (Resolve-Path -LiteralPath ${BasePath}).Path.TrimEnd('\')

    function Get-RelPath {
        param([Parameter(Mandatory = $true)][string]${FullPath})
        ${rel} = ${FullPath}.Substring(${resolvedBase}.Length).TrimStart('\')
        if ([string]::IsNullOrWhiteSpace(${rel})) { return '.' }
        return ${rel}
    }

    function Test-IsExcludedRelPath {
        param([Parameter(Mandatory = $true)][string]${RelPath})
        foreach (${rx} in ${ExcludeRelPathRegex}) {
            if ([string]::IsNullOrWhiteSpace(${rx})) { continue }
            if (${RelPath} -match ${rx}) { return $true }
        }
        return $false
    }

    ${dirList} = New-Object System.Collections.Generic.List[object]
    ${queue} = New-Object System.Collections.Generic.Queue[object]
    ${queue}.Enqueue([PSCustomObject]@{ Path = ${resolvedBase}; Depth = 0 })

    while (${queue}.Count -gt 0) {
        ${node} = ${queue}.Dequeue()
        ${p} = ${node}.Path
        ${d} = [int]${node}.Depth

        if (${d} -gt ${MaxDepth}) { continue }

        ${rel} = Get-RelPath -FullPath ${p}
        if (Test-IsExcludedRelPath -RelPath ${rel}) { continue }

        if (${d} -eq 0 -and -not ${IncludeRootCategory}) {
            # skip root category
        } else {
            ${dirList}.Add([PSCustomObject]@{ Path = ${p}; Rel = ${rel}; Depth = ${d} }) | Out-Null
        }

        if (${d} -eq ${MaxDepth}) { continue }

        try {
            foreach (${dir} in (Get-ChildItem -LiteralPath ${p} -Directory -ErrorAction Stop | Sort-Object -Property Name)) {
                ${queue}.Enqueue([PSCustomObject]@{ Path = ${dir}.FullName; Depth = (${d} + 1) })
            }
        } catch {}
    }

    ${catalog} = @{}

    foreach (${entry} in (${dirList} | Sort-Object Depth, Rel)) {
        try {
            ${scripts} = @(Get-ChildItem -LiteralPath ${entry}.Path -Filter '*.ps1' -File -ErrorAction Stop | Sort-Object -Property Name)
            if (${OnlyFoldersWithScripts} -and @(${scripts}).Count -eq 0) { continue }
            ${catalog}[${entry}.Rel] = ${scripts}
        } catch {}
    }

    foreach (${rule} in ${FlattenRules}) {
        if (-not ${rule}) { continue }

        ${matchPrefix} = [string]${rule}.MatchPrefix
        ${outputKey} = [string]${rule}.OutputKey
        ${recurse} = $true
        try { if ($null -ne ${rule}.Recurse) { ${recurse} = [bool]${rule}.Recurse } } catch { ${recurse} = $true }

        if ([string]::IsNullOrWhiteSpace(${matchPrefix}) -or [string]::IsNullOrWhiteSpace(${outputKey})) { continue }

        ${matchPrefix} = ${matchPrefix}.Trim('\')
        ${absPrefix} = Join-Path ${resolvedBase} ${matchPrefix}
        if (-not (Test-Path -LiteralPath ${absPrefix} -PathType Container)) { continue }

        try {
            if (${recurse}) {
                ${flatScripts} = @(Get-ChildItem -LiteralPath ${absPrefix} -Filter '*.ps1' -File -Recurse -ErrorAction Stop | Sort-Object -Property Name)
            } else {
                ${flatScripts} = @(Get-ChildItem -LiteralPath ${absPrefix} -Filter '*.ps1' -File -ErrorAction Stop | Sort-Object -Property Name)
            }

            if (@(${flatScripts}).Count -gt 0) {
                ${catalog}[${outputKey}] = ${flatScripts}

                ${prefixPattern} = ('^{0}(\\|$)' -f [regex]::Escape(${matchPrefix}))
                foreach (${k} in @(${catalog}.Keys)) {
                    if (${k} -match ${prefixPattern} -and ${k} -ne ${outputKey}) {
                        [void]${catalog}.Remove(${k})
                    }
                }
            }
        } catch {}
    }

    ${ordered} = [ordered]@{}
    foreach (${k} in @(${catalog}.Keys | Sort-Object)) {
        ${ordered}[${k}] = ${catalog}[${k}]
    }

    return ${ordered}
}

function Get-ScriptCatalog {
    param(
        [Parameter(Mandatory = $true)][string]${BasePath},
        [Parameter(Mandatory = $true)][int]${MaxDepth}
    )

    ${flattenRules} = @()
    if (${EnableDefaultFlattenRules}) {
        ${flattenRules} = @(Get-DefaultFlattenRules)
    }

    ${catalogOrdered} = Get-ScriptCatalogV3 `
        -BasePath ${BasePath} `
        -MaxDepth ${MaxDepth} `
        -IncludeRootCategory $true `
        -OnlyFoldersWithScripts $true `
        -ExcludeRelPathRegex ${ExcludeRelativePathRegex} `
        -FlattenRules ${flattenRules}

    try {
        Write-Log -Message ("Total categories loaded: {0}" -f @(${catalogOrdered}.Keys).Count) -Level 'INFO'
    } catch {}

    return ${catalogOrdered}
}

# ---------------------------- UI HELPERS ----------------------------
function Populate-ListBox {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.CheckedListBox]${ListBox},
        [Parameter(Mandatory = $true)][System.IO.FileInfo[]]${Scripts},
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]${FilterText} = ''
    )

    if ($null -eq ${FilterText}) { ${FilterText} = '' }

    ${needle} = (${FilterText}.Trim()).ToLowerInvariant()

    ${ListBox}.BeginUpdate()
    try {
        ${ListBox}.Items.Clear()

        foreach (${s} in ${Scripts}) {
            if ([string]::IsNullOrWhiteSpace(${needle}) -or (${s}.Name.ToLowerInvariant().Contains(${needle}))) {
                [void]${ListBox}.Items.Add(${s}.Name, $false)
            }
        }

        if (${ListBox}.Items.Count -eq 0) {
            [void]${ListBox}.Items.Add('<No matching scripts found>', $false)
        }
    } finally {
        ${ListBox}.EndUpdate()
    }
}

function Get-SelectedScriptPaths {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.TabControl]${TabControl},
        [Parameter(Mandatory = $true)][hashtable]${Catalog}
    )

    ${selected} = New-Object System.Collections.Generic.List[string]

    foreach (${tab} in ${TabControl}.TabPages) {
        ${tabName} = ${tab}.Text
        if (-not ${Catalog}.ContainsKey(${tabName})) { continue }

        ${lb} = $null
        foreach (${ctrl} in ${tab}.Controls) {
            if (${ctrl} -is [System.Windows.Forms.CheckedListBox]) { ${lb} = ${ctrl}; break }
        }
        if (-not ${lb}) { continue }

        foreach (${item} in ${lb}.CheckedItems) {
            if (${item} -eq '<No matching scripts found>') { continue }

            ${fileObj} = ${Catalog}[${tabName}] | Where-Object { $_.Name -eq ${item} } | Select-Object -First 1
            if (${fileObj} -and (Test-Path -LiteralPath ${fileObj}.FullName)) {
                ${selected}.Add(${fileObj}.FullName) | Out-Null
            }
        }
    }

    return @(${selected})
}

function Execute-SelectedScripts {
    param(
        [Parameter(Mandatory = $true)][string[]]${ScriptPaths},
        [Parameter(Mandatory = $true)][string]${HostBinary},
        [Parameter(Mandatory = $true)][System.Windows.Forms.ProgressBar]${ProgressBar},
        [Parameter(Mandatory = $true)][System.Windows.Forms.Label]${StatusLabel}
    )

    if (@(${ScriptPaths}).Count -eq 0) {
        Show-InfoBox -Message "No scripts selected."
        return
    }

    ${ProgressBar}.Minimum = 0
    ${ProgressBar}.Maximum = [math]::Max(1, @(${ScriptPaths}).Count)
    ${ProgressBar}.Value = 0

    foreach (${path} in ${ScriptPaths}) {
        ${StatusLabel}.Text = ("Executing: {0}" -f ${path})
        Write-Log -Message ("Executing script: {0}" -f ${path}) -Level 'INFO'

        try {
            ${psi} = New-Object System.Diagnostics.ProcessStartInfo
            ${psi}.FileName = ${HostBinary}
            ${psi}.Arguments = ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f ${path})
            ${psi}.UseShellExecute = $false
            ${psi}.RedirectStandardOutput = $true
            ${psi}.RedirectStandardError = $true
            ${psi}.CreateNoWindow = $true

            ${proc} = [System.Diagnostics.Process]::Start(${psi})
            ${stdout} = ${proc}.StandardOutput.ReadToEnd()
            ${stderr} = ${proc}.StandardError.ReadToEnd()
            ${proc}.WaitForExit()

            if (${proc}.ExitCode -eq 0) {
                Write-Log -Message ("SUCCESS: {0}" -f ${path}) -Level 'SUCCESS'
            } else {
                Write-Log -Message ("ERROR: {0} | ExitCode={1} | {2}" -f ${path}, ${proc}.ExitCode, ${stderr}) -Level 'ERROR'
            }

            if (-not [string]::IsNullOrWhiteSpace(${stdout})) {
                Write-Log -Message ("STDOUT ({0}): {1}" -f ([System.IO.Path]::GetFileName(${path})), (${stdout}.Trim())) -Level 'DEBUG'
            }
        } catch {
            Write-Log -Message ("Exception executing '{0}': {1}" -f ${path}, $_.Exception.Message) -Level 'ERROR'
        }

        ${ProgressBar}.Value = [math]::Min((${ProgressBar}.Value + 1), ${ProgressBar}.Maximum)
        try { [System.Windows.Forms.Application]::DoEvents() } catch {}
    }

    ${StatusLabel}.Text = "Execution completed. Check log for details."
    Show-InfoBox -Message ("Execution completed. Log: {0}" -f ${script:LogPath})
}

# ---------------------------- GUI ----------------------------
function Create-GUI {
    ${catalog} = Get-ScriptCatalog -BasePath ${RootDirectory} -MaxDepth ${CategoryDepth}
    if (@(${catalog}.Keys).Count -eq 0) {
        Show-ErrorBox -Message "No .ps1 scripts were found in the selected root folder."
        return
    }

    ${hostBin} = Get-ExecutionBinary -Mode ${ExecutionHost}
    Write-Log -Message ("Execution host resolved: {0}" -f ${hostBin}) -Level 'INFO'

    ${formW} = 1100
    ${formH} = 820
    ${pad} = 10
    ${btnH} = 34
    ${gap} = 10
    ${progH} = 14
    ${labelH} = 18

    ${form} = New-Object System.Windows.Forms.Form
    ${form}.Text = "Launch Script Menu"
    ${form}.ClientSize = New-Object System.Drawing.Size(${formW}, ${formH})
    ${form}.StartPosition = "CenterScreen"
    ${form}.FormBorderStyle = 'FixedSingle'
    ${form}.MaximizeBox = $false
    ${form}.BackColor = [System.Drawing.Color]::WhiteSmoke
    ${form}.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    ${bottomY} = ${form}.ClientSize.Height - ${pad} - ${btnH}
    ${labelY} = ${bottomY} - ${gap} - ${labelH}
    ${progY} = ${labelY} - ${gap} - ${progH}
    ${tabH} = ${progY} - ${pad} - ${gap}

    ${tabControl} = New-Object System.Windows.Forms.TabControl
    ${tabControl}.Location = New-Object System.Drawing.Point(${pad}, ${pad})
    ${tabControl}.Size = New-Object System.Drawing.Size((${formW} - (2 * ${pad})), ${tabH})
    ${form}.Controls.Add(${tabControl})

    ${progress} = New-Object System.Windows.Forms.ProgressBar
    ${progress}.Location = New-Object System.Drawing.Point(${pad}, ${progY})
    ${progress}.Size = New-Object System.Drawing.Size((${formW} - (2 * ${pad})), ${progH})
    ${progress}.Minimum = 0
    ${progress}.Maximum = 100
    ${progress}.Value = 0
    ${form}.Controls.Add(${progress})

    ${lblStatus} = New-Object System.Windows.Forms.Label
    ${lblStatus}.Location = New-Object System.Drawing.Point(${pad}, ${labelY})
    ${lblStatus}.Size = New-Object System.Drawing.Size((${formW} - (2 * ${pad})), ${labelH})
    ${lblStatus}.Text = "Ready"
    ${form}.Controls.Add(${lblStatus})

    ${btnWidthExec} = 180
    ${btnWidthClose} = 120

    ${btnClose} = New-Object System.Windows.Forms.Button
    ${btnClose}.Text = "Close"
    ${btnClose}.Size = New-Object System.Drawing.Size(${btnWidthClose}, ${btnH})
    ${btnClose}.Location = New-Object System.Drawing.Point((${formW} - ${pad} - ${btnWidthClose}), ${bottomY})
    ${btnClose}.Add_Click({ ${form}.Close() })
    ${form}.Controls.Add(${btnClose})

    ${btnExecute} = New-Object System.Windows.Forms.Button
    ${btnExecute}.Text = "Execute Selected"
    ${btnExecute}.Size = New-Object System.Drawing.Size(${btnWidthExec}, ${btnH})
    ${btnExecute}.Location = New-Object System.Drawing.Point((${btnClose}.Left - ${gap} - ${btnWidthExec}), ${bottomY})
    ${btnExecute}.BackColor = [System.Drawing.Color]::LightSkyBlue
    ${btnExecute}.Enabled = $false
    ${btnExecute}.Visible = $true
    ${form}.Controls.Add(${btnExecute})

    # ScriptBlock updater (invoke via .Invoke() only, never with &)
    [scriptblock]${updateExecState} = {
        try {
            ${selectedAll} = @(Get-SelectedScriptPaths -TabControl ${tabControl} -Catalog ${catalog})
            ${countSel} = @(${selectedAll}).Count

            if (${countSel} -gt 0) {
                ${btnExecute}.Enabled = $true
                ${lblStatus}.Text = ("Selected: {0}" -f ${countSel})
            } else {
                ${btnExecute}.Enabled = $false
                if (${lblStatus}.Text -notmatch '^Filtered:') { ${lblStatus}.Text = 'Ready' }
            }
        } catch {
            Write-Log -Message ("updateExecState failed: {0}" -f $_.Exception.Message) -Level 'WARN'
        }
    }.GetNewClosure()

    # helper delegate used for BeginInvoke
    ${invokeUpdate} = { $null = ${updateExecState}.Invoke() }.GetNewClosure()
    ${methodInvokerUpdate} = [System.Windows.Forms.MethodInvoker]${invokeUpdate}

    ${debounce} = New-Object System.Windows.Forms.Timer
    ${debounce}.Interval = 250

    ${tickHandler} = {
        param($sender, $eventArgs)
        try {
            ${debounce}.Stop()
            ${ctx} = ${debounce}.Tag
            if (-not ${ctx}) { return }

            ${tb} = ${ctx}.SearchBox
            ${lb} = ${ctx}.ListBox
            ${sf} = ${ctx}.Scripts

            if (-not ${tb} -or -not ${lb} -or -not ${sf}) { return }

            Populate-ListBox -ListBox ${lb} -Scripts ${sf} -FilterText ${tb}.Text
            ${lblStatus}.Text = ("Filtered: {0}" -f ${ctx}.Category)

            $null = ${updateExecState}.Invoke()
        } catch {
            Write-Log -Message ("Debounce Tick handler failed: {0}" -f $_.Exception.Message) -Level 'ERROR'
        }
    }.GetNewClosure()
    ${debounce}.Add_Tick(${tickHandler})

    foreach (${category} in @(${catalog}.Keys | Sort-Object)) {
        ${categoryLocal} = ${category}
        ${scriptsLocal} = ${catalog}[${categoryLocal}]

        ${tab} = New-Object System.Windows.Forms.TabPage
        ${tab}.Text = ${categoryLocal}
        ${tab}.BackColor = [System.Drawing.Color]::White
        [void]${tabControl}.TabPages.Add(${tab})

        ${searchBox} = New-Object System.Windows.Forms.TextBox
        ${searchBox}.Location = New-Object System.Drawing.Point(${pad}, ${pad})
        ${searchBox}.Size = New-Object System.Drawing.Size((${tabControl}.Width - (2 * ${pad}) - 20), 24)
        ${searchBox}.Anchor = 'Top,Left,Right'
        ${tab}.Controls.Add(${searchBox})

        ${listBox} = New-Object System.Windows.Forms.CheckedListBox
        ${listBox}.Location = New-Object System.Drawing.Point(${pad}, 45)
        ${listBox}.Size = New-Object System.Drawing.Size((${tabControl}.Width - (2 * ${pad}) - 20), (${tabH} - 55))
        ${listBox}.Anchor = 'Top,Bottom,Left,Right'
        ${listBox}.CheckOnClick = $true
        ${tab}.Controls.Add(${listBox})

        Populate-ListBox -ListBox ${listBox} -Scripts ${scriptsLocal} -FilterText ''

        ${searchBoxLocal} = ${searchBox}
        ${listBoxLocal} = ${listBox}

        ${textChangedHandler} = {
            param($sender, $eventArgs)
            try {
                ${debounce}.Stop()
                ${debounce}.Tag = [PSCustomObject]@{
                    Category = ${categoryLocal}
                    SearchBox = ${searchBoxLocal}
                    ListBox = ${listBoxLocal}
                    Scripts = ${scriptsLocal}
                }
                ${debounce}.Start()
            } catch {
                Write-Log -Message ("Search TextChanged handler failed for '{0}': {1}" -f ${categoryLocal}, $_.Exception.Message) -Level 'ERROR'
            }
        }.GetNewClosure()
        ${searchBoxLocal}.Add_TextChanged(${textChangedHandler})

        # Defer selection-state refresh until after CheckedItems updates
        ${itemCheckHandler} = {
            param($sender, $eventArgs)
            try {
                $null = ${form}.BeginInvoke(${methodInvokerUpdate})
            } catch {
                Write-Log -Message ("ItemCheck handler failed for '{0}': {1}" -f ${categoryLocal}, $_.Exception.Message) -Level 'WARN'
            }
        }.GetNewClosure()

        ${listBoxLocal}.Add_ItemCheck(${itemCheckHandler})
        ${listBoxLocal}.Add_SelectedIndexChanged(${itemCheckHandler})
    }

    ${btnExecute}.Add_Click({
            try {
                ${lblStatus}.Text = "Collecting selected scripts..."
                ${selected} = Get-SelectedScriptPaths -TabControl ${tabControl} -Catalog ${catalog}
                Execute-SelectedScripts -ScriptPaths ${selected} -HostBinary ${hostBin} -ProgressBar ${progress} -StatusLabel ${lblStatus}
                $null = ${updateExecState}.Invoke()
            } catch {
                Write-Log -Message ("Execution pipeline error: {0}" -f $_.Exception.Message) -Level 'ERROR'
                Show-ErrorBox -Message ("Execution failed: {0}" -f $_.Exception.Message)
            }
        })

    ${form}.Add_Shown({
            try { $null = ${updateExecState}.Invoke() } catch {}
        })

    ${form}.Add_FormClosing({
            Write-Log -Message "==== Session ended ====" -Level 'INFO'
        })

    [void]${form}.ShowDialog()
}

# ---------------------------- ENTRY POINT ----------------------------
try {
    Create-GUI
} catch {
    Write-Log -Message ("Fatal error: {0}" -f $_.Exception.Message) -Level 'ERROR'
    try { Show-ErrorBox -Message ("Fatal error: {0}" -f $_.Exception.Message) } catch {}
} finally {
    try { Write-Log -Message "==== Session ended ====" -Level 'INFO' } catch {}
}

# End of Script
