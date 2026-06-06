function Test-HttpEndpoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [int]$TimeoutSeconds = 10
    )

    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec $TimeoutSeconds
        return [pscustomobject]@{
            Ok         = ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400)
            StatusCode = $response.StatusCode
        }
    }
    catch {
        return [pscustomobject]@{
            Ok         = $false
            StatusCode = $null
        }
    }
}

function Wait-ForOpenWebUi {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [int]$RetryCount = 30,

        [int]$DelaySeconds = 2
    )

    $url = "http://127.0.0.1:$($Config.openwebui_port)"

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        $response = Test-HttpEndpoint -Url $url
        $health = Get-OpenWebUiHealth -Config $Config

        if ($response.Ok -and ($health -eq "healthy" -or $health -eq "running")) {
            return
        }

        Start-Sleep -Seconds $DelaySeconds
    }

    $stateSummary = Get-OpenWebUiStateSummary -Config $Config
    $recentLogs = Get-OpenWebUiRecentLogs -Config $Config -Tail 20
    $logSummary = if ($recentLogs.Count -gt 0) {
        " Recent logs: $($recentLogs -join ' | ')"
    }
    else {
        ""
    }

    throw "Open WebUI did not become ready at $url. Container state: $stateSummary.$logSummary"
}
