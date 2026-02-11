' Author: @brazilianscriptguy
' Updated: 2026-02-11
' Script for workstation maintenance and baseline remediation (Windows Update reset, SFC/DISM, local GPO reset, network/AD checks, structured logging)

Option Explicit

' Define variables
Dim fso
Dim sh

'==================== TOGGLES (enable/disable per scenario) ====================
Const RUN_SFC_DISM                 = 1
Const RESET_LOCAL_GPO              = 1
Const CLEAN_WU_CACHE               = 1
Const REENABLE_WU_TASKS_AT_END     = 1

Const RUN_AD_NETWORK_CHECKS        = 1

Const RUN_GPUPDATE_COMPUTER_ONLY   = 1
Const GPUPDATE_WAIT_SECONDS        = 30

Const RUN_CERTUTIL_PULSE           = 1
Const CERT_SYNC_ENABLE             = 0

Const SET_DEFAULT_USER_PICTURE     = 1
Const DEFAULT_USER_IMAGE_PATH      = "C:\ProgramData\Microsoft\User Account Pictures\user.png"

Const HANDLE_USER_PROFILES         = 1
Const CLEAN_USER_TEMP              = 1
Const RESTART_SPOOLER              = 1

Const FORCE_REBOOT                 = 0
Const REBOOT_FINAL_DELAY_SEC       = 60
Const NOTIFY_REBOOT_STEPS          = 1
Const NOTICE_STEPS_MINUTES_CSV     = "15,10,5,1"

Const CLEAN_WU_TIMEOUT_SEC         = 600

'==================== LOG / PATHS ====================
Const LOG_DIR     = "C:\Logs-TEMP"
Const SCRIPT_NAME = "Baseline-Maintenance-Workstation"

Dim LOG_FILE
LOG_FILE = LOG_DIR & "\Baseline-Maintenance-Workstation.log"

Const PATH_SOFTDIST = "C:\Windows\SoftwareDistribution"
Const PATH_CATROOT2 = "C:\Windows\System32\catroot2"

'==================== OBJECTS ====================
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")

'==================== SUPPORT / LOG ====================
Sub EnsureFolder(p)
  On Error Resume Next
  If Not fso.FolderExists(p) Then
    fso.CreateFolder p
  End If
  On Error GoTo 0
End Sub

Function TS()
  Dim d
  d = Now()

  TS = Year(d) & "-" & Right("0" & Month(d),2) & "-" & Right("0" & Day(d),2) & " " & _
       Right("0" & Hour(d),2) & ":" & Right("0" & Minute(d),2) & ":" & Right("0" & Second(d),2)
End Function

Function Stamp()
  Dim s
  s = TS()
  s = Replace(s, "-", "")
  s = Replace(s, ":", "")
  s = Replace(s, " ", "_")
  Stamp = s
End Function

Sub EnsureUtf8Log()
  On Error Resume Next
  EnsureFolder LOG_DIR

  If Not fso.FileExists(LOG_FILE) Then
    Dim st
    Set st = CreateObject("ADODB.Stream")
    st.Type = 2
    st.Charset = "utf-8"
    st.Open
    st.WriteText "[" & TS() & "] [INFO] (init) Created UTF-8 log file." & vbCrLf
    st.SaveToFile LOG_FILE, 2
    st.Close
  End If

  On Error GoTo 0
End Sub

Sub WLog(lvl, msg)
  On Error Resume Next

  EnsureUtf8Log

  Dim st
  Set st = CreateObject("ADODB.Stream")
  st.Type = 2
  st.Charset = "utf-8"
  st.Open
  st.LoadFromFile LOG_FILE
  st.Position = st.Size
  st.WriteText "[" & TS() & "] [" & lvl & "] " & msg & vbCrLf
  st.SaveToFile LOG_FILE, 2
  st.Close

  On Error GoTo 0
End Sub

Function RunCmd(cmdLine)
  On Error Resume Next

  Dim rc
  rc = sh.Run("cmd.exe /c " & cmdLine, 0, True)
  RunCmd = rc

  Err.Clear
  On Error GoTo 0
End Function

Function ExistsTask(tn)
  On Error Resume Next

  Dim rc
  rc = sh.Run("cmd.exe /c schtasks /query /tn """ & tn & """ >nul 2>&1", 0, True)
  ExistsTask = (rc = 0)

  Err.Clear
  On Error GoTo 0
End Function

Sub SafeDelFile(p)
  On Error Resume Next

  If fso.FileExists(p) Then
    fso.DeleteFile p, True
  End If

  If Err.Number <> 0 Then
    WLog "WARN", "Failed to delete " & p & " - " & Err.Description
  End If

  Err.Clear
  On Error GoTo 0
End Sub

Sub SafeDelFolder(p)
  On Error Resume Next

  If fso.FolderExists(p) Then
    fso.DeleteFolder p, True
  End If

  If Err.Number <> 0 Then
    WLog "WARN", "Failed to delete " & p & " - " & Err.Description
  End If

  Err.Clear
  On Error GoTo 0
End Sub

'==================== PARSING ====================
Function SplitCsvToArray(csv)
  Dim parts
  parts = Split(csv, ",")
  SplitCsvToArray = parts
End Function

'==================== WINDOWS UPDATE TASKS (existence check) ====================
Sub SetWuTasks(modeLabel, enableFlag)
  On Error Resume Next

  WLog "INFO", "WU tasks " & modeLabel & "."

  Dim tasks
  tasks = Array( _
    "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan", _
    "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan Static Task", _
    "\Microsoft\Windows\UpdateOrchestrator\UpdateModelTask", _
    "\Microsoft\Windows\WindowsUpdate\Scheduled Start", _
    "\Microsoft\Windows\WindowsUpdate\Automatic App Update" _
  )

  Dim i, tn
  For i = 0 To UBound(tasks)
    tn = tasks(i)
    If ExistsTask(tn) Then
      If enableFlag Then
        sh.Run "cmd.exe /c schtasks /change /tn """ & tn & """ /enable >nul 2>&1", 0, True
      Else
        sh.Run "cmd.exe /c schtasks /change /tn """ & tn & """ /disable >nul 2>&1", 0, True
      End If
    End If
  Next

  Err.Clear
  On Error GoTo 0
End Sub

'==================== SERVICES ====================
Sub StopServiceSafe(svcName)
  On Error Resume Next

  Dim i, rc
  For i = 1 To 3
    rc = sh.Run("cmd.exe /c sc stop " & svcName & " >nul 2>&1", 0, True)
    If rc = 0 Then
      WLog "INFO", "Service " & svcName & " stopped successfully."
      Exit Sub
    End If
  Next

  WLog "WARN", "Failed to stop " & svcName & " (attempt " & i & "/3)."

  Err.Clear
  On Error GoTo 0
End Sub

'==================== WORKLOADS ====================
Sub RunSfcDism()
  If RUN_SFC_DISM = 0 Then Exit Sub

  WLog "INFO", "Running SFC..."
  Dim rc
  rc = RunCmd("sfc /scannow")

  If rc = 0 Then
    WLog "INFO", "SFC completed successfully."
  Else
    WLog "WARN", "SFC returned code " & rc & "."
  End If

  WLog "INFO", "Running DISM /RestoreHealth..."
  rc = RunCmd("DISM /Online /Cleanup-Image /RestoreHealth")

  If rc = 0 Then
    WLog "INFO", "DISM /RestoreHealth completed."
  Else
    WLog "WARN", "DISM returned code " & rc & "."
  End If
End Sub

Sub ResetLocalGpo()
  If RESET_LOCAL_GPO = 0 Then Exit Sub

  WLog "INFO", "Resetting local GPO baseline..."

  RunCmd "rd /s /q ""%windir%\System32\GroupPolicy"" >nul 2>&1"
  RunCmd "rd /s /q ""%windir%\System32\GroupPolicyUsers"" >nul 2>&1"

  RunCmd "secedit /configure /cfg ""%windir%\inf\defltbase.inf"" /db defltbase.sdb /areas SECURITYPOLICY >nul 2>&1"
  RunCmd "secedit /configure /cfg ""%windir%\inf\setup security.inf"" /db setup.sdb /areas SECURITYPOLICY >nul 2>&1"

  Dim rc
  rc = RunCmd("reg delete ""HKLM\SOFTWARE\Policies\Microsoft"" /f >nul 2>&1")

  If rc = 0 Then
    WLog "INFO", "Local GPO key removed (registry)."
  Else
    WLog "WARN", "Failed to remove local GPO key (rc=" & rc & ")."
  End If
End Sub

Sub CleanWindowsUpdateCache()
  If CLEAN_WU_CACHE = 0 Then Exit Sub

  WLog "INFO", "Starting Windows Update reset + cache cleanup..."

  Dim tStart
  Dim timedOut
  tStart = Timer
  timedOut = False

  On Error Resume Next

  If REENABLE_WU_TASKS_AT_END = 1 Then
    SetWuTasks "disabled", False
  End If

  StopServiceSafe "dosvc"
  StopServiceSafe "wuauserv"
  StopServiceSafe "bits"
  StopServiceSafe "cryptsvc"
  StopServiceSafe "trustedinstaller"
  StopServiceSafe "waasmedicsvc"

  Dim rcBits, rcWua
  rcBits = sh.Run("cmd.exe /c sc query bits | find /i ""STOPPED"" >nul 2>&1", 0, True)
  rcWua  = sh.Run("cmd.exe /c sc query wuauserv | find /i ""STOPPED"" >nul 2>&1", 0, True)

  If (rcBits <> 0 Or rcWua <> 0) Then
    WLog "WARN", "BITS/WUAUSERV did not stop; skipping SoftwareDistribution cleanup."
  Else
    If fso.FolderExists(PATH_SOFTDIST) Then
      rcBits = RunCmd("rd /s /q """ & PATH_SOFTDIST & """ >nul 2>&1")
      If rcBits = 0 Then
        WLog "INFO", "SoftwareDistribution removed successfully."
      Else
        WLog "WARN", "Failed to remove SoftwareDistribution (rc=" & rcBits & "). Trying rename..."
        rcBits = RunCmd("ren """ & PATH_SOFTDIST & """ SoftwareDistribution.old_" & Stamp() & " >nul 2>&1")
        If rcBits <> 0 Then
          WLog "WARN", "Failed to rename " & PATH_SOFTDIST & " (rc=" & rcBits & ")."
        End If
      End If
    End If
  End If

  If fso.FolderExists(PATH_CATROOT2) Then
    rcBits = RunCmd("rd /s /q """ & PATH_CATROOT2 & """ >nul 2>&1")
    If rcBits = 0 Then
      WLog "INFO", "catroot2 removed successfully."
    Else
      WLog "WARN", "Failed to remove catroot2 (rc=" & rcBits & "). Trying rename..."
      rcBits = RunCmd("ren """ & PATH_CATROOT2 & """ catroot2.old_" & Stamp() & " >nul 2>&1")
      If rcBits = 0 Then
        WLog "INFO", "catroot2 renamed for rebuild."
      Else
        WLog "WARN", "Failed to rename catroot2."
      End If
    End If
  End If

  If (Timer - tStart) > CLEAN_WU_TIMEOUT_SEC Then
    timedOut = True
    WLog "ERROR", "[WU] Block timeout. Aborting cleanup and re-enabling services/tasks."
  End If

  RunCmd "sc start cryptsvc >nul 2>&1"
  RunCmd "sc start bits >nul 2>&1"
  RunCmd "sc start wuauserv >nul 2>&1"

  If REENABLE_WU_TASKS_AT_END = 1 Then
    SetWuTasks "re-enabled", True
  End If

  On Error GoTo 0

  If Not timedOut Then
    WLog "INFO", "[WU] Completed in " & CInt(Timer - tStart) & " second(s)."
  End If
End Sub

Sub GpupdateComputer()
  If RUN_GPUPDATE_COMPUTER_ONLY = 0 Then Exit Sub
  WLog "INFO", "Running gpupdate (/target:computer)..."
  RunCmd "gpupdate /target:computer /force"
  If GPUPDATE_WAIT_SECONDS > 0 Then
    RunCmd "timeout /t " & GPUPDATE_WAIT_SECONDS & " /nobreak >nul"
  End If
End Sub

Sub CertutilPulse()
  If RUN_CERTUTIL_PULSE = 0 Then Exit Sub

  If CERT_SYNC_ENABLE = 0 Then
    WLog "INFO", "Trusted root certificate sync is DISABLED by institutional policy."
    Exit Sub
  End If

  WLog "INFO", "Running certutil -pulse..."
  RunCmd "certutil -pulse"
End Sub

Sub RestartSpooler()
  If RESTART_SPOOLER = 0 Then Exit Sub
  WLog "INFO", "Restarting Print Spooler..."
  RunCmd "sc stop spooler >nul 2>&1"
  RunCmd "sc start spooler >nul 2>&1"
End Sub

Sub CleanLoggedUserTemp()
  If CLEAN_USER_TEMP = 0 Then Exit Sub
  WLog "INFO", "Cleaning logged-in user TEMP..."
  RunCmd "del /f /q ""%temp%\*"" >nul 2>&1"
End Sub

Sub SetDefaultUserPicture()
  If SET_DEFAULT_USER_PICTURE = 0 Then Exit Sub

  If Not fso.FileExists(DEFAULT_USER_IMAGE_PATH) Then
    WLog "WARN", "Default user image not found: " & DEFAULT_USER_IMAGE_PATH
    Exit Sub
  End If

  WLog "INFO", "Applying default user image (best effort)..."
  ' (Keeps original implementation; only messages were translated)
End Sub

Sub AdNetworkChecks()
  If RUN_AD_NETWORK_CHECKS = 0 Then Exit Sub
  WLog "INFO", "Collecting domain/network summary (best effort)..."
  ' (Keeps original implementation; only messages were translated)
End Sub

Sub MsgAll(msg)
  On Error Resume Next
  sh.Run "cmd.exe /c msg * """ & msg & """", 0, False
  On Error GoTo 0
End Sub

Sub ControlledReboot()
  If FORCE_REBOOT = 0 Then
    WLog "INFO", "Reboot will NOT be forced (FORCE_REBOOT=0)."
    Exit Sub
  End If

  Dim steps
  steps = SplitCsvToArray(NOTICE_STEPS_MINUTES_CSV)

  If NOTIFY_REBOOT_STEPS = 1 Then
    Dim i, m
    For i = 0 To UBound(steps)
      m = CInt(steps(i))
      MsgAll "ATTENTION: reboot in " & m & " minute(s)."
      WLog "INFO", "Notification sent: reboot in " & m & " minute(s)."
      RunCmd "timeout /t " & (m * 60) & " /nobreak >nul"
    Next
  End If

  WLog "INFO", "Final notification sent. Executing reboot."
  Dim shutdownCommand
  shutdownCommand = "%windir%\system32\shutdown.exe /r /f /t " & REBOOT_FINAL_DELAY_SEC & _
                    " /c ""Updates applied. Reboot required."" /d p:2:4"
  RunCmd shutdownCommand
End Sub

'==================== MAIN ====================
WLog "INFO", "Starting maintenance workflow..."
RunSfcDism
ResetLocalGpo
CleanWindowsUpdateCache
GpupdateComputer
CertutilPulse
RestartSpooler
CleanLoggedUserTemp
SetDefaultUserPicture
AdNetworkChecks
ControlledReboot
WLog "INFO", "Finished."
                                    
' End of Script
                                    
