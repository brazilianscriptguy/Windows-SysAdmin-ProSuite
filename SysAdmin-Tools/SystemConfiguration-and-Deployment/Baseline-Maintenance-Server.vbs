
' Author: @brazilianscriptguy
' Updated: 2026-02-11
' Script for server maintenance and baseline remediation (light Windows Update cache cleanup, SFC/DISM, staged reboot notifications, structured logging)

Option Explicit

' Define variables
Dim fso
Dim sh

'==================== TOGGLES ====================
Const RUN_SFC_DISM         = 1
Const CLEAN_WU_CACHE_LIGHT = 1
Const FORCE_REBOOT         = 0
Const NOTIFY_REBOOT_STEPS  = 1
Const CERTUTIL_PULSE       = 0
Const CERT_SYNC_ENABLE     = 0   ' normally OFF on servers

' Notice steps (minutes)
Dim NOTICE_STEPS
NOTICE_STEPS = Array(15,10,5,1)

'==================== LOG ====================
Const LOG_DIR     = "C:\Logs-TEMP"
Const SCRIPT_NAME = "Baseline-Maintenance-Server"

Dim LOG_FILE
LOG_FILE = LOG_DIR & "\Baseline-Maintenance-Server.log"

'==================== OBJECTS ====================
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")

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

Sub WLog(lvl, msg)
  On Error Resume Next

  EnsureFolder LOG_DIR

  Dim f
  Set f = fso.OpenTextFile(LOG_FILE, 8, True, 0)
  f.WriteLine "[" & TS() & "] [" & lvl & "] " & msg
  f.Close

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

Sub StopSvc(svcName, maxTries)
  On Error Resume Next

  Dim i
  For i = 1 To maxTries
    If sh.Run("cmd.exe /c sc stop " & svcName & " >nul 2>&1", 0, True) = 0 Then
      Exit Sub
    End If
    WLog "WARN", "Failed to stop " & svcName & " (attempt " & i & "/" & maxTries & ")."
  Next

  Err.Clear
  On Error GoTo 0
End Sub

Sub MsgAll(msg)
  On Error Resume Next
  sh.Run "cmd.exe /c msg * """ & msg & """", 0, False
  On Error GoTo 0
End Sub

Sub RunSfcDism()
  If RUN_SFC_DISM = 0 Then Exit Sub

  WLog "INFO", "Running SFC..."
  Dim rc
  rc = RunCmd("sfc /scannow")

  If rc = 0 Then
    WLog "INFO", "SFC completed."
  Else
    WLog "WARN", "SFC returned code " & rc & "."
  End If

  WLog "INFO", "Running DISM /RestoreHealth..."
  rc = RunCmd("DISM /Online /Cleanup-Image /RestoreHealth")

  If rc = 0 Then
    WLog "INFO", "DISM completed."
  Else
    WLog "WARN", "DISM returned code " & rc & "."
  End If
End Sub

Sub CleanWuCacheLight()
  If CLEAN_WU_CACHE_LIGHT = 0 Then Exit Sub

  WLog "INFO", "Light Windows Update cache cleanup (SoftwareDistribution)..."

  StopSvc "wuauserv", 3
  StopSvc "bits", 3

  Dim p
  p = "C:\Windows\SoftwareDistribution"

  On Error Resume Next
  If fso.FolderExists(p) Then
    fso.DeleteFolder p, True
    If Err.Number = 0 Then
      WLog "INFO", "Directory deleted: " & p
    Else
      WLog "WARN", "Failed to delete " & p & " - " & Err.Description
    End If
  End If
  Err.Clear
  On Error GoTo 0

  RunCmd "sc start bits >nul 2>&1"
  RunCmd "sc start wuauserv >nul 2>&1"
End Sub

Sub CertPulse()
  If CERTUTIL_PULSE = 0 Then Exit Sub

  If CERT_SYNC_ENABLE = 0 Then
    WLog "INFO", "Trusted root certificate sync is DISABLED by institutional policy."
    Exit Sub
  End If

  WLog "INFO", "Running certutil -pulse..."
  RunCmd "certutil -pulse"
End Sub

Sub ControlledReboot()
  If FORCE_REBOOT = 0 Then
    WLog "INFO", "Reboot will NOT be forced."
    Exit Sub
  End If

  If NOTIFY_REBOOT_STEPS = 1 Then
    Dim i, minLeft
    For i = 0 To UBound(NOTICE_STEPS)
      minLeft = NOTICE_STEPS(i)
      MsgAll "ATTENTION: reboot in " & minLeft & " minute(s)."
      RunCmd "timeout /t " & (minLeft * 60) & " /nobreak >nul"
    Next
  End If

  Dim finalMsg
  finalMsg = "Immediate reboot required to complete maintenance."
  MsgAll finalMsg

  WLog "INFO", "Issuing reboot command."
  RunCmd "%windir%\system32\shutdown.exe /r /f /t 60 /c """ & finalMsg & """ /d p:2:4"
End Sub

'==================== MAIN ====================
WLog "INFO", "Starting maintenance workflow..."
RunSfcDism
CleanWuCacheLight
CertPulse
ControlledReboot
WLog "INFO", "Finished."

' End of Script
