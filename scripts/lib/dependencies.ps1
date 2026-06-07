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

    $candidatePaths = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidatePaths.Add((Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"))
    }

    foreach ($programFilesPath in @($env:ProgramFiles, $env:ProgramW6432)) {
        if (-not [string]::IsNullOrWhiteSpace($programFilesPath)) {
            $candidatePaths.Add((Join-Path $programFilesPath "Ollama\ollama.exe"))
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:SystemDrive)) {
        $usersRoot = Join-Path $env:SystemDrive "Users"

        if (Test-Path -LiteralPath $usersRoot) {
            foreach ($profileDirectory in (Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue)) {
                $candidatePaths.Add((Join-Path $profileDirectory.FullName "AppData\Local\Programs\Ollama\ollama.exe"))
            }
        }
    }

    foreach ($candidatePath in ($candidatePaths | Select-Object -Unique)) {
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
