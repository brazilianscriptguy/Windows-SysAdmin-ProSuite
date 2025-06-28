' Author: @brazilianscriptguy
' Updated: June 19, 2025
' Script for: Copying the local HOSTS File where the local routing is defined - Web Digital Signers.
' This file, in the first station setup, also prevents virus attacks and other malicious tools, until the Network Firewall and Antivirus settings kick in,
' being replaced by a reduced version only with the signers.

' Script testing section for debugging with and without execution errors
On Error Resume Next

' Creation of the object to interact with the operating system's script library
Set objFSO = CreateObject("Scripting.FileSystemObject")
Set objShell = CreateObject("WScript.Shell")
Set WEnv = objShell.Environment("Process")

' Define the global constants that will be used
Const OverwriteExisting = True

' Define the environment variables for the local folder of the hosts file
HostsPath = WEnv("SystemRoot") & "\system32\drivers\etc\"

' Copy the initial protection hosts file to the local folder of the station
objFSO.CopyFile "C:\ITSM-Templates-WKS\Assets\CustomImages\hosts", HostsPath, OverwriteExisting

' End of Script
