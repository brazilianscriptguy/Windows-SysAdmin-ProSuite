@{
    IncludeDefaultRules = $false
    Severity = @('Error','Warning')

    IncludeRules = @(
        'PSAvoidUsingInvokeExpression',
        'PSAvoidUsingEmptyCatchBlock',
        'PSAvoidUsingWriteHost',
        'PSAvoidUsingCmdletAliases',
        'PSUseShouldProcessForStateChangingFunctions'
    )

    Rules = @{
        PSAvoidUsingInvokeExpression = @{ Enable = $true }
        PSAvoidUsingEmptyCatchBlock  = @{ Enable = $true }
        PSAvoidUsingWriteHost        = @{ Enable = $true }
        PSAvoidUsingCmdletAliases    = @{ Enable = $true }

        # Noise disabled
        PSUseConsistentWhitespace    = @{ Enable = $false }
        PSUseConsistentIndentation   = @{ Enable = $false }
        PSAvoidGlobalVars            = @{ Enable = $false }
    }
}
