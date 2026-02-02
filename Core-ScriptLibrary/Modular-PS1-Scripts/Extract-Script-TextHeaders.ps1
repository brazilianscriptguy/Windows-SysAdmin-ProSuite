<#
.SYNOPSIS
    Extracts comment-based help headers from .ps1 files and consolidates them into a single merged report.

.DESCRIPTION
    Recursively scans a selected root folder for PowerShell scripts (*.ps1),
    extracts the first comment-based help header (first block delimited by <# and # >),
    and writes all headers into a single consolidated text file.

    Enhancements in this build:
    - Deterministic output ordering (sorted by FullName)
    - Summary footer (totals + headers found + missing headers + breakdown)
    - Optional extraction of line-based help headers (# .SYNOPSIS style)
    - PowerShell 5.1-safe OS detection (no $PSVersionTable.Platform)
    - Count-safe array handling everywhere .Count is used
    - Enterprise-grade logging to C:\Logs-TEMP (single file per run)
    - WinForms GUI on Windows; CLI fallback otherwise

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    3.4 - 2026-02-02
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]${RootFolder} = $null,

    [Parameter(Mandatory=$false)]
    [switch]${AllowLineCommentHeaders},

    [Parameter(Mandatory=$false)]
    [switch]${ShowConsole}
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------- OS DETECTION (PS 5.1 SAFE) ----------------------------
function Test-IsWindows {
    return ($env:OS -eq 'Windows_NT' -or $PSVersionTable.PSEdition -eq 'Desktop')
}

# ---------------------------- GLOBAL CONTEXT ----------------------------
${script:ScriptName} = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
${script:LogDir}     = 'C:\Logs-TEMP'
${script:LogPath}    = $null
${script:LogBuffer}  = New-Object System.Collections.Generic.List[string]

# Run counters (summary)
${script:TotalFiles}    = 0
${script:HeadersFound}  = 0
${script:NoHeader}      = 0
${script:LineHeaders}   = 0
${script:BlockHeaders}  = 0
${script:ReadErrors}    = 0

# ---------------------------- CONSOLE VISIBILITY (OPTIONAL) ----------------------------
function Set-ConsoleVisibility {
    param([Parameter(Mandatory=$true)][bool]${Visible})

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

# ---------------------------- LOGGING (PROSUITE) ----------------------------
function Initialize-Log {
    param([Parameter(Mandatory=$false)][string]${Directory} = 'C:\Logs-TEMP')

    try {
        if (-not (Test-Path -LiteralPath ${Directory})) {
            New-Item -Path ${Directory} -ItemType Directory -Force | Out-Null
        }
        ${script:LogDir} = ${Directory}
    } catch {
        ${script:LogDir} = $env:TEMP
    }

    ${script:LogPath} = Join-Path ${script:LogDir} "${script:ScriptName}.log"

    Write-Log -Message "==== Session started ====" -Level 'INFO'
    Write-Log -Message "Script: ${script:ScriptName}" -Level 'INFO'
    Write-Log -Message "LogPath: ${script:LogPath}" -Level 'INFO'
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]${Message},
        [ValidateSet('INFO','WARN','ERROR','SUCCESS','DEBUG')][string]${Level} = 'INFO'
    )

    if ([string]::IsNullOrWhiteSpace(${script:LogPath})) {
        ${fallbackDir} = 'C:\Logs-TEMP'
        if (-not (Test-Path -LiteralPath ${fallbackDir})) {
            New-Item -Path ${fallbackDir} -ItemType Directory -Force | Out-Null
        }
        ${script:LogPath} = Join-Path ${fallbackDir} "${script:ScriptName}.log"
    }

    ${ts}    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    ${entry} = "[${ts}] [${Level}] ${Message}"

    try { Add-Content -Path ${script:LogPath} -Value ${entry} -Encoding UTF8 -ErrorAction Stop } catch {}
    try { ${script:LogBuffer}.Add(${entry}) | Out-Null } catch {}
}

function Finalize-Log {
    Write-Log -Message "==== Session ended ====" -Level 'INFO'
}

function Show-ErrorBox {
    param([Parameter(Mandatory=$true)][string]${Message})

    if (-not (Test-IsWindows)) { return }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [void][System.Windows.Forms.MessageBox]::Show(${Message}, 'Error', 'OK', 'Error')
    } catch {}
}

function Show-InfoBox {
    param([Parameter(Mandatory=$true)][string]${Message})

    if (-not (Test-IsWindows)) { return }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [void][System.Windows.Forms.MessageBox]::Show(${Message}, 'Information', 'OK', 'Information')
    } catch {}
}

function Handle-Error {
    param(
        [Parameter(Mandatory=$true)][string]${ErrorMessage},
        [Parameter(Mandatory=$false)][switch]${ShowMessageBox}
    )
    Write-Log -Message ${ErrorMessage} -Level 'ERROR'
    if (${ShowMessageBox}) { Show-ErrorBox -Message ${ErrorMessage} }
}

# ---------------------------- HEADER EXTRACTION ----------------------------

function Get-BlockHelpHeader {
    param([Parameter(Mandatory=$true)][string]${FilePath})

    ${headerLines} = New-Object System.Collections.Generic.List[string]
    ${inHeader}    = $false
    ${foundStart}  = $false
    ${foundEnd}    = $false
    ${lineCount}   = 0

    try {
        foreach (${line} in (Get-Content -LiteralPath ${FilePath} -ErrorAction Stop)) {
            ${lineCount}++

            if (-not ${foundStart} -and ${line} -match '<#') {
                ${inHeader}   = $true
                ${foundStart} = $true
            }

            if (${inHeader}) { ${headerLines}.Add(${line}) | Out-Null }

            if (${inHeader} -and ${line} -match '#>') {
                ${foundEnd} = $true
                break
            }

            # Performance guard: stop scanning if header didn't appear quickly
            if (-not ${foundStart} -and ${lineCount} -ge 80) { break }
        }
    } catch {
        ${script:ReadErrors}++
        Write-Log -Message "Failed to read file: ${FilePath}. $($_.Exception.Message)" -Level 'ERROR'
        return @()
    }

    if (-not ${foundStart} -or -not ${foundEnd}) { return @() }
    return @(${headerLines})
}

function Get-LineHelpHeader {
    param([Parameter(Mandatory=$true)][string]${FilePath})

    # Accepts headers like:
    # # .SYNOPSIS
    # # ...
    # Stops on first non-comment line after starting.
    ${lines} = New-Object System.Collections.Generic.List[string]
    ${started} = $false
    ${lineCount} = 0

    try {
        foreach (${line} in (Get-Content -LiteralPath ${FilePath} -ErrorAction Stop)) {
            ${lineCount}++

            if (-not ${started}) {
                # Only search within first N lines for a marker
                if (${lineCount} -gt 120) { break }

                if (${line} -match '^\s*#\s*\.SYNOPSIS\b' -or ${line} -match '^\s*#\s*\.DESCRIPTION\b') {
                    ${started} = $true
                    ${lines}.Add(${line}) | Out-Null
                    continue
                }

                # If we hit code early, abandon line-header search
                if (${line}.Trim().Length -gt 0 -and ${line}.Trim() -notmatch '^\s*#') { break }

                continue
            }

            # Started: keep comment lines and blanks
            if (${line}.Trim().Length -eq 0 -or ${line} -match '^\s*#') {
                ${lines}.Add(${line}) | Out-Null
                continue
            }

            # First code line after header -> stop
            break
        }
    } catch {
        ${script:ReadErrors}++
        Write-Log -Message "Failed to read file (line-header scan): ${FilePath}. $($_.Exception.Message)" -Level 'ERROR'
        return @()
    }

    if (-not ${started}) { return @() }
    return @(${lines})
}

function Get-FileHeader {
    param([Parameter(Mandatory=$true)][string]${FilePath})

    # Prefer block-help; optionally fallback to line-help.
    ${block} = @(Get-BlockHelpHeader -FilePath ${FilePath})
    if (@(${block}).Count -gt 0) {
        ${script:BlockHeaders}++
        return @(${block})
    }

    if (${AllowLineCommentHeaders}) {
        ${lineHeader} = @(Get-LineHelpHeader -FilePath ${FilePath})
        if (@(${lineHeader}).Count -gt 0) {
            ${script:LineHeaders}++
            return @(${lineHeader})
        }
    }

    return @()
}

function Write-SummaryFooter {
    param(
        [Parameter(Mandatory=$true)][string]${MergedFile},
        [Parameter(Mandatory=$true)][string]${RootFolder}
    )

    ${summary} = New-Object System.Text.StringBuilder
    [void]${summary}.AppendLine("")
    [void]${summary}.AppendLine("===============================================================")
    [void]${summary}.AppendLine("SUMMARY")
    [void]${summary}.AppendLine("Folder: ${RootFolder}")
    [void]${summary}.AppendLine(("Total files: {0}" -f ${script:TotalFiles}))
    [void]${summary}.AppendLine(("Headers found: {0}" -f ${script:HeadersFound}))
    [void]${summary}.AppendLine(("No header: {0}" -f ${script:NoHeader}))
    [void]${summary}.AppendLine(("Block headers: {0}" -f ${script:BlockHeaders}))
    [void]${summary}.AppendLine(("Line headers: {0}" -f ${script:LineHeaders}))
    [void]${summary}.AppendLine(("Read errors: {0}" -f ${script:ReadErrors}))
    [void]${summary}.AppendLine(("Generated: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    [void]${summary}.AppendLine("===============================================================")

    Add-Content -Path ${MergedFile} -Value ${summary}.ToString() -Encoding UTF8
}

function Start-HeaderExtraction {
    param([Parameter(Mandatory=$true)][string]${RootFolder})

    try {
        if (-not (Test-Path -LiteralPath ${RootFolder} -PathType Container)) {
            throw "Invalid folder path: ${RootFolder}"
        }

        Write-Log -Message "Starting header extraction from: ${RootFolder}" -Level 'INFO'

        # Reset counters per run (important for multiple GUI runs)
        ${script:TotalFiles}    = 0
        ${script:HeadersFound}  = 0
        ${script:NoHeader}      = 0
        ${script:LineHeaders}   = 0
        ${script:BlockHeaders}  = 0
        ${script:ReadErrors}    = 0

        ${mergedFile} = Join-Path ${RootFolder} "Merged-PowerShellScripts-Headers.txt"

        ${banner} = @(
            "### Merged Headers from Folder: ${RootFolder} ###"
            "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            "==============================================================="
            ""
        ) -join "`r`n"

        ${banner} | Out-File -FilePath ${mergedFile} -Force -Encoding UTF8

        # Deterministic ordering (sorted by FullName)
        ${ps1Files} = @(
            Get-ChildItem -LiteralPath ${RootFolder} -Recurse -Filter "*.ps1" -File -ErrorAction Stop |
            Sort-Object -Property FullName
        )

        ${script:TotalFiles} = @(${ps1Files}).Count
        Write-Log -Message "Files discovered: ${script:TotalFiles}" -Level 'INFO'

        ${index} = 0
        foreach (${file} in ${ps1Files}) {
            ${index}++
            try {
                Write-Progress -Activity "Extracting Headers" -Status ${file}.FullName -PercentComplete ((${index} / [math]::Max(1, ${script:TotalFiles})) * 100)
            } catch {}

            Add-Content -Path ${mergedFile} -Value ("`r`n### File: {0} ###`r`n" -f ${file}.FullName) -Encoding UTF8

            ${header} = @(Get-FileHeader -FilePath ${file}.FullName)

            if (@(${header}).Count -gt 0) {
                ${script:HeadersFound}++
                Add-Content -Path ${mergedFile} -Value (${header} -join "`r`n") -Encoding UTF8
            } else {
                ${script:NoHeader}++
                Add-Content -Path ${mergedFile} -Value ("No header found in {0}`r`n" -f ${file}.Name) -Encoding UTF8
            }
        }

        Write-SummaryFooter -MergedFile ${mergedFile} -RootFolder ${RootFolder}

        Write-Log -Message "Extraction complete. Output saved to: ${mergedFile}" -Level 'SUCCESS'
        Write-Log -Message ("Summary - Total={0}, Headers={1}, NoHeader={2}, Block={3}, Line={4}, ReadErrors={5}" -f `
            ${script:TotalFiles}, ${script:HeadersFound}, ${script:NoHeader}, ${script:BlockHeaders}, ${script:LineHeaders}, ${script:ReadErrors}) -Level 'INFO'

        return ${mergedFile}
    } catch {
        Handle-Error -ErrorMessage "Extraction failed: $($_.Exception.Message)" -ShowMessageBox
        return $null
    } finally {
        try { Write-Progress -Activity "Extracting Headers" -Completed } catch {}
    }
}

# ---------------------------- GUI ----------------------------
function Show-GUI {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    ${uiLeft} = 10
    ${uiTop}  = 12
    ${uiLblW} = 120
    ${uiGap}  = 10
    ${uiBoxW} = 420
    ${uiBtnH} = 32

    ${form} = New-Object System.Windows.Forms.Form
    ${form}.Text = "PowerShell Scripts Headers Extractor"
    ${form}.Size = New-Object System.Drawing.Size(640, 360)
    ${form}.StartPosition = "CenterScreen"
    ${form}.MaximizeBox = $false
    ${form}.FormBorderStyle = 'FixedDialog'

    ${label} = New-Object System.Windows.Forms.Label
    ${label}.Text = "Select Root Folder:"
    ${label}.Location = New-Object System.Drawing.Point(${uiLeft}, ${uiTop})
    ${label}.Size = New-Object System.Drawing.Size(${uiLblW}, 20)
    ${form}.Controls.Add(${label})

    ${textBox} = New-Object System.Windows.Forms.TextBox
    ${textBox}.Location = New-Object System.Drawing.Point((${uiLeft} + ${uiLblW}), (${uiTop} - 2))
    ${textBox}.Size = New-Object System.Drawing.Size(${uiBoxW}, 20)
    ${textBox}.Text = if ($PWD) { $PWD.Path } else { [Environment]::CurrentDirectory }
    ${form}.Controls.Add(${textBox})

    ${browse} = New-Object System.Windows.Forms.Button
    ${browse}.Text = "Browse"
    ${browse}.Size = New-Object System.Drawing.Size(80, 23)
    ${browse}.Location = New-Object System.Drawing.Point((${textBox}.Right + ${uiGap}), (${uiTop} - 4))
    ${browse}.Add_Click({
        ${dialog} = New-Object System.Windows.Forms.FolderBrowserDialog
        if (${dialog}.ShowDialog() -eq "OK") { ${textBox}.Text = ${dialog}.SelectedPath }
    })
    ${form}.Controls.Add(${browse})

    ${chkLineHeaders} = New-Object System.Windows.Forms.CheckBox
    ${chkLineHeaders}.Text = "Allow line-based headers (# .SYNOPSIS)"
    ${chkLineHeaders}.AutoSize = $true
    ${chkLineHeaders}.Location = New-Object System.Drawing.Point(${uiLeft}, 50)
    ${chkLineHeaders}.Checked = [bool]${AllowLineCommentHeaders}
    ${form}.Controls.Add(${chkLineHeaders})

    ${btnRun} = New-Object System.Windows.Forms.Button
    ${btnRun}.Text = "Run"
    ${btnRun}.Size = New-Object System.Drawing.Size(100, ${uiBtnH})
    ${btnRun}.Location = New-Object System.Drawing.Point((${uiLeft} + ${uiLblW}), 80)
    ${form}.Controls.Add(${btnRun})

    ${btnExit} = New-Object System.Windows.Forms.Button
    ${btnExit}.Text = "Exit"
    ${btnExit}.Size = New-Object System.Drawing.Size(100, ${uiBtnH})
    ${btnExit}.Location = New-Object System.Drawing.Point((${btnRun}.Right + ${uiGap}), 80)
    ${btnExit}.Add_Click({ ${form}.Close() })
    ${form}.Controls.Add(${btnExit})

    ${lblStatus} = New-Object System.Windows.Forms.Label
    ${lblStatus}.Text = "Ready"
    ${lblStatus}.Location = New-Object System.Drawing.Point(${uiLeft}, 125)
    ${lblStatus}.Size = New-Object System.Drawing.Size(610, 20)
    ${form}.Controls.Add(${lblStatus})

    ${textBoxLog} = New-Object System.Windows.Forms.TextBox
    ${textBoxLog}.Multiline = $true
    ${textBoxLog}.ScrollBars = "Vertical"
    ${textBoxLog}.ReadOnly = $true
    ${textBoxLog}.Location = New-Object System.Drawing.Point(${uiLeft}, 150)
    ${textBoxLog}.Size = New-Object System.Drawing.Size(610, 160)
    ${form}.Controls.Add(${textBoxLog})

    function Update-LogView {
        ${textBoxLog}.Text = (${script:LogBuffer} -join "`r`n")
        ${textBoxLog}.SelectionStart = ${textBoxLog}.TextLength
        ${textBoxLog}.ScrollToCaret()
    }

    ${btnRun}.Add_Click({
        ${folder} = ${textBox}.Text.Trim()

        if (-not (Test-Path -LiteralPath ${folder} -PathType Container)) {
            Handle-Error -ErrorMessage "Invalid folder path: ${folder}" -ShowMessageBox
            Update-LogView
            return
        }

        try {
            ${AllowLineCommentHeaders} = [bool]${chkLineHeaders}.Checked

            ${lblStatus}.Text = "Running..."
            Write-Log -Message "GUI run requested for folder: ${folder} (AllowLineHeaders=${AllowLineCommentHeaders})" -Level 'INFO'
            Update-LogView

            ${merged} = Start-HeaderExtraction -RootFolder ${folder}
            Update-LogView

            if (${merged}) {
                ${lblStatus}.Text = "Completed: ${merged}"
                Show-InfoBox -Message ("Headers saved to:`r`n{0}`r`n`r`nTotal: {1} | Headers: {2} | Missing: {3}" -f `
                    ${merged}, ${script:TotalFiles}, ${script:HeadersFound}, ${script:NoHeader})
            } else {
                ${lblStatus}.Text = "Completed with errors. Check log."
            }
        } catch {
            Handle-Error -ErrorMessage "GUI run failed: $($_.Exception.Message)" -ShowMessageBox
            Update-LogView
        }
    })

    [void]${form}.ShowDialog()
}

# ---------------------------- MAIN ----------------------------
try {
    Initialize-Log -Directory ${script:LogDir}

    if (-not ${ShowConsole}) { Set-ConsoleVisibility -Visible $false }

    Write-Log -Message "Starting ${script:ScriptName}" -Level 'INFO'
    Write-Log -Message ("Parameters - RootFolder='{0}', ShowConsole={1}, AllowLineCommentHeaders={2}" -f ${RootFolder}, ${ShowConsole}, ${AllowLineCommentHeaders}) -Level 'INFO'

    if (Test-IsWindows) {
        if (-not [string]::IsNullOrWhiteSpace(${RootFolder})) {
            ${out} = Start-HeaderExtraction -RootFolder ${RootFolder}
            if (${out}) { Write-Output ${out} }
        } else {
            Show-GUI
        }
    } else {
        if ([string]::IsNullOrWhiteSpace(${RootFolder})) {
            Handle-Error -ErrorMessage "GUI is not supported on non-Windows. Provide -RootFolder for CLI mode." -ShowMessageBox:$false
            throw "RootFolder is required for CLI mode on non-Windows."
        }

        ${out} = Start-HeaderExtraction -RootFolder ${RootFolder}
        if (${out}) { Write-Output ${out} }
    }
} catch {
    Handle-Error -ErrorMessage "Fatal error: $($_.Exception.Message)" -ShowMessageBox
} finally {
    try { Finalize-Log } catch {}
}

# End of Script
