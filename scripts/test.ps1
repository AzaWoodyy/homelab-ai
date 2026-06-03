param()

. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "test"

$failures = New-Object System.Collections.Generic.List[string]

function Invoke-Check {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock
    )

    Write-Log $Name "STEP"

    try {
        $detail = & $ScriptBlock

        if (-not [string]::IsNullOrWhiteSpace([string]$detail)) {
            Write-Log $detail "OK"
        }
        else {
            Write-Log "$Name passed." "OK"
        }
    }
    catch {
        $message = $_.Exception.Message
        $failures.Add("${Name}: $message")
        Write-Log "$Name failed: $message" "ERROR"
    }
}

$config = $null
$models = $null
$ollamaPath = $null
$dockerPath = $null

Invoke-Check -Name "Load homelab config" -ScriptBlock {
    $script:config = Get-HomelabConfig
    "Hostname: $($script:config.hostname), Open WebUI port: $($script:config.openwebui_port)"
}

Invoke-Check -Name "Load model config" -ScriptBlock {
    $script:models = Get-ConfiguredModels
    "Configured models: $($script:models -join ', ')"
}

Invoke-Check -Name "Validate Ollama CLI" -ScriptBlock {
    $script:ollamaPath = Get-OllamaPath
    Get-CommandVersion -CommandPath $script:ollamaPath
}

Invoke-Check -Name "Validate Docker CLI" -ScriptBlock {
    $script:dockerPath = Get-DockerPath
    Get-CommandVersion -CommandPath $script:dockerPath
}

Invoke-Check -Name "Validate Docker Compose config" -ScriptBlock {
    Test-ComposeConfiguration -Config $script:config
    "Compose config rendered successfully."
}

Invoke-Check -Name "Validate Ollama runtime" -ScriptBlock {
    if (-not (Test-OllamaReady -OllamaPath $script:ollamaPath)) {
        throw "Ollama is not responding. Start Ollama first."
    }

    "Ollama is responding."
}

Invoke-Check -Name "Validate installed models" -ScriptBlock {
    $installedModels = Get-InstalledOllamaModels -OllamaPath $script:ollamaPath
    Assert-ConfiguredModelsInstalled -ConfiguredModels $script:models -InstalledModels $installedModels
    "All configured models are installed."
}

Invoke-Check -Name "Validate Open WebUI container" -ScriptBlock {
    $health = Get-OpenWebUiHealth -Config $script:config

    if ($health -eq "missing") {
        throw "Open WebUI container is not present. Run .\\scripts\\start.ps1 first."
    }

    if ($health -eq "stopped") {
        throw "Open WebUI container is stopped. Run .\\scripts\\start.ps1 first."
    }

    if ($health -ne "healthy" -and $health -ne "running") {
        throw "Open WebUI container health is '$health'."
    }

    "Open WebUI container health: $health"
}

Invoke-Check -Name "Validate Open WebUI HTTP endpoint" -ScriptBlock {
    $url = "http://127.0.0.1:$($script:config.openwebui_port)"
    $response = Test-HttpEndpoint -Url $url -TimeoutSeconds 15

    if (-not $response.Ok) {
        throw "Open WebUI did not return a healthy HTTP response at $url."
    }

    "Open WebUI is reachable at $url (HTTP $($response.StatusCode))."
}

if ($failures.Count -gt 0) {
    Write-Log "Test run completed with $($failures.Count) failure(s)." "ERROR"
    $failures | ForEach-Object { Write-Log $_ "ERROR" }
    throw "Homelab validation failed."
}

Write-Log "All homelab validation checks passed." "OK"
