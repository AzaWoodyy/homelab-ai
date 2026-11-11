@{
    Severity     = @("Error", "Warning")

    # Style rules that do not fit an operator-facing script collection:
    # - interactive scripts intentionally print colored output with Write-Host;
    # - helper names favor readability over the approved-verb and singular-noun lists;
    # - ShouldProcess (-WhatIf) is not part of the scripts' contract;
    # - Write-Log is the repo's own logger and predates the built-in cmdlet.
    ExcludeRules = @(
        "PSAvoidUsingWriteHost",
        "PSUseApprovedVerbs",
        "PSUseSingularNouns",
        "PSUseShouldProcessForStateChangingFunctions",
        "PSAvoidOverwritingBuiltInCmdlets"
    )
}
