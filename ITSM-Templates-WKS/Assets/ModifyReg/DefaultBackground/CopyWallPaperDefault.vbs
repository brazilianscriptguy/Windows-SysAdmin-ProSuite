' Author: @brazilianscriptguy
' Updated: June 19, 2025
' Script for: SETTING THE VARIABLES OF WHERE THE STANDARD CORPORATE WALLPAPER RESIDES AND COPYING THE NEW FILE

' Script testing section for debugging with and without execution errors
'On Error Resume Next

' Creation of the object to interact with the operating system's script library
Dim objFSO, objShell, WEnv
Set objFSO = CreateObject("Scripting.FileSystemObject")
Set objShell = CreateObject("WScript.Shell")
Set WEnv = objShell.Environment("Process")

' Define the global constants that will be used
Const OverwriteExisting = True

' Define the environment variables for the location of the Folder where the standard wallpaper resides
Dim ThemesPath, SourceImagePath
ThemesPath = WEnv("SystemRoot") & "\Resources\ITSM-Templates-WKS\Themes\"
SourceImagePath = "C:\ITSM-Templates-WKS\Assets\CustomImages\wallpaperDefault.jpg"

' Check if ThemesPath folder exists, if not, create it
If Not objFSO.FolderExists(ThemesPath) Then
    objShell.Run "cmd /c mkdir """ & ThemesPath & """", 0, True
End If

' Copy the institutional wallpaper files
If objFSO.FileExists(SourceImagePath) Then
    objFSO.CopyFile SourceImagePath, ThemesPath, OverwriteExisting
    If Err.Number <> 0 Then
        WScript.Echo "Error copying file: " & SourceImagePath
        WScript.Echo "Error description: " & Err.Description
        WScript.Quit
    End If
End If
' End of Script
