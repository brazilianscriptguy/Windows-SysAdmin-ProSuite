' Author: @brazilianscriptguy
' Updated: June 19, 2025
' Script for: CLEARING OLD WSUS UPDATE SETTINGS AND POINTING ONLY TO THE NEW DOMAIN'S WSUS SERVER

' Script testing section for debugging with and without execution errors
On Error Resume Next

' Define variables that will be used later in the script
Dim objShell

' Creation of the object to interact with the operating system's script library
Set objShell = CreateObject("WScript.Shell")

' Stop the WSUS update service WUAUSERV
objShell.Run "net stop wuauserv", 0, True

' Delete the AccountDomainSid registry key that belongs to legacy domains and update for the new domain structure
If Not IsEmpty(objShell.RegRead("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\AccountDomainSid")) Then
    objShell.RegDelete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\AccountDomainSid"
End If

' Delete the PingID registry key
If Not IsEmpty(objShell.RegRead("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\PingID")) Then
    objShell.RegDelete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\PingID"
End If

' Delete the SusClientId registry key that belongs to legacy domains and update for the new domain structure
If Not IsEmpty(objShell.RegRead("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\SusClientId")) Then
    objShell.RegDelete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\SusClientId"
End If

' Start the WSUS update service WUAUSERV
objShell.Run "net start wuauserv", 0, True

' Reset the update authorization cookie from old domains and resynchronize with the new local WSUS service
objShell.Run "wuauclt /resetauthorization /detectnow", 0, True

' Release the previously allocated environment object
Set objShell = Nothing

' End of Script
