# .psscriptanalyzer.psd1
@{
    # Reduce noise: only show Error + Warning by default
    IncludeDefaultRules = $true
    Severity            = @('Error','Warning')

    # Focused include list: high-signal rules
    IncludeRules = @(
        'PSAvoidUsingInvokeExpression',
        'PSAvoidUsingEmptyCatchBlock',
        'PSAvoidGlobalVars',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSAvoidUsingWriteHost',
        'PSAvoidUsingCmdletAliases',
        'PSUseConsistentIndentation',
        'PSUseConsistentWhitespace'
    )

    Rules = @{
        # --- High-signal rules kept as Warning/Error (default severities) ---
        PSAvoidUsingInvokeExpression = @{ Enable = $true }
        PSAvoidUsingEmptyCatchBlock  = @{ Enable = $true }
        PSAvoidGlobalVars            = @{ Enable = $true }
        PSUseShouldProcessForStateChangingFunctions = @{ Enable = $true }
        PSAvoidUsingWriteHost        = @{ Enable = $true }
        PSAvoidUsingCmdletAliases    = @{ Enable = $true }

        # --- Style rules: keep enabled but downgrade to Information (noise control) ---
        PSUseConsistentIndentation = @{
            Enable              = $true
            Severity            = 'Information'
            Kind                = 'space'
            IndentationSize     = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
        }

        PSUseConsistentWhitespace = @{
            Enable          = $true
            Severity        = 'Information'
            CheckInnerBrace = $true
            CheckOpenBrace  = $true
            CheckOpenParen  = $true
            CheckOperator   = $true
            CheckSeparator  = $true
        }
    }
}
