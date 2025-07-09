<div>
  <h1>🛠️ Active Directory Management Tools</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>Active Directory Management</strong> folder features a powerful suite of 
    <strong>PowerShell scripts</strong> for automating and simplifying tasks related to 
    <strong>Active Directory (AD)</strong>. These tools streamline user and computer account management, 
    enhance OU administration, enforce policy compliance, and maintain directory integrity across enterprise domains.
  </p>

  <h3>Key Features:</h3>
  <ul>
    <li><strong>Graphical Interfaces:</strong> Several tools include GUIs to simplify user interaction and configuration.</li>
    <li><strong>Comprehensive Logging:</strong> Scripts generate structured <code>.log</code> files for auditing and diagnostics.</li>
    <li><strong>Exportable Reports:</strong> Most tools export data in <code>.csv</code> format for reporting and compliance.</li>
    <li><strong>Efficient AD Automation:</strong> Reduces manual overhead in managing accounts, OUs, GPOs, and permissions.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell</strong>
      <ul>
        <li>Requires PowerShell 5.1 or later.</li>
        <li>Verify version with:
          <pre><code>$PSVersionTable.PSVersion</code></pre>
        </li>
        <li>Ensure <code>ActiveDirectory</code> module is imported where needed:
          <pre><code>Import-Module ActiveDirectory</code></pre>
        </li>
      </ul>
    </li>
    <li>
      <strong>🔑 Administrator Privileges</strong>
      <p>Most scripts require elevation to manage AD objects and configurations.</p>
    </li>
    <li>
      <strong>🖥️ RSAT Components</strong>
      <p>Ensure RSAT tools for Active Directory are installed on the workstation or admin server.</p>
    </li>
    <li>
      <strong>🔧 Execution Policy</strong>
      <p>Temporarily allow local script execution:</p>
      <pre><code>Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process</code></pre>
    </li>
  </ol>

  <hr />

<h2>📄 Script Descriptions (Alphabetical Order)</h2>
<table border="1" style="border-collapse: collapse; width: 100%;">
  <thead>
    <tr>
      <th style="padding: 8px;">Script Name</th>
      <th style="padding: 8px;">Description</th>
    </tr>
  </thead>
  <tbody>
    <tr><td><strong>Add-ADComputers-GrantPermissions.ps1</strong></td><td>Adds AD computers to OUs and grants domain join permissions.</td></tr>
    <tr><td><strong>Add-ADInetOrgPerson.ps1</strong></td><td>Creates <code>InetOrgPerson</code> objects for detailed directory attribute use.</td></tr>
    <tr><td><strong>Add-ADUserAccount.ps1</strong></td><td>Creates AD users in designated OUs via a GUI form.</td></tr>
    <tr><td><strong>Adjust-ExpirationDate-ADUserAccount.ps1</strong></td><td>Modifies user account expiration dates for lifecycle control.</td></tr>
    <tr><td><strong>Check-Shorter-ADComputerNames.ps1</strong></td><td>Detects computer accounts with non-compliant short names.</td></tr>
    <tr><td><strong>Cleanup-Inactive-ADComputerAccounts.ps1</strong></td><td>Removes stale AD computer accounts to reduce clutter and risk.</td></tr>
    <tr><td><strong>Cleanup-MetaData-ADForest-Tool.ps1</strong></td><td>Synchronizes metadata and removes orphaned objects in the forest.</td></tr>
    <tr><td><strong>Create-OUsDefaultADStructure.ps1</strong></td><td>Implements a standardized OU structure in a new or existing domain.</td></tr>
    <tr><td><strong>Enforce-Expiration-ADUserPasswords.ps1</strong></td><td>Enables password expiration enforcement on user accounts.</td></tr>
    <tr><td><strong>Export-n-Import-GPOsTool.ps1</strong></td><td>GUI tool to export/import GPOs between domains or backups.</td></tr>
    <tr><td><strong>Fix-ADForest-DNSDelegation.ps1</strong></td><td>Resolves DNS delegation inconsistencies in the AD forest.</td></tr>
    <tr><td><strong>Inventory-ADComputers-and-OUs.ps1</strong></td><td>Exports AD computers and OU paths from one or all domains via GUI.</td></tr>
    <tr><td><strong>Inventory-ADDomainComputers.ps1</strong></td><td>Exports a list of all domain-joined computers.</td></tr>
    <tr><td><strong>Inventory-ADGroups-their-Members.ps1</strong></td><td>Lists all AD groups and their associated members.</td></tr>
    <tr><td><strong>Inventory-ADMemberServers.ps1</strong></td><td>Generates reports on all domain member servers.</td></tr>
    <tr><td><strong>Inventory-ADUserAttributes.ps1</strong></td><td>Extracts all attribute data for AD users into CSV reports.</td></tr>
    <tr><td><strong>Inventory-ADUserLastLogon.ps1</strong></td><td>Tracks last logon timestamps for user accounts.</td></tr>
    <tr><td><strong>Inventory-ADUserWithNonExpiringPasswords.ps1</strong></td><td>Lists accounts with passwords set to never expire.</td></tr>
    <tr><td><strong>Inventory-InactiveADComputerAccounts.ps1</strong></td><td>Identifies unused computer accounts for cleanup.</td></tr>
    <tr><td><strong>Manage-Disabled-Expired-ADUserAccounts.ps1</strong></td><td>Disables expired AD accounts based on policy rules.</td></tr>
    <tr><td><strong>Manage-FSMOs-Roles.ps1</strong></td><td>Manages and transfers FSMO roles within the forest.</td></tr>
    <tr><td><strong>Move-ADComputer-betweenOUs.ps1</strong></td><td>Moves computers between OUs automatically based on logic.</td></tr>
    <tr><td><strong>Move-ADUser-betweenOUs.ps1</strong></td><td>Transfers user accounts between OUs as needed.</td></tr>
    <tr><td><strong>Reset-ADUserPasswordsToDefault.ps1</strong></td><td>Resets passwords to a default secure string for selected users.</td></tr>
    <tr><td><strong>Retrieve-ADComputer-SharedFolders.ps1</strong></td><td>Scans AD computers and lists all shared folders.</td></tr>
    <tr><td><strong>Retrieve-ADDomain-AuditPolicy-Configuration.ps1</strong></td><td>Exports domain audit policies for review and compliance.</td></tr>
    <tr><td><strong>Retrieve-Elevated-ADForestInfo.ps1</strong></td><td>Displays privileged group memberships and domain roles.</td></tr>
    <tr><td><strong>Synchronize-ADForestDCs.ps1</strong></td><td>Forces replication across all Domain Controllers.</td></tr>
    <tr><td><strong>Unlock-SMBShareADUserAccess.ps1</strong></td><td>Restores SMB share permissions for users.</td></tr>
    <tr><td><strong>Update-ADComputer-Descriptions.ps1</strong></td><td>Updates computer descriptions based on inventory data.</td></tr>
    <tr><td><strong>Update-ADUserDisplayName.ps1</strong></td><td>Applies naming standards to user display names in AD.</td></tr>
  </tbody>
</table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Run the Script:</strong> Right-click the script and choose <code>Run with PowerShell</code>, or execute from an elevated console.</li>
    <li><strong>Provide Inputs:</strong> Supply parameters or interact with GUI prompts depending on the script.</li>
    <li><strong>Review Outputs:</strong> Review <code>.log</code> and <code>.csv</code> files generated in the working directory or <code>C:\Logs-TEMP\</code>.</li>
  </ol>

  <hr />

  <h2>📄 Complementary Files Overview</h2>
  <ul>
    <li><strong>GPO-Template-Backup.zip:</strong> Archive containing exported GPOs for import.</li>
    <li><strong>Default-AD-OUs.csv:</strong> List of OUs used in organizational design scripts.</li>
    <li><strong>Password-Reset-Log.log:</strong> Example output from bulk password reset operations.</li>
  </ul>

  <hr />

  <h2>💡 Tips for Optimization</h2>
  <ul>
    <li><strong>Automate Execution:</strong> Use Task Scheduler or Group Policy to run maintenance tasks regularly.</li>
    <li><strong>Centralize Logs and Reports:</strong> Store execution logs in a centralized folder or logging server.</li>
    <li><strong>Tailor for Your Domain:</strong> Modify filter logic, OU paths, and naming schemes to fit enterprise conventions.</li>
  </ul>
</div>
