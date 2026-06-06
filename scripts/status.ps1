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

if ($ollamaState -eq "ready") {
    $installedModels = Get-InstalledOllamaModels -OllamaPath $ollamaPath
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

if ($installedModels.Count -gt 0) {
    Write-Log "Installed models: $($installedModels -join ', ')" "INFO"
}
