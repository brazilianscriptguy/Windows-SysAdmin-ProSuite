<#
.SYNOPSIS
    Forest-agnostic Active Directory Computer Pre-Staging and Domain-Join Authorization Manager.

.DESCRIPTION
    Forest-agnostic Active Directory computer pre-staging, authorization audit, and optional ACL remediation tool.

    The tool pre-stages workstation computer accounts in selected Active Directory
    Organizational Units and validates that the configured ingress security principal
    has the domain-join permissions required by the established domain-join workflow.

    Operating model:
      - Manual comma-separated names and TXT-file input.
      - Runtime-selectable Domain Join Principal; no account/domain is hard-coded.
      - GUI pre-fills domainingress@<ForestRootDomain> only as an editable convenience default; it is live-validated.
      - Runtime-selectable naming policy.
      - All OUs are discoverable; no language or OU-name convention is assumed.
      - The OU Search box defaults to 'OU to Join Computers' only as a convenience filter; clear it to display every OU.
      - Build Preview is cumulative: multiple Domain + OU batches can coexist in one provisioning list.
      - Each accumulated row preserves its own Domain, writable DC, DC IP, Target OU, and planned action.
      - Duplicate Domain + ComputerName rows are skipped automatically.
      - Add Computer: creates a new pre-staged computer when the name does not exist.
      - Controlled Re-Ingress: preserves an existing same-name computer object only when it is classified STALE.
      - ACTIVE same-name computer objects are always blocked from re-ingress.
      - Re-ingress eligibility is revalidated immediately before Commit.
      - Join authorization is inherited-first; when enabled, only missing core domain-join ACEs are added explicitly.
      - Standard computer-reuse/domain-join rights are audited before remediation.
      - VALIDATE inherited permissions first.
      - ADD explicit ACEs only when a required core right is genuinely missing.
      - Never replace a compliant inherited ACL with redundant explicit ACEs.

    Compatible with Windows PowerShell 5.1 and Windows Server 2019.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    2026-08-18-v3.3.6-FOREST-AGNOSTIC-MULTIDOMAIN-BATCH-HOSTNAME-POLICY

.REQUIREMENTS
    - Windows PowerShell 5.1
    - Windows Server 2019
    - ActiveDirectory PowerShell module
    - Rights to create computer objects in the selected OU
    - Rights to read/write the relevant computer object DACL if ACL remediation is required

.SAFETY
    - Dry Run enabled by default.
    - Candidate discovery and Commit are separate.
    - Existing computer accounts are never deleted or moved automatically.
    - Every AD operation uses an explicit writable DC FQDN.
    - Computer identity is revalidated by ObjectGUID before ACL mutation.
    - ACL remediation is additive and only for missing legacy/core ACEs.
    - PasswordNotRequired is OFF by default; a legacy compatibility toggle is provided.
    - Passwords and credentials are never logged.
    - All displayed columns are searchable/filterable and sortable.
#>

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
    [switch]$ShowConsole
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# =====================================================================================
# Startup / console suppression
# =====================================================================================
try {
    if(-not $ShowConsole){
        try{
            if(-not ('NativeConsoleWindow' -as [type])){
                Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeConsoleWindow {
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide(){
        IntPtr h = GetConsoleWindow();
        if(h != IntPtr.Zero){ ShowWindow(h, 0); }
    }
}
"@
            }
            [NativeConsoleWindow]::Hide()
        }catch{}
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName Microsoft.VisualBasic
    [System.Windows.Forms.Application]::EnableVisualStyles()

    if(-not (Get-Module -ListAvailable -Name ActiveDirectory)){
        throw 'The ActiveDirectory PowerShell module is not installed or available.'
    }

    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Error "Initialization failed: $($_.Exception.Message)"
    return
}

# =====================================================================================
# Application state / constants
# =====================================================================================
$script:AppName      = 'AD Computer Pre-Staging Manager'
$script:AppVersion   = '3.3.6'
$script:ScriptName   = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:LogRoot      = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'ADComputerPreStaging\Logs'
$script:RunStamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:LogFile      = Join-Path $script:LogRoot "$($script:ScriptName)-$($script:RunStamp).log"
$script:ReportFile   = Join-Path $script:LogRoot "$($script:ScriptName)-$($script:RunStamp)-report.csv"

$script:Forest       = $null
$script:DomainCache  = @{}
$script:OUCache      = @{}
$script:Ingress      = $null
$script:Candidates   = @()
$script:Displayed    = @()
$script:SortColumn   = -1
$script:SortDescending = $false

$script:listView       = $null
$script:txtRuntimeLog  = $null
$script:statusMain     = $null

$script:ComputerClassGuid = [Guid]'bf967a86-0de6-11d0-a285-00aa003049e2'

# Legacy/core permissions from the proven script.
$script:JoinRights = [ordered]@{
    ResetPassword = [pscustomobject]@{
        FriendlyName = 'Reset Password'
        Guid         = [Guid]'00299570-246d-11d0-a768-00aa006e0529'
        RequiredMask = [DirectoryServices.ActiveDirectoryRights]::ExtendedRight
        RuleKind     = 'ExtendedRight'
    }
    ValidatedDns = [pscustomobject]@{
        FriendlyName = 'Validated Write DNS Host Name'
        Guid         = [Guid]'72e39547-7b18-11d1-adef-00c04fd8d5cd'
        RequiredMask = [DirectoryServices.ActiveDirectoryRights]::Self
        RuleKind     = 'Self'
    }
    ValidatedSpn = [pscustomobject]@{
        FriendlyName = 'Validated Write SPN'
        Guid         = [Guid]'f3a64788-5306-11d1-a9c5-0000f80367c1'
        RequiredMask = [DirectoryServices.ActiveDirectoryRights]::Self
        RuleKind     = 'Self'
    }
    AccountRestrictions = [pscustomobject]@{
        FriendlyName = 'Write Account Restrictions'
        Guid         = [Guid]'4c164200-20c0-11d0-a768-00aa006e0529'
        RequiredMask = [DirectoryServices.ActiveDirectoryRights]::WriteProperty
        RuleKind     = 'WriteProperty'
    }
}

# Additional current-domain-join reuse rights that are useful for audit visibility.
$script:AdditionalAuditRights = [ordered]@{
    ChangePassword = [pscustomobject]@{
        FriendlyName = 'Change Password'
        Guid         = [Guid]'ab721a53-1e2f-11d0-9819-00aa0040529b'
    }
    AllowedToAuthenticate = [pscustomobject]@{
        FriendlyName = 'Allowed to Authenticate'
        Guid         = [Guid]'68b1d179-0d15-4d4f-ab71-46152e79a7bc'
    }
}

if(-not (Test-Path -LiteralPath $script:LogRoot)){
    New-Item -Path $script:LogRoot -ItemType Directory -Force | Out-Null
}

# =====================================================================================
# Logging / messages
# =====================================================================================
function Write-AppLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [ValidateSet('INFO','SUCCESS','WARN','ERROR')]
        [string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message

    try{
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    }catch{}

    if($script:txtRuntimeLog -and -not $script:txtRuntimeLog.IsDisposed){
        $script:txtRuntimeLog.AppendText($line + [Environment]::NewLine)
        $script:txtRuntimeLog.SelectionStart = $script:txtRuntimeLog.Text.Length
        $script:txtRuntimeLog.ScrollToCaret()
    }
    elseif($ShowConsole){
        Write-Host $line
    }
}

function Set-AppStatus {
    param([string]$Text)

    if($script:statusMain -and -not $script:statusMain.IsDisposed){
        $script:statusMain.Text = $Text
        [Windows.Forms.Application]::DoEvents()
    }
}

function Show-AppMessage {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [ValidateSet('Information','Warning','Error')]
        [string]$Type = 'Information'
    )

    switch($Type){
        'Error' {
            $icon = [Windows.Forms.MessageBoxIcon]::Error
            Write-AppLog $Message ERROR
        }
        'Warning' {
            $icon = [Windows.Forms.MessageBoxIcon]::Warning
            Write-AppLog $Message WARN
        }
        default {
            $icon = [Windows.Forms.MessageBoxIcon]::Information
            Write-AppLog $Message INFO
        }
    }

    [void][Windows.Forms.MessageBox]::Show(
        $Message,
        $script:AppName,
        [Windows.Forms.MessageBoxButtons]::OK,
        $icon
    )
}

# =====================================================================================
# AD discovery
# =====================================================================================
function Get-ScalarString {
    param($Value)

    $items = @($Value)
    if($items.Count -eq 0){ return '' }
    return ([string]$items[0]).Trim()
}

function Get-WritableDomainControllerRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$DomainName
    )

    if($script:DomainCache.ContainsKey($DomainName)){
        return $script:DomainCache[$DomainName]
    }

    $domain = Get-ADDomain -Identity $DomainName -Server $DomainName -ErrorAction Stop

    # Prefer a discovered writable DC, then normalize HostName to scalar string.
    $dc = Get-ADDomainController -Discover -DomainName $DomainName -Writable -ErrorAction Stop
    $dcFqdn = Get-ScalarString $dc.HostName

    if([string]::IsNullOrWhiteSpace($dcFqdn)){
        throw "Writable DC discovery returned no FQDN for '$DomainName'."
    }

    $dcResolved = Get-ADDomainController -Identity $dcFqdn -Server $DomainName -ErrorAction Stop
    $ipv4 = Get-ScalarString $dcResolved.IPv4Address

    $record = [pscustomobject]@{
        DomainName        = [string]$domain.DNSRoot
        NetBIOSName       = [string]$domain.NetBIOSName
        DistinguishedName = [string]$domain.DistinguishedName
        DomainSID         = [string]$domain.DomainSID
        DCFqdn            = $dcFqdn
        DCIPv4            = $ipv4
        Site              = [string]$dcResolved.Site
        IsGlobalCatalog   = [bool]$dcResolved.IsGlobalCatalog
        IsReadOnly        = [bool]$dcResolved.IsReadOnly
    }

    $script:DomainCache[$DomainName] = $record
    return $record
}

function Initialize-ForestContext {
    $script:Forest = Get-ADForest -ErrorAction Stop

    foreach($domainName in @($script:Forest.Domains)){
        [void](Get-WritableDomainControllerRecord -DomainName ([string]$domainName))
    }
}

function Resolve-JoinPrincipal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$SearchValue
    )

    $SearchValue = $SearchValue.Trim()

    if([string]::IsNullOrWhiteSpace($SearchValue)){
        throw 'Enter a Domain Join Principal before resolving the account.'
    }

    $matches = New-Object Collections.ArrayList

    foreach($domainName in @($script:Forest.Domains)){
        $domainRecord = Get-WritableDomainControllerRecord -DomainName ([string]$domainName)

        $escaped = $SearchValue.Replace('\','\5c').Replace('*','\2a').Replace('(','\28').Replace(')','\29')
        $sam = $SearchValue
        $upn = $SearchValue

        if($SearchValue -like '*@*'){
            $sam = $SearchValue.Split('@')[0]
        }

        $ldap = "(|(sAMAccountName=$escaped)(userPrincipalName=$escaped)(sAMAccountName=$sam))"

        try{
            $objects = @(
                Get-ADObject -Server $domainRecord.DCFqdn `
                    -LDAPFilter $ldap `
                    -Properties objectSid,objectClass,sAMAccountName,userPrincipalName,ObjectGUID `
                    -ErrorAction Stop
            )

            foreach($obj in $objects){
                if($null -eq $obj.objectSid){ continue }

                [void]$matches.Add([pscustomobject]@{
                    DomainName        = $domainRecord.DomainName
                    DCFqdn            = $domainRecord.DCFqdn
                    ObjectClass       = [string]$obj.ObjectClass
                    Name              = [string]$obj.Name
                    SamAccountName    = [string]$obj.sAMAccountName
                    UserPrincipalName = [string]$obj.userPrincipalName
                    SID               = [string]$obj.objectSid
                    DistinguishedName = [string]$obj.DistinguishedName
                    ObjectGUID        = [Guid]$obj.ObjectGUID
                })
            }
        }catch{
            Write-AppLog "Ingress lookup failed in '$domainName': $($_.Exception.Message)" WARN
        }
    }

    $unique = @(
        $matches |
        Sort-Object SID -Unique
    )

    if($unique.Count -eq 0){
        throw "Ingress security principal '$SearchValue' was not found in the forest."
    }

    if($unique.Count -gt 1){
        $details = ($unique | ForEach-Object { "$($_.DomainName):$($_.DistinguishedName)" }) -join '; '
        throw "Ingress value '$SearchValue' resolved to multiple security principals: $details"
    }

    return $unique[0]
}

function Get-ComputerOUsForDomain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$DomainName
    )

    if($script:OUCache.ContainsKey($DomainName)){
        return @($script:OUCache[$DomainName])
    }

    $domain = Get-WritableDomainControllerRecord -DomainName $DomainName

    $ous = @(
        Get-ADOrganizationalUnit -Server $domain.DCFqdn `
            -Filter * `
            -Properties ObjectGUID,ProtectedFromAccidentalDeletion `
            -ErrorAction Stop |
        Select-Object Name,DistinguishedName,ObjectGUID,ProtectedFromAccidentalDeletion |
        Sort-Object DistinguishedName
    )

    $script:OUCache[$DomainName] = $ous
    return @($ous)
}

# =====================================================================================
# Naming / input
# =====================================================================================
function Test-ComputerNamePolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ComputerName,

        [int]$MaximumLength = 15,

        [bool]$RequireUppercase = $false,

        # ASCII letters, digits, and internal hyphen only.
        # Hyphen cannot be first or last.
        [string]$Pattern = '^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$'
    )

    $name = $ComputerName.Trim()

    if([string]::IsNullOrWhiteSpace($name)){
        return [pscustomobject]@{
            Valid  = $false
            Reason = 'Computer name is empty.'
        }
    }

    if($MaximumLength -lt 1 -or $MaximumLength -gt 63){
        return [pscustomobject]@{
            Valid  = $false
            Reason = 'Configured hostname length must be between 1 and 63 characters.'
        }
    }

    if($name.Length -ne $MaximumLength){
        return [pscustomobject]@{
            Valid  = $false
            Reason = "Hostname must contain exactly $MaximumLength characters. Current length: $($name.Length)."
        }
    }

    # Strict ASCII character policy.
    if($name -notmatch '^[A-Za-z0-9-]+$'){
        $invalidChars = @(
            $name.ToCharArray() |
            Where-Object {
                $_ -notmatch '[A-Za-z0-9-]'
            } |
            Select-Object -Unique
        )

        $display = if($invalidChars.Count -gt 0){
            ($invalidChars | ForEach-Object { "'$_'" }) -join ', '
        }else{
            'unknown'
        }

        return [pscustomobject]@{
            Valid  = $false
            Reason = "Invalid hostname character(s): $display. Allowed characters are A-Z, a-z, 0-9, and hyphen (-) only."
        }
    }

    if($name.StartsWith('-') -or $name.EndsWith('-')){
        return [pscustomobject]@{
            Valid  = $false
            Reason = 'Computer name cannot begin or end with a hyphen.'
        }
    }

    if($RequireUppercase -and $name -cne $name.ToUpperInvariant()){
        return [pscustomobject]@{
            Valid  = $false
            Reason = 'Configured naming policy requires uppercase letters.'
        }
    }

    try{
        if($name -notmatch $Pattern){
            return [pscustomobject]@{
                Valid  = $false
                Reason = 'Computer name does not match the configured hostname policy.'
            }
        }
    }
    catch{
        return [pscustomobject]@{
            Valid  = $false
            Reason = "Invalid naming-policy regex: $Pattern"
        }
    }

    return [pscustomobject]@{
        Valid  = $true
        Reason = 'Valid hostname.'
    }
}

function ConvertTo-ComputerNameList {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Text
    )

    if([string]::IsNullOrWhiteSpace($Text)){
        return @()
    }

    # Regex escapes \r and \n are intentional.
    # Do not use PowerShell backtick escapes inside this single-quoted regex.
    return @(
        $Text -split '[,;\r\n]+' |
        ForEach-Object {
            $_.Trim()
        } |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        } |
        Sort-Object -Unique
    )
}

# =====================================================================================
# AD object / ACL inspection
# =====================================================================================
function Get-ComputerAcrossForest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ComputerName)

    $matches = New-Object Collections.ArrayList

    foreach($domainName in @($script:Forest.Domains)){
        $domain = Get-WritableDomainControllerRecord -DomainName ([string]$domainName)

        try{
            $objects = @(
                Get-ADComputer -Server $domain.DCFqdn `
                    -LDAPFilter "(sAMAccountName=$ComputerName`$)" `
                    -Properties ObjectGUID,Enabled,DNSHostName,Description,userAccountControl,
                        PasswordNotRequired,whenCreated,whenChanged,LastLogonDate,
                        PasswordLastSet,OperatingSystem,OperatingSystemVersion `
                    -ErrorAction Stop
            )

            foreach($obj in $objects){
                [void]$matches.Add([pscustomobject]@{
                    DomainName = $domain.DomainName
                    DCFqdn     = $domain.DCFqdn
                    DCIPv4     = $domain.DCIPv4
                    Computer   = $obj
                })
            }
        }catch{
            Write-AppLog "Forest duplicate check failed in '$domainName' for '$ComputerName': $($_.Exception.Message)" WARN
        }
    }

    return @($matches)
}

function Get-ComputerAcl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Server,
        [Parameter(Mandatory=$true)][string]$DistinguishedName
    )

    $driveName = 'ADACL' + ([Guid]::NewGuid().ToString('N').Substring(0,6))

    try{
        New-PSDrive -Name $driveName -PSProvider ActiveDirectory `
            -Root '//RootDSE/' -Server $Server -Scope Script -ErrorAction Stop | Out-Null

        $path = '{0}:\{1}' -f $driveName,$DistinguishedName
        return Get-Acl -Path $path -ErrorAction Stop
    }
    finally{
        if(Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue){
            Remove-PSDrive -Name $driveName -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-RuleSIDString {
    param($Rule)

    try{
        if($Rule.IdentityReference -is [Security.Principal.SecurityIdentifier]){
            return $Rule.IdentityReference.Value
        }

        return $Rule.IdentityReference.Translate(
            [Security.Principal.SecurityIdentifier]
        ).Value
    }catch{
        return ''
    }
}

function Test-JoinAcl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Server,
        [Parameter(Mandatory=$true)][string]$DistinguishedName,
        [Parameter(Mandatory=$true)][string]$IngressSID
    )

    $acl = Get-ComputerAcl -Server $Server -DistinguishedName $DistinguishedName
    $ingressRules = @(
        $acl.Access |
        Where-Object {
            (Get-RuleSIDString -Rule $_) -eq $IngressSID -and
            $_.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow
        }
    )

    $result = [ordered]@{
        Owner                   = [string]$acl.Owner
        AclProtected            = [bool]$acl.AreAccessRulesProtected
        TotalIngressAces        = [int]$ingressRules.Count
        ExplicitIngressAces     = [int]@($ingressRules | Where-Object { -not $_.IsInherited }).Count
        InheritedIngressAces    = [int]@($ingressRules | Where-Object { $_.IsInherited }).Count
        ResetPassword           = $false
        ResetPasswordSource     = 'MISSING'
        ValidatedDns            = $false
        ValidatedDnsSource      = 'MISSING'
        ValidatedSpn            = $false
        ValidatedSpnSource      = 'MISSING'
        AccountRestrictions     = $false
        AccountRestrictionsSource = 'MISSING'
        ChangePassword          = $false
        AllowedToAuthenticate   = $false
    }

    foreach($rule in $ingressRules){
        $objectType = [Guid]$rule.ObjectType
        $rights = [DirectoryServices.ActiveDirectoryRights]$rule.ActiveDirectoryRights
        $source = if($rule.IsInherited){'INHERITED'}else{'EXPLICIT'}

        foreach($key in @($script:JoinRights.Keys)){
            $def = $script:JoinRights[$key]
            if($objectType -eq $def.Guid -and (($rights -band $def.RequiredMask) -ne 0)){
                $result[$key] = $true
                $result["${key}Source"] = $source
            }
        }

        if($objectType -eq $script:AdditionalAuditRights.ChangePassword.Guid){
            $result.ChangePassword = $true
        }

        if($objectType -eq $script:AdditionalAuditRights.AllowedToAuthenticate.Guid){
            $result.AllowedToAuthenticate = $true
        }
    }

    $result.CoreCompliant = (
        $result.ResetPassword -and
        $result.ValidatedDns -and
        $result.ValidatedSpn -and
        $result.AccountRestrictions
    )

    $result.CoreSummary = @(
        "ResetPassword=$($result.ResetPasswordSource)"
        "DNS=$($result.ValidatedDnsSource)"
        "SPN=$($result.ValidatedSpnSource)"
        "AcctRestrictions=$($result.AccountRestrictionsSource)"
    ) -join '; '

    return [pscustomobject]$result
}

function Add-MissingLegacyJoinAces {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)][string]$Server,
        [Parameter(Mandatory=$true)][string]$DistinguishedName,
        [Parameter(Mandatory=$true)][Guid]$ExpectedObjectGUID,
        [Parameter(Mandatory=$true)][Security.Principal.SecurityIdentifier]$IngressSID
    )

    $current = Get-ADComputer -Identity $DistinguishedName -Server $Server `
        -Properties ObjectGUID -ErrorAction Stop

    if([Guid]$current.ObjectGUID -ne $ExpectedObjectGUID){
        throw 'ObjectGUID changed before ACL remediation.'
    }

    $before = Test-JoinAcl -Server $Server -DistinguishedName $DistinguishedName `
        -IngressSID $IngressSID.Value

    if($before.CoreCompliant){
        return [pscustomobject]@{
            Changed=$false
            AddedRights=''
            Detail='Core domain-join ACL already compliant; no explicit ACE added.'
        }
    }

    if(-not $PSCmdlet.ShouldProcess($DistinguishedName,'Add only missing core domain-join ACEs')){
        return [pscustomobject]@{
            Changed=$false
            AddedRights=''
            Detail='ShouldProcess declined ACL remediation.'
        }
    }

    $ldapPath = "LDAP://$Server/$DistinguishedName"
    $entry = New-Object DirectoryServices.DirectoryEntry($ldapPath)

    try{
        $security = $entry.ObjectSecurity
        $added = New-Object Collections.Generic.List[string]

        if(-not $before.ResetPassword){
            $rule = New-Object DirectoryServices.ExtendedRightAccessRule(
                $IngressSID,
                [Security.AccessControl.AccessControlType]::Allow,
                $script:JoinRights.ResetPassword.Guid
            )
            $security.AddAccessRule($rule)
            $added.Add('Reset Password')
        }

        if(-not $before.ValidatedDns){
            $rule = New-Object DirectoryServices.ActiveDirectoryAccessRule(
                $IngressSID,
                [DirectoryServices.ActiveDirectoryRights]::Self,
                [Security.AccessControl.AccessControlType]::Allow,
                $script:JoinRights.ValidatedDns.Guid
            )
            $security.AddAccessRule($rule)
            $added.Add('Validated Write DNS Host Name')
        }

        if(-not $before.ValidatedSpn){
            $rule = New-Object DirectoryServices.ActiveDirectoryAccessRule(
                $IngressSID,
                [DirectoryServices.ActiveDirectoryRights]::Self,
                [Security.AccessControl.AccessControlType]::Allow,
                $script:JoinRights.ValidatedSpn.Guid
            )
            $security.AddAccessRule($rule)
            $added.Add('Validated Write SPN')
        }

        if(-not $before.AccountRestrictions){
            $rule = New-Object DirectoryServices.ActiveDirectoryAccessRule(
                $IngressSID,
                [DirectoryServices.ActiveDirectoryRights]::WriteProperty,
                [Security.AccessControl.AccessControlType]::Allow,
                $script:JoinRights.AccountRestrictions.Guid
            )
            $security.AddAccessRule($rule)
            $added.Add('Write Account Restrictions')
        }

        if($added.Count -gt 0){
            $entry.ObjectSecurity = $security
            $entry.CommitChanges()
        }

        $after = Test-JoinAcl -Server $Server -DistinguishedName $DistinguishedName `
            -IngressSID $IngressSID.Value

        if(-not $after.CoreCompliant){
            throw "ACL remediation completed but core compliance verification failed: $($after.CoreSummary)"
        }

        return [pscustomobject]@{
            Changed=($added.Count -gt 0)
            AddedRights=($added -join '; ')
            Detail="ACL verified after remediation. $($after.CoreSummary)"
        }
    }
    finally{
        $entry.Dispose()
    }
}

function Get-OwnerTrustAssessment {
    param(
        [string]$Owner,
        [string]$DomainName
    )

    # This is intentionally an assessment rather than an automatic ownership change.
    # Known production baseline owner is Enterprise Admins.
    $normalized = $Owner.ToLowerInvariant()

    if($normalized -match 'administradores de empresa|enterprise admins'){
        return 'TRUSTED-ADMIN-BASELINE'
    }

    if($normalized -match 'administradores do domínio|domain admins|builtin\\administradores|builtin\\administrators'){
        return 'TRUSTED-ADMIN-BASELINE'
    }

    return 'REVIEW-ACCOUNT-REUSE-POLICY'
}

# =====================================================================================
# Existing computer activity / reuse assessment
# =====================================================================================
function Get-ComputerReuseAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Computer,
        [ValidateRange(30,3650)][int]$ReuseAfterDays = 90
    )

    $now = Get-Date
    $cutoff = $now.AddDays(-$ReuseAfterDays)

    $lastLogon = $Computer.LastLogonDate
    $passwordLastSet = $Computer.PasswordLastSet
    $created = $Computer.whenCreated

    $isServer = (
        ([string]$Computer.OperatingSystem -like '*Server*')
    )

    if($isServer){
        return [pscustomobject]@{
            Reusable=$false
            Activity='PROTECTED'
            LastLogonDate=$lastLogon
            PasswordLastSet=$passwordLastSet
            InactiveDays=$null
            Reason='Existing object reports a Windows Server operating system; automatic workstation-name reuse is blocked.'
        }
    }

    # Any recent replicated activity is enough to classify the object as ACTIVE.
    if($lastLogon -and $lastLogon -ge $cutoff){
        return [pscustomobject]@{
            Reusable=$false
            Activity='ACTIVE'
            LastLogonDate=$lastLogon
            PasswordLastSet=$passwordLastSet
            InactiveDays=[int][math]::Floor(($now-$lastLogon).TotalDays)
            Reason="LastLogonDate is within the configured $ReuseAfterDays-day activity window."
        }
    }

    if($passwordLastSet -and $passwordLastSet -ge $cutoff){
        return [pscustomobject]@{
            Reusable=$false
            Activity='ACTIVE'
            LastLogonDate=$lastLogon
            PasswordLastSet=$passwordLastSet
            InactiveDays=[int][math]::Floor(($now-$passwordLastSet).TotalDays)
            Reason="PasswordLastSet is within the configured $ReuseAfterDays-day activity window."
        }
    }

    # If both signals are absent, do not reuse a recently created object.
    if(-not $lastLogon -and -not $passwordLastSet -and $created -and $created -ge $cutoff){
        return [pscustomobject]@{
            Reusable=$false
            Activity='ACTIVE/NEW'
            LastLogonDate=$null
            PasswordLastSet=$null
            InactiveDays=[int][math]::Floor(($now-$created).TotalDays)
            Reason="No activity timestamps are populated, but the object was created within the configured $ReuseAfterDays-day window."
        }
    }

    $reference = $null
    if($lastLogon -and $passwordLastSet){
        $reference = if($lastLogon -gt $passwordLastSet){$lastLogon}else{$passwordLastSet}
    }elseif($lastLogon){
        $reference = $lastLogon
    }elseif($passwordLastSet){
        $reference = $passwordLastSet
    }elseif($created){
        $reference = $created
    }

    $inactiveDays = if($reference){
        [int][math]::Floor(($now-$reference).TotalDays)
    }else{
        $null
    }

    return [pscustomobject]@{
        Reusable=$true
        Activity='STALE'
        LastLogonDate=$lastLogon
        PasswordLastSet=$passwordLastSet
        InactiveDays=$inactiveDays
        Reason="No recent computer activity was found inside the configured $ReuseAfterDays-day window."
    }
}

# =====================================================================================
# Candidate preparation
# =====================================================================================
function New-CandidateRecord {
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)]$DomainRecord,
        [Parameter(Mandatory=$true)]$OU,
        [int]$MaximumLength = 15,
        [bool]$RequireUppercase = $false,
        [string]$NamePattern = '^[A-Za-z0-9-]+$',
        [ValidateRange(30,3650)][int]$ReuseAfterDays = 90,
        [bool]$AllowReIngress = $false
    )

    $policy = Test-ComputerNamePolicy -ComputerName $ComputerName -MaximumLength $MaximumLength -RequireUppercase $RequireUppercase -Pattern $NamePattern

    if(-not $policy.Valid){
        return [pscustomobject]@{
            ComputerName=$ComputerName
            Domain=$DomainRecord.DomainName
            DC=$DomainRecord.DCFqdn
            DCIPv4=$DomainRecord.DCIPv4
            TargetOU=$OU.DistinguishedName
            Existing='INVALID'
            ExistingDN=''
            ObjectGUID=''
            Owner=''
            OwnerAssessment=''
            PwdNotRequired=''
            UAC=''
            CoreAcl='NOT CHECKED'
            ResetPassword=''
            ValidatedDNS=''
            ValidatedSPN=''
            AccountRestrictions=''
            Activity=''
            LastLogonDate=''
            PasswordLastSet=''
            InactiveDays=''
            PlannedAction='BLOCKED'
            Status='INVALID NAME'
            Detail=$policy.Reason
        }
    }

    $matches = @(Get-ComputerAcrossForest -ComputerName $ComputerName)

    if($matches.Count -gt 1){
        return [pscustomobject]@{
            ComputerName=$ComputerName
            Domain=$DomainRecord.DomainName
            DC=$DomainRecord.DCFqdn
            DCIPv4=$DomainRecord.DCIPv4
            TargetOU=$OU.DistinguishedName
            Existing='MULTIPLE'
            ExistingDN=($matches.Computer.DistinguishedName -join ' | ')
            ObjectGUID=''
            Owner=''
            OwnerAssessment=''
            PwdNotRequired=''
            UAC=''
            CoreAcl='NOT CHECKED'
            ResetPassword=''
            ValidatedDNS=''
            ValidatedSPN=''
            AccountRestrictions=''
            Activity=''
            LastLogonDate=''
            PasswordLastSet=''
            InactiveDays=''
            PlannedAction='BLOCKED'
            Status='FOREST CONFLICT'
            Detail='Computer name exists in more than one forest domain.'
        }
    }

    if($matches.Count -eq 1){
        $match = $matches[0]
        $computer = $match.Computer

        $acl = Test-JoinAcl -Server $match.DCFqdn `
            -DistinguishedName $computer.DistinguishedName `
            -IngressSID $script:Ingress.SID

        $sameDomain = ($match.DomainName -eq $DomainRecord.DomainName)
        $sameOU = ((($computer.DistinguishedName -split '(?<!\\),',2)[1]) -eq $OU.DistinguishedName)
        $reuse = Get-ComputerReuseAssessment -Computer $computer -ReuseAfterDays $ReuseAfterDays

        $action = if(-not $sameDomain){
            'BLOCKED'
        }elseif(-not $reuse.Reusable){
            'BLOCKED'
        }elseif(-not $AllowReIngress){
            'BLOCKED'
        }elseif($sameOU){
            'CONTROLLED RE-INGRESS'
        }else{
            'RE-INGRESS + OPTIONAL MOVE'
        }

        $status = if(-not $sameDomain){
            'EXISTS OTHER DOMAIN'
        }elseif(-not $reuse.Reusable){
            'ACTIVE - RE-INGRESS BLOCKED'
        }elseif(-not $AllowReIngress){
            'STALE - RE-INGRESS NOT ENABLED'
        }elseif($sameOU){
            'STALE - RE-INGRESS READY'
        }else{
            'STALE - RE-INGRESS READY OTHER OU'
        }

        return [pscustomobject]@{
            ComputerName=$ComputerName
            Domain=$match.DomainName
            DC=$match.DCFqdn
            DCIPv4=$match.DCIPv4
            TargetOU=$OU.DistinguishedName
            Existing='YES'
            ExistingDN=$computer.DistinguishedName
            ObjectGUID=[string]$computer.ObjectGUID
            Owner=$acl.Owner
            OwnerAssessment=(Get-OwnerTrustAssessment -Owner $acl.Owner -DomainName $match.DomainName)
            PwdNotRequired=[string]$computer.PasswordNotRequired
            UAC=[string]$computer.userAccountControl
            CoreAcl=$(if($acl.CoreCompliant){'COMPLIANT'}else{'INCOMPLETE'})
            ResetPassword=$acl.ResetPasswordSource
            ValidatedDNS=$acl.ValidatedDnsSource
            ValidatedSPN=$acl.ValidatedSpnSource
            AccountRestrictions=$acl.AccountRestrictionsSource
            Activity=$reuse.Activity
            LastLogonDate=$(if($reuse.LastLogonDate){$reuse.LastLogonDate.ToString('yyyy-MM-dd HH:mm:ss')}else{''})
            PasswordLastSet=$(if($reuse.PasswordLastSet){$reuse.PasswordLastSet.ToString('yyyy-MM-dd HH:mm:ss')}else{''})
            InactiveDays=$(if($null-ne$reuse.InactiveDays){[string]$reuse.InactiveDays}else{''})
            PlannedAction=$action
            Status=$status
            Detail="$($reuse.Reason) $($acl.CoreSummary)"
        }
    }

    return [pscustomobject]@{
        ComputerName=$ComputerName
        Domain=$DomainRecord.DomainName
        DC=$DomainRecord.DCFqdn
        DCIPv4=$DomainRecord.DCIPv4
        TargetOU=$OU.DistinguishedName
        Existing='NO'
        ExistingDN=''
        ObjectGUID=''
        Owner=''
        OwnerAssessment='PENDING CREATE'
        PwdNotRequired=''
        UAC=''
        CoreAcl='PENDING CREATE'
        ResetPassword=''
        ValidatedDNS=''
        ValidatedSPN=''
        AccountRestrictions=''
        PlannedAction='CREATE + VERIFY'
        Status='READY'
        Detail='Computer name does not currently exist in the forest.'
    }
}

# =====================================================================================
# Searchable/sortable GUI result handling
# =====================================================================================
function Set-CandidateList {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [object[]]$Rows
    )

    $selected = @{}
    foreach($item in $script:listView.CheckedItems){
        if($item.Tag){
            $selected[[string]$item.Tag.ComputerName] = $true
        }
    }

    $script:listView.BeginUpdate()
    try{
        $script:listView.Items.Clear()

        foreach($row in $Rows){
            $item = New-Object Windows.Forms.ListViewItem([string]$row.ComputerName)

            foreach($value in @(
                $row.Domain,$row.DC,$row.DCIPv4,$row.TargetOU,$row.Existing,$row.ExistingDN,
                $row.Owner,$row.OwnerAssessment,$row.PwdNotRequired,$row.UAC,$row.CoreAcl,
                $row.ResetPassword,$row.ValidatedDNS,$row.ValidatedSPN,$row.AccountRestrictions,
                $row.PlannedAction,$row.Status,$row.Detail
            )){
                [void]$item.SubItems.Add([string]$value)
            }

            $item.Tag = $row

            if($selected.ContainsKey([string]$row.ComputerName) -and $row.PlannedAction -ne 'BLOCKED'){
                $item.Checked = $true
            }

            [void]$script:listView.Items.Add($item)
        }
    }
    finally{
        $script:listView.EndUpdate()
    }
}

function Test-CandidateMatchesFilter {
    param($Row,[string]$Filter)

    if([string]::IsNullOrWhiteSpace($Filter)){
        return $true
    }

    $needle = $Filter.Trim()

    foreach($property in @(
        'ComputerName','Domain','DC','DCIPv4','TargetOU','Existing','ExistingDN','Owner',
        'OwnerAssessment','PwdNotRequired','UAC','CoreAcl','ResetPassword','ValidatedDNS',
        'ValidatedSPN','AccountRestrictions','Activity','LastLogonDate','PasswordLastSet',
        'InactiveDays','PlannedAction','Status','Detail'
    )){
        if(([string]$Row.$property).IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0){
            return $true
        }
    }

    return $false
}

function Apply-CandidateFilter {
    param([string]$Filter)

    $script:Displayed = @(
        $script:Candidates |
        Where-Object {
            Test-CandidateMatchesFilter -Row $_ -Filter $Filter
        }
    )

    Set-CandidateList -Rows $script:Displayed

    $ready = @($script:Candidates | Where-Object { $_.PlannedAction -ne 'BLOCKED' }).Count
    $blocked = $script:Candidates.Count - $ready

    $summaryLabel.Text = "Provisioning List: $($script:Candidates.Count) | Actionable: $ready | Blocked: $blocked | Displayed: $($script:Displayed.Count)"
}

function Sort-Candidates {
    param([int]$Column)

    if($script:SortColumn -eq $Column){
        $script:SortDescending = -not $script:SortDescending
    }else{
        $script:SortColumn = $Column
        $script:SortDescending = $false
    }

    $properties = @(
        'ComputerName','Domain','DC','DCIPv4','TargetOU','Existing','ExistingDN','Owner',
        'OwnerAssessment','PwdNotRequired','UAC','CoreAcl','ResetPassword','ValidatedDNS',
        'ValidatedSPN','AccountRestrictions','Activity','LastLogonDate','PasswordLastSet',
        'InactiveDays','PlannedAction','Status','Detail'
    )

    $property = if($Column -ge 0 -and $Column -lt $properties.Count){
        $properties[$Column]
    }else{
        'ComputerName'
    }

    $script:Candidates = @(
        $script:Candidates |
        Sort-Object -Property $property -Descending:$script:SortDescending
    )

    Apply-CandidateFilter -Filter $txtFilter.Text
}

function Get-CheckedCandidates {
    $rows = New-Object Collections.ArrayList

    foreach($item in $script:listView.CheckedItems){
        if($item.Tag -and $item.Tag.PlannedAction -ne 'BLOCKED'){
            [void]$rows.Add($item.Tag)
        }
    }

    return @($rows)
}

# =====================================================================================
# Provisioning / verification
# =====================================================================================
function Invoke-CandidateCommit {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)]$Candidate,
        [Parameter(Mandatory=$true)][string]$Description,
        [Parameter(Mandatory=$true)][bool]$LegacyPasswordNotRequired,
        [Parameter(Mandatory=$true)][bool]$RemediateMissingAcl,
        [ValidateRange(30,3650)][int]$ReuseAfterDays = 90,
        [bool]$MoveReusedToTargetOU = $false,
        [bool]$AllowReIngress = $false
    )

    $result = [ordered]@{
        ComputerName=$Candidate.ComputerName
        Domain=$Candidate.Domain
        DC=$Candidate.DC
        DCIPv4=$Candidate.DCIPv4
        TargetOU=$Candidate.TargetOU
        Action=''
        Result=''
        Owner=''
        OwnerAssessment=''
        ObjectGUID=''
        PwdNotRequired=''
        UAC=''
        CoreAcl=''
        ResetPassword=''
        ValidatedDNS=''
        ValidatedSPN=''
        AccountRestrictions=''
        Activity=''
        LastLogonDate=''
        PasswordLastSet=''
        InactiveDays=''
        Detail=''
    }

    try{
        $computer = $null
        $action = ''

        if($Candidate.Existing -eq 'NO'){
            $action = 'CREATE'

            if($PSCmdlet.ShouldProcess(
                "$($Candidate.ComputerName) in $($Candidate.TargetOU)",
                'Pre-stage Active Directory computer account'
            )){
                $params = @{
                    Name        = $Candidate.ComputerName
                    SamAccountName = ($Candidate.ComputerName + '$')
                    Path        = $Candidate.TargetOU
                    Description = $Description
                    Server      = $Candidate.DC
                    PassThru    = $true
                    ErrorAction = 'Stop'
                }

                if($LegacyPasswordNotRequired){
                    $params['PasswordNotRequired'] = $true
                }

                $computer = New-ADComputer @params

                $computer = Get-ADComputer -Identity $computer.DistinguishedName `
                    -Server $Candidate.DC `
                    -Properties ObjectGUID,Enabled,DNSHostName,Description,userAccountControl,
                        PasswordNotRequired,whenCreated,whenChanged `
                    -ErrorAction Stop

                Write-AppLog "Created computer '$($Candidate.ComputerName)' on '$($Candidate.DC)' in '$($Candidate.TargetOU)'." SUCCESS
            }
        }
        else{
            if(-not $AllowReIngress){
                throw 'Existing computer requires explicit Controlled Re-Ingress authorization.'
            }

            $action = 'RE-INGRESS'
            $computer = Get-ADComputer -Identity $Candidate.ExistingDN `
                -Server $Candidate.DC `
                -Properties ObjectGUID,Enabled,DNSHostName,Description,userAccountControl,
                    PasswordNotRequired,whenCreated,whenChanged,LastLogonDate,
                    PasswordLastSet,OperatingSystem,OperatingSystemVersion `
                -ErrorAction Stop

            if([string]$computer.ObjectGUID -ne [string]$Candidate.ObjectGUID){
                throw 'Existing computer ObjectGUID changed since preview.'
            }

            $reuseNow = Get-ComputerReuseAssessment -Computer $computer -ReuseAfterDays $ReuseAfterDays
            if(-not $reuseNow.Reusable){
                throw "Reuse blocked during commit revalidation: $($reuseNow.Reason)"
            }

            $currentParent = ($computer.DistinguishedName -split '(?<!\\),',2)[1]
            if($MoveReusedToTargetOU -and $currentParent -ne $Candidate.TargetOU){
                if($PSCmdlet.ShouldProcess($computer.DistinguishedName,"Move stale reused computer to '$($Candidate.TargetOU)'")){
                    Move-ADObject -Identity $computer.DistinguishedName `
                        -TargetPath $Candidate.TargetOU `
                        -Server $Candidate.DC `
                        -Confirm:$false `
                        -ErrorAction Stop

                    $computer = Get-ADComputer -Identity $computer.ObjectGUID `
                        -Server $Candidate.DC `
                        -Properties ObjectGUID,Enabled,DNSHostName,Description,userAccountControl,
                            PasswordNotRequired,whenCreated,whenChanged,LastLogonDate,
                            PasswordLastSet,OperatingSystem,OperatingSystemVersion `
                        -ErrorAction Stop

                    Write-AppLog "Moved re-ingress computer '$($Candidate.ComputerName)' to '$($Candidate.TargetOU)'." SUCCESS
                }
            }

            if(-not $computer.Enabled){
                if($PSCmdlet.ShouldProcess($computer.DistinguishedName,'Enable stale reused computer account')){
                    Set-ADComputer -Identity $computer.DistinguishedName -Enabled $true `
                        -Server $Candidate.DC -ErrorAction Stop
                    $computer = Get-ADComputer -Identity $computer.ObjectGUID -Server $Candidate.DC `
                        -Properties ObjectGUID,Enabled,DNSHostName,Description,userAccountControl,
                            PasswordNotRequired,whenCreated,whenChanged,LastLogonDate,
                            PasswordLastSet,OperatingSystem,OperatingSystemVersion `
                        -ErrorAction Stop
                    Write-AppLog "Enabled re-ingress computer '$($Candidate.ComputerName)' for controlled re-ingress." SUCCESS
                }
            }
        }

        if($null -eq $computer){
            throw 'Computer object was not available after the requested operation.'
        }

        $acl = Test-JoinAcl -Server $Candidate.DC `
            -DistinguishedName $computer.DistinguishedName `
            -IngressSID $script:Ingress.SID

        $remediationDetail = ''

        if(-not $acl.CoreCompliant){
            if($RemediateMissingAcl){
                $sid = New-Object Security.Principal.SecurityIdentifier($script:Ingress.SID)

                $remediation = Add-MissingLegacyJoinAces `
                    -Server $Candidate.DC `
                    -DistinguishedName $computer.DistinguishedName `
                    -ExpectedObjectGUID ([Guid]$computer.ObjectGUID) `
                    -IngressSID $sid `
                    -Confirm:$false

                $remediationDetail = $remediation.Detail

                $acl = Test-JoinAcl -Server $Candidate.DC `
                    -DistinguishedName $computer.DistinguishedName `
                    -IngressSID $script:Ingress.SID
            }
            else{
                $remediationDetail = 'Core ACL incomplete and remediation is disabled.'
            }
        }
        else{
            $remediationDetail = 'Inherited/explicit ACL already satisfies the configured core domain-join authorization baseline.'
        }

        $result.Action = $action
        $result.Result = if($acl.CoreCompliant){'SUCCESS'}else{'WARNING'}
        $result.Owner = $acl.Owner
        $result.OwnerAssessment = Get-OwnerTrustAssessment -Owner $acl.Owner -DomainName $Candidate.Domain
        $result.ObjectGUID = [string]$computer.ObjectGUID
        $result.PwdNotRequired = [string]$computer.PasswordNotRequired
        $result.UAC = [string]$computer.userAccountControl
        $result.CoreAcl = if($acl.CoreCompliant){'COMPLIANT'}else{'INCOMPLETE'}
        $result.ResetPassword = $acl.ResetPasswordSource
        $result.ValidatedDNS = $acl.ValidatedDnsSource
        $result.ValidatedSPN = $acl.ValidatedSpnSource
        $result.AccountRestrictions = $acl.AccountRestrictionsSource
        $postActivity = Get-ComputerReuseAssessment -Computer $computer -ReuseAfterDays $ReuseAfterDays
        $result.Activity = $postActivity.Activity
        $result.LastLogonDate = $(if($postActivity.LastLogonDate){$postActivity.LastLogonDate.ToString('yyyy-MM-dd HH:mm:ss')}else{''})
        $result.PasswordLastSet = $(if($postActivity.PasswordLastSet){$postActivity.PasswordLastSet.ToString('yyyy-MM-dd HH:mm:ss')}else{''})
        $result.InactiveDays = $(if($null-ne$postActivity.InactiveDays){[string]$postActivity.InactiveDays}else{''})
        $result.Detail = "$($acl.CoreSummary); $remediationDetail"

        if($acl.CoreCompliant){
            Write-AppLog "Verified '$($Candidate.ComputerName)': $($acl.CoreSummary); Owner='$($acl.Owner)'." SUCCESS
        }else{
            Write-AppLog "Computer '$($Candidate.ComputerName)' remains JOIN-PERMISSIONS-INCOMPLETE: $($acl.CoreSummary)." WARN
        }
    }
    catch{
        $result.Action = if($result.Action){$result.Action}else{'ERROR'}
        $result.Result = 'FAILED'
        $result.Detail = $_.Exception.Message
        Write-AppLog "Provisioning failed for '$($Candidate.ComputerName)': $($_.Exception.Message)" ERROR
    }

    return [pscustomobject]$result
}

# =====================================================================================
# GUI construction
# =====================================================================================
$form = New-Object Windows.Forms.Form
$form.Text = "$($script:AppName) - v$($script:AppVersion)"
$form.Size = New-Object Drawing.Size(1180,760)
$form.MinimumSize = New-Object Drawing.Size(980,680)
$form.StartPosition = 'CenterScreen'

$main = New-Object Windows.Forms.TableLayoutPanel
$main.Dock = 'Fill'
$main.Padding = New-Object Windows.Forms.Padding(10)
$main.ColumnCount = 1
$main.RowCount = 9
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',72)))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',28)))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$form.Controls.Add($main)

# Row 1: domain / OU controls - responsive two-row layout
$pDomain = New-Object Windows.Forms.TableLayoutPanel
$pDomain.Dock='Fill'
$pDomain.AutoSize=$true
$pDomain.ColumnCount=6
$pDomain.RowCount=2

$pDomain.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pDomain.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',35)))
$pDomain.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pDomain.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',65)))
$pDomain.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pDomain.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))

$lblDomain=New-Object Windows.Forms.Label
$lblDomain.Text='Domain:'
$lblDomain.AutoSize=$true
$lblDomain.Anchor='Left'
$lblDomain.Margin=New-Object Windows.Forms.Padding(3,7,6,3)
$pDomain.Controls.Add($lblDomain,0,0)

$cmbDomain=New-Object Windows.Forms.ComboBox
$cmbDomain.Dock='Fill'
$cmbDomain.DropDownStyle='DropDownList'
$pDomain.Controls.Add($cmbDomain,1,0)

$lblOUSearch=New-Object Windows.Forms.Label
$lblOUSearch.Text='OU Search:'
$lblOUSearch.AutoSize=$true
$lblOUSearch.Anchor='Left'
$lblOUSearch.Margin=New-Object Windows.Forms.Padding(12,7,6,3)
$pDomain.Controls.Add($lblOUSearch,2,0)

$txtOUSearch=New-Object Windows.Forms.TextBox
$txtOUSearch.Dock='Fill'
$txtOUSearch.Text='OU to Join Computers'
$txtOUSearch.Tag='Default search only. Clear to display all OUs.'
$pDomain.Controls.Add($txtOUSearch,3,0)

$btnReload=New-Object Windows.Forms.Button
$btnReload.Text='Reload OUs'
$btnReload.Width=90
$pDomain.Controls.Add($btnReload,4,0)

$lblDC=New-Object Windows.Forms.Label
$lblDC.AutoSize=$true
$lblDC.Text='DC: -'
$lblDC.Visible=$false

$lblOU=New-Object Windows.Forms.Label
$lblOU.Text='Target OU:'
$lblOU.AutoSize=$true
$lblOU.Anchor='Left'
$lblOU.Margin=New-Object Windows.Forms.Padding(3,7,6,3)
$pDomain.Controls.Add($lblOU,0,1)

$cmbOU=New-Object Windows.Forms.ComboBox
$cmbOU.Dock='Fill'
$cmbOU.DropDownStyle='DropDownList'
$cmbOU.DisplayMember='DistinguishedName'
$pDomain.Controls.Add($cmbOU,1,1)
$pDomain.SetColumnSpan($cmbOU,4)

$main.Controls.Add($pDomain,0,0)

# Row 2: principal / settings - aligned enterprise layout
$pSettings=New-Object Windows.Forms.TableLayoutPanel
$pSettings.Dock='Fill'
$pSettings.AutoSize=$true
$pSettings.ColumnCount=8
$pSettings.RowCount=4
$pSettings.Margin=New-Object Windows.Forms.Padding(0,3,0,3)

# Label | Value | Label | Value | Option | Option | Option | Status/Option
$pSettings.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',140)))
$pSettings.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',28)))
$pSettings.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',135)))
$pSettings.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',32)))
$pSettings.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pSettings.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pSettings.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pSettings.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',40)))

# -------------------------------------------------------------------------
# Row 1 - Domain Join Account
# -------------------------------------------------------------------------
$lblIngress=New-Object Windows.Forms.Label
$lblIngress.Text='Domain Join Account:'
$lblIngress.AutoSize=$true
$lblIngress.Anchor='Left'
$lblIngress.Margin=New-Object Windows.Forms.Padding(3,7,6,3)
$pSettings.Controls.Add($lblIngress,0,0)

$txtIngress=New-Object Windows.Forms.TextBox
$txtIngress.Dock='Fill'
$txtIngress.Text=''
$pSettings.Controls.Add($txtIngress,1,0)

$lblIngressStatus=New-Object Windows.Forms.Label
$lblIngressStatus.Text='Principal: not configured'
$lblIngressStatus.AutoSize=$true
$lblIngressStatus.Anchor='Left'
$lblIngressStatus.Margin=New-Object Windows.Forms.Padding(8,7,6,3)
$pSettings.Controls.Add($lblIngressStatus,2,0)
$pSettings.SetColumnSpan($lblIngressStatus,2)

$btnValidatePrincipal=New-Object Windows.Forms.Button
$btnValidatePrincipal.Text='Join Account'
$btnValidatePrincipal.Width=100
$btnValidatePrincipal.Margin=New-Object Windows.Forms.Padding(8,3,6,3)
$pSettings.Controls.Add($btnValidatePrincipal,4,0)

$lblPrincipalState=New-Object Windows.Forms.Label
$lblPrincipalState.Text='NOT VALIDATED'
$lblPrincipalState.AutoSize=$true
$lblPrincipalState.Anchor='Left'
$lblPrincipalState.Margin=New-Object Windows.Forms.Padding(4,7,3,3)
$pSettings.Controls.Add($lblPrincipalState,5,0)
$pSettings.SetColumnSpan($lblPrincipalState,3)

# -------------------------------------------------------------------------
# Row 2 - Description / execution options
# -------------------------------------------------------------------------
$lblDescription=New-Object Windows.Forms.Label
$lblDescription.Text='Description:'
$lblDescription.AutoSize=$true
$lblDescription.Anchor='Left'
$lblDescription.Margin=New-Object Windows.Forms.Padding(3,7,6,3)
$pSettings.Controls.Add($lblDescription,0,1)

$txtDescription=New-Object Windows.Forms.TextBox
$txtDescription.Dock='Fill'
$txtDescription.Text='Pre-staged Active Directory computer account'
$pSettings.Controls.Add($txtDescription,1,1)
$pSettings.SetColumnSpan($txtDescription,3)

$chkDryRun=New-Object Windows.Forms.CheckBox
$chkDryRun.Text='Dry Run'
$chkDryRun.Checked=$true
$chkDryRun.AutoSize=$true
$chkDryRun.Margin=New-Object Windows.Forms.Padding(8,7,8,3)
$pSettings.Controls.Add($chkDryRun,4,1)

$chkRemediate=New-Object Windows.Forms.CheckBox
$chkRemediate.Text='Ensure Join Permissions'
$chkRemediate.Checked=$true
$chkRemediate.AutoSize=$true
$chkRemediate.Margin=New-Object Windows.Forms.Padding(8,7,8,3)
$pSettings.Controls.Add($chkRemediate,5,1)

$chkLegacyPwd=New-Object Windows.Forms.CheckBox
$chkLegacyPwd.Text='PwdNotRequired'
$chkLegacyPwd.Checked=$false
$chkLegacyPwd.AutoSize=$true
$chkLegacyPwd.Margin=New-Object Windows.Forms.Padding(8,7,8,3)
$chkLegacyPwd.Tag='Legacy compatibility: set PasswordNotRequired.'
$pSettings.Controls.Add($chkLegacyPwd,6,1)

$chkReIngress=New-Object Windows.Forms.CheckBox
$chkReIngress.Text='Allow Controlled Re-Ingress'
$chkReIngress.Checked=$false
$chkReIngress.AutoSize=$true
$chkReIngress.Margin=New-Object Windows.Forms.Padding(8,7,3,3)
$chkReIngress.Tag='Allows reuse only for an existing computer classified STALE. ACTIVE computer names remain blocked.'
$pSettings.Controls.Add($chkReIngress,7,1)

# -------------------------------------------------------------------------
# Row 3 - Hostname policy
# -------------------------------------------------------------------------
$lblMaxLength=New-Object Windows.Forms.Label
$lblMaxLength.Text='Hostname Length:'
$lblMaxLength.AutoSize=$true
$lblMaxLength.Anchor='Left'
$lblMaxLength.Margin=New-Object Windows.Forms.Padding(3,7,6,3)
$pSettings.Controls.Add($lblMaxLength,0,2)

$numMaxLength=New-Object Windows.Forms.NumericUpDown
$numMaxLength.Minimum=1
$numMaxLength.Maximum=63
$numMaxLength.Value=15
$numMaxLength.Width=70
$numMaxLength.Anchor='Left'
$pSettings.Controls.Add($numMaxLength,1,2)

$chkUppercase=New-Object Windows.Forms.CheckBox
$chkUppercase.Text='Require Uppercase'
$chkUppercase.Checked=$true
$chkUppercase.AutoSize=$true
$chkUppercase.Margin=New-Object Windows.Forms.Padding(8,7,8,3)
$pSettings.Controls.Add($chkUppercase,2,2)

$lblHostnameExample=New-Object Windows.Forms.Label
$lblHostnameExample.Text='Hostname Example: NYCLACCOUN37890'
$lblHostnameExample.AutoSize=$true
$lblHostnameExample.Anchor='Left'
$lblHostnameExample.Margin=New-Object Windows.Forms.Padding(8,7,8,3)
$pSettings.Controls.Add($lblHostnameExample,3,2)
$pSettings.SetColumnSpan($lblHostnameExample,2)

$lblHostnameRule=New-Object Windows.Forms.Label
$lblHostnameRule.Text='Exactly 15 chars | A-Z, 0-9, hyphen (-) only'
$lblHostnameRule.AutoSize=$true
$lblHostnameRule.Anchor='Left'
$lblHostnameRule.Margin=New-Object Windows.Forms.Padding(8,7,3,3)
$pSettings.Controls.Add($lblHostnameRule,5,2)
$pSettings.SetColumnSpan($lblHostnameRule,3)

# Forest-agnostic default computer-name validation policy.
$script:ComputerNameRegex='^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$'

# -------------------------------------------------------------------------
# Row 4 - Re-Ingress policy
# -------------------------------------------------------------------------
$lblReuseDays=New-Object Windows.Forms.Label
$lblReuseDays.Text='Reuse After Days:'
$lblReuseDays.AutoSize=$true
$lblReuseDays.Anchor='Left'
$lblReuseDays.Margin=New-Object Windows.Forms.Padding(3,7,6,3)
$pSettings.Controls.Add($lblReuseDays,0,3)

$numReuseDays=New-Object Windows.Forms.NumericUpDown
$numReuseDays.Minimum=30
$numReuseDays.Maximum=3650
$numReuseDays.Value=90
$numReuseDays.Width=70
$numReuseDays.Anchor='Left'
$pSettings.Controls.Add($numReuseDays,1,3)

$chkMoveReuse=New-Object Windows.Forms.CheckBox
$chkMoveReuse.Text='Move stale reuse to Target OU'
$chkMoveReuse.Checked=$false
$chkMoveReuse.AutoSize=$true
$chkMoveReuse.Margin=New-Object Windows.Forms.Padding(8,7,3,3)
$pSettings.Controls.Add($chkMoveReuse,2,3)
$pSettings.SetColumnSpan($chkMoveReuse,3)

$lblReuseRule=New-Object Windows.Forms.Label
$lblReuseRule.Text='ACTIVE names blocked | STALE names require Controlled Re-Ingress'
$lblReuseRule.AutoSize=$true
$lblReuseRule.Anchor='Left'
$lblReuseRule.Margin=New-Object Windows.Forms.Padding(8,7,3,3)
$pSettings.Controls.Add($lblReuseRule,5,3)
$pSettings.SetColumnSpan($lblReuseRule,3)

$main.Controls.Add($pSettings,0,1)

# Row 3: computer input
$pInput=New-Object Windows.Forms.TableLayoutPanel
$pInput.Dock='Fill';$pInput.AutoSize=$true;$pInput.ColumnCount=6;$pInput.RowCount=1
$pInput.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pInput.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
$pInput.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pInput.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pInput.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pInput.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pInput.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))

$lblComputers=New-Object Windows.Forms.Label
$lblComputers.Text='Computer Names (comma/line separated):';$lblComputers.AutoSize=$true;$lblComputers.Anchor='Left';$lblComputers.Margin=New-Object Windows.Forms.Padding(3,7,4,3)
$pInput.Controls.Add($lblComputers,0,0)

$txtComputers=New-Object Windows.Forms.TextBox
$txtComputers.Dock='Fill'
$pInput.Controls.Add($txtComputers,1,0)

$lblHostnameCount=New-Object Windows.Forms.Label
$lblHostnameCount.Text='Exactly 15 characters required'
$lblHostnameCount.AutoSize=$true
$lblHostnameCount.Anchor='Left'
$lblHostnameCount.Margin=New-Object Windows.Forms.Padding(5,7,5,3)
$pInput.Controls.Add($lblHostnameCount,2,0)

$btnFile=New-Object Windows.Forms.Button
$btnFile.Text='Load TXT';$btnFile.Width=90
$pInput.Controls.Add($btnFile,3,0)

$btnPreview=New-Object Windows.Forms.Button
$btnPreview.Text='Build Preview';$btnPreview.Width=105
$pInput.Controls.Add($btnPreview,4,0)

$btnClearInput=New-Object Windows.Forms.Button
$btnClearInput.Text='Clear Input';$btnClearInput.Width=90
$pInput.Controls.Add($btnClearInput,5,0)

$main.Controls.Add($pInput,0,2)

# Row 4: result filter
$pFilter=New-Object Windows.Forms.TableLayoutPanel
$pFilter.Dock='Fill'
$pFilter.AutoSize=$true
$pFilter.ColumnCount=3
$pFilter.RowCount=1

$pFilter.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
$pFilter.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
$pFilter.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))

$lblFilter=New-Object Windows.Forms.Label
$lblFilter.Text='Filter all columns:'
$lblFilter.AutoSize=$true
$lblFilter.Anchor='Left'
$lblFilter.Margin=New-Object Windows.Forms.Padding(3,7,6,3)
$pFilter.Controls.Add($lblFilter,0,0)

$txtFilter=New-Object Windows.Forms.TextBox
$txtFilter.Dock='Fill'
$pFilter.Controls.Add($txtFilter,1,0)

$btnClearFilter=New-Object Windows.Forms.Button
$btnClearFilter.Text='Clear Filter'
$btnClearFilter.Width=90
$pFilter.Controls.Add($btnClearFilter,2,0)

$main.Controls.Add($pFilter,0,3)

# Row 5: action buttons - flow layout prevents right-edge clipping
$pActions=New-Object Windows.Forms.FlowLayoutPanel
$pActions.Dock='Fill'
$pActions.AutoSize=$true
$pActions.WrapContents=$true
$pActions.FlowDirection='LeftToRight'

$btnSelectActionable=New-Object Windows.Forms.Button
$btnSelectActionable.Text='Select Actionable'
$btnSelectActionable.Width=115
$pActions.Controls.Add($btnSelectActionable)

$btnCommit=New-Object Windows.Forms.Button
$btnCommit.Text='Add / Re-Ingress Selected'
$btnCommit.Width=155
$pActions.Controls.Add($btnCommit)

$btnExport=New-Object Windows.Forms.Button
$btnExport.Text='Export Report'
$btnExport.Width=95
$pActions.Controls.Add($btnExport)

$btnKnownGood=New-Object Windows.Forms.Button
$btnKnownGood.Text='Audit Existing'
$btnKnownGood.Width=105
$pActions.Controls.Add($btnKnownGood)

$btnClearList=New-Object Windows.Forms.Button
$btnClearList.Text='Clear Provisioning List'
$btnClearList.Width=145
$pActions.Controls.Add($btnClearList)

$main.Controls.Add($pActions,0,4)

# Row 5: result grid
$listView=New-Object Windows.Forms.ListView
$listView.Dock='Fill';$listView.View='Details';$listView.CheckBoxes=$true
$listView.FullRowSelect=$true;$listView.GridLines=$true;$listView.HideSelection=$false
$script:listView=$listView

$columns = @(
    @('ComputerName',135),@('Domain',175),@('DC FQDN',205),@('DC IP',95),
    @('Target OU',330),@('Existing',75),@('Existing DN',330),@('Owner',190),
    @('Owner Assessment',170),@('PwdNotRequired',105),@('UAC',70),@('Core ACL',95),
    @('Reset Password',105),@('Validated DNS',105),@('Validated SPN',105),
    @('Acct Restrictions',110),@('Activity',90),@('Last Logon',135),
    @('Password Last Set',135),@('Inactive Days',90),@('Planned Action',145),
    @('Status',175),@('Detail',360)
)

foreach($c in $columns){ [void]$listView.Columns.Add($c[0],[int]$c[1]) }
$main.Controls.Add($listView,0,5)

$summaryLabel=New-Object Windows.Forms.Label
$summaryLabel.AutoSize=$true
$summaryLabel.Text='No candidate preview has been built.'
$main.Controls.Add($summaryLabel,0,6)

# Row 7: runtime log
$txtRuntimeLog=New-Object Windows.Forms.TextBox
$txtRuntimeLog.Dock='Fill';$txtRuntimeLog.Multiline=$true;$txtRuntimeLog.ReadOnly=$true
$txtRuntimeLog.ScrollBars='Vertical';$txtRuntimeLog.Font=New-Object Drawing.Font('Consolas',8.5)
$script:txtRuntimeLog=$txtRuntimeLog
$main.Controls.Add($txtRuntimeLog,0,7)

# Row 8: status
$statusStrip=New-Object Windows.Forms.StatusStrip
$statusMain=New-Object Windows.Forms.ToolStripStatusLabel
$statusMain.Spring=$true;$statusMain.Text='Ready';$script:statusMain=$statusMain
[void]$statusStrip.Items.Add($statusMain)

$statusDC=New-Object Windows.Forms.ToolStripStatusLabel
$statusDC.Text='DC: -';$script:statusDC=$statusDC
[void]$statusStrip.Items.Add($statusDC)

$statusMode=New-Object Windows.Forms.ToolStripStatusLabel
$statusMode.Text='Mode: DRY RUN'
[void]$statusStrip.Items.Add($statusMode)

$statusFile=New-Object Windows.Forms.ToolStripStatusLabel
$statusFile.Text="Log: $([IO.Path]::GetFileName($script:LogFile))"
[void]$statusStrip.Items.Add($statusFile)

$main.Controls.Add($statusStrip,0,8)

# =====================================================================================
# GUI helpers/events
# =====================================================================================
function Refresh-OUCombo {
    $domainName=[string]$cmbDomain.SelectedItem
    if([string]::IsNullOrWhiteSpace($domainName)){ return }

    $all=@(Get-ComputerOUsForDomain -DomainName $domainName)
    $filter=$txtOUSearch.Text.Trim()

    $currentDN=''
    if($cmbOU.SelectedItem){ $currentDN=[string]$cmbOU.SelectedItem.DistinguishedName }

    $filtered=@(
        $all |
        Where-Object {
            [string]::IsNullOrWhiteSpace($filter) -or
            ([string]$_.Name).IndexOf($filter,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            ([string]$_.DistinguishedName).IndexOf($filter,[StringComparison]::OrdinalIgnoreCase) -ge 0
        }
    )

    $cmbOU.BeginUpdate()
    try{
        $cmbOU.Items.Clear()
        foreach($ou in $filtered){ [void]$cmbOU.Items.Add($ou) }

        $selected=-1
        if($currentDN){
            for($i=0;$i-lt$cmbOU.Items.Count;$i++){
                if([string]$cmbOU.Items[$i].DistinguishedName -eq $currentDN){
                    $selected=$i
                    break
                }
            }
        }

        if($selected -ge 0){
            $cmbOU.SelectedIndex=$selected
        }elseif($cmbOU.Items.Count -gt 0){
            $cmbOU.SelectedIndex=0
        }
    }finally{
        $cmbOU.EndUpdate()
    }

    $domain=Get-WritableDomainControllerRecord -DomainName $domainName
    $lblDC.Text="DC: $($domain.DCFqdn) [$($domain.DCIPv4)]"
    if($null -ne (Get-Variable -Name statusDC -Scope Script -ErrorAction SilentlyContinue)){ $script:statusDC.Text = "DC: $($domain.DCFqdn) [$($domain.DCIPv4)]" }
    Set-AppStatus "Displayed $($filtered.Count) of $($all.Count) OU(s) for $domainName."
}

function Resolve-GuiJoinPrincipal {
    $value = $txtIngress.Text.Trim()

    if([string]::IsNullOrWhiteSpace($value)){
        $script:Ingress = $null
        $lblIngressStatus.Text = 'Principal: not configured'
        $lblPrincipalState.Text = 'NOT CONFIGURED'
        Set-AppStatus 'Enter a Domain Join Account before Preview, Audit Existing, or Commit.'
        return $false
    }

    try{
        $script:Ingress = Resolve-JoinPrincipal -SearchValue $value

        $displayIdentity = if(-not [string]::IsNullOrWhiteSpace($script:Ingress.UserPrincipalName)){
            $script:Ingress.UserPrincipalName
        }elseif(-not [string]::IsNullOrWhiteSpace($script:Ingress.SamAccountName)){
            $script:Ingress.SamAccountName
        }else{
            $script:Ingress.DistinguishedName
        }

        $lblIngressStatus.Text = "Principal: $($script:Ingress.ObjectClass) | $displayIdentity"
        $lblPrincipalState.Text = 'VALID'
        Set-AppStatus "Domain Join Account validated: $displayIdentity"
        Write-AppLog "Resolved Domain Join Principal '$value' to '$($script:Ingress.DistinguishedName)' SID '$($script:Ingress.SID)'." SUCCESS
        return $true
    }catch{
        $script:Ingress = $null
        $lblIngressStatus.Text = 'Principal: validation failed'
        $lblPrincipalState.Text = 'INVALID'
        Set-AppStatus "Domain Join Account validation failed: $($_.Exception.Message)"
        Write-AppLog "Domain Join Account validation failed for '$value': $($_.Exception.Message)" WARN
        return $false
    }
}

$script:PrincipalValidationTimer = New-Object Windows.Forms.Timer
$script:PrincipalValidationTimer.Interval = 800
$script:PrincipalValidationTimer.Add_Tick({
    $script:PrincipalValidationTimer.Stop()
    if([string]::IsNullOrWhiteSpace($txtIngress.Text)){
        $script:Ingress = $null
        $lblIngressStatus.Text = 'Principal: not configured'
        $lblPrincipalState.Text = 'NOT CONFIGURED'
        return
    }
    [void](Resolve-GuiJoinPrincipal)
})

function Update-HostnameLengthFeedback {
    $requiredLength = [int]$numMaxLength.Value

    $lblHostnameRule.Text = "Exactly $requiredLength chars | A-Z, 0-9, hyphen (-) only"

    $raw = $txtComputers.Text.Trim()

    if([string]::IsNullOrWhiteSpace($raw)){
        $lblHostnameCount.Text = "Exactly $requiredLength characters required"
        return
    }

    $names = @(ConvertTo-ComputerNameList -Text $raw)

    if($names.Count -eq 0){
        $lblHostnameCount.Text = "Exactly $requiredLength characters required"
        return
    }

    $results = @(
        foreach($name in $names){
            $policy = Test-ComputerNamePolicy `
                -ComputerName $name `
                -MaximumLength $requiredLength `
                -RequireUppercase ([bool]$chkUppercase.Checked) `
                -Pattern $script:ComputerNameRegex

            [pscustomobject]@{
                Name   = $name
                Length = $name.Length
                Valid  = [bool]$policy.Valid
                Reason = [string]$policy.Reason
            }
        }
    )

    if($results.Count -eq 1){
        $result = $results[0]

        if($result.Valid){
            $lblHostnameCount.Text = "$($result.Length)/$requiredLength - VALID"
        }
        elseif($result.Length -ne $requiredLength){
            $lblHostnameCount.Text = "$($result.Length)/$requiredLength - INVALID LENGTH"
        }
        elseif($result.Reason -like 'Invalid hostname character*'){
            $lblHostnameCount.Text = "$($result.Length)/$requiredLength - INVALID CHARACTERS"
        }
        elseif($result.Reason -like '*uppercase*'){
            $lblHostnameCount.Text = "$($result.Length)/$requiredLength - INVALID CASE"
        }
        else{
            $lblHostnameCount.Text = "$($result.Length)/$requiredLength - INVALID"
        }

        return
    }

    $invalid = @($results | Where-Object { -not $_.Valid })

    if($invalid.Count -eq 0){
        $lblHostnameCount.Text = "$($results.Count) names - ALL VALID"
    }else{
        $lblHostnameCount.Text = "$($invalid.Count) of $($results.Count) INVALID"
    }
}

$txtComputers.Add_TextChanged({
    Update-HostnameLengthFeedback
})

$numMaxLength.Add_ValueChanged({
    Update-HostnameLengthFeedback
})

$chkUppercase.Add_CheckedChanged({
    Update-HostnameLengthFeedback
})

$txtIngress.Add_TextChanged({
    $script:Ingress = $null

    if($script:PrincipalValidationTimer.Enabled){
        $script:PrincipalValidationTimer.Stop()
    }

    if([string]::IsNullOrWhiteSpace($txtIngress.Text)){
        $lblIngressStatus.Text = 'Principal: not configured'
        $lblPrincipalState.Text = 'NOT CONFIGURED'
        return
    }

    $lblIngressStatus.Text = 'Principal: validation pending'
    $lblPrincipalState.Text = 'VALIDATING...'
    $script:PrincipalValidationTimer.Start()
})

$btnValidatePrincipal.Add_Click({
    if($script:PrincipalValidationTimer.Enabled){
        $script:PrincipalValidationTimer.Stop()
    }
    [void](Resolve-GuiJoinPrincipal)
})

$cmbDomain.Add_SelectedIndexChanged({
    try{
        Refresh-OUCombo
    }catch{
        Show-AppMessage "Domain/OU refresh failed: $($_.Exception.Message)" Error
    }
})

$txtOUSearch.Add_TextChanged({
    try{ Refresh-OUCombo }catch{}
})

$btnReload.Add_Click({
    try{
        $domainName=[string]$cmbDomain.SelectedItem
        if($script:OUCache.ContainsKey($domainName)){ $script:OUCache.Remove($domainName) }
        Refresh-OUCombo
        Write-AppLog "Reloaded Computer OUs for '$domainName'." INFO
    }catch{
        Show-AppMessage "OU reload failed: $($_.Exception.Message)" Error
    }
})

$chkDryRun.Add_CheckedChanged({
    $statusMode.Text=if($chkDryRun.Checked){'Mode: DRY RUN'}else{'Mode: COMMIT'}
})

$btnFile.Add_Click({
    try{
        $dlg=New-Object Windows.Forms.OpenFileDialog
        $dlg.Filter='Text Files (*.txt)|*.txt|All Files (*.*)|*.*'
        if($dlg.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){
            $names=@(
                Get-Content -LiteralPath $dlg.FileName -ErrorAction Stop |
                ForEach-Object { $_.Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )

            $txtComputers.Text=($names -join ', ')
            Update-HostnameLengthFeedback
            Set-AppStatus "Loaded $($names.Count) line(s) from '$($dlg.FileName)'."
        }
    }catch{
        Show-AppMessage "TXT load failed: $($_.Exception.Message)" Error
    }
})

$btnClearInput.Add_Click({
    $txtComputers.Clear()
    Set-AppStatus 'Computer Names input cleared. Accumulated provisioning list was preserved.'
})

$txtFilter.Add_TextChanged({
    Apply-CandidateFilter -Filter $txtFilter.Text
})

$btnClearFilter.Add_Click({ $txtFilter.Clear() })

$listView.Add_ColumnClick({
    param($sender,$e)
    Sort-Candidates -Column $e.Column
})

$listView.Add_ItemCheck({
    param($sender,$e)
    try{
        $item=$listView.Items[$e.Index]
        if($item.Tag -and $item.Tag.PlannedAction -eq 'BLOCKED' -and
           $e.NewValue -eq [Windows.Forms.CheckState]::Checked){
            $e.NewValue=[Windows.Forms.CheckState]::Unchecked
            Set-AppStatus "Selection blocked for '$($item.Tag.ComputerName)': $($item.Tag.Status)."
        }
    }catch{}
})

$btnSelectActionable.Add_Click({
    $count=0
    foreach($item in $listView.Items){
        if($item.Tag -and $item.Tag.PlannedAction -ne 'BLOCKED'){
            $item.Checked=$true
            $count++
        }else{
            $item.Checked=$false
        }
    }
    Set-AppStatus "Selected $count actionable displayed candidate(s)."
})

$btnClearList.Add_Click({
    if($script:Candidates.Count -eq 0){
        Set-AppStatus 'Provisioning list is already empty.'
        return
    }

    $answer=[Windows.Forms.MessageBox]::Show(
        "Clear all $($script:Candidates.Count) accumulated provisioning candidate(s)?",
        'Clear Provisioning List',
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Question,
        [Windows.Forms.MessageBoxDefaultButton]::Button2
    )

    if($answer -eq [Windows.Forms.DialogResult]::Yes){
        $script:Candidates=@()
        $script:Displayed=@()
        Set-CandidateList -Rows @()
        $summaryLabel.Text='Provisioning list cleared.'
        Write-AppLog 'Accumulated provisioning list cleared by operator.' INFO
        Set-AppStatus 'Provisioning list cleared.'
    }
})

$btnPreview.Add_Click({
    try{
        Update-HostnameLengthFeedback

        $requiredLength = [int]$numMaxLength.Value
        $previewNames = @(ConvertTo-ComputerNameList -Text $txtComputers.Text)

        if($previewNames.Count -eq 0){
            [Windows.Forms.MessageBox]::Show(
                'Enter at least one computer name before building the preview.',
                'Computer Name Required',
                [Windows.Forms.MessageBoxButtons]::OK,
                [Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            $txtComputers.Focus()
            return
        }

        $invalidPolicyNames = @(
            foreach($previewName in $previewNames){
                $policy = Test-ComputerNamePolicy `
                    -ComputerName $previewName `
                    -MaximumLength $requiredLength `
                    -RequireUppercase ([bool]$chkUppercase.Checked) `
                    -Pattern $script:ComputerNameRegex

                if(-not $policy.Valid){
                    [pscustomobject]@{
                        Name   = $previewName
                        Length = $previewName.Length
                        Reason = $policy.Reason
                    }
                }
            }
        )

        if($invalidPolicyNames.Count -gt 0){
            $details = @(
                $invalidPolicyNames |
                ForEach-Object {
                    "'$($_.Name)' [$($_.Length) chars] - $($_.Reason)"
                }
            ) -join [Environment]::NewLine

            $message = @"
Hostname policy validation failed.

Required length: exactly $requiredLength characters.
Allowed characters: A-Z, 0-9, and hyphen (-) only.
Hyphen cannot be the first or last character.
Uppercase required: $($chkUppercase.Checked)

Invalid computer name(s):
$details

Build Preview has been blocked.
Correct the hostname(s) before continuing.
"@

            [Windows.Forms.MessageBox]::Show(
                $message,
                'Invalid Hostname Policy',
                [Windows.Forms.MessageBoxButtons]::OK,
                [Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null

            Write-AppLog (
                "Build Preview blocked: {0} computer name(s) violate the configured hostname policy." -f
                $invalidPolicyNames.Count
            ) WARN

            Set-AppStatus 'Build Preview blocked - invalid hostname policy.'
            $txtComputers.Focus()
            return
        }

        if($null -eq $cmbOU.SelectedItem){ throw 'Select a target OU.' }

        if(-not (Resolve-GuiJoinPrincipal)){ return }

        $names=@(ConvertTo-ComputerNameList -Text $txtComputers.Text)
        if($names.Count -eq 0){ throw 'Enter at least one computer name or load a TXT file.' }

        $domainName=[string]$cmbDomain.SelectedItem
        $domain=Get-WritableDomainControllerRecord -DomainName $domainName
        $ou=$cmbOU.SelectedItem

        Set-AppStatus "Building candidate preview for $($names.Count) name(s)..."

        $rows=New-Object Collections.ArrayList
        $i=0

        foreach($name in $names){
            $i++
            Set-AppStatus "Previewing $i of $($names.Count): $name"
            [void]$rows.Add((New-CandidateRecord -ComputerName $name -DomainRecord $domain -OU $ou `
                -MaximumLength ([int]$numMaxLength.Value) `
                -RequireUppercase ([bool]$chkUppercase.Checked) `
                -NamePattern $script:ComputerNameRegex `
                -ReuseAfterDays ([int]$numReuseDays.Value) `
                -AllowReIngress ([bool]$chkReIngress.Checked)))
            [Windows.Forms.Application]::DoEvents()
        }

        # Build Preview is cumulative. Preserve previously previewed rows from
        # other domains/OUs and append only new domain+computer combinations.
        $existingKeys=@{}
        foreach($existingCandidate in @($script:Candidates)){
            $key=('{0}|{1}' -f
                ([string]$existingCandidate.Domain).ToUpperInvariant(),
                ([string]$existingCandidate.ComputerName).ToUpperInvariant()
            )
            $existingKeys[$key]=$true
        }

        $added=0
        $duplicates=0

        foreach($row in @($rows)){
            $key=('{0}|{1}' -f
                ([string]$row.Domain).ToUpperInvariant(),
                ([string]$row.ComputerName).ToUpperInvariant()
            )

            if($existingKeys.ContainsKey($key)){
                $duplicates++
                Write-AppLog "Skipped duplicate preview candidate '$($row.ComputerName)' in domain '$($row.Domain)'." WARN
                continue
            }

            $script:Candidates += $row
            $existingKeys[$key]=$true
            $added++
        }

        $script:Displayed=@($script:Candidates)

        # Preserve the user's active filter when accumulating new rows.
        Apply-CandidateFilter -Filter $txtFilter.Text

        Write-AppLog ("Candidate preview accumulated. Domain='{0}'; OU='{1}'; Added={2}; DuplicatesSkipped={3}; TotalCandidates={4}." -f
            $domainName,$ou.DistinguishedName,$added,$duplicates,$script:Candidates.Count) SUCCESS

        $txtComputers.Clear()

        Set-AppStatus ("Preview added {0} candidate(s); skipped {1} duplicate(s). Total provisioning list: {2}." -f
            $added,$duplicates,$script:Candidates.Count)
    }catch{
        Show-AppMessage "Preview failed: $($_.Exception.Message)" Error
    }
})

$btnKnownGood.Add_Click({
    try{
        if(-not (Resolve-GuiJoinPrincipal)){ return }

        $name = [Microsoft.VisualBasic.Interaction]::InputBox(
            'Enter the existing computer name to audit across the discovered forest:',
            'Audit Existing Computer',
            ''
        ).Trim()

        if([string]::IsNullOrWhiteSpace($name)){ return }

        $matches=@(Get-ComputerAcrossForest -ComputerName $name)

        if($matches.Count -eq 0){
            throw "Computer '$name' was not found in the discovered forest."
        }
        if($matches.Count -gt 1){
            throw "Computer '$name' exists in more than one forest domain; audit is intentionally blocked."
        }

        $m=$matches[0]
        $acl=Test-JoinAcl -Server $m.DCFqdn `
            -DistinguishedName $m.Computer.DistinguishedName `
            -IngressSID $script:Ingress.SID

        $message=@"
Existing computer audit: $name

Domain: $($m.DomainName)
DC: $($m.DCFqdn)
DC IP: $($m.DCIPv4)
Owner: $($acl.Owner)
ACL Protected: $($acl.AclProtected)
Join-principal ACEs: $($acl.TotalIngressAces)
Explicit ACEs: $($acl.ExplicitIngressAces)
Inherited ACEs: $($acl.InheritedIngressAces)

Core authorization:
$($acl.CoreSummary)

Core compliant: $($acl.CoreCompliant)
"@

        [void][Windows.Forms.MessageBox]::Show(
            $message,
            'Existing Computer Authorization Audit',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Information
        )

        Write-AppLog "Existing-computer audit '$name': Owner='$($acl.Owner)'; $($acl.CoreSummary); InheritedAces=$($acl.InheritedIngressAces); ExplicitAces=$($acl.ExplicitIngressAces)." INFO
    }catch{
        Show-AppMessage "Existing-computer audit failed: $($_.Exception.Message)" Error
    }
})

$btnCommit.Add_Click({
    try{
        $selected=@(Get-CheckedCandidates)
        if($selected.Count -eq 0){
            Show-AppMessage 'Select at least one actionable candidate.' Information
            return
        }

        if($null -eq $script:Ingress){
            if(-not (Resolve-GuiJoinPrincipal)){ return }
        }

        if($chkDryRun.Checked){
            foreach($row in $selected){
                Write-AppLog "DRY RUN: '$($row.ComputerName)' action='$($row.PlannedAction)' domain='$($row.Domain)' DC='$($row.DC)' DCIP='$($row.DCIPv4)' OU='$($row.TargetOU)'." INFO
            }

            Show-AppMessage "Dry Run completed for $($selected.Count) candidate(s). No Active Directory state was changed." Information
            return
        }

        $legacyWarning = if($chkLegacyPwd.Checked){
            "`r`nPasswordNotRequired is ENABLED for newly created accounts."
        }else{
            "`r`nPasswordNotRequired is DISABLED for newly created accounts."
        }

        $confirm=@"
COMMIT Active Directory computer pre-staging?

Selected candidates: $($selected.Count)
Selected domains: $(@($selected.Domain | Sort-Object -Unique).Count)
Domain Join Principal: $($script:Ingress.UserPrincipalName)
Principal SID: $($script:Ingress.SID)
Ensure missing domain-join ACEs: $($chkRemediate.Checked)
Controlled Re-Ingress enabled: $($chkReIngress.Checked)
Re-Ingress inactivity threshold: $([int]$numReuseDays.Value) day(s)
Move stale re-ingress accounts to Target OU: $($chkMoveReuse.Checked)
$legacyWarning

ACTIVE existing computer names are always blocked.
STALE existing computer names require explicit Controlled Re-Ingress.
Activity is revalidated immediately before Commit.
Existing computer objects are preserved and never automatically deleted.
"@

        $answer=[Windows.Forms.MessageBox]::Show(
            $confirm,
            'Confirm Computer Pre-Staging',
            [Windows.Forms.MessageBoxButtons]::YesNo,
            [Windows.Forms.MessageBoxIcon]::Warning,
            [Windows.Forms.MessageBoxDefaultButton]::Button2
        )

        if($answer -ne [Windows.Forms.DialogResult]::Yes){
            Write-AppLog 'Commit cancelled by operator.' WARN
            return
        }

        $results=New-Object Collections.ArrayList
        $i=0

        foreach($row in $selected){
            $i++
            Set-AppStatus "Committing $i of $($selected.Count): $($row.ComputerName)"

            $result=Invoke-CandidateCommit `
                -Candidate $row `
                -Description $txtDescription.Text `
                -LegacyPasswordNotRequired:$chkLegacyPwd.Checked `
                -RemediateMissingAcl:$chkRemediate.Checked `
                -ReuseAfterDays ([int]$numReuseDays.Value) `
                -MoveReusedToTargetOU:$chkMoveReuse.Checked `
                -AllowReIngress:$chkReIngress.Checked `
                -Confirm:$false

            [void]$results.Add($result)
            [Windows.Forms.Application]::DoEvents()
        }

        @($results) |
            Export-Csv -LiteralPath $script:ReportFile -NoTypeInformation -Encoding UTF8

        $success=@($results | Where-Object { $_.Result -eq 'SUCCESS' }).Count
        $warning=@($results | Where-Object { $_.Result -eq 'WARNING' }).Count
        $failed=@($results | Where-Object { $_.Result -eq 'FAILED' }).Count

        $message="Commit completed.`r`n`r`nSuccess: $success`r`nWarning: $warning`r`nFailed: $failed`r`n`r`nReport: $($script:ReportFile)"
        if($failed -gt 0){
            Show-AppMessage $message Warning
        }else{
            Show-AppMessage $message Information
        }

        # Rebuild preview to show final state.
        $btnPreview.PerformClick()
    }catch{
        Show-AppMessage "Commit failed: $($_.Exception.Message)" Error
    }
})

$btnExport.Add_Click({
    try{
        if($script:Candidates.Count -eq 0){
            throw 'There is no preview/report data to export.'
        }

        $dlg=New-Object Windows.Forms.SaveFileDialog
        $dlg.Filter='CSV (*.csv)|*.csv'
        $dlg.FileName="$($script:ScriptName)-audit-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"

        if($dlg.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){
            $script:Candidates |
                Export-Csv -LiteralPath $dlg.FileName -NoTypeInformation -Encoding UTF8

            Write-AppLog "Exported candidate audit to '$($dlg.FileName)'." SUCCESS
            Set-AppStatus "Exported audit report to '$($dlg.FileName)'."
        }
    }catch{
        Show-AppMessage "Export failed: $($_.Exception.Message)" Error
    }
})

# =====================================================================================
# Main
# =====================================================================================
try{
    Write-AppLog "Starting $($script:ScriptName)." INFO
    Write-AppLog ("Host PowerShell: {0}; OS: {1}" -f $PSVersionTable.PSVersion,[Environment]::OSVersion.VersionString) INFO

    Initialize-ForestContext

    # Forest-agnostic convenience default. This is only a suggested value;
    # the principal is not trusted/resolved until Preview, Audit Existing, or Commit.
    $defaultJoinDomain = [string]$script:Forest.RootDomain
    if(-not [string]::IsNullOrWhiteSpace($defaultJoinDomain)){
        $txtIngress.Text = "domainingress@$defaultJoinDomain"
        $script:Ingress = $null
        $lblIngressStatus.Text = 'Principal: validation pending'
        $lblPrincipalState.Text = 'VALIDATING...'
    }

    foreach($domainName in @($script:Forest.Domains | Sort-Object)){
        [void]$cmbDomain.Items.Add([string]$domainName)
    }

    if($cmbDomain.Items.Count -eq 0){
        throw 'No forest domains were discovered.'
    }

    # Prefer the current domain if available; otherwise first forest domain.
    $currentDomain=''
    try{
        $currentDomain=[string](Get-ADDomain).DNSRoot
    }catch{}

    $selectedIndex=0
    if($currentDomain){
        for($i=0;$i-lt$cmbDomain.Items.Count;$i++){
            if([string]$cmbDomain.Items[$i] -eq $currentDomain){
                $selectedIndex=$i
                break
            }
        }
    }

    $cmbDomain.SelectedIndex=$selectedIndex

    $script:Ingress = $null
    $lblIngressStatus.Text = 'Principal: not configured'
    Set-AppStatus 'Forest discovery completed. The Domain Join Account was prefilled from the forest root domain; validate or replace it, select an OU, and build a preview.'

    Write-AppLog ("Discovered forest domains: {0}" -f (@($script:Forest.Domains) -join ', ')) SUCCESS
    Write-AppLog "Forest-agnostic behavior: discover environment dynamically; validate inherited ACLs first; explicit core ACE remediation is opt-in." INFO

    [void]$form.ShowDialog()
}
catch{
    Write-AppLog "Fatal startup error: $($_.Exception.Message)" ERROR

    [void][Windows.Forms.MessageBox]::Show(
        "Fatal startup error:`r`n$($_.Exception.Message)",
        $script:AppName,
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Error
    )
}
finally{
    Write-AppLog "Closing $($script:ScriptName)." INFO
}

# End of script
