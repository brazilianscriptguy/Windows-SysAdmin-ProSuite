@{
    # Goal: high-signal findings only (quality/security). No style noise.
    # This settings file is intended for "report-only" CI runs.

    # Do NOT include the full default ruleset (too noisy for large repos)
    IncludeDefaultRules = $false

    # Only report these severities
    Severity = @('Error','Warning')

    # Curated high-signal rules (quality/security)
    IncludeRules = @(
        # Security / execution safety
        'PSAvoidUsingInvokeExpression',

        # Reliability / observability
        'PSAvoidUsingEmptyCatchBlock',

        # Professional output (avoid Write-Host in tooling)
        'PSAvoidUsingWriteHost',

        # Maintainability / correctness
        'PSAvoidUsingCmdletAliases',

        # Safety for state-changing functions (WhatIf/Confirm)
        'PSUseShouldProcessForStateChangingFunctions'
    )

    Rules = @{
        PSAvoidUsingInvokeExpression = @{
            Enable = $true
        }

        PSAvoidUsingEmptyCatchBlock = @{
            Enable = $true
        }

        PSAvoidUsingWriteHost = @{
            Enable = $true
        }

        PSAvoidUsingCmdletAliases = @{
            Enable = $true
        }

        PSUseShouldProcessForStateChangingFunctions = @{
            Enable = $true
        }

        # Explicitly disable style rules (noise)
        PSUseConsistentWhitespace = @{
            Enable = $false
        }

        PSUseConsistentIndentation = @{
            Enable = $false
        }

        # Explicitly disable common GUI/script-state noise (optional but recommended for your goal)
        PSAvoidGlobalVars = @{
            Enable = $false
        }
    }
}
