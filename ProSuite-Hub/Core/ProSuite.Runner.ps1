# ProSuite-Hub\Core\ProSuite.Runner.ps1
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "ProSuite.Helpers.ps1")
. (Join-Path $PSScriptRoot "ProSuite.Logging.ps1")

function Invoke-ProSuiteToolProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Tool,
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$HubLogDir,
        [switch]$RunAsAdmin,
        [scriptblock]$OnOutput,
        [scriptblock]$OnCompleted
    )

    $toolPath = Join-Path $RepoRoot $Tool.path
    if (-not (Test-Path -LiteralPath $toolPath)) {
        if ($OnCompleted) { & $OnCompleted.Invoke($false, $null, "Tool file not found: $toolPath") }
        return
    }

    $hubLog = New-HubLogFile -HubLogDir $HubLogDir -ToolId $Tool.id
    Write-HubLog -Path $hubLog -Level INFO -Message ("Start: {0} | {1}" -f $Tool.name, $Tool.path)

    $ext = [IO.Path]::GetExtension($toolPath).ToLowerInvariant()

    # Decide executor
    $exe = $null
    $args = $null

    switch ($ext) {
        ".ps1" {
            $exe = "powershell.exe"
            $args = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$toolPath)
        }
        ".vbs" {
            $exe = "cscript.exe"
            $args = @("//nologo",$toolPath)
        }
        ".hta" {
            $exe = "mshta.exe"
            $args = @($toolPath)
        }
        default {
            Write-HubLog -Path $hubLog -Level ERROR -Message "Unsupported extension: $ext"
            if ($OnCompleted) { & $OnCompleted.Invoke($false, $hubLog, "Unsupported file type: $ext") }
            return
        }
    }

    $needsElevation = $false
    if ($RunAsAdmin) { $needsElevation = $true }
    elseif ($Tool.requiresAdmin -eq $true -and -not (Test-IsAdmin)) { $needsElevation = $true }

    if ($needsElevation) {
        Write-HubLog -Path $hubLog -Level WARN -Message "Launching elevated (RunAs)."
        try {
            $argLine = ($args | ForEach-Object { if ($_ -match '\s') { '"{0}"' -f $_ } else { $_ } }) -join ' '
            Start-Process -FilePath $exe -ArgumentList $argLine -Verb RunAs | Out-Null
            if ($OnOutput) { & $OnOutput.Invoke("INFO: Process launched elevated.`r`n") }
            if ($OnCompleted) { & $OnCompleted.Invoke($true, $hubLog, $null) }
        } catch {
            Write-HubLog -Path $hubLog -Level ERROR -Message ("RunAs failed: {0}" -f ($_ | Out-String))
            if ($OnCompleted) { & $OnCompleted.Invoke($false, $hubLog, "RunAs failed.") }
        }
        return
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = ($args | ForEach-Object { if ($_ -match '\s') { '"{0}"' -f $_ } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $p.EnableRaisingEvents = $true

    $stdOutHandler = [System.Diagnostics.DataReceivedEventHandler]{
        param($sender,$e)
        if ([string]::IsNullOrWhiteSpace($e.Data)) { return }
        Write-HubLog -Path $hubLog -Level INFO -Message $e.Data
        if ($OnOutput) { & $OnOutput.Invoke(($e.Data + "`r`n")) }
    }

    $stdErrHandler = [System.Diagnostics.DataReceivedEventHandler]{
        param($sender,$e)
        if ([string]::IsNullOrWhiteSpace($e.Data)) { return }
        Write-HubLog -Path $hubLog -Level ERROR -Message $e.Data
        if ($OnOutput) { & $OnOutput.Invoke(("ERROR: " + $e.Data + "`r`n")) }
    }

    $exitHandler = {
        try {
            $code = $p.ExitCode
            if ($code -eq 0) {
                Write-HubLog -Path $hubLog -Level INFO -Message "Completed. ExitCode=0"
                if ($OnCompleted) { & $OnCompleted.Invoke($true, $hubLog, $null) }
            } else {
                Write-HubLog -Path $hubLog -Level ERROR -Message ("Completed with errors. ExitCode={0}" -f $code)
                if ($OnCompleted) { & $OnCompleted.Invoke($false, $hubLog, "ExitCode=$code") }
            }
        } catch {
            Write-HubLog -Path $hubLog -Level ERROR -Message ("Exit handler error: {0}" -f ($_|Out-String))
            if ($OnCompleted) { & $OnCompleted.Invoke($false, $hubLog, "Exit handler error.") }
        }
    }

    try {
        if (-not $p.Start()) {
            Write-HubLog -Path $hubLog -Level ERROR -Message "Process failed to start."
            if ($OnCompleted) { & $OnCompleted.Invoke($false, $hubLog, "Process failed to start.") }
            return
        }

        $p.add_OutputDataReceived($stdOutHandler)
        $p.add_ErrorDataReceived($stdErrHandler)
        $p.add_Exited($exitHandler)

        $p.BeginOutputReadLine()
        $p.BeginErrorReadLine()

        if ($OnOutput) { & $OnOutput.Invoke(("INFO: Running... ({0})`r`n" -f $exe)) }
    } catch {
        Write-HubLog -Path $hubLog -Level ERROR -Message ("Exception starting process: {0}" -f ($_|Out-String))
        if ($OnCompleted) { & $OnCompleted.Invoke($false, $hubLog, "Exception starting process.") }
    }
}
