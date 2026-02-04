# 🤝 Contributing to Windows SysAdmin ProSuite

Thank you for your interest in contributing to **Windows SysAdmin ProSuite**.  
This repository contains **enterprise-grade PowerShell and VBScript automation tools** focused on Windows Server, Active Directory, ITSM workflows, and security operations.

Contributions are welcome and appreciated, provided they follow the guidelines below.

---

## 📝 Ways to Contribute

### 🐞 Reporting Bugs
All issues **must** be submitted using the GitHub Issue Forms.

- Use **Bug Report** for defects, errors, or unexpected behavior
- Provide:
  - Clear reproduction steps
  - Expected vs actual behavior
  - Environment details (OS, PowerShell version, tool path)
  - Logs or screenshots when applicable

👉 Issue forms automatically apply labels and ensure consistent structure.

---

### ✨ Requesting Features
Use the **Feature Request** issue form when proposing enhancements.

Please include:
- The problem being solved
- The proposed solution
- Alternatives considered
- Expected impact or benefit

Feature requests should align with:
- Windows Server administration
- Active Directory / IAM
- ITSM automation
- Security and compliance tooling

---

### 🔀 Submitting Pull Requests

#### 1. Fork & Branch
- Fork the repository
- Create a branch from `main`
- Use descriptive branch names:
  - `feature/add-dhcp-tool`
  - `bugfix/fix-null-check`
  - `docs/update-readme`

#### 2. Development Rules
- Follow existing folder structure
- Do **not** mix unrelated changes in a single PR
- Do **not** modify version numbers inside PRs

#### 3. Coding Standards (Mandatory)

**PowerShell**
- 4-space indentation
- No `Write-Host`
- Comment-based help headers required
- Compatible with PowerShell 5.1+
- Logging to `C:\Logs-TEMP`
- No breaking changes without discussion

**Linting / Formatting**
- PSScriptAnalyzer rules enforced
- Prettier formatting for Markdown, YAML, JSON
- CI must pass before review

#### 4. Testing
Before submitting:
- Test scripts locally
- Validate GUI behavior if applicable
- Ensure no regressions are introduced

#### 5. Submit the PR
- Target the `main` branch
- Clearly describe:
  - What was changed
  - Why it was changed
  - Any limitations or follow-ups

---

## ☑️ Pull Request Checklist

Before submitting, confirm:

- [ ] Code follows repository standards
- [ ] Scripts were tested locally
- [ ] No unrelated files were modified
- [ ] Documentation updated when needed
- [ ] No new warnings or errors introduced
- [ ] CI checks pass

---

## 💬 Communication & Conduct

- Be respectful and constructive
- Keep discussions technical and objective
- Use Issues for questions or clarifications

Please read the **Code of Conduct** before contributing.

---

## 📚 Useful Links

- 📄 **README:**  
  https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite

- 📜 **Code of Conduct:**  
  https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/CODE_OF_CONDUCT.md

- 🔐 **Security Policy:**  
  https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/SECURITY.md

---

Thank you for helping improve **Windows SysAdmin ProSuite** 🚀
