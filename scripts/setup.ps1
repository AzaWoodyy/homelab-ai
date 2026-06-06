param(
    [switch]$RefreshModels
)

. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "setup"

$config = Get-HomelabConfig
$models = Get-ConfiguredModels

Write-Log "Checking Ollama..." "STEP"
$ollamaPath = Get-OllamaPath
Write-Log (Get-CommandVersion -CommandPath $ollamaPath) "OK"

Write-Log "Checking Docker..." "STEP"
$dockerPath = Get-DockerPath
Write-Log (Get-CommandVersion -CommandPath $dockerPath) "OK"

Write-Log "Checking Tailscale..." "STEP"
$tailscalePath = Get-TailscalePath
Write-Log (Get-CommandVersion -CommandPath $tailscalePath) "OK"

Write-Log "Validating Tailscale HTTPS prerequisites..." "STEP"
$tailscaleNodeInfo = Assert-TailscaleServePrerequisites
Write-Log "Tailscale HTTPS URL: $($tailscaleNodeInfo.HttpsUrl)" "OK"

Write-Log "Validating Docker Compose configuration..." "STEP"
Test-ComposeConfiguration -Config $config
Write-Log "Docker Compose configuration is valid." "OK"

Write-Log "Ensuring Ollama is running..." "STEP"
Start-Ollama -Config $config -OllamaPath $ollamaPath
Wait-ForOllamaReady -OllamaPath $ollamaPath
Write-Log "Ollama is ready." "OK"

Write-Log "Getting installed models..." "STEP"
$installedModels = Get-InstalledOllamaModels -OllamaPath $ollamaPath

foreach ($model in $models) {
    $isInstalled = $model -in $installedModels

    if ($isInstalled -and -not $RefreshModels) {
        Write-Log "$model already installed" "OK"
        continue
    }

    if ($isInstalled -and $RefreshModels) {
        Write-Log "Refreshing $model" "STEP"
    }
    else {
        Write-Log "Pulling $model" "STEP"
    }

    $pullResult = Invoke-NativeCommand -FilePath $ollamaPath -Arguments @("pull", $model)

    if ($pullResult.ExitCode -ne 0) {
        $message = ($pullResult.StdErr + [Environment]::NewLine + $pullResult.StdOut).Trim()
        throw $message
    }

    Write-Log "$model is ready." "OK"
}

$installedModels = Get-InstalledOllamaModels -OllamaPath $ollamaPath
Assert-ConfiguredModelsInstalled -ConfiguredModels $models -InstalledModels $installedModels

Write-Log "Setup completed." "OK"
