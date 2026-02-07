# .psscriptanalyzer.psd1
# VALID for PSScriptAnalyzer 1.24.0
# Notes:
# - No RuleSeverity (NOT supported by PSA 1.24.0 settings hashtable)
# - Repo-wide rules live here; “severity buckets” are enforced by your YAML (two-pass PSA run)
# - GUI-only suppressions and folder scoping are enforced by your YAML (post-filter), not here

@{
    # =========================================================================
    # What rules are active across the repo (all folders + subfolders)
    # =========================================================================
    IncludeRules = @(
        # --- Formatting (safe autofix) ---
        'PSUseConsistentIndentation'
        'PSUseConsistentWhitespace'

        # --- Style / maintainability ---
        'PSAvoidUsingCmdletAliases'
        'PSUseDeclaredVarsMoreThanAssignments'
        'PSAvoidGlobalVars'

        # --- Safety / security ---
        'PSAvoidUsingWriteHost'
        'PSAvoidUsingInvokeExpression'
        'PSAvoidUsingEmptyCatchBlock'

        # --- Correctness / state-changing ---
        'PSUseShouldProcessForStateChangingFunctions'
    )

    # =========================================================================
    # Rule configuration (only valid keys for PSA 1.24.0)
    # =========================================================================
    Rules = @{
        # -------------------------
        # Formatting config
        # -------------------------
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

        # -------------------------
        # Hygiene / maintainability
        # -------------------------
        PSAvoidUsingCmdletAliases = @{
            Enable = $true
        }

        PSUseDeclaredVarsMoreThanAssignments = @{
            Enable = $true
        }

        PSAvoidGlobalVars = @{
            Enable = $true
        }

        # -------------------------
        # Safety / security
        # -------------------------
        PSAvoidUsingWriteHost = @{
            Enable = $true
        }

        PSAvoidUsingInvokeExpression = @{
            Enable = $true
        }

        PSAvoidUsingEmptyCatchBlock = @{
            Enable = $true
        }

        # -------------------------
        # Correctness
        # -------------------------
        PSUseShouldProcessForStateChangingFunctions = @{
            Enable = $true
        }
    }

    # =========================================================================
    # Optional repo-wide Severity gate (supported key)
    # =========================================================================
    # This controls which severities PSA emits when *you* do not pass -Severity.
    # Your YAML already runs PSA in two passes (Error pass + Warning pass),
    # so this is mostly a safe default.
    Severity = @('Error','Warning')
}
