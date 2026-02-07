@{
    # Corporate runtime-safety profile (low noise)
    # Baseline: PowerShell 5.1 compatible estates.
    # Goal: catch high-risk patterns (security + runtime safety) without style noise.

    IncludeDefaultRules = $false

    # Only meaningful severities for action (keep noise down)
    Severity = @('Error', 'Warning')

    IncludeRules = @(
        # --- Execution / injection risk ---
        'PSAvoidUsingInvokeExpression',

        # --- Credential / secret handling ---
        'PSAvoidUsingPlainTextForPassword',
        'PSAvoidUsingConvertToSecureStringWithPlainText',
        'PSAvoidUsingUsernameAndPasswordParams',

        # --- Reliability ---
        'PSAvoidUsingEmptyCatchBlock',

        # --- Operability / enterprise standards ---
        'PSAvoidUsingWriteHost',
        'PSAvoidUsingCmdletAliases',

        # --- Safe change model ---
        'PSUseShouldProcessForStateChangingFunctions',

        # --- Legacy / compatibility risk ---
        'PSAvoidUsingWMICmdlet'
    )

    Rules = @{
        PSAvoidUsingInvokeExpression = @{ Enable = $true }

        PSAvoidUsingPlainTextForPassword = @{ Enable = $true }
        PSAvoidUsingConvertToSecureStringWithPlainText = @{ Enable = $true }
        PSAvoidUsingUsernameAndPasswordParams = @{ Enable = $true }

        PSAvoidUsingEmptyCatchBlock = @{ Enable = $true }

        PSAvoidUsingWriteHost = @{ Enable = $true }
        PSAvoidUsingCmdletAliases = @{ Enable = $true }

        PSUseShouldProcessForStateChangingFunctions = @{ Enable = $true }

        PSAvoidUsingWMICmdlet = @{ Enable = $true }

        # Disable style noise (keep this profile safety-focused)
        PSUseConsistentWhitespace   = @{ Enable = $false }
        PSUseConsistentIndentation  = @{ Enable = $false }

        # Often noisy in large corporate scripts; keep off unless you want it
        PSAvoidGlobalVars           = @{ Enable = $false }
    }
}
