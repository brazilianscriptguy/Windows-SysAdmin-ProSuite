' Author: @brazilianscriptguy
' Updated: June 19, 2025
' Script for: RENEWING ALL IP ADDRESSING CONFIGURATIONS OF THE LOCAL MACHINE AND REGISTERING THE NEW STATION INFORMATION IN THE DOMAIN DNS

' Script testing section for debugging with and without execution errors
'On Error Resume Next

' Creation of the object to interact with the operating system's script library
Set objShell = CreateObject("WScript.Shell")

' Execute the operating system's IPCONFIG command, with options to: release the current addresses; clear the local DNS table; renew network addresses via DHCP; register new DNS table
objShell.Run "ipconfig /release", 0, True
objShell.Run "ipconfig /flushdns", 0, True
objShell.Run "ipconfig /renew", 0, True
objShell.Run "netsh int ip reset", 0, True
objShell.Run "netsh int winsock reset", 0, True

' Enable IPv6 settings for all local network adapters
objShell.Run "cmd.exe /c powershell.exe -ExecutionPolicy Bypass Enable-NetAdapterBinding -Name '*' -ComponentID ms_tcpip6", 0, True

' End of Script