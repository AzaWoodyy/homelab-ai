param(
    [switch]$StartNow
)

. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "manager-install"

$config = Get-HomelabConfig
Assert-ManagementAdminSecretConfigured -Config $config

Write-Log "Registering Homelab manager scheduled task..." "STEP"
Register-HomelabManagerScheduledTask
Write-Log "Homelab manager scheduled task registered." "OK"

if ($StartNow) {
    Write-Log "Starting Homelab manager now..." "STEP"
    & (Join-Path $PSScriptRoot "manager-start.ps1")
}
