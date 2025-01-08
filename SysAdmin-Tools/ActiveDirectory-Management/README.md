<div>
  <h1>🛠️ Active Directory Management Tools</h1>

  <h2>📄 Overview</h2>
  <p>
    This folder contains a comprehensive suite of PowerShell scripts designed to automate and streamline tasks related to Active Directory (AD). 
    These tools help administrators manage user accounts, computer accounts, organizational units, and overall directory maintenance, 
    enhancing both efficiency and security.
  </p>

  <hr />

  <h2>📜 Script List and Descriptions</h2>
  <table border="1" style="border-collapse: collapse; width: 100%;">
    <thead>
      <tr>
        <th style="padding: 8px;">Script Name</th>
        <th style="padding: 8px;">Description</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td style="padding: 8px;">Add-ADComputers-GrantPermissions.ps1</td>
        <td style="padding: 8px;">
          Automates adding workstations to specific OUs in AD and assigns necessary permissions for domain joining.
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;">Add-ADInetOrgPerson.ps1</td>
        <td style="padding: 8px;">
          Simplifies creating <code>InetOrgPerson</code> entries in AD, enabling detailed organizational attribute management.
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;">Add-ADUserAccount.ps1</td>
        <td style="padding: 8px;">
          Facilitates creating new AD user accounts within specified OUs through an intuitive user interface.
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;">Adjust-ExpirationDate-ADUserAccount.ps1</td>
        <td style="padding: 8px;">
          Provides a GUI for updating the expiration dates of AD user accounts, ensuring compliance with organizational policies.
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;">Check-Shorter-ADComputerNames.ps1</td>
        <td style="padding: 8px;">
          Identifies AD computer names that do not meet minimum length requirements, helping enforce naming conventions.
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;">Cleanup-Inactive-ADComputerAccounts.ps1</td>
        <td style="padding: 8px;">
          Detects and removes inactive computer accounts in AD, improving security and directory organization.
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;">Cleanup-MetaData-ADForest-Tool.ps1</td>
        <td style="padding: 8px;">
          Cleans up metadata in the AD forest by removing orphaned objects and synchronizing Domain Controllers for optimal performance.
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;">Create-OUsDefaultADStructure.ps1</td>
        <td style="padding: 8px;">
          Helps define and implement a standardized OU structure for easier domain setup or reorganization.
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;">Enforce-Expiration-ADUserPasswords.ps1</td>
        <td style="padding: 8px;">
          Enforces password expiration policies for users within specific OUs, ensuring compliance with security requirements.
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;">Export-n-Import-GPOsTool.ps1</td>
        <td style="padding: 8px;">
          Provides a GUI for exporting and importing Group Policy Objects (GPOs) between domains, with progress tracking.
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;">Inventory-ADDomainComputers.ps1</td>
        <td style="padding: 8px;">
          Generates a detailed inventory of all computers within an AD domain for asset tracking and management.
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;">Inventory-ADGroups-their-Members.ps1</td>
        <td style="padding: 8px;">
          Retrieves group membership details, aiding in audits and compliance checks.
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;">Inventory-ADMemberServers.ps1</td>
        <td style="padding: 8px;">
          Produces detailed reports on member servers in the AD domain, simplifying server management.
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;">Inventory-ADUserAttributes.ps1</td>
        <td style="padding: 8px;">
          Extracts user attributes from AD, helping administrators manage and report user data more effectively.
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;">Inventory-ADUserLastLogon.ps1</td>
        <td style="padding: 8px;">
          Tracks user last logon times, helping identify inactive accounts.
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;">Inventory-ADUserWithNonExpiringPasswords.ps1</td>
        <td style="padding: 8px;">
          Lists users with non-expiring passwords, enabling enforcement of password policies.
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;">Manage-Disabled-Expired-ADUserAccounts.ps1</td>
        <td style="padding: 8px;">
          Automates the disabling of expired AD user accounts, improving security and compliance.
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;">Manage-FSMOs-Roles.ps1</td>
        <td style="padding: 8px;">
          Simplifies managing and transferring Flexible Single Master Operation (FSMO) roles within the AD forest.
        </td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🔍 How to Use</h2>
  <ul>
    <li>Each script includes a detailed header for instructions and requirements.</li>
    <li>Open the scripts in a PowerShell editor to review their descriptions and modify parameters as needed.</li>
    <li>Ensure that all necessary modules, such as <code>ActiveDirectory</code>, are installed and imported before running the scripts.</li>
  </ul>

  <hr />

  <h2>💻 Prerequisites</h2>
  <ul>
    <li>
      <strong>PowerShell Version:</strong> PowerShell 5.1 or later.  
      Verify your version with:
      <pre><code>$PSVersionTable.PSVersion</code></pre>
    </li>
    <li>
      <strong>Active Directory Module:</strong> Ensure the <code>ActiveDirectory</code> module is installed. Import it with:
      <pre><code>Import-Module ActiveDirectory</code></pre>
    </li>
    <li>
      <strong>Administrator Privileges:</strong> Most scripts require elevated permissions to access AD configurations and apply changes.
    </li>
    <li>
      <strong>Execution Policy:</strong> Temporarily set the execution policy to allow script execution:
      <pre><code>Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process</code></pre>
    </li>
  </ul>
</div>
