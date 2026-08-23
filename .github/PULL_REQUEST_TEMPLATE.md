# Pull Request

## Summary

Describe the change and the problem it solves.

## Related Issue

Use an applicable closing keyword when appropriate:

```text
Fixes #123
```

## Affected Component

- [ ] ADCS-Management-Tools
- [ ] AD-SSO-Integrations
- [ ] BlueTeam-Tools
- [ ] Core-ScriptLibrary
- [ ] GPO-Templates
- [ ] ITSM-Templates-SVR
- [ ] ITSM-Templates-WKS
- [ ] ProSuite-Hub
- [ ] SysAdmin-Tools
- [ ] WSUS-Management-Tools
- [ ] All-Repository-Files
- [ ] READMEs-Files-Package
- [ ] Repository governance / CI / metadata
- [ ] Other

## Type of Change

- [ ] Bug fix
- [ ] New feature
- [ ] Security hardening or vulnerability remediation
- [ ] Refactor or reliability improvement
- [ ] Documentation update
- [ ] CI/CD or release-engineering change
- [ ] Breaking change

## Technical and Operational Impact

Describe:

- Behavior before the change
- Behavior after the change
- Administrative privileges required
- Infrastructure prerequisites
- Compatibility impact
- Migration or rollback considerations
- Potential production impact

## Testing

**Environment:**

- Operating system:
- Windows/Server version:
- PowerShell version:
- Affected role/service:
- Test environment type:

**Validation performed:**

- [ ] Script parsing/execution
- [ ] Windows PowerShell 5.1 compatibility
- [ ] Dry-run / WhatIf / confirmation path where applicable
- [ ] State-changing execution where applicable
- [ ] Repeated execution / idempotency
- [ ] Error handling
- [ ] Logging / report output
- [ ] GUI behavior where applicable
- [ ] PSScriptAnalyzer
- [ ] Prettier / EditorConfig
- [ ] Gitleaks / secret review
- [ ] Other:

## Security Review

- [ ] No credentials, secrets, private keys, tokens, or sensitive production data are included.
- [ ] Least-privilege requirements were reviewed.
- [ ] High-impact operations include appropriate confirmation or safety controls.
- [ ] Security-sensitive behavior is documented.
- [ ] Any new external dependency or GitHub Action was reviewed.

## Documentation and Release Governance

- [ ] Relevant README documentation was updated.
- [ ] `CHANGELOG.md` was updated when release-relevant.
- [ ] Managed CHANGELOG sections retain `Added / Changed / Security`.
- [ ] Canonical module names and repository paths remain aligned.
- [ ] Release workflow changes were included if package/distribution behavior changed.
- [ ] License and citation metadata remain accurate.

## Final Checklist

- [ ] The PR is focused and contains no unrelated changes.
- [ ] Code follows repository engineering standards.
- [ ] I reviewed my own changes.
- [ ] New warnings or errors were not introduced without explanation.
- [ ] Applicable local tests pass.
- [ ] Applicable CI checks pass or remaining findings are explained below.

## Additional Notes

Add screenshots, sanitized logs, limitations, follow-up work, or reviewer guidance here.
