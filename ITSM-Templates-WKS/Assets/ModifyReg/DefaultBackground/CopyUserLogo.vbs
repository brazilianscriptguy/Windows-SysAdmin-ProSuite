' Author: @brazilianscriptguy
' Updated: June 19, 2025
' Script for: COPYING STANDARD CORPORATE IMAGES TO THE USER PROFILE AND THE STANDARD SUPPORT IDENTIFICATION IMAGE IN THE OPERATING SYSTEM

' Script testing section for debugging with and without execution errors
'On Error Resume Next

' Creation of the object to interact with the operating system's script library
Set objFSO = CreateObject("Scripting.FileSystemObject")
Set objShell = CreateObject("WScript.Shell")
Set WEnv = objShell.Environment("Process")

' Define the global constants that will be used later in the script
Const OverwriteExisting = True

' Retrieve the environment variable that defines the local folder of user profile images
ProgramPath = WEnv("PROGRAMDATA") & "\Microsoft\User Account Pictures\"

' Remove previous user profile images
objFSO.DeleteFile "C:\ProgramData\Microsoft\User Account Pictures\*.*", True

'Copy the new user profile images
objFSO.CopyFile "C:\ITSM-Templates-WKS\Assets\CustomImages\user*.*", ProgramPath, OverwriteExisting

'Copy the new operating system support images
objFSO.CopyFile "C:\ITSM-Templates-WKS\Assets\CustomImages\oemlogo.bmp", "C:\windows\system32\oemlogo.bmp", OverwriteExisting

' End of Script