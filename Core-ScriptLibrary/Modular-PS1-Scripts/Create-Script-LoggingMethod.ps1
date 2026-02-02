# ==================================================================================================
# ENTERPRISE LOGGING (Windows-SysAdmin-ProSuite STANDARD)
# - Single log file per run (no per-call file creation)
# - Default log directory: C:\Logs-TEMP
# - GUI-friendly: optional MessageBox helpers; avoids noisy console output by default
# - Supports -Verbose, -Debug, and -WhatIf semantics (log includes tags)
# ==================================================================================================

# ---- Global log context (initialize once per script run) ----
${script:ScriptName} = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
${script:LogDir}     = 'C:\Logs-TEMP'
${script:StartStamp} = (Get-Date -Format 'yyyyMMdd_HHmmss')
${script:LogPath}    = $null

function Initialize-Log {
    param(
        [Parameter(Mandatory=$false)]
        [string]${LogDirectory} = 'C:\Logs-TEMP',

        [Parameter(Mandatory=$false)]
        [string]${LogFileName} = $null
    )

    ${script:LogDir} = ${LogDirectory}

    if (-not (Test-Path -LiteralPath ${script:LogDir})) {
        New-Item -Path ${script:LogDir} -ItemType Directory -Force | Out-Null
    }

    if ([string]::IsNullOrWhiteSpace(${LogFileName})) {
        ${LogFileName} = "${script:ScriptName}.log"
    }

    ${script:LogPath} = Join-Path ${script:LogDir} ${LogFileName}

    Write-Log -Message "==== Session started ====" -Level 'INFO'
    Write-Log -Message "Script: ${script:ScriptName}" -Level 'INFO'
    Write-Log -Message "LogPath: ${script:LogPath}" -Level 'INFO'
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]${Message},

        [Parameter(Mandatory=$false)]
        [ValidateSet('INFO','WARN','ERROR','SUCCESS','DEBUG')]
        [string]${Level} = 'INFO',

        [Parameter(Mandatory=$false)]
        [switch]${AsWhatIf},

        [Parameter(Mandatory=$false)]
        [int]${PercentComplete} = -1,

        [Parameter(Mandatory=$false)]
        [string]${Activity} = 'Processing'
    )

    if ([string]::IsNullOrWhiteSpace(${script:LogPath})) {
        # Fail-safe: initialize log if caller forgot
        ${fallbackDir} = 'C:\Logs-TEMP'
        if (-not (Test-Path -LiteralPath ${fallbackDir})) {
            New-Item -Path ${fallbackDir} -ItemType Directory -Force | Out-Null
        }
        ${script:LogPath} = Join-Path ${fallbackDir} "${script:ScriptName}.log"
    }

    ${ts} = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    ${tag} = if (${AsWhatIf}) { 'WHAT-IF' } else { ${Level} }
    ${entry} = "[${ts}] [${tag}] ${Message}"

    try {
        Add-Content -Path ${script:LogPath} -Value ${entry} -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Last resort: do not throw hard; avoid breaking operational scripts
        try { Write-Warning "Failed to write log entry: $($_.Exception.Message)" } catch {}
    }

    # Optional progress updates (only if caller provides a valid percent)
    if (${PercentComplete} -ge 0 -and ${PercentComplete} -le 100) {
        try {
            Write-Progress -Activity ${Activity} -Status ${Message} -PercentComplete ${PercentComplete}
        } catch {}
    }

    # Console behavior: keep quiet unless operator requested -Verbose / -Debug
    switch (${Level}) {
        'ERROR' {
            try { Write-Error ${entry} } catch {}
        }
        'WARN' {
            try { Write-Warning ${entry} } catch {}
        }
        'DEBUG' {
            if ($PSBoundParameters.ContainsKey('Debug') -or $DebugPreference -eq 'Continue') {
                try { Write-Debug ${entry} } catch {}
            }
        }
        default {
            if ($VerbosePreference -eq 'Continue') {
                try { Write-Verbose ${entry} } catch {}
            }
        }
    }
}

function Finalize-Log {
    Write-Log -Message "==== Session ended ====" -Level 'INFO'
}

# ---- GUI-friendly message helpers (optional) ----
function Show-InfoBox {
    param([Parameter(Mandatory=$true)][string]${Message})
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [void][System.Windows.Forms.MessageBox]::Show(${Message}, 'Information', 'OK', 'Information')
    } catch {}
}

function Show-ErrorBox {
    param([Parameter(Mandatory=$true)][string]${Message})
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [void][System.Windows.Forms.MessageBox]::Show(${Message}, 'Error', 'OK', 'Error')
    } catch {}
}

function Handle-Error {
    param(
        [Parameter(Mandatory=$true)]
        [string]${ErrorMessage},

        [Parameter(Mandatory=$false)]
        [switch]${ShowMessageBox},

        [Parameter(Mandatory=$false)]
        [string]${Context} = $null
    )

    ${msg} = if ([string]::IsNullOrWhiteSpace(${Context})) { ${ErrorMessage} } else { "${Context}: ${ErrorMessage}" }
    Write-Log -Message ${msg} -Level 'ERROR'

    if (${ShowMessageBox}) {
        Show-ErrorBox -Message ${msg}
    }
}

# ==================================================================================================
# EXAMPLE USAGE (remove from production scripts)
# ==================================================================================================
# Initialize-Log
# $VerbosePreference = 'Continue'
# Write-Log -Message "Script execution started" -Level 'INFO'
# Write-Log -Message "Processing task..." -Level 'INFO' -PercentComplete 10 -Activity 'Demo'
# Write-Log -Message "Debugging variable X=123" -Level 'DEBUG'
# Handle-Error -ErrorMessage "Test error occurred" -ShowMessageBox -Context 'DemoStep'
# Finalize-Log
