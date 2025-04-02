<div>
  <h1>🛠️ Active Directory Management Tools</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>Active Directory Management Folder</strong> contains a suite of 
    <strong>PowerShell scripts</strong> designed to streamline and automate tasks related to 
    <strong>Active Directory (AD)</strong>. These tools help administrators manage accounts, 
    organizational units (OUs), group policies, and overall directory services while enhancing 
    security and operational efficiency.
  </p>

  <h3>Key Features:</h3>
  <ul>
    <li><strong>User-Friendly GUI:</strong> Simplifies interaction with intuitive graphical interfaces for selected scripts.</li>
    <li><strong>Detailed Logging:</strong> All scripts generate <code>.log</code> files for comprehensive tracking and troubleshooting.</li>
    <li><strong>Exportable Reports:</strong> Outputs in <code>.csv</code> format for streamlined analysis and reporting.</li>
    <li><strong>Efficient Directory Management:</strong> Automates AD management tasks, reducing manual effort and improving accuracy.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell</strong>
      <ul>
        <li>PowerShell 5.1 or later must be enabled on your system.</li>
        <li>The following module may need to be imported where applicable:</li>
        <li><code>Import-Module ActiveDirectory</code></li>
      </ul>
    </li>
    <li>
      <strong>🔑 Administrator Privileges</strong>
      <p>Scripts may require elevated permissions to access sensitive configurations and make changes in Active Directory.</p>
    </li>
    <li>
      <strong>🖥️ Remote Server Administration Tools (RSAT)</strong>
      <p>Install RSAT on your Windows 10/11 workstation to enable remote management of Active Directory and server roles.</p>
    </li>
    <li>
      <strong>⚙️ Execution Policy</strong>
      <p>Temporarily set the execution policy to allow script execution:</p>
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
    <tr>
      <td><strong>Add-ADComputers-GrantPermissions.ps1</strong></td>
      <td>Automates adding computers to specific OUs in AD and assigns necessary permissions for domain joining.</td>
    </tr>
    <tr>
      <td><strong>Add-ADInetOrgPerson.ps1</strong></td>
      <td>Creates <code>InetOrgPerson</code> entries in AD, enabling detailed organizational attribute management.</td>
    </tr>
    <tr>
      <td><strong>Add-ADUserAccount.ps1</strong></td>
      <td>Facilitates the creation of new AD user accounts within specified OUs through an intuitive interface.</td>
    </tr>
    <tr>
      <td><strong>Adjust-ExpirationDate-ADUserAccount.ps1</strong></td>
      <td>Updates expiration dates for AD user accounts, ensuring compliance with organizational policies.</td>
    </tr>
    <tr>
      <td><strong>Check-Shorter-ADComputerNames.ps1</strong></td>
      <td>Identifies AD computer names that do not meet minimum length requirements, helping enforce naming conventions.</td>
    </tr>
    <tr>
      <td><strong>Cleanup-Inactive-ADComputerAccounts.ps1</strong></td>
      <td>Detects and removes inactive AD computer accounts to improve security and directory organization.</td>
    </tr>
    <tr>
      <td><strong>Cleanup-MetaData-ADForest-Tool.ps1</strong></td>
      <td>Removes orphaned objects and synchronizes metadata across Domain Controllers for optimal performance.</td>
    </tr>
    <tr>
      <td><strong>Create-OUsDefaultADStructure.ps1</strong></td>
      <td>Defines and implements a standardized OU structure for easier domain setup and management.</td>
    </tr>
    <tr>
      <td><strong>Enforce-Expiration-ADUserPasswords.ps1</strong></td>
      <td>Enforces password expiration policies for users in specific OUs, ensuring compliance with security requirements.</td>
    </tr>
    <tr>
      <td><strong>Export-n-Import-GPOsTool.ps1</strong></td>
      <td>Provides a GUI for exporting and importing Group Policy Objects (GPOs) between domains, with progress tracking.</td>
    </tr>
    <tr>
      <td><strong>Fix-ADForest-DNSDelegation.ps1</strong></td>
      <td>Repairs and maintains DNS delegation settings in AD forests for proper name resolution.</td>
    </tr>
    <tr>
      <td><strong>Inventory-ADDomainComputers.ps1</strong></td>
      <td>Generates a detailed inventory of all computers within an AD domain for asset management.</td>
    </tr>
    <tr>
      <td><strong>Inventory-ADGroups-their-Members.ps1</strong></td>
      <td>Retrieves group membership details to assist in audits and compliance checks.</td>
    </tr>
    <tr>
      <td><strong>Inventory-ADMemberServers.ps1</strong></td>
      <td>Produces detailed reports on member servers in the AD domain for simplified management.</td>
    </tr>
    <tr>
      <td><strong>Inventory-ADUserAttributes.ps1</strong></td>
      <td>Extracts user attributes from AD, helping administrators manage and report user data more effectively.</td>
    </tr>
    <tr>
      <td><strong>Inventory-ADUserLastLogon.ps1</strong></td>
      <td>Tracks user last logon times, helping identify inactive accounts.</td>
    </tr>
    <tr>
      <td><strong>Inventory-ADUserWithNonExpiringPasswords.ps1</strong></td>
      <td>Lists users with non-expiring passwords, enabling enforcement of password policies.</td>
    </tr>
    <tr>
      <td><strong>Inventory-InactiveADComputerAccounts.ps1</strong></td>
      <td>Identifies inactive AD computer accounts for cleanup and organization.</td>
    </tr>
    <tr>
      <td><strong>Manage-Disabled-Expired-ADUserAccounts.ps1</strong></td>
      <td>Automates the disabling of expired AD user accounts for improved security and compliance.</td>
    </tr>
    <tr>
      <td><strong>Manage-FSMOs-Roles.ps1</strong></td>
      <td>Simplifies managing and transferring Flexible Single Master Operation (FSMO) roles within the AD forest.</td>
    </tr>
    <tr>
      <td><strong>Move-ADComputer-betweenOUs.ps1</strong></td>
      <td>Automates moving AD computers between OUs based on policies.</td>
    </tr>
    <tr>
      <td><strong>Move-ADUser-betweenOUs.ps1</strong></td>
      <td>Facilitates moving AD users between OUs to maintain directory organization.</td>
    </tr>
    <tr>
      <td><strong>Reset-ADUserPasswordsToDefault.ps1</strong></td>
      <td>Resets user passwords to a default value for bulk operations or compliance purposes.</td>
    </tr>
    <tr>
      <td><strong>Retrieve-ADComputer-SharedFolders.ps1</strong></td>
      <td>Lists shared folders on AD computers for audit and compliance reviews.</td>
    </tr>
    <tr>
      <td><strong>Retrieve-ADDomain-AuditPolicy-Configuration.ps1</strong></td>
      <td>Extracts audit policy configurations for the entire AD domain for compliance reporting.</td>
    </tr>
    <tr>
      <td><strong>Retrieve-Elevated-ADForestInfo.ps1</strong></td>
      <td>Provides detailed information on AD forests, including elevated privileges and configurations.</td>
    </tr>
    <tr>
      <td><strong>Synchronize-ADForestDCs.ps1</strong></td>
      <td>Synchronizes Domain Controllers across the AD forest for optimal performance.</td>
    </tr>
    <tr>
      <td><strong>Unlock-SMBShareADUserAccess.ps1</strong></td>
      <td>Unlocks SMB shared folder access for specific AD users.</td>
    </tr>
    <tr>
      <td><strong>Update-ADComputer-Descriptions.ps1</strong></td>
      <td>Updates descriptions for AD computer accounts to maintain directory accuracy.</td>
    </tr>
    <tr>
      <td><strong>Update-ADUserDisplayName.ps1</strong></td>
      <td>Modifies display names of AD users to align with organizational naming conventions.</td>
    </tr>
  </tbody>
</table>
<hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Run the Script:</strong> Launch the desired script using the <code>Run With PowerShell</code> option.</li>
    <li><strong>Provide Inputs:</strong> Follow on-screen prompts or customize parameters as required.</li>
    <li><strong>Review Outputs:</strong> Check generated <code>.log</code> files and exported <code>.csv</code> reports for results.</li>
  </ol>

  <hr />

  <h2>📝 Logging and Output</h2>
  <ul>
    <li><strong>📄 Logs:</strong> Each script generates detailed logs in <code>.log</code> format.</li>
    <li><strong>📊 Reports:</strong> Scripts export data in <code>.csv</code> format for auditing and reporting.</li>
  </ul>

  <hr />

  <h2>💡 Tips for Optimization</h2>
  <ul>
    <li><strong>Automate Execution:</strong> Schedule scripts to run periodically using Task Scheduler.</li>
    <li><strong>Centralize Logs and Reports:</strong> Store <code>.log</code> and <code>.csv</code> files in a shared repository for collaboration and analysis.</li>
    <li><strong>Customize Scripts:</strong> Adjust script parameters to align with your organization's specific needs.</li>
  </ul>
</div>
