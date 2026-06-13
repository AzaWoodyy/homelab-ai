function Get-DockerDaemonNotReadyMessage {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    if (Test-HomelabContainerBackendWsl -Config $Config) {
        return "Docker daemon is not running in WSL. Start the WSL Docker service or run .\scripts\wsl-bootstrap.ps1 first."
    }

    return "Docker daemon is not running. Start Docker Desktop (or the Docker engine) and try again."
}

function Get-ComposePathForBackend {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $composePath = Get-ComposePath

    if (Test-HomelabContainerBackendWsl -Config $Config) {
        return Convert-WindowsPathToWslPath -Path $composePath
    }

    return $composePath
}

function Test-DockerDaemonReady {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    try {
        $dockerCommand = Get-DockerCommandSpec -Config $Config
        $result = Invoke-HomelabCommandSpec -CommandSpec $dockerCommand -Arguments @("info", "--format", "{{.ServerVersion}}")

        return ($result.ExitCode -eq 0)
    }
    catch {
        return $false
    }
}

function Assert-DockerDaemonReady {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    if (Test-DockerDaemonReady -Config $Config) {
        return
    }

    throw (Get-DockerDaemonNotReadyMessage -Config $Config)
}

function Start-DockerBackend {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [int]$RetryCount = 30,

        [int]$DelaySeconds = 2,

        [int]$DockerDesktopStartTimeoutSeconds = 120
    )

    if (Test-DockerDaemonReady -Config $Config) {
        return
    }

    if (Test-HomelabContainerBackendWsl -Config $Config) {
        Write-Log "Starting Docker service in WSL distro $($Config.runtime_wsl_distro)..." "STEP"
        Start-WslSystemService -Config $Config -ServiceName "docker"
    }
    else {
        $dockerPath = Get-DockerPath
        Write-Log "Docker daemon is not ready. Asking Docker Desktop to start..." "WARN"
        $result = Invoke-NativeCommand -FilePath $dockerPath -Arguments @("desktop", "start", "--detach", "--timeout", [string]$DockerDesktopStartTimeoutSeconds)

        if ($result.ExitCode -ne 0) {
            $message = ($result.StdErr + [Environment]::NewLine + $result.StdOut).Trim()

            if (-not [string]::IsNullOrWhiteSpace($message)) {
                throw $message
            }

            throw "docker desktop start failed with exit code $($result.ExitCode)."
        }
    }

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        if (Test-DockerDaemonReady -Config $Config) {
            if (Test-HomelabContainerBackendWsl -Config $Config) {
                Write-Log "Docker daemon is ready in WSL." "OK"
            }

            return
        }

        Start-Sleep -Seconds $DelaySeconds
    }

    throw (Get-DockerDaemonNotReadyMessage -Config $Config)
}

function Get-WindowsDockerCommandSpec {
    return New-HomelabCommandSpec `
        -FilePath (Get-DockerPath) `
        -DisplayName "docker"
}

function Test-WindowsDockerDaemonReady {
    try {
        $result = Invoke-HomelabCommandSpec -CommandSpec (Get-WindowsDockerCommandSpec) -Arguments @("info", "--format", "{{.ServerVersion}}")
        return ($result.ExitCode -eq 0)
    }
    catch {
        return $false
    }
}

function Get-LegacyWindowsDockerContainers {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    if (-not (Test-HomelabContainerBackendWsl -Config $Config)) {
        return @()
    }

    if (-not (Test-WindowsDockerDaemonReady)) {
        return @()
    }

    $dockerCommand = Get-WindowsDockerCommandSpec
    $containerNames = @(
        [string]$Config.openwebui_container_name
        [string]$Config.tts_container_name
    ) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique

    $containers = New-Object System.Collections.Generic.List[object]

    foreach ($containerName in $containerNames) {
        $result = Invoke-HomelabCommandSpec -CommandSpec $dockerCommand -Arguments @(
            "inspect",
            "--format",
            '{{.Name}}|{{.State.Status}}|{{range $p, $conf := .NetworkSettings.Ports}}{{if $conf}}{{$p}}={{range $conf}}{{.HostIp}}:{{.HostPort}} {{end}}{{end}}{{end}}',
            $containerName
        )

        if ($result.ExitCode -ne 0) {
            continue
        }

        $firstLine = (($result.StdOut -split "\r?\n") | Select-Object -First 1).Trim()

        if ([string]::IsNullOrWhiteSpace($firstLine)) {
            continue
        }

        $parts = $firstLine -split '\|', 3

        if ($parts.Count -lt 2) {
            continue
        }

        $ports = ""

        if ($parts.Count -ge 3) {
            $ports = [string]$parts[2]
        }

        $containers.Add([pscustomobject]@{
            Name  = ($parts[0] -replace '^/', '').Trim()
            State = [string]$parts[1]
            Ports = $ports
        }) | Out-Null
    }

    return $containers.ToArray()
}

function Stop-LegacyWindowsDockerContainers {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $legacyContainers = @(Get-LegacyWindowsDockerContainers -Config $Config | Where-Object { $_.State -in @("running", "restarting") })

    if ($legacyContainers.Count -eq 0) {
        return
    }

    $names = @($legacyContainers | ForEach-Object { $_.Name })
    Write-Log "Stopping legacy Windows Docker containers before starting the WSL stack: $($names -join ', ')." "WARN"

    $dockerCommand = Get-WindowsDockerCommandSpec

    foreach ($container in $legacyContainers) {
        $result = Invoke-HomelabCommandSpec -CommandSpec $dockerCommand -Arguments @("stop", [string]$container.Name)

        if ($result.ExitCode -ne 0) {
            $message = ($result.StdErr + [Environment]::NewLine + $result.StdOut).Trim()

            if ([string]::IsNullOrWhiteSpace($message)) {
                throw "Failed to stop legacy Windows Docker container '$($container.Name)'."
            }

            throw "Failed to stop legacy Windows Docker container '$($container.Name)'. $message"
        }
    }

    Write-Log "Legacy Windows Docker containers were stopped so the WSL stack can bind local ports." "OK"
}

function Test-WslComposeContainerNeedsRecreate {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$ContainerName
    )

    if (-not (Test-HomelabContainerBackendWsl -Config $Config)) {
        return $false
    }

    $dockerCommand = Get-DockerCommandSpec -Config $Config
    $result = Invoke-HomelabCommandSpec -CommandSpec $dockerCommand -Arguments @(
        "inspect",
        "--format",
        '{{len .NetworkSettings.Networks}}|{{len .NetworkSettings.Ports}}|{{len .HostConfig.PortBindings}}',
        $ContainerName
    )

    if ($result.ExitCode -ne 0) {
        return $false
    }

    $firstLine = (($result.StdOut -split "\r?\n") | Select-Object -First 1).Trim()

    if ([string]::IsNullOrWhiteSpace($firstLine)) {
        return $false
    }

    $parts = $firstLine -split '\|', 3

    if ($parts.Count -lt 3) {
        return $false
    }

    $networkCount = 0
    $publishedPortCount = 0
    $requestedPortCount = 0

    [void][int]::TryParse([string]$parts[0], [ref]$networkCount)
    [void][int]::TryParse([string]$parts[1], [ref]$publishedPortCount)
    [void][int]::TryParse([string]$parts[2], [ref]$requestedPortCount)

    return ($requestedPortCount -gt 0 -and $networkCount -eq 0 -and $publishedPortCount -eq 0)
}

function Repair-WslComposeContainersIfNeeded {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    if (-not (Test-HomelabContainerBackendWsl -Config $Config)) {
        return
    }

    $servicesToRecreate = New-Object System.Collections.Generic.List[string]
    $serviceMap = [ordered]@{
        "open-webui"      = [string]$Config.openwebui_container_name
        "openedai-speech" = [string]$Config.tts_container_name
    }

    foreach ($entry in $serviceMap.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.Value)) {
            continue
        }

        if (Test-WslComposeContainerNeedsRecreate -Config $Config -ContainerName ([string]$entry.Value)) {
            $servicesToRecreate.Add([string]$entry.Key) | Out-Null
        }
    }

    if ($servicesToRecreate.Count -eq 0) {
        return
    }

    Write-Log "Recreating WSL containers with stale Docker networking metadata: $($servicesToRecreate -join ', ')." "WARN"
    [void](Invoke-DockerCompose -Config $Config -Arguments (@("up", "-d", "--force-recreate") + $servicesToRecreate.ToArray()) -RequireDaemon)
    Write-Log "WSL containers were recreated with fresh Docker network attachments." "OK"
}

function Set-ComposeEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    Assert-WebUiSecretKeyConfigured -Config $Config

    $composeEnvironment = Get-ComposeEnvironmentValues -Config $Config

    foreach ($entry in $composeEnvironment.GetEnumerator()) {
        Set-Item -Path ("Env:" + [string]$entry.Key) -Value ([string]$entry.Value)
    }
}

function Get-ComposeEnvironmentValues {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    Assert-WebUiSecretKeyConfigured -Config $Config

    return [ordered]@{
        OPENWEBUI_PORT            = [string]$Config.openwebui_port
        OPENWEBUI_IMAGE_TAG       = [string]$Config.openwebui_image_tag
        MCP_INITIALIZE_TIMEOUT    = [string]$Config.openwebui_mcp_initialize_timeout
        ENABLE_KB_EXEC            = if ($Config.openwebui_kb_exec_enabled) { "true" } else { "false" }
        PROFILE_IMAGE_MAX_DATA_URI_SIZE = if ($null -ne $Config.openwebui_profile_image_max_data_uri_size) { [string]$Config.openwebui_profile_image_max_data_uri_size } else { "" }
        OPENEDAI_SPEECH_PORT      = [string]$Config.tts_port
        OLLAMA_BASE_URL           = "http://$($Config.ollama_host):$($Config.ollama_port)"
        AUDIO_TTS_ENGINE          = if ($Config.tts_enabled) { "openai" } else { "" }
        AUDIO_TTS_OPENAI_API_BASE_URL = "http://$($Config.tts_container_name):8000/v1"
        AUDIO_TTS_OPENAI_API_KEY  = "local-tts"
        AUDIO_TTS_MODEL           = [string]$Config.tts_model
        AUDIO_TTS_VOICE           = [string]$Config.tts_default_voice
        WHISPER_MODEL             = [string]$Config.stt_model
        WHISPER_LANGUAGE          = [string]$Config.stt_language
        WHISPER_MODEL_AUTO_UPDATE = if ($Config.stt_auto_update) { "true" } else { "false" }
        WEBUI_SECRET_KEY          = [string]$Config.webui_secret_key
    }
}

function ConvertTo-BashSingleQuotedLiteral {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    $escapedSingleQuote = "'" + '"' + "'" + '"' + "'"
    return "'" + $Value.Replace("'", $escapedSingleQuote) + "'"
}

function Invoke-WslDockerCompose {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string[]]$DockerArguments
    )

    $environmentValues = Get-ComposeEnvironmentValues -Config $Config
    $environmentAssignments = @()

    foreach ($entry in $environmentValues.GetEnumerator()) {
        $environmentAssignments += ("{0}={1}" -f [string]$entry.Key, (ConvertTo-BashSingleQuotedLiteral -Value ([string]$entry.Value)))
    }

    $quotedDockerArguments = @($DockerArguments | ForEach-Object { ConvertTo-BashSingleQuotedLiteral -Value ([string]$_) })
    $commandText = "env " + ($environmentAssignments -join " ") + " docker " + ($quotedDockerArguments -join " ")

    return Invoke-WslCommand -Config $Config -Arguments @("sh", "-lc", $commandText)
}

function Get-ComposeRenderedConfig {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $dockerCommand = Get-DockerCommandSpec -Config $Config
    $composePath = Get-ComposePathForBackend -Config $Config

    Set-ComposeEnvironment -Config $Config

    $dockerArguments = @(
        "compose",
        "-f",
        $composePath,
        "config"
    )
    $result = if (Test-HomelabContainerBackendWsl -Config $Config) {
        Invoke-WslDockerCompose -Config $Config -DockerArguments $dockerArguments
    }
    else {
        Invoke-HomelabCommandSpec -CommandSpec $dockerCommand -Arguments $dockerArguments
    }

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
        Assert-DockerDaemonReady -Config $Config
    }

    $dockerCommand = Get-DockerCommandSpec -Config $Config
    $composePath = Get-ComposePathForBackend -Config $Config

    Set-ComposeEnvironment -Config $Config

    $dockerArguments = @(
        "compose",
        "-f",
        $composePath
    ) + $Arguments

    $result = if (Test-HomelabContainerBackendWsl -Config $Config) {
        Invoke-WslDockerCompose -Config $Config -DockerArguments $dockerArguments
    }
    else {
        Invoke-HomelabCommandSpec -CommandSpec $dockerCommand -Arguments $dockerArguments
    }

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
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$ContainerName
    )

    if (-not (Test-DockerDaemonReady -Config $Config)) {
        return "daemon-unavailable"
    }

    $dockerCommand = Get-DockerCommandSpec -Config $Config
    $result = Invoke-HomelabCommandSpec -CommandSpec $dockerCommand -Arguments @(
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
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$ContainerName
    )

    if (-not (Test-DockerDaemonReady -Config $Config)) {
        return "daemon unavailable"
    }

    $dockerCommand = Get-DockerCommandSpec -Config $Config
    $result = Invoke-HomelabCommandSpec -CommandSpec $dockerCommand -Arguments @(
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
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [int]$Tail = 40
    )

    if (-not (Test-DockerDaemonReady -Config $Config)) {
        return @("Docker daemon is not running.")
    }

    $dockerCommand = Get-DockerCommandSpec -Config $Config
    $result = Invoke-HomelabCommandSpec -CommandSpec $dockerCommand -Arguments @(
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

    return Get-ContainerHealthState -Config $Config -ContainerName $Config.openwebui_container_name
}

function Get-OpenWebUiStateSummary {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return Get-ContainerStateSummary -Config $Config -ContainerName $Config.openwebui_container_name
}

function Get-OpenWebUiRecentLogs {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [int]$Tail = 40
    )

    return Get-ContainerRecentLogs -Config $Config -ContainerName $Config.openwebui_container_name -Tail $Tail
}

function Get-TtsHealth {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return Get-ContainerHealthState -Config $Config -ContainerName $Config.tts_container_name
}

function Get-TtsStateSummary {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return Get-ContainerStateSummary -Config $Config -ContainerName $Config.tts_container_name
}

function Get-TtsRecentLogs {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [int]$Tail = 40
    )

    return Get-ContainerRecentLogs -Config $Config -ContainerName $Config.tts_container_name -Tail $Tail
}
