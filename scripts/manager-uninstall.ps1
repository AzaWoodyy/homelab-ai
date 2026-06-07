param(
    [switch]$KeepRunning
)

. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "manager-uninstall"

Write-Log "Removing Homelab manager scheduled task..." "STEP"
Unregister-HomelabManagerScheduledTask
Write-Log "Homelab manager scheduled task removed." "OK"

if (-not $KeepRunning) {
    & (Join-Path $PSScriptRoot "manager-stop.ps1")
}
