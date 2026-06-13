param()

. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "manager-summary-refresh"
Invoke-HomelabManagerSummaryRefresh
