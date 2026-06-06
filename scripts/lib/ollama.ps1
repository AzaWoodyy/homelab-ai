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
