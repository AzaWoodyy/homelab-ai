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

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$Arguments = @()
    )

    $stdoutPath = Join-Path ([System.IO.Path]::GetTempPath()) ("homelab-ai-stdout-{0}.log" -f [guid]::NewGuid())
    $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) ("homelab-ai-stderr-{0}.log" -f [guid]::NewGuid())

    try {
        $process = Start-Process `
            -FilePath $FilePath `
            -ArgumentList $Arguments `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        $stdout = if (Test-Path -LiteralPath $stdoutPath) {
            Get-Content -Raw -LiteralPath $stdoutPath
        }
        else {
            ""
        }

        $stderr = if (Test-Path -LiteralPath $stderrPath) {
            Get-Content -Raw -LiteralPath $stderrPath
        }
        else {
            ""
        }

        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut   = $stdout
            StdErr   = $stderr
        }
    }
    finally {
        if (Test-Path -LiteralPath $stdoutPath) {
            Remove-Item -LiteralPath $stdoutPath -ErrorAction SilentlyContinue
        }

        if (Test-Path -LiteralPath $stderrPath) {
            Remove-Item -LiteralPath $stderrPath -ErrorAction SilentlyContinue
        }
    }
}

function Get-HomelabConfig {
    $configPath = Join-Path $script:HomelabRoot "config\homelab.json"
    $localConfigPath = Join-Path $script:HomelabRoot "config\homelab.local.json"

    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Config file not found: $configPath"
    }

    $rawConfig = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
    $localConfig = $null

    if (Test-Path -LiteralPath $localConfigPath) {
        $localConfig = Get-Content -Raw -LiteralPath $localConfigPath | ConvertFrom-Json
    }

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

    $imageTag = [string]$rawConfig.openwebui_image_tag

    if ([string]::IsNullOrWhiteSpace($imageTag)) {
        $imageTag = "v0.9.5"
    }

    $imageTag = $imageTag.Trim()

    $webUiSecretKey = ""

    if ($localConfig -and $null -ne $localConfig.webui_secret_key) {
        $webUiSecretKey = [string]$localConfig.webui_secret_key
    }

    if (-not [string]::IsNullOrWhiteSpace($env:WEBUI_SECRET_KEY)) {
        $webUiSecretKey = [string]$env:WEBUI_SECRET_KEY
    }

    $webUiSecretKey = $webUiSecretKey.Trim()

    return [pscustomobject]@{
        hostname                 = $hostname
        openwebui_port           = $port
        openwebui_image_tag      = $imageTag
        openwebui_container_name = "open-webui"
        ollama_service_name      = "Ollama"
        ollama_host              = "host.docker.internal"
        ollama_port              = 11434
        webui_secret_key         = $webUiSecretKey
    }
}

function Assert-WebUiSecretKeyConfigured {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    if ([string]::IsNullOrWhiteSpace([string]$Config.webui_secret_key)) {
        throw "WEBUI_SECRET_KEY is required. Set it in config\\homelab.local.json or the WEBUI_SECRET_KEY environment variable."
    }
}

function Normalize-OllamaModelName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelName
    )

    $normalized = $ModelName.Trim()

    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $normalized
    }

    $lastSlashIndex = $normalized.LastIndexOf("/")
    $lastColonIndex = $normalized.LastIndexOf(":")

    if ($lastColonIndex -gt $lastSlashIndex) {
        return $normalized
    }

    return "$normalized`:latest"
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
        ForEach-Object { Normalize-OllamaModelName -ModelName $_ } |
        Group-Object |
        Where-Object Count -gt 1 |
        Select-Object -ExpandProperty Name

    if ($duplicates) {
        throw "Duplicate models found in config/models.json after normalization: $($duplicates -join ', ')"
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

    $result = Invoke-NativeCommand -FilePath $CommandPath -Arguments @("--version")

    if ($result.ExitCode -ne 0) {
        $message = ($result.StdErr + [Environment]::NewLine + $result.StdOut).Trim()
        throw $message
    }

    return (($result.StdOut -split "\r?\n") | Select-Object -First 1).Trim()
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
        $result = Invoke-NativeCommand -FilePath $OllamaPath -Arguments @("list")
        return ($result.ExitCode -eq 0)
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

    $result = Invoke-NativeCommand -FilePath $OllamaPath -Arguments @("list")

    if ($result.ExitCode -ne 0) {
        $message = ($result.StdErr + [Environment]::NewLine + $result.StdOut).Trim()
        throw $message
    }

    return ($result.StdOut -split "\r?\n") |
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

    Assert-WebUiSecretKeyConfigured -Config $Config

    $env:OPENWEBUI_PORT = [string]$Config.openwebui_port
    $env:OPENWEBUI_IMAGE_TAG = [string]$Config.openwebui_image_tag
    $env:OLLAMA_BASE_URL = "http://$($Config.ollama_host):$($Config.ollama_port)"
    $env:WEBUI_SECRET_KEY = [string]$Config.webui_secret_key
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

    $result = Invoke-NativeCommand -FilePath "docker" -Arguments @(
        "inspect",
        "--format",
        "{{if .State.Running}}{{if .State.Health}}{{.State.Health.Status}}{{else}}running{{end}}{{else}}stopped{{end}}",
        $Config.openwebui_container_name
    )

    if ($result.ExitCode -ne 0) {
        return "missing"
    }

    return (($result.StdOut -split "\r?\n") | Select-Object -First 1).Trim()
}

function Get-OpenWebUiStateSummary {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $null = Get-DockerPath

    $result = Invoke-NativeCommand -FilePath "docker" -Arguments @(
        "inspect",
        "--format",
        "{{if .State}}{{.State.Status}}{{if .State.Restarting}} (restarting){{end}}{{if .State.Health}} health={{.State.Health.Status}}{{end}}{{if .State.ExitCode}} exit={{.State.ExitCode}}{{end}}{{end}}",
        $Config.openwebui_container_name
    )

    if ($result.ExitCode -ne 0) {
        return "missing"
    }

    return (($result.StdOut -split "\r?\n") | Select-Object -First 1).Trim()
}

function Get-OpenWebUiRecentLogs {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [int]$Tail = 40
    )

    $null = Get-DockerPath

    $result = Invoke-NativeCommand -FilePath "docker" -Arguments @(
        "logs",
        "--tail",
        $Tail,
        $Config.openwebui_container_name
    )

    $combinedOutput = @()

    if (-not [string]::IsNullOrWhiteSpace($result.StdOut)) {
        $combinedOutput += ($result.StdOut -split "\r?\n")
    }

    if (-not [string]::IsNullOrWhiteSpace($result.StdErr)) {
        $combinedOutput += ($result.StdErr -split "\r?\n")
    }

    if ($result.ExitCode -ne 0 -and $combinedOutput.Count -eq 0) {
        return @()
    }

    return $combinedOutput |
        ForEach-Object { $_.ToString().TrimEnd() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
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

    $stateSummary = Get-OpenWebUiStateSummary -Config $Config
    $recentLogs = Get-OpenWebUiRecentLogs -Config $Config -Tail 20
    $logSummary = if ($recentLogs.Count -gt 0) {
        " Recent logs: $($recentLogs -join ' | ')"
    }
    else {
        ""
    }

    throw "Open WebUI did not become ready at $url. Container state: $stateSummary.$logSummary"
}

function Assert-ConfiguredModelsInstalled {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ConfiguredModels,

        [Parameter(Mandatory = $true)]
        [string[]]$InstalledModels
    )

    $normalizedInstalledModels = $InstalledModels |
        ForEach-Object { Normalize-OllamaModelName -ModelName $_ } |
        Select-Object -Unique

    $missingModels = $ConfiguredModels | Where-Object {
        (Normalize-OllamaModelName -ModelName $_) -notin $normalizedInstalledModels
    }

    if ($missingModels) {
        throw "Missing configured models: $($missingModels -join ', ')"
    }
}
