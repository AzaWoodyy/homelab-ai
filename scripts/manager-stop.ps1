param()

. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "manager-stop"

$config = Get-HomelabConfig

try {
    Disable-TailscaleManagementHttps -Config $config
    Write-Log "Homelab manager Tailscale HTTPS disabled." "OK"
}
catch {
    Write-Log "Homelab manager Tailscale HTTPS disable skipped: $($_.Exception.Message)" "WARN"
}

$lockInfo = Get-HomelabManagerLockInfo

if ($null -eq $lockInfo) {
    Write-Log "Homelab manager is not running." "INFO"
    Remove-HomelabManagerLockInfo
    return
}

Write-Log "Stopping Homelab manager process $($lockInfo.pid)..." "STEP"
Stop-HomelabManagerProcess -ProcessId ([int]$lockInfo.pid)
Start-Sleep -Seconds 2
Remove-HomelabManagerLockInfo
Write-Log "Homelab manager stopped." "OK"
