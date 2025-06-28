' Author: @brazilianscriptguy
' Updated: June 19, 2025
' Script for: ADDING EXECUTION PERMISSIONS IN THE ROOT FOLDER OF YOUR LEGACY APPLICATION FOR THE COMMON USER PROFILE OF THE STATION

' Script testing section for debugging with and without execution errors
'On Error Resume Next

' Creation of the object to interact with the operating system's script library
Set objShell = CreateObject("WScript.Shell")

' Grant access to the application folder and its contents
objShell.Run "cmd /c cacls C:\your-legacy-path\app-folder\* /E /P ""Everyone"":F", 0, True

' End of Script
