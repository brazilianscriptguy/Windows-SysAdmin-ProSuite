<div align="center">
  <h1>WSUS Admin Maintenance Tool</h1>
  <p>A PowerShell script with a GUI to manage and maintain Windows Server Update Services (WSUS) and its SUSDB database.</p>
  <img src="https://img.shields.io/badge/Version-1.0-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/Last%20Updated-July%2011,%202025-green.svg" alt="Last Updated">
  <a href="https://twitter.com/brazilianscriptguy">
    <img src="https://img.shields.io/badge/Twitter-@brazilianscriptguy-blue.svg" alt="Twitter">
  </a>
</div>

<div align="left">

## Overview
This tool is designed to simplify WSUS maintenance by providing a graphical interface to perform tasks such as declining unapproved, expired, or superseded updates, compressing updates, purging unassigned files, and managing the SUSDB database (e.g., backup, reindexing, shrinking). It leverages PowerShell and the WSUS Administration Console components to automate routine maintenance tasks.

## Installation
1. **Prerequisites**: Ensure the WSUS Administration Console is installed on the server.
2. **Download**: Clone or download this repository to your local machine.
   ```bash
   git clone https://github.com/yourusername/WSUS-Admin-Maintenance-Tool.git
