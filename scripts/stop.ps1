. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "stop"

$config = Get-HomelabConfig

Write-Log "Stopping Open WebUI..." "STEP"
try {
    [void](Invoke-DockerCompose -Config $config -Arguments @("stop") -RequireDaemon)
    Write-Log "Open WebUI stopped." "OK"
}
catch {
    Write-Log "Open WebUI stop skipped: $($_.Exception.Message)" "WARN"
}

Write-Log "Stopping Ollama..." "STEP"
Stop-Ollama -Config $config

Write-Log "Stop completed." "OK"
