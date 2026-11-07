# PSScriptAnalyzer settings, used by CI:
#   Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # A console and desktop tool: Write-Host is how it talks to people.
        'PSAvoidUsingWriteHost',
        # The internal helpers only change files the tool owns. The switches people type (-Setup, -Label, -Quit)
        # are the confirmation, so -WhatIf/-Confirm plumbing would add code without making anything safer.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
