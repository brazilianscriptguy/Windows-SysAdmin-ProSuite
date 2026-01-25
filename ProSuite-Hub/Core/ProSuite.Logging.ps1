# ProSuite-Hub\Core\ProSuite.Logging.ps1
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "ProSuite.Helpers.ps1")

function Ensure-Directory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function New-HubLogFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$HubLogDir,
        [Parameter(Mandatory)][string]$ToolId
    )
    Ensure-Directory -Path $HubLogDir
    $safe = ($ToolId -replace '[^\w\.-]', '_')
    $ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
    return (Join-Path $HubLogDir ("{0}_{1}.log" -f $safe, $ts))
}

function Write-HubLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")][string]$Level = "INFO"
    )
    $line = "[{0}] [{1}] {2}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
}

function Show-MessageBox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [ValidateSet("Info", "Warning", "Error")][string]$Type = "Info",
        [string]$Title = "Windows SysAdmin ProSuite"
    )
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    switch ($Type) {
        "Info" { $icon = [System.Windows.Forms.MessageBoxIcon]::Information }
        "Warning" { $icon = [System.Windows.Forms.MessageBoxIcon]::Warning }
        "Error" { $icon = [System.Windows.Forms.MessageBoxIcon]::Error }
    }
    [System.Windows.Forms.MessageBox]::Show(
        $Text, $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $icon
    ) | Out-Null
}
