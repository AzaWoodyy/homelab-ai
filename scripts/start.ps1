$ErrorActionPreference = "Stop"

$root = Split-Path $PSScriptRoot -Parent
$composePath = Join-Path $root "docker\compose.yml"

function Get-OllamaPath {
    $command = Get-Command "ollama" -ErrorAction SilentlyContinue

    if ($command) {
        return $command.Source
    }

    $candidatePaths = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"),
        (Join-Path $env:ProgramFiles "Ollama\ollama.exe")
    )

    foreach ($candidatePath in $candidatePaths) {
        if (Test-Path $candidatePath) {
            return $candidatePath
        }
    }

    throw "Ollama executable not found. Install Ollama or add ollama.exe to PATH."
}

$ollamaPath = Get-OllamaPath

Write-Host "Starting Ollama..."

$ollamaService = Get-Service -Name "Ollama" -ErrorAction SilentlyContinue

if ($ollamaService) {
    if ($ollamaService.Status -ne "Running") {
        Start-Service -Name "Ollama"
    }
}
else {
    try {
        & $ollamaPath list | Out-Null
        Write-Host "[OK] Ollama is already running"
    }
    catch {
        Start-Process -FilePath $ollamaPath -ArgumentList "serve" -WindowStyle Hidden
    }
}

Write-Host "Waiting for Ollama..."

$ollamaReady = $false

for ($i = 0; $i -lt 20; $i++) {
    try {
        & $ollamaPath list | Out-Null
        $ollamaReady = $true
        break
    }
    catch {
        Start-Sleep -Seconds 1
    }
}

if (-not $ollamaReady) {
    throw "Ollama did not become ready."
}

Write-Host "Starting Open WebUI..."

docker compose -f $composePath up -d

Write-Host "Done."
