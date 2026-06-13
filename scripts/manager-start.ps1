param()

. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "manager-start"

$config = Get-HomelabConfig
Assert-ManagementAdminSecretConfigured -Config $config

$lockInfo = Get-HomelabManagerLockInfo

if ($null -ne $lockInfo) {
    Write-Log "Homelab manager is already running with PID $($lockInfo.pid)." "INFO"
}
else {
    Write-Log "Starting Homelab manager..." "STEP"
    [void](Start-HomelabManagerDetached)
    Wait-ForHomelabManager -Config $config -TimeoutSeconds 20
    Write-Log "Homelab manager is reachable at $(Get-HomelabManagerLocalUrl -Config $config)." "OK"
}

try {
    $nodeInfo = Enable-TailscaleManagementHttps -Config $config
    Write-Log "Homelab manager remote URL: $(Get-HomelabManagerRemoteUrl -Config $config -NodeInfo $nodeInfo)" "OK"
}
catch {
    Write-Log "Homelab manager Tailscale HTTPS is not ready yet: $($_.Exception.Message) The background manager service will keep retrying." "WARN"
}
