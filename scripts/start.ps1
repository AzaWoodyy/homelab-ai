. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "start"

$config = Get-HomelabConfig
$ollamaPath = Get-OllamaPath
$tailscaleNodeInfo = Assert-TailscaleServePrerequisites

Write-Log "Starting Ollama..." "STEP"
Start-Ollama -Config $config -OllamaPath $ollamaPath
Wait-ForOllamaReady -OllamaPath $ollamaPath
Write-Log "Ollama is ready." "OK"

Write-Log "Validating Docker Compose configuration..." "STEP"
Test-ComposeConfiguration -Config $config
Write-Log "Docker Compose configuration is valid." "OK"

Write-Log "Starting Open WebUI..." "STEP"
[void](Invoke-DockerCompose -Config $config -Arguments @("up", "-d") -RequireDaemon)

Write-Log "Waiting for Open WebUI..." "STEP"
Wait-ForOpenWebUi -Config $config

$localUrl = "http://localhost:$($config.openwebui_port)"
$tailscaleUrl = $tailscaleNodeInfo.HttpsUrl

Write-Log "Configuring Tailscale HTTPS..." "STEP"
$tailscaleNodeInfo = Enable-TailscaleOpenWebUiHttps -Config $config

Write-Log "Open WebUI remote URL: $($tailscaleNodeInfo.HttpsUrl)" "OK"
Write-Log "Open WebUI local URL: $localUrl" "INFO"
