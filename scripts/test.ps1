param()

. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "test"

$failures = New-Object System.Collections.Generic.List[string]

function New-SkippedCheckResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Reason
    )

    return [pscustomobject]@{
        Skipped = $true
        Detail  = $Reason
    }
}

function Invoke-Check {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock
    )

    Write-Log $Name "STEP"

    try {
        $detail = & $ScriptBlock

        if ($detail -is [pscustomobject] -and
            $detail.PSObject.Properties.Name -contains "Skipped" -and
            $detail.Skipped) {
            Write-Log "$Name skipped: $($detail.Detail)" "WARN"
            return
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$detail)) {
            Write-Log $detail "OK"
        }
        else {
            Write-Log "$Name passed." "OK"
        }
    }
    catch {
        $message = $_.Exception.Message
        $failures.Add("${Name}: $message")
        Write-Log "$Name failed: $message" "ERROR"
    }
}

$config = $null
$models = $null
$ollamaPath = $null
$dockerPath = $null
$dockerDaemonReady = $false
$tailscaleNodeInfo = $null
$ttsUrl = $null

Invoke-Check -Name "Load homelab config" -ScriptBlock {
    $script:config = Get-HomelabConfig
    "Hostname: $($script:config.hostname), Open WebUI port: $($script:config.openwebui_port)"
}

Invoke-Check -Name "Load model config" -ScriptBlock {
    $script:models = Get-ConfiguredModels
    "Configured models: $($script:models -join ', ')"
}

Invoke-Check -Name "Validate Ollama CLI" -ScriptBlock {
    $script:ollamaPath = Get-OllamaPath
    Get-CommandVersion -CommandPath $script:ollamaPath
}

Invoke-Check -Name "Validate Docker CLI" -ScriptBlock {
    $script:dockerPath = Get-DockerPath
    Get-CommandVersion -CommandPath $script:dockerPath
}

Invoke-Check -Name "Validate Tailscale CLI" -ScriptBlock {
    $tailscalePath = Get-TailscalePath
    Get-CommandVersion -CommandPath $tailscalePath
}

Invoke-Check -Name "Validate Tailscale HTTPS prerequisites" -ScriptBlock {
    $script:tailscaleNodeInfo = Assert-TailscaleServePrerequisites
    "Tailscale HTTPS URL: $($script:tailscaleNodeInfo.HttpsUrl)"
}

Invoke-Check -Name "Validate Docker daemon" -ScriptBlock {
    Assert-DockerDaemonReady
    $script:dockerDaemonReady = $true
    "Docker daemon is responding."
}

Invoke-Check -Name "Validate Docker Compose config" -ScriptBlock {
    if (-not $script:dockerDaemonReady) {
        return New-SkippedCheckResult -Reason "Docker daemon is not running."
    }

    Test-ComposeConfiguration -Config $script:config
    "Compose config rendered successfully."
}

Invoke-Check -Name "Validate external TTS configuration" -ScriptBlock {
    if (-not $script:config.tts_enabled) {
        return New-SkippedCheckResult -Reason "Local TTS is disabled in config."
    }

    $renderedConfig = Get-ComposeRenderedConfig -Config $script:config

    if ($renderedConfig -notmatch "AUDIO_TTS_ENGINE:\s+openai") {
        throw "Open WebUI is not configured to use the OpenAI-compatible TTS engine."
    }

    if ($renderedConfig -notmatch [regex]::Escape("AUDIO_TTS_OPENAI_API_BASE_URL: http://$($script:config.tts_container_name):8000/v1")) {
        throw "Open WebUI is not configured to use the openedai-speech service URL."
    }

    if ($renderedConfig -match "AUDIO_TTS_ENGINE:\s+transformers") {
        throw "Open WebUI is still configured to use local transformers TTS."
    }

    if ($renderedConfig -notmatch [regex]::Escape("WHISPER_MODEL: $($script:config.stt_model)")) {
        throw "Open WebUI is not configured to use Whisper model '$($script:config.stt_model)'."
    }

    if ($renderedConfig -notmatch [regex]::Escape("WHISPER_MODEL_AUTO_UPDATE: `"$($script:config.stt_auto_update.ToString().ToLowerInvariant())`"")) {
        throw "Open WebUI Whisper auto-update config is not aligned."
    }

    "Open WebUI is configured to use the external local TTS service and local STT model."
}

Invoke-Check -Name "Validate persisted Open WebUI audio config" -ScriptBlock {
    if (-not $script:dockerDaemonReady) {
        return New-SkippedCheckResult -Reason "Docker daemon is not running."
    }

    $health = Get-OpenWebUiHealth -Config $script:config

    if ($health -ne "healthy" -and $health -ne "running") {
        return New-SkippedCheckResult -Reason "Open WebUI is not running."
    }

    $persistedConfig = Get-OpenWebUiPersistedConfigJson -Config $script:config | ConvertFrom-Json

    if ($persistedConfig.audio.tts.engine -ne "openai") {
        throw "Persisted Open WebUI TTS engine is '$($persistedConfig.audio.tts.engine)' instead of 'openai'."
    }

    if ($persistedConfig.audio.tts.voice -ne $script:config.tts_default_voice) {
        throw "Persisted Open WebUI TTS voice is '$($persistedConfig.audio.tts.voice)' instead of '$($script:config.tts_default_voice)'."
    }

    if ($persistedConfig.audio.tts.openai.api_base_url -ne "http://$($script:config.tts_container_name):8000/v1") {
        throw "Persisted Open WebUI TTS API base URL is '$($persistedConfig.audio.tts.openai.api_base_url)'."
    }

    if ($persistedConfig.audio.stt.whisper_model -ne $script:config.stt_model) {
        throw "Persisted Open WebUI Whisper model is '$($persistedConfig.audio.stt.whisper_model)' instead of '$($script:config.stt_model)'."
    }

    "Persisted Open WebUI audio config is aligned."
}

Invoke-Check -Name "Validate local Whisper cache" -ScriptBlock {
    if (-not $script:dockerDaemonReady) {
        return New-SkippedCheckResult -Reason "Docker daemon is not running."
    }

    $health = Get-OpenWebUiHealth -Config $script:config

    if ($health -ne "healthy" -and $health -ne "running") {
        return New-SkippedCheckResult -Reason "Open WebUI is not running."
    }

    $cacheState = Get-OpenWebUiWhisperCacheState -Config $script:config

    if (-not $cacheState.cached) {
        throw "Whisper model '$($script:config.stt_model)' is not cached locally. $($cacheState.local_error)"
    }

    "Whisper model '$($script:config.stt_model)' is cached for offline STT."
}

Invoke-Check -Name "Validate Open WebUI voice-camera runtime patch" -ScriptBlock {
    if (-not $script:dockerDaemonReady) {
        return New-SkippedCheckResult -Reason "Docker daemon is not running."
    }

    $health = Get-OpenWebUiHealth -Config $script:config

    if ($health -ne "healthy" -and $health -ne "running") {
        return New-SkippedCheckResult -Reason "Open WebUI is not running."
    }

    $patchState = Get-OpenWebUiRuntimePatchState -Config $script:config

    if ($patchState -ne "ollama-native-images") {
        throw "Open WebUI runtime patch state is '$patchState' instead of 'ollama-native-images'."
    }

    "Open WebUI Ollama-native voice-camera runtime patch is active."
}

Invoke-Check -Name "Validate Open WebUI Ollama native image replay" -ScriptBlock {
    if (-not $script:dockerDaemonReady) {
        return New-SkippedCheckResult -Reason "Docker daemon is not running."
    }

    $health = Get-OpenWebUiHealth -Config $script:config

    if ($health -ne "healthy" -and $health -ne "running") {
        return New-SkippedCheckResult -Reason "Open WebUI is not running."
    }

    $replay = Get-OpenWebUiOllamaNativeImageReplayResult -Config $script:config

    if ($replay.ExitCode -ne 0) {
        throw "Ollama native image replay failed."
    }

    if ($replay.user_message_count -ne 1) {
        throw "Expected exactly one user message in the replay payload, got $($replay.user_message_count)."
    }

    if ($replay.content -ne "vois-tu") {
        throw "Expected replay content 'vois-tu', got '$($replay.content)'."
    }

    if ($replay.images_count -lt 1) {
        throw "Expected at least one Ollama image payload in the replay."
    }

    if ($replay.first_image_is_url) {
        throw "Expected the first Ollama image payload to be base64 data, but it still looks like a URL."
    }

    if ($replay.first_image_length -le 1024) {
        throw "Expected a large base64 image payload, got only $($replay.first_image_length) bytes."
    }

    "Ollama native image replay passed ($($replay.first_image_length) bytes, prefix $($replay.first_image_prefix))."
}

Invoke-Check -Name "Validate Ollama runtime" -ScriptBlock {
    if (-not (Test-OllamaReady -OllamaPath $script:ollamaPath)) {
        throw "Ollama is not responding. Start Ollama first."
    }

    "Ollama is responding."
}

Invoke-Check -Name "Validate installed models" -ScriptBlock {
    $installedModels = Get-InstalledOllamaModels -OllamaPath $script:ollamaPath
    Assert-ConfiguredModelsInstalled -ConfiguredModels $script:models -InstalledModels $installedModels
    "All configured models are installed."
}

Invoke-Check -Name "Validate Open WebUI container" -ScriptBlock {
    if (-not $script:dockerDaemonReady) {
        return New-SkippedCheckResult -Reason "Docker daemon is not running."
    }

    $health = Get-OpenWebUiHealth -Config $script:config

    if ($health -eq "daemon-unavailable") {
        throw "Docker daemon is not running. Start Docker Desktop (or the Docker engine) first."
    }

    if ($health -eq "missing") {
        throw "Open WebUI container is not present. Run .\\scripts\\start.ps1 first."
    }

    if ($health -eq "stopped") {
        throw "Open WebUI container is stopped. Run .\\scripts\\start.ps1 first."
    }

    if ($health -ne "healthy" -and $health -ne "running") {
        throw "Open WebUI container health is '$health'."
    }

    "Open WebUI container health: $health"
}

Invoke-Check -Name "Validate local TTS container" -ScriptBlock {
    if (-not $script:config.tts_enabled) {
        return New-SkippedCheckResult -Reason "Local TTS is disabled in config."
    }

    if (-not $script:dockerDaemonReady) {
        return New-SkippedCheckResult -Reason "Docker daemon is not running."
    }

    $health = Get-TtsHealth -Config $script:config

    if ($health -eq "daemon-unavailable") {
        throw "Docker daemon is not running. Start Docker Desktop (or the Docker engine) first."
    }

    if ($health -eq "missing") {
        throw "Local TTS container is not present. Run .\\scripts\\start.ps1 first."
    }

    if ($health -eq "stopped") {
        throw "Local TTS container is stopped. Run .\\scripts\\start.ps1 first."
    }

    if ($health -ne "healthy" -and $health -ne "running") {
        throw "Local TTS container health is '$health'."
    }

    "Local TTS container health: $health"
}

Invoke-Check -Name "Validate Open WebUI HTTP endpoint" -ScriptBlock {
    if (-not $script:dockerDaemonReady) {
        return New-SkippedCheckResult -Reason "Docker daemon is not running."
    }

    $url = "http://127.0.0.1:$($script:config.openwebui_port)"
    $response = Test-HttpEndpoint -Url $url -TimeoutSeconds 15

    if (-not $response.Ok) {
        throw "Open WebUI did not return a healthy HTTP response at $url."
    }

    $script:ttsUrl = "http://127.0.0.1:$($script:config.tts_port)/v1/audio/speech"
    "Open WebUI is reachable at $url (HTTP $($response.StatusCode))."
}

Invoke-Check -Name "Validate local TTS HTTP endpoint" -ScriptBlock {
    if (-not $script:config.tts_enabled) {
        return New-SkippedCheckResult -Reason "Local TTS is disabled in config."
    }

    if (-not $script:dockerDaemonReady) {
        return New-SkippedCheckResult -Reason "Docker daemon is not running."
    }

    $url = "http://127.0.0.1:$($script:config.tts_port)/docs"
    $response = Test-HttpEndpoint -Url $url -TimeoutSeconds 15

    if (-not $response.Ok) {
        throw "Local TTS did not return a healthy HTTP response at $url."
    }

    $script:ttsUrl = "http://127.0.0.1:$($script:config.tts_port)/v1/audio/speech"
    "Local TTS is reachable at $url (HTTP $($response.StatusCode))."
}

Invoke-Check -Name "Validate local TTS French synthesis" -ScriptBlock {
    if (-not $script:config.tts_enabled) {
        return New-SkippedCheckResult -Reason "Local TTS is disabled in config."
    }

    if ([string]::IsNullOrWhiteSpace([string]$script:ttsUrl)) {
        return New-SkippedCheckResult -Reason "Local TTS HTTP endpoint is not reachable."
    }

    $result = Test-TtsSpeechSynthesis -Url $script:ttsUrl -Voice $script:config.tts_default_voice -InputText "Bonjour depuis Homelab AI $([guid]::NewGuid())." -Model $script:config.tts_model

    if (-not $result.Ok) {
        throw "French synthesis failed. $($result.Error)"
    }

    "French TTS synthesis passed with $($script:config.tts_default_voice)."
}

Invoke-Check -Name "Validate local TTS English synthesis" -ScriptBlock {
    if (-not $script:config.tts_enabled) {
        return New-SkippedCheckResult -Reason "Local TTS is disabled in config."
    }

    if ([string]::IsNullOrWhiteSpace([string]$script:ttsUrl)) {
        return New-SkippedCheckResult -Reason "Local TTS HTTP endpoint is not reachable."
    }

    $result = Test-TtsSpeechSynthesis -Url $script:ttsUrl -Voice $script:config.tts_fallback_voice -InputText "Hello from Homelab AI $([guid]::NewGuid())." -Model $script:config.tts_model

    if (-not $result.Ok) {
        throw "English synthesis failed. $($result.Error)"
    }

    "English TTS synthesis passed with $($script:config.tts_fallback_voice)."
}

Invoke-Check -Name "Validate local TTS OpenAI voice alias synthesis" -ScriptBlock {
    if (-not $script:config.tts_enabled) {
        return New-SkippedCheckResult -Reason "Local TTS is disabled in config."
    }

    if ([string]::IsNullOrWhiteSpace([string]$script:ttsUrl)) {
        return New-SkippedCheckResult -Reason "Local TTS HTTP endpoint is not reachable."
    }

    $result = Test-TtsSpeechSynthesis -Url $script:ttsUrl -Voice "alloy" -InputText "Bonjour depuis la voix alloy $([guid]::NewGuid())." -Model $script:config.tts_model

    if (-not $result.Ok) {
        throw "OpenAI voice alias synthesis failed. $($result.Error)"
    }

    "OpenAI voice alias synthesis passed with alloy."
}

Invoke-Check -Name "Validate Open WebUI local TTS proxy synthesis" -ScriptBlock {
    if (-not $script:config.tts_enabled) {
        return New-SkippedCheckResult -Reason "Local TTS is disabled in config."
    }

    if (-not $script:dockerDaemonReady) {
        return New-SkippedCheckResult -Reason "Docker daemon is not running."
    }

    $health = Get-OpenWebUiHealth -Config $script:config

    if ($health -ne "healthy" -and $health -ne "running") {
        return New-SkippedCheckResult -Reason "Open WebUI is not running."
    }

    $url = "http://127.0.0.1:$($script:config.openwebui_port)/api/v1/audio/speech"
    $result = Test-OpenWebUiTtsSpeechSynthesis -Config $script:config -Url $url -Voice $script:config.tts_default_voice -InputText "Bonjour depuis Open WebUI $([guid]::NewGuid())." -Model $script:config.tts_model

    if (-not $result.Ok) {
        throw "Open WebUI TTS proxy synthesis failed. Status=$($result.StatusCode), Content-Type=$($result.ContentType), Size=$($result.OutputSize). $($result.Error)"
    }

    "Open WebUI TTS proxy synthesis passed ($($result.ContentType), $($result.OutputSize) bytes)."
}

Invoke-Check -Name "Validate Tailscale Serve config" -ScriptBlock {
    if ($null -eq $script:tailscaleNodeInfo) {
        return New-SkippedCheckResult -Reason "Tailscale HTTPS prerequisites are not satisfied."
    }

    $serveState = Get-TailscaleServeState -Config $script:config

    if (-not $serveState.IsConfiguredExpected) {
        throw "Tailscale Serve is not configured for $($serveState.ExpectedProxyTarget)."
    }

    "Tailscale Serve is configured for $($script:tailscaleNodeInfo.HttpsUrl)."
}

Invoke-Check -Name "Validate Tailscale HTTPS endpoint" -ScriptBlock {
    if ($null -eq $script:tailscaleNodeInfo) {
        return New-SkippedCheckResult -Reason "Tailscale HTTPS prerequisites are not satisfied."
    }

    $url = $script:tailscaleNodeInfo.HttpsUrl
    $response = Test-HttpEndpoint -Url $url -TimeoutSeconds 15

    if (-not $response.Ok) {
        throw "Open WebUI did not return a healthy HTTPS response at $url."
    }

    "Open WebUI is reachable at $url (HTTP $($response.StatusCode))."
}

if ($failures.Count -gt 0) {
    Write-Log "Test run completed with $($failures.Count) failure(s)." "ERROR"
    $failures | ForEach-Object { Write-Log $_ "ERROR" }
    throw "Homelab validation failed."
}

Write-Log "All homelab validation checks passed." "OK"
