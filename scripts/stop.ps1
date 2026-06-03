$ErrorActionPreference = "Stop"

$root = Split-Path $PSScriptRoot -Parent
$composePath = Join-Path $root "docker\compose.yml"

Write-Host "Stopping Open WebUI..."

docker compose -f $composePath down

Write-Host "Stopping Ollama..."

$ollamaService = Get-Service -Name "Ollama" -ErrorAction SilentlyContinue

if ($ollamaService) {
    if ($ollamaService.Status -ne "Stopped") {
        Stop-Service -Name "Ollama"
    }
}
else {
    Stop-Process -Name "ollama" -Force -ErrorAction SilentlyContinue
}

Write-Host "Done."
