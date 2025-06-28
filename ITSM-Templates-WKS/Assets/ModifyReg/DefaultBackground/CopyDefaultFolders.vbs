' Author: @brazilianscriptguy
' Updated: June 19, 2025
' Script for: COPYING STANDARD FOLDERS FROM LOCATION: C:\ITSM-Templates-WKS\Assets\ModifyReg\userdesktopfolders TO SET AS STANDARD FOLDERS FOR ALL NEW USERS OF THE STATION
' AND ALSO TO SET THE START BUTTON STANDARD WITHOUT THE VARIOUS ICONS AND DYNAMIC TILES OF WINDOWS 10 - TO REDUCE INTERNET CONNECTION AND AUDIOVISUAL RESOURCE CONSUMPTION

' Script testing section for debugging with and without execution errors
'On Error Resume Next

' Creation of the object to interact with the operating system's script library
Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")

' Remove old folders from the default user's desktop
objFSO.DeleteFolder "C:\Users\Default\Desktop", True
objFSO.CreateFolder "C:\Users\Default\Desktop"

' Copy the default files and folders to the default user's desktop
objFSO.CopyFolder "C:\ITSM-Templates-WKS\ModifyReg\userdesktopfolders", "C:\Users\Default\Desktop", True

' Delete all contents of the Windows Shell folder before copying the new XML files
If objFSO.FolderExists("C:\Users\Default\AppData\Local\Microsoft\Windows\Shell") Then
    objFSO.DeleteFolder "C:\Users\Default\AppData\Local\Microsoft\Windows\Shell", True
End If
objFSO.CreateFolder "C:\Users\Default\AppData\Local\Microsoft\Windows\Shell"

' Copy XML files to the Windows Shell folder / Change the start button to the classic model and remove dynamic tiles that connect to the Internet
objFSO.CopyFile "C:\ITSM-Templates-WKS\Assets\ModifyReg\userdesktoptheme\*.xml", "C:\Users\Default\AppData\Local\Microsoft\Windows\Shell", True

' Release the previously allocated environment object
Set objShell = Nothing
Set objFSO = Nothing

' End of Script
