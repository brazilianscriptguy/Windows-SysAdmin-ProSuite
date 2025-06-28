' Author: @brazilianscriptguy
' Updated: June 19, 2025
' Script for installing local ADCS, RDS, and WSUS server certificates for secure connections via certificates

' Define variables
Dim objShell, strCommand, strCerPathADCS, strCerPathRDS, strCerPathWSUS

' Create a shell object to interact with the operating system's script library
Set objShell = CreateObject("WScript.Shell")

' Paths where the certificates are stored locally
strCerPathADCS = "C:\ITSM-Templates-WKS\Assets\Certificates\ADCS-Server\your-adcs-server-certificate.cer"
strCerPathRDS = "C:\ITSM-Templates-WKS\Assets\Certificates\RDS-Server\your-rds-server-certificate.cer"
strCerPathWSUS = "C:\ITSM-Templates-WKS\Assets\Certificates\WSUS-Server\your-wsus-server-certificate.cer"

' Commands to install the certificates in the respective stores
Dim commands(2)
commands(0) = "certutil -addstore -f Root """ & strCerPathADCS & """"
commands(1) = "certutil -addstore -f Root """ & strCerPathRDS & """"
commands(2) = "certutil -addstore -f Root """ & strCerPathWSUS & """"

' Execute the commands
For Each command In commands
    objShell.Run command, 0, True
Next

' Release the shell object
Set objShell = Nothing

' End of Script
