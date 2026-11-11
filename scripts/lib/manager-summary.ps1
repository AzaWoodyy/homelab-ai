function Get-HomelabManagerReadOnlyConfig {
    $config = Get-HomelabConfig

    return [ordered]@{
        hostname                = $config.hostname
        openwebui_port          = $config.openwebui_port
        management_port         = $config.management_port
        management_https_port   = $config.management_tailscale_https_port
        management_startup      = $config.management_startup
        runtime_container_backend = $config.runtime_container_backend
        runtime_ollama_backend  = $config.runtime_ollama_backend
        runtime_wsl_distro      = $config.runtime_wsl_distro
        tts_port                = $config.tts_port
        hermes_home             = $config.hermes_home
        hermes_api_port         = $config.hermes_api_server_port
    }
}

function Get-HomelabManagerConfigResponse {
    return [ordered]@{
        editable      = Get-EditableHomelabConfig
        read_only     = Get-HomelabManagerReadOnlyConfig
        pending_apply = Get-HomelabManagerPendingApplyState
    }
}

function Get-HomelabManagerSummaryCacheTtlSeconds {
    return 45
}

function Get-HomelabManagerSummaryRefreshLockTtlSeconds {
    return 300
}

function Read-HomelabManagerSummaryCache {
    return Read-JsonFile -Path (Get-ManagerSummaryCachePath) -AllowMissing
}

function Save-HomelabManagerSummaryCache {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Summary,

        [Parameter(Mandatory = $true)]
        [string]$GeneratedAt,

        [Parameter(Mandatory = $true)]
        [int]$DurationMs,

        [string[]]$Errors = @()
    )

    Write-JsonFile -Path (Get-ManagerSummaryCachePath) -Value ([ordered]@{
        generated_at   = $GeneratedAt
        duration_ms    = $DurationMs
        refresh_status = "idle"
        errors         = @($Errors)
        summary        = $Summary
    })
}

function Get-HomelabManagerSummaryRefreshLock {
    $lock = Read-JsonFile -Path (Get-ManagerSummaryRefreshLockPath) -AllowMissing

    if ($null -eq $lock) {
        return $null
    }

    $startedAtText = [string](Get-HomelabObjectPropertyValue -InputObject $lock -Name "started_at" -DefaultValue "")
    $startedAt = [datetime]::MinValue

    if ([datetime]::TryParse($startedAtText, [ref]$startedAt)) {
        $ageSeconds = ((Get-Date) - $startedAt).TotalSeconds

        if ($ageSeconds -le (Get-HomelabManagerSummaryRefreshLockTtlSeconds)) {
            return $lock
        }
    }

    Remove-FileIfPresent -Path (Get-ManagerSummaryRefreshLockPath)
    return $null
}

function Write-HomelabManagerSummaryRefreshLock {
    param(
        [int]$ProcessId = 0
    )

    Write-JsonFile -Path (Get-ManagerSummaryRefreshLockPath) -Value ([ordered]@{
        refresh_status = "running"
        started_at     = Get-ManagerTimestamp
        pid            = if ($ProcessId -gt 0) { $ProcessId } else { $null }
    })
}

function Clear-HomelabManagerSummaryRefreshLock {
    Remove-FileIfPresent -Path (Get-ManagerSummaryRefreshLockPath)
}

function Get-HomelabManagerSummaryCacheAgeSeconds {
    param(
        [object]$Cache
    )

    $generatedAtText = [string](Get-HomelabObjectPropertyValue -InputObject $Cache -Name "generated_at" -DefaultValue "")
    $generatedAt = [datetime]::MinValue

    if (-not [datetime]::TryParse($generatedAtText, [ref]$generatedAt)) {
        return $null
    }

    return [int][math]::Max(0, [math]::Floor(((Get-Date) - $generatedAt).TotalSeconds))
}

function Test-HomelabManagerSummaryCacheFresh {
    param(
        [object]$Cache
    )

    $ageSeconds = Get-HomelabManagerSummaryCacheAgeSeconds -Cache $Cache

    return ($null -ne $ageSeconds -and $ageSeconds -le (Get-HomelabManagerSummaryCacheTtlSeconds))
}

function Get-HomelabManagerSummaryRefreshStatus {
    param(
        [object]$Cache
    )

    if ($null -ne (Get-HomelabManagerSummaryRefreshLock)) {
        return "running"
    }

    if ($null -eq $Cache) {
        return "missing"
    }

    if (Test-HomelabManagerSummaryCacheFresh -Cache $Cache) {
        return "idle"
    }

    return "stale"
}

function Get-HomelabManagerSummaryMeta {
    param(
        [object]$Cache
    )

    return [ordered]@{
        generated_at      = Get-HomelabObjectPropertyValue -InputObject $Cache -Name "generated_at" -DefaultValue $null
        duration_ms       = Get-HomelabObjectPropertyValue -InputObject $Cache -Name "duration_ms" -DefaultValue $null
        cache_age_seconds = Get-HomelabManagerSummaryCacheAgeSeconds -Cache $Cache
        refresh_status    = Get-HomelabManagerSummaryRefreshStatus -Cache $Cache
        errors            = @(Get-HomelabObjectPropertyValue -InputObject $Cache -Name "errors" -DefaultValue @())
    }
}

function Get-HomelabManagerModelsResponse {
    $config = Get-HomelabConfig
    $installedModels = @()

    try {
        if (Test-OllamaReady -Config $config) {
            $installedModels = Get-InstalledOllamaModels -Config $config
        }
    }
    catch {
        $installedModels = @()
    }

    return [ordered]@{
        configured     = @(Get-ConfiguredModels)
        installed      = @($installedModels)
        pending_apply  = Get-HomelabManagerPendingApplyState
        tts_enabled    = [bool]$config.tts_enabled
    }
}

function Get-HomelabManagerFullSummarySnapshot {
    param(
        [System.Collections.Generic.List[string]]$Errors
    )

    $config = Get-HomelabConfig
    $ollamaReady = $false
    $ollamaVersion = $null
    $dockerReady = $false
    $openWebUiHealth = "unknown"
    $ttsHealth = if ($config.tts_enabled) { "unknown" } else { "disabled" }
    $runtimePatchState = "unknown"
    $whisperCacheState = $null
    $installedModels = @()

    try {
        $ollamaVersion = Get-HomelabManagerOllamaVersionProbe -Config $config -Errors $Errors
        $ollamaReady = Test-HomelabManagerOllamaReadyProbe -Config $config -Errors $Errors

        if ($ollamaReady) {
            $installedModels = Get-HomelabManagerInstalledModelsProbe -Config $config -Errors $Errors
        }
    }
    catch {
        Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "Ollama probe failed: $($_.Exception.Message)"
        $ollamaReady = $false
    }

    try {
        $dockerReady = Test-HomelabManagerDockerReadyProbe -Config $config -Errors $Errors
    }
    catch {
        Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "Docker probe failed: $($_.Exception.Message)"
        $dockerReady = $false
    }

    if ($dockerReady) {
        $openWebUiHealth = Get-HomelabManagerContainerHealthProbe -Config $config -ContainerName $config.openwebui_container_name -Errors $Errors

        if ($config.tts_enabled) {
            $ttsHealth = Get-HomelabManagerContainerHealthProbe -Config $config -ContainerName $config.tts_container_name -Errors $Errors
        }

        if ($openWebUiHealth -in @("healthy", "running")) {
            try {
                $runtimePatchState = Get-OpenWebUiRuntimePatchState -Config $config
            }
            catch {
                Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "Open WebUI runtime patch probe failed: $($_.Exception.Message)"
                $runtimePatchState = "unknown"
            }

            try {
                $whisperCacheState = Get-OpenWebUiWhisperCacheState -Config $config
            }
            catch {
                Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "Open WebUI Whisper cache probe failed: $($_.Exception.Message)"
                $whisperCacheState = $null
            }
        }
    }
    else {
        $openWebUiHealth = "daemon-unavailable"

        if ($config.tts_enabled) {
            $ttsHealth = "daemon-unavailable"
        }
    }

    $openWebUiUrl = "http://127.0.0.1:$($config.openwebui_port)"
    $managementUrl = Get-HomelabManagerLocalUrl -Config $config
    $ttsUrl = "http://127.0.0.1:$($config.tts_port)"
    $hermesSummary = $null

    try {
        $hermesSummary = Get-HermesSummary -Config $config
    }
    catch {
        Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "Hermes probe failed: $($_.Exception.Message)"
        $hermesSummary = [ordered]@{
            enabled       = [bool]$config.hermes_enabled
            cli_available = $false
            version       = $null
            home          = [string]$config.hermes_home
            model         = [string]$config.hermes_model
            missing_config = @($_.Exception.Message)
            gateway       = [ordered]@{
                enabled    = [bool]$config.hermes_gateway_enabled
                running    = $false
                pid        = $null
                started_at = $null
            }
            api_server    = [ordered]@{
                enabled    = [bool]$config.hermes_api_server_enabled
                local_url  = Get-HermesApiServerUrl -Config $config
                reachable  = $false
                model_name = [string]$config.hermes_api_server_model_name
            }
            platforms     = Get-HermesPlatformStatus -Config $config
            log_tail      = @()
        }
    }

    $openWebUiHttp = Test-HttpEndpoint -Url $openWebUiUrl -TimeoutSeconds 2
    $managementHttp = [pscustomobject]@{ Ok = $true; StatusCode = 200 }
    $ttsHttp = if ($config.tts_enabled) {
        Test-HttpEndpoint -Url "$ttsUrl/docs" -TimeoutSeconds 2
    }
    else {
        $null
    }

    $tailscaleNodeInfo = $null
    $webUiServeState = $null
    $managementServeState = $null
    $tailscaleError = $null

    try {
        $tailscaleNodeInfo = Get-HomelabManagerTailscaleNodeInfoProbe -Errors $Errors

        if ($null -ne $tailscaleNodeInfo) {
            $webUiServeState = Get-HomelabManagerTailscaleServeProxyStateProbe -Config $config -NodeInfo $tailscaleNodeInfo -HttpsPort 443 -ExpectedProxyTarget "http://127.0.0.1:$($config.openwebui_port)" -Errors $Errors
            $managementServeState = Get-HomelabManagerTailscaleServeProxyStateProbe -Config $config -NodeInfo $tailscaleNodeInfo -HttpsPort $config.management_tailscale_https_port -ExpectedProxyTarget "http://127.0.0.1:$($config.management_port)" -Errors $Errors
        }
    }
    catch {
        $tailscaleError = $_.Exception.Message
        Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "Tailscale probe failed: $tailscaleError"
    }

    $lockInfo = Get-HomelabManagerLockInfo

    return [ordered]@{
        manager = [ordered]@{
            running                   = ($null -ne $lockInfo)
            pid                       = if ($null -ne $lockInfo) { [int]$lockInfo.pid } else { $null }
            started_at                = if ($null -ne $lockInfo) { [string]$lockInfo.started_at } else { $null }
            local_url                 = $managementUrl
            local_reachable           = [bool]$managementHttp.Ok
            scheduled_task_registered = Test-HomelabManagerTaskRegistered
            management_https_port     = $config.management_tailscale_https_port
        }
        stack = [ordered]@{
            ollama = [ordered]@{
                ready   = $ollamaReady
                version = $ollamaVersion
            }
            docker = [ordered]@{
                ready = $dockerReady
            }
            open_webui = [ordered]@{
                health             = $openWebUiHealth
                local_url          = $openWebUiUrl
                local_reachable    = [bool]$openWebUiHttp.Ok
                runtime_patch      = $runtimePatchState
                whisper_cache      = $whisperCacheState
            }
            tts = [ordered]@{
                enabled         = [bool]$config.tts_enabled
                health          = $ttsHealth
                local_url       = $ttsUrl
                local_reachable = if ($null -ne $ttsHttp) { [bool]$ttsHttp.Ok } else { $false }
            }
            hermes = $hermesSummary
        }
        models = [ordered]@{
            configured = @(Get-ConfiguredModels)
            installed  = @($installedModels)
        }
        config = [ordered]@{
            editable  = Get-EditableHomelabConfig
            read_only = Get-HomelabManagerReadOnlyConfig
        }
        tailscale = [ordered]@{
            available             = ($null -ne $tailscaleNodeInfo)
            error                 = $tailscaleError
            https_url             = if ($null -ne $tailscaleNodeInfo) { $tailscaleNodeInfo.HttpsUrl } else { $null }
            management_remote_url = if ($null -ne $tailscaleNodeInfo) { Get-HomelabManagerRemoteUrl -Config $config -NodeInfo $tailscaleNodeInfo } else { $null }
            magic_dns_enabled     = if ($null -ne $tailscaleNodeInfo) { [bool]$tailscaleNodeInfo.MagicDnsEnabled } else { $false }
            certs_enabled         = if ($null -ne $tailscaleNodeInfo) { [bool]$tailscaleNodeInfo.HttpsCertificatesEnabled } else { $false }
            open_webui            = if ($null -ne $webUiServeState) {
                [ordered]@{
                    configured_expected = [bool]$webUiServeState.IsConfiguredExpected
                    expected_target     = [string]$webUiServeState.ExpectedProxyTarget
                }
            } else { $null }
            management            = if ($null -ne $managementServeState) {
                [ordered]@{
                    configured_expected = [bool]$managementServeState.IsConfiguredExpected
                    expected_target     = [string]$managementServeState.ExpectedProxyTarget
                    https_port          = [int]$managementServeState.HttpsPort
                }
            } else { $null }
        }
        jobs = Get-HomelabManagerFastJobsSnapshot
        meta = $null
    }
}

function New-HomelabManagerDefaultSummary {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $managementUrl = Get-HomelabManagerLocalUrl -Config $Config
    $openWebUiUrl = "http://127.0.0.1:$($Config.openwebui_port)"
    $ttsUrl = "http://127.0.0.1:$($Config.tts_port)"
    $hermesSummary = Get-HermesSummary -Config $Config

    return [ordered]@{
        manager = [ordered]@{
            running                   = $false
            pid                       = $null
            started_at                = $null
            local_url                 = $managementUrl
            local_reachable           = $true
            scheduled_task_registered = $false
            management_https_port     = $Config.management_tailscale_https_port
        }
        stack = [ordered]@{
            ollama = [ordered]@{
                ready   = $false
                version = $null
            }
            docker = [ordered]@{
                ready = $false
            }
            open_webui = [ordered]@{
                health          = "unknown"
                local_url       = $openWebUiUrl
                local_reachable = $false
                runtime_patch   = "unknown"
                whisper_cache   = $null
            }
            tts = [ordered]@{
                enabled         = [bool]$Config.tts_enabled
                health          = if ($Config.tts_enabled) { "unknown" } else { "disabled" }
                local_url       = $ttsUrl
                local_reachable = $false
            }
            hermes = $hermesSummary
        }
        models = [ordered]@{
            configured = @(Get-ConfiguredModels)
            installed  = @()
        }
        config = [ordered]@{
            editable  = Get-EditableHomelabConfig
            read_only = Get-HomelabManagerReadOnlyConfig
        }
        tailscale = [ordered]@{
            available             = $false
            error                 = $null
            https_url             = $null
            management_remote_url = $null
            magic_dns_enabled     = $false
            certs_enabled         = $false
            open_webui            = $null
            management            = $null
        }
        jobs = Get-HomelabManagerFastJobsSnapshot
        meta = $null
    }
}

function Get-HomelabManagerFastSummary {
    param(
        [object]$Cache
    )

    $config = Get-HomelabConfig
    $cachedSummary = Get-HomelabObjectPropertyValue -InputObject $Cache -Name "summary" -DefaultValue $null
    $summary = if ($null -ne $cachedSummary) {
        $cachedSummary
    }
    else {
        New-HomelabManagerDefaultSummary -Config $config
    }

    $lockInfo = Get-HomelabManagerLockInfo
    $manager = Get-HomelabObjectPropertyValue -InputObject $summary -Name "manager" -DefaultValue $null
    $stack = Get-HomelabObjectPropertyValue -InputObject $summary -Name "stack" -DefaultValue $null
    $tts = if ($null -ne $stack) { Get-HomelabObjectPropertyValue -InputObject $stack -Name "tts" -DefaultValue $null } else { $null }
    $hermes = if ($null -ne $stack) { Get-HomelabObjectPropertyValue -InputObject $stack -Name "hermes" -DefaultValue $null } else { $null }
    $models = Get-HomelabObjectPropertyValue -InputObject $summary -Name "models" -DefaultValue $null
    $configSection = Get-HomelabObjectPropertyValue -InputObject $summary -Name "config" -DefaultValue $null

    if ($null -ne $manager) {
        Set-HomelabObjectPropertyValue -InputObject $manager -Name "running" -Value ($null -ne $lockInfo)
        Set-HomelabObjectPropertyValue -InputObject $manager -Name "pid" -Value $(if ($null -ne $lockInfo) { [int]$lockInfo.pid } else { $null })
        Set-HomelabObjectPropertyValue -InputObject $manager -Name "started_at" -Value $(if ($null -ne $lockInfo) { [string]$lockInfo.started_at } else { $null })
        Set-HomelabObjectPropertyValue -InputObject $manager -Name "local_url" -Value (Get-HomelabManagerLocalUrl -Config $config)
        Set-HomelabObjectPropertyValue -InputObject $manager -Name "local_reachable" -Value $true
        Set-HomelabObjectPropertyValue -InputObject $manager -Name "management_https_port" -Value $config.management_tailscale_https_port
    }

    if ($null -ne $tts) {
        Set-HomelabObjectPropertyValue -InputObject $tts -Name "enabled" -Value ([bool]$config.tts_enabled)
        Set-HomelabObjectPropertyValue -InputObject $tts -Name "local_url" -Value "http://127.0.0.1:$($config.tts_port)"
    }

    if ($null -ne $stack) {
        Set-HomelabObjectPropertyValue -InputObject $stack -Name "hermes" -Value (Get-HermesSummary -Config $config)
    }

    if ($null -ne $models) {
        Set-HomelabObjectPropertyValue -InputObject $models -Name "configured" -Value @(Get-ConfiguredModels)
    }

    if ($null -ne $configSection) {
        Set-HomelabObjectPropertyValue -InputObject $configSection -Name "editable" -Value (Get-EditableHomelabConfig)
        Set-HomelabObjectPropertyValue -InputObject $configSection -Name "read_only" -Value (Get-HomelabManagerReadOnlyConfig)
    }

    Set-HomelabObjectPropertyValue -InputObject $summary -Name "jobs" -Value (Get-HomelabManagerFastJobsSnapshot)
    Set-HomelabObjectPropertyValue -InputObject $summary -Name "meta" -Value (Get-HomelabManagerSummaryMeta -Cache $Cache)

    return $summary
}

function Start-HomelabManagerSummaryRefresh {
    param(
        [switch]$Force
    )

    $cache = Read-HomelabManagerSummaryCache

    if (-not $Force -and (Test-HomelabManagerSummaryCacheFresh -Cache $cache)) {
        return $false
    }

    if ($null -ne (Get-HomelabManagerSummaryRefreshLock)) {
        return $false
    }

    Write-HomelabManagerSummaryRefreshLock
    $refreshScript = Join-Path $script:HomelabRoot "scripts\manager-summary-refresh.ps1"

    try {
        $process = Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $refreshScript
        ) -WindowStyle Hidden -PassThru
        Write-HomelabManagerSummaryRefreshLock -ProcessId $process.Id
        return $true
    }
    catch {
        Clear-HomelabManagerSummaryRefreshLock
        throw
    }
}

function Invoke-HomelabManagerSummaryRefresh {
    Write-HomelabManagerSummaryRefreshLock -ProcessId $PID
    $startedAt = Get-Date
    $generatedAt = Get-ManagerTimestamp
    $errors = [System.Collections.Generic.List[string]]::new()

    try {
        $snapshot = Get-HomelabManagerFullSummarySnapshot -Errors $errors
        $durationMs = [int][math]::Round(((Get-Date) - $startedAt).TotalMilliseconds)
        Save-HomelabManagerSummaryCache -Summary $snapshot -GeneratedAt $generatedAt -DurationMs $durationMs -Errors @($errors)
    }
    catch {
        Add-HomelabManagerSummaryProbeError -Errors $errors -Message "Summary refresh failed: $($_.Exception.Message)"
        $cache = Read-HomelabManagerSummaryCache
        $fallback = Get-HomelabObjectPropertyValue -InputObject $cache -Name "summary" -DefaultValue $null

        if ($null -eq $fallback) {
            $fallback = New-HomelabManagerDefaultSummary -Config (Get-HomelabConfig)
        }

        $durationMs = [int][math]::Round(((Get-Date) - $startedAt).TotalMilliseconds)
        Save-HomelabManagerSummaryCache -Summary $fallback -GeneratedAt $generatedAt -DurationMs $durationMs -Errors @($errors)
    }
    finally {
        Clear-HomelabManagerSummaryRefreshLock
    }
}

function Get-HomelabManagerSummary {
    $cache = Read-HomelabManagerSummaryCache

    if (-not (Test-HomelabManagerSummaryCacheFresh -Cache $cache)) {
        try {
            [void](Start-HomelabManagerSummaryRefresh)
        }
        catch {
        }
    }

    $cache = Read-HomelabManagerSummaryCache
    return Get-HomelabManagerFastSummary -Cache $cache
}

function Request-HomelabManagerSummaryRefresh {
    try {
        [void](Start-HomelabManagerSummaryRefresh -Force)
    }
    catch {
    }

    return Get-HomelabManagerFastSummary -Cache (Read-HomelabManagerSummaryCache)
}
