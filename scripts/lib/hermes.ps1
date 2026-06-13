function Get-HermesHomePath {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return [string]$Config.hermes_home
}

function Ensure-HermesHome {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $hermesHomePath = Get-HermesHomePath -Config $Config

    if (-not (Test-Path -LiteralPath $hermesHomePath)) {
        New-Item -ItemType Directory -Path $hermesHomePath -Force | Out-Null
    }

    $logs = Join-Path $hermesHomePath "logs"

    if (-not (Test-Path -LiteralPath $logs)) {
        New-Item -ItemType Directory -Path $logs -Force | Out-Null
    }

    return $hermesHomePath
}

function Get-HermesGatewayPidPath {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return Join-Path (Ensure-HermesHome -Config $Config) "gateway.pid"
}

function Get-HermesGatewayRuntimePath {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return Join-Path (Ensure-HermesHome -Config $Config) "gateway-runtime.json"
}

function Get-HermesGatewayStatePath {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return Join-Path (Ensure-HermesHome -Config $Config) "gateway_state.json"
}

function Get-HermesEnvPath {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return Join-Path (Ensure-HermesHome -Config $Config) ".env"
}

function Get-HermesConfigPath {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return Join-Path (Ensure-HermesHome -Config $Config) "config.yaml"
}

function Get-HermesCommandPath {
    $command = Get-Command "hermes" -ErrorAction SilentlyContinue

    if ($command) {
        return $command.Source
    }

    $candidate = Join-Path $env:LOCALAPPDATA "hermes\bin\hermes.exe"

    if (Test-Path -LiteralPath $candidate) {
        return $candidate
    }

    $venvCandidate = Join-Path $env:LOCALAPPDATA "hermes\hermes-agent\venv\Scripts\hermes.exe"

    if (Test-Path -LiteralPath $venvCandidate) {
        return $venvCandidate
    }

    return $null
}

function Get-HermesPythonwCommandPath {
    $hermesPath = Get-HermesCommandPath

    if ([string]::IsNullOrWhiteSpace($hermesPath)) {
        return $null
    }

    $scriptsPath = Split-Path -Parent $hermesPath
    $candidate = Join-Path $scriptsPath "pythonw.exe"

    if (Test-Path -LiteralPath $candidate) {
        return $candidate
    }

    return $null
}

function Test-HermesCliAvailable {
    return -not [string]::IsNullOrWhiteSpace((Get-HermesCommandPath))
}

function Invoke-HermesCommand {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [string[]]$Arguments = @(),

        [int]$TimeoutMs = 15000
    )

    $hermesPath = Get-HermesCommandPath

    if ([string]::IsNullOrWhiteSpace($hermesPath)) {
        throw "Hermes CLI was not found. Install Hermes Agent first, then rerun setup."
    }

    Set-HermesProcessEnvironment -Config $Config
    return Invoke-NativeCommandWithTimeout -FilePath $hermesPath -Arguments $Arguments -TimeoutMs $TimeoutMs
}

function Get-HermesVersion {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $result = Invoke-HermesCommand -Config $Config -Arguments @("--version") -TimeoutMs 10000

    if ($result.TimedOut) {
        throw "Hermes version probe timed out."
    }

    if ($result.ExitCode -ne 0) {
        $message = ($result.StdErr + [Environment]::NewLine + $result.StdOut).Trim()
        throw $message
    }

    return (($result.StdOut -split "\r?\n") | Select-Object -First 1).Trim()
}

function Set-HermesEnvIfPresent {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$Values,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowEmptyString()]
        [string]$Value
    )

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $Values[$Name] = $Value
    }
}

function Get-HermesEnvironmentValues {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $values = [ordered]@{
        HERMES_HOME = (Ensure-HermesHome -Config $Config)
    }
    $values["HERMES_GATEWAY_LOCK_DIR"] = Join-Path ([string]$values["HERMES_HOME"]) "gateway-locks"

    if ($Config.hermes_api_server_enabled) {
        $values["API_SERVER_ENABLED"] = "true"
        $values["API_SERVER_HOST"] = [string]$Config.hermes_api_server_host
        $values["API_SERVER_PORT"] = [string]$Config.hermes_api_server_port
        $values["API_SERVER_KEY"] = [string]$Config.hermes_api_server_key
        $values["API_SERVER_MODEL_NAME"] = [string]$Config.hermes_api_server_model_name
    }

    if ($Config.hermes_discord_enabled) {
        Set-HermesEnvIfPresent -Values $values -Name "DISCORD_BOT_TOKEN" -Value ([string]$Config.hermes_discord_bot_token)
        Set-HermesEnvIfPresent -Values $values -Name "DISCORD_ALLOWED_USERS" -Value ([string]$Config.hermes_discord_allowed_users)
        Set-HermesEnvIfPresent -Values $values -Name "DISCORD_ALLOWED_ROLES" -Value ([string]$Config.hermes_discord_allowed_roles)
        Set-HermesEnvIfPresent -Values $values -Name "DISCORD_HOME_CHANNEL" -Value ([string]$Config.hermes_discord_home_channel)
        $values["DISCORD_REQUIRE_MENTION"] = if ($Config.hermes_discord_require_mention) { "true" } else { "false" }
        Set-HermesEnvIfPresent -Values $values -Name "DISCORD_FREE_RESPONSE_CHANNELS" -Value ([string]$Config.hermes_discord_free_response_channels)
    }

    if ($Config.hermes_email_enabled) {
        Set-HermesEnvIfPresent -Values $values -Name "EMAIL_ADDRESS" -Value ([string]$Config.hermes_email_address)
        Set-HermesEnvIfPresent -Values $values -Name "EMAIL_PASSWORD" -Value ([string]$Config.hermes_email_password)
        Set-HermesEnvIfPresent -Values $values -Name "EMAIL_IMAP_HOST" -Value ([string]$Config.hermes_email_imap_host)
        Set-HermesEnvIfPresent -Values $values -Name "EMAIL_SMTP_HOST" -Value ([string]$Config.hermes_email_smtp_host)
        $values["EMAIL_IMAP_PORT"] = [string]$Config.hermes_email_imap_port
        $values["EMAIL_SMTP_PORT"] = [string]$Config.hermes_email_smtp_port
        $values["EMAIL_POLL_INTERVAL"] = [string]$Config.hermes_email_poll_interval
        Set-HermesEnvIfPresent -Values $values -Name "EMAIL_ALLOWED_USERS" -Value ([string]$Config.hermes_email_allowed_users)
        Set-HermesEnvIfPresent -Values $values -Name "EMAIL_HOME_ADDRESS" -Value ([string]$Config.hermes_email_home_address)
    }

    if ($Config.hermes_photon_enabled) {
        Set-HermesEnvIfPresent -Values $values -Name "PHOTON_PROJECT_ID" -Value ([string]$Config.hermes_photon_project_id)
        Set-HermesEnvIfPresent -Values $values -Name "PHOTON_PROJECT_SECRET" -Value ([string]$Config.hermes_photon_project_secret)
        $values["PHOTON_SIDECAR_PORT"] = [string]$Config.hermes_photon_sidecar_port
        $values["PHOTON_SIDECAR_AUTOSTART"] = if ($Config.hermes_photon_sidecar_autostart) { "true" } else { "false" }
        Set-HermesEnvIfPresent -Values $values -Name "PHOTON_ALLOWED_USERS" -Value ([string]$Config.hermes_photon_allowed_users)
        Set-HermesEnvIfPresent -Values $values -Name "PHOTON_HOME_CHANNEL" -Value ([string]$Config.hermes_photon_home_channel)
        Set-HermesEnvIfPresent -Values $values -Name "PHOTON_HOME_CHANNEL_NAME" -Value ([string]$Config.hermes_photon_home_channel_name)
        $values["PHOTON_REQUIRE_MENTION"] = if ($Config.hermes_photon_require_mention) { "true" } else { "false" }
        Set-HermesEnvIfPresent -Values $values -Name "PHOTON_MENTION_PATTERNS" -Value ([string]$Config.hermes_photon_mention_patterns)
        Set-HermesEnvIfPresent -Values $values -Name "PHOTON_NODE_BIN" -Value ([string]$Config.hermes_photon_node_bin)
        Set-HermesEnvIfPresent -Values $values -Name "PHOTON_DASHBOARD_HOST" -Value ([string]$Config.hermes_photon_dashboard_host)
        Set-HermesEnvIfPresent -Values $values -Name "PHOTON_SPECTRUM_HOST" -Value ([string]$Config.hermes_photon_spectrum_host)
    }

    if ($Config.hermes_whatsapp_cloud_enabled) {
        Set-HermesEnvIfPresent -Values $values -Name "WHATSAPP_CLOUD_PHONE_NUMBER_ID" -Value ([string]$Config.hermes_whatsapp_cloud_phone_number_id)
        Set-HermesEnvIfPresent -Values $values -Name "WHATSAPP_CLOUD_ACCESS_TOKEN" -Value ([string]$Config.hermes_whatsapp_cloud_access_token)
        Set-HermesEnvIfPresent -Values $values -Name "WHATSAPP_CLOUD_APP_SECRET" -Value ([string]$Config.hermes_whatsapp_cloud_app_secret)
        Set-HermesEnvIfPresent -Values $values -Name "WHATSAPP_CLOUD_VERIFY_TOKEN" -Value ([string]$Config.hermes_whatsapp_cloud_verify_token)
        Set-HermesEnvIfPresent -Values $values -Name "WHATSAPP_CLOUD_ALLOWED_USERS" -Value ([string]$Config.hermes_whatsapp_cloud_allowed_users)
        Set-HermesEnvIfPresent -Values $values -Name "WHATSAPP_CLOUD_HOME_CHANNEL" -Value ([string]$Config.hermes_whatsapp_cloud_home_channel)
        Set-HermesEnvIfPresent -Values $values -Name "WHATSAPP_CLOUD_APP_ID" -Value ([string]$Config.hermes_whatsapp_cloud_app_id)
        Set-HermesEnvIfPresent -Values $values -Name "WHATSAPP_CLOUD_WABA_ID" -Value ([string]$Config.hermes_whatsapp_cloud_waba_id)
        $values["WHATSAPP_CLOUD_WEBHOOK_HOST"] = [string]$Config.hermes_whatsapp_cloud_webhook_host
        $values["WHATSAPP_CLOUD_WEBHOOK_PORT"] = [string]$Config.hermes_whatsapp_cloud_webhook_port
        $values["WHATSAPP_CLOUD_WEBHOOK_PATH"] = [string]$Config.hermes_whatsapp_cloud_webhook_path
        $values["WHATSAPP_CLOUD_API_VERSION"] = [string]$Config.hermes_whatsapp_cloud_api_version
    }

    return $values
}

function Read-HermesEnvFileValues {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $values = [ordered]@{}
    $envPath = Get-HermesEnvPath -Config $Config

    if (-not (Test-Path -LiteralPath $envPath)) {
        return $values
    }

    foreach ($line in @(Get-Content -LiteralPath $envPath)) {
        $trimmed = ([string]$line).Trim()

        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#") -or $trimmed -notmatch "^[A-Za-z_][A-Za-z0-9_]*=") {
            continue
        }

        $parts = $trimmed -split "=", 2
        $values[[string]$parts[0]] = if ($parts.Count -gt 1) { [string]$parts[1] } else { "" }
    }

    return $values
}

function Get-HermesEnvValue {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowEmptyString()]
        [string]$ConfiguredValue = ""
    )

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredValue)) {
        return $ConfiguredValue
    }

    $existingValues = Read-HermesEnvFileValues -Config $Config

    if ($existingValues.Contains($Name)) {
        return [string]$existingValues[$Name]
    }

    return ""
}

function Set-HermesProcessEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    foreach ($entry in (Get-HermesEnvironmentValues -Config $Config).GetEnumerator()) {
        Set-Item -Path ("Env:" + [string]$entry.Key) -Value ([string]$entry.Value)
    }

    $hermesPythonwPath = Get-HermesPythonwCommandPath
    if (-not [string]::IsNullOrWhiteSpace($hermesPythonwPath)) {
        Set-Item -Path "Env:VIRTUAL_ENV" -Value (Split-Path -Parent (Split-Path -Parent $hermesPythonwPath))
    }
}

function ConvertTo-HermesEnvLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowEmptyString()]
        [string]$Value
    )

    $safeValue = $Value.Replace("`r", "").Replace("`n", "")
    return "$Name=$safeValue"
}

function Set-HermesManagedGatewayPlatformConfig {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $content = [System.IO.File]::ReadAllText($Path)
    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $startMarker = "  # Homelab AI managed gateway platforms"
    $endMarker = "  # End Homelab AI managed gateway platforms"
    $escapedStart = [regex]::Escape($startMarker)
    $escapedEnd = [regex]::Escape($endMarker)
    $managedPattern = "(?ms)^$escapedStart\r?\n.*?^$escapedEnd\r?\n?"

    $managedLines = @()
    if ($Config.hermes_photon_enabled) {
        $managedLines = @(
            $startMarker,
            "  platforms:",
            "    photon:",
            "      enabled: true",
            "      require_mention: $($Config.hermes_photon_require_mention.ToString().ToLowerInvariant())",
            $endMarker
        )
    }

    $managedBlock = if ($managedLines.Count -gt 0) {
        ($managedLines -join $newline) + $newline
    } else {
        ""
    }

    if ([regex]::IsMatch($content, $managedPattern)) {
        $updated = [regex]::Replace($content, $managedPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $managedBlock })
    } elseif ($managedBlock) {
        $updated = [regex]::Replace($content, "(?m)^gateway:\r?\n", ("gateway:" + $newline + $managedBlock), 1)
    } else {
        $updated = $content
    }

    if ($updated -ne $content) {
        [System.IO.File]::WriteAllText($Path, $updated, [System.Text.UTF8Encoding]::new($false))
    }
}

function Set-HermesManagedWebConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $content = [System.IO.File]::ReadAllText($Path)
    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $webBlock = @(
        "web:",
        "  backend: parallel",
        "  search_backend: parallel",
        "  extract_backend: parallel",
        "  use_gateway: true"
    ) -join $newline
    $webBlock += $newline

    if ($content -match "(?m)^web:\r?\n") {
        $updated = [regex]::Replace($content, "(?m)^web:\r?\n(?:^[ \t].*\r?\n)*", $webBlock, 1)
    } else {
        $updated = $webBlock + $content
    }

    if ($updated -ne $content) {
        [System.IO.File]::WriteAllText($Path, $updated, [System.Text.UTF8Encoding]::new($false))
    }
}

function Sync-HermesRuntimeConfig {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $hermesHomePath = Ensure-HermesHome -Config $Config
    $envPath = Get-HermesEnvPath -Config $Config
    $configPath = Get-HermesConfigPath -Config $Config
    $mergedEnvValues = Read-HermesEnvFileValues -Config $Config

    foreach ($entry in (Get-HermesEnvironmentValues -Config $Config).GetEnumerator()) {
        if ([string]$entry.Key -eq "HERMES_HOME") {
            continue
        }

        $mergedEnvValues[[string]$entry.Key] = [string]$entry.Value
    }

    $envLines = @(
        "# Generated by Homelab AI. Edit config/homelab.local.json or use Hermes setup commands for platform-owned credentials."
    )

    foreach ($entry in $mergedEnvValues.GetEnumerator()) {
        $envLines += (ConvertTo-HermesEnvLine -Name ([string]$entry.Key) -Value ([string]$entry.Value))
    }

    [System.IO.File]::WriteAllText($envPath, (($envLines -join [Environment]::NewLine) + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))

    $configLines = @(
        "# Generated by Homelab AI. Non-secret Hermes preferences live here.",
        "model: $($Config.hermes_model)",
        "group_sessions_per_user: true",
        "display:",
        "  tool_progress: new",
        "  background_process_notifications: result",
        "web:",
        "  backend: parallel",
        "  search_backend: parallel",
        "  extract_backend: parallel",
        "  use_gateway: true",
        "gateway:",
        "  # Homelab AI managed gateway platforms",
        "  platforms:",
        "    photon:",
        "      enabled: $($Config.hermes_photon_enabled.ToString().ToLowerInvariant())",
        "      require_mention: $($Config.hermes_photon_require_mention.ToString().ToLowerInvariant())",
        "  # End Homelab AI managed gateway platforms",
        "discord:",
        "  require_mention: $($Config.hermes_discord_require_mention.ToString().ToLowerInvariant())",
        "  auto_thread: true",
        "  history_backfill: true",
        "  free_response_channels: `"$($Config.hermes_discord_free_response_channels)`"",
        "platforms:"
    )

    if ($Config.hermes_photon_enabled) {
        $configLines += @(
            "  photon:",
            "    enabled: true",
            "    require_mention: $($Config.hermes_photon_require_mention.ToString().ToLowerInvariant())"
        )
    }

    if (-not (Test-Path -LiteralPath $configPath)) {
        [System.IO.File]::WriteAllText($configPath, (($configLines -join [Environment]::NewLine) + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
    } else {
        Set-HermesManagedWebConfig -Path $configPath
        Set-HermesManagedGatewayPlatformConfig -Config $Config -Path $configPath
    }

    return [ordered]@{
        home        = $hermesHomePath
        env_path    = $envPath
        config_path = $configPath
    }
}

function Get-HermesMissingConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $missing = New-Object System.Collections.Generic.List[string]

    if (-not $Config.hermes_enabled) {
        return @()
    }

    if ($Config.hermes_api_server_enabled -and [string]::IsNullOrWhiteSpace([string]$Config.hermes_api_server_key)) {
        $missing.Add("hermes.api_server_key") | Out-Null
    }

    if ($Config.hermes_discord_enabled) {
        if ([string]::IsNullOrWhiteSpace([string]$Config.hermes_discord_bot_token)) {
            $missing.Add("hermes.discord.bot_token") | Out-Null
        }

        if (
            [string]::IsNullOrWhiteSpace([string]$Config.hermes_discord_allowed_users) -and
            [string]::IsNullOrWhiteSpace([string]$Config.hermes_discord_allowed_roles)
        ) {
            $missing.Add("hermes.discord.allowed_users or hermes.discord.allowed_roles") | Out-Null
        }
    }

    if ($Config.hermes_email_enabled) {
        foreach ($name in @("address", "password", "imap_host", "smtp_host", "allowed_users")) {
            $propertyName = "hermes_email_$name"

            if ([string]::IsNullOrWhiteSpace([string]$Config.$propertyName)) {
                $missing.Add("hermes.email.$name") | Out-Null
            }
        }
    }

    if ($Config.hermes_whatsapp_cloud_enabled) {
        foreach ($name in @("phone_number_id", "access_token", "app_secret", "verify_token", "allowed_users")) {
            $propertyName = "hermes_whatsapp_cloud_$name"

            if ([string]::IsNullOrWhiteSpace([string]$Config.$propertyName)) {
                $missing.Add("hermes.whatsapp_cloud.$name") | Out-Null
            }
        }
    }

    if ($Config.hermes_photon_enabled) {
        $photonProjectId = Get-HermesEnvValue -Config $Config -Name "PHOTON_PROJECT_ID" -ConfiguredValue ([string]$Config.hermes_photon_project_id)
        $photonProjectSecret = Get-HermesEnvValue -Config $Config -Name "PHOTON_PROJECT_SECRET" -ConfiguredValue ([string]$Config.hermes_photon_project_secret)

        if ([string]::IsNullOrWhiteSpace($photonProjectId)) {
            $missing.Add("hermes.photon.project_id or PHOTON_PROJECT_ID from hermes photon setup") | Out-Null
        }

        if ([string]::IsNullOrWhiteSpace($photonProjectSecret)) {
            $missing.Add("hermes.photon.project_secret or PHOTON_PROJECT_SECRET from hermes photon setup") | Out-Null
        }
    }

    return $missing.ToArray()
}

function Assert-HermesConfigured {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    if (-not $Config.hermes_enabled) {
        return
    }

    if (-not (Test-HermesCliAvailable)) {
        throw "Hermes is enabled but the 'hermes' CLI was not found. Install Hermes Agent first."
    }

    $missing = @(Get-HermesMissingConfiguration -Config $Config)

    if ($missing.Count -gt 0) {
        throw "Hermes is enabled but local configuration is incomplete: $($missing -join ', ')."
    }
}

function Get-HermesGatewayLockInfo {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $statePath = Get-HermesGatewayStatePath -Config $Config
    $state = Read-JsonFile -Path $statePath -AllowMissing

    if (
        $null -ne $state -and
        [string]$state.gateway_state -eq "running" -and
        $null -ne $state.pid -and
        (Test-ProcessAlive -Id ([int]$state.pid))
    ) {
        $runtime = Read-JsonFile -Path (Get-HermesGatewayRuntimePath -Config $Config) -AllowMissing

        return [pscustomobject]@{
            pid        = [int]$state.pid
            started_at = if ($null -ne $runtime) { [string]$runtime.started_at } else { $null }
            home       = [string]$Config.hermes_home
            model      = [string]$Config.hermes_model
        }
    }

    $runtimePath = Get-HermesGatewayRuntimePath -Config $Config
    $runtime = Read-JsonFile -Path $runtimePath -AllowMissing

    if ($null -eq $runtime) {
        return $null
    }

    if (-not (Test-ProcessAlive -Id ([int]$runtime.pid))) {
        Remove-FileIfPresent -Path $runtimePath
        Remove-FileIfPresent -Path (Get-HermesGatewayPidPath -Config $Config)
        return $null
    }

    return $runtime
}

function Test-HermesGatewayRunning {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return $null -ne (Get-HermesGatewayLockInfo -Config $Config)
}

function Start-HermesGateway {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    if (-not $Config.hermes_enabled -or -not $Config.hermes_gateway_enabled) {
        Write-Log "Hermes gateway is disabled." "INFO"
        return
    }

    Assert-HermesConfigured -Config $Config
    [void](Sync-HermesRuntimeConfig -Config $Config)

    if (Test-HermesGatewayRunning -Config $Config) {
        Write-Log "Hermes gateway is already running." "OK"
        return
    }

    $gatewayPath = Get-HermesPythonwCommandPath
    $gatewayArguments = @("-m", "hermes_cli.main", "gateway", "--accept-hooks", "run")

    if ([string]::IsNullOrWhiteSpace($gatewayPath)) {
        $gatewayPath = Get-HermesCommandPath
        $gatewayArguments = @("gateway", "--accept-hooks", "run")
    }

    Set-HermesProcessEnvironment -Config $Config
    $env:HERMES_GATEWAY_DETACHED = "1"
    $env:PYTHONIOENCODING = "utf-8"
    $process = Start-Process -FilePath $gatewayPath -ArgumentList $gatewayArguments -WorkingDirectory $script:HomelabRoot -WindowStyle Hidden -PassThru
    $gatewayPid = $process.Id

    foreach ($attempt in 1..20) {
        Start-Sleep -Milliseconds 500
        $state = Read-JsonFile -Path (Get-HermesGatewayStatePath -Config $Config) -AllowMissing

        if (
            $null -ne $state -and
            [string]$state.gateway_state -eq "running" -and
            $null -ne $state.pid -and
            (Test-ProcessAlive -Id ([int]$state.pid))
        ) {
            $gatewayPid = [int]$state.pid
            break
        }
    }

    [System.IO.File]::WriteAllText((Get-HermesGatewayPidPath -Config $Config), "$gatewayPid`n", [System.Text.UTF8Encoding]::new($false))
    Write-JsonFile -Path (Get-HermesGatewayRuntimePath -Config $Config) -Value ([ordered]@{
        pid        = $gatewayPid
        started_at = (Get-Date).ToString("o")
        home       = [string]$Config.hermes_home
        model      = [string]$Config.hermes_model
    })

    Write-Log "Hermes gateway started with HERMES_HOME=$($Config.hermes_home)." "OK"
}

function Stop-HermesGateway {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $lock = Get-HermesGatewayLockInfo -Config $Config

    if ($null -eq $lock) {
        Write-Log "Hermes gateway is not running." "OK"
        return
    }

    $hermesPath = Get-HermesCommandPath
    if (-not [string]::IsNullOrWhiteSpace($hermesPath)) {
        Set-HermesProcessEnvironment -Config $Config
        $result = Invoke-NativeCommandWithTimeout -FilePath $hermesPath -Arguments @("gateway", "stop") -TimeoutMs 30000

        if (-not $result.TimedOut -and $result.ExitCode -eq 0) {
            Remove-FileIfPresent -Path (Get-HermesGatewayRuntimePath -Config $Config)
            Remove-FileIfPresent -Path (Get-HermesGatewayPidPath -Config $Config)
            Write-Log "Hermes gateway stopped." "OK"
            return
        }
    }

    Stop-Process -Id ([int]$lock.pid) -Force
    Remove-FileIfPresent -Path (Get-HermesGatewayRuntimePath -Config $Config)
    Remove-FileIfPresent -Path (Get-HermesGatewayPidPath -Config $Config)
    Write-Log "Hermes gateway stopped." "OK"
}

function Restart-HermesGateway {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    Stop-HermesGateway -Config $Config
    Start-HermesGateway -Config $Config
}

function Get-HermesApiServerUrl {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return "http://$($Config.hermes_api_server_host):$($Config.hermes_api_server_port)"
}

function Get-HermesLogTail {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [int]$Tail = 40
    )

    $logPath = Join-Path (Join-Path (Ensure-HermesHome -Config $Config) "logs") "gateway.log"

    if (-not (Test-Path -LiteralPath $logPath)) {
        return @()
    }

    return @(Get-Content -LiteralPath $logPath -Tail $Tail)
}

function Get-HermesPlatformStatus {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return [ordered]@{
        discord = [ordered]@{
            enabled    = [bool]$Config.hermes_discord_enabled
            configured = (
                -not [string]::IsNullOrWhiteSpace([string]$Config.hermes_discord_bot_token) -and
                (
                    -not [string]::IsNullOrWhiteSpace([string]$Config.hermes_discord_allowed_users) -or
                    -not [string]::IsNullOrWhiteSpace([string]$Config.hermes_discord_allowed_roles)
                )
            )
        }
        photon = [ordered]@{
            enabled    = [bool]$Config.hermes_photon_enabled
            configured = (
                -not [string]::IsNullOrWhiteSpace((Get-HermesEnvValue -Config $Config -Name "PHOTON_PROJECT_ID" -ConfiguredValue ([string]$Config.hermes_photon_project_id))) -and
                -not [string]::IsNullOrWhiteSpace((Get-HermesEnvValue -Config $Config -Name "PHOTON_PROJECT_SECRET" -ConfiguredValue ([string]$Config.hermes_photon_project_secret)))
            )
        }
    }
}

function Get-HermesSummary {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $lock = Get-HermesGatewayLockInfo -Config $Config
    $apiUrl = Get-HermesApiServerUrl -Config $Config
    $apiHealth = if ($Config.hermes_enabled -and $Config.hermes_api_server_enabled) {
        Test-HttpEndpoint -Url "$apiUrl/health" -TimeoutSeconds 2
    }
    else {
        $null
    }

    $cliAvailable = Test-HermesCliAvailable
    $version = $null

    if ($cliAvailable) {
        try {
            $version = Get-HermesVersion -Config $Config
        }
        catch {
            $version = $null
        }
    }

    return [ordered]@{
        enabled       = [bool]$Config.hermes_enabled
        cli_available = [bool]$cliAvailable
        version       = $version
        home          = [string]$Config.hermes_home
        model         = [string]$Config.hermes_model
        missing_config = @(Get-HermesMissingConfiguration -Config $Config)
        gateway       = [ordered]@{
            enabled    = [bool]$Config.hermes_gateway_enabled
            running    = ($null -ne $lock)
            pid        = if ($null -ne $lock) { [int]$lock.pid } else { $null }
            started_at = if ($null -ne $lock) { [string]$lock.started_at } else { $null }
        }
        api_server    = [ordered]@{
            enabled   = [bool]$Config.hermes_api_server_enabled
            local_url = $apiUrl
            reachable = if ($null -ne $apiHealth) { [bool]$apiHealth.Ok } else { $false }
            model_name = [string]$Config.hermes_api_server_model_name
        }
        platforms     = Get-HermesPlatformStatus -Config $Config
        log_tail      = @(Get-HermesLogTail -Config $Config -Tail 40)
    }
}
