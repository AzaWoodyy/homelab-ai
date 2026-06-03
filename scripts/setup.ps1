Write-Host "Checking Ollama..."

ollama --version

Write-Host "Checking Docker..."

docker --version

$models = Get-Content ../config/models.json | ConvertFrom-Json

foreach ($model in $models.models) {
    Write-Host "Pulling $model"
    ollama pull $model
}

Write-Host "Setup completed."