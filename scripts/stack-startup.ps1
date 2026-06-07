param(
    [int]$MaxAttempts = 40,
    [int]$RetryDelaySeconds = 15,
    [int]$DockerStartTimeoutSeconds = 120
)

. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "stack-startup"

function Start-DockerDesktopIfNeeded {
    if (Test-DockerDaemonReady) {
        return
    }

    $dockerPath = Get-DockerPath
    Write-Log "Docker daemon is not ready. Asking Docker Desktop to start..." "WARN"
    $result = Invoke-NativeCommand -FilePath $dockerPath -Arguments @("desktop", "start", "--detach", "--timeout", [string]$DockerStartTimeoutSeconds)

    if ($result.ExitCode -ne 0) {
        $message = ($result.StdErr + [Environment]::NewLine + $result.StdOut).Trim()

        if (-not [string]::IsNullOrWhiteSpace($message)) {
            throw $message
        }

        throw "docker desktop start failed with exit code $($result.ExitCode)."
    }
}

for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    try {
        Write-Log "Boot stack startup attempt $attempt of $MaxAttempts..." "STEP"
        Start-DockerDesktopIfNeeded
        & (Join-Path $PSScriptRoot "start.ps1")
        Write-Log "Homelab stack boot startup completed." "OK"
        exit 0
    }
    catch {
        $message = $_.Exception.Message

        if ($attempt -ge $MaxAttempts) {
            Write-Log "Homelab stack boot startup failed after $attempt attempts: $message" "ERROR"
            throw
        }

        Write-Log "Homelab stack boot startup attempt $attempt failed: $message" "WARN"
        Write-Log "Retrying in $RetryDelaySeconds seconds..." "WARN"
        Start-Sleep -Seconds $RetryDelaySeconds
    }
}
