# ProSuite-Hub\Generate-Manifest.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Core\ProSuite.Helpers.ps1")

$repoRoot = Get-RepoRoot
$settings = Read-JsonFile -Path (Join-Path $PSScriptRoot "Settings.json")

$roots = @($settings.index.roots)
$includeExt = @($settings.index.includeExtensions)
$excludePrefixes = @($settings.index.excludePrefixes)
$includePrefixes = @($settings.index.includePrefixes)

function Should-IncludePath {
    param([string]$relativePath)

    # Normaliza para backslash
    $rp = $relativePath -replace '/', '\'

    # Se estiver em um include explícito, inclui
    foreach ($inc in $includePrefixes) {
        if ($rp.StartsWith($inc, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    # Se estiver em um exclude, exclui
    foreach ($ex in $excludePrefixes) {
        if ($rp.StartsWith($ex, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }

    return $true
}

$tools = New-Object System.Collections.Generic.List[object]

foreach ($r in $roots) {
    $rootPath = Join-Path $repoRoot $r
    if (-not (Test-Path -LiteralPath $rootPath)) { continue }

    Get-ChildItem -LiteralPath $rootPath -Recurse -File |
        Where-Object {
            $ext = $_.Extension.ToLowerInvariant()
            $includeExt -contains $ext
        } |
        ForEach-Object {
            $rel = Get-RelativePath -FullPath $_.FullName -BasePath $repoRoot
            $rel = $rel -replace '/', '\'

            if (-not (Should-IncludePath -relativePath $rel)) { return }

            # Domain e Module
            $parts = $rel.Split('\')
            $domain = $parts[0]
            $module = if ($parts.Length -ge 2) { $parts[1] } else { $domain }

            # Ajuste específico: ITSM WKS Support Tools
            $uiModule = $module
            if ($rel.StartsWith("ITSM-Templates-WKS\Assets\AdditionalSupportScipts\", [System.StringComparison]::OrdinalIgnoreCase)) {
                $uiModule = "Support Tools"
            }

            $id = ($rel -replace '\\','-')
            $id = $id.ToLower() -replace '[^\w\-\.]','-'

            $requiresAdmin = $false
            if ($_.Extension.ToLowerInvariant() -eq ".ps1") {
                $requiresAdmin = Infer-RequiresAdmin -ScriptPath $_.FullName
            } else {
                # VBS/HTA em geral são “assistivos”, mas você pode ajustar depois
                $requiresAdmin = $false
            }

            $synopsis = ""
            if ($_.Extension.ToLowerInvariant() -eq ".ps1") {
                $synopsis = Try-ExtractSynopsis -ScriptPath $_.FullName
            }

            $readme = Get-NearestReadme -StartDirectory $_.DirectoryName -RepoRoot $repoRoot
            $readmeRel = if ($readme) { Get-RelativePath -FullPath $readme -BasePath $repoRoot } else { $null }

            $tools.Add([pscustomobject]@{
                id            = $id
                name          = $_.BaseName
                domain        = $domain
                module        = $uiModule
                modulePath    = $module
                type          = $_.Extension.TrimStart('.').ToUpper()
                path          = $rel
                requiresAdmin = $requiresAdmin
                synopsis      = $synopsis
                readmePath    = $readmeRel
            })
        }
}

$manifest = [pscustomobject]@{
    app = [pscustomobject]@{
        name      = $settings.appName
        version   = "0.1.0"
        hubLogDir = $settings.hubLogDir
        generated = (Get-Date).ToString("s")
    }
    tools = $tools | Sort-Object domain, module, name
}

$out = Join-Path $PSScriptRoot "Manifest.json"
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $out -Encoding UTF8

Write-Host "Manifest generated: $out"
Write-Host ("Tools indexed: {0}" -f $tools.Count)
