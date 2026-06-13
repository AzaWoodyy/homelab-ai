function Get-OllamaService {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    if (Test-HomelabOllamaBackendWsl -Config $Config) {
        return $null
    }

    return Get-Service -Name $Config.ollama_service_name -ErrorAction SilentlyContinue
}

function Get-OllamaVersion {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $ollamaCommand = Get-OllamaCommandSpec -Config $Config
    return Get-HomelabCommandSpecVersion -CommandSpec $ollamaCommand
}

function Test-HomelabManagedOllamaPathConfigured {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    if (Test-HomelabOllamaBackendWsl -Config $Config) {
        return $false
    }

    return (-not [string]::IsNullOrWhiteSpace([string]$Config.ollama_models_path))
}

function Test-OllamaReady {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    try {
        $ollamaCommand = Get-OllamaCommandSpec -Config $Config
        $result = Invoke-HomelabCommandSpec -CommandSpec $ollamaCommand -Arguments @("list")
        return ($result.ExitCode -eq 0)
    }
    catch {
        return $false
    }
}

function Wait-ForOllamaReady {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [int]$RetryCount = 20,

        [int]$DelaySeconds = 1
    )

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        if (Test-OllamaReady -Config $Config) {
            return
        }

        Start-Sleep -Seconds $DelaySeconds
    }

    throw "Ollama did not become ready after $RetryCount attempts."
}

function Start-Ollama {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    if (Test-HomelabOllamaBackendWsl -Config $Config) {
        if (Test-OllamaReady -Config $Config) {
            Write-Log "Ollama service in WSL is already running." "OK"
            return
        }

        Start-WslSystemService -Config $Config -ServiceName "ollama"

        if (-not [string]::IsNullOrWhiteSpace([string]$Config.ollama_models_runtime_path)) {
            Write-Log "Started Ollama WSL service with models path $($Config.ollama_models_runtime_path)." "OK"
        }
        else {
            Write-Log "Started Ollama WSL service." "OK"
        }

        return
    }

    $ollamaCommand = Get-OllamaCommandSpec -Config $Config
    $service = Get-OllamaService -Config $Config
    $useManagedProcess = Test-HomelabManagedOllamaPathConfigured -Config $Config

    if ($useManagedProcess) {
        if ($service -and $service.Status -eq "Running") {
            Stop-Service -Name $Config.ollama_service_name
            Write-Log "Stopped Ollama Windows service so the configured models path can be used." "WARN"
        }

        if (Test-OllamaReady -Config $Config) {
            Write-Log "Ollama is already running with the configured models path." "OK"
            return
        }

        Start-Process -FilePath $ollamaCommand.FilePath -ArgumentList "serve" -WindowStyle Hidden
        Write-Log "Started Ollama process with models path $($Config.ollama_models_path)." "OK"
        return
    }

    if ([string]$Config.runtime_ollama_backend -eq "windows-service" -and $service) {
        if ($service.Status -eq "Running") {
            Write-Log "Ollama service is already running." "OK"
            return
        }

        Start-Service -Name $Config.ollama_service_name
        Write-Log "Ollama service started." "OK"
        return
    }

    if (Test-OllamaReady -Config $Config) {
        Write-Log "Ollama is already running." "OK"
        return
    }

    Start-Process -FilePath $ollamaCommand.FilePath -ArgumentList "serve" -WindowStyle Hidden
    Write-Log "Started Ollama process." "OK"
}

function Stop-Ollama {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    if (Test-HomelabOllamaBackendWsl -Config $Config) {
        $result = Invoke-WslCommand -Config $Config -Arguments @("systemctl", "stop", "ollama") -AsRoot

        if ($result.ExitCode -ne 0) {
            $message = ($result.StdErr + [Environment]::NewLine + $result.StdOut).Trim()

            if ([string]::IsNullOrWhiteSpace($message)) {
                $message = "Unknown WSL systemctl error."
            }

            throw "Failed to stop Ollama WSL service. $message"
        }

        Write-Log "Ollama WSL service stopped." "OK"
        return
    }

    $service = Get-OllamaService -Config $Config
    $useManagedProcess = Test-HomelabManagedOllamaPathConfigured -Config $Config

    if ($useManagedProcess) {
        if ($service -and $service.Status -eq "Running") {
            Stop-Service -Name $Config.ollama_service_name
            Write-Log "Ollama Windows service stopped." "OK"
        }

        $processes = Get-Process -Name "ollama" -ErrorAction SilentlyContinue

        if (-not $processes) {
            if (-not ($service -and $service.Status -eq "Running")) {
                Write-Log "No Ollama process found." "OK"
            }
            return
        }

        $processes | Stop-Process -Force
        Write-Log "Stopped Ollama process." "OK"
        return
    }

    if ([string]$Config.runtime_ollama_backend -eq "windows-service" -and $service) {
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
        [pscustomobject]$Config
    )

    $ollamaCommand = Get-OllamaCommandSpec -Config $Config
    $result = Invoke-HomelabCommandSpec -CommandSpec $ollamaCommand -Arguments @("list")

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
