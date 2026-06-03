Write-Host "Stopping Open WebUI..."

docker compose -f ../docker/docker-compose.yml down

Write-Host "Stopping Ollama..."

Stop-Service Ollama

Write-Host "Done."