function Get-HomelabRawConfig {
    $configPath = Join-Path $script:HomelabRoot "config\homelab.json"

    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Config file not found: $configPath"
    }

    return Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
}

function Get-HomelabLocalRawConfig {
    $localConfigPath = Join-Path $script:HomelabRoot "config\homelab.local.json"

    if (-not (Test-Path -LiteralPath $localConfigPath)) {
        return $null
    }

    return Get-Content -Raw -LiteralPath $localConfigPath | ConvertFrom-Json
}

function Get-HomelabConfig {
    $rawConfig = Get-HomelabRawConfig
    $localConfig = Get-HomelabLocalRawConfig

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
    $managementAdminSecret = ""

    if ($localConfig -and ($localConfig.PSObject.Properties.Name -contains "webui_secret_key") -and $null -ne $localConfig.webui_secret_key) {
        $webUiSecretKey = [string]$localConfig.webui_secret_key
    }

    if ($localConfig -and ($localConfig.PSObject.Properties.Name -contains "management_admin_secret") -and $null -ne $localConfig.management_admin_secret) {
        $managementAdminSecret = [string]$localConfig.management_admin_secret
    }

    if (-not [string]::IsNullOrWhiteSpace($env:WEBUI_SECRET_KEY)) {
        $webUiSecretKey = [string]$env:WEBUI_SECRET_KEY
    }

    if (-not [string]::IsNullOrWhiteSpace($env:MANAGEMENT_ADMIN_SECRET)) {
        $managementAdminSecret = [string]$env:MANAGEMENT_ADMIN_SECRET
    }

    $webUiSecretKey = $webUiSecretKey.Trim()
    $managementAdminSecret = $managementAdminSecret.Trim()

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

    if ($null -ne $rawConfig.tts) {
        if ($null -ne $rawConfig.tts.enabled) {
            $ttsEnabled = [bool]$rawConfig.tts.enabled
        }

        if ($null -ne $rawConfig.tts.port) {
            $ttsPort = [int]$rawConfig.tts.port
        }

        if ($null -ne $rawConfig.tts.default_voice) {
            $ttsDefaultVoice = [string]$rawConfig.tts.default_voice
        }

        if ($null -ne $rawConfig.tts.fallback_voice) {
            $ttsFallbackVoice = [string]$rawConfig.tts.fallback_voice
        }
    }

    if ($null -ne $rawConfig.stt) {
        if ($null -ne $rawConfig.stt.model) {
            $sttModel = [string]$rawConfig.stt.model
        }

        if ($null -ne $rawConfig.stt.language) {
            $sttLanguage = [string]$rawConfig.stt.language
        }

        if ($null -ne $rawConfig.stt.auto_update) {
            $sttAutoUpdate = [bool]$rawConfig.stt.auto_update
        }
    }

    if ($null -ne $rawConfig.voice_vision_model) {
        $voiceVisionModel = [string]$rawConfig.voice_vision_model
    }

    if ($null -ne $rawConfig.voice_vision_fallback_model) {
        $voiceVisionFallbackModel = [string]$rawConfig.voice_vision_fallback_model
    }

    if (($rawConfig.PSObject.Properties.Name -contains "management") -and $null -ne $rawConfig.management) {
        if (($rawConfig.management.PSObject.Properties.Name -contains "port") -and $null -ne $rawConfig.management.port) {
            $managementPort = [int]$rawConfig.management.port
        }

        if (($rawConfig.management.PSObject.Properties.Name -contains "tailscale_https_port") -and $null -ne $rawConfig.management.tailscale_https_port) {
            $managementTailscaleHttpsPort = [int]$rawConfig.management.tailscale_https_port
        }
    }

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
        webui_secret_key         = $webUiSecretKey
        management_port          = $managementPort
        management_tailscale_https_port = $managementTailscaleHttpsPort
        management_startup       = "scheduled-task"
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

function Get-EditableHomelabConfig {
    $rawConfig = Get-HomelabRawConfig

    return [ordered]@{
        openwebui_image_tag        = [string]$rawConfig.openwebui_image_tag
        voice_vision_model         = [string]$rawConfig.voice_vision_model
        voice_vision_fallback_model = [string]$rawConfig.voice_vision_fallback_model
        tts                        = [ordered]@{
            enabled        = if ($null -ne $rawConfig.tts -and $null -ne $rawConfig.tts.enabled) { [bool]$rawConfig.tts.enabled } else { $true }
            default_voice  = if ($null -ne $rawConfig.tts) { [string]$rawConfig.tts.default_voice } else { "" }
            fallback_voice = if ($null -ne $rawConfig.tts) { [string]$rawConfig.tts.fallback_voice } else { "" }
        }
        stt                        = [ordered]@{
            model       = if ($null -ne $rawConfig.stt) { [string]$rawConfig.stt.model } else { "" }
            language    = if ($null -ne $rawConfig.stt) { [string]$rawConfig.stt.language } else { "" }
            auto_update = if ($null -ne $rawConfig.stt -and $null -ne $rawConfig.stt.auto_update) { [bool]$rawConfig.stt.auto_update } else { $false }
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

    if ($null -eq $rawConfig.tts) {
        $rawConfig | Add-Member -NotePropertyName "tts" -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    $rawConfig.tts.enabled = [bool]$EditableConfig.tts.enabled
    $rawConfig.tts.default_voice = [string]$EditableConfig.tts.default_voice
    $rawConfig.tts.fallback_voice = [string]$EditableConfig.tts.fallback_voice

    if ($null -eq $rawConfig.stt) {
        $rawConfig | Add-Member -NotePropertyName "stt" -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    $rawConfig.stt.model = [string]$EditableConfig.stt.model
    $rawConfig.stt.language = [string]$EditableConfig.stt.language
    $rawConfig.stt.auto_update = [bool]$EditableConfig.stt.auto_update

    $json = $rawConfig | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($configPath, ($json + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))

    return Get-EditableHomelabConfig
}
