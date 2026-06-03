Write-Host "Starting Ollama..."

Start-Service Ollama

Write-Host "Starting Open WebUI..."

docker compose -f ../docker/docker-compose.yml up -d

Write-Host "Done."