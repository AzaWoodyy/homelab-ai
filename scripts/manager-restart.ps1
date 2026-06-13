param()

. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "manager-restart"

Write-Log "Restarting Homelab manager..." "STEP"

& (Join-Path $PSScriptRoot "manager-stop.ps1")
& (Join-Path $PSScriptRoot "manager-start.ps1")

Write-Log "Homelab manager restart completed." "OK"
