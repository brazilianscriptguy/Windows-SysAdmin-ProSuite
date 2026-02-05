<#
.SYNOPSIS
    <One-line purpose (imperative + outcome).>

.DESCRIPTION
    <What this script does, in plain terms, for enterprise operations.>
    This script is part of the Windows-SysAdmin-ProSuite toolset and is designed to be:
    - Operator-friendly (GUI-first where applicable, minimal console reliance)
    - Auditable (structured logging under C:\Logs-TEMP)
    - Safe-by-default (validation, clear errors, and optional WhatIf)
    - Compatible with Windows Server / Windows 10/11 enterprise environments

.FEATURES
    - GUI-first workflow (Windows Forms) with fixed, aligned controls (no truncated buttons).
    - Structured log output to C:\Logs-TEMP\<ScriptName>.log (append-only session markers).
    - Clear user feedback via MessageBox (Info/Warn/Error), console hidden by default.
    - Robust error handling (try/catch with actionable messages; no silent failures).
    - Optional safe execution switches (e.g., -WhatIf) for change-impact review.
    - Optional CSV export to user's Documents folder for reporting and audit trails.

.PARAMETERS
    -DomainFqdn <String>
        Target domain FQDN (e.g., "SEDE.TJAP"). When omitted in GUI mode, selectable from forest domains.

    -OutputDir <String>
        Output directory for logs and artifacts. Default: C:\Logs-TEMP

    -ExportCsv <Switch>
        If set, exports the main report to CSV in the current user's Documents folder.

    -WhatIf <Switch>
        If set, performs a dry-run (no changes). Actions are logged as [WHAT-IF].

    -ShowConsole <Switch>
        If set, keeps the PowerShell console visible (useful for debugging).
        Default behavior is to hide the console for GUI-focused tools.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    1.0 - 2026-02-02

.NOTES
    Requirements:
    - PowerShell 5.1+ (Windows PowerShell). Compatible with PowerShell 7+ where modules support it.
    - RSAT/ActiveDirectory or other modules as required by the script’s scope.
    - Administrator privileges may be required depending on actions performed.

    Logging:
    - Log file: C:\Logs-TEMP\<ScriptName>.log
    - Recommended to run from an elevated session when making directory/service/AD changes.

    Design standards (ProSuite):
    - StrictMode enabled; predictable error behavior; no Write-Host for operational logs.
    - GUI buttons aligned and sized to avoid truncation (fixed layout math).
    - Prefer -Identity over -Filter when an exact identifier is available.

.EXAMPLES
    Example 1: Default GUI execution (recommended)
    ```powershell
    .\ScriptName.ps1
    ```

    Example 2: CLI mode with CSV export and WhatIf
    ```powershell
    .\ScriptName.ps1 -DomainFqdn "SEDE.TJAP" -ExportCsv -WhatIf
    ```

    Example 3: Keep console visible for troubleshooting
    ```powershell
    .\ScriptName.ps1 -ShowConsole
    ```
#>

