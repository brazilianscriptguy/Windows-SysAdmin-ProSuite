@{
    # Enterprise runtime-safety profile.
    # Primary compatibility target: Windows PowerShell 5.1.
    # Security, reliability, operability, and safe-change controls only.

    IncludeDefaultRules = $false
    Severity = @('Error', 'Warning')

    IncludeRules = @(
        'PSAvoidUsingInvokeExpression',
        'PSAvoidUsingPlainTextForPassword',
        'PSAvoidUsingConvertToSecureStringWithPlainText',
        'PSAvoidUsingUsernameAndPasswordParams',
        'PSAvoidUsingEmptyCatchBlock',
        'PSAvoidUsingWriteHost',
        'PSAvoidUsingCmdletAliases',
        'PSUseShouldProcessForStateChangingFunctions',
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

        # Formatting is delegated to EditorConfig and dedicated formatters.
        PSUseConsistentWhitespace = @{ Enable = $false }
        PSUseConsistentIndentation = @{ Enable = $false }

        # Disabled to avoid excessive noise in established enterprise scripts.
        PSAvoidGlobalVars = @{ Enable = $false }
    }
}
