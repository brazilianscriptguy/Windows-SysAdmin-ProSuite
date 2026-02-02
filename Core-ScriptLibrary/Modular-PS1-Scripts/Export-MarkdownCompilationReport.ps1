<#
.SYNOPSIS
    Combines all Markdown (.md) files under a root folder into a single compilation report file.

.DESCRIPTION
    Scans a root directory recursively for *.md files (with exclude patterns), generates a deterministic
    compilation output (TOC + per-file headers + content), and writes it as UTF-8 (no BOM).

    Enterprise standards applied:
    - Set-StrictMode + $ErrorActionPreference = 'Stop'
    - Guard clauses + PS 5.1-safe path handling
    - Count-safe enumeration
    - Deterministic ordering
    - No Write-Host (uses Write-Verbose / Write-Warning / Write-Error)
    - Robust file reading (UTF8 -> Default -> Unicode fallback)
    - Safe StreamWriter usage + flush + dispose
    - Optional file size cap per Markdown file to prevent runaway outputs

.NOTES
    - Output file is created (overwritten) at the resolved path.
    - Excludes: .git, node_modules by default (customizable).
    - Designed to run on Windows PowerShell 5.1 and PowerShell 7+.

.PARAMETER Root
    Root directory to scan. Defaults to current location.

.PARAMETER OutputFile
    Output file name or full path. If relative, it is created under Root.

.PARAMETER ExcludePathRegex
    One or more regex patterns applied to FULL PATH to exclude matches.

.PARAMETER MaxFileBytes
    Maximum bytes to read per markdown file. Files larger than this will be truncated in output.

.EXAMPLE
    .\Combine-Markdown.ps1 -Root "D:\Repo" -OutputFile "All-Markdown-Files-Combined.txt" -Verbose

.EXAMPLE
    .\Combine-Markdown.ps1 -Root "D:\Repo" -OutputFile "D:\Exports\md_dump.txt" -MaxFileBytes 2097152
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$Root = (Get-Location).Path,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputFile = "All-Markdown-Files-Combined.txt",

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludePathRegex = @(
        '\\\.git\\',
        '\\node_modules\\'
    ),

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 2147483647)]
    [int]$MaxFileBytes = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Base,
        [Parameter(Mandatory = $true)][string]$Full
    )

    $basePath = (Resolve-Path -LiteralPath $Base).Path.TrimEnd('\')
    $fullPath = (Resolve-Path -LiteralPath $Full).Path

    if ($fullPath.StartsWith($basePath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($basePath.Length).TrimStart('\')
    }
    return $fullPath
}

function Test-IsExcludedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FullPath,
        [Parameter(Mandatory = $true)][string[]]$RegexList
    )

    foreach ($rx in $RegexList) {
        if ([string]::IsNullOrWhiteSpace($rx)) { continue }
        if ($FullPath -match $rx) { return $true }
    }
    return $false
}

function Read-TextFileSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $false)][int]$MaxBytes = 0
    )

    # MaxBytes=0 => read all
    # Keep it simple and robust: try encodings in order.
    $encodings = @('utf8', 'default', 'unicode')

    foreach ($enc in $encodings) {
        try {
            if ($MaxBytes -gt 0) {
                # Read at most MaxBytes bytes, then decode
                $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                try {
                    $len = [int][math]::Min($MaxBytes, $fs.Length)
                    $buf = New-Object byte[] $len
                    $read = $fs.Read($buf, 0, $len)

                    if ($read -le 0) { return "" }

                    if ($read -ne $len) {
                        $buf2 = New-Object byte[] $read
                        [Array]::Copy($buf, $buf2, $read)
                        $buf = $buf2
                    }

                    switch ($enc) {
                        'utf8' { return ([System.Text.Encoding]::UTF8.GetString($buf)) }
                        'default' { return ([System.Text.Encoding]::Default.GetString($buf)) }
                        'unicode' { return ([System.Text.Encoding]::Unicode.GetString($buf)) }
                    }
                } finally {
                    $fs.Dispose()
                }
            } else {
                return Get-Content -LiteralPath $Path -Raw -Encoding $enc
            }
        } catch {
            continue
        }
    }

    # last resort (should rarely happen)
    return Get-Content -LiteralPath $Path -Raw
}

function Resolve-OutputPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RootResolved,
        [Parameter(Mandatory = $true)][string]$OutputFile
    )

    if ([System.IO.Path]::IsPathRooted($OutputFile)) {
        return $OutputFile
    }
    return (Join-Path -Path $RootResolved -ChildPath $OutputFile)
}

# ---------------------------- MAIN ----------------------------

$sep = '=' * 80
$sepMinor = '-' * 40
$now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

$rootResolved = (Resolve-Path -LiteralPath $Root).Path
$outFull = Resolve-OutputPath -RootResolved $rootResolved -OutputFile $OutputFile

Write-Verbose ("Root: {0}" -f $rootResolved)
Write-Verbose ("Output (full): {0}" -f $outFull)

# Enumerate markdown files deterministically
$mdFiles = @(
    Get-ChildItem -LiteralPath $rootResolved -Recurse -File -Filter '*.md' -Force -ErrorAction Stop |
        Where-Object { -not (Test-IsExcludedPath -FullPath $_.FullName -RegexList $ExcludePathRegex) } |
        Sort-Object -Property FullName
)

# Ensure output directory exists
$outDir = Split-Path -Path $outFull -Parent
if (-not (Test-Path -LiteralPath $outDir -PathType Container)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

# Overwrite safely
if (Test-Path -LiteralPath $outFull) {
    Remove-Item -LiteralPath $outFull -Force
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$fs = $null
$sw = $null

try {
    $fs = [System.IO.File]::Open($outFull, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    $sw = New-Object System.IO.StreamWriter($fs, $utf8NoBom)

    # Header
    $sw.WriteLine("MARKDOWN FILES COMPILATION REPORT")
    $sw.WriteLine("Generated on: $now")
    $sw.WriteLine("Search Path: $rootResolved")
    $sw.WriteLine($sep)
    $sw.WriteLine()

    # Summary
    $sw.WriteLine("SUMMARY:")
    $sw.WriteLine(("- Total .md files found: {0}" -f @($mdFiles).Count))

    $totalBytes = 0L
    if (@($mdFiles).Count -gt 0) {
        $totalBytes = [int64](($mdFiles | Measure-Object Length -Sum).Sum)
    }
    $totalKb = [math]::Round(($totalBytes / 1KB), 2)
    $sw.WriteLine(("- Total size: {0} KB" -f $totalKb))

    if ($MaxFileBytes -gt 0) {
        $sw.WriteLine(("- MaxFileBytes: {0} bytes (files may be truncated)" -f $MaxFileBytes))
    } else {
        $sw.WriteLine("- MaxFileBytes: unlimited")
    }

    $sw.WriteLine("- Search completed: $now")
    $sw.WriteLine()
    $sw.WriteLine($sep)
    $sw.WriteLine()
    $sw.WriteLine("TABLE OF CONTENTS:")

    for ($i = 0; $i -lt @($mdFiles).Count; $i++) {
        $rel = Get-RelativePath -Base $rootResolved -Full $mdFiles[$i].FullName
        $sw.WriteLine(("{0}. {1} - {2}" -f ($i + 1), $mdFiles[$i].Name, $rel))
    }

    $sw.WriteLine()
    $sw.WriteLine($sep)
    $sw.WriteLine()

    # Body
    for ($i = 0; $i -lt @($mdFiles).Count; $i++) {
        $f = $mdFiles[$i]
        $rel = Get-RelativePath -Base $rootResolved -Full $f.FullName

        $sw.WriteLine($sep)
        $sw.WriteLine(("FILE #{0}: {1}" -f ($i + 1), $f.Name))
        $sw.WriteLine($sep)
        $sw.WriteLine(("FULL PATH: {0}" -f $f.FullName))
        $sw.WriteLine(("RELATIVE PATH: {0}" -f $rel))
        $sw.WriteLine(("CREATED:  {0:yyyy-MM-dd HH:mm:ss}" -f $f.CreationTime))
        $sw.WriteLine(("MODIFIED: {0:yyyy-MM-dd HH:mm:ss}" -f $f.LastWriteTime))
        $sw.WriteLine(("SIZE: {0:N2} KB ({1} bytes)" -f ($f.Length / 1KB), $f.Length))
        $sw.WriteLine(("FILE NUMBER: {0} of {1}" -f ($i + 1), @($mdFiles).Count))
        $sw.WriteLine($sep)
        $sw.WriteLine()

        if ($f.Length -eq 0) {
            $sw.WriteLine("[FILE IS EMPTY]")
        } else {
            $content = Read-TextFileSafe -Path $f.FullName -MaxBytes $MaxFileBytes
            $content = $content -replace "`r`n", "`n" -replace "`r", "`n"

            if ($MaxFileBytes -gt 0 -and $f.Length -gt $MaxFileBytes) {
                $sw.WriteLine("[NOTE] File was truncated due to MaxFileBytes limit.")
                $sw.WriteLine()
            }

            $sw.WriteLine($content.TrimEnd())
        }

        $sw.WriteLine()
        $sw.WriteLine($sepMinor)
        $sw.WriteLine()
    }

    $sw.WriteLine($sep)
    $sw.WriteLine("END OF DOCUMENT")
    $sw.WriteLine($sep)

    $sw.Flush()
    $fs.Flush($true)
}
finally {
    if ($sw) { $sw.Dispose() }
    if ($fs) { $fs.Dispose() }
}

# Verification (no Write-Host; return object + verbose)
if (Test-Path -LiteralPath $outFull) {
    $fi = Get-Item -LiteralPath $outFull
    Write-Verbose ("OK: created {0} ({1} KB)" -f $fi.FullName, ([math]::Round($fi.Length / 1KB, 2)))

    # Return a useful object
    [PSCustomObject]@{
        Root = $rootResolved
        OutputPath = $fi.FullName
        MdFiles = @($mdFiles).Count
        TotalBytes = $totalBytes
        OutputBytes = $fi.Length
        MaxFileBytes = $MaxFileBytes
        GeneratedOn = $now
    }
} else {
    Write-Error ("FAILED: file not found after write: {0}" -f $outFull)
}
