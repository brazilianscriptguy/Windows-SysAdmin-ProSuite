# Contributing to Windows-SysAdmin-ProSuite

Thank you for your interest in contributing to **Windows-SysAdmin-ProSuite**.

The repository is an enterprise-oriented Windows automation platform covering Active Directory, IAM, LDAP/SSO, AD CS and enterprise PKI, Group Policy, Windows Server, Windows 10/11, WSUS and SUSDB, ITSM-aligned lifecycle automation, Blue Team operations, and DFIR.

Contributions are welcome when they preserve the repository's engineering, security, documentation, licensing, and release-governance standards.

---

## Repository Architecture

The project currently maintains **10 functional Suite Modules**:

- `ADCS-Management-Tools`
- `AD-SSO-Integrations`
- `BlueTeam-Tools`
- `Core-ScriptLibrary`
- `GPO-Templates`
- `ITSM-Templates-SVR`
- `ITSM-Templates-WKS`
- `ProSuite-Hub`
- `SysAdmin-Tools`
- `WSUS-Management-Tools`

GitHub Actions manages **12 distribution packages**: the 10 modules above plus:

- `All-Repository-Files`
- `READMEs-Files-Package`

Canonical component names, directory paths, CHANGELOG headings, release tags, ZIP names, SHA256 manifests, and release metadata must remain synchronized.

---

## Ways to Contribute

### Reporting Bugs

Use the repository's GitHub Issue Forms for defects, regressions, or unexpected behavior.

Include:

- Clear reproduction steps
- Expected and actual behavior
- Affected module, script, or workflow
- Operating system and version
- Windows PowerShell or PowerShell version
- Relevant server role or infrastructure context
- Sanitized logs, screenshots, or diagnostic output where useful

Do not include passwords, tokens, private keys, production credentials, personal data, or other secrets.

### Requesting Features

Use the Feature Request issue form and describe the problem, proposed solution, alternatives, operational/security impact, affected module, and compatibility considerations.

### Security Vulnerabilities

Do not open a public Issue for a suspected vulnerability. Follow [`SECURITY.md`](SECURITY.md).

---

## Pull Request Workflow

### 1. Fork and Branch

Fork the repository and create a branch from `main`.

Recommended branch naming:

```text
feature/add-dhcp-tool
feature/add-wsus-assessment
bugfix/fix-null-check
security/harden-credential-handling
docs/update-adcs-readme
ci/update-release-workflow
```

### 2. Keep Changes Focused

- Do not mix unrelated changes in one PR.
- Do not modify release versions unless the PR explicitly owns a versioning change.
- Do not rename canonical Suite Modules or CHANGELOG headings without updating dependent workflows in the same PR.
- Preserve repository folder boundaries and module responsibilities.

### 3. PowerShell Engineering Standards

PowerShell contributions should:

- Target **Windows PowerShell 5.1** as the primary compatibility baseline unless explicitly documented otherwise.
- Use four-space indentation.
- Avoid `Write-Host` for operational output unless a narrowly justified interactive scenario requires it.
- Include comment-based help for reusable scripts and functions.
- Use structured, actionable error handling.
- Avoid hardcoded production credentials, secrets, passwords, or private key material.
- Use least privilege and explicit administrative intent.
- Implement `SupportsShouldProcess`, dry-run behavior, confirmation controls, or equivalent safeguards for state-changing operations where technically appropriate.
- Perform prerequisite/dependency validation before high-impact operations.
- Perform post-change verification when state is modified.
- Use the repository's established logging/reporting patterns or a configurable path rather than introducing a new fixed logging root.
- Preserve idempotent or repeatable behavior where practical.

### 4. Formatting and Static Analysis

Before submission:

- Run PSScriptAnalyzer with repository settings.
- Run Prettier checks for supported Markdown, YAML, JSON, and web/configuration assets.
- Respect `.editorconfig`, `.gitattributes`, `.prettierrc`, and `.prettierignore`.
- Ensure Gitleaks does not identify committed secrets.
- Review relevant SARIF or code-scanning findings.

### 5. Documentation and Release Governance

Update documentation when behavior, prerequisites, configuration, output, module inventory, security requirements, or operational impact changes.

Managed CHANGELOG sections must retain:

```markdown
## Component-Name

### Added

### Changed

### Security
```

When adding or renaming a managed component, update all applicable governance surfaces: README files, `CHANGELOG.md`, GitHub Actions release/CHANGELOG workflows, and package metadata.

### 6. Testing

Depending on the component, test:

- Script parsing and execution
- Windows PowerShell 5.1 compatibility
- Dry-run / WhatIf / confirmation behavior
- State-changing execution where applicable
- Repeated execution/idempotency
- Error handling
- Logging and report output
- GUI behavior where applicable
- Relevant AD, PKI, GPO, WSUS, or infrastructure prerequisites

Do not test destructive operations against production systems without authorization, change control, backup/recovery readiness, and operational safeguards.

---

## Pull Request Checklist

- [ ] The change is focused and belongs in the selected module or repository area.
- [ ] Windows PowerShell 5.1 compatibility was preserved where required.
- [ ] Local testing was completed.
- [ ] Potentially disruptive behavior includes appropriate safeguards.
- [ ] Error handling and operational logging were reviewed.
- [ ] No secrets, credentials, private keys, or sensitive production data were committed.
- [ ] PSScriptAnalyzer and applicable formatting checks were reviewed.
- [ ] Relevant documentation was updated.
- [ ] `CHANGELOG.md` was updated when release-relevant.
- [ ] Canonical module and distribution names remain synchronized.
- [ ] No unrelated files were modified.
- [ ] Applicable CI checks pass.

---

## Licensing and Reuse

Contributions are accepted under the repository-wide [MIT License](../LICENSE.txt).

By submitting a contribution, you represent that you have the right to submit it under terms compatible with the repository's MIT License.

Copies or substantial portions of the Software must retain the applicable copyright and MIT permission notices.

Academic or institutional citation through the repository DOI and `CITATION.cff` is encouraged but is separate from the MIT License requirements.

---

## Communication and Conduct

Keep discussions technical, respectful, and constructive. Read [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) before contributing.

---

## Useful Links

- [Main repository](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite)
- [Code of Conduct](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/CODE_OF_CONDUCT.md)
- [Security Policy](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/SECURITY.md)
- [MIT License](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/LICENSE.txt)
- [Citation metadata](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/CITATION.cff)
- [CHANGELOG](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/CHANGELOG.md)
