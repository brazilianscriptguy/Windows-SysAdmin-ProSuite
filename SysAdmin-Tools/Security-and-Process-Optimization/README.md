<div>
  <h1>🛡️ Security and Process Optimization Tools</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>Security and Process Optimization</strong> folder includes a refined suite of 
    <strong>PowerShell scripts</strong> to improve certificate hygiene, file structure compliance, licensing visibility, 
    and privileged access control. These tools enable safe automation of sensitive operations while reducing manual administrative overhead 
    and enhancing security posture.
  </p>

  <h3>Key Features:</h3>
  <ul>
    <li><strong>Certificate Management:</strong> Clean expired certs and organize shared certificate repositories.</li>
    <li><strong>Access and Compliance Audits:</strong> Retrieve product keys, elevated accounts, shared folders, and software lists.</li>
    <li><strong>Storage and File Optimization:</strong> Shorten overly long file names and clean up aged/empty files.</li>
    <li><strong>Safe Offboarding:</strong> Unjoin and clean computer metadata from AD.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell</strong>
      <ul>
        <li>Requires PowerShell 5.1 or newer.</li>
        <li>Check version with:
          <pre><code>$PSVersionTable.PSVersion</code></pre>
        </li>
      </ul>
    </li>
    <li>
      <strong>🔑 Administrator Access</strong>
      <p>Most scripts require elevated permissions, especially those accessing system certificates, disk, registry, or AD.</p>
    </li>
    <li>
      <strong>📂 Execution Policy</strong>
      <p>Allow script execution with:
        <pre><code>Set-ExecutionPolicy RemoteSigned -Scope Process</code></pre>
      </p>
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
        <td><strong>Check-ServicesPort-Connectivity.ps1</strong></td>
        <td>Checks the real-time connectivity status of specified service ports. Logs are created for later analysis.</td>
      </tr>
      <tr>
        <td><strong>Cleanup-CertificateAuthority-Tool.ps1</strong></td>
        <td>Removes expired or unnecessary certificate data from local Certificate Authority servers to enhance compliance.</td>
      </tr>
      <tr>
        <td><strong>Cleanup-Repository-ExpiredCertificates-Tool.ps1</strong></td>
        <td>Scans shared repositories for expired certificates and removes them to maintain a clean compliance environment.</td>
      </tr>
      <tr>
        <td><strong>Initiate-MultipleRDPSessions.ps1</strong></td>
        <td>Allows launching multiple simultaneous RDP sessions on supported systems, useful for IT multi-session environments.</td>
      </tr>
      <tr>
        <td><strong>Organize-CERTs-Repository.ps1</strong></td>
        <td>Sorts and organizes SSL/TLS certificates in shared repositories based on issuer or expiration for improved manageability.</td>
      </tr>
      <tr>
        <td><strong>Purge-ExpiredInstalledCertificates-Tool.ps1</strong></td>
        <td>Scans and removes expired certificates from the local machine’s certificate store.</td>
      </tr>
      <tr>
        <td><strong>Purge-ExpiredInstalledCertificates-viaGPO.ps1</strong></td>
        <td>GPO-ready script to automate expired certificate cleanup on domain-joined computers.</td>
      </tr>
      <tr>
        <td><strong>Remove-EmptyFiles-or-DateRange.ps1</strong></td>
        <td>Deletes files that are empty or fall within a defined age range, supporting storage hygiene policies.</td>
      </tr>
      <tr>
        <td><strong>Retrieve-Windows-ProductKey.ps1</strong></td>
        <td>Extracts the product key of the local Windows installation for inventory and audit tracking.</td>
      </tr>
      <tr>
        <td><strong>Shorten-LongFileNames-Tool.ps1</strong></td>
        <td>Automatically detects and shortens files with long paths to prevent sync and backup errors.</td>
      </tr>
      <tr>
        <td><strong>Unjoin-ADComputer-and-Cleanup.ps1</strong></td>
        <td>Securely unjoins a computer from AD, removes stale DNS records, and resets the system to workgroup mode.</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Run the Script:</strong> Right-click and select <code>Run with PowerShell</code> or run from an elevated shell.</li>
    <li><strong>Provide Inputs:</strong> Use prompt-based input or adjust pre-defined parameters in the script.</li>
    <li><strong>Review Results:</strong> Check log files and exported reports located in the <code>C:\Logs-TEMP</code> or user-defined path.</li>
  </ol>

  <hr />

  <h2>📝 Logging and Output</h2>
  <ul>
    <li><strong>📄 Logs:</strong> Logs are stored locally and contain step-by-step execution data.</li>
    <li><strong>📊 Reports:</strong> Where applicable, scripts export structured <code>.csv</code> reports for inventory or compliance audits.</li>
  </ul>

  <hr />

  <h2>💡 Tips for Optimization</h2>
  <ul>
    <li><strong>Use GPO-Compatible Scripts:</strong> Deploy cleanup scripts via GPO for enterprise-wide automation.</li>
    <li><strong>Schedule Periodic Cleanup:</strong> Use Task Scheduler for unattended maintenance runs.</li>
    <li><strong>Structure Repositories:</strong> Organize certificate and file repositories to improve manageability and reduce risk.</li>
  </ul>
</div>
