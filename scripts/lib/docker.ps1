function Test-DockerDaemonReady {
    $dockerPath = Get-DockerPath
    $result = Invoke-NativeCommand -FilePath $dockerPath -Arguments @("info", "--format", "{{.ServerVersion}}")

    return ($result.ExitCode -eq 0)
}

function Assert-DockerDaemonReady {
    if (Test-DockerDaemonReady) {
        return
    }

    throw "Docker daemon is not running. Start Docker Desktop (or the Docker engine) and try again."
}

function Set-ComposeEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    Assert-WebUiSecretKeyConfigured -Config $Config

    $env:OPENWEBUI_PORT = [string]$Config.openwebui_port
    $env:OPENWEBUI_IMAGE_TAG = [string]$Config.openwebui_image_tag
    $env:OPENEDAI_SPEECH_PORT = [string]$Config.tts_port
    $env:OLLAMA_BASE_URL = "http://$($Config.ollama_host):$($Config.ollama_port)"
    $env:AUDIO_TTS_ENGINE = if ($Config.tts_enabled) { "openai" } else { "" }
    $env:AUDIO_TTS_OPENAI_API_BASE_URL = "http://$($Config.tts_container_name):8000/v1"
    $env:AUDIO_TTS_OPENAI_API_KEY = "local-tts"
    $env:AUDIO_TTS_MODEL = [string]$Config.tts_model
    $env:AUDIO_TTS_VOICE = [string]$Config.tts_default_voice
    $env:WHISPER_MODEL = [string]$Config.stt_model
    $env:WHISPER_LANGUAGE = [string]$Config.stt_language
    $env:WHISPER_MODEL_AUTO_UPDATE = if ($Config.stt_auto_update) { "true" } else { "false" }
    $env:WEBUI_SECRET_KEY = [string]$Config.webui_secret_key
}

function Get-ComposeRenderedConfig {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $composePath = Get-ComposePath

    Set-ComposeEnvironment -Config $Config

    $result = Invoke-NativeCommand -FilePath "docker" -Arguments @(
        "compose",
        "-f",
        $composePath,
        "config"
    )

    if ($result.ExitCode -ne 0) {
        $message = ($result.StdErr + [Environment]::NewLine + $result.StdOut).Trim()
        throw $message
    }

    return $result.StdOut
}

function Invoke-DockerCompose {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$RequireDaemon
    )

    if ($RequireDaemon) {
        Assert-DockerDaemonReady
    }

    $composePath = Get-ComposePath

    Set-ComposeEnvironment -Config $Config

    $dockerArguments = @(
        "compose",
        "-f",
        $composePath
    ) + $Arguments

    $result = Invoke-NativeCommand -FilePath "docker" -Arguments $dockerArguments

    if ($result.ExitCode -ne 0) {
        $message = ($result.StdErr + [Environment]::NewLine + $result.StdOut).Trim()

        if ([string]::IsNullOrWhiteSpace($message)) {
            throw "docker compose $($Arguments -join ' ') failed with exit code $($result.ExitCode)."
        }

        throw "docker compose $($Arguments -join ' ') failed with exit code $($result.ExitCode): $message"
    }

    return $result.StdOut
}

function Test-ComposeConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    [void](Get-ComposeRenderedConfig -Config $Config)
}

function Get-ContainerHealthState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName
    )

    $null = Get-DockerPath

    if (-not (Test-DockerDaemonReady)) {
        return "daemon-unavailable"
    }

    $result = Invoke-NativeCommand -FilePath "docker" -Arguments @(
        "inspect",
        "--format",
        "{{if .State.Running}}{{if .State.Health}}{{.State.Health.Status}}{{else}}running{{end}}{{else}}stopped{{end}}",
        $ContainerName
    )

    if ($result.ExitCode -ne 0) {
        return "missing"
    }

    return (($result.StdOut -split "\r?\n") | Select-Object -First 1).Trim()
}

function Get-ContainerStateSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName
    )

    $null = Get-DockerPath

    if (-not (Test-DockerDaemonReady)) {
        return "daemon unavailable"
    }

    $result = Invoke-NativeCommand -FilePath "docker" -Arguments @(
        "inspect",
        "--format",
        "{{if .State}}{{.State.Status}}{{if .State.Restarting}} (restarting){{end}}{{if .State.Health}} health={{.State.Health.Status}}{{end}}{{if .State.ExitCode}} exit={{.State.ExitCode}}{{end}}{{end}}",
        $ContainerName
    )

    if ($result.ExitCode -ne 0) {
        return "missing"
    }

    return (($result.StdOut -split "\r?\n") | Select-Object -First 1).Trim()
}

function Get-ContainerRecentLogs {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [int]$Tail = 40
    )

    $null = Get-DockerPath

    if (-not (Test-DockerDaemonReady)) {
        return @("Docker daemon is not running.")
    }

    $result = Invoke-NativeCommand -FilePath "docker" -Arguments @(
        "logs",
        "--tail",
        $Tail,
        $ContainerName
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

function Get-OpenWebUiHealth {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return Get-ContainerHealthState -ContainerName $Config.openwebui_container_name
}

function Get-OpenWebUiStateSummary {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return Get-ContainerStateSummary -ContainerName $Config.openwebui_container_name
}

function Get-OpenWebUiRecentLogs {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [int]$Tail = 40
    )

    return Get-ContainerRecentLogs -ContainerName $Config.openwebui_container_name -Tail $Tail
}

function Get-TtsHealth {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return Get-ContainerHealthState -ContainerName $Config.tts_container_name
}

function Get-TtsStateSummary {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return Get-ContainerStateSummary -ContainerName $Config.tts_container_name
}

function Get-TtsRecentLogs {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [int]$Tail = 40
    )

    return Get-ContainerRecentLogs -ContainerName $Config.tts_container_name -Tail $Tail
}
