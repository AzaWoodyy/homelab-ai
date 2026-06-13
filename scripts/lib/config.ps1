function Get-HomelabRawConfig {
    $configPath = Join-Path $script:HomelabRoot "config\homelab.json"

    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Config file not found: $configPath"
    }

    return Read-JsonFile -Path $configPath
}

function Get-HomelabLocalRawConfig {
    $localConfigPath = Join-Path $script:HomelabRoot "config\homelab.local.json"

    return Read-JsonFile -Path $localConfigPath -AllowMissing
}

function Get-HomelabConfig {
    $rawConfig = Get-HomelabRawConfig
    $localConfig = Get-HomelabLocalRawConfig

    $hostname = [string](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("hostname") -DefaultValue "")

    if ([string]::IsNullOrWhiteSpace($hostname)) {
        $hostname = "homelab-ai"
    }

    $port = 3000

    $port = [int](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("openwebui_port") -DefaultValue $port)

    if ($port -lt 1 -or $port -gt 65535) {
        throw "openwebui_port must be between 1 and 65535."
    }

    $imageTag = [string](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("openwebui_image_tag") -DefaultValue "")

    if ([string]::IsNullOrWhiteSpace($imageTag)) {
        $imageTag = "v0.9.5"
    }

    $imageTag = $imageTag.Trim()

    $webUiSecretKey = ""
    $managementAdminSecret = ""
    $ollamaModelsPath = ""
    $runtimeContainerBackend = "windows-docker"
    $runtimeWslDistro = "Ubuntu"
    $runtimeOllamaBackend = "windows-process"

    $webUiSecretKey = [string](Get-HomelabNestedPropertyValue -InputObject $localConfig -Path @("webui_secret_key") -DefaultValue $webUiSecretKey)
    $managementAdminSecret = [string](Get-HomelabNestedPropertyValue -InputObject $localConfig -Path @("management_admin_secret") -DefaultValue $managementAdminSecret)
    $ollamaModelsPath = [string](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("ollama", "models_path") -DefaultValue $ollamaModelsPath)
    $runtimeContainerBackend = [string](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("runtime", "container_backend") -DefaultValue $runtimeContainerBackend)
    $runtimeWslDistro = [string](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("runtime", "wsl_distro") -DefaultValue $runtimeWslDistro)
    $runtimeOllamaBackend = [string](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("runtime", "ollama_backend") -DefaultValue $runtimeOllamaBackend)
    $runtimeContainerBackend = [string](Get-HomelabNestedPropertyValue -InputObject $localConfig -Path @("runtime", "container_backend") -DefaultValue $runtimeContainerBackend)
    $runtimeWslDistro = [string](Get-HomelabNestedPropertyValue -InputObject $localConfig -Path @("runtime", "wsl_distro") -DefaultValue $runtimeWslDistro)
    $runtimeOllamaBackend = [string](Get-HomelabNestedPropertyValue -InputObject $localConfig -Path @("runtime", "ollama_backend") -DefaultValue $runtimeOllamaBackend)
    $ollamaModelsPath = [string](Get-HomelabNestedPropertyValue -InputObject $localConfig -Path @("ollama", "models_path") -DefaultValue $ollamaModelsPath)

    if (-not [string]::IsNullOrWhiteSpace($env:WEBUI_SECRET_KEY)) {
        $webUiSecretKey = [string]$env:WEBUI_SECRET_KEY
    }

    if (-not [string]::IsNullOrWhiteSpace($env:MANAGEMENT_ADMIN_SECRET)) {
        $managementAdminSecret = [string]$env:MANAGEMENT_ADMIN_SECRET
    }

    if (-not [string]::IsNullOrWhiteSpace($env:OLLAMA_MODELS)) {
        $ollamaModelsPath = [string]$env:OLLAMA_MODELS
    }

    $webUiSecretKey = $webUiSecretKey.Trim()
    $managementAdminSecret = $managementAdminSecret.Trim()
    $ollamaModelsPath = $ollamaModelsPath.Trim()
    $runtimeContainerBackend = $runtimeContainerBackend.Trim().ToLowerInvariant()
    $runtimeWslDistro = $runtimeWslDistro.Trim()
    $runtimeOllamaBackend = $runtimeOllamaBackend.Trim().ToLowerInvariant()

    if (-not [string]::IsNullOrWhiteSpace($ollamaModelsPath)) {
        $ollamaModelsPath = [System.IO.Path]::GetFullPath($ollamaModelsPath)
    }

    if ($runtimeContainerBackend -notin @("windows-docker", "wsl-docker-engine")) {
        throw "runtime.container_backend must be 'windows-docker' or 'wsl-docker-engine'."
    }

    if ($runtimeOllamaBackend -notin @("windows-process", "windows-service", "wsl-service")) {
        throw "runtime.ollama_backend must be 'windows-process', 'windows-service', or 'wsl-service'."
    }

    if (($runtimeContainerBackend -eq "wsl-docker-engine" -or $runtimeOllamaBackend -eq "wsl-service") -and [string]::IsNullOrWhiteSpace($runtimeWslDistro)) {
        throw "runtime.wsl_distro is required when a WSL backend is selected."
    }

    $ttsEnabled = $true
    $ttsPort = 8000
    $ttsDefaultVoice = "fr_FR-siwis-medium"
    $ttsFallbackVoice = "en_US-lessac-medium"
    $sttModel = "medium"
    $sttLanguage = ""
    $sttAutoUpdate = $false
    $voiceVisionModel = "llava:13b"
    $voiceVisionFallbackModel = "qwen3.5:9b"
    $managementPort = 3081
    $managementTailscaleHttpsPort = 8443

    $ttsEnabled = [bool](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("tts", "enabled") -DefaultValue $ttsEnabled)
    $ttsPort = [int](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("tts", "port") -DefaultValue $ttsPort)
    $ttsDefaultVoice = [string](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("tts", "default_voice") -DefaultValue $ttsDefaultVoice)
    $ttsFallbackVoice = [string](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("tts", "fallback_voice") -DefaultValue $ttsFallbackVoice)
    $sttModel = [string](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("stt", "model") -DefaultValue $sttModel)
    $sttLanguage = [string](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("stt", "language") -DefaultValue $sttLanguage)
    $sttAutoUpdate = [bool](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("stt", "auto_update") -DefaultValue $sttAutoUpdate)
    $voiceVisionModel = [string](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("voice_vision_model") -DefaultValue $voiceVisionModel)
    $voiceVisionFallbackModel = [string](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("voice_vision_fallback_model") -DefaultValue $voiceVisionFallbackModel)
    $managementPort = [int](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("management", "port") -DefaultValue $managementPort)
    $managementTailscaleHttpsPort = [int](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("management", "tailscale_https_port") -DefaultValue $managementTailscaleHttpsPort)

    if ($ttsPort -lt 1 -or $ttsPort -gt 65535) {
        throw "tts.port must be between 1 and 65535."
    }

    if ($managementPort -lt 1 -or $managementPort -gt 65535) {
        throw "management.port must be between 1 and 65535."
    }

    if ($managementTailscaleHttpsPort -lt 1 -or $managementTailscaleHttpsPort -gt 65535) {
        throw "management.tailscale_https_port must be between 1 and 65535."
    }

    $ttsDefaultVoice = $ttsDefaultVoice.Trim()
    $ttsFallbackVoice = $ttsFallbackVoice.Trim()
    $sttModel = $sttModel.Trim()
    $sttLanguage = $sttLanguage.Trim()

    if ($ttsEnabled -and [string]::IsNullOrWhiteSpace($ttsDefaultVoice)) {
        throw "tts.default_voice is required when tts.enabled is true."
    }

    if ($ttsEnabled -and [string]::IsNullOrWhiteSpace($ttsFallbackVoice)) {
        throw "tts.fallback_voice is required when tts.enabled is true."
    }

    if ([string]::IsNullOrWhiteSpace($sttModel)) {
        throw "stt.model is required."
    }

    $voiceVisionModel = $voiceVisionModel.Trim()
    $voiceVisionFallbackModel = $voiceVisionFallbackModel.Trim()

    return [pscustomobject]@{
        hostname                 = $hostname
        openwebui_port           = $port
        openwebui_image_tag      = $imageTag
        openwebui_container_name = "open-webui"
        tts_enabled              = $ttsEnabled
        tts_port                 = $ttsPort
        tts_container_name       = "openedai-speech"
        tts_model                = "tts-1"
        tts_default_voice        = $ttsDefaultVoice
        tts_fallback_voice       = $ttsFallbackVoice
        stt_model                = $sttModel
        stt_language             = $sttLanguage
        stt_auto_update          = $sttAutoUpdate
        voice_vision_model       = $voiceVisionModel
        voice_vision_fallback_model = $voiceVisionFallbackModel
        ollama_service_name      = "Ollama"
        ollama_host              = "host.docker.internal"
        ollama_port              = 11434
        ollama_models_path       = $ollamaModelsPath
        ollama_models_runtime_path = if (-not [string]::IsNullOrWhiteSpace($ollamaModelsPath) -and $runtimeOllamaBackend -eq "wsl-service") { Convert-WindowsPathToWslPath -Path $ollamaModelsPath } else { $ollamaModelsPath }
        runtime_container_backend = $runtimeContainerBackend
        runtime_wsl_distro      = $runtimeWslDistro
        runtime_ollama_backend  = $runtimeOllamaBackend
        webui_secret_key         = $webUiSecretKey
        management_port          = $managementPort
        management_tailscale_https_port = $managementTailscaleHttpsPort
        management_startup       = "scheduled-task-user-logon"
        management_admin_secret  = $managementAdminSecret
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

function Assert-ManagementAdminSecretConfigured {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    if ([string]::IsNullOrWhiteSpace([string]$Config.management_admin_secret)) {
        throw "MANAGEMENT_ADMIN_SECRET is required. Set it in config\homelab.local.json or the MANAGEMENT_ADMIN_SECRET environment variable."
    }
}

function Set-HomelabProcessEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$Config.ollama_models_path)) {
        if (Test-HomelabOllamaBackendWsl -Config $Config) {
            Remove-Item Env:OLLAMA_MODELS -ErrorAction SilentlyContinue
            return
        }

        $env:OLLAMA_MODELS = [string]$Config.ollama_models_path
        return
    }

    Remove-Item Env:OLLAMA_MODELS -ErrorAction SilentlyContinue
}

function Get-EditableHomelabConfig {
    $rawConfig = Get-HomelabRawConfig

    return [ordered]@{
        openwebui_image_tag        = [string](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("openwebui_image_tag") -DefaultValue "")
        voice_vision_model         = [string](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("voice_vision_model") -DefaultValue "")
        voice_vision_fallback_model = [string](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("voice_vision_fallback_model") -DefaultValue "")
        tts                        = [ordered]@{
            enabled        = [bool](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("tts", "enabled") -DefaultValue $true)
            default_voice  = [string](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("tts", "default_voice") -DefaultValue "")
            fallback_voice = [string](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("tts", "fallback_voice") -DefaultValue "")
        }
        stt                        = [ordered]@{
            model       = [string](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("stt", "model") -DefaultValue "")
            language    = [string](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("stt", "language") -DefaultValue "")
            auto_update = [bool](Get-HomelabNestedPropertyValue -InputObject $rawConfig -Path @("stt", "auto_update") -DefaultValue $false)
        }
    }
}

function Save-EditableHomelabConfig {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$EditableConfig
    )

    $configPath = Join-Path $script:HomelabRoot "config\homelab.json"
    $rawConfig = Get-HomelabRawConfig

    if ([string]::IsNullOrWhiteSpace([string]$EditableConfig.openwebui_image_tag)) {
        throw "openwebui_image_tag is required."
    }

    if ([string]::IsNullOrWhiteSpace([string]$EditableConfig.voice_vision_model)) {
        throw "voice_vision_model is required."
    }

    if ([string]::IsNullOrWhiteSpace([string]$EditableConfig.voice_vision_fallback_model)) {
        throw "voice_vision_fallback_model is required."
    }

    if ($null -eq $EditableConfig.tts) {
        throw "tts config is required."
    }

    if ($null -eq $EditableConfig.stt) {
        throw "stt config is required."
    }

    if ([bool]$EditableConfig.tts.enabled) {
        if ([string]::IsNullOrWhiteSpace([string]$EditableConfig.tts.default_voice)) {
            throw "tts.default_voice is required when TTS is enabled."
        }

        if ([string]::IsNullOrWhiteSpace([string]$EditableConfig.tts.fallback_voice)) {
            throw "tts.fallback_voice is required when TTS is enabled."
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$EditableConfig.stt.model)) {
        throw "stt.model is required."
    }

    $rawConfig.openwebui_image_tag = [string]$EditableConfig.openwebui_image_tag
    $rawConfig.voice_vision_model = [string]$EditableConfig.voice_vision_model
    $rawConfig.voice_vision_fallback_model = [string]$EditableConfig.voice_vision_fallback_model

    $ttsConfig = Ensure-HomelabNestedObjectProperty -InputObject $rawConfig -Name "tts"

    Set-HomelabObjectPropertyValue -InputObject $ttsConfig -Name "enabled" -Value ([bool]$EditableConfig.tts.enabled)
    Set-HomelabObjectPropertyValue -InputObject $ttsConfig -Name "default_voice" -Value ([string]$EditableConfig.tts.default_voice)
    Set-HomelabObjectPropertyValue -InputObject $ttsConfig -Name "fallback_voice" -Value ([string]$EditableConfig.tts.fallback_voice)

    $sttConfig = Ensure-HomelabNestedObjectProperty -InputObject $rawConfig -Name "stt"

    Set-HomelabObjectPropertyValue -InputObject $sttConfig -Name "model" -Value ([string]$EditableConfig.stt.model)
    Set-HomelabObjectPropertyValue -InputObject $sttConfig -Name "language" -Value ([string]$EditableConfig.stt.language)
    Set-HomelabObjectPropertyValue -InputObject $sttConfig -Name "auto_update" -Value ([bool]$EditableConfig.stt.auto_update)

    Write-JsonFile -Path $configPath -Value $rawConfig -Depth 10

    return Get-EditableHomelabConfig
}
