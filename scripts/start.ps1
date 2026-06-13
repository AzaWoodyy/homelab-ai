. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "start"

$config = Get-HomelabConfig

Write-Log "Ensuring container runtime is available..." "STEP"
Start-DockerBackend -Config $config

Write-Log "Starting Ollama..." "STEP"
Start-Ollama -Config $config
Wait-ForOllamaReady -Config $config
Write-Log "Ollama is ready." "OK"

Write-Log "Validating Docker Compose configuration..." "STEP"
Test-ComposeConfiguration -Config $config
Write-Log "Docker Compose configuration is valid." "OK"

Stop-LegacyWindowsDockerContainers -Config $config

Write-Log "Starting Open WebUI..." "STEP"
[void](Invoke-DockerCompose -Config $config -Arguments @("up", "-d") -RequireDaemon)
Repair-WslComposeContainersIfNeeded -Config $config

if ($config.tts_enabled) {
    Write-Log "Waiting for local TTS service..." "STEP"
    Wait-ForTtsService -Config $config
    Write-Log "Local TTS service is ready." "OK"
}

Write-Log "Waiting for Open WebUI..." "STEP"
Wait-ForOpenWebUi -Config $config

Write-Log "Validating local Whisper cache..." "STEP"
[void](Assert-OpenWebUiWhisperModelCached -Config $config)
Write-Log "Local Whisper cache is ready for offline STT." "OK"

Write-Log "Syncing persisted Open WebUI audio and voice settings..." "STEP"
Ensure-OpenWebUiPersistedConfig -Config $config
Ensure-OpenWebUiRuntimePatch -Config $config
[void](Clear-OpenWebUiSpeechCache -Config $config)
[void](Invoke-DockerCompose -Config $config -Arguments @("restart", "open-webui") -RequireDaemon)
Wait-ForOpenWebUi -Config $config
Assert-OpenWebUiCanProxyTts -Config $config
Write-Log "Persisted Open WebUI audio settings and runtime voice-camera patch are aligned." "OK"

$localUrl = "http://localhost:$($config.openwebui_port)"
$ttsUrl = "http://127.0.0.1:$($config.tts_port)"

Write-Log "Configuring Tailscale HTTPS..." "STEP"
$tailscaleNodeInfo = Enable-TailscaleOpenWebUiHttps -Config $config

Write-Log "Open WebUI remote URL: $($tailscaleNodeInfo.HttpsUrl)" "OK"
Write-Log "Open WebUI local URL: $localUrl" "INFO"
if ($config.tts_enabled) {
    Write-Log "Local TTS URL: $ttsUrl" "INFO"
}
Write-Log "Recommended voice/camera model: $($config.voice_vision_model) (fallback: $($config.voice_vision_fallback_model))" "INFO"
