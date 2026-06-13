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

function Test-TtsSpeechSynthesis {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$Voice,

        [Parameter(Mandatory = $true)]
        [string]$InputText,

        [string]$Model = "tts-1",

        [int]$TimeoutSeconds = 60
    )

    $outputPath = Join-Path ([System.IO.Path]::GetTempPath()) ("homelab-ai-tts-{0}.mp3" -f [guid]::NewGuid())

    try {
        $payload = @{
            model = $Model
            voice = $Voice
            input = $InputText
        } | ConvertTo-Json -Compress

        $response = Invoke-WebRequest `
            -UseBasicParsing `
            -Method Post `
            -Uri $Url `
            -ContentType "application/json" `
            -Body $payload `
            -Headers @{ Authorization = "Bearer local-tts" } `
            -TimeoutSec $TimeoutSeconds `
            -OutFile $outputPath

        $size = if (Test-Path -LiteralPath $outputPath) {
            (Get-Item -LiteralPath $outputPath).Length
        }
        else {
            0
        }

        $statusCode = if ($null -ne $response -and $response.PSObject.Properties.Name -contains "StatusCode") {
            [int]$response.StatusCode
        }
        else {
            200
        }

        return [pscustomobject]@{
            Ok         = ($statusCode -ge 200 -and $statusCode -lt 300 -and $size -gt 1024)
            StatusCode = $statusCode
            OutputSize = $size
            Error      = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Ok         = $false
            StatusCode = $null
            OutputSize = 0
            Error      = $_.Exception.Message
        }
    }
    finally {
        if (Test-Path -LiteralPath $outputPath) {
            Remove-Item -LiteralPath $outputPath -ErrorAction SilentlyContinue
        }
    }
}

function Test-OpenWebUiTtsSpeechSynthesis {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$Voice,

        [Parameter(Mandatory = $true)]
        [string]$InputText,

        [string]$Model = "tts-1",

        [int]$TimeoutSeconds = 60
    )

    $outputPath = Join-Path ([System.IO.Path]::GetTempPath()) ("homelab-ai-openwebui-tts-{0}.mp3" -f [guid]::NewGuid())

    try {
        $token = New-OpenWebUiLocalJwtToken -Config $Config
        $payload = @{
            model = $Model
            voice = $Voice
            input = $InputText
        } | ConvertTo-Json -Compress

        $response = Invoke-WebRequest `
            -UseBasicParsing `
            -Method Post `
            -Uri $Url `
            -ContentType "application/json" `
            -Body $payload `
            -Headers @{ Authorization = "Bearer $token" } `
            -TimeoutSec $TimeoutSeconds `
            -OutFile $outputPath

        $size = if (Test-Path -LiteralPath $outputPath) {
            (Get-Item -LiteralPath $outputPath).Length
        }
        else {
            0
        }

        $statusCode = if ($null -ne $response -and $response.PSObject.Properties.Name -contains "StatusCode") {
            [int]$response.StatusCode
        }
        else {
            200
        }

        $contentType = if ($null -ne $response -and $null -ne $response.Headers["Content-Type"]) {
            [string]$response.Headers["Content-Type"]
        }
        else {
            ""
        }

        return [pscustomobject]@{
            Ok          = ($statusCode -ge 200 -and $statusCode -lt 300 -and $size -gt 1024)
            StatusCode  = $statusCode
            OutputSize  = $size
            ContentType = $contentType
            Error       = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Ok          = $false
            StatusCode  = $null
            OutputSize  = 0
            ContentType = ""
            Error       = $_.Exception.Message
        }
    }
    finally {
        if (Test-Path -LiteralPath $outputPath) {
            Remove-Item -LiteralPath $outputPath -ErrorAction SilentlyContinue
        }
    }
}

function Assert-OpenWebUiCanProxyTts {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    if (-not $Config.tts_enabled) {
        return
    }

    if (-not (Test-OpenWebUiHasLocalUser -Config $Config)) {
        return
    }

    $url = "http://127.0.0.1:$($Config.openwebui_port)/api/v1/audio/speech"
    $inputText = "Bonjour depuis Open WebUI $([guid]::NewGuid())."
    $result = Test-OpenWebUiTtsSpeechSynthesis `
        -Config $Config `
        -Url $url `
        -Voice $Config.tts_default_voice `
        -InputText $inputText `
        -Model $Config.tts_model

    if (-not $result.Ok) {
        throw "Open WebUI could not proxy local TTS at $url. $($result.Error)"
    }
}

function Wait-ForTtsService {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [int]$RetryCount = 30,

        [int]$DelaySeconds = 2
    )

    $url = "http://127.0.0.1:$($Config.tts_port)/docs"

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        $response = Test-HttpEndpoint -Url $url
        $health = Get-TtsHealth -Config $Config

        if ($response.Ok -and ($health -eq "healthy" -or $health -eq "running")) {
            return
        }

        Start-Sleep -Seconds $DelaySeconds
    }

    $stateSummary = Get-TtsStateSummary -Config $Config
    $recentLogs = Get-TtsRecentLogs -Config $Config -Tail 20
    $logSummary = if ($recentLogs.Count -gt 0) {
        " Recent logs: $($recentLogs -join ' | ')"
    }
    else {
        ""
    }

    throw "TTS service did not become ready at $url. Container state: $stateSummary.$logSummary"
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
