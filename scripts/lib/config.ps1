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
        throw "WEBUI_SECRET_KEY is required. Set it in config\homelab.local.json or the WEBUI_SECRET_KEY environment variable."
    }
}
