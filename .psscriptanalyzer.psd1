@{
    # =========================================================================
    # Global behavior
    # =========================================================================
    EnableExit = $true  # makes Invoke-ScriptAnalyzer exit non-zero when it finds Error severity findings

    # =========================================================================
    # Baseline rule set (applies repo-wide)
    # =========================================================================
    IncludeRules = @(
        # Formatting
        'PSUseConsistentIndentation'
        'PSUseConsistentWhitespace'

        # Style / maintainability
        'PSAvoidUsingCmdletAliases'
        'PSUseDeclaredVarsMoreThanAssignments'
        'PSAvoidGlobalVars'

        # Security / safety
        'PSAvoidUsingWriteHost'
        'PSAvoidUsingInvokeExpression'
        'PSAvoidUsingEmptyCatchBlock'

        # Correctness for state-changing commands
        'PSUseShouldProcessForStateChangingFunctions'
    )

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
        PSAvoidUsingCmdletAliases = @{ Enable = $true }
        PSUseDeclaredVarsMoreThanAssignments = @{ Enable = $true }
        PSAvoidGlobalVars = @{ Enable = $true }

        # -------------------------
        # Security / safety
        # -------------------------
        PSAvoidUsingWriteHost = @{ Enable = $true }
        PSAvoidUsingInvokeExpression = @{ Enable = $true }
        PSAvoidUsingEmptyCatchBlock = @{ Enable = $true }

        # -------------------------
        # Correctness
        # -------------------------
        PSUseShouldProcessForStateChangingFunctions = @{ Enable = $true }
    }

    # =========================================================================
    # Severity control (Error vs Warning)
    # =========================================================================
    RuleSeverity = @{
        # Formatting: warnings
        PSUseConsistentIndentation = 'Warning'
        PSUseConsistentWhitespace  = 'Warning'

        # Hygiene: warnings
        PSAvoidUsingCmdletAliases                 = 'Warning'
        PSUseDeclaredVarsMoreThanAssignments      = 'Warning'
        PSAvoidGlobalVars                         = 'Warning'
        PSAvoidUsingEmptyCatchBlock               = 'Warning'

        # Security: make IEX an Error
        PSAvoidUsingInvokeExpression              = 'Error'

        # Behavior: choose Warning (you can flip to Error later if you want)
        PSAvoidUsingWriteHost                     = 'Warning'

        # Best practice gate: Error
        PSUseShouldProcessForStateChangingFunctions = 'Error'
    }

    # =========================================================================
    # Path scoping (GUI-only suppressions, repo-wide scanning otherwise)
    # =========================================================================
    #
    # PSA still scans everything; these blocks only adjust rules for matching files.
    #
    # IMPORTANT: These regex paths assume Linux-style forward slashes (GitHub ubuntu runner).
    #
    Settings = @(
        # ---------------------------------------------------------------------
        # GUI scripts: suppress console-focused or noisy rules
        # ---------------------------------------------------------------------
        @{
            Include = @(
                # SysAdmin tools with GUI / WinForms naming
                '^SysAdmin-Tools/.+/(.+GUI.+|.+WinForms.+|.+Form.+)\.ps1$',
                '^SysAdmin-Tools/.+/(.+GUI.+|.+WinForms.+|.+Form.+)\.psm1$',

                # Core library GUI helpers / launchers (adjust if needed)
                '^Core-ScriptLibrary/.+/(.+GUI.+|.+WinForms.+|.+Form.+)\.ps1$',
                '^Core-ScriptLibrary/.+/(.+GUI.+|.+WinForms.+|.+Form.+)\.psm1$',

                # ITSM GUI scripts
                '^ITSM-Templates-(WKS|SVR)/.+/(.+GUI.+|.+WinForms.+|.+Form.+)\.ps1$',
                '^ITSM-Templates-(WKS|SVR)/.+/(.+GUI.+|.+WinForms.+|.+Form.+)\.psm1$',

                # ProSuite Hub launchers often are UI-ish
                '^ProSuite-Hub/.+/(.+GUI.+|.+WinForms.+|.+Form.+|.+Launcher.+)\.ps1$',
                '^ProSuite-Hub/.+/(.+GUI.+|.+WinForms.+|.+Form.+|.+Launcher.+)\.psm1$'
            )

            # In GUI tools, console output rules can be counterproductive.
            ExcludeRules = @(
                'PSAvoidUsingWriteHost'
            )

            # Optionally relax ShouldProcess for GUI-only wrappers (uncomment if needed)
            # ExcludeRules = @('PSAvoidUsingWriteHost','PSUseShouldProcessForStateChangingFunctions')
        }

        # ---------------------------------------------------------------------
        # ProSuite-Hub: often orchestration; keep strict but practical
        # ---------------------------------------------------------------------
        @{
            Include = @('^ProSuite-Hub/')

            # Keep full baseline rules; just adjust severity if desired
            RuleSeverity = @{
                PSAvoidUsingWriteHost = 'Warning'
            }
        }
    )
}
