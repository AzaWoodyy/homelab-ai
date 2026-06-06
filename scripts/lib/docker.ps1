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
    $env:OLLAMA_BASE_URL = "http://$($Config.ollama_host):$($Config.ollama_port)"
    $env:WEBUI_SECRET_KEY = [string]$Config.webui_secret_key
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

    if (-not (Test-DockerDaemonReady)) {
        return "daemon-unavailable"
    }

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

    if (-not (Test-DockerDaemonReady)) {
        return "daemon unavailable"
    }

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

    if (-not (Test-DockerDaemonReady)) {
        return @("Docker daemon is not running.")
    }

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
