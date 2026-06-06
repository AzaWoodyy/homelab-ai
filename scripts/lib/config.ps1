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

    $ttsEnabled = $true
    $ttsPort = 8000
    $ttsDefaultVoice = "fr_FR-siwis-medium"
    $ttsFallbackVoice = "en_US-lessac-medium"
    $sttModel = "medium"
    $sttLanguage = ""
    $sttAutoUpdate = $false
    $voiceVisionModel = "llava:13b"
    $voiceVisionFallbackModel = "qwen3.5:9b"

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

    if ($ttsPort -lt 1 -or $ttsPort -gt 65535) {
        throw "tts.port must be between 1 and 65535."
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
