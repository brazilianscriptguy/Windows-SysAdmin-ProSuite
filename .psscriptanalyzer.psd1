@{
    # Corporate runtime-safety profile (low noise)
    # Intent: catch high-risk patterns that can break or endanger execution across a Windows estate,
    # while avoiding style/formatting and common GUI-state noise.

    # Keep the ruleset curated (enterprise-friendly signal/noise)
    IncludeDefaultRules = $false

    # Only meaningful severities
    Severity = @('Error','Warning')

    # High-signal safety + security + operability rules
    IncludeRules = @(
        # --- Execution / code injection risk ---
        'PSAvoidUsingInvokeExpression',

        # --- Credential / secret handling safety ---
        'PSAvoidUsingPlainTextForPassword',
        'PSAvoidUsingConvertToSecureStringWithPlainText',
        'PSAvoidUsingUsernameAndPasswordParams',

        # --- Reliability / observability ---
        'PSAvoidUsingEmptyCatchBlock',

        # --- Operational professionalism (enterprise tooling standards) ---
        'PSAvoidUsingWriteHost',
        'PSAvoidUsingCmdletAliases',

        # --- Safe change model (WhatIf/Confirm) ---
        'PSUseShouldProcessForStateChangingFunctions',

        # --- Legacy/compat risk (common in Windows estates) ---
        'PSAvoidUsingWMICmdlet'
    )

    Rules = @{
        # -------------------------
        # ENABLED (high signal)
        # -------------------------

        PSAvoidUsingInvokeExpression = @{
            Enable = $true
        }

        PSAvoidUsingPlainTextForPassword = @{
            Enable = $true
        }

        PSAvoidUsingConvertToSecureStringWithPlainText = @{
            Enable = $true
        }

        PSAvoidUsingUsernameAndPasswordParams = @{
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

        PSAvoidUsingWMICmdlet = @{
            Enable = $true
        }

        # -------------------------
        # DISABLED (noise / style)
        # -------------------------

        # Formatting/style noise (keep out of the safety report)
        PSUseConsistentWhitespace = @{
            Enable = $false
        }

        PSUseConsistentIndentation = @{
            Enable = $false
        }

        # Common "GUI state" / large script patterns (too noisy for your repo today)
        PSAvoidGlobalVars = @{
            Enable = $false
        }
    }
}
