param()

. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "status"

$config = Get-HomelabConfig

$ollamaState = if (Test-OllamaReady -Config $config) { "ready" } else { "not responding" }
$dockerDaemonState = if (Test-DockerDaemonReady -Config $config) { "ready" } else { "not running" }
$openWebUiHealth = if ($dockerDaemonState -eq "ready") {
    Get-OpenWebUiHealth -Config $config
}
else {
    "daemon-unavailable"
}
$openWebUiRuntimePatchState = if ($dockerDaemonState -eq "ready" -and $openWebUiHealth -in @("healthy", "running")) {
    Get-OpenWebUiRuntimePatchState -Config $config
}
else {
    "unknown"
}
$openWebUiWhisperCacheState = if ($dockerDaemonState -eq "ready" -and $openWebUiHealth -in @("healthy", "running")) {
    Get-OpenWebUiWhisperCacheState -Config $config
}
else {
    $null
}
$ttsHealth = if ($config.tts_enabled -and $dockerDaemonState -eq "ready") {
    Get-TtsHealth -Config $config
}
elseif ($config.tts_enabled) {
    "daemon-unavailable"
}
else {
    "disabled"
}
$localUrl = "http://127.0.0.1:$($config.openwebui_port)"
$ttsUrl = "http://127.0.0.1:$($config.tts_port)"
$managerUrl = "http://127.0.0.1:$($config.management_port)"
$httpStatus = Test-HttpEndpoint -Url $localUrl -TimeoutSeconds 5
$managerStatus = Test-HttpEndpoint -Url $managerUrl -TimeoutSeconds 5
$ttsStatus = if ($config.tts_enabled) {
    Test-HttpEndpoint -Url "$ttsUrl/docs" -TimeoutSeconds 5
}
else {
    $null
}
$installedModels = @()
$tailscaleNodeInfo = $null
$tailscaleServeState = $null
$managementServeState = $null
$tailscaleError = $null
$managerLockInfo = Get-HomelabManagerLockInfo
$pendingApply = Get-HomelabManagerPendingApplyState
$currentManagerJob = Get-HomelabManagerCurrentJob
$latestManagerJob = Get-HomelabManagerLastJob
$hermesSummary = Get-HermesSummary -Config $config

if ($ollamaState -eq "ready") {
    $installedModels = Get-InstalledOllamaModels -Config $config
}

try {
    $tailscaleNodeInfo = Get-TailscaleNodeInfo
    $tailscaleServeState = Get-TailscaleServeState -Config $config
    $managementServeState = Get-TailscaleManagementServeState -Config $config
}
catch {
    $tailscaleError = $_.Exception.Message
}

Write-Log "Hostname: $($config.hostname)" "INFO"
Write-Log "Open WebUI port: $($config.openwebui_port)" "INFO"
Write-Log "Manager port: $($config.management_port)" "INFO"
Write-Log "Container backend: $($config.runtime_container_backend)" "INFO"
Write-Log "Ollama backend: $($config.runtime_ollama_backend)" "INFO"
if ((Test-HomelabContainerBackendWsl -Config $config) -or (Test-HomelabOllamaBackendWsl -Config $config)) {
    Write-Log "WSL distro: $($config.runtime_wsl_distro)" "INFO"
}
Write-Log "Ollama: $ollamaState" "INFO"
Write-Log "Docker daemon: $dockerDaemonState" "INFO"
$managerTaskQuery = Get-HomelabManagerTaskQuery
Write-Log "Manager user-logon task: $($managerTaskQuery.Exists -and $managerTaskQuery.IsExpectedRegistration)" "INFO"
if ($managerTaskQuery.Exists -and -not $managerTaskQuery.IsExpectedRegistration) {
    Write-Log "Manager task registration is present but not in the expected user-logon form (user=$($managerTaskQuery.UserId), expected=$($managerTaskQuery.ExpectedUserId))." "WARN"
}
Write-Log "Open WebUI container: $openWebUiHealth" "INFO"
Write-Log "Open WebUI voice-camera patch: $openWebUiRuntimePatchState" "INFO"
Write-Log "Open WebUI STT model: $($config.stt_model)" "INFO"
if ($null -ne $openWebUiWhisperCacheState) {
    $whisperCacheLabel = if ($openWebUiWhisperCacheState.cached) { "ready" } else { "missing" }
    Write-Log "Open WebUI STT cache: $whisperCacheLabel" "INFO"
}
if ($config.tts_enabled) {
    Write-Log "Local TTS container: $ttsHealth" "INFO"
}

if ($openWebUiHealth -eq "stopped") {
    Write-Log "Open WebUI is stopped; voice, camera, and speaker buttons cannot work until .\scripts\start.ps1 runs." "WARN"
}
elseif ($null -ne $openWebUiWhisperCacheState -and -not $openWebUiWhisperCacheState.cached) {
    Write-Log "Local Whisper cache is missing; microphone transcription will fail offline until .\scripts\setup.ps1 is run once with internet access." "WARN"
}

if ($ttsHealth -eq "stopped") {
    Write-Log "Local TTS is stopped; Open WebUI cannot synthesize speech until .\scripts\start.ps1 runs." "WARN"
}

if ($managerLockInfo) {
    Write-Log "Manager process: running (PID $($managerLockInfo.pid))" "OK"
}
else {
    Write-Log "Manager process: not running" "WARN"
}

if ($httpStatus.Ok) {
    Write-Log "Open WebUI URL: $localUrl (HTTP $($httpStatus.StatusCode))" "OK"
}
else {
    Write-Log "Open WebUI URL: $localUrl (unreachable)" "WARN"
}

if ($managerStatus.Ok) {
    Write-Log "Manager URL: $managerUrl (HTTP $($managerStatus.StatusCode))" "OK"
}
else {
    Write-Log "Manager URL: $managerUrl (unreachable)" "WARN"
}

if ($config.tts_enabled) {
    if ($ttsStatus.Ok) {
        Write-Log "Local TTS URL: $ttsUrl (HTTP $($ttsStatus.StatusCode))" "OK"
    }
    else {
        Write-Log "Local TTS URL: $ttsUrl (unreachable)" "WARN"
    }

    Write-Log "Local TTS voices: default=$($config.tts_default_voice), fallback=$($config.tts_fallback_voice)" "INFO"
}

Write-Log "Recommended voice/camera model: $($config.voice_vision_model)" "INFO"
Write-Log "Voice/camera fallback model: $($config.voice_vision_fallback_model)" "INFO"

if ($hermesSummary.enabled) {
    Write-Log "Hermes Agent: enabled, gateway=$(if ($hermesSummary.gateway.running) { 'running' } else { 'stopped' }), model=$($hermesSummary.model)" "INFO"

    if ($hermesSummary.cli_available) {
        Write-Log "Hermes CLI: $($hermesSummary.version)" "OK"
    }
    else {
        Write-Log "Hermes CLI: not found" "WARN"
    }

    if ($hermesSummary.api_server.enabled) {
        $apiState = if ($hermesSummary.api_server.reachable) { "reachable" } else { "unreachable" }
        Write-Log "Hermes API server: $($hermesSummary.api_server.local_url) ($apiState)" "INFO"
    }

    if (@($hermesSummary.missing_config).Count -gt 0) {
        Write-Log "Hermes missing config: $(@($hermesSummary.missing_config) -join ', ')" "WARN"
    }
}
else {
    Write-Log "Hermes Agent: disabled" "INFO"
}

if ($tailscaleNodeInfo) {
    Write-Log "Tailscale HTTPS URL: $($tailscaleNodeInfo.HttpsUrl)" "INFO"
    Write-Log "Manager remote URL: $(Get-HomelabManagerRemoteUrl -Config $config -NodeInfo $tailscaleNodeInfo)" "INFO"

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

    if ($managementServeState -and $managementServeState.IsConfiguredExpected) {
        Write-Log "Manager Tailscale Serve: configured for $($managementServeState.ExpectedProxyTarget)" "OK"
    }
    elseif ($managementServeState -and $managementServeState.HasAnyConfiguration) {
        Write-Log "Manager Tailscale Serve: configured, but not for this repo target" "WARN"
    }
    else {
        Write-Log "Manager Tailscale Serve: not configured for the manager" "WARN"
    }
}
else {
    Write-Log "Tailscale status unavailable: $tailscaleError" "WARN"
}

if ($installedModels.Count -gt 0) {
    Write-Log "Installed models: $($installedModels -join ', ')" "INFO"
}

if ($pendingApply) {
    Write-Log "Pending apply actions: $(@($pendingApply.remaining_actions) -join ', ')" "WARN"
}

if ($currentManagerJob) {
    Write-Log "Current manager job: $($currentManagerJob.action) [$($currentManagerJob.status)]" "INFO"
}
elseif ($latestManagerJob) {
    Write-Log "Latest manager job: $($latestManagerJob.action) [$($latestManagerJob.status)]" "INFO"
}
