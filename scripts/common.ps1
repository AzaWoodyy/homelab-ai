Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:HomelabRoot = Split-Path $PSScriptRoot -Parent
$script:CurrentLogPath = $null

function Initialize-HomelabScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName
    )

    $logsPath = Join-Path $script:HomelabRoot "logs"

    if (-not (Test-Path -LiteralPath $logsPath)) {
        New-Item -ItemType Directory -Path $logsPath | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $script:CurrentLogPath = Join-Path $logsPath "$ScriptName-$timestamp.log"
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "STEP", "OK", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"

    $color = switch ($Level) {
        "STEP" { "Cyan" }
        "OK" { "Green" }
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
        default { "Gray" }
    }

    Write-Host $line -ForegroundColor $color

    if ($script:CurrentLogPath) {
        Add-Content -LiteralPath $script:CurrentLogPath -Value $line
    }
}

function Get-HomelabConfig {
    $configPath = Join-Path $script:HomelabRoot "config\homelab.json"

    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Config file not found: $configPath"
    }

    $rawConfig = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
    $hostname = [string]$rawConfig.hostname

    if ([string]::IsNullOrWhiteSpace($hostname)) {
        $hostname = "homelab-ai"
    }

    $port = 3000

    if ($null -ne $rawConfig.openwebui_port) {
        $port = [int]$rawConfig.openwebui_port
    }

    if ($port -lt 1 -or $port -gt 65535) {
        throw "openwebui_port must be between 1 and 65535."
    }

    return [pscustomobject]@{
        hostname                 = $hostname
        openwebui_port           = $port
        openwebui_container_name = "open-webui"
        ollama_service_name      = "Ollama"
        ollama_host              = "host.docker.internal"
        ollama_port              = 11434
    }
}

function Get-ConfiguredModels {
    $configPath = Join-Path $script:HomelabRoot "config\models.json"

    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Model config file not found: $configPath"
    }

    $rawConfig = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json

    if ($null -eq $rawConfig.models -or $rawConfig.models.Count -eq 0) {
        throw "config/models.json must contain at least one model."
    }

    $models = @()

    foreach ($model in $rawConfig.models) {
        $modelName = [string]$model

        if ([string]::IsNullOrWhiteSpace($modelName)) {
            throw "config/models.json contains an empty model entry."
        }

        $models += $modelName.Trim()
    }

    $duplicates = $models |
        Group-Object |
        Where-Object Count -gt 1 |
        Select-Object -ExpandProperty Name

    if ($duplicates) {
        throw "Duplicate models found in config/models.json: $($duplicates -join ', ')"
    }

    return $models
}

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

function Get-CommandVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandPath
    )

    $output = & $CommandPath --version 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw ($output | Out-String).Trim()
    }

    return ($output | Select-Object -First 1).ToString().Trim()
}

function Get-OllamaService {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return Get-Service -Name $Config.ollama_service_name -ErrorAction SilentlyContinue
}

function Test-OllamaReady {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OllamaPath
    )

    try {
        $output = & $OllamaPath list 2>&1
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

function Wait-ForOllamaReady {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OllamaPath,

        [int]$RetryCount = 20,

        [int]$DelaySeconds = 1
    )

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        if (Test-OllamaReady -OllamaPath $OllamaPath) {
            return
        }

        Start-Sleep -Seconds $DelaySeconds
    }

    throw "Ollama did not become ready after $RetryCount attempts."
}

function Start-Ollama {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$OllamaPath
    )

    $service = Get-OllamaService -Config $Config

    if ($service) {
        if ($service.Status -eq "Running") {
            Write-Log "Ollama service is already running." "OK"
            return
        }

        Start-Service -Name $Config.ollama_service_name
        Write-Log "Ollama service started." "OK"
        return
    }

    if (Test-OllamaReady -OllamaPath $OllamaPath) {
        Write-Log "Ollama is already running." "OK"
        return
    }

    Start-Process -FilePath $OllamaPath -ArgumentList "serve" -WindowStyle Hidden
    Write-Log "Started Ollama process." "OK"
}

function Stop-Ollama {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $service = Get-OllamaService -Config $Config

    if ($service) {
        if ($service.Status -eq "Stopped") {
            Write-Log "Ollama service is already stopped." "OK"
            return
        }

        Stop-Service -Name $Config.ollama_service_name
        Write-Log "Ollama service stopped." "OK"
        return
    }

    $processes = Get-Process -Name "ollama" -ErrorAction SilentlyContinue

    if (-not $processes) {
        Write-Log "No Ollama process found." "OK"
        return
    }

    $processes | Stop-Process -Force
    Write-Log "Stopped Ollama process." "OK"
}

function Get-InstalledOllamaModels {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OllamaPath
    )

    $output = & $OllamaPath list 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw ($output | Out-String).Trim()
    }

    return $output |
        Select-Object -Skip 1 |
        ForEach-Object { $_.ToString().Trim() } |
        Where-Object { $_ } |
        ForEach-Object { ($_ -split '\s+')[0] }
}

function Set-ComposeEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $env:OPENWEBUI_PORT = [string]$Config.openwebui_port
    $env:OLLAMA_BASE_URL = "http://$($Config.ollama_host):$($Config.ollama_port)"
}

function Invoke-DockerCompose {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $null = Get-DockerPath
    $composePath = Get-ComposePath

    Set-ComposeEnvironment -Config $Config

    & docker compose -f $composePath @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "docker compose $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

function Test-ComposeConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    [void](Invoke-DockerCompose -Config $Config -Arguments @("config"))
}

function Get-OpenWebUiHealth {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $null = Get-DockerPath

    $output = & docker inspect --format '{{if .State.Running}}{{if .State.Health}}{{.State.Health.Status}}{{else}}running{{end}}{{else}}stopped{{end}}' $Config.openwebui_container_name 2>$null

    if ($LASTEXITCODE -ne 0) {
        return "missing"
    }

    return ($output | Select-Object -First 1).ToString().Trim()
}

function Test-HttpEndpoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [int]$TimeoutSeconds = 10
    )

    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec $TimeoutSeconds
        return [pscustomobject]@{
            Ok         = ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400)
            StatusCode = $response.StatusCode
        }
    }
    catch {
        return [pscustomobject]@{
            Ok         = $false
            StatusCode = $null
        }
    }
}

function Wait-ForOpenWebUi {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [int]$RetryCount = 30,

        [int]$DelaySeconds = 2
    )

    $url = "http://127.0.0.1:$($Config.openwebui_port)"

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        $response = Test-HttpEndpoint -Url $url
        $health = Get-OpenWebUiHealth -Config $Config

        if ($response.Ok -and ($health -eq "healthy" -or $health -eq "running")) {
            return
        }

        Start-Sleep -Seconds $DelaySeconds
    }

    throw "Open WebUI did not become ready at $url."
}

function Assert-ConfiguredModelsInstalled {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ConfiguredModels,

        [Parameter(Mandatory = $true)]
        [string[]]$InstalledModels
    )

    $missingModels = $ConfiguredModels | Where-Object { $_ -notin $InstalledModels }

    if ($missingModels) {
        throw "Missing configured models: $($missingModels -join ', ')"
    }
}
