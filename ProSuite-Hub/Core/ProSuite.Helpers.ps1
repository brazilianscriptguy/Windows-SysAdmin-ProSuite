# ProSuite-Hub\Core\ProSuite.Helpers.ps1
Set-StrictMode -Version Latest

function Get-RepoRoot {
    [CmdletBinding()]
    param()
    # RepoRoot = pasta pai de ProSuite-Hub
    return (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}

function Get-RelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FullPath,
        [Parameter(Mandatory)][string]$BasePath
    )
    $base = $BasePath.TrimEnd('\')
    $p = $FullPath
    if ($p.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $p.Substring($base.Length).TrimStart('\')
    }
    return $FullPath
}

function Read-JsonFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JSON file not found: $Path"
    }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-NearestReadme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StartDirectory,
        [Parameter(Mandatory)][string]$RepoRoot
    )

    $dir = $StartDirectory
    while ($dir -and ($dir.Length -ge $RepoRoot.Length)) {
        $candidate = Join-Path $dir "README.md"
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
        if ($dir -ieq $RepoRoot) { break }
        $dir = Split-Path -Parent $dir
    }

    $rootReadme = Join-Path $RepoRoot "README.md"
    if (Test-Path -LiteralPath $rootReadme) { return $rootReadme }
    return $null
}

function Test-IsAdmin {
    [CmdletBinding()]
    param()
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Infer-RequiresAdmin {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptPath
    )

    # Heurística conservadora (você pode evoluir depois)
    try {
        $head = Get-Content -LiteralPath $ScriptPath -TotalCount 220 -ErrorAction Stop
        $t = ($head -join "`n")
        if ($t -match '(?i)\bHKLM:\\|\bSet-ItemProperty\b|\bNew-Service\b|\bRestart-Service\b|\bStop-Service\b|\bsc\.exe\b|\bnetsh\b|\bwbadmin\b|\bAdd-Computer\b|\bSet-DnsServer\b|\bSet-ExecutionPolicy\b|\bEnable-PSRemoting\b|\bWSUS\b|\bSet-GPRegistryValue\b|\bNew-GPO\b|\bImport-GPO\b|\bDnsServer\b|\bDhcpServer\b') {
            return $true
        }
    } catch { }
    return $false
}

function Try-ExtractSynopsis {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ScriptPath)

    try {
        $content = Get-Content -LiteralPath $ScriptPath -TotalCount 120 -ErrorAction Stop
        $text = ($content -join "`n")
        if ($text -match '(?is)\.SYNOPSIS\s*(.+?)\r?\n\s*\.') {
            return (($Matches[1] -replace '\r','') -replace '^\s+|\s+$','')
        }
    } catch { }
    return ""
}
