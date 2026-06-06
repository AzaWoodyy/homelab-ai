function Get-ComposePath {
    $composePath = Join-Path $script:HomelabRoot "docker\compose.yml"

    if (-not (Test-Path -LiteralPath $composePath)) {
        throw "Compose file not found: $composePath"
    }

    return $composePath
}

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
        if (Test-Path -LiteralPath $candidatePath) {
            return $candidatePath
        }
    }

    throw "Ollama executable not found. Install Ollama or add ollama.exe to PATH."
}

function Get-DockerPath {
    $command = Get-Command "docker" -ErrorAction SilentlyContinue

    if (-not $command) {
        throw "Docker CLI not found. Install Docker Desktop or add docker.exe to PATH."
    }

    return $command.Source
}
