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
    [string]$LogPath = (Join-Path $env:LOCALAPPDATA "ScriptLogs"),
    
    [Parameter(Mandatory = $false)]
    [switch]$ShowConsole
)

begin {
    #region --- Initialization ---
    $ScriptName = $MyInvocation.MyCommand.Name
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $LogFile = Join-Path $LogPath "$ScriptName-$Timestamp.log"
    $global:LogContent = [System.Collections.Concurrent.ConcurrentBag[string]]::new()

    # Hide console if not requested
    if (-not $ShowConsole -and $PSVersionTable.Platform -eq "Win32NT") {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() {
        var handle = GetConsoleWindow();
        ShowWindow(handle, 0);
    }
}
"@
        [Window]::Hide()
    }

    # Ensure log directory exists
    if (-not (Test-Path $LogPath)) {
        try {
            New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
            Write-Log "Created log directory: $LogPath"
        } catch {
            Handle-Error "Failed to create log directory: $_" -ShowMessageBox
            exit 1
        }
    }

    # Logging function
    function Write-Log {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Message,
            [Parameter(Mandatory = $false)]
            [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")]
            [string]$Level = "INFO",
            [Parameter(Mandatory = $false)]
            [string]$LogDirectory = $LogPath,
            [Parameter(Mandatory = $false)]
            [switch]$ShowProgress
        )
        $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
        Add-Content -Path $LogFile -Value $logEntry -ErrorAction Stop
        $global:LogContent.Add($logEntry)
        if ($ShowProgress) {
            Write-Progress -Activity "Processing" -Status $Message -PercentComplete 0
        }
        switch ($Level) {
            "ERROR" { Write-Error $logEntry }
            "WARNING" { Write-Warning $logEntry }
            "DEBUG" { if ($VerbosePreference -eq 'Continue' -or $PSCmdlet.MyInvocation.BoundParameters["Verbose"]) { Write-Verbose $logEntry } }
            "INFO" { if ($VerbosePreference -eq 'Continue') { Write-Verbose $logEntry } }
        }
    }

    # Error handling function
    function Handle-Error {
        param (
            [Parameter(Mandatory = $true)]
            [string]$ErrorMessage,
            [Parameter(Mandatory = $false)]
            [switch]$ShowMessageBox
        )
        Write-Log -Message $ErrorMessage -Level "ERROR"
        if ($ShowMessageBox -and $PSVersionTable.Platform -eq "Win32NT") {
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.MessageBox]::Show($ErrorMessage, "Error", "OK", "Error") | Out-Null
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
    $form.Size = New-Object System.Drawing.Size(640, 200)
    $form.StartPosition = "CenterScreen"
    $form.MaximizeBox = $false
    $form.FormBorderStyle = 'FixedDialog'

    $labelPath = New-Object System.Windows.Forms.Label
    $labelPath.Text = "Working Path:"
    $labelPath.Location = New-Object System.Drawing.Point(10, 20)
    $labelPath.AutoSize = $true
    $form.Controls.Add($labelPath)

    $textBoxPath = New-Object System.Windows.Forms.TextBox
    $textBoxPath.Size = New-Object System.Drawing.Size(390, 20)
    $textBoxPath.Location = New-Object System.Drawing.Point(130, 18)
    $textBoxPath.Text = $Path
    $form.Controls.Add($textBoxPath)

    $buttonBrowse = New-Object System.Windows.Forms.Button
    $buttonBrowse.Text = "Browse"
    $buttonBrowse.Size = New-Object System.Drawing.Size(75, 23)
    $buttonBrowse.Location = New-Object System.Drawing.Point(530, 16)
    $buttonBrowse.Add_Click({
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($dialog.ShowDialog() -eq "OK") {
            $textBoxPath.Text = $dialog.SelectedPath
        }
    })
    $form.Controls.Add($buttonBrowse)

    $labelOutputName = New-Object System.Windows.Forms.Label
    $labelOutputName.Text = "Output Name:"
    $labelOutputName.Location = New-Object System.Drawing.Point(10, 50)
    $labelOutputName.AutoSize = $true
    $form.Controls.Add($labelOutputName)

    $textBoxOutputName = New-Object System.Windows.Forms.TextBox
    $textBoxOutputName.Size = New-Object System.Drawing.Size(390, 20)
    $textBoxOutputName.Location = New-Object System.Drawing.Point(130, 48)
    $textBoxOutputName.Text = $OutputName
    $form.Controls.Add($textBoxOutputName)

    $labelLogPath = New-Object System.Windows.Forms.Label
    $labelLogPath.Text = "Log Path:"
    $labelLogPath.Location = New-Object System.Drawing.Point(10, 80)
    $labelLogPath.AutoSize = $true
    $form.Controls.Add($labelLogPath)

    $textBoxLogPath = New-Object System.Windows.Forms.TextBox
    $textBoxLogPath.Size = New-Object System.Drawing.Size(390, 20)
    $textBoxLogPath.Location = New-Object System.Drawing.Point(130, 78)
    $textBoxLogPath.Text = $LogPath
    $form.Controls.Add($textBoxLogPath)

    $buttonRun = New-Object System.Windows.Forms.Button
    $buttonRun.Text = "Execute Task"
    $buttonRun.Size = New-Object System.Drawing.Size(100, 30)
    $buttonRun.Location = New-Object System.Drawing.Point(130, 120)
    $buttonRun.Add_Click({
        $script:Path = $textBoxPath.Text
        $script:OutputName = $textBoxOutputName.Text
        $script:LogPath = $textBoxLogPath.Text
        $LogFile = Join-Path $LogPath "$ScriptName-$Timestamp.log"
        $totalSteps = 1  # Customize based on task complexity
        $currentStep = 0
        Execute-Task -TotalSteps $totalSteps -CurrentStep ([ref]$currentStep)
        Update-LogView
        if ($global:LogContent | Where-Object { $_ -like "*[ERROR]*" }) {
            Handle-Error "Task completed with errors. Check logs." -ShowMessageBox
        } else {
            [System.Windows.Forms.MessageBox]::Show("Task completed successfully!", "Success", "OK", "Information") | Out-Null
        }
    })
    $form.Controls.Add($buttonRun)

    $buttonExit = New-Object System.Windows.Forms.Button
    $buttonExit.Text = "Exit"
    $buttonExit.Size = New-Object System.Drawing.Size(100, 30)
    $buttonExit.Location = New-Object System.Drawing.Point(250, 120)
    $buttonExit.Add_Click({ $form.Close() })
    $form.Controls.Add($buttonExit)

    $labelLog = New-Object System.Windows.Forms.Label
    $labelLog.Text = "Log Output:"
    $labelLog.Location = New-Object System.Drawing.Point(10, 160)
    $labelLog.AutoSize = $true
    $form.Controls.Add($labelLog)

    $textBoxLog = New-Object System.Windows.Forms.TextBox
    $textBoxLog.Multiline = $true
    $textBoxLog.ScrollBars = "Vertical"
    $textBoxLog.ReadOnly = $true
    $textBoxLog.Location = New-Object System.Drawing.Point(10, 180)
    $textBoxLog.Size = New-Object System.Drawing.Size(610, 100)
    $form.Controls.Add($textBoxLog)

    function Update-LogView {
        $textBoxLog.Text = ($global:LogContent | Sort-Object | ForEach-Object { $_ }) -join "`r`n"
    }

    [void]$form.ShowDialog()
}

function Execute-Task {
    param (
        [Parameter(Mandatory = $true)]
        [int]$TotalSteps,
        [Parameter(Mandatory = $true)]
        [ref]$CurrentStep
    )
    try {
        #region --- CUSTOM_TASK ---
        Write-Log "Executing custom task with OutputName: $OutputName in $Path" -ShowProgress
        $fullPath = Join-Path $Path "$OutputName.txt"
        if (Test-Path $fullPath) {
            Write-Log "Output $fullPath already exists. Overwriting." -Level "WARNING"
        }
        "This is a sample output created on $(Get-Date)" | Out-File -FilePath $fullPath -Force
        $CurrentStep.Value++
        Write-Progress -Activity "Processing" -Status "Creating output" -PercentComplete (($CurrentStep.Value / $TotalSteps) * 100)
        Write-Log "Successfully created output: $fullPath"
        #endregion
    } catch {
        Handle-Error "Error occurred: $_" -ShowMessageBox
        throw
    }
}
#endregion
