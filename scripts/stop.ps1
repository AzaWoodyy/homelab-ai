. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "stop"

$config = Get-HomelabConfig

if ($config.hermes_enabled) {
    Write-Log "Stopping Hermes Agent gateway..." "STEP"
    Stop-HermesGateway -Config $config
}

Write-Log "Disabling Tailscale HTTPS..." "STEP"
try {
    Disable-TailscaleOpenWebUiHttps -Config $config
    Write-Log "Tailscale HTTPS disabled." "OK"
}
catch {
    Write-Log "Tailscale HTTPS disable skipped: $($_.Exception.Message)" "WARN"
}

Write-Log "Stopping Open WebUI..." "STEP"
try {
    [void](Invoke-DockerCompose -Config $config -Arguments @("stop") -RequireDaemon)
    Write-Log "Open WebUI and local TTS services stopped." "OK"
}
catch {
    Write-Log "Open WebUI and local TTS stop skipped: $($_.Exception.Message)" "WARN"
}

Write-Log "Stopping Ollama..." "STEP"
Stop-Ollama -Config $config

Write-Log "Stop completed." "OK"
