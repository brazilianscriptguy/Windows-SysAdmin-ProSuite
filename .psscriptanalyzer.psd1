# .psscriptanalyzer.psd1
@{
    # IMPORTANT (PSScriptAnalyzer 1.24.0):
    # Valid top-level keys are:
    # CustomRulePath, ExcludeRules, IncludeRules, IncludeDefaultRules,
    # RecurseCustomRulePath, Rules, Severity

    IncludeDefaultRules = $true

    # Return these severities; your workflow should "gate" only on Error.
    Severity = @('Error','Warning','Information')

    # Optional: global exclusions (leave empty unless you truly never want a rule anywhere)
    ExcludeRules = @(
        # Example: 'PSAvoidUsingWriteHost'
    )

    # Corporate baseline (focused + stable)
    IncludeRules = @(
        'PSAvoidUsingCmdletAliases',
        'PSAvoidUsingWriteHost',
        'PSAvoidUsingInvokeExpression',
        'PSAvoidUsingEmptyCatchBlock',
        'PSAvoidGlobalVars',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseConsistentIndentation',
        'PSUseConsistentWhitespace'
    )

    Rules = @{
        PSUseConsistentIndentation = @{
            Enable              = $true
            Kind                = 'space'
            IndentationSize     = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
        }

        PSUseConsistentWhitespace = @{
            Enable          = $true
            CheckInnerBrace = $true
            CheckOpenBrace  = $true
            CheckOpenParen  = $true
            CheckOperator   = $true
            CheckSeparator  = $true
        }

        PSAvoidUsingWriteHost = @{
            Enable = $true
        }

        PSAvoidUsingCmdletAliases = @{
            Enable = $true
        }

        PSAvoidUsingInvokeExpression = @{
            Enable = $true
        }

        PSAvoidUsingEmptyCatchBlock = @{
            Enable = $true
        }

        PSAvoidGlobalVars = @{
            Enable = $true
        }

        PSUseDeclaredVarsMoreThanAssignments = @{
            Enable = $true
        }

        PSUseShouldProcessForStateChangingFunctions = @{
            Enable = $true
        }
    }
}
