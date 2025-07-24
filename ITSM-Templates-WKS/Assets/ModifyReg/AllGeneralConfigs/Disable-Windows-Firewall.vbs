' Author: @brazilianscriptguy
' Updated: June 19, 2025
' Script for: DISABLING THE OPERATING SYSTEM FIREWALL AND LEAVING CONTROL WITH THE MANAGEMENT OF CORPORATE ANTIVIRUS

' Script testing section for debugging with and without execution errors
' On Error Resume Next

' Creation of the object to interact with the operating system's script library
Set objShell = CreateObject("WScript.Shell")

' Disables the Windows Firewall for all profiles
objShell.Run "netsh advfirewall set allprofiles state off", 0, True

' End of Script
