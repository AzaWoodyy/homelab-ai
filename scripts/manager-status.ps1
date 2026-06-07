param()

. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "manager-status"

$config = Get-HomelabConfig
$lockInfo = Get-HomelabManagerLockInfo
$pendingApply = Get-HomelabManagerPendingApplyState
$currentJob = Get-HomelabManagerCurrentJob
$latestJob = Get-HomelabManagerLastJob
$localUrl = Get-HomelabManagerLocalUrl -Config $config
$localStatus = Test-HttpEndpoint -Url $localUrl -TimeoutSeconds 5

Write-Log "Manager local URL: $localUrl" "INFO"
Write-Log "Manager scheduled task registered: $(Test-HomelabManagerTaskRegistered)" "INFO"

if ($null -ne $lockInfo) {
    Write-Log "Manager PID: $($lockInfo.pid)" "INFO"
    Write-Log "Manager started at: $($lockInfo.started_at)" "INFO"
}
else {
    Write-Log "Manager process: not running" "WARN"
}

if ($localStatus.Ok) {
    Write-Log "Manager HTTP endpoint reachable (HTTP $($localStatus.StatusCode))." "OK"
}
else {
    Write-Log "Manager HTTP endpoint is not reachable." "WARN"
}

try {
    $nodeInfo = Get-TailscaleNodeInfo
    $managementServeState = Get-TailscaleManagementServeState -Config $config
    Write-Log "Manager remote URL: $(Get-HomelabManagerRemoteUrl -Config $config -NodeInfo $nodeInfo)" "INFO"

    if ($managementServeState.IsConfiguredExpected) {
        Write-Log "Manager Tailscale Serve mapping is configured." "OK"
    }
    else {
        Write-Log "Manager Tailscale Serve mapping is not configured." "WARN"
    }
}
catch {
    Write-Log "Manager Tailscale status unavailable: $($_.Exception.Message)" "WARN"
}

if ($null -ne $pendingApply) {
    Write-Log "Pending apply actions: $([string]::Join(', ', @($pendingApply.remaining_actions)))" "WARN"
}

if ($null -ne $currentJob) {
    Write-Log "Current job: $($currentJob.action) [$($currentJob.status)]" "INFO"
}
elseif ($null -ne $latestJob) {
    Write-Log "Latest job: $($latestJob.action) [$($latestJob.status)]" "INFO"
}
