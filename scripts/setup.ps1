param(
    [switch]$RefreshModels
)

. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "setup"

$config = Get-HomelabConfig
$models = Get-ConfiguredModels

Write-Log "Checking Ollama..." "STEP"
Write-Log (Get-OllamaVersion -Config $config) "OK"

Write-Log "Checking Docker..." "STEP"
Write-Log (Get-HomelabCommandSpecVersion -CommandSpec (Get-DockerCommandSpec -Config $config)) "OK"

Write-Log "Checking Tailscale..." "STEP"
$tailscalePath = Get-TailscalePath
Write-Log (Get-CommandVersion -CommandPath $tailscalePath) "OK"

Write-Log "Validating Tailscale HTTPS prerequisites..." "STEP"
$tailscaleNodeInfo = Assert-TailscaleServePrerequisites
Write-Log "Tailscale HTTPS URL: $($tailscaleNodeInfo.HttpsUrl)" "OK"

Write-Log "Validating Docker Compose configuration..." "STEP"
Test-ComposeConfiguration -Config $config
Write-Log "Docker Compose configuration is valid." "OK"

Write-Log "Ensuring container runtime is available..." "STEP"
Start-DockerBackend -Config $config

Stop-LegacyWindowsDockerContainers -Config $config
Repair-WslComposeContainersIfNeeded -Config $config

if ($config.tts_enabled) {
    Write-Log "Ensuring local TTS image is available..." "STEP"
    [void](Invoke-DockerCompose -Config $config -Arguments @("pull", "openedai-speech") -RequireDaemon)
    Write-Log "Local TTS image is ready." "OK"
}

Write-Log "Ensuring Ollama is running..." "STEP"
Start-Ollama -Config $config
Wait-ForOllamaReady -Config $config
Write-Log "Ollama is ready." "OK"

Write-Log "Getting installed models..." "STEP"
$installedModels = Get-InstalledOllamaModels -Config $config

foreach ($model in $models) {
    $isInstalled = $model -in $installedModels

    if ($isInstalled -and -not $RefreshModels) {
        Write-Log "$model already installed" "OK"
        continue
    }

    if ($isInstalled -and $RefreshModels) {
        Write-Log "Refreshing $model" "STEP"
    }
    else {
        Write-Log "Pulling $model" "STEP"
    }

    $pullResult = Invoke-HomelabCommandSpec -CommandSpec (Get-OllamaCommandSpec -Config $config) -Arguments @("pull", $model)

    if ($pullResult.ExitCode -ne 0) {
        $message = ($pullResult.StdErr + [Environment]::NewLine + $pullResult.StdOut).Trim()
        throw $message
    }

    Write-Log "$model is ready." "OK"
}

$installedModels = Get-InstalledOllamaModels -Config $config
Assert-ConfiguredModelsInstalled -ConfiguredModels $models -InstalledModels $installedModels

if ($config.tts_enabled) {
    $ttsWasRunning = (Get-TtsHealth -Config $config) -in @("healthy", "running")

    try {
        Write-Log "Starting local TTS service for warmup..." "STEP"
        [void](Invoke-DockerCompose -Config $config -Arguments @("up", "-d", "openedai-speech") -RequireDaemon)
        Wait-ForTtsService -Config $config
        Write-Log "Local TTS service is ready." "OK"

        $ttsUrl = "http://127.0.0.1:$($config.tts_port)/v1/audio/speech"

        Write-Log "Preloading default voice $($config.tts_default_voice)..." "STEP"
        $defaultVoiceCheck = Test-TtsSpeechSynthesis -Url $ttsUrl -Voice $config.tts_default_voice -InputText "Bonjour depuis Homelab AI." -Model $config.tts_model

        if (-not $defaultVoiceCheck.Ok) {
            throw "Failed to warm default TTS voice '$($config.tts_default_voice)'. $($defaultVoiceCheck.Error)"
        }

        Write-Log "Default TTS voice is ready." "OK"

        Write-Log "Preloading fallback voice $($config.tts_fallback_voice)..." "STEP"
        $fallbackVoiceCheck = Test-TtsSpeechSynthesis -Url $ttsUrl -Voice $config.tts_fallback_voice -InputText "Hello from Homelab AI." -Model $config.tts_model

        if (-not $fallbackVoiceCheck.Ok) {
            throw "Failed to warm fallback TTS voice '$($config.tts_fallback_voice)'. $($fallbackVoiceCheck.Error)"
        }

        Write-Log "Fallback TTS voice is ready." "OK"
    }
    finally {
        if (-not $ttsWasRunning) {
            try {
                [void](Invoke-DockerCompose -Config $config -Arguments @("stop", "openedai-speech") -RequireDaemon)
            }
            catch {
                Write-Log "Local TTS stop after warmup skipped: $($_.Exception.Message)" "WARN"
            }
        }
    }
}

$openWebUiWasRunning = (Get-OpenWebUiHealth -Config $config) -in @("healthy", "running")
$openWebUiStartedForSetup = $false

try {
    if (-not $openWebUiWasRunning) {
        Write-Log "Starting Open WebUI for local Whisper warmup..." "STEP"
        [void](Invoke-DockerCompose -Config $config -Arguments @("up", "-d", "open-webui") -RequireDaemon)
        Wait-ForOpenWebUi -Config $config
        $openWebUiStartedForSetup = $true
        Write-Log "Open WebUI is ready for setup tasks." "OK"
    }

    Write-Log "Preloading local Whisper model $($config.stt_model)..." "STEP"
    $whisperState = Ensure-OpenWebUiWhisperModelCached -Config $config

    if ($whisperState.downloaded) {
        Write-Log "Local Whisper model was downloaded and cached for offline STT." "OK"
    }
    else {
        Write-Log "Local Whisper model is already cached for offline STT." "OK"
    }

    Write-Log "Syncing persisted Open WebUI audio and voice settings..." "STEP"
    Ensure-OpenWebUiPersistedConfig -Config $config
    Ensure-OpenWebUiRuntimePatch -Config $config
    [void](Clear-OpenWebUiSpeechCache -Config $config)
    [void](Invoke-DockerCompose -Config $config -Arguments @("restart", "open-webui") -RequireDaemon)
    Wait-ForOpenWebUi -Config $config
    Write-Log "Persisted Open WebUI audio settings and runtime voice-camera patch are aligned." "OK"
}
finally {
    if ($openWebUiStartedForSetup) {
        try {
            [void](Invoke-DockerCompose -Config $config -Arguments @("stop", "open-webui") -RequireDaemon)
        }
        catch {
            Write-Log "Open WebUI stop after Whisper warmup skipped: $($_.Exception.Message)" "WARN"
        }
    }
}

Write-Log "Setup completed." "OK"
