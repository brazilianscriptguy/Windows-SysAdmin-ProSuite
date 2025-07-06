'====================================================================
' Author: @brazilianscriptguy
' Last Updated: July 6, 2025
' Purpose: Renew all IP addressing configurations of the local machine 
'          and re-register its information in the domain DNS.
'====================================================================

' Uncomment the line below for silent error handling during development/debugging
' On Error Resume Next

' Create a Shell object to interact with the system shell
Dim objShell
Set objShell = CreateObject("WScript.Shell")

' Log function (optional - logs to console if run via cscript)
Sub Log(msg)
    If InStr(LCase(WScript.FullName), "cscript") > 0 Then
        WScript.Echo "[INFO] " & msg
    End If
End Sub

' Release the current IP addresses
Log "Releasing current IP configuration..."
objShell.Run "ipconfig /release", 0, True

' Flush the local DNS cache
Log "Flushing DNS cache..."
objShell.Run "ipconfig /flushdns", 0, True

' Renew IP configuration via DHCP
Log "Renewing IP configuration..."
objShell.Run "ipconfig /renew", 0, True

' Reset TCP/IP stack to default settings
Log "Resetting TCP/IP stack..."
objShell.Run "netsh int ip reset", 0, True

' Reset Winsock catalog
Log "Resetting Winsock catalog..."
objShell.Run "netsh winsock reset", 0, True

' Enable IPv6 on all adapters using PowerShell
Log "Enabling IPv6 on all adapters..."
objShell.Run "cmd.exe /c powershell.exe -ExecutionPolicy Bypass -NoProfile -Command ""Enable-NetAdapterBinding -Name '*' -ComponentID ms_tcpip6""", 0, True

Log "Network configuration reset completed."

' Cleanup
Set objShell = Nothing

' End of script
