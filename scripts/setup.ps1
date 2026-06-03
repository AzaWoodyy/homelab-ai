Write-Host "Checking Ollama..."
ollama --version

Write-Host "Checking Docker..."
docker --version

$root = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $root "config\models.json"

if (-not (Test-Path $configPath)) {
    throw "Config file not found: $configPath"
}

$models = Get-Content $configPath | ConvertFrom-Json

Write-Host "Getting installed models..."

$installedModels = @()

try {
    $installedModels = (ollama list) |
        Select-Object -Skip 1 |
        ForEach-Object {
            ($_ -split '\s+')[0]
        }
}
catch {
    Write-Warning "Unable to retrieve installed models."
}

foreach ($model in $models.models) {

    if ($installedModels -contains $model) {
        Write-Host "[OK] $model already installed"
        continue
    }

    Write-Host "[PULL] $model"
    ollama pull $model
}

Write-Host "Setup completed."