' Author: @brazilianscriptguy
' Updated: June 19, 2025
' Script for: CREATING THE DEFAULT FOLDER FOR THE WALLPAPER, COPYING THE WALLPAPER TO THE LOCAL FOLDER - AT THE INITIAL SETUP OF THE STATION

' Script testing section for debugging with and without execution errors
'On Error Resume Next

' Creation of the object to interact with the operating system's script library
Set objFSO = CreateObject("Scripting.FileSystemObject")
Set objShell = CreateObject("WScript.Shell")
Set WEnv = objShell.Environment("Process")

' Define the global constants to be used in the Script
Const OverwriteExisting = True

' Define variables that will be used later in the script
ThemesPath = WEnv("SystemRoot") & "\Resources\ITSM-Templates-WKS\Themes\"

'Create the folder info/backgrounds if it does not exist
If Not objFSO.FolderExists(ThemesPath) Then
    objShell.Run "cmd /c mkdir """ & ThemesPath & """", 0, True
End If

'Copy the logon screen wallpaper
objFSO.CopyFile "C:\ITSM-Templates-WKS\Assets\CustomImages\backgroundDefault.jpg", ThemesPath, OverwriteExisting

'End of Script
