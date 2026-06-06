param()

. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "status"

$config = Get-HomelabConfig
$ollamaPath = Get-OllamaPath

$ollamaState = if (Test-OllamaReady -OllamaPath $ollamaPath) { "ready" } else { "not responding" }
$dockerDaemonState = if (Test-DockerDaemonReady) { "ready" } else { "not running" }
$openWebUiHealth = if ($dockerDaemonState -eq "ready") {
    Get-OpenWebUiHealth -Config $config
}
else {
    "daemon-unavailable"
}
$localUrl = "http://127.0.0.1:$($config.openwebui_port)"
$httpStatus = Test-HttpEndpoint -Url $localUrl -TimeoutSeconds 5
$installedModels = @()
$tailscaleNodeInfo = $null
$tailscaleServeState = $null
$tailscaleError = $null

if ($ollamaState -eq "ready") {
    $installedModels = Get-InstalledOllamaModels -OllamaPath $ollamaPath
}

try {
    $tailscaleNodeInfo = Get-TailscaleNodeInfo
    $tailscaleServeState = Get-TailscaleServeState -Config $config
}
catch {
    $tailscaleError = $_.Exception.Message
}

Write-Log "Hostname: $($config.hostname)" "INFO"
Write-Log "Open WebUI port: $($config.openwebui_port)" "INFO"
Write-Log "Ollama: $ollamaState" "INFO"
Write-Log "Docker daemon: $dockerDaemonState" "INFO"
Write-Log "Open WebUI container: $openWebUiHealth" "INFO"

if ($httpStatus.Ok) {
    Write-Log "Open WebUI URL: $localUrl (HTTP $($httpStatus.StatusCode))" "OK"
}
else {
    Write-Log "Open WebUI URL: $localUrl (unreachable)" "WARN"
}

if ($tailscaleNodeInfo) {
    Write-Log "Tailscale HTTPS URL: $($tailscaleNodeInfo.HttpsUrl)" "INFO"

    if (-not $tailscaleNodeInfo.MagicDnsEnabled) {
        Write-Log "Tailscale MagicDNS is not enabled for this tailnet." "WARN"
    }
    elseif (-not $tailscaleNodeInfo.HttpsCertificatesEnabled) {
        Write-Log "Tailscale HTTPS certificates are not enabled for this tailnet." "WARN"
    }
    elseif ($tailscaleServeState -and $tailscaleServeState.IsConfiguredExpected) {
        Write-Log "Tailscale Serve: configured for $($tailscaleServeState.ExpectedProxyTarget)" "OK"
    }
    elseif ($tailscaleServeState -and $tailscaleServeState.HasAnyConfiguration) {
        Write-Log "Tailscale Serve: configured, but not for this repo target" "WARN"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($tailscaleError)) {
        Write-Log "Tailscale Serve status unavailable: $tailscaleError" "WARN"
    }
    else {
        Write-Log "Tailscale Serve: not configured for Open WebUI" "WARN"
    }
}
else {
    Write-Log "Tailscale status unavailable: $tailscaleError" "WARN"
}

if ($installedModels.Count -gt 0) {
    Write-Log "Installed models: $($installedModels -join ', ')" "INFO"
}
