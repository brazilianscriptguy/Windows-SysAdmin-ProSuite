[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$Path = $PSScriptRoot,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputName = "output",

    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path (Split-Path $_ -Parent) -PathType Container })]
    [string]$LogPath = (Join-Path $env:LOCALAPPDATA "ScriptLogs")
)

begin {
    #region --- Initialization ---
    $ScriptName = $MyInvocation.MyCommand.Name
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $LogFile = Join-Path $LogPath "$ScriptName-$Timestamp.log"
    $global:LogContent = [System.Collections.Concurrent.ConcurrentBag[string]]::new()

    # Ensure log directory exists
    if (-not (Test-Path $LogPath)) {
        try {
            New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
            Write-Log "Created log directory: $LogPath"
        } catch {
            Write-Error "Failed to create log directory: $_"
            exit 1
        }
    }

    # Logging function
    function Write-Log {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Message,
            [Parameter(Mandatory = $false)]
            [ValidateSet("INFO", "WARNING", "ERROR")]
            [string]$Level = "INFO",
            [Parameter(Mandatory = $false)]
            [string]$LogDirectory = $LogPath
        )
        $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
        Add-Content -Path $LogFile -Value $logEntry -ErrorAction Stop
        $global:LogContent.Add($logEntry)
        if ($Level -eq "ERROR") {
            Write-Error $logEntry
        } elseif ($VerbosePreference -eq 'Continue') {
            Write-Verbose $logEntry
        }
    }

    Write-Log "Starting $ScriptName"
    Write-Log "Parameters - Path: $Path, OutputName: $OutputName, LogPath: $LogPath"
    #endregion
}

process {
    if ($PSVersionTable.Platform -eq "Win32NT") {
        Show-GUI
    } else {
        Write-Warning "GUI not supported on non-Windows platforms. Running in CLI mode."
        Execute-Task
    }
}

end {
    Write-Log "Completed $ScriptName execution"
}

#region --- GUI Functions ---
function Show-GUI {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$ScriptName v1.0"
    $form.Size = New-Object System.Drawing.Size(400, 300)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = 'FixedSingle'

    $labelPath = New-Object System.Windows.Forms.Label
    $labelPath.Text = "Working Path:"
    $labelPath.Location = New-Object System.Drawing.Point(10, 20)
    $labelPath.Size = New-Object System.Drawing.Size(100, 20)
    $form.Controls.Add($labelPath)

    $textBoxPath = New-Object System.Windows.Forms.TextBox
    $textBoxPath.Text = $Path
    $textBoxPath.Location = New-Object System.Drawing.Point(120, 20)
    $textBoxPath.Size = New-Object System.Drawing.Size(250, 20)
    $form.Controls.Add($textBoxPath)

    $labelOutputName = New-Object System.Windows.Forms.Label
    $labelOutputName.Text = "Output Name:"
    $labelOutputName.Location = New-Object System.Drawing.Point(10, 50)
    $labelOutputName.Size = New-Object System.Drawing.Size(100, 20)
    $form.Controls.Add($labelOutputName)

    $textBoxOutputName = New-Object System.Windows.Forms.TextBox
    $textBoxOutputName.Text = $OutputName
    $textBoxOutputName.Location = New-Object System.Drawing.Point(120, 50)
    $textBoxOutputName.Size = New-Object System.Drawing.Size(250, 20)
    $form.Controls.Add($textBoxOutputName)

    $labelLogPath = New-Object System.Windows.Forms.Label
    $labelLogPath.Text = "Log Path:"
    $labelLogPath.Location = New-Object System.Drawing.Point(10, 80)
    $labelLogPath.Size = New-Object System.Drawing.Size(100, 20)
    $form.Controls.Add($labelLogPath)

    $textBoxLogPath = New-Object System.Windows.Forms.TextBox
    $textBoxLogPath.Text = $LogPath
    $textBoxLogPath.Location = New-Object System.Drawing.Point(120, 80)
    $textBoxLogPath.Size = New-Object System.Drawing.Size(250, 20)
    $form.Controls.Add($textBoxLogPath)

    $buttonRun = New-Object System.Windows.Forms.Button
    $buttonRun.Text = "Execute Task"
    $buttonRun.Location = New-Object System.Drawing.Point(150, 120)
    $buttonRun.Size = New-Object System.Drawing.Size(100, 30)
    $buttonRun.Add_Click({
        $script:Path = $textBoxPath.Text
        $script:OutputName = $textBoxOutputName.Text
        $script:LogPath = $textBoxLogPath.Text
        $LogFile = Join-Path $LogPath "$ScriptName-$Timestamp.log"
        Execute-Task
        Update-LogView
    })
    $form.Controls.Add($buttonRun)

    $labelLog = New-Object System.Windows.Forms.Label
    $labelLog.Text = "Log Output:"
    $labelLog.Location = New-Object System.Drawing.Point(10, 160)
    $labelLog.Size = New-Object System.Drawing.Size(100, 20)
    $form.Controls.Add($labelLog)

    $textBoxLog = New-Object System.Windows.Forms.TextBox
    $textBoxLog.Multiline = $true
    $textBoxLog.ScrollBars = "Vertical"
    $textBoxLog.ReadOnly = $true
    $textBoxLog.Location = New-Object System.Drawing.Point(10, 180)
    $textBoxLog.Size = New-Object System.Drawing.Size(360, 100)
    $form.Controls.Add($textBoxLog)

    function Update-LogView {
        $textBoxLog.Text = ($global:LogContent | Sort-Object | ForEach-Object { $_ }) -join "`r`n"
    }

    [void]$form.ShowDialog()
}

function Execute-Task {
    try {
        #region --- CUSTOM_TASK ---
        Write-Log "Executing custom task with OutputName: $OutputName in $Path"
        $fullPath = Join-Path $Path "$OutputName.txt"
        if (Test-Path $fullPath) {
            Write-Log "Output $fullPath already exists. Overwriting." -Level "WARNING"
        }
        "This is a sample output created on $(Get-Date)" | Out-File -FilePath $fullPath -Force
        Write-Log "Successfully created output: $fullPath"
        #endregion
    } catch {
        Write-Log "Error occurred: $_" -Level "ERROR"
        throw
    }
}
#endregion
