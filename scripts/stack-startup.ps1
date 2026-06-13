param(
    [int]$MaxAttempts = 40,
    [int]$RetryDelaySeconds = 15,
    [int]$DockerStartTimeoutSeconds = 120
)

. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "stack-startup"

function Start-StackRuntimeIfNeeded {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    if (Test-DockerDaemonReady -Config $Config) {
        return
    }

    Start-DockerBackend -Config $Config -DockerDesktopStartTimeoutSeconds $DockerStartTimeoutSeconds
}

for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    try {
        $config = Get-HomelabConfig
        Write-Log "Boot stack startup attempt $attempt of $MaxAttempts..." "STEP"
        Start-StackRuntimeIfNeeded -Config $config
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
